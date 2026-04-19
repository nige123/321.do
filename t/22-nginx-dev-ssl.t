use strict;
use warnings;
use Test::More;
use Path::Tiny qw(tempdir path);
use Deploy::Config;
use Deploy::Nginx;
use Deploy::CertProvider;

my $home_obj = tempdir(CLEANUP => 1);
my $scan_obj = tempdir(CLEANUP => 1);
my $repo_obj = tempdir(CLEANUP => 1);

my $repo = path($scan_obj, 'web.demo.do');
$repo->mkpath;
path($repo, '321.yml')->spew_utf8(<<'YAML');
name: demo.web
entry: bin/app.pl
runner: hypnotoad
dev:
  host: demo.do.dev
  port: 9400
live:
  host: demo.do
  port: 9400
YAML

# Simulate mkcert-provisioned certs in the ssl_dir
my $fake_ssl_dir = tempdir(CLEANUP => 1);
path($fake_ssl_dir, 'demo.do.dev.pem')->spew_utf8('');
path($fake_ssl_dir, 'demo.do.dev-key.pem')->spew_utf8('');

my $sites = tempdir(CLEANUP => 1);
my $cfg = Deploy::Config->new(app_home => "$home_obj", scan_dir => "$scan_obj", target => 'dev');
my $n = Deploy::Nginx->new(
    config          => $cfg,
    sites_available => "$sites",
    sites_enabled   => "$sites",
    cert_provider   => Deploy::CertProvider->new(ssl_dir => "$fake_ssl_dir"),
);

my $r = $n->generate('demo.web');
is $r->{status}, 'ok';
is $r->{ssl},    1, 'detects mkcert cert as SSL';

my $conf = path($sites, 'demo.do.dev')->slurp_utf8;
like $conf, qr{listen 443 ssl},                'ssl block present';
like $conf, qr{ssl_certificate\s+\Q$fake_ssl_dir\E/demo\.do\.dev\.pem};
like $conf, qr{ssl_certificate_key\s+\Q$fake_ssl_dir\E/demo\.do\.dev-key\.pem};
unlike $conf, qr{/etc/letsencrypt}, 'no letsencrypt paths in dev config';

done_testing;
