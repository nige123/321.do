use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;

my $home = tempdir(CLEANUP => 1);
path($home, 'services')->mkpath;

# ------------------------------------------------------------------ helpers --

sub make_config {
    my (%args) = @_;
    Deploy::Config->new(app_home => $home, %args);
}

# ------------------------------------------------------------------ test 1: dev target has no ssh fields --

subtest 'dev target has no ssh or ssh_key fields' => sub {
    path($home, 'services', 'test.app.yml')->spew_utf8(<<"YAML");
name: test.app
repo: /nonexistent
targets:
  dev:
    host: test.local
    port: 9100
  live:
    host: test.do
    port: 9101
    ssh: deploy\@test.do
    ssh_key: /home/deploy/.ssh/id_ed25519
YAML

    my $c = make_config(target => 'dev');
    my $svc = $c->service('test.app');
    ok !exists $svc->{ssh},     'dev target: no ssh field';
    ok !exists $svc->{ssh_key}, 'dev target: no ssh_key field';
};

# ------------------------------------------------------------------ test 2: live target with ssh fields --

subtest 'live target with ssh + ssh_key has them in resolved output' => sub {
    my $c = make_config(target => 'live');
    my $svc = $c->service('test.app');
    is $svc->{ssh},     'deploy@test.do',                  'ssh field present';
    is $svc->{ssh_key}, '/home/deploy/.ssh/id_ed25519',    'ssh_key field present';
    is $svc->{host},    'test.do',                         'host correct';
    is $svc->{port},    9101,                              'port correct';
};

# ------------------------------------------------------------------ test 3: manifest loaded from 321.yml --

subtest 'manifest loaded from 321.yml (not .321.yml)' => sub {
    my $repo = tempdir(CLEANUP => 1);
    path($repo, '321.yml')->spew_utf8(<<'YAML');
name: mtest.web
entry: bin/mtest.pl
runner: hypnotoad
perl: perl-5.42.0
YAML

    path($home, 'services', 'mtest.web.yml')->spew_utf8(<<"YAML");
name: mtest.web
repo: $repo
targets:
  live:
    host: mtest.do
    port: 9200
YAML

    my $c = make_config(target => 'live');
    my $svc = $c->service('mtest.web');
    is $svc->{bin},      'bin/mtest.pl',  'bin populated from manifest entry';
    is $svc->{perlbrew}, 'perl-5.42.0',  'perlbrew populated from manifest perl';
    is $svc->{runner},   'hypnotoad',    'runner from manifest';
};

# ------------------------------------------------------------------ test 4: .321.yml not loaded --

subtest 'manifest NOT found when only .321.yml exists' => sub {
    my $repo = tempdir(CLEANUP => 1);
    path($repo, '.321.yml')->spew_utf8(<<'YAML');
name: old.web
entry: bin/old.pl
runner: hypnotoad
YAML

    path($home, 'services', 'old.web.yml')->spew_utf8(<<"YAML");
name: old.web
repo: $repo
targets:
  live:
    host: old.do
    port: 9300
YAML

    my $c = make_config(target => 'live');
    my $svc = $c->service('old.web');
    ok !defined $svc->{bin},      'bin not populated (only .321.yml exists)';
    ok !defined $svc->{perlbrew}, 'perlbrew not populated (only .321.yml exists)';
};

done_testing;
