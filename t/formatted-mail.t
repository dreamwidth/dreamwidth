use strict;
use Test::More tests => 4;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user);

use LJ::Sendmail;
use DW::External::User;

note("simple email");
{
my $original_text=qq{Stuff's [happening].

Go to [Dreamwidth](https://www.dreamwidth.org).};

my ( $html, $plain ) = LJ::format_mail( $original_text, "foobarbaz" );
is( $html, qq{<p>Dear foobarbaz,</p>

<p>Stuff's [happening].</p>

<p>Go to <a href="https://www.dreamwidth.org">Dreamwidth</a>.</p>

<p>Regards, <br />
$LJ::SITENAMESHORT Team</p>

<p>$LJ::SITEROOT</p>
}
, "HTML version looks fine."
);

is( $plain, qq{Dear foobarbaz,

Stuff's [happening].

Go to Dreamwidth (https://www.dreamwidth.org).

Regards,  
$LJ::SITENAMESHORT Team

$LJ::SITEROOT}
, "Plain version looks fine."
);
}

note("text with username");
{
my ( $html, $plain ) = LJ::format_mail( 'Hello @world', '@foobarbaz' );
my $foobarbaz_usertag = LJ::ljuser( "foobarbaz" );
my $world_usertag = LJ::ljuser( "world" );

is( $html, qq{<p>Dear $foobarbaz_usertag,</p>

<p>Hello $world_usertag</p>

<p>Regards, <br />
$LJ::SITENAMESHORT Team</p>

<p>$LJ::SITEROOT</p>
}
, "HTML version looks fine."
);

is( $plain, qq{Dear \@foobarbaz,

Hello \@world

Regards,  
$LJ::SITENAMESHORT Team

$LJ::SITEROOT}
, "Plain version looks fine."
);
}
1;
