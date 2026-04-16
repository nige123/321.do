use strict;
use warnings;
use Test::More;
use Test::Mojo;
use MIME::Base64;

$ENV{MOJO_MODE} = 'production';

my $t = Test::Mojo->new(Mojo::File->new('bin/321.pl'));
my $auth = { Authorization => 'Basic ' . encode_base64('321:kaizen', '') };

# Unauthenticated — 401
$t->get_ok('/docs')
  ->status_is(401);

# Authenticated — 200, rendered markdown
$t->get_ok('/docs', $auth)
  ->status_is(200)
  ->content_type_like(qr{text/html})
  ->content_like(qr{<h1>.*How to use}s, 'renders top-level heading')
  ->content_like(qr{<code>.*321 install.*</code>}s, 'renders fenced code / inline code')
  ->content_like(qr{<a href="/docs" class="mission-link">DOCS</a>}, 'DOCS link present in mission bar');

done_testing;
