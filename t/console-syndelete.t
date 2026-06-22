# t/console-syndelete.t
#
# Test LJ::Console syn_delete and syn_undelete commands.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 14;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_feed);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u    = temp_user();
my $feed = temp_feed();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# both commands require the syn_edit priv
is(
    $run->( "syn_delete " . $feed->user ),
    "error: You are not authorized to run this command.",
    "syn_delete requires syn_edit priv."
);
is(
    $run->( "syn_undelete " . $feed->user ),
    "error: You are not authorized to run this command.",
    "syn_undelete requires syn_edit priv."
);
$u->grant_priv("syn_edit");
$u = LJ::load_user( $u->user );

# can only operate on syndicated accounts
my $reguser = temp_user();
is(
    $run->( "syn_delete " . $reguser->user ),
    "error: Not a syndicated account",
    "syn_delete refuses non-syndicated accounts."
);

# undelete on a non-deleted feed should fail
is(
    $run->( "syn_undelete " . $feed->user ),
    "error: Account is not deleted.",
    "Cannot undelete a feed that is not deleted."
);

# delete it
is(
    $run->( "syn_delete " . $feed->user ),
    "success: Feed account "
        . $feed->user
        . " marked as deleted; the syndication system will stop refreshing it.",
    "Deletes the feed."
);
$feed = LJ::load_user( $feed->user );
ok( $feed->is_deleted, "Feed account is now marked deleted." );

# deleting again should fail
is(
    $run->( "syn_delete " . $feed->user ),
    "error: Account is already deleted.",
    "Cannot delete an already-deleted feed."
);

# undelete it
is(
    $run->( "syn_undelete " . $feed->user ),
    "success: Feed account "
        . $feed->user
        . " restored; the syndication system will resume refreshing it.",
    "Undeletes the feed."
);
$feed = LJ::load_user( $feed->user );
ok( $feed->is_visible, "Feed account is visible again." );

# undelete resets the schedule so syndication picks it back up
my $dbh = LJ::get_db_reader();
my ( $checknext, $failcount ) =
    $dbh->selectrow_array( "SELECT checknext, failcount FROM syndicated WHERE userid=?",
    undef, $feed->id );
is( $failcount, 0, "failcount reset on undelete." );
ok( defined $checknext, "checknext is set on undelete." );

# undeleting a live feed fails
is(
    $run->( "syn_undelete " . $feed->user ),
    "error: Account is not deleted.",
    "Cannot undelete a feed that is already visible."
);

# delete then undelete a second time, to confirm it round-trips
is(
    $run->( "syn_delete " . $feed->user ),
    "success: Feed account "
        . $feed->user
        . " marked as deleted; the syndication system will stop refreshing it.",
    "Deletes the feed a second time."
);
$feed = LJ::load_user( $feed->user );
ok( $feed->is_deleted, "Feed account deleted again." );
