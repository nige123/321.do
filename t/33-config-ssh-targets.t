use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;

my $home = tempdir(CLEANUP => 1);
my $scan = tempdir(CLEANUP => 1);

# ------------------------------------------------------------------ test 1: dev target has no ssh fields --

subtest 'dev target has no ssh or ssh_key fields' => sub {
    my $repo = path($scan, 'app.test.do');
    $repo->mkpath;
    path($repo, '321.yml')->spew_utf8(<<'YAML');
name: test.app
entry: bin/app.pl
runner: hypnotoad
dev:
  host: test.local
  port: 9100
live:
  host: test.do
  port: 9101
  ssh: deploy@test.do
  ssh_key: /home/deploy/.ssh/id_ed25519
YAML

    my $c = Deploy::Config->new(app_home => $home, scan_dir => "$scan", target => 'dev');
    my $svc = $c->service('test.app');
    ok !exists $svc->{ssh},     'dev target: no ssh field';
    ok !exists $svc->{ssh_key}, 'dev target: no ssh_key field';
};

# ------------------------------------------------------------------ test 2: live target with ssh fields --

subtest 'live target with ssh + ssh_key has them in resolved output' => sub {
    my $c = Deploy::Config->new(app_home => $home, scan_dir => "$scan", target => 'live');
    my $svc = $c->service('test.app');
    is $svc->{ssh},     'deploy@test.do',                  'ssh field present';
    is $svc->{ssh_key}, '/home/deploy/.ssh/id_ed25519',    'ssh_key field present';
    is $svc->{host},    'test.do',                         'host correct';
    is $svc->{port},    9101,                              'port correct';
};

# ------------------------------------------------------------------ test 3: manifest loaded from 321.yml --

subtest 'manifest loaded from 321.yml in repo dir' => sub {
    my $repo2 = path($scan, 'web.mtest.do');
    $repo2->mkpath;
    path($repo2, '321.yml')->spew_utf8(<<'YAML');
name: mtest.web
entry: bin/mtest.pl
runner: hypnotoad
perl: perl-5.42.0
live:
  host: mtest.do
  port: 9200
YAML

    my $c = Deploy::Config->new(app_home => $home, scan_dir => "$scan", target => 'live');
    my $svc = $c->service('mtest.web');
    is $svc->{bin},      'bin/mtest.pl',  'bin populated from manifest entry';
    is $svc->{perlbrew}, 'perl-5.42.0',  'perlbrew populated from manifest perl';
    is $svc->{runner},   'hypnotoad',    'runner from manifest';
};

# ------------------------------------------------------------------ test 4: .321.yml not loaded --

subtest 'manifest NOT found when only .321.yml exists (no 321.yml)' => sub {
    my $repo3 = path($scan, 'web.old.do');
    $repo3->mkpath;
    # Only create a .321.yml (dot-prefixed), not 321.yml
    path($repo3, '.321.yml')->spew_utf8(<<'YAML');
name: old.web
entry: bin/old.pl
runner: hypnotoad
YAML

    my $c = Deploy::Config->new(app_home => $home, scan_dir => "$scan", target => 'live');
    my $svc = $c->service('old.web');
    ok !defined $svc, 'old.web not found (only .321.yml exists, not 321.yml)';
};

done_testing;
