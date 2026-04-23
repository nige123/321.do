package Deploy::Command::start;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Start a service';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my ($svc_input, $target) = $self->parse_target(@args);
    die $self->usage unless $svc_input;
    my $name = $self->resolve_service($svc_input);
    my $transport = $self->transport_for($name, $target);
    $self->config->target($target);
    my $r = $transport->run("ubic start $name");

    # Check if ubic knows about this service
    if ($r->{output} && $r->{output} =~ /not found|unknown service/i) {
        say "  \e[31m$name is not installed\e[0m";
        say "";
        say "  Next: install it first:";
        say "    321 install $name" . $self->target_flag($target);
        return;
    }

    say "  $r->{output}" if $r->{output} && $r->{output} =~ /\S/;

    # Verify it's actually running — check port, not just ubic
    sleep 2;
    my $svc      = $self->config->service($name);
    my $port     = $svc->{port} // '?';
    my $url      = $self->service_url($svc);
    my $port_ok  = $self->check_port($port, $transport);

    if ($port_ok) {
        say "  \e[32m$name running\e[0m ($target)  port:$port  $url";
    } else {
        say "  \e[31m$name not running\e[0m after start";
        say "";

        my @diag = $self->diagnose_stderr($transport, $name, $target);
        if (@diag) {
            say "  $diag[0]";
            say "  Fix: $diag[1]";
        } else {
            say "  Next: check logs:";
            say "    321 logs $name" . $self->target_flag($target) . " --stderr";
        }
    }
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION start <service>

=cut
