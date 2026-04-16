# Manifest + Secrets UI — Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `.321.yml` manifests into the deploy config pipeline and add a secrets management UI so operators can see which env vars a service needs and set them from the dashboard.

**Architecture:** `Deploy::Manifest` (already implemented) loads `.321.yml` from service repos. `Deploy::Config::_resolve` merges manifest fields into the resolved service hash at read time — deploy YAML wins on conflict. A new `Deploy::Secrets` module manages `secrets/<name>.env` files with atomic writes and audit logging. Three new API endpoints expose diff/set/delete. The dashboard gets a secrets badge per tile; the service detail page gets a secrets form panel. `deploy()` blocks when required secrets are missing.

**Tech Stack:** Perl 5.42, Mojolicious::Lite, YAML::XS, Path::Tiny, Test::Mojo. No new runtime dependencies.

---

## File Structure

**Already implemented (do not touch):**
- `lib/Deploy/Manifest.pm` — `.321.yml` loader + validator (commit `c996b0d`)
- `t/10-manifest.t` — 6 subtests, all passing

**New files:**
- `lib/Deploy/Secrets.pm` — env file read/diff/write + audit log (Task 3)
- `t/11-secrets.t` — secrets module unit tests (Task 3)
- `t/12-config-manifest-merge.t` — config merge integration tests (Task 2)
- `t/13-secrets-endpoints.t` — endpoint tests (Task 4)
- `t/16-deploy-blocks-on-missing-secrets.t` — deploy precondition test (Task 7)

**Modified files:**
- `lib/Deploy/Config.pm` — merge manifest into `_resolve()`, add `$ENV{APP_HOME}` override (Task 2)
- `lib/Deploy/Service.pm` — add secrets precondition check in `deploy()` (Task 7)
- `lib/Deploy/Command/install.pm` — fail fast if repo missing `.321.yml` (Task 8)
- `bin/321.pl` — secrets endpoints (Task 4), `/services` response enrichment (Task 5), dashboard badge JS/CSS (Task 5), service detail secrets panel JS/CSS (Task 6)
- `services/321.web.yml` — remove `bin`/`perlbrew` (now from manifest) (Task 9)
- `CLAUDE.md` — document manifest contract (Task 10)

**Committed but untracked:**
- `.321.yml` — exists at repo root, needs `git add` (Task 1)

---

## Task 1: Commit the `.321.yml` dogfood manifest

The file exists at repo root but is untracked (`git status` shows `?? .321.yml`).

**Files:**
- Stage: `.321.yml`

- [ ] **Step 1: Verify the manifest parses**

```bash
perl -Ilib -MDeploy::Manifest -MData::Dumper -E 'print Dumper(Deploy::Manifest->load("."))'
```
Expected: hash with `name => '321.web'`, `entry => 'bin/321.pl'`, `runner => 'hypnotoad'`, `perl => 'perl-5.42.0'`.

- [ ] **Step 2: Commit and push**

```bash
git add .321.yml
git commit -m "Add .321.yml manifest for 321.web (dogfood)"
git push
```

---

## Task 2: Merge manifest into resolved service config

**Files:**
- Modify: `lib/Deploy/Config.pm:8` (app_home default), `lib/Deploy/Config.pm:94-115` (`_resolve` method)
- Create: `t/12-config-manifest-merge.t`

`_resolve()` currently builds the resolved hash entirely from deploy YAML. After this task, it also loads the manifest from the service repo (if present) and merges `entry` -> `bin`, `perl` -> `perlbrew`, `runner`, `health`, `env_required`, `env_optional`. Deploy-YAML values win on conflict.

- [ ] **Step 1: Write failing test**

Create `t/12-config-manifest-merge.t`:

```perl
use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;

my $home = tempdir(CLEANUP => 1);
path($home, 'services')->mkpath;
path($home, 'secrets')->mkpath;

my $repo = tempdir(CLEANUP => 1);
path($repo, '.321.yml')->spew_utf8(<<'YAML');
name: demo.web
entry: bin/demo.pl
runner: hypnotoad
perl: perl-5.42.1
health: /health
env_required:
  API_KEY: "upstream API"
env_optional:
  LOG_LEVEL:
    default: info
YAML

path($home, 'services', 'demo.web.yml')->spew_utf8(<<"YAML");
name: demo.web
repo: $repo
branch: master
targets:
  live:
    host: demo.do
    port: 9400
YAML

my $c = Deploy::Config->new(app_home => $home, target => 'live');
my $svc = $c->service('demo.web');

is $svc->{bin},      'bin/demo.pl',    'bin from manifest entry';
is $svc->{runner},   'hypnotoad',      'runner from manifest';
is $svc->{perlbrew}, 'perl-5.42.1',    'perl from manifest';
is $svc->{port},     9400,             'port from deploy yaml';
is $svc->{host},     'demo.do',        'host from deploy yaml';
is $svc->{health},   '/health',        'health from manifest';
is_deeply $svc->{env_required}, { API_KEY => 'upstream API' };
is $svc->{env_optional}{LOG_LEVEL}{default}, 'info';

# Deploy YAML override wins
path($home, 'services', 'demo.web.yml')->spew_utf8(<<"YAML");
name: demo.web
repo: $repo
bin: bin/override.pl
targets:
  live:
    host: demo.do
    port: 9400
YAML
$c->reload;
is $c->service('demo.web')->{bin}, 'bin/override.pl', 'deploy yaml overrides manifest';

done_testing;
```

- [ ] **Step 2: Run test, confirm failure**

```bash
prove -lv t/12-config-manifest-merge.t
```
Expected: FAIL — `bin` is undef when deploy YAML omits it, `env_required` not in result hash.

- [ ] **Step 3: Add `use Deploy::Manifest` to Config.pm**

In `lib/Deploy/Config.pm`, after the existing `use Path::Tiny` (line 5), add:

```perl
use Deploy::Manifest;
```

- [ ] **Step 4: Make `app_home` accept `$ENV{APP_HOME}` override**

In `lib/Deploy/Config.pm`, replace line 8:

```perl
# Before (line 8):
has 'app_home'    => sub { curfile->dirname->dirname->dirname };

# After:
has 'app_home'    => sub { $ENV{APP_HOME} // curfile->dirname->dirname->dirname };
```

- [ ] **Step 5: Replace `_resolve` method**

In `lib/Deploy/Config.pm`, replace lines 94–115 (the entire `_resolve` sub) with:

```perl
sub _resolve ($self, $name, $raw) {
    my $target_name = $self->target;
    my $targets = $raw->{targets} // {};
    my $target  = $targets->{$target_name} // $targets->{live} // {};

    my $manifest = $raw->{repo} && -d $raw->{repo}
        ? Deploy::Manifest->load($raw->{repo})
        : undef;

    my $bin      = $raw->{bin}      // ($manifest ? $manifest->{entry}  : undef);
    my $perlbrew = $raw->{perlbrew} // ($manifest ? $manifest->{perl}   : undef);
    my $runner   = $target->{runner} // ($manifest ? $manifest->{runner} : 'hypnotoad');
    my $health   = ($manifest ? $manifest->{health} : '/health');

    return {
        name         => $name,
        repo         => $raw->{repo},
        branch       => $raw->{branch} // 'master',
        bin          => $bin,
        mode         => $runner eq 'morbo' ? 'development' : 'production',
        runner       => $runner,
        port         => $target->{port},
        logs         => $target->{logs} // {},
        env          => $target->{env} // {},
        host         => $target->{host} // 'localhost',
        health       => $health,
        apt_deps     => $raw->{apt_deps} // [],
        env_required => $manifest ? $manifest->{env_required} : {},
        env_optional => $manifest ? $manifest->{env_optional} : {},
        ($target->{docs}  ? (docs  => $target->{docs})  : ()),
        ($target->{admin} ? (admin => $target->{admin}) : ()),
        ($perlbrew        ? (perlbrew => $perlbrew)      : ()),
    };
}
```

- [ ] **Step 6: Run test, confirm pass**

```bash
prove -lv t/12-config-manifest-merge.t
```

- [ ] **Step 7: Run full suite**

```bash
prove -lr t
```
Expected: all existing tests still pass.

- [ ] **Step 8: Commit and push**

```bash
git add lib/Deploy/Config.pm t/12-config-manifest-merge.t
git commit -m "Merge .321.yml manifest into resolved service config"
git push
```

---

## Task 3: Secrets diff + audit log module

**Files:**
- Create: `lib/Deploy/Secrets.pm`
- Create: `t/11-secrets.t`

`Deploy::Secrets` reads/writes `secrets/<name>.env` files (shell-style `KEY=value`), diffs against manifest `env_required`/`env_optional`, and appends to a per-service audit log (`secrets/<name>.audit.log`) recording key name + actor, never values. Writes are atomic (temp + rename, `chmod 0600`).

- [ ] **Step 1: Write failing tests**

Create `t/11-secrets.t`:

```perl
use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Secrets;

my $home = tempdir(CLEANUP => 1);
path($home, 'secrets')->mkpath;

my $s = Deploy::Secrets->new(app_home => $home);

subtest 'diff: no file, nothing required' => sub {
    my $d = $s->diff('svc', { required => {}, optional => {} });
    is_deeply $d->{missing}, [];
    is_deeply $d->{present}, [];
};

subtest 'diff: missing required key' => sub {
    my $d = $s->diff('svc', {
        required => { API_KEY => 'x', DB_URL => 'y' },
        optional => {},
    });
    is_deeply [sort @{$d->{missing}}], [qw(API_KEY DB_URL)];
};

subtest 'set + diff: required present' => sub {
    $s->set('svc', 'API_KEY', 'abc123', actor => 'tester');
    $s->set('svc', 'DB_URL',  'postgres://', actor => 'tester');
    my $d = $s->diff('svc', {
        required => { API_KEY => 'x', DB_URL => 'y' },
        optional => { LOG_LEVEL => { default => 'info' } },
    });
    is_deeply $d->{missing}, [], 'nothing missing';
    is_deeply [sort @{$d->{present}}], [qw(API_KEY DB_URL)];
    is_deeply $d->{optional_set}, [], 'optional key not set';
};

subtest 'atomic write: permissions 0600' => sub {
    my $file = path($home, 'secrets', 'svc.env');
    my $mode = (stat $file)[2] & 07777;
    is $mode, 0600, 'env file is 0600';
};

subtest 'audit log: append on set' => sub {
    my $log = path($home, 'secrets', 'svc.audit.log');
    ok $log->exists, 'audit log exists';
    my @lines = $log->lines_utf8({ chomp => 1 });
    is scalar @lines, 2, 'one line per set';
    like $lines[0], qr/^\S+ tester set API_KEY$/, 'format: ts actor action key';
    unlike $lines[0], qr/abc123/, 'value never in log';
};

subtest 'delete + diff' => sub {
    $s->delete('svc', 'DB_URL', actor => 'tester');
    my $d = $s->diff('svc', {
        required => { API_KEY => 'x', DB_URL => 'y' },
        optional => {},
    });
    is_deeply $d->{missing}, ['DB_URL'];
    my @lines = path($home, 'secrets', 'svc.audit.log')->lines_utf8({ chomp => 1 });
    like $lines[-1], qr/^\S+ tester delete DB_URL$/;
};

subtest 'reject invalid key name' => sub {
    my $err = eval { $s->set('svc', 'lowercase', 'x', actor => 't'); 0 } || $@;
    like $err, qr/invalid key/;
};

subtest 'reject value with newline' => sub {
    my $err = eval { $s->set('svc', 'GOOD_KEY', "a\nb", actor => 't'); 0 } || $@;
    like $err, qr/newline not allowed/;
};

done_testing;
```

- [ ] **Step 2: Run tests, confirm all fail**

```bash
prove -lv t/11-secrets.t
```
Expected: "Can't locate Deploy/Secrets.pm".

- [ ] **Step 3: Implement `Deploy::Secrets`**

Create `lib/Deploy/Secrets.pm`:

```perl
package Deploy::Secrets;

use Mojo::Base -base, -signatures;
use Path::Tiny qw(path);
use POSIX qw(strftime);

has 'app_home';

my $KEY_RE = qr/^[A-Z_][A-Z0-9_]*$/;

sub _env_file ($self, $name) {
    return path($self->app_home, 'secrets', "$name.env");
}

sub _audit_file ($self, $name) {
    return path($self->app_home, 'secrets', "$name.audit.log");
}

sub _read ($self, $name) {
    my $file = $self->_env_file($name);
    return {} unless $file->exists;
    my %env;
    for my $line ($file->lines_utf8({ chomp => 1 })) {
        next if $line =~ /^\s*(#|$)/;
        if ($line =~ /^([A-Z_][A-Z0-9_]*)=(.*)$/) {
            $env{$1} = $2;
        }
    }
    return \%env;
}

sub _write_atomic ($self, $name, $env) {
    my $file = $self->_env_file($name);
    $file->parent->mkpath;
    my $tmp  = path($file->parent, "$name.env.tmp.$$");
    my @lines = map { "$_=$env->{$_}" } sort keys %$env;
    $tmp->spew_utf8(join("\n", @lines) . (@lines ? "\n" : ''));
    chmod 0600, "$tmp" or die "chmod: $!";
    rename "$tmp", "$file" or die "rename: $!";
}

sub _audit ($self, $name, $actor, $action, $key) {
    my $log = $self->_audit_file($name);
    my $ts  = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
    $log->append_utf8("$ts $actor $action $key\n");
    chmod 0600, "$log";
}

sub diff ($self, $name, $manifest_env) {
    my $env      = $self->_read($name);
    my %required = %{ $manifest_env->{required} // {} };
    my %optional = %{ $manifest_env->{optional} // {} };

    my @missing = grep { !exists $env->{$_} } sort keys %required;
    my @present = grep {  exists $env->{$_} } sort keys %required;
    my @opt_set = grep {  exists $env->{$_} } sort keys %optional;

    return { missing => \@missing, present => \@present, optional_set => \@opt_set };
}

sub set ($self, $name, $key, $value, %opts) {
    die "invalid key '$key'\n" unless $key =~ $KEY_RE;
    die "newline not allowed in value\n" if $value =~ /[\r\n]/;
    my $actor = $opts{actor} // 'unknown';

    my $env = $self->_read($name);
    $env->{$key} = $value;
    $self->_write_atomic($name, $env);
    $self->_audit($name, $actor, 'set', $key);
}

sub delete ($self, $name, $key, %opts) {
    die "invalid key '$key'\n" unless $key =~ $KEY_RE;
    my $actor = $opts{actor} // 'unknown';

    my $env = $self->_read($name);
    return unless exists $env->{$key};
    delete $env->{$key};
    $self->_write_atomic($name, $env);
    $self->_audit($name, $actor, 'delete', $key);
}

1;
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
prove -lv t/11-secrets.t
```

- [ ] **Step 5: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 6: Commit and push**

```bash
git add lib/Deploy/Secrets.pm t/11-secrets.t
git commit -m "Add Deploy::Secrets with atomic writes and audit log"
git push
```

---

## Task 4: Secrets endpoints

**Files:**
- Modify: `bin/321.pl:20` (add `use Deploy::Secrets`), `bin/321.pl:45` (instantiate `$secrets_mgr`), `bin/321.pl:59` (add helper), `bin/321.pl:393` (insert routes after nginx/certbot block)
- Create: `t/13-secrets-endpoints.t`

Three new routes: `GET /service/#name/secrets` (diff), `POST /service/#name/secrets` (set key), `POST /service/#name/secrets/delete` (delete key). Values are never returned in responses.

- [ ] **Step 1: Write failing endpoint tests**

Create `t/13-secrets-endpoints.t`:

```perl
use strict;
use warnings;
use Test::More;
use Test::Mojo;
use MIME::Base64;
use Path::Tiny qw(tempdir path);

my $home = tempdir(CLEANUP => 1);
path($home, 'services')->mkpath;
path($home, 'secrets')->mkpath;

my $repo = tempdir(CLEANUP => 1);
path($repo, '.321.yml')->spew_utf8(<<'YAML');
name: demo.web
entry: bin/demo.pl
runner: hypnotoad
env_required:
  API_KEY: required
env_optional:
  LOG_LEVEL:
    default: info
YAML

path($home, 'services', 'demo.web.yml')->spew_utf8(<<"YAML");
name: demo.web
repo: $repo
targets:
  live:
    host: demo.do
    port: 9400
YAML

$ENV{MOJO_MODE} = 'production';
$ENV{APP_HOME}  = $home;

my $t = Test::Mojo->new(Mojo::File->new('bin/321.pl'));
my $auth = { Authorization => 'Basic ' . encode_base64('321:kaizen', '') };

# GET secrets: missing key
$t->get_ok('/service/demo.web/secrets', $auth)
  ->status_is(200)
  ->json_is('/status' => 'success')
  ->json_is('/data/missing/0' => 'API_KEY')
  ->json_is('/data/present' => []);

# POST set key
$t->post_ok('/service/demo.web/secrets' => $auth => json => { key => 'API_KEY', value => 'abc' })
  ->status_is(200)
  ->json_is('/status' => 'success');

# GET again: now present
$t->get_ok('/service/demo.web/secrets', $auth)
  ->json_is('/data/missing' => [])
  ->json_is('/data/present/0' => 'API_KEY');

# Reject bad key
$t->post_ok('/service/demo.web/secrets' => $auth => json => { key => 'lowercase', value => 'x' })
  ->status_is(200)
  ->json_is('/status' => 'error')
  ->json_like('/message' => qr/invalid key/);

# DELETE key
$t->post_ok('/service/demo.web/secrets/delete' => $auth => json => { key => 'API_KEY' })
  ->status_is(200)
  ->json_is('/status' => 'success');

# Confirm deleted
$t->get_ok('/service/demo.web/secrets', $auth)
  ->json_is('/data/missing/0' => 'API_KEY');

done_testing;
```

- [ ] **Step 2: Run test, confirm failure**

```bash
prove -lv t/13-secrets-endpoints.t
```
Expected: 404 on the GET (route doesn't exist).

- [ ] **Step 3: Add `use Deploy::Secrets` to `bin/321.pl`**

In `bin/321.pl`, after `use Deploy::Nginx;` (line 20), add:

```perl
use Deploy::Secrets;
```

- [ ] **Step 4: Instantiate `$secrets_mgr`**

In `bin/321.pl`, after the `$nginx_mgr` instantiation (after line 45), add:

```perl
my $secrets_mgr = Deploy::Secrets->new(app_home => $app_home);
```

- [ ] **Step 5: Add helper**

In `bin/321.pl`, after `helper nginx_mgr => sub { $nginx_mgr };` (line 59), add:

```perl
helper secrets_mgr => sub { $secrets_mgr };
```

- [ ] **Step 6: Add three routes**

In `bin/321.pl`, after the `post '/service/#name/nginx/certbot'` handler (after line 393, before the `# --- Target switch ---` comment), add:

```perl
# --- Secrets ---

get '/service/#name/secrets' => sub ($c) {
    my $name = $c->param('name');
    return unless $c->validate_service($name);
    my $svc = $config->service($name);

    my $diff = $secrets_mgr->diff($name, {
        required => $svc->{env_required} // {},
        optional => $svc->{env_optional} // {},
    });
    $c->json_response(success => 'ok', {
        required     => [ sort keys %{ $svc->{env_required} // {} } ],
        optional     => $svc->{env_optional} // {},
        missing      => $diff->{missing},
        present      => $diff->{present},
        optional_set => $diff->{optional_set},
    });
};

post '/service/#name/secrets' => sub ($c) {
    my $name = $c->param('name');
    return unless $c->validate_service($name);
    my $body = $c->req->json // {};
    my $key  = $body->{key};
    my $val  = $body->{value} // '';
    return $c->json_response(error => 'key required') unless $key;

    my $ok = eval {
        $secrets_mgr->set($name, $key, $val, actor => '321');
        1;
    };
    return $c->json_response(error => ($@ // 'set failed')) unless $ok;
    $c->json_response(success => "set $key for $name");
};

post '/service/#name/secrets/delete' => sub ($c) {
    my $name = $c->param('name');
    return unless $c->validate_service($name);
    my $body = $c->req->json // {};
    my $key  = $body->{key};
    return $c->json_response(error => 'key required') unless $key;

    my $ok = eval {
        $secrets_mgr->delete($name, $key, actor => '321');
        1;
    };
    return $c->json_response(error => ($@ // 'delete failed')) unless $ok;
    $c->json_response(success => "deleted $key from $name");
};
```

- [ ] **Step 7: Run test, confirm pass**

```bash
prove -lv t/13-secrets-endpoints.t
```

- [ ] **Step 8: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 9: Commit and push**

```bash
git add bin/321.pl t/13-secrets-endpoints.t
git commit -m "Add secrets GET/POST/DELETE endpoints with audit logging"
git push
```

---

## Task 5: Dashboard secrets badge

**Files:**
- Modify: `bin/321.pl:138-141` (enrich `/services` response)
- Modify: `bin/321.pl:1941-1969` (badge HTML in `loadServices()`)
- Modify: `bin/321.pl` (CSS in ops layout `<style>` block)

The dashboard is JS-driven — `loadServices()` (line 1921) fetches `/services` and builds tiles client-side. The badge data must come from the API response.

- [ ] **Step 1: Enrich `/services` response with secrets data**

In `bin/321.pl`, replace the `GET /services` handler (lines 138–141):

```perl
# Before (lines 138-141):
get '/services' => sub ($c) {
    my $services = $service_mgr->all_status;
    $c->json_response(success => scalar(@$services) . ' services registered', $services);
};

# After:
get '/services' => sub ($c) {
    my $services = $service_mgr->all_status;
    for my $svc_status (@$services) {
        my $svc = $config->service($svc_status->{name});
        next unless $svc;
        my $diff = $secrets_mgr->diff($svc_status->{name}, {
            required => $svc->{env_required} // {},
            optional => $svc->{env_optional} // {},
        });
        my $req_count = scalar keys %{ $svc->{env_required} // {} };
        $svc_status->{secrets} = {
            required => $req_count,
            present  => $req_count - scalar @{ $diff->{missing} },
            missing  => $diff->{missing},
        };
    }
    $c->json_response(success => scalar(@$services) . ' services registered', $services);
};
```

- [ ] **Step 2: Run existing tests to confirm no regression**

```bash
prove -lr t
```

- [ ] **Step 3: Add badge into tile HTML**

In `bin/321.pl`, in the `loadServices()` function, find the tile's `svc-header` div (around line 1942). Replace:

```javascript
// Before (line 1942-1944):
            <div class="svc-header">
                <div class="svc-name"><a href="/ui/service/${svc.name}">${svc.name}</a>${modeBadge}</div>
                <div class="status-led ${running ? 'on' : 'off'}"></div>
            </div>
```

With:

```javascript
            <div class="svc-header">
                <div class="svc-name"><a href="/ui/service/${svc.name}">${svc.name}</a>${modeBadge}${(() => {
                    const sec = svc.secrets;
                    if (!sec || sec.required === 0) return '';
                    const ok = sec.present === sec.required;
                    return '<span class="badge ' + (ok ? 'badge-ok' : 'badge-warn') + '">secrets: ' + sec.present + '/' + sec.required + '</span>';
                })()}</div>
                <div class="status-led ${running ? 'on' : 'off'}"></div>
            </div>
```

- [ ] **Step 4: Add badge CSS**

In `bin/321.pl`, in the ops layout `<style>` block, find the `.deploy-output` styles (search for `.deploy-output`). After the `.deploy-output` block, add:

```css
.badge { display:inline-block; padding:2px 6px; border-radius:3px; font-size:11px; margin-left:6px; vertical-align:middle; }
.badge-ok   { background:var(--accent); color:var(--bg); }
.badge-warn { background:#c33; color:#fff; }
```

- [ ] **Step 5: Smoke test in browser**

Start the app and visit the dashboard. Confirm:
- Services with `env_required` in their manifest show a `secrets: N/M` badge next to the name.
- Badge is green (`badge-ok`) when all secrets are set, red (`badge-warn`) when any are missing.
- Services without a manifest show no badge.

- [ ] **Step 6: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 7: Commit and push**

```bash
git add bin/321.pl
git commit -m "Show secrets status badge on dashboard tiles"
git push
```

---

## Task 6: Secrets panel on service detail page

**Files:**
- Modify: `bin/321.pl:2111` (add panel HTML in sidebar, after the VISIT button)
- Modify: `bin/321.pl` (add `loadSecrets`/`setSecret`/`deleteSecret` JS functions in `service_detail` script block)
- Modify: `bin/321.pl` (add secrets panel CSS in ops layout `<style>`)

The service detail page is also JS-driven — `loadStatus()` (line 2156) fetches `/service/:name/status`. The secrets panel fetches `/service/:name/secrets` separately.

Existing JS utilities available: `api(path, opts)` (line 1736), `esc(s)` (line 1741), `toast(msg, type)` (line 1727), `SVC` (line 2153).

- [ ] **Step 1: Add secrets panel HTML to sidebar**

In `bin/321.pl`, in the `service_detail` template, after the VISIT button `</a>` tag (line 2110) and before the sidebar's closing `</div>` (line 2112), add:

```html
            <div class="secrets-panel" id="secrets-panel" style="display:none">
                <div class="section-title" style="margin-top:16px">SECRETS</div>
                <div id="secrets-content"></div>
            </div>
```

- [ ] **Step 2: Add JS functions for secrets management**

In the `service_detail` template's `<script>` block (inside `content_for scripts => begin`), after the `loadStatus()` function (after line 2194), add:

```javascript
async function loadSecrets() {
    try {
        const d = await api('/service/' + SVC + '/secrets');
        if (d.status !== 'success') return;
        const panel = document.getElementById('secrets-panel');
        const content = document.getElementById('secrets-content');
        panel.style.display = '';

        let html = '';

        // Required keys
        if (d.data.required && d.data.required.length > 0) {
            html += '<h3 class="secrets-heading">Required</h3>';
            html += '<div class="secrets-list">';
            for (const key of d.data.required) {
                const isSet = d.data.present.includes(key);
                html += '<div class="secret-row" data-key="' + esc(key) + '">'
                    + '<span class="secret-key">' + esc(key) + '</span>'
                    + '<span class="secret-status ' + (isSet ? 'set' : 'missing') + '">' + (isSet ? 'SET' : 'MISSING') + '</span>'
                    + '<input type="password" class="secret-input" placeholder="' + (isSet ? '(keep existing)' : 'set value') + '" autocomplete="off">'
                    + '<button class="btn btn-sm" onclick="setSecret(\'' + esc(key) + '\', this)">Save</button>'
                    + (isSet ? '<button class="btn btn-sm btn-danger" onclick="deleteSecret(\'' + esc(key) + '\')">Del</button>' : '')
                    + '</div>';
            }
            html += '</div>';
        }

        // Optional keys
        const optKeys = Object.keys(d.data.optional || {});
        if (optKeys.length > 0) {
            html += '<details class="secrets-optional"><summary>Optional (' + optKeys.length + ')</summary>';
            html += '<div class="secrets-list">';
            for (const key of optKeys.sort()) {
                const spec = d.data.optional[key] || {};
                const isSet = (d.data.optional_set || []).includes(key);
                const hint = spec.desc ? esc(spec.desc) : '';
                const def = spec['default'] ? ' (default: ' + esc(spec['default']) + ')' : '';
                html += '<div class="secret-row" data-key="' + esc(key) + '">'
                    + '<span class="secret-key">' + esc(key) + '</span>'
                    + '<span class="secret-hint">' + hint + def + '</span>'
                    + '<span class="secret-status ' + (isSet ? 'set' : 'default') + '">' + (isSet ? 'SET' : 'default') + '</span>'
                    + '<input type="password" class="secret-input" placeholder="' + (isSet ? '(keep existing)' : 'set value') + '" autocomplete="off">'
                    + '<button class="btn btn-sm" onclick="setSecret(\'' + esc(key) + '\', this)">Save</button>'
                    + (isSet ? '<button class="btn btn-sm btn-danger" onclick="deleteSecret(\'' + esc(key) + '\')">Del</button>' : '')
                    + '</div>';
            }
            html += '</div></details>';
        }

        if (!html) html = '<div class="secrets-none">No env keys declared in manifest.</div>';
        content.innerHTML = html;
    } catch(e) {
        // silently ignore -- secrets panel just won't show
    }
}

async function setSecret(key, btn) {
    const row = btn.closest('.secret-row');
    const input = row.querySelector('.secret-input');
    const value = input.value;
    if (!value) return;
    btn.disabled = true;
    try {
        const d = await api('/service/' + SVC + '/secrets', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({key: key, value: value})
        });
        if (d.status === 'success') {
            toast(key + ' saved');
            loadSecrets();
        } else {
            toast(d.message || 'Failed', 'error');
        }
    } catch(e) {
        toast('Error: ' + e.message, 'error');
    }
    btn.disabled = false;
    input.value = '';
}

async function deleteSecret(key) {
    if (!confirm('Delete ' + key + '?')) return;
    try {
        const d = await api('/service/' + SVC + '/secrets/delete', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({key: key})
        });
        if (d.status === 'success') {
            toast(key + ' deleted');
            loadSecrets();
        } else {
            toast(d.message || 'Failed', 'error');
        }
    } catch(e) {
        toast('Error: ' + e.message, 'error');
    }
}
```

- [ ] **Step 3: Call `loadSecrets()` on page init**

In the `service_detail` script block, find the end of the `loadStatus()` function (line 2194). Add a `loadSecrets()` call at the very end of `loadStatus`, just before the closing `}`:

```javascript
    // At end of loadStatus(), before closing }:
    loadSecrets();
```

- [ ] **Step 4: Add secrets panel CSS**

In the ops layout `<style>` block, after the `.badge` styles added in Task 5, add:

```css
.secrets-heading { font-size: 12px; margin: 8px 0 4px; color: var(--accent); }
.secrets-list { display: flex; flex-direction: column; gap: 4px; }
.secret-row { display: flex; align-items: center; gap: 6px; padding: 4px 0; font-size: 12px; flex-wrap: wrap; }
.secret-key { font-weight: 600; min-width: 120px; }
.secret-status { font-size: 10px; padding: 1px 5px; border-radius: 2px; }
.secret-status.set { background: var(--accent); color: var(--bg); }
.secret-status.missing { background: #c33; color: #fff; }
.secret-status.default { opacity: 0.5; }
.secret-hint { font-size: 10px; opacity: 0.6; }
.secret-input { background: var(--surface); border: 1px solid var(--border); color: var(--fg); padding: 3px 6px; font-size: 11px; width: 140px; border-radius: 3px; }
.btn-sm { font-size: 10px; padding: 3px 8px; }
.btn-danger { color: #c33; }
.secrets-optional { margin-top: 8px; }
.secrets-optional summary { cursor: pointer; font-size: 11px; opacity: 0.7; }
.secrets-none { font-size: 11px; opacity: 0.5; padding: 8px 0; }
```

- [ ] **Step 5: Smoke test in browser**

Visit `https://dev.321.do/ui/service/321.web`. Confirm:
- Secrets panel appears in the sidebar with MOJO_MODE listed as required.
- Setting a value via the input + Save shows it as SET after save.
- Delete button removes the key and shows MISSING.
- Optional section (DEPLOY_TOKEN) appears in a collapsible `<details>`.
- Values are never pre-filled or visible in the HTML.

- [ ] **Step 6: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 7: Commit and push**

```bash
git add bin/321.pl
git commit -m "Add secrets management panel to service detail page"
git push
```

---

## Task 7: Block deploy when required secrets are missing

**Files:**
- Modify: `lib/Deploy/Service.pm:1` (add `use Deploy::Secrets`), `lib/Deploy/Service.pm:44-46` (add precondition in `deploy`)
- Create: `t/16-deploy-blocks-on-missing-secrets.t`

- [ ] **Step 1: Write failing test**

Create `t/16-deploy-blocks-on-missing-secrets.t`:

```perl
use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;
use Deploy::Service;
use Mojo::Log;

my $home = tempdir(CLEANUP => 1);
path($home, 'services')->mkpath;
path($home, 'secrets')->mkpath;
my $repo = tempdir(CLEANUP => 1);
system("cd $repo && git init -q && git config user.email t\@t && git config user.name t && git commit --allow-empty -m init -q");
path($repo, 'cpanfile')->spew_utf8("requires 'perl', '5.010';\n");
path($repo, '.321.yml')->spew_utf8(
    "name: demo.web\nentry: bin/x.pl\nrunner: hypnotoad\n" .
    "env_required:\n  API_KEY: required\n"
);
path($home, 'services', 'demo.web.yml')->spew_utf8(
    "name: demo.web\nrepo: $repo\ntargets:\n  live:\n    port: 9400\n"
);

my $c = Deploy::Config->new(app_home => $home, target => 'live');
my $s = Deploy::Service->new(
    config => $c,
    log    => Mojo::Log->new(level => 'fatal'),
);

subtest 'deploy blocked when secret missing' => sub {
    my $result = $s->deploy('demo.web', skip_git => 1);
    is $result->{status}, 'error', 'deploy blocked';
    like $result->{message}, qr/missing required secrets?: API_KEY/;
};

subtest 'deploy proceeds when secret present' => sub {
    path($home, 'secrets', 'demo.web.env')->spew_utf8("API_KEY=test123\n");
    chmod 0600, path($home, 'secrets', 'demo.web.env')->stringify;
    my $result = $s->deploy('demo.web', skip_git => 1);
    # Will fail at ubic_restart (no ubic in test), but NOT at secrets check
    isnt $result->{message}, 'missing required secret: API_KEY', 'passed secrets check';
};

done_testing;
```

- [ ] **Step 2: Run test, confirm failure**

```bash
prove -lv t/16-deploy-blocks-on-missing-secrets.t
```
Expected: first subtest FAIL — deploy proceeds despite missing secret.

- [ ] **Step 3: Add `use Deploy::Secrets` to Service.pm**

In `lib/Deploy/Service.pm`, after the existing `use POSIX` (line 6), add:

```perl
use Deploy::Secrets;
```

- [ ] **Step 4: Add precondition check in `deploy()`**

In `lib/Deploy/Service.pm`, in `sub deploy` (line 44), after the `Unknown service` check (line 46) and before `my $skip_git` (line 48), add:

```perl
    # Block deploy if required secrets are missing
    if (keys %{ $svc->{env_required} // {} }) {
        my $secrets = Deploy::Secrets->new(app_home => $self->config->app_home);
        my $diff = $secrets->diff($name, {
            required => $svc->{env_required},
            optional => $svc->{env_optional} // {},
        });
        if (@{ $diff->{missing} }) {
            my $pl = @{$diff->{missing}} > 1 ? 's' : '';
            return {
                status  => 'error',
                message => "missing required secret$pl: " . join(', ', @{ $diff->{missing} }),
            };
        }
    }
```

- [ ] **Step 5: Run test, confirm pass**

```bash
prove -lv t/16-deploy-blocks-on-missing-secrets.t
```

- [ ] **Step 6: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 7: Commit and push**

```bash
git add lib/Deploy/Service.pm t/16-deploy-blocks-on-missing-secrets.t
git commit -m "Block deploy when required secrets are missing"
git push
```

---

## Task 8: Install command — fail fast without manifest

**Files:**
- Modify: `lib/Deploy/Command/install.pm:35` (add manifest check after clone block)

After cloning (or finding the repo), load the manifest and abort with a useful error if missing.

- [ ] **Step 1: Add manifest check after clone step**

In `lib/Deploy/Command/install.pm`, after the clone block (after line 35 — the closing `}` of the `if/else` that handles repo clone), add:

```perl
    # Step 1b: Validate manifest
    require Deploy::Manifest;
    my $manifest = Deploy::Manifest->load($repo);
    unless ($manifest) {
        die "\n  No .321.yml in $repo\n"
          . "  Every service repo must ship a manifest.\n"
          . "  See CLAUDE.md -> Service Repo Contract\n";
    }
    say "  [OK] Manifest: $manifest->{name} ($manifest->{runner}, $manifest->{entry})";
```

- [ ] **Step 2: Smoke test with 321.web**

```bash
perl bin/321.pl install 321.web
```
Expected: prints `[OK] Manifest: 321.web (hypnotoad, bin/321.pl)`, then continues to deps/ubic/nginx steps.

- [ ] **Step 3: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 4: Commit and push**

```bash
git add lib/Deploy/Command/install.pm
git commit -m "Require .321.yml manifest during install"
git push
```

---

## Task 9: Migrate existing service YAMLs

**Files:**
- Modify: `services/321.web.yml` — remove `bin: bin/321.pl` and `perlbrew: perl-5.42.0` lines

Only migrate services whose repos have a `.321.yml` on disk. Currently only `321.web` has one (the dogfood manifest from Task 1). Other services keep their deploy YAML unchanged until their repos get manifests.

- [ ] **Step 1: Identify which service repos have a manifest**

```bash
for f in services/*.yml; do
    name=$(grep '^name:' "$f" | awk '{print $2}');
    repo=$(grep '^repo:' "$f" | awk '{print $2}');
    if [ -f "$repo/.321.yml" ]; then
        echo "HAS MANIFEST: $name ($repo)";
    else
        echo "NO MANIFEST:  $name ($repo)";
    fi
done
```

- [ ] **Step 2: Remove `bin` and `perlbrew` from `services/321.web.yml`**

The current file has these two lines to remove:
```
bin: bin/321.pl
perlbrew: perl-5.42.0
```

Remove only those lines. Leave `name`, `branch`, `repo`, `targets`, and everything else untouched.

Check if the file contains a `sops:` marker before editing — if SOPS-encrypted, re-encrypt after: `~/bin/sops encrypt -i services/321.web.yml`. If not encrypted, skip re-encryption.

- [ ] **Step 3: Verify resolved config still correct**

```bash
perl -Ilib -MDeploy::Config -E '
  my $c = Deploy::Config->new;
  my $s = $c->service("321.web");
  say "bin:      " . ($s->{bin} // "UNDEF");
  say "perlbrew: " . ($s->{perlbrew} // "UNDEF");
  say "runner:   " . ($s->{runner} // "UNDEF");
'
```
Expected: `bin: bin/321.pl`, `perlbrew: perl-5.42.0`, `runner: hypnotoad` — all sourced from the manifest now.

- [ ] **Step 4: Run full suite**

```bash
prove -lr t
```

- [ ] **Step 5: Commit and push**

```bash
git add services/321.web.yml
git commit -m "Slim 321.web deploy YAML: bin+perlbrew now from .321.yml manifest"
git push
```

---

## Task 10: Document manifest contract in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `## Service Repo Contract` section**

In `CLAUDE.md`, insert between the existing `## Dev parity` section and the `## Development` section:

````markdown
## Service Repo Contract

Every service repo installed by 321 must ship a `.321.yml` at the repo root. It declares code-side facts — things that belong with the application, not in the deploy repo.

```yaml
name: love.web              # <group>.<name>
entry: bin/love.pl
runner: hypnotoad           # hypnotoad | morbo | script
perl: perl-5.42.1           # optional; perlbrew version
health: /health             # optional; post-deploy probe path
env_required:               # keys the app cannot start without
  DATABASE_URL: "Postgres DSN"
env_optional:               # keys with sensible defaults or only-sometimes-needed
  LOG_LEVEL:
    default: info
    desc: "debug | info | warn"
```

The deploy repo (`services/<name>.yml`) only owns deploy-side facts: repo URL, branch, per-target `host`/`port`/`ssl`/`env`, `apt_deps`, and any operator overrides. When a deploy YAML sets a field that also exists in the manifest (e.g. `bin:`), the deploy-side value wins (operator override).

The 321 dashboard compares `env_required` against `secrets/<name>.env` and refuses to deploy or start a service with any missing required key. Secrets are managed via the dashboard UI or the `/service/:name/secrets` API.
````

- [ ] **Step 2: Commit and push**

```bash
git add CLAUDE.md
git commit -m "Document .321.yml service repo contract in CLAUDE.md"
git push
```

---

## Self-Review Checklist

- [ ] Task 1: `.321.yml` committed (was untracked).
- [ ] Task 2: `Config.pm` merges manifest; `APP_HOME` env override enabled; test covers merge + override.
- [ ] Task 3: `Deploy::Secrets` with diff/set/delete, atomic writes, audit log; 8 subtests.
- [ ] Task 4: Three secrets endpoints; 6 endpoint assertions; `$secrets_mgr` wired same as other managers.
- [ ] Task 5: `/services` response enriched; badge rendered client-side in `loadServices()`; CSS added.
- [ ] Task 6: Secrets panel in sidebar; `loadSecrets()`/`setSecret()`/`deleteSecret()` JS; CSS for `.secret-*` classes; called from `loadStatus()`.
- [ ] Task 7: `deploy()` blocks on missing required secrets; test covers both blocked and proceeds cases.
- [ ] Task 8: `install` fails fast without `.321.yml`.
- [ ] Task 9: `services/321.web.yml` slimmed; resolved config verified.
- [ ] Task 10: CLAUDE.md documents contract.
- [ ] No TODO or placeholder code.
- [ ] All tests pass after every task.
- [ ] Every commit is pushed (per repo convention).
- [ ] Naming consistent: `env_required`/`env_optional` everywhere, `secrets_mgr` lexical, `diff`/`set`/`delete` methods, `required`/`optional` keys in diff arg hash.
