use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;
use Deploy::Service;
use Deploy::Ubic;
use Mojo::Log;

# Stub ubic_mgr that records generate calls and returns a fake path.
package StubUbic;
sub new { bless {}, shift }
sub generate { return { path => '/tmp/stub-ubic-path' } }

# Subclass Deploy::Service to stub out external commands.
package TestService;
use parent -norequire, 'Deploy::Service';
sub _run_cmd  { return (1, 'stubbed') }          # ubic restart always succeeds
sub _check_port { return 1 }                     # port always up
# _run_in_dir is used for cpanm; let it run for real (tempdir repo, cpanfile present)

package main;

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
    my $cfg = Deploy::Config->new(app_home => $home, target => 'live');

    # Build the ubic dir structure so generate() works
    path($repo, 'ubic', 'service', 'demo')->mkpath;

    my $svc_mgr = TestService->new(
        config   => $cfg,
        log      => Mojo::Log->new(level => 'fatal'),
        ubic_mgr => Deploy::Ubic->new(config => $cfg),
    );
    my $r = $svc_mgr->deploy('demo.web', skip_git => 1);
    my @steps = map { $_->{step} } @{ $r->{data}{steps} };
    is_deeply \@steps,
        [qw(apt_deps cpanm generate_ubic ubic_restart port_check)],
        'full deploy emits the expected step list (skip_git)';
};

done_testing;
