package Deploy::Logs;

use Mojo::Base -base, -signatures;
use Path::Tiny qw(path);

has 'config';     # Deploy::Config instance
has 'transport';  # Deploy::Local or Deploy::SSH instance (optional)

sub tail ($self, $name, $type = 'stderr', $n = 100) {
    my $logfile = $self->_logfile($name, $type);
    return { status => 'error', message => "Unknown service or log type" } unless $logfile;

    if ($self->transport) {
        my $r = $self->transport->run("tail -n $n $logfile");
        return {
            status => $r->{ok} ? 'success' : 'error',
            data   => { lines => [split /\n/, $r->{output}], type => $type, file => $logfile },
        };
    }

    return { status => 'error', message => "Log file not found: $logfile" } unless -f $logfile;

    my @lines = path($logfile)->lines_utf8({ chomp => 1 });
    my $total = scalar @lines;
    $n = $total if $n > $total;
    my @tail = @lines[$total - $n .. $total - 1];

    return {
        status  => 'success',
        message => "Last $n lines of $type log for $name",
        data    => {
            service => $name,
            type    => $type,
            lines   => \@tail,
            total   => $total,
            showing => scalar @tail,
        },
    };
}

sub search ($self, $name, $query, $type = 'stderr', $n = 50) {
    my $logfile = $self->_logfile($name, $type);
    return { status => 'error', message => "Unknown service or log type" } unless $logfile;

    if ($self->transport) {
        my $r = $self->transport->run("grep -n " . quotemeta($query) . " $logfile | tail -n $n");
        my @matches;
        for my $line (split /\n/, $r->{output} // '') {
            if ($line =~ /^(\d+):(.*)/) {
                push @matches, { line => $1 + 0, text => $2 };
            }
        }
        return {
            status  => 'success',
            message => scalar(@matches) . " matches for '$query' in $type log",
            data    => {
                service => $name,
                type    => $type,
                query   => $query,
                matches => \@matches,
                total   => scalar @matches,
            },
        };
    }

    return { status => 'error', message => "Log file not found: $logfile" } unless -f $logfile;

    my @lines = path($logfile)->lines_utf8({ chomp => 1 });
    my @matches;
    my $line_num = 0;
    for my $line (@lines) {
        $line_num++;
        if (index(lc($line), lc($query)) >= 0) {
            push @matches, { line => $line_num, text => $line };
            last if @matches >= $n;
        }
    }

    return {
        status  => 'success',
        message => scalar(@matches) . " matches for '$query' in $type log",
        data    => {
            service => $name,
            type    => $type,
            query   => $query,
            matches => \@matches,
            total   => scalar @matches,
        },
    };
}

sub stream ($self, $name, %opts) {
    my $type = $opts{type} // 'stdout';
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    my $logfile = $svc->{logs}{$type};
    return { status => 'error', message => "No $type log configured for $name" } unless $logfile;

    say "Streaming $type for $name: $logfile";
    say "Press Ctrl-C to stop.\n";
    $self->transport->stream("tail -f $logfile", on_line => $opts{on_line});
}

sub analyse ($self, $name, $n = 1000) {
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    my $logs = $svc->{logs} // {};
    my @all_lines;

    # Read from all available log files
    for my $type (sort keys %$logs) {
        my $file = $logs->{$type};
        next unless -f $file;
        my @lines = path($file)->lines_utf8({ chomp => 1 });
        my $total = scalar @lines;
        my $start = $total > $n ? $total - $n : 0;
        push @all_lines, @lines[$start .. $total - 1];
    }

    my (%errors, %warnings, %status_codes);
    my $request_count = 0;
    my $earliest_ts;
    my $latest_ts;

    for my $line (@all_lines) {
        # Count errors
        if ($line =~ /\b(error|fatal|die|exception)\b/i) {
            my $pattern = _normalize_pattern($line);
            $errors{$pattern}{count}++;
            $errors{$pattern}{sample} //= $line;
            $errors{$pattern}{last_seen} = _extract_timestamp($line) // 'unknown';
        }

        # Count warnings
        if ($line =~ /\bwarn(?:ing)?\b/i) {
            my $pattern = _normalize_pattern($line);
            $warnings{$pattern}{count}++;
            $warnings{$pattern}{sample} //= $line;
            $warnings{$pattern}{last_seen} = _extract_timestamp($line) // 'unknown';
        }

        # Count HTTP status codes
        if ($line =~ /\b[A-Z]+\s+\S+\s+HTTP\/[\d.]+"\s+(\d{3})\b/ ||
            $line =~ /\s(\d{3})\s/) {
            my $code = $1;
            if ($code >= 100 && $code <= 599) {
                $status_codes{$code}++;
                $request_count++;
            }
        }
    }

    # Format errors and warnings as arrays
    my @error_list = map {
        { pattern => $_, count => $errors{$_}{count}, lastSeen => $errors{$_}{last_seen}, sample => $errors{$_}{sample} }
    } sort { $errors{$b}{count} <=> $errors{$a}{count} } keys %errors;

    my @warning_list = map {
        { pattern => $_, count => $warnings{$_}{count}, lastSeen => $warnings{$_}{last_seen}, sample => $warnings{$_}{sample} }
    } sort { $warnings{$b}{count} <=> $warnings{$a}{count} } keys %warnings;

    return {
        status  => 'success',
        message => "Analysis of last $n lines for $name",
        data    => {
            service      => $name,
            period       => "last $n lines",
            errors       => \@error_list,
            warnings     => \@warning_list,
            statusCodes  => \%status_codes,
            requestCount => $request_count,
        },
    };
}

sub _logfile ($self, $name, $type) {
    my $svc = $self->config->service($name);
    return undef unless $svc;
    return $svc->{logs}{$type};
}

sub _normalize_pattern ($line) {
    # Strip timestamps and variable data to group similar errors
    my $pattern = $line;
    $pattern =~ s/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\S*//g;  # timestamps
    $pattern =~ s/0x[0-9a-f]+/0xXXX/gi;                             # hex addresses
    $pattern =~ s/\b\d{5,}\b/NNN/g;                                  # long numbers
    $pattern =~ s/^\s+//;
    # Truncate for grouping
    $pattern = substr($pattern, 0, 80) if length($pattern) > 80;
    return $pattern;
}

sub _extract_timestamp ($line) {
    if ($line =~ /(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})/) {
        return $1;
    }
    return undef;
}

1;
