package Deploy::Command::status;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Show service status';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my ($svc_input, $target) = $self->parse_target(@args);
    my $transport;

    if ($svc_input) {
        my $name = $self->resolve_service($svc_input);
        $transport = $self->transport_for($name, $target);
        my $r = $transport->run("ubic status $name");
        say $r->{output};
    } else {
        $transport = $self->transport_for(($self->config->service_names->[0] // return), $target);
        my $r = $transport->run("ubic status");
        say $r->{output};
    }
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION status [service]

  321 status            # all services
  321 status zorda.web  # single service

=cut
