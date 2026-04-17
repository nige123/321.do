package Deploy::Command::list;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'List all services';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my (undef, $target) = $self->parse_target(@args);
    my $cfg = $self->config;
    $cfg->target($target);

    for my $name (@{ $cfg->service_names }) {
        my $svc = $cfg->service($name);
        printf "  %-20s %-5s %-12s port %s\n",
            $name,
            uc($svc->{mode} eq 'development' ? 'DEV' : 'LIVE'),
            $svc->{runner},
            $svc->{port} // '-';
    }
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION list

  321 list   # show all services with mode, runner, port

=cut
