# t/console-screen.t
#
# Tests the screen_set and screen_unset console commands, including refusing to
# automatically screen account types that cannot leave comments.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 15;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw( temp_user temp_comm temp_feed );
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u        = temp_user();
my $person   = temp_user();
my $identity = temp_user( journaltype => 'I' );
my $comm     = temp_comm();
my $comm2    = temp_comm();
my $feed     = temp_feed();

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

my $screened = sub {
    my ( $target, $journal ) = @_;
    return
          "success: Comments from user "
        . $target->user . " in "
        . $journal->user
        . " will now be automatically screened.";
};

my $rejected = sub {
    my ( $target, $type ) = @_;
    return
          "error: "
        . $target->user
        . " is a $type account and cannot leave comments.\n"
        . "Only personal and OpenID accounts can be selectively screened.\n"
        . "To screen anonymous comments, use the Comment Screening setting.";
};

$refresh->();

# Personal and OpenID accounts can comment, so they can be screened.
is(
    $run->( "screen_set " . $person->user ),
    $screened->( $person, $u ),
    "personal account can be screened"
);
ok( $u->has_autoscreen($person), "personal account is screened" );
is(
    $run->( "screen_set " . $identity->user ),
    $screened->( $identity, $u ),
    "OpenID account can be screened"
);
ok( $u->has_autoscreen($identity), "OpenID account is screened" );

# Communities and feeds can't comment; refuse instead of storing a useless relationship.
is(
    $run->( "screen_set " . $comm->user ),
    $rejected->( $comm, 'community' ),
    "community account is rejected"
);
ok( !$u->has_autoscreen($comm), "community account is not screened" );
is(
    $run->( "screen_set " . $feed->user ),
    $rejected->( $feed, 'syndicated' ),
    "feed account is rejected"
);
ok( !$u->has_autoscreen($feed), "feed account is not screened" );

# The same rule applies when screening in a community the remote user maintains.
is( LJ::set_rel( $comm, $u, 'A' ), '1', "set user as maintainer" );
$refresh->();
is(
    $run->( "screen_set " . $comm2->user . " from " . $comm->user ),
    $rejected->( $comm2, 'community' ),
    "community account is rejected from a maintained community"
);
ok( !$comm->has_autoscreen($comm2), "community account is not screened in the community" );
is(
    $run->( "screen_set " . $person->user . " from " . $comm->user ),
    $screened->( $person, $comm ),
    "personal account can be screened from a maintained community"
);

# screen_unset must still clear relationships stored before screen_set refused them.
is( LJ::set_rel( $u, $comm2, 'S' ), '1', "store an existing community screen" );
$refresh->();
is(
    $run->( "screen_unset " . $comm2->user ),
    "success: Comments from user "
        . $comm2->user . " in "
        . $u->user
        . " will no longer be automatically screened.",
    "community account can still be unscreened"
);
ok( !$u->has_autoscreen($comm2), "community account screen is removed" );
