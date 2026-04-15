package Deploy::Command::generate;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Regenerate ubic service files';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my $results = $self->ubic->generate_all;
    for my $r (@$results) {
        say "  $r->{name}: $r->{path}";
    }
    my $links = $self->ubic->install_symlinks;
    for my $l (@$links) {
        say "  symlink: $l->{dest} -> $l->{source}";
    }
    # Update /etc/hosts dev block (best-effort — skip if no sudo)
    require Deploy::Hosts;
    my (%_seen, @dev_hosts);
    for my $name (@{ $self->config->service_names }) {
        my $raw = $self->config->service_raw($name);
        my $dev = $raw->{targets}{dev} // next;
        push @dev_hosts, $dev->{host} if $dev->{host} && $dev->{host} ne 'localhost' && !$_seen{$dev->{host}}++;
    }
    if (@dev_hosts && -w '/etc/hosts') {
        Deploy::Hosts->new->write([sort @dev_hosts]);
        say "  /etc/hosts updated (" . scalar(@dev_hosts) . " dev hosts)";
    } elsif (@dev_hosts) {
        say "  /etc/hosts not writable - run 'sudo -E perl bin/321.pl hosts' to update";
    }
    say "Done.";
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION generate

  Regenerate all ubic service files from config.

=cut
