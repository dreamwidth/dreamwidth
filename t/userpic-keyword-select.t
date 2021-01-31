# t/userpic-keyword-select.t
#
# Test the LJ::User::icon_keyword_menu() function, which is used to build
# a select element for choosing an icon for a post or comment.
#
# Authors:
#      Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );

use FindBin qw($Bin);
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

# preload userpics so we don't have to read the file hundreds of times
open( my $fh, 'good.png' ) or die $!;
my $ICON1 = do { local $/; <$fh> };

open( my $fh2, 'good.jpg' ) or die $!;
my $ICON2 = do { local $/; <$fh2> };

note("called for user with...");
{
    my $u = temp_user();
    LJ::set_remote($u);
    my $icons;

    note("  ...no icons");
    $icons = $u->icon_keyword_menu;
    my $empty = [];
    is_deeply( $icons, $empty, "No user, empty icons list" );

    note("  ...one icon, one keyword, no default");
    my $icon1 = LJ::Userpic->create( $u, data => \$ICON1 );
    $icon1->set_keywords("rad pic");
    $icons = $u->icon_keyword_menu;
    is( @$icons, 2, "Select would have two items" );
    ok(
        defined $icons->[0]->{data}->{url},
        "Default icon slot still has a URL for a placeholder image, even though there's no default"
    );

    note("  ...two icons, five keywords, yes default");
    my $icon2 = LJ::Userpic->create( $u, data => \$ICON2 );
    $icon1->set_keywords("b, z");
    $icon2->set_keywords("a, c, y");
    $icon1->make_default;
    $icons = $u->icon_keyword_menu;
    is( @$icons, 6, "Select would have six items" );
    my @keywords   = map  { $_->{value} } @$icons;
    my $b_keywords = grep { $_ eq 'b' } @keywords;
    is( $b_keywords, 1, "The 'value' key of each hashref contains the keyword" );
    is( $icons->[0]->{data}->{url},
        $icon1->url, "First icon slot's URL matches the real default icon's URL" );
}
