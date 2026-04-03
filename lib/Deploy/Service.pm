package Deploy::Service;

use Mojo::Base -base, -signatures;
use Mojo::IOLoop;
use Path::Tiny qw(path);
use POSIX qw(strftime);

has 'config';  # Deploy::Config instance
has 'log';     # Mojo::Log instance

sub status ($self, $name) {
    my $svc = $self->config->service($name);
    return undef unless $svc;

    my $pid = $self->_get_pid($svc);
    my $git_sha = $self->_git_sha($svc->{repo});
    my $port_ok = $self->_check_port($svc->{port});

    return {
        name    => $name,
        pid     => $pid,
        port    => $svc->{port},
        running => ($pid && $port_ok) ? \1 : \0,
        git_sha => $git_sha,
        repo    => $svc->{repo},
        branch  => $svc->{branch},
    };
}

sub all_status ($self) {
    my @results;
    for my $name (@{ $self->config->service_names }) {
        push @results, $self->status($name);
    }
    return \@results;
}

sub deploy ($self, $name) {
    my $svc = $self->config->service($name);
    return { status => 'error', message => "Unknown service: $name" } unless $svc;

    my @steps;
    my $repo = $svc->{repo};
    my $branch = $svc->{branch} // 'master';
    my $bin = $svc->{bin};
    my $perlbrew = $svc->{perlbrew};

    # Step 1: git fetch + reset
    my ($ok, $out) = $self->_run_in_dir($repo, "git fetch origin && git reset --hard origin/$branch");
    push @steps, { step => 'git_pull', success => $ok, output => $out };
    return $self->_deploy_result($name, 'error', 'Git pull failed', \@steps) unless $ok;

    # Step 2: install deps
    my $cpanm_cmd = 'cpanm --notest --installdeps .';
    if ($perlbrew) {
        $cpanm_cmd = "bash -lc 'source ~/perl5/perlbrew/etc/bashrc && perlbrew use $perlbrew && $cpanm_cmd'";
    }
    ($ok, $out) = $self->_run_in_dir($repo, $cpanm_cmd);
    push @steps, { step => 'cpanm', success => $ok, output => $out };
    # cpanm failure is a warning, not fatal — deps may already be installed
    $self->log->warn("cpanm failed for $name: $out") unless $ok;

    # Step 3: load secrets + env
    my $secrets = $self->config->load_secrets($name);
    my $svc_env = $svc->{env} // {};
    my %env = (%$svc_env, %$secrets);
    push @steps, { step => 'load_secrets', success => \1, output => scalar(keys %env) . ' env vars loaded' };

    # Step 4: hypnotoad restart
    my $env_prefix = join(' ', map { "$_='$env{$_}'" } sort keys %env);
    my $hypnotoad_cmd;
    if ($perlbrew) {
        $hypnotoad_cmd = "bash -lc 'source ~/perl5/perlbrew/etc/bashrc && perlbrew use $perlbrew && $env_prefix hypnotoad $bin'";
    } else {
        $hypnotoad_cmd = "$env_prefix hypnotoad $bin";
    }
    ($ok, $out) = $self->_run_in_dir($repo, $hypnotoad_cmd);
    push @steps, { step => 'hypnotoad_restart', success => $ok, output => $out };
    return $self->_deploy_result($name, 'error', 'Hypnotoad restart failed', \@steps) unless $ok;

    # Step 5: verify port is responding
    sleep 2;
    my $port_ok = $self->_check_port($svc->{port});
    push @steps, { step => 'port_check', success => $port_ok ? \1 : \0, output => $port_ok ? "Port $svc->{port} responding" : "Port $svc->{port} not responding" };

    # Log the deploy
    $self->_log_deploy($name, \@steps);

    my $final_status = $port_ok ? 'success' : 'error';
    my $final_msg = $port_ok ? "Deployed $name successfully" : "Deployed $name but port check failed";
    return $self->_deploy_result($name, $final_status, $final_msg, \@steps);
}

sub _deploy_result ($self, $name, $status, $message, $steps) {
    return {
        status  => $status,
        message => $message,
        data    => {
            service => $name,
            steps   => $steps,
            timestamp => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
        },
    };
}

sub _run_in_dir ($self, $dir, $cmd) {
    $self->log->info("Running: cd $dir && $cmd");
    my $output = eval {
        local $SIG{ALRM} = sub { die "Command timed out\n" };
        alarm 120;
        my $result = `cd \Q$dir\E && $cmd 2>&1`;
        alarm 0;
        $result;
    };
    alarm 0;
    if ($@) {
        return (0, "Error: $@");
    }
    return ($? == 0, $output // '');
}

sub _get_pid ($self, $svc) {
    my $pidfile = path($svc->{repo}, 'hypnotoad.pid');
    return undef unless $pidfile->exists;
    my $pid = $pidfile->slurp;
    $pid =~ s/\s+//g;
    return undef unless $pid =~ /^\d+$/;
    # Check if process is actually running
    return kill(0, $pid) ? $pid : undef;
}

sub _git_sha ($self, $repo) {
    my $sha = `cd \Q$repo\E && git rev-parse --short HEAD 2>/dev/null`;
    chomp $sha if $sha;
    return $sha || undef;
}

sub _check_port ($self, $port) {
    return 0 unless $port;
    eval {
        require IO::Socket::INET;
        my $sock = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
            Proto    => 'tcp',
            Timeout  => 1,
        );
        return 0 unless $sock;
        close $sock;
    };
    return $@ ? 0 : 1;
}

sub _log_deploy ($self, $name, $steps) {
    my $dir = path('/tmp/321.do/deploys');
    $dir->mkpath;
    my $timestamp = strftime('%Y%m%d-%H%M%S', localtime);
    my $logfile = $dir->child("$name-$timestamp.log");

    my @lines;
    push @lines, "Deploy: $name at $timestamp";
    push @lines, "=" x 40;
    for my $step (@$steps) {
        my $ok = ref $step->{success} ? ${$step->{success}} : $step->{success};
        push @lines, sprintf("[%s] %s", $ok ? 'OK' : 'FAIL', $step->{step});
        push @lines, "  $step->{output}" if $step->{output};
    }
    $logfile->spew_utf8(join("\n", @lines) . "\n");
    $self->log->info("Deploy log written to $logfile");
}

1;
