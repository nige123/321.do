package Deploy::Command::status;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Show service status';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my ($svc_input, $target) = $self->parse_target(@args);
    $self->config->target($target);

    my @names = $svc_input
        ? ($self->resolve_service($svc_input))
        : @{ $self->config->service_names };

    for my $name (@names) {
        my $svc = $self->config->service($name);
        my $transport = $self->transport_for($name, $target);

        # Ubic status
        my $r = $transport->run("ubic status $name");
        my $ubic_status = $r->{output} // '';
        chomp $ubic_status;
        $ubic_status =~ s/^.*?\t//;
        $ubic_status =~ s/^\Q$name\E\s+//;

        my $port = $svc->{port} // '?';
        my $host = $svc->{host} // 'localhost';
        my $url  = $host ne 'localhost' ? "https://$host/" : "http://localhost:$port/";

        # Port check — verify process is actually responding
        my $ubic_says_running = $ubic_status =~ /running/;
        my $port_ok = 0;
        if ($port && $port ne '?') {
            my $check = $transport->run(
                "curl -sf -o /dev/null --connect-timeout 2 http://127.0.0.1:$port/",
                timeout => 5,
            );
            $port_ok = $check->{ok};
        }

        my $actually_running = $ubic_says_running && $port_ok;
        my $status_text;
        if ($actually_running) {
            $status_text = "\e[32m$ubic_status\e[0m";
        } elsif ($ubic_says_running && !$port_ok) {
            $status_text = "\e[33m$ubic_status (port $port not responding)\e[0m";
        } else {
            $status_text = "\e[31m$ubic_status\e[0m";
        }

        printf "%-15s  %s  port:%-5s  %s\n", $name, $status_text, $port, $url;
    }
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION status [service]

  321 status            # all services
  321 status zorda.web  # single service

=cut
