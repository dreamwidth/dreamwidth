# t/directory-updatetime.t
#
# Posting an entry must queue a refresh of the directory record for the journal
# that was posted to, so that the directory's "updated in the last N days"
# filter and its sort order see the new update time. Community posts are the
# case that matters: the poster and the journal are different accounts.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );
use LJ::UserSearch::MetaUpdater;

my $poster = temp_user();
my $comm   = temp_comm();
my @uids   = ( $poster->id, $comm->id );

my $dbh = LJ::get_db_writer();
my $dbs =
    defined $LJ::USERSEARCH_DB_WRITER
    ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER)
    : $dbh;

END {
    $dbs->do( "DELETE FROM usersearch_packdata WHERE userid IN (?, ?)", undef, @uids )
        if $dbs && @uids;
}

# true if the directory updater will rebuild this account's record
my $queued = sub {
    my $u = shift;
    return $dbs->selectrow_array(
        "SELECT good_until <= UNIX_TIMESTAMP() FROM usersearch_packdata WHERE userid=?",
        undef, $u->id );
};

# the update time stored in this account's directory record
my $packed_updatetime = sub {
    my $u      = shift;
    my $packed = $dbs->selectrow_array( "SELECT packed FROM usersearch_packdata WHERE userid=?",
        undef, $u->id );
    return unpack( "N", $packed );
};

# start with current directory records for both accounts, as the
# background updater would leave them
LJ::UserSearch::MetaUpdater::update_user($_) foreach $poster, $comm;
ok( !$queued->($comm), "community directory record starts out current" );

# post to the community
$poster->t_post_fake_comm_entry($comm);
ok( $queued->($comm), "posting to a community queues its directory record for refresh" );

my $comm_timeupdate =
    $dbh->selectrow_array( "SELECT UNIX_TIMESTAMP(timeupdate) FROM userusage WHERE userid=?",
    undef, $comm->id );
ok( $comm_timeupdate, "community has an update time after the post" );

# the background updater then stores the community's new update time
LJ::UserSearch::MetaUpdater::update_user($comm);
is( $packed_updatetime->($comm),
    $comm_timeupdate, "refreshed community record carries the new update time" );

# posting to your own journal still queues your own record
LJ::UserSearch::MetaUpdater::update_user($poster);
ok( !$queued->($poster), "personal directory record starts out current" );
$poster->t_post_fake_entry;
ok( $queued->($poster), "posting to your own journal queues your directory record for refresh" );
