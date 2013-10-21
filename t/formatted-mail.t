use strict;
use Test::More tests => 2;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Test qw( temp_user);

use LJ::Sendmail;

my $original_text=<<OT;
Stuff's happening.

Go to [Dreamwidth](http://www.dreamwidth.org).

OT

my ( $html, $plain ) = LJ::format_mail( $original_text );
is( $html, <<HTML
<p>Stuff's happening.</p>

<p>Go to <a href="http://www.dreamwidth.org">Dreamwidth</a>.</p>
HTML
, "HTML version looks fine."
);

is( $plain, <<PLAIN
Stuff's happening.

Go to Dreamwidth (http://www.dreamwidth.org).

PLAIN
, "Plain version looks fine."
);

1;