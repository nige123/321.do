package Deploy::Config;

use Mojo::Base -base, -signatures;
use Path::Tiny qw(path);
use Mojo::File qw(curfile);
use Deploy::Manifest;

has 'app_home'  => sub { $ENV{APP_HOME} // curfile->dirname->dirname->dirname };
has 'scan_dir'  => sub { $ENV{SCAN_DIR} // '/home/s3' };
has 'target'    => 'dev';
has '_services' => sub ($self) { $self->_load_all };

sub reload ($self) {
    $self->_services($self->_load_all);
    return $self;
}

sub _load_all ($self) {
    my $base = path($self->scan_dir);
    return {} unless $base->exists;

    my %services;
    for my $dir (sort $base->children) {
        next unless $dir->is_dir;
        my $manifest = Deploy::Manifest->load($dir);
        next unless $manifest;
        $services{ $manifest->{name} } = $manifest;
    }
    return \%services;
}

sub services ($self) {
    return $self->_services;
}

sub service ($self, $name) {
    my $manifest = $self->_services->{$name};
    return undef unless $manifest;
    return $self->_resolve($name, $manifest);
}

sub _resolve ($self, $name, $manifest) {
    my $target_name = $self->target;
    my $target = $manifest->{targets}{$target_name} // {};

    my $runner = $target->{runner} // $manifest->{runner} // 'hypnotoad';

    return {
        name         => $name,
        repo         => $manifest->{repo},
        branch       => $manifest->{branch} // 'master',
        bin          => $manifest->{entry},
        mode         => $runner eq 'morbo' ? 'development' : 'production',
        runner       => $runner,
        port         => $target->{port},
        host         => $target->{host} // 'localhost',
        apt_deps     => $manifest->{apt_deps} // [],
        health       => $manifest->{health} // '/health',
        env_required => $manifest->{env_required} // {},
        env_optional => $manifest->{env_optional} // {},
        logs         => {
            stdout => "/tmp/$name.stdout.log",
            stderr => "/tmp/$name.stderr.log",
            ubic   => "/tmp/$name.ubic.log",
        },
        ($manifest->{favicon}  ? (favicon  => $manifest->{favicon})  : ()),
        ($target->{ssh}        ? (ssh      => $target->{ssh})        : ()),
        ($target->{ssh_key}    ? (ssh_key  => $target->{ssh_key})    : ()),
        ($target->{docs}       ? (docs     => $target->{docs})       : ()),
        ($target->{admin}      ? (admin    => $target->{admin})      : ()),
        ($manifest->{perl}     ? (perlbrew => $manifest->{perl})     : ()),
        ($target->{env}        ? (env      => $target->{env})        : (env => {})),
    };
}

sub service_names ($self) {
    return [ sort keys %{ $self->_services } ];
}

sub service_raw ($self, $name) {
    return $self->_services->{$name};
}

sub load_secrets ($self, $name) {
    my $env_file = path($self->app_home, 'secrets', "$name.env");
    return {} unless $env_file->exists;

    my %env;
    for my $line ($env_file->lines_utf8({ chomp => 1 })) {
        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;
        if ($line =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/) {
            $env{$1} = $2;
        }
    }
    return \%env;
}

sub dev_hostnames ($self) {
    my %seen;
    my @hosts;
    for my $name (@{ $self->service_names }) {
        my $manifest = $self->_services->{$name};
        my $dev = $manifest->{targets}{dev} or next;
        my $h = $dev->{host} or next;
        next if $h eq 'localhost';
        push @hosts, $h unless $seen{$h}++;
    }
    return [ sort @hosts ];
}

1;
