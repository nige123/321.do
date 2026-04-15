package Deploy::Command::hosts;

use Mojo::Base 'Deploy::Command', -signatures;
use Deploy::Hosts;

has description => 'Update /etc/hosts with dev-target hostnames';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my @hosts = $self->_dev_hosts;

    if ($args[0] && $args[0] eq '--print') {
        say for @hosts;
        return;
    }

    my $h = Deploy::Hosts->new;
    my $err = eval { $h->write(\@hosts); 0 } || $@;
    if ($err =~ /Permission denied/) {
        die "\n  /etc/hosts needs sudo. Re-run:\n  sudo -E perl bin/321.pl hosts\n";
    }
    die $err if $err;

    say "Wrote " . scalar(@hosts) . " dev host(s) to /etc/hosts:";
    say "  $_" for @hosts;
}

sub _dev_hosts ($self) {
    my $cfg = $self->config;
    my %seen;
    my @hosts;
    for my $name (@{ $cfg->service_names }) {
        my $raw = $cfg->service_raw($name);
        my $dev = $raw->{targets}{dev} // next;
        my $host = $dev->{host};
        push @hosts, $host if $host && $host ne 'localhost' && !$seen{$host}++;
    }
    return sort @hosts;
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION hosts [--print]

  Writes /etc/hosts managed block from all services' dev-target hostnames.
  Use --print to preview without writing.
  Needs sudo for the actual write.

=cut
