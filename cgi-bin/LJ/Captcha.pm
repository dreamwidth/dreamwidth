#!/usr/bin/perl
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

package LJ::Captcha;
use strict;
use LJ::Blob qw{};

use lib "$LJ::HOME/cgi-bin";
require "ljlib.pl";

### get_visual_id() -> ( $capid, $anum )
sub get_visual_id { get_id('image') }
sub get_audio_id { get_id('audio') }

### get_id( $type ) -> ( $capid, $anum )
sub get_id
{
    my ( $type ) = @_;
    my (
        $dbh,                   # Database handle (writer)
        $sql,                   # SQL statement
        $row,                   # Row arrayref
        $capid,                 # Captcha id
        $anum,                  # Unseries-ifier number
        $issuedate,             # unixtime of issue
       );

    # Fetch database handle and lock the captcha table
    $dbh = LJ::get_db_writer()
                or return LJ::error( "Couldn't fetch a db writer." );
    $dbh->selectrow_array("SELECT GET_LOCK('get_captcha', 10)")
                or return LJ::error( "Failed lock on getting a captcha." );

    # Fetch the first unassigned row
    $sql = q{
        SELECT capid, anum
        FROM captchas
        WHERE
            issuetime = 0
            AND type = ?
        LIMIT 1
    };
    $row = $dbh->selectrow_arrayref( $sql, undef, $type )
        or $dbh->do("DO RELEASE_LOCK('get_captcha')") && die "No $type captchas available";
    die "selectrow_arrayref: $sql: ", $dbh->errstr if $dbh->err;
    ( $capid, $anum ) = @$row;

    # Mark the captcha as issued
    $issuedate = time();
    $sql = qq{
        UPDATE captchas
        SET issuetime = $issuedate
        WHERE capid = $capid
    };
    $dbh->do( $sql ) or die "do: $sql: ", $dbh->errstr;
    $dbh->do("DO RELEASE_LOCK('get_captcha')");

    return ( $capid, $anum );
}


### get_visual_data( $capid, $anum, $want_paths )
# if want_paths is true, this function may return an arrayref containing
# one or more paths (disk or HTTP) to the resource
sub get_visual_data
{
    my ( $capid, $anum, $want_paths ) = @_;
    $capid = int($capid);

    my (
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL statement
        $valid,                 # Are the capid/anum valid?
        $data,                  # The PNG data
        $u,                     # System user
        $location,              # Location of the file (mogile/blob)
       );

    $dbr = LJ::get_db_reader();
    $sql = q{
        SELECT capid, location
        FROM captchas
        WHERE
            capid = ?
            AND anum = ?
    };

    ( $valid, $location ) = $dbr->selectrow_array( $sql, undef, $capid, $anum );
    return undef unless $valid;

    if ($location eq 'mogile') {
        die "MogileFS object not loaded.\n" unless LJ::mogclient();
        if ($want_paths) {
            # return path(s) to the content if they want
            my @paths = LJ::mogclient()->get_paths("captcha:$capid");
            return \@paths;
        } else {
            $data = ${LJ::mogclient()->get_file_data("captcha:$capid")};
        }
    } else {
        $u = LJ::load_user( "system" )
            or die "Couldn't load the system user.";

        $data = LJ::Blob::get( $u, 'captcha_image', 'png', $capid )
              or die "Failed to fetch captcha_image $capid from media server";
    }
    return $data;
}


### get_audio_data( $capid, $anum, $want_paths )
# if want_paths is true, this function may return an arrayref containing
# one or more paths (disk or HTTP) to the resource
sub get_audio_data
{
    my ( $capid, $anum, $want_paths ) = @_;
    $capid = int($capid);

    my (
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL statement
        $valid,                 # Are the capid/anum valid?
        $data,                  # The PNG data
        $u,                     # System user
        $location,              # Location of the file (mogile/blob)
       );

    $dbr = LJ::get_db_reader();
    $sql = q{
        SELECT capid, location
        FROM captchas
        WHERE
            capid = ?
            AND anum = ?
    };

    ( $valid, $location ) = $dbr->selectrow_array( $sql, undef, $capid, $anum );
    return undef unless $valid;

    if ($location eq 'mogile') {
        die "MogileFS object not loaded.\n" unless LJ::mogclient();
        if ($want_paths) {
            # return path(s) to the content if they want
            my @paths = LJ::mogclient()->get_paths("captcha:$capid");
            return \@paths;
        } else {
            $data = ${LJ::mogclient()->get_file_data("captcha:$capid")};
        }
    } else {
        $u = LJ::load_user( "system" )
            or die "Couldn't load the system user.";

        $data = LJ::Blob::get( $u, 'captcha_audio', 'wav', $capid )
              or die "Failed to fetch captcha_audio $capid from media server";
    }
    return $data;
}

### check_code( $capid, $anum, $code, $u ) -> <true value if code is correct>
sub check_code {
    my ( $capid, $anum, $code, $u ) = @_;

    my (
        $dbr,                   # Database handle (reader)
        $sql,                   # SQL query
        $answer,                # Challenge answer
        $userid,                # userid of previous answerer (or 0 if none)
       );

    $sql = q{
        SELECT answer, userid
        FROM captchas
        WHERE
            capid = ?
            AND anum = ?
    };

    # Fetch the challenge's answer based on id and anum.
    $dbr = LJ::get_db_writer();
    ( $answer, $userid ) = $dbr->selectrow_array( $sql, undef, $capid, $anum );

    # if it's already been answered, it must have been answered by the $u
    # given to this function (double-click protection)
    return 0 if $userid && ( ! $u || $u->{userid} != $userid );

    # otherwise, just check answer.
    return lc $answer eq lc $code;
}

# Verify captcha answer if using a captcha session.
# (captcha challenge, code, $u)
# Returns capid and anum if answer correct. (for expire)
sub session_check_code {
    my ($sess, $code, $u) = @_;
    return 0 unless $sess && $code;
    $sess = LJ::get_challenge_attributes($sess);

    $u = LJ::load_user('system') unless $u;

    my $dbcm = LJ::get_cluster_master($u);
    my $dbr = LJ::get_db_reader();

    my ($lcapid, $try) =  # clustered
        $dbcm->selectrow_array('SELECT lastcapid, trynum ' .
                               'FROM captcha_session ' .
                               'WHERE sess=?', undef, $sess);
    my ($capid, $anum) =  # global
        $dbr->selectrow_array('SELECT capid,anum ' .
                              'FROM captchas '.
                              'WHERE capid=?', undef, $lcapid);
    if (! LJ::Captcha::check_code($capid, $anum, $code, $u)) {
        # update try and lastcapid
        $u->do('UPDATE captcha_session SET lastcapid=NULL, ' .
               'trynum=trynum+1 WHERE sess=?', undef, $sess);
        return 0;
    }
    return ($capid, $anum);
}

### expire( $capid ) -> <true value if code was expired successfully>
sub expire {
    my ( $capid, $anum, $userid ) = @_;

    my (
        $dbh,                   # Database handle (writer)
        $sql,                   # SQL update query
       );

    $sql = q{
        UPDATE captchas
        SET userid = ?
        WHERE capid = ? AND anum = ? AND userid = 0
    };

    # Fetch the challenge's answer based on id and anum.
    $dbh = LJ::get_db_writer();
    $dbh->do( $sql, undef, $userid, $capid, $anum ) or return undef;

    return 1;
}

# Update/create captcha sessions, return new capid/anum pairs on success.
# challenge, type, optional journalu->{clusterid} for clustering.
# Type is either 'image' or 'audio'
sub session
{
    my ($chal, $type, $cid) = @_;
    return unless $chal && $type;

    my $chalinfo = {};
    LJ::challenge_check($chal, $chalinfo);
    return unless $chalinfo->{valid};

    my $sess = LJ::get_challenge_attributes($chal);
    my ($capid, $anum) = ($type eq 'image') ?
                         LJ::Captcha::get_visual_id() :
                         LJ::Captcha::get_audio_id();


    $cid = LJ::load_user('system')->{clusterid} unless $cid;
    my $dbcm = LJ::get_cluster_master($cid);

    # Retain try count
    my $try = $dbcm->selectrow_array('SELECT trynum FROM captcha_session ' .
                                     'WHERE sess=?', undef, $sess);
    $try ||= 0;
    # Add/update session
    $dbcm->do('REPLACE INTO captcha_session SET sess=?, sesstime=?, '.
              'lastcapid=?, trynum=?', undef, $sess, time(), $capid, $try);
    return ($capid, $anum);
}


1;
