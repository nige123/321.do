package Deploy::Command::dash;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Start the local web dashboard';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my $port = 9321;
    say "Starting 321 dashboard on http://127.0.0.1:$port";
    say "Press Ctrl-C to stop.\n";
    $self->app->start('daemon', '-l', "http://127.0.0.1:$port");
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION dash

  Starts the local 321 web dashboard on port 9321.

=cut
