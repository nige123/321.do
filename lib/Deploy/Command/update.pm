package Deploy::Command::update;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Update: git pull + cpanm + migrate (no restart)';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my ($svc_input, $target) = $self->parse_target(@args);
    die $self->usage unless $svc_input;
    my $name = $self->resolve_service($svc_input);
    my $transport = $self->transport_for($name, $target);

    my $svc_mgr = $self->svc_mgr;
    $svc_mgr->transport($transport);
    $self->config->target($target);
    my $r = $svc_mgr->update($name);
    for my $step (@{ $r->{data}{steps} // [] }) {
        my $ok = $self->step_ok($step);
        printf "  [%s] %s\n", ($ok ? 'OK' : 'FAIL'), $step->{step};
    }
    say "  $r->{message}" if $r->{message};
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION update <service>

  git pull + cpanm + bin/migrate (if present). No restart.

=cut
