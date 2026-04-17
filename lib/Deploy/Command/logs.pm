package Deploy::Command::logs;

use Mojo::Base 'Deploy::Command', -signatures;

has description => 'Tail, search, or analyse service logs';
has usage => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
    my %opts;
    my @positional;
    for my $arg (@args) {
        if ($arg =~ /^--stderr$/)        { $opts{type} = 'stderr' }
        elsif ($arg =~ /^--ubic$/)       { $opts{type} = 'ubic' }
        elsif ($arg =~ /^--search=(.+)/) { $opts{search} = $1 }
        elsif ($arg =~ /^--analyse$/)    { $opts{analyse} = 1 }
        elsif ($arg =~ /^--n=(\d+)/)     { $opts{n} = $1 }
        else                             { push @positional, $arg }
    }

    my ($svc_input, $target) = $self->parse_target(@positional);
    die $self->usage unless $svc_input;
    my $name = $self->resolve_service($svc_input);
    my $transport = $self->transport_for($name, $target);

    my $log_mgr = $self->app->log_mgr_obj;
    $log_mgr->transport($transport);

    if ($opts{search}) {
        my $r = $log_mgr->search($name, $opts{search},
            $opts{type} // 'stderr', $opts{n} // 50);
        if ($r->{status} eq 'success') {
            say $_ for @{ $r->{data}{matches} // [] };
        } else {
            say "Error: $r->{message}";
        }
    } elsif ($opts{analyse}) {
        my $r = $log_mgr->analyse($name, $opts{n} // 1000);
        if ($r->{status} eq 'success') {
            my $d = $r->{data};
            my $errors   = $d->{errors}   // [];
            my $warnings = $d->{warnings} // [];
            say "Errors: " . scalar(@$errors) . "  Warnings: " . scalar(@$warnings);
            for my $e (@$errors) {
                printf "  [%d] %s\n", $e->{count}, $e->{pattern};
            }
        } else {
            say "Error: $r->{message}";
        }
    } else {
        $log_mgr->stream($name, type => $opts{type} // 'stdout');
    }
}

1;

=head1 SYNOPSIS

  Usage: APPLICATION logs <service> [target] [options]

  Options:
    --stderr        Tail stderr instead of stdout
    --ubic          Tail ubic log
    --search=TERM   Search logs for TERM
    --analyse       Show error/warning summary
    --n=NUM         Number of lines

  Examples:
    321 logs love.web
    321 logs love.web live
    321 logs love.web --stderr
    321 logs love.web live --search=ERROR

=cut
