# t/settings.t
#
# Test LJ::Setting::EmailFormat and LJ::Setting::Name
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by

# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 9;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Lang;
use LJ::HTMLControls;

use LJ::Setting::EmailFormat;
use LJ::Setting::Name;

my $fmtkey  = LJ::Setting::EmailFormat->pkgkey;
my $namekey = LJ::Setting::Name->pkgkey;
is( $fmtkey, "LJ__Setting__EmailFormat_", "key check" );

my $u = LJ::load_user("system");

is( LJ::Setting->error_map( $u, {}, () ), undef, "no errors for no settings" );
is( LJ::Setting::EmailFormat->error_map( $u, { "${fmtkey}emailformat" => "Y" } ),
    undef, "no errors for emailformat with 'Y'" );
is( LJ::Setting::EmailFormat->error_map( $u, { "${fmtkey}emailformat" => "N" } ),
    undef, "no errors for emailformat with 'N'" );
isnt( LJ::Setting::EmailFormat->error_map( $u, { "${fmtkey}emailformat" => "X" } ),
    undef, "errors for emailformat with 'X'" );

{
    my @settings = qw(LJ::Setting::Name LJ::Setting::EmailFormat);
    my $errmap;
    local $LJ::T_FAKE_SETTINGS_RULES = 1;
    my %post = (
        "${namekey}txt"        => "this is `bad",
        "${fmtkey}emailformat" => "Y",
    );
    $errmap = LJ::Setting->error_map( $u, \%post, @settings );
    ok( $errmap, "got errors" );

    my $html;
    $html = LJ::Setting::Name->as_html( $u, $errmap, \%post );
    like( $html, qr/this is .bad/, "got posted value back" );
    like( $html, qr/T-FAKE-ERROR/, "got inline error" );

}

# and this time okay:
{
    my @settings = qw(LJ::Setting::Name LJ::Setting::EmailFormat);
    my $errmap;
    my %post = (
        "${namekey}txt"        => "the system user",
        "${fmtkey}emailformat" => "Y",
    );
    $errmap = LJ::Setting->error_map( $u, \%post, @settings );
    ok( !$errmap, "no errors" );
}

#    use Data::Dumper;
#    print Dumper($errmap);

