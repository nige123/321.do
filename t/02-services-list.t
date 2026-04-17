use strict;
use warnings;
use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new(Mojo::File->new('bin/321.pl'));

# Should list services without auth
$t->get_ok('/services')
  ->status_is(200)
  ->json_is('/status' => 'success')
  ->json_has('/data');

# Service status for known service
$t->get_ok('/service/123.api/status')
  ->status_is(200)
  ->json_is('/status' => 'success')
  ->json_is('/data/name' => '123.api')
  ->json_has('/data/port')
  ->json_has('/data/running');

# Unknown service
$t->get_ok('/service/nonexistent/status')
  ->status_is(200)
  ->json_is('/status' => 'error')
  ->json_like('/message' => qr/Unknown service/);

done_testing;
