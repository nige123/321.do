use strict;
use warnings;
use Test::More;
use Test::Mojo;

$ENV{DEPLOY_TOKEN} = 'test-token-123';
$ENV{MOJO_MODE} = 'production';

my $t = Test::Mojo->new(Mojo::File->new('bin/deploy.pl'));

# Without auth — should get 401
$t->get_ok('/services')
  ->status_is(401)
  ->json_is('/status' => 'error');

# With auth — should list services
$t->get_ok('/services', { Authorization => 'Bearer test-token-123' })
  ->status_is(200)
  ->json_is('/status' => 'success')
  ->json_has('/data');

# Service status for known service
$t->get_ok('/service/123.api/status', { Authorization => 'Bearer test-token-123' })
  ->status_is(200)
  ->json_is('/status' => 'success')
  ->json_is('/data/name' => '123.api')
  ->json_has('/data/port')
  ->json_has('/data/running');

# Unknown service
$t->get_ok('/service/nonexistent/status', { Authorization => 'Bearer test-token-123' })
  ->status_is(200)
  ->json_is('/status' => 'error')
  ->json_like('/message' => qr/Unknown service/);

done_testing;
