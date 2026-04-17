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
path($repo, '321.yml')->spew_utf8(
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
