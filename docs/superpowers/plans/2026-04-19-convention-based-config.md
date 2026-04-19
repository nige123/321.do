# Convention-Based Config: 321.yml as Single Source of Truth

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate `services/*.yml` from the 321 repo. Each service repo's `321.yml` becomes the single source of truth for everything — identity, targets, env requirements. 321 discovers services by scanning `/home/s3/*/321.yml`.

**Architecture:** `Deploy::Config::_load_all` scans a configurable base directory (default `/home/s3`) for directories containing `321.yml`. `Deploy::Manifest` expands to parse target blocks (`dev:`, `live:`, etc.) alongside the existing service identity fields. `_resolve` simplifies — no more merging two separate YAML sources. Log paths use convention: `/tmp/<name>.<type>.log`. The only thing remaining in the 321 repo per-service is `secrets/<name>.env`.

**Tech Stack:** Perl 5.42, YAML::XS, Path::Tiny. No new dependencies.

---

## New 321.yml format

```yaml
# /home/s3/love.honeywillow.com/321.yml
name: love.web
entry: bin/app.pl
perl: perl-5.42.0
health: /health
branch: main

dev:
    host: love.honeywillow.com.dev
    port: 8888
    runner: morbo

live:
    ssh: ubuntu@ec2-34-248-234-254.eu-west-1.compute.amazonaws.com
    ssh_key: ~/.ssh/kaizen-nige.pem
    host: love.honeywillow.com
    port: 8888
    runner: hypnotoad

env_required:
    DATABASE_URL: "Postgres connection string"

env_optional:
    LOG_LEVEL:
        default: info
        desc: "debug | info | warn | error"
```

### Log path convention

Derived from service name, not configured:
```
/tmp/<name>.stdout.log    e.g. /tmp/love.web.stdout.log
/tmp/<name>.stderr.log
/tmp/<name>.ubic.log
```

---

## File Structure

**Modified files:**
- `lib/Deploy/Config.pm` — rewrite `_load_all` to scan repos, rewrite `_resolve` to read from unified 321.yml, remove `_services_dir`/`_load_legacy`/`_load_file_decrypted`/SOPS, remove `save_service`/`delete_service`
- `lib/Deploy/Manifest.pm` — expand to parse target blocks and return full config including targets
- `lib/Deploy/Ubic.pm` — use conventional log paths instead of `$svc->{logs}`
- `lib/Deploy/Command/install.pm` — update scaffold boilerplate with target blocks
- `321.yml` — update this repo's own manifest with target blocks
- `bin/321.pl` — remove routes that reference `save_service`/`delete_service`

**Deleted files:**
- `services/*.yml` — all six files (config now lives in each service repo)

**Test files to update:**
- Any test creating `services/*.yml` fixtures must create `321.yml` in a repo dir instead
- `t/10-manifest.t` — add tests for target block parsing
- `t/12-config-manifest-merge.t` — rewrite for new discovery
- `t/33-config-ssh-targets.t` — rewrite for new discovery

---

## Task 1: Expand Deploy::Manifest to parse target blocks

The manifest loader currently only parses identity fields (name, entry, runner, perl, health, env). Expand it to also parse target blocks and other fields.

**Files:**
- Modify: `lib/Deploy/Manifest.pm`
- Modify: `t/10-manifest.t`

- [ ] **Step 1: Add tests for target parsing**

Append to `t/10-manifest.t` before `done_testing`:

```perl
subtest 'manifest with target blocks' => sub {
    path($dir, '321.yml')->spew_utf8(<<'YAML');
name: demo.web
entry: bin/app.pl
runner: hypnotoad
perl: perl-5.42.0
branch: main

dev:
    host: demo.do.dev
    port: 9400
    runner: morbo

live:
    ssh: ubuntu@example.com
    ssh_key: ~/.ssh/key.pem
    host: demo.do
    port: 9400
    runner: hypnotoad

env_required:
    API_KEY: "upstream API"
YAML
    my $m = Deploy::Manifest->load($dir);
    is $m->{name}, 'demo.web';
    is $m->{branch}, 'main', 'branch parsed';
    ok $m->{targets}{dev}, 'dev target parsed';
    is $m->{targets}{dev}{host}, 'demo.do.dev';
    is $m->{targets}{dev}{port}, 9400;
    is $m->{targets}{dev}{runner}, 'morbo';
    ok $m->{targets}{live}, 'live target parsed';
    is $m->{targets}{live}{ssh}, 'ubuntu@example.com';
    is $m->{targets}{live}{ssh_key}, '~/.ssh/key.pem';
    is $m->{targets}{live}{host}, 'demo.do';
    is $m->{targets}{live}{runner}, 'hypnotoad';
    is $m->{env_required}{API_KEY}, 'upstream API';
};

subtest 'manifest without targets still works' => sub {
    path($dir, '321.yml')->spew_utf8(<<'YAML');
name: simple.web
entry: bin/app.pl
runner: hypnotoad
YAML
    my $m = Deploy::Manifest->load($dir);
    is $m->{name}, 'simple.web';
    is_deeply $m->{targets}, {}, 'no targets = empty hash';
};
```

- [ ] **Step 2: Run tests — new subtests should fail**

Run: `prove -lv t/10-manifest.t`
Expected: FAIL — `targets` key not in manifest output, `branch` not returned.

- [ ] **Step 3: Update Deploy::Manifest**

Replace `lib/Deploy/Manifest.pm`:

```perl
package Deploy::Manifest;

use Mojo::Base -base, -signatures;
use YAML::XS qw(LoadFile);
use Path::Tiny qw(path);

my %VALID_RUNNER = map { $_ => 1 } qw(hypnotoad morbo script);
my $ENV_KEY_RE   = qr/^[A-Z_][A-Z0-9_]*$/;

# Keys that are service identity (not targets)
my %IDENTITY_KEY = map { $_ => 1 } qw(
    name entry runner perl health branch
    env_required env_optional apt_deps favicon
);

sub load ($class, $repo_dir) {
    my $file = path($repo_dir, '321.yml');
    return undef unless $file->exists;

    my $raw = LoadFile($file->stringify);
    die "Manifest $file: not a mapping\n" unless ref $raw eq 'HASH';

    for my $k (qw(name entry runner)) {
        die "Manifest $file: missing '$k'\n" unless defined $raw->{$k};
    }

    die "Manifest $file: unknown runner '$raw->{runner}'\n"
        unless $VALID_RUNNER{ $raw->{runner} };

    my %required = %{ $raw->{env_required} // {} };
    my %optional = %{ $raw->{env_optional} // {} };

    for my $k (keys %required, keys %optional) {
        die "Manifest $file: invalid env key '$k'\n" unless $k =~ $ENV_KEY_RE;
    }

    # Collect target blocks — any top-level key that's a hashref
    # and not an identity key is a target (dev, live, live2, etc.)
    my %targets;
    for my $k (keys %$raw) {
        next if $IDENTITY_KEY{$k};
        next unless ref $raw->{$k} eq 'HASH';
        $targets{$k} = $raw->{$k};
    }

    return {
        name         => $raw->{name},
        entry        => $raw->{entry},
        runner       => $raw->{runner},
        perl         => $raw->{perl},
        health       => $raw->{health} // '/health',
        branch       => $raw->{branch} // 'master',
        env_required => \%required,
        env_optional => \%optional,
        apt_deps     => $raw->{apt_deps} // [],
        targets      => \%targets,
        repo         => "$repo_dir",
        ($raw->{favicon} ? (favicon => $raw->{favicon}) : ()),
    };
}

1;
```

- [ ] **Step 4: Run tests — all should pass**

Run: `prove -lv t/10-manifest.t`
Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `prove -lr t`
Expected: PASS (existing tests still work — manifest returns a superset of old fields).

- [ ] **Step 6: Commit**

```bash
git add lib/Deploy/Manifest.pm t/10-manifest.t
git commit -m "Manifest: parse target blocks (dev/live) and branch from 321.yml"
```

---

## Task 2: Rewrite Deploy::Config to scan repos

Replace the `services/*.yml` loader with a repo scanner. `_load_all` scans a base directory for `321.yml` files. `_resolve` reads from the unified manifest instead of merging two sources.

**Files:**
- Modify: `lib/Deploy/Config.pm`
- Create: `t/35-config-repo-scan.t`

- [ ] **Step 1: Write tests for repo scanning**

Create `t/35-config-repo-scan.t`:

```perl
use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;

my $base = tempdir(CLEANUP => 1);

# Create two fake service repos with 321.yml
my $repo_a = path($base, 'web.alpha.do');
$repo_a->mkpath;
path($repo_a, '321.yml')->spew_utf8(<<'YAML');
name: alpha.web
entry: bin/app.pl
runner: hypnotoad
perl: perl-5.42.0
dev:
    host: alpha.do.dev
    port: 9100
    runner: morbo
live:
    ssh: ubuntu@example.com
    ssh_key: ~/.ssh/key.pem
    host: alpha.do
    port: 9100
    runner: hypnotoad
env_required:
    API_KEY: "required"
YAML

my $repo_b = path($base, 'api.beta.do');
$repo_b->mkpath;
path($repo_b, '321.yml')->spew_utf8(<<'YAML');
name: beta.api
entry: bin/api.pl
runner: hypnotoad
dev:
    host: beta.do.dev
    port: 9200
    runner: morbo
YAML

# Dir without manifest — should be ignored
path($base, 'no-manifest')->mkpath;

my $home = tempdir(CLEANUP => 1);
path($home, 'secrets')->mkpath;

my $c = Deploy::Config->new(app_home => $home, scan_dir => "$base", target => 'dev');

subtest 'discovers services from repo scan' => sub {
    my @names = sort @{ $c->service_names };
    is_deeply \@names, [qw(alpha.web beta.api)], 'found both services';
};

subtest 'resolves dev target' => sub {
    my $svc = $c->service('alpha.web');
    is $svc->{name}, 'alpha.web';
    is $svc->{host}, 'alpha.do.dev';
    is $svc->{port}, 9100;
    is $svc->{runner}, 'morbo';
    is $svc->{bin}, 'bin/app.pl';
    is $svc->{perlbrew}, 'perl-5.42.0';
    is $svc->{repo}, "$repo_a";
};

subtest 'resolves live target with ssh' => sub {
    $c->target('live');
    my $svc = $c->service('alpha.web');
    is $svc->{host}, 'alpha.do';
    is $svc->{runner}, 'hypnotoad';
    is $svc->{ssh}, 'ubuntu@example.com';
    is $svc->{ssh_key}, '~/.ssh/key.pem';
    $c->target('dev');
};

subtest 'conventional log paths' => sub {
    my $svc = $c->service('alpha.web');
    is $svc->{logs}{stdout}, '/tmp/alpha.web.stdout.log';
    is $svc->{logs}{stderr}, '/tmp/alpha.web.stderr.log';
    is $svc->{logs}{ubic},   '/tmp/alpha.web.ubic.log';
};

subtest 'env_required from manifest' => sub {
    my $svc = $c->service('alpha.web');
    is $svc->{env_required}{API_KEY}, 'required';
};

subtest 'service without live target falls back gracefully' => sub {
    $c->target('live');
    my $svc = $c->service('beta.api');
    is $svc->{runner}, 'hypnotoad', 'uses default runner';
    is $svc->{host}, 'localhost', 'defaults to localhost';
    $c->target('dev');
};

subtest 'dev_hostnames scans all dev targets' => sub {
    my @hosts = sort @{ $c->dev_hostnames };
    is_deeply \@hosts, [qw(alpha.do.dev beta.do.dev)];
};

done_testing;
```

- [ ] **Step 2: Run tests — should fail**

Run: `prove -lv t/35-config-repo-scan.t`
Expected: FAIL — `scan_dir` attribute doesn't exist yet.

- [ ] **Step 3: Rewrite Deploy::Config**

Replace `lib/Deploy/Config.pm`:

```perl
package Deploy::Config;

use Mojo::Base -base, -signatures;
use Path::Tiny qw(path);
use Mojo::File qw(curfile);
use Deploy::Manifest;

has 'app_home'  => sub { $ENV{APP_HOME} // curfile->dirname->dirname->dirname };
has 'scan_dir'  => sub { $ENV{SCAN_DIR} // '/home/s3' };
has 'target'    => 'dev';
has '_services' => sub ($self) { $self->_load_all };

sub reload ($self) {
    $self->_services($self->_load_all);
    return $self;
}

sub _load_all ($self) {
    my $base = path($self->scan_dir);
    return {} unless $base->exists;

    my %services;
    for my $dir (sort $base->children) {
        next unless $dir->is_dir;
        my $manifest = Deploy::Manifest->load($dir);
        next unless $manifest;
        $services{ $manifest->{name} } = $manifest;
    }
    return \%services;
}

sub services ($self) {
    return $self->_services;
}

sub service ($self, $name) {
    my $manifest = $self->_services->{$name};
    return undef unless $manifest;
    return $self->_resolve($name, $manifest);
}

sub _resolve ($self, $name, $manifest) {
    my $target_name = $self->target;
    my $target = $manifest->{targets}{$target_name} // {};

    my $runner = $target->{runner} // $manifest->{runner} // 'hypnotoad';

    return {
        name         => $name,
        repo         => $manifest->{repo},
        branch       => $manifest->{branch} // 'master',
        bin          => $manifest->{entry},
        mode         => $runner eq 'morbo' ? 'development' : 'production',
        runner       => $runner,
        port         => $target->{port},
        host         => $target->{host} // 'localhost',
        apt_deps     => $manifest->{apt_deps} // [],
        health       => $manifest->{health} // '/health',
        env_required => $manifest->{env_required} // {},
        env_optional => $manifest->{env_optional} // {},
        logs         => {
            stdout => "/tmp/$name.stdout.log",
            stderr => "/tmp/$name.stderr.log",
            ubic   => "/tmp/$name.ubic.log",
        },
        ($manifest->{favicon}  ? (favicon  => $manifest->{favicon})  : ()),
        ($target->{ssh}        ? (ssh      => $target->{ssh})        : ()),
        ($target->{ssh_key}    ? (ssh_key  => $target->{ssh_key})    : ()),
        ($target->{docs}       ? (docs     => $target->{docs})       : ()),
        ($target->{admin}      ? (admin    => $target->{admin})      : ()),
        ($manifest->{perl}     ? (perlbrew => $manifest->{perl})     : ()),
        ($target->{env}        ? (env      => $target->{env})        : (env => {})),
    };
}

sub service_names ($self) {
    return [ sort keys %{ $self->_services } ];
}

sub service_raw ($self, $name) {
    return $self->_services->{$name};
}

sub load_secrets ($self, $name) {
    my $env_file = path($self->app_home, 'secrets', "$name.env");
    return {} unless $env_file->exists;

    my %env;
    for my $line ($env_file->lines_utf8({ chomp => 1 })) {
        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;
        if ($line =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/) {
            $env{$1} = $2;
        }
    }
    return \%env;
}

sub dev_hostnames ($self) {
    my %seen;
    my @hosts;
    for my $name (@{ $self->service_names }) {
        my $manifest = $self->_services->{$name};
        my $dev = $manifest->{targets}{dev} or next;
        my $h = $dev->{host} or next;
        next if $h eq 'localhost';
        push @hosts, $h unless $seen{$h}++;
    }
    return [ sort @hosts ];
}

1;
```

- [ ] **Step 4: Run new tests — should pass**

Run: `prove -lv t/35-config-repo-scan.t`
Expected: PASS.

- [ ] **Step 5: Fix existing tests**

Tests that create `services/*.yml` fixtures need updating to create `321.yml` in repo dirs instead. Key files:
- `t/33-config-ssh-targets.t` — rewrite to use `scan_dir`
- `t/12-config-manifest-merge.t` — rewrite or delete (merge logic is gone)
- `t/12-config-dev-hostnames.t` — rewrite to use `scan_dir`
- Any test using `Deploy::Config->new(app_home => $home)` that expects `services/` loading

For each, the pattern changes from:
```perl
path($home, 'services', 'demo.web.yml')->spew_utf8(...);
my $c = Deploy::Config->new(app_home => $home, target => 'dev');
```
To:
```perl
my $repo = path($base, 'web.demo.do');
$repo->mkpath;
path($repo, '321.yml')->spew_utf8(...);
my $c = Deploy::Config->new(app_home => $home, scan_dir => "$base", target => 'dev');
```

- [ ] **Step 6: Run full suite — confirm clean**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Deploy/Config.pm t/35-config-repo-scan.t t/33-config-ssh-targets.t t/12-config-manifest-merge.t t/12-config-dev-hostnames.t
git commit -m "Config: scan repos for 321.yml instead of loading services/*.yml"
```

---

## Task 3: Update 321.yml for this repo + all service repos

Write the new-format `321.yml` for `web.321.do` with target blocks. Create `321.yml` files for all other service repos that currently have `services/*.yml` configs.

**Files:**
- Modify: `321.yml` (this repo)
- Create: `321.yml` in each service repo that needs one

- [ ] **Step 1: Update this repo's 321.yml**

Replace `/home/s3/web.321.do/321.yml`:

```yaml
name: 321.web
entry: bin/321.pl
runner: hypnotoad
perl: perl-5.42.0
health: /health
branch: master

dev:
    host: 321.do.dev
    port: 9321
    runner: morbo

live:
    ssh: ubuntu@ec2-34-248-234-254.eu-west-1.compute.amazonaws.com
    ssh_key: ~/.ssh/kaizen-nige.pem
    host: 321.do
    port: 9321
    runner: hypnotoad

env_required:
    MOJO_MODE: "production or development"

env_optional:
    DEPLOY_TOKEN:
        desc: "Token for remote deploy endpoint"
```

- [ ] **Step 2: Create 321.yml for each other service repo**

Read each `services/*.yml` to extract the current config, then write a `321.yml` into the corresponding repo. Use info from `services/*.yml` for target blocks.

For each service repo (`/home/s3/love.honeywillow.com`, `/home/s3/web.zorda.co`, etc.):
1. Read the `services/<name>.yml` file
2. Write `321.yml` in the repo dir with the equivalent config
3. Commit in the service repo

- [ ] **Step 3: Verify config still resolves**

```bash
perl -Ilib -MDeploy::Config -E '
    my $c = Deploy::Config->new(target => "dev");
    for my $name (@{ $c->service_names }) {
        my $svc = $c->service($name);
        printf "%-20s %-20s port %s\n", $name, $svc->{host}, $svc->{port} // "-";
    }
'
```

Expected: same services as before, all resolving correctly.

- [ ] **Step 4: Commit this repo's changes**

```bash
git add 321.yml
git commit -m "Update 321.yml with dev/live target blocks"
```

---

## Task 4: Delete services/*.yml

Remove the now-redundant service config files from the 321 repo.

**Files:**
- Delete: `services/321.web.yml`, `services/123.api.yml`, `services/123.web.yml`, `services/love.web.yml`, `services/nh.web.yml`, `services/zorda.web.yml`

- [ ] **Step 1: Verify all services are discoverable via 321.yml scan**

```bash
perl -Ilib -MDeploy::Config -E 'print join("\n", @{Deploy::Config->new->service_names}), "\n"'
```

Expected: all 6 services listed.

- [ ] **Step 2: Delete services directory**

```bash
git rm services/*.yml
```

- [ ] **Step 3: Remove _services_dir references**

Remove or update any code that references the `services/` directory:
- `Deploy::Config` — already rewritten in Task 2 (no `_services_dir` method)
- `bin/321.pl` — check for any routes that write to `services/`

- [ ] **Step 4: Run full suite**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "Remove services/*.yml — config now lives in each service repo's 321.yml"
```

---

## Task 5: Update Ubic to use conventional log paths

`Deploy::Ubic` currently reads `$svc->{logs}` which came from `services/*.yml`. Now logs are conventional — always `/tmp/<name>.<type>.log`. The resolved service already has these paths (from Task 2), so Ubic just uses them.

**Files:**
- Modify: `lib/Deploy/Ubic.pm` — verify it works with new log format (it already reads `$svc->{logs}` which is now set by convention)

- [ ] **Step 1: Verify Ubic works with new config**

```bash
perl -Ilib -MDeploy::Config -MDeploy::Ubic -E '
    my $c = Deploy::Config->new;
    my $u = Deploy::Ubic->new(config => $c);
    my $r = $u->generate("321.web");
    print "status: $r->{status}\n";
    use Path::Tiny; print Path::Tiny::path($r->{path})->slurp_utf8;
'
```

Expected: ubic file generated with `/tmp/321.web.stdout.log` etc.

- [ ] **Step 2: Run full suite**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 3: Commit if any changes needed**

```bash
git add lib/Deploy/Ubic.pm
git commit -m "Ubic: verify conventional log paths work"
```

---

## Task 6: Update install scaffold with target blocks

Update the boilerplate `321.yml` generated by `321 install` to include target block examples.

**Files:**
- Modify: `lib/Deploy/Command/install.pm`

- [ ] **Step 1: Update `_scaffold_manifest`**

Replace the manifest template in the method:

```perl
sub _scaffold_manifest ($self, $repo, $name, $transport) {
    my $manifest = <<"YAML";
# 321.yml - service manifest for $name
#
# This file tells 321 how to run your app.
# Edit the values below, then re-run: 321 install $name

# Service identity
name: $name

# Entry point - the script 321 starts via hypnotoad/morbo
entry: bin/app.pl

# Default process runner: hypnotoad (production) or morbo (dev, auto-reload)
runner: hypnotoad

# Perl version managed by perlbrew (omit if using system perl)
# perl: perl-5.42.0

# Health check path - 321 hits this after deploy to verify the app is up
# health: /health

# Git branch to deploy from
# branch: main

# === Targets ===
# Each target defines where and how the service runs.
# 'dev' runs locally, 'live' runs on a remote server via SSH.

dev:
    host: $name.dev
    port: 8080
    runner: morbo

# live:
#     ssh: ubuntu\@your-ec2-host.compute.amazonaws.com
#     ssh_key: ~/.ssh/your-key.pem
#     host: your-domain.com
#     port: 8080
#     runner: hypnotoad

# === Environment Variables ===

# Variables the app requires to start (deploy blocked if missing)
# env_required:
#   DATABASE_URL: "Postgres connection string"
#   SECRET_KEY: "Session signing key"

# Variables with sensible defaults (optional to set)
# env_optional:
#   LOG_LEVEL:
#     default: info
#     desc: "debug | info | warn | error"
YAML

    require Path::Tiny;
    my $tmp = Path::Tiny::path("/tmp/321-manifest-$$.yml");
    $tmp->spew_utf8($manifest);
    $transport->upload("$tmp", "$repo/321.yml");
    $tmp->remove;
}
```

- [ ] **Step 2: Run full suite**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/Deploy/Command/install.pm
git commit -m "Install scaffold: include target blocks and env examples in boilerplate"
```

---

## Task 7: Clean up bin/321.pl

Remove routes and code that referenced the old `services/*.yml` system.

**Files:**
- Modify: `bin/321.pl`

- [ ] **Step 1: Remove save/delete/create routes if still present**

Search `bin/321.pl` for `save_service`, `delete_service`, `services/create`. Remove any routes that write to the old `services/` directory.

- [ ] **Step 2: Update config initialization**

Ensure `Deploy::Config->new` uses the correct `scan_dir`. The default `/home/s3` should work for both dev and production. If `$ENV{SCAN_DIR}` is set, it overrides.

- [ ] **Step 3: Run full suite**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add bin/321.pl
git commit -m "Remove services/*.yml references from dashboard"
```

---

## Self-Review Checklist

- [x] `services/*.yml` eliminated — config lives in each service repo's `321.yml`
- [x] Convention-based discovery: scan `/home/s3/*/321.yml`
- [x] Convention-based log paths: `/tmp/<name>.<type>.log`
- [x] Target blocks (dev/live) in `321.yml` replace nested `targets:` in old format
- [x] SSH fields (ssh, ssh_key) work in target blocks
- [x] `secrets/<name>.env` remains in the 321 repo (unchanged)
- [x] Scaffold boilerplate updated with target blocks
- [x] No placeholders — every step has code
- [x] Commit per task
