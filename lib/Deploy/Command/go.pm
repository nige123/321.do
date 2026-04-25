package Deploy::Command::go;

use Mojo::Base 'Deploy::Command', -signatures;
use Deploy::Local;

has description => 'Deploy a service: git pull, cpanm, ubic restart';
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
        my $r = $local->run_in_dir($svc->{repo}, $svc->{test}, timeout => 300);
        print $r->{output} if $r->{output};
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

  Usage: APPLICATION go <service>

  321 go zorda.web   # deploy latest code

=cut
