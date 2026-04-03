use strict;
use warnings;
use Test::More;
use Test::Mojo;

$ENV{DEPLOY_TOKEN} = 'test-token-123';
$ENV{MOJO_MODE} = 'production';

my $t = Test::Mojo->new(Mojo::File->new('bin/321.pl'));

# Deploy without auth
$t->post_ok('/service/123.api/deploy')
  ->status_is(401);

# Deploy unknown service
$t->post_ok('/service/nonexistent/deploy', { Authorization => 'Bearer test-token-123' })
  ->status_is(200)
  ->json_is('/status' => 'error')
  ->json_like('/message' => qr/Unknown service/);

# Wrong token
$t->post_ok('/service/123.api/deploy', { Authorization => 'Bearer wrong-token' })
  ->status_is(401)
  ->json_is('/status' => 'error');

done_testing;
