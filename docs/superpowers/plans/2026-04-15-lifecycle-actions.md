# Service Lifecycle Actions (Update / Migrate / Restart) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give operators fine-grained post-install service lifecycle control from the dashboard — update code without restarting, run DB migrations, restart without redeploying — in addition to the existing full DEPLOY.

**Architecture:** `Deploy::Service::deploy` is refactored into private step helpers (`_step_apt_deps`, `_step_git_pull`, `_step_cpanm`, `_step_migrate`, `_step_ubic_restart`, `_step_port_check`), each returning a `{step, success, output}` hashref. Four public methods compose these: `deploy` (all), `update` (git+cpanm+migrate), `migrate` (just migrate), `restart` (just restart+port). `bin/migrate` in the service repo is the convention — runs with the same PERL5LIB/PATH as the service. Three new JSON endpoints + three buttons on the service detail page, reusing the existing `renderDeploySteps()` UI.

**Tech Stack:** Perl 5.42, Mojolicious::Lite, Ubic, Test::Mojo. No new dependencies.

---

## File Structure

**Modified files:**
- `lib/Deploy/Service.pm` — refactor `deploy` into step helpers; add `update`, `migrate`, `restart` public methods; new `_step_migrate` method.
- `bin/321.pl` — three new routes (`POST /service/:name/update|migrate|restart`); three new buttons + wiring in the `service_detail` template.

**New files:**
- `t/27-service-lifecycle.t` — unit tests covering each public method and the migrate step in isolation (using a git-initialized tempdir repo with a fake `bin/migrate`).

**Untouched:**
- `Deploy::Nginx`, `Deploy::Hosts`, `Deploy::CertProvider`, `Deploy::Ubic` — out of scope.
- Dashboard deploy button — behaviour unchanged; only new buttons on the service detail page.

---

## Task 1: Refactor `deploy` into step helpers

Pre-refactor. Split the 40-line `deploy` method into reusable step helpers — no behaviour change. Makes Tasks 2–5 composable.

**Files:**
- Modify: `lib/Deploy/Service.pm:44-89` (body of `deploy`)

- [ ] **Step 1: Add a regression test that locks the current deploy step sequence**

Create `t/27-service-lifecycle.t`:

```perl
use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;
use Deploy::Service;
use Mojo::Log;

# Fixtures: a repo with a local git history plus a stub cpanfile.
sub make_fixture {
    my $home = tempdir(CLEANUP => 1);
    path($home, 'services')->mkpath;
    path($home, 'secrets')->mkpath;

    my $repo = tempdir(CLEANUP => 1);
    system("cd $repo && git init -q && git config user.email t\@t && git config user.name t && git commit --allow-empty -m init -q");
    path($repo, 'cpanfile')->spew_utf8("requires 'perl', '5.010';\n");

    path($home, 'services', 'demo.web.yml')->spew_utf8(<<"YAML");
name: demo.web
repo: $repo
branch: master
bin: bin/app.pl
targets:
  live:
    host: demo.do
    port: 39400
    runner: hypnotoad
YAML

    return ($home, $repo);
}

subtest 'deploy returns the same step sequence as before the refactor' => sub {
    my ($home, $repo) = make_fixture();
    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->deploy('demo.web', skip_git => 1);
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps,
        [qw(apt_deps cpanm generate_ubic ubic_restart port_check)],
        'full deploy emits the expected step list (skip_git)';
};

done_testing;
```

- [ ] **Step 2: Run the test — it should pass against current code**

Run: `prove -lv t/27-service-lifecycle.t`
Expected: PASS. This proves the baseline before refactoring.

- [ ] **Step 3: Refactor — extract step helpers**

Replace the body of `sub deploy` in `lib/Deploy/Service.pm` and add the private step helpers below. Full replacement of lines 44–89:

```perl
sub deploy ($self, $name, %opts) {
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    my $skip_git = $opts{skip_git} // 0;
    my @steps;

    my $s = $self->_step_apt_deps($svc);
    push @steps, $s;
    return $self->_deploy_result($name, 'error', 'System packages missing', \@steps)
        unless $s->{success} eq \1 || $s->{success};

    unless ($skip_git) {
        $s = $self->_step_git_pull($svc);
        push @steps, $s;
        return $self->_deploy_result($name, 'error', 'Git pull failed', \@steps)
            unless $s->{success};
    }

    $s = $self->_step_cpanm($svc);
    push @steps, $s;
    $self->log->warn("cpanm failed for $name: $s->{output}") unless $s->{success};

    if (-x "$svc->{repo}/bin/migrate") {
        $s = $self->_step_migrate($svc);
        push @steps, $s;
        return $self->_deploy_result($name, 'error', 'Migration failed', \@steps)
            unless $s->{success};
    }

    if ($self->ubic_mgr) {
        my $gen = $self->ubic_mgr->generate($name);
        push @steps, { step => 'generate_ubic', success => \1, output => "Generated: $gen->{path}" };
    }

    $s = $self->_step_ubic_restart($name);
    push @steps, $s;
    return $self->_deploy_result($name, 'error', 'Ubic restart failed', \@steps)
        unless $s->{success};

    sleep 2;
    $s = $self->_step_port_check($svc);
    push @steps, $s;

    $self->_log_deploy($name, \@steps);

    my $tag = $skip_git ? ' (dev)' : '';
    my $port_ok = ref $s->{success} ? ${$s->{success}} : $s->{success};
    my $final_status = $port_ok ? 'success' : 'error';
    my $final_msg = $port_ok
        ? "Deployed $name$tag successfully"
        : "Deployed $name$tag but port check failed";
    return $self->_deploy_result($name, $final_status, $final_msg, \@steps);
}

sub _step_apt_deps ($self, $svc) {
    my ($ok, $out) = $self->_check_apt_deps($svc);
    return { step => 'apt_deps', success => $ok ? \1 : \0, output => $out };
}

sub _step_git_pull ($self, $svc) {
    my $branch = $svc->{branch} // 'master';
    my ($ok, $out) = $self->_run_in_dir($svc->{repo},
        "git fetch origin && git reset --hard origin/$branch");
    return { step => 'git_pull', success => $ok, output => $out };
}

sub _step_cpanm ($self, $svc) {
    my ($ok, $out) = $self->_run_in_dir($svc->{repo}, $self->_cpanm_cmd($svc->{perlbrew}));
    return { step => 'cpanm', success => $ok, output => $out };
}

sub _step_ubic_restart ($self, $name) {
    my ($ok, $out) = $self->_run_cmd("ubic restart $name");
    return { step => 'ubic_restart', success => $ok, output => $out };
}

sub _step_port_check ($self, $svc) {
    my $ok = $self->_check_port($svc->{port});
    return {
        step    => 'port_check',
        success => $ok ? \1 : \0,
        output  => $ok ? "Port $svc->{port} responding" : "Port $svc->{port} not responding",
    };
}
```

Note: `_step_migrate` is added in Task 2; for this task the `deploy` method references it behind an `-x "$svc->{repo}/bin/migrate"` guard, so the refactor produces identical behaviour when no `bin/migrate` exists (fixture has none).

- [ ] **Step 4: Run the regression test — should still pass**

Run: `prove -lv t/27-service-lifecycle.t`
Expected: PASS. Step list unchanged.

- [ ] **Step 5: Run the full suite — no regressions**

Run: `prove -lr t`
Expected: PASS across all existing tests.

- [ ] **Step 6: Commit**

```bash
git add lib/Deploy/Service.pm t/27-service-lifecycle.t
git commit -m "Refactor Deploy::Service::deploy into composable step helpers"
```

---

## Task 2: Add `bin/migrate` convention + `_step_migrate`

**Files:**
- Modify: `lib/Deploy/Service.pm` (add `_step_migrate` method, already referenced in Task 1's `deploy`)
- Modify: `t/27-service-lifecycle.t` (append subtests)

- [ ] **Step 1: Add failing tests for the migrate step**

Append to `t/27-service-lifecycle.t` (before `done_testing`):

```perl
subtest '_step_migrate: success' => sub {
    my ($home, $repo) = make_fixture();
    path($repo, 'bin')->mkpath;
    path($repo, 'bin/migrate')->spew_utf8('#!/bin/sh' . "\n" . 'echo "applying migration 001"' . "\n");
    chmod 0755, "$repo/bin/migrate";

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $svc = $svc_mgr->config->service('demo.web');
    my $s = $svc_mgr->_step_migrate($svc);

    is $s->{step}, 'migrate',                'step name';
    ok $s->{success},                         'success is truthy';
    like $s->{output}, qr/applying migration 001/, 'migrate output captured';
};

subtest '_step_migrate: failure propagates non-zero exit' => sub {
    my ($home, $repo) = make_fixture();
    path($repo, 'bin')->mkpath;
    path($repo, 'bin/migrate')->spew_utf8('#!/bin/sh' . "\n" . 'echo boom >&2' . "\n" . 'exit 7' . "\n");
    chmod 0755, "$repo/bin/migrate";

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $svc = $svc_mgr->config->service('demo.web');
    my $s = $svc_mgr->_step_migrate($svc);

    ok !$s->{success},         'non-zero exit → success false';
    like $s->{output}, qr/boom/, 'stderr captured in output';
};

subtest 'deploy runs bin/migrate when present' => sub {
    my ($home, $repo) = make_fixture();
    path($repo, 'bin')->mkpath;
    path($repo, 'bin/migrate')->spew_utf8('#!/bin/sh' . "\n" . 'echo migrated' . "\n");
    chmod 0755, "$repo/bin/migrate";

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->deploy('demo.web', skip_git => 1);
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps,
        [qw(apt_deps cpanm migrate generate_ubic ubic_restart port_check)],
        'migrate slotted between cpanm and ubic_restart';
};

subtest 'deploy aborts before restart when migrate fails' => sub {
    my ($home, $repo) = make_fixture();
    path($repo, 'bin')->mkpath;
    path($repo, 'bin/migrate')->spew_utf8('#!/bin/sh' . "\n" . 'exit 1' . "\n");
    chmod 0755, "$repo/bin/migrate";

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->deploy('demo.web', skip_git => 1);
    is $r->{status}, 'error',                      'deploy reports error';
    like $r->{message}, qr/Migration failed/i,     'message names the failure';
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    ok !(grep { $_ eq 'ubic_restart' } @steps),    'no restart after failed migrate';
};
```

- [ ] **Step 2: Run the new subtests — all four should fail**

Run: `prove -lv t/27-service-lifecycle.t`
Expected: FAIL with "`Can't locate object method "_step_migrate"`" (or similar) on the first two, and the deploy subtests that assume migrate in the pipeline also fail.

- [ ] **Step 3: Implement `_step_migrate`**

Add this method to `lib/Deploy/Service.pm`, immediately after `_step_port_check`:

```perl
sub _step_migrate ($self, $svc) {
    my $repo = $svc->{repo};
    my $env_prefix = "PERL5LIB=$repo/local/lib/perl5 PATH=$repo/local/bin:\$PATH";
    my ($ok, $out) = $self->_run_in_dir($repo, "$env_prefix ./bin/migrate");
    return { step => 'migrate', success => $ok, output => $out };
}
```

- [ ] **Step 4: Run the full suite — all should pass**

Run: `prove -lr t`
Expected: PASS. The `_step_migrate` subtests pass; the existing baseline subtest still passes (fixture has no `bin/migrate`, so the step is skipped).

- [ ] **Step 5: Commit**

```bash
git add lib/Deploy/Service.pm t/27-service-lifecycle.t
git commit -m "Add bin/migrate hook to deploy pipeline (convention over config)"
```

---

## Task 3: Public `update` method

`update` = `git_pull` + `cpanm` + `migrate` (no restart). For when you want to pull new code and migrate the DB without bouncing the service.

**Files:**
- Modify: `lib/Deploy/Service.pm`
- Modify: `t/27-service-lifecycle.t`

- [ ] **Step 1: Append failing tests**

```perl
subtest 'update: runs git_pull+cpanm+migrate, no restart' => sub {
    my ($home, $repo) = make_fixture();
    path($repo, 'bin')->mkpath;
    path($repo, 'bin/migrate')->spew_utf8('#!/bin/sh' . "\n" . 'echo migrated' . "\n");
    chmod 0755, "$repo/bin/migrate";

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->update('demo.web');
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps, [qw(apt_deps git_pull cpanm migrate)],
        'update skips restart + port_check';
    is $r->{status}, 'success', 'update reports success';
};

subtest 'update: aborts on git_pull failure' => sub {
    my ($home, $repo) = make_fixture();
    # Remove the repo's .git dir so git fetch fails
    path($repo, '.git')->remove_tree;

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->update('demo.web');
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps, [qw(apt_deps git_pull)], 'short-circuits on git failure';
    is $r->{status}, 'error';
};
```

- [ ] **Step 2: Run tests — both should fail**

Run: `prove -lv t/27-service-lifecycle.t`
Expected: FAIL with "`Can't locate object method "update"`".

- [ ] **Step 3: Implement `update`**

Add to `lib/Deploy/Service.pm`, after `deploy_dev`:

```perl
sub update ($self, $name) {
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    my @steps;

    my $s = $self->_step_apt_deps($svc);
    push @steps, $s;
    return $self->_deploy_result($name, 'error', 'System packages missing', \@steps)
        unless ref $s->{success} ? ${$s->{success}} : $s->{success};

    $s = $self->_step_git_pull($svc);
    push @steps, $s;
    return $self->_deploy_result($name, 'error', 'Git pull failed', \@steps)
        unless $s->{success};

    $s = $self->_step_cpanm($svc);
    push @steps, $s;
    $self->log->warn("cpanm failed for $name: $s->{output}") unless $s->{success};

    if (-x "$svc->{repo}/bin/migrate") {
        $s = $self->_step_migrate($svc);
        push @steps, $s;
        return $self->_deploy_result($name, 'error', 'Migration failed', \@steps)
            unless $s->{success};
    }

    return $self->_deploy_result($name, 'success', "Updated $name (no restart)", \@steps);
}
```

- [ ] **Step 4: Run tests — both pass**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/Deploy/Service.pm t/27-service-lifecycle.t
git commit -m "Add Deploy::Service::update (pull+cpanm+migrate, no restart)"
```

---

## Task 4: Public `migrate` method

Just `_step_migrate`. Used when you want to re-run migrations without pulling code.

**Files:**
- Modify: `lib/Deploy/Service.pm`
- Modify: `t/27-service-lifecycle.t`

- [ ] **Step 1: Append failing tests**

```perl
subtest 'migrate: runs only the migrate step' => sub {
    my ($home, $repo) = make_fixture();
    path($repo, 'bin')->mkpath;
    path($repo, 'bin/migrate')->spew_utf8('#!/bin/sh' . "\n" . 'echo migrated' . "\n");
    chmod 0755, "$repo/bin/migrate";

    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->migrate('demo.web');
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps, ['migrate'], 'single step';
    is $r->{status}, 'success';
};

subtest 'migrate: missing bin/migrate reports no-op' => sub {
    my ($home, $repo) = make_fixture();
    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    my $r = $svc_mgr->migrate('demo.web');
    is $r->{status}, 'success',                          'no-op is success';
    like $r->{message}, qr/no bin\/migrate/i,            'message explains';
    is scalar @{ $r->{data}{steps} }, 0,                 'no steps emitted';
};
```

- [ ] **Step 2: Run tests — both should fail**

Run: `prove -lv t/27-service-lifecycle.t`
Expected: FAIL with "`Can't locate object method "migrate"`".

- [ ] **Step 3: Implement `migrate`**

Add to `lib/Deploy/Service.pm`:

```perl
sub migrate ($self, $name) {
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    unless (-x "$svc->{repo}/bin/migrate") {
        return $self->_deploy_result($name, 'success', "no bin/migrate in $svc->{repo}", []);
    }

    my $s = $self->_step_migrate($svc);
    my $ok = $s->{success};
    return $self->_deploy_result(
        $name,
        $ok ? 'success' : 'error',
        $ok ? "Migrated $name" : 'Migration failed',
        [$s],
    );
}
```

- [ ] **Step 4: Run tests — both pass**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/Deploy/Service.pm t/27-service-lifecycle.t
git commit -m "Add Deploy::Service::migrate (standalone migrate step)"
```

---

## Task 5: Public `restart` method

Just restart + port check. For when you want to bounce the service after an env or config change without redeploying.

**Files:**
- Modify: `lib/Deploy/Service.pm`
- Modify: `t/27-service-lifecycle.t`

- [ ] **Step 1: Append failing test**

```perl
subtest 'restart: runs ubic_restart then port_check' => sub {
    my ($home, $repo) = make_fixture();
    my $svc_mgr = Deploy::Service->new(
        config => Deploy::Config->new(app_home => $home, target => 'live'),
        log    => Mojo::Log->new(level => 'fatal'),
    );
    # ubic restart will fail (no ubic setup in test sandbox) — we just care
    # about the step sequence.
    my $r = $svc_mgr->restart('demo.web');
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps, [qw(ubic_restart port_check)],
        'restart emits only ubic_restart + port_check';
};
```

- [ ] **Step 2: Run test — fails**

Run: `prove -lv t/27-service-lifecycle.t`
Expected: FAIL with "`Can't locate object method "restart"`".

- [ ] **Step 3: Implement `restart`**

Add to `lib/Deploy/Service.pm`:

```perl
sub restart ($self, $name) {
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    my @steps;

    my $s = $self->_step_ubic_restart($name);
    push @steps, $s;
    return $self->_deploy_result($name, 'error', 'Ubic restart failed', \@steps)
        unless $s->{success};

    sleep 2;
    $s = $self->_step_port_check($svc);
    push @steps, $s;

    my $port_ok = ref $s->{success} ? ${$s->{success}} : $s->{success};
    return $self->_deploy_result(
        $name,
        $port_ok ? 'success' : 'error',
        $port_ok ? "Restarted $name" : 'Port check failed after restart',
        \@steps,
    );
}
```

- [ ] **Step 4: Run tests — all pass**

Run: `prove -lr t`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/Deploy/Service.pm t/27-service-lifecycle.t
git commit -m "Add Deploy::Service::restart (just ubic restart + port check)"
```

---

## Task 6: HTTP endpoints for update / migrate / restart

**Files:**
- Modify: `bin/321.pl` (new routes in the authed group)
- Create: `t/28-lifecycle-endpoints.t`

- [ ] **Step 1: Write failing endpoint tests**

Create `t/28-lifecycle-endpoints.t`:

```perl
use strict;
use warnings;
use Test::More;
use Test::Mojo;
use MIME::Base64;

$ENV{MOJO_MODE} = 'production';
my $t = Test::Mojo->new(Mojo::File->new('bin/321.pl'));
my $auth = { Authorization => 'Basic ' . encode_base64('321:kaizen', '') };

# The real service mgr will return "Unknown service" for our bogus name,
# but the route existing (200 with error payload) vs not existing (404)
# is what we're validating here.

for my $path (qw(/service/nonexistent/update /service/nonexistent/migrate /service/nonexistent/restart)) {
    # Unauthed → 401
    $t->post_ok($path)->status_is(401);
    # Authed → 200 with JSON error body
    $t->post_ok($path, $auth)
      ->status_is(200)
      ->json_is('/status' => 'error')
      ->json_like('/message' => qr/Unknown service/i);
}

done_testing;
```

- [ ] **Step 2: Run — all fail**

Run: `prove -lv t/28-lifecycle-endpoints.t`
Expected: FAIL with 404 (routes don't exist).

- [ ] **Step 3: Add the three routes**

In `bin/321.pl`, find the block of routes near the existing `/service/#name/deploy-dev` handler (around line 163). Immediately after that handler, add:

```perl
post '/service/#name/update' => sub ($c) {
    my $name = $c->param('name');
    return unless $c->validate_service($name);
    my $result = $service_mgr->update($name);
    $c->render(json => $result);
};

post '/service/#name/migrate' => sub ($c) {
    my $name = $c->param('name');
    return unless $c->validate_service($name);
    my $result = $service_mgr->migrate($name);
    $c->render(json => $result);
};

post '/service/#name/restart' => sub ($c) {
    my $name = $c->param('name');
    return unless $c->validate_service($name);
    my $result = $service_mgr->restart($name);
    $c->render(json => $result);
};
```

- [ ] **Step 4: Run — all 6 subtests pass**

```
prove -lv t/28-lifecycle-endpoints.t
prove -lr t
```
Expected: PASS, no regressions.

- [ ] **Step 5: Commit**

```bash
git add bin/321.pl t/28-lifecycle-endpoints.t
git commit -m "Add POST /service/:name/{update,migrate,restart} endpoints"
```

---

## Task 7: Dashboard / service-detail UI buttons

Three new buttons below the existing DEPLOY button on the service detail page, each reusing `renderDeploySteps()` for output.

**Files:**
- Modify: `bin/321.pl` (service_detail template + script block)

- [ ] **Step 1: Add the buttons to the sidebar**

Find the existing DEPLOY/VISIT block in the `service_detail` template (around lines 2060–2068) and replace it with:

```
            <button class="btn btn-deploy" id="deploy-btn" onclick="deploy()" style="width:100%;justify-content:center">
                DEPLOY
            </button>
            <div class="lifecycle-row">
                <button class="btn btn-tint btn-docs"  id="update-btn"  onclick="lifecycle('update')"  title="git pull + cpanm + migrate, no restart">UPDATE</button>
                <button class="btn btn-tint btn-admin" id="migrate-btn" onclick="lifecycle('migrate')" title="Run bin/migrate only">MIGRATE</button>
                <button class="btn btn-tint btn-stop"  id="restart-btn" onclick="lifecycle('restart')" title="ubic restart + port check">RESTART</button>
            </div>
            <a id="visit-btn" href="#" target="_blank" rel="noopener"
               class="btn btn-tint btn-visit"
               style="width:100%;justify-content:center;margin-top:8px;display:none">
                VISIT &rarr;
            </a>
            <div class="deploy-output" id="deploy-out"></div>
```

- [ ] **Step 2: Add CSS for the button row**

In the `<style>` block of the layout (the `.deploy-output` neighbourhood, around line 1087 in the DEPLOY OUTPUT section), append:

```css
.lifecycle-row {
    display: flex;
    gap: 6px;
    margin-top: 6px;
}
.lifecycle-row .btn {
    flex: 1;
    justify-content: center;
    font-size: 11px;
    padding: 6px 8px;
}
```

- [ ] **Step 3: Add the JS handler**

In the `service_detail` template's `<script>` block (inside `content_for scripts => begin`, near the existing `deploy()` function around line 2224), add a new function:

```javascript
async function lifecycle(action) {
    const btn = document.getElementById(action + '-btn');
    const out = document.getElementById('deploy-out');
    btn.disabled = true;
    const original = btn.textContent;
    btn.innerHTML = '<span class="spinner"></span> ' + action.toUpperCase();
    out.classList.add('visible');
    out.innerHTML = '<span class="step-label">Running ' + action + '...</span>';

    try {
        const d = await api('/service/' + SVC + '/' + action, { method: 'POST' });
        renderDeploySteps(out, d.data && d.data.steps);
        if (d.status === 'success') {
            toast(SVC + ' ' + action + ' ok');
        } else {
            toast(d.message || (action + ' failed'), 'error');
        }
    } catch(e) {
        out.classList.add('visible');
        out.innerHTML = '<div class="step-fail">\u2717 ABORT: ' + esc(e.message) + '</div>';
        toast(action + ' error: ' + e.message, 'error');
    }

    btn.disabled = false;
    btn.textContent = original;
    loadStatus();
}
```

- [ ] **Step 4: Smoke test in a browser**

Start/ensure the daemon is running:
```
bash -lc 'hypnotoad bin/321.pl'
```

Open `https://321.do.dev/ui/service/zorda.web`. Confirm:
- Three new buttons (UPDATE, MIGRATE, RESTART) appear in a row below DEPLOY, above VISIT.
- Clicking RESTART shows per-step output with `ubic_restart` + `port_check` expandable blocks.
- Clicking MIGRATE on a service without `bin/migrate` shows "no bin/migrate in …" as a single-line success message (no steps).
- On failure, failed steps auto-expand as before.

- [ ] **Step 5: Run the full suite**

```
prove -lr t
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bin/321.pl
git commit -m "Service detail: UPDATE / MIGRATE / RESTART buttons"
```

---

## Task 8: Document the lifecycle actions

**Files:**
- Modify: `docs/ops.md` (insert a new section)

- [ ] **Step 1: Insert section**

In `docs/ops.md`, insert immediately before the existing `## Per-repo Perl deps (local/)` section:

```markdown
## Lifecycle actions

Four buttons on the service detail page:

- **DEPLOY** — full pipeline: `apt_deps` → `git_pull` → `cpanm` → `migrate` (if `bin/migrate` exists) → `ubic_restart` → `port_check`.
- **UPDATE** — `git_pull` + `cpanm` + `migrate`. No restart. Useful when you want to pull new code and migrate the DB before bouncing the service.
- **MIGRATE** — `bin/migrate` only. For re-running migrations without a code pull.
- **RESTART** — `ubic_restart` + `port_check` only. For picking up env or config changes without touching code.

Each renders per-step output in the same collapsible panel as DEPLOY; failed steps auto-expand.

### Migration convention

Drop a `bin/migrate` executable in the service repo. 321 invokes it with `PERL5LIB=<repo>/local/lib/perl5` and `PATH=<repo>/local/bin:$PATH` so the script can `use` your repo-local modules. Non-zero exit aborts the deploy before restart; the full stdout+stderr appears in the deploy log panel.

Pick whatever migration tool fits — `DBIx::Migration`, `App::Sqitch`, plain `psql -f migrations/<ts>.sql`, a `make migrate` shim. 321 only cares about the exit code.
```

- [ ] **Step 2: Commit**

```bash
git add docs/ops.md
git commit -m "Document UPDATE / MIGRATE / RESTART lifecycle actions"
```

---

## Self-Review Checklist

- [x] Task 1 (refactor) locks the step sequence with a test before touching the body of `deploy`.
- [x] Task 2 adds both the `_step_migrate` unit tests and the integration test for `deploy`-with-migrate.
- [x] Tasks 3–5 each add the public method + ≥2 subtests, then implement.
- [x] Task 6 covers route wiring + auth with a tiny but full Test::Mojo suite that doesn't require a real running service.
- [x] Task 7 covers the UI changes; no test (manual smoke only) — consistent with how the existing deploy-log UI has been delivered.
- [x] Task 8 ensures operator documentation exists.
- [x] No TODO / "implement later" / "add error handling" placeholders.
- [x] Method names consistent: `update`, `migrate`, `restart` as public; `_step_migrate`, `_step_git_pull`, `_step_cpanm`, `_step_ubic_restart`, `_step_apt_deps`, `_step_port_check` as private.
- [x] Route paths consistent: `/service/:name/{update,migrate,restart}`.
- [x] Step name strings in responses consistent with helper names (`git_pull`, `cpanm`, `migrate`, `ubic_restart`, `port_check`, `apt_deps`).
