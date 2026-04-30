package Deploy::Command::go;

use Mojo::Base 'Deploy::Command', -signatures;
use Deploy::Local;
use Deploy::Command::install;

has description => 'Deploy a service: install if new, otherwise hot-restart';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my ($svc_input, $target) = $self->parse_target(@args);
    die $self->usage unless $svc_input;
    my $name = $self->resolve_service($svc_input);
    $self->config->target($target);

    my $svc = $self->config->service($name);

    # Run tests before deploying to live
    if ($target ne 'dev' && $svc->{test}) {
        say "Running tests before deploy...";
        say "";
        my $local = Deploy::Local->new;
        my $r = $local->stream("cd $svc->{repo} && $svc->{test}");
        unless ($r->{ok}) {
            say "";
            say "  \e[31mTests failed - deploy aborted\e[0m";
            return;
        }
        say "";
        say "  \e[32mTests passed\e[0m";
        say "";
    }

    my $transport = $self->transport_for($name, $target);

    # First-time bring-up vs hot-restart: install if the repo OR the ubic
    # service file is missing. A partial install (repo cloned but ubic file
    # gone) re-triggers install rather than failing in deploy.
    my ($group, $svc_short) = split /\./, $name, 2;
    my $check = $transport->run(
        "test -d $svc->{repo}/.git && test -e ~/ubic/service/$group/$svc_short && echo OK"
    );
    my $needs_install = ($check->{output} // '') !~ /OK/;

    if ($needs_install) {
        my $install = Deploy::Command::install->new(app => $self->app);
        $install->run($name, $target);
        return;
    }

    my $svc_mgr = $self->svc_mgr;
    $svc_mgr->transport($transport);

    say "3... 2... 1... deploying $name ($target)";
    my $skip_git = ($target eq 'dev') ? 1 : 0;
    my $r = $svc_mgr->deploy($name, skip_git => $skip_git);
    $self->print_steps($r);
    say "  $r->{message}" if $r->{message};
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION go [service] [target]

  First run on a target installs (clone, deps, ubic, nginx, SSL, start).
  Later runs hot-restart via hypnotoad (git pull, cpanm, ubic restart).

  321 go              # deploy current repo to dev
  321 go live         # deploy current repo to live
  321 go zorda.web    # deploy zorda.web to dev

=cut
