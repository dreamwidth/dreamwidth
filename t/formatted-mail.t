use strict;
use Test::More tests => 2;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Test qw( temp_user);

use LJ::Sendmail;

my $original_text=qq{Stuff's [happening].

Go to [Dreamwidth](http://www.dreamwidth.org).};

my ( $html, $plain ) = LJ::format_mail( $original_text, "foobarbaz" );
is( $html, qq{<p>Dear foobarbaz,</p>

<p>Stuff's [happening].</p>

<p>Go to <a href="http://www.dreamwidth.org">Dreamwidth</a>.</p>

<p>Regards, <br />
$LJ::SITENAMESHORT Team</p>

<p>$LJ::SITEROOT</p>
}
, "HTML version looks fine."
);

is( $plain, qq{Dear foobarbaz,

Stuff's [happening].

Go to Dreamwidth (http://www.dreamwidth.org).

Regards,  
$LJ::SITENAMESHORT Team

$LJ::SITEROOT}
, "Plain version looks fine."
);

1;
