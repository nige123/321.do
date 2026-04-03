package Deploy::Config;

use Mojo::Base -base, -signatures;
use YAML::XS qw(LoadFile);
use Path::Tiny qw(path);
use Mojo::File qw(curfile);

has 'app_home' => sub { curfile->dirname->dirname->dirname };
has 'config'   => sub ($self) { $self->_load_config };
has 'services' => sub ($self) { $self->config->{services} // {} };

sub _load_config ($self) {
    my $file = path($self->app_home, 'services.yml');
    die "services.yml not found at $file\n" unless $file->exists;
    return LoadFile($file->stringify);
}

sub service ($self, $name) {
    my $svc = $self->services->{$name};
    return undef unless $svc;
    return { %$svc, name => $name };
}

sub service_names ($self) {
    return [ sort keys %{ $self->services } ];
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

sub deploy_token ($self) {
    # Check env var first, then file
    return $ENV{DEPLOY_TOKEN} if $ENV{DEPLOY_TOKEN};

    my $token_file = path($self->app_home, 'deploy_token.txt');
    return undef unless $token_file->exists;

    my $token = $token_file->slurp_utf8;
    $token =~ s/\s+$//;
    return $token;
}

1;
