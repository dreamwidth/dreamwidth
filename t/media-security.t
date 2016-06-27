# t/media-security.t
#
# Test DW::Media access permissions.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);
use DW::Media;

plan tests => 15;

my $u1 = temp_user();
my $u2 = temp_user();

ok( ! $u1->trusts( $u2 ), "Viewer does not have access to poster" );

# Use an image from dw-free for testing purposes.

my $obj = DW::Media->upload_media(
    user     => $u1,
    file     => "htdocs/img/videoplaceholder.png",
    security => "friends",  # make sure this doesn't fail
);

ok( $obj, 'Successfully created DW::Media object from test image.' );

if ( defined $obj ) {
    # first test public security
    $obj->set_security( security => "public" );

    ok( $obj->visible_to( $u2 ), "Viewer can see public image" );

    # then private
    $obj->set_security( security => "private" );

    ok( ! $obj->visible_to( $u2 ), "Viewer can't see private image" );

    # test basic access
    $obj->set_security( security => "usemask", allowmask => 1 );

    ok( ! $obj->visible_to( $u2 ), "Untrusted user can't see access image" );

    # set up trust edge
    $u1->add_edge( $u2, trust => { nonotify => 1 } );

    ok( $u1->trusts( $u2 ), "Viewer has access to poster" );

    ok( $obj->visible_to( $u2 ), "Trusted user can see access image" );

    # note that undefined or zero value for allowmask will fail
    $obj->set_security( security => "usemask", allowmask => 0 );

    ok( ! $obj->visible_to( $u2 ), "Trusted user can't view if no allowmask" );

    $obj->set_security( security => "usemask", allowmask => undef );

    ok( ! $obj->visible_to( $u2 ), "Trusted user can't view undef allowmask" );

    # make sure "friends" security works (newpost_minsecurity still uses this)
    $obj->set_security( security => "friends" );

    ok( $obj->visible_to( $u2 ), "Trusted user can view friends security" );

    # create an access group and add the viewer to it
    my $groupid = $u1->create_trust_group( groupname => 'testing' );
    $u1->edit_trustmask( $u2, add => $groupid );

    ok( $obj->visible_to( $u2 ), "Member of group can view friends security" );

    # calculate the trustmask (group membership + basic access)
    my $mask = $groupid << 1;
    ok( $u1->trustmask( $u2 ) == $mask + 1, 'Validate calculated trustmask' );

    # test access group visibility
    $obj->set_security( security => "usemask", allowmask => $mask );

    ok( $obj->visible_to( $u2 ), "Member of group can view masked image" );
    ok( $obj->visible_to( $u1 ), "Owner of image can view masked image" );

    $u1->edit_trustmask( $u2, remove => $groupid );
    ok( ! $obj->visible_to( $u2 ), "Non-member of group can't see image" );

    # cleanup and exit

    $obj->delete;
}

1;
