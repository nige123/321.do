use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Manifest;

my $dir = tempdir(CLEANUP => 1);

subtest 'missing file returns undef' => sub {
    my $m = Deploy::Manifest->load($dir);
    ok !$m, 'returns undef when .321.yml absent';
};

subtest 'minimal manifest' => sub {
    path($dir, '.321.yml')->spew_utf8(<<'YAML');
name: foo.web
entry: bin/app.pl
runner: hypnotoad
YAML
    my $m = Deploy::Manifest->load($dir);
    is $m->{name},   'foo.web';
    is $m->{entry},  'bin/app.pl';
    is $m->{runner}, 'hypnotoad';
    is_deeply $m->{env_required}, {}, 'env_required defaults to empty';
    is_deeply $m->{env_optional}, {}, 'env_optional defaults to empty';
};

subtest 'full manifest with env' => sub {
    path($dir, '.321.yml')->spew_utf8(<<'YAML');
name: love.web
entry: bin/love.pl
runner: hypnotoad
perl: perl-5.42.0
health: /health
env_required:
  DATABASE_URL: "Postgres DSN"
env_optional:
  LOG_LEVEL:
    default: info
    desc: "debug | info | warn"
YAML
    my $m = Deploy::Manifest->load($dir);
    is $m->{perl}, 'perl-5.42.0';
    is $m->{env_required}{DATABASE_URL}, 'Postgres DSN';
    is $m->{env_optional}{LOG_LEVEL}{default}, 'info';
};

subtest 'invalid: missing required field' => sub {
    path($dir, '.321.yml')->spew_utf8("name: bad\n");
    my $err = eval { Deploy::Manifest->load($dir); 0 } || $@;
    like $err, qr/missing 'entry'/, 'rejects manifest without entry';
};

subtest 'invalid: unknown runner' => sub {
    path($dir, '.321.yml')->spew_utf8(<<'YAML');
name: bad
entry: bin/x.pl
runner: supervisord
YAML
    my $err = eval { Deploy::Manifest->load($dir); 0 } || $@;
    like $err, qr/unknown runner/, 'rejects unsupported runner';
};

subtest 'invalid: bad env key name' => sub {
    path($dir, '.321.yml')->spew_utf8(<<'YAML');
name: bad
entry: bin/x.pl
runner: hypnotoad
env_required:
  "lowercase": "no"
YAML
    my $err = eval { Deploy::Manifest->load($dir); 0 } || $@;
    like $err, qr/invalid env key/, 'rejects non-conforming env key';
};

done_testing;
