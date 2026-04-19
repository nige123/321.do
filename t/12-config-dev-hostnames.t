use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;

my $home = tempdir(CLEANUP => 1);
my $scan = tempdir(CLEANUP => 1);

# Two services share dev.shared.do; one has no dev target; one has localhost

my $repo_a = path($scan, 'web.a.do');
$repo_a->mkpath;
path($repo_a, '321.yml')->spew_utf8(<<'YAML');
name: a.web
entry: bin/app.pl
runner: hypnotoad
dev:
  host: dev.a.do
  port: 9001
YAML

my $repo_b = path($scan, 'web.b.do');
$repo_b->mkpath;
path($repo_b, '321.yml')->spew_utf8(<<'YAML');
name: b.web
entry: bin/app.pl
runner: hypnotoad
dev:
  host: dev.shared.do
  port: 9002
YAML

my $repo_c = path($scan, 'web.c.do');
$repo_c->mkpath;
path($repo_c, '321.yml')->spew_utf8(<<'YAML');
name: c.web
entry: bin/app.pl
runner: hypnotoad
dev:
  host: dev.shared.do
  port: 9003
YAML

my $repo_d = path($scan, 'web.d.do');
$repo_d->mkpath;
path($repo_d, '321.yml')->spew_utf8(<<'YAML');
name: d.web
entry: bin/app.pl
runner: hypnotoad
live:
  host: d.do
  port: 9004
YAML

my $repo_e = path($scan, 'web.e.do');
$repo_e->mkpath;
path($repo_e, '321.yml')->spew_utf8(<<'YAML');
name: e.web
entry: bin/app.pl
runner: hypnotoad
dev:
  host: localhost
  port: 9005
YAML

my $c = Deploy::Config->new(app_home => $home, scan_dir => "$scan");
is_deeply $c->dev_hostnames, ['dev.a.do', 'dev.shared.do'],
    'dedupes, skips localhost, skips services without dev target, sorts';

done_testing;
