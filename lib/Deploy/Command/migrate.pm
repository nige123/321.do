package Deploy::Command::migrate;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Run bin/migrate for a service';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    die $self->usage unless @args;
    my $name = $self->resolve_service($args[0]);
    say "Migrating $name";

    my $r = $self->svc_mgr->migrate($name);
    for my $s (@{ $r->{data}{steps} }) {
        my $ok = ref $s->{success} ? ${$s->{success}} : $s->{success};
        printf "  [%s] %s\n", ($ok ? 'OK' : 'FAIL'), $s->{step};
        say "  $s->{output}" if $s->{output} && !$ok;
    }
    say $r->{status} eq 'success' ? "  $r->{message}" : "  FAILED: $r->{message}";
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION migrate <service>

  Run bin/migrate in the service repo. No-op if bin/migrate doesn't exist.

=cut
