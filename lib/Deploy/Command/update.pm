package Deploy::Command::update;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Update: git pull + cpanm + migrate (no restart)';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    die $self->usage unless @args;
    my $name = $self->resolve_service($args[0]);
    say "Updating $name (pull + deps + migrate, no restart)";

    my $r = $self->svc_mgr->update($name);
    for my $s (@{ $r->{data}{steps} }) {
        my $ok = ref $s->{success} ? ${$s->{success}} : $s->{success};
        printf "  [%s] %s\n", ($ok ? 'OK' : 'FAIL'), $s->{step};
    }
    say $r->{status} eq 'success' ? "  $name updated." : "  FAILED: $r->{message}";
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION update <service>

  git pull + cpanm + bin/migrate (if present). No restart.

=cut
