#!/usr/bin/perl
#
# DW::Counter
#
# Modern counter management. Used to replace AUTO_INCREMENT so that we can use
# SQLite locally, but also generally just to simplify the database logic.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2024 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Counter;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Carp qw/ confess /;

# Single-letter domain values are for livejournal-generic code.
#  - 0-9 are reserved for site-local hooks and are mapped from a long
#    (> 1 char) string passed as the $dom to a single digit by the
#    'map_global_counter_domain' hook.
#
# LJ-generic domains:
#  $dom: 'S' == style, 'P' == userpic, 'A' == stock support answer
#        'E' == external user, 'V' == vgifts,
#        'L' == poLL,  'M' == Messaging, 'H' == sHopping cart,
#        'F' == PubSubHubbub subscription id (F for Fred),
#        'K' == sitekeyword, 'I' == shopping cart Item,
#        'X' == sphinX id, 'U' == OAuth ConsUmer, 'N' == seNdmail history
#
sub alloc_global_counter {
    my ( $dom, $recurse ) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # $dom can come as a direct argument or as a string to be mapped via hook
    my $dom_unmod = $dom;
    unless ( $dom =~ /^[ESLPAHCMFKIVXUN]$/ ) {
        $dom = LJ::Hooks::run_hook( 'map_global_counter_domain', $dom );
    }
    return LJ::errobj( "InvalidParameters", params => { dom => $dom_unmod } )->cond_throw
        unless defined $dom;

    my $newmax;
    my $uid = 0;    # userid is not needed, we just use '0'

    my $rs = $dbh->do( "UPDATE counter SET max=LAST_INSERT_ID(max+1) WHERE journalid=? AND area=?",
        undef, $uid, $dom );
    if ( $rs > 0 ) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");
        return $newmax;
    }

    return undef if $recurse;

    # no prior counter rows - initialize one.
    if ( $dom eq "S" ) {
        confess 'Tried to allocate S1 counter.';
    }
    elsif ( $dom eq "P" ) {
        $newmax = 0;
        foreach my $cid (@LJ::CLUSTERS) {
            my $dbcm = LJ::get_cluster_master($cid) or return undef;
            my $max  = $dbcm->selectrow_array('SELECT MAX(picid) FROM userpic2') // 0;
            $newmax = $max if $max > $newmax;
        }
    }
    elsif ( $dom eq "E" || $dom eq "M" ) {

        # if there is no extuser or message counter row
        # start at 'ext_1'  - ( the 0 here is incremented after the recurse )
        $newmax = 0;
    }
    elsif ( $dom eq "A" ) {
        $newmax = $dbh->selectrow_array("SELECT MAX(ansid) FROM support_answers");
    }
    elsif ( $dom eq "H" ) {
        $newmax = $dbh->selectrow_array("SELECT MAX(cartid) FROM shop_carts");
    }
    elsif ( $dom eq "L" ) {

        # pick maximum id from pollowner
        $newmax = $dbh->selectrow_array("SELECT MAX(pollid) FROM pollowner");
    }
    elsif ( $dom eq 'F' ) {
        confess 'Tried to allocate PubSubHubbub counter.';
    }
    elsif ( $dom eq 'U' ) {
        $newmax = $dbh->selectrow_array("SELECT MAX(consumer_id) FROM oauth_consumer");
    }
    elsif ( $dom eq 'V' ) {
        $newmax = $dbh->selectrow_array("SELECT MAX(vgiftid) FROM vgift_ids");
    }
    elsif ( $dom eq 'N' ) {
        $newmax = $dbh->selectrow_array("SELECT MAX(msgid) FROM siteadmin_email_history");
    }
    elsif ( $dom eq 'K' ) {

        # pick maximum id from sitekeywords & interests
        my $max_sitekeys  = $dbh->selectrow_array("SELECT MAX(kwid) FROM sitekeywords");
        my $max_interests = $dbh->selectrow_array("SELECT MAX(intid) FROM interests");
        $newmax = ( $max_sitekeys // 0 ) > ( $max_interests // 0 ) ? $max_sitekeys : $max_interests;
    }
    elsif ( $dom eq 'I' ) {

        # if we have no counter, start at 0, as we have no way of determining what
        # the maximum used item id is
        $newmax = 0;
    }
    elsif ( $dom eq 'X' ) {
        my $dbsx = LJ::get_dbh('sphinx_search')
            or die "Unable to allocate counter type X unless Sphinx is configured.\n";
        $newmax = $dbsx->selectrow_array('SELECT MAX(id) FROM items_raw');
    }
    else {
        $newmax = LJ::Hooks::run_hook( 'global_counter_init_value', $dom );
        die "No alloc_global_counter initalizer for domain '$dom'"
            unless defined $newmax;
    }
    $newmax += 0;
    $dbh->do( "INSERT IGNORE INTO counter (journalid, area, max) VALUES (?,?,?)",
        undef, $uid, $dom, $newmax )
        or return LJ::errobj($dbh)->cond_throw;
    return LJ::alloc_global_counter( $dom, 1 );
}
*LJ::alloc_global_counter = \&alloc_global_counter;

# $dom: 'L' == log, 'T' == talk, 'M' == modlog, 'S' == session,
#       'R' == memory (remembrance), 'K' == keyword id,
#       'C' == pending comment
#       'V' == 'vgift', 'E' == ESN subscription id
#       'Q' == Notification Inbox,
#       'D' == 'moDule embed contents', 'I' == Import data block
#       'Z' == import status item, 'X' == eXternal account
#       'F' == filter id, 'Y' = pic/keYword mapping id
#       'A' == mediA item id, 'O' == cOllection id,
#       'N' == collectioN item id, 'B' == api key id,
#       'P' == Profile account id
#
#       remaining unused letters: G H J U W
#
sub alloc_user_counter {
    my ( $u, $dom, $opts ) = @_;
    $opts ||= {};

    ##################################################################
    # IF YOU UPDATE THIS MAKE SURE YOU ADD INITIALIZATION CODE BELOW #
    return undef unless $dom =~ /^[LTMPSRKCOVEQDIZXFYABN]$/;
    ##################################################################

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $newmax;
    my $uid = $u->userid + 0;
    return undef unless $uid;
    my $memkey = [ $uid, "auc:$uid:$dom" ];

    # in a master-master DB cluster we need to be careful that in
    # an automatic failover case where one cluster is slightly behind
    # that the same counter ID isn't handed out twice.  use memcache
    # as a sanity check to record/check latest number handed out.
    my $memmax = int( LJ::MemCache::get($memkey) || 0 );

    my $rs = $dbh->do(
        "UPDATE usercounter SET max=LAST_INSERT_ID(GREATEST(max,$memmax)+1) "
            . "WHERE journalid=? AND area=?",
        undef, $uid, $dom
    );
    if ( $rs > 0 ) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");

        # if we've got a supplied callback, lets check the counter
        # number for consistency.  If it fails our test, wipe
        # the counter row and start over, initializing a new one.
        # callbacks should return true to signal 'all is well.'
        if ( $opts->{callback} && ref $opts->{callback} eq 'CODE' ) {
            my $rv = 0;
            eval { $rv = $opts->{callback}->( $u, $newmax ) };
            if ( $@ or !$rv ) {
                $dbh->do( "DELETE FROM usercounter WHERE " . "journalid=? AND area=?",
                    undef, $uid, $dom );
                return LJ::alloc_user_counter( $u, $dom );
            }
        }

        LJ::MemCache::set( $memkey, $newmax );
        return $newmax;
    }

    if ( $opts->{recurse} ) {

        # We shouldn't ever get here if all is right with the world.
        return undef;
    }

    my $qry_map = {

        # for entries:
        'log'         => "SELECT MAX(jitemid) FROM log2     WHERE journalid=?",
        'logtext'     => "SELECT MAX(jitemid) FROM logtext2 WHERE journalid=?",
        'talk_nodeid' => "SELECT MAX(nodeid)  FROM talk2    WHERE nodetype='L' AND journalid=?",

        # for comments:
        'talk'     => "SELECT MAX(jtalkid) FROM talk2     WHERE journalid=?",
        'talktext' => "SELECT MAX(jtalkid) FROM talktext2 WHERE journalid=?",
    };

    my $consider = sub {
        my @tables = @_;
        foreach my $t (@tables) {
            my $res = $u->selectrow_array( $qry_map->{$t}, undef, $uid );
            $newmax = $res if defined $res and $res > $newmax;
        }
    };

    # Make sure the counter table is populated for this uid/dom.
    if ( $dom eq "L" ) {

        # back in the ol' days IDs were reused (because of MyISAM)
        # so now we're extra careful not to reuse a number that has
        # foreign junk "attached".  turns out people like to delete
        # each entry by hand, but we do lazy deletes that are often
        # too lazy and a user can see old stuff come back alive
        $consider->( "log", "logtext", "talk_nodeid" );
    }
    elsif ( $dom eq "T" ) {

        # just paranoia, not as bad as above.  don't think we've ever
        # run into cases of talktext without a talk, but who knows.
        # can't hurt.
        $consider->( "talk", "talktext" );
    }
    elsif ( $dom eq "M" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(modid) FROM modlog WHERE journalid=?", undef, $uid );
    }
    elsif ( $dom eq "S" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(sessid) FROM sessions WHERE userid=?", undef, $uid );
    }
    elsif ( $dom eq "R" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(memid) FROM memorable2 WHERE userid=?", undef, $uid );
    }
    elsif ( $dom eq "K" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(kwid) FROM userkeywords WHERE userid=?", undef, $uid );
    }
    elsif ( $dom eq "C" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(pendcid) FROM pendcomments WHERE jid=?", undef, $uid );
    }
    elsif ( $dom eq "V" ) {
        $newmax = $u->selectrow_array( "SELECT MAX(transid) FROM vgift_trans WHERE rcptid=?",
            undef, $uid );
    }
    elsif ( $dom eq "E" ) {
        $newmax = $u->selectrow_array( "SELECT MAX(subid) FROM subs WHERE userid=?", undef, $uid );
    }
    elsif ( $dom eq "Q" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(qid) FROM notifyqueue WHERE userid=?", undef, $uid );
    }
    elsif ( $dom eq "D" ) {
        $newmax = $u->selectrow_array( "SELECT MAX(moduleid) FROM embedcontent WHERE userid=?",
            undef, $uid );
    }
    elsif ( $dom eq "I" ) {
        $newmax =
            $dbh->selectrow_array( "SELECT MAX(import_data_id) FROM import_data WHERE userid=?",
            undef, $uid );
    }
    elsif ( $dom eq "Z" ) {
        $newmax =
            $dbh->selectrow_array( "SELECT MAX(import_status_id) FROM import_status WHERE userid=?",
            undef, $uid );
    }
    elsif ( $dom eq "X" ) {
        $newmax = $u->selectrow_array( "SELECT MAX(acctid) FROM externalaccount WHERE userid=?",
            undef, $uid );
    }
    elsif ( $dom eq "F" ) {
        $newmax = $u->selectrow_array( "SELECT MAX(filterid) FROM watch_filters WHERE userid=?",
            undef, $uid );
    }
    elsif ( $dom eq "Y" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(mapid) FROM userpicmap3 WHERE userid=?", undef, $uid );
    }
    elsif ( $dom eq "A" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(mediaid) FROM media WHERE userid = ?", undef, $uid );
    }
    elsif ( $dom eq "O" ) {
        $newmax = $u->selectrow_array( "SELECT MAX(colid) FROM collections WHERE userid = ?",
            undef, $uid );
    }
    elsif ( $dom eq "B" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(keyid) FROM api_key WHERE userid = ?", undef, $uid );
    }
    elsif ( $dom eq "N" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(colitemid) FROM collection_items WHERE userid = ?",
            undef, $uid );
    }
    elsif ( $dom eq "P" ) {
        $newmax =
            $u->selectrow_array( "SELECT MAX(account_id) FROM user_profile_accts WHERE userid = ?",
            undef, $uid );
    }
    else {
        die "No user counter initializer defined for area '$dom'.\n";
    }
    $newmax += 0;
    $dbh->do( "INSERT IGNORE INTO usercounter (journalid, area, max) VALUES (?,?,?)",
        undef, $uid, $dom, $newmax )
        or return undef;

    # The 2nd invocation of the alloc_user_counter sub should do the
    # intended incrementing.
    return LJ::alloc_user_counter( $u, $dom, { recurse => 1 } );
}
*LJ::alloc_user_counter = \&alloc_user_counter;

1;
