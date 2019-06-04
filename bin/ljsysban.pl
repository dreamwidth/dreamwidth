#!/usr/bin/perl
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
use Getopt::Long;

# parse input options
my ( $list, $add, $modify, $banid, $status, $bandate, $banuntil, $banlength, $what, $value, $note );
exit 1
    unless GetOptions(
    'list'        => \$list,
    'add'         => \$add,
    'modify'      => \$modify,
    'banid=s'     => \$banid,
    'status=s'    => \$status,
    'bandate=s'   => \$bandate,
    'banuntil=s'  => \$banuntil,
    'banlength=s' => \$banlength,
    'what=s'      => \$what,
    'value=s'     => \$value,
    'note=s'      => \$note,
    );

# did they give valid input?
my $an_opt = ( $what || $value || $status || $bandate || $banuntil || $banlength || $note );
unless (
    (
           $list && ( ( $banid && !$an_opt ) || ( !$banid && $an_opt ) )
        || ( $add    && $what  && $value )
        || ( $modify && $banid && $an_opt )
    )
    )
{

    die "Usage: ljsysban.pl [opts]\n\n"
        . "  --list   { <--banid=?> | or one of:\n"
        . "             [--what=? --status=? --bandate=datetime --banuntil=datetime\n"
        . "              --value=? --note=?]\n"
        . "           }\n\n"
        . "  --add    <--what=? --value=?\n"
        . "             [--status=? --bandate=datetime { --banuntil=datetime | --banlength=duration } --note=?]>\n\n"
        . "  --modify <--banid=?>\n"
        . "             [--status=? --bandate=datetime { --banuntil=datetime |\n"
        . "              --banlength=duration } --value=? --note=?]\n\n"
        . "datetime in format 'YYYY-MM-DD HH:MM:SS', duration in format 'N[dhms]' e.g. '5d' or '3h'.\n\n"
        . "examples:\n"
        . "  ljsysban.pl --list --what=ip --value=127.0.0.1\n"
        . "  ljsysban.pl --add --what=email --value=test\@test.com --banuntil='2006-06-01 00:00:00' --note='test'\n"
        . "  ljsysban.pl --add --what=uniq --value=jd87fdnef8jf8jef --banlength=3d --note='3 day ban'\n\n";
}

# now load in the beast
BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}
use LJ::Sysban;
my $dbh = LJ::get_db_writer();

# list bans
if ($list) {
    my $where;
    if ($banid) {
        $where = "banid=" . $dbh->quote($banid);
    }
    else {
        my @where = ();
        push @where, ( "what=" . $dbh->quote($what) )         if $what;
        push @where, ( "value=" . $dbh->quote($value) )       if $value;
        push @where, ( "status=" . $dbh->quote($status) )     if $status;
        push @where, ( "bandate=" . $dbh->quote($bandate) )   if $bandate;
        push @where, ( "banuntil=" . $dbh->quote($banuntil) ) if $banuntil;
        push @where, ( "note=" . $dbh->quote($note) )         if $note;
        $where = join( " AND ", @where );
    }

    my $sth = $dbh->prepare("SELECT * FROM sysban WHERE $where ORDER BY bandate ASC");
    $sth->execute;
    my $ct;
    while ( my $ban = $sth->fetchrow_hashref ) {
        print "> banid: $ban->{'banid'}, status: $ban->{'status'}, ";
        print "bandate: " .  ( $ban->{'bandate'}  ? $ban->{'bandate'}  : "BOT" ) . ", ";
        print "banuntil: " . ( $ban->{'banuntil'} ? $ban->{'banuntil'} : "EOT" ) . "\n";
        print "> what: $ban->{'what'}, value: $ban->{'value'}\n";
        print "> note: $ban->{'note'}\n" if $ban->{'note'};
        print "\n";
        $ct++;
    }
    print "\n\tNO MATCHES\n\n" unless $ct;

    exit;
}

# verify ban length and convert to banuntil as necessary
if ($banlength) {
    die "--banlength must be of format N[dmhs] such as 3d, 5h, 60m, 35s.\n"
        unless $banlength =~ /^(\d+)([dhms])$/i;
    my ( $num, $type ) = ( $1, lc $2 );
    $banlength = "DATE_ADD(NOW(), INTERVAL $num "
        . { 'd' => "DAY", 'h' => "HOUR", 'm' => "MINUTE", 's' => "SECOND" }->{$type} . ")";
    $banuntil = $dbh->selectrow_array("SELECT $banlength");
    die $dbh->errstr if $dbh->err;
}

# add new ban
if ($add) {

    $status = ( $status eq 'expired' ? 'expired' : 'active' );

    $dbh->do(
        "INSERT INTO sysban (status, what, value, note, bandate, banuntil)"
            . "VALUES (?, ?, ?, ?, "
            . ( $bandate  ? $dbh->quote($bandate)  : 'NOW()' ) . ", "
            . ( $banuntil ? $dbh->quote($banuntil) : 'NULL' ) . ")",
        undef, $status, $what, $value, $note
    );
    die $dbh->errstr if $dbh->err;
    my $insertid = $dbh->{'mysql_insertid'};

    LJ::Sysban::ban_do( $what, $value, LJ::mysqldate_to_time($banuntil) );

    # log in statushistory
    LJ::statushistory_add( 0, 0, 'sysban_add',
              "banid=$insertid; status=$status; "
            . "bandate="
            . ( $bandate || LJ::mysql_time() ) . "; "
            . "banuntil="
            . ( $banuntil || 'NULL' ) . "; "
            . "what=$what; value=$value; "
            . "note=$note;" );

    print "CREATED: banid=$insertid\n";
    exit;
}

# modify existing ban
if ($modify) {

    # load selected ban
    my $ban = $dbh->selectrow_hashref( "SELECT * FROM sysban WHERE banid=?", undef, $banid );
    die $dbh->errstr if $dbh->err;

    my @set = ();

    # ip/uniq ban and we're going to change the value
    if (   ( $value && $value ne $ban->{'value'} )
        || $banuntil && $banuntil ne $ban->{'banuntil'}
        || ( $status && $status ne $ban->{'status'} && $status eq 'expired' ) )
    {

        LJ::Sysban::ban_undo( $ban->{what}, $value || $ban->{value} );
    }

    # what - must have a value
    if ( $what && $what ne $ban->{'what'} ) {
        $ban->{'what'} = $what;
        push @set, "what=" . $dbh->quote( $ban->{'what'} );
    }

    # ip/uniq ban and we are going to change the value
    if (   ( $value && $value ne $ban->{'value'} )
        || $banuntil && $banuntil ne $ban->{'banuntil'}
        || ( $status && $status ne $ban->{'status'} && $status eq 'active' ) )
    {

        my $new_value    = $value || $ban->{value};
        my $new_banuntil = LJ::mysqldate_to_time( $banuntil || $ban->{banuntil} );

        LJ::Sysban::ban_do( $ban->{what}, $new_value, $new_banuntil );
    }

    # value - must have a value
    if ( $value && $value ne $ban->{'value'} ) {
        $ban->{'value'} = $value;
        push @set, "value=" . $dbh->quote( $ban->{'value'} );
    }

    # status - must have a value
    if ( $status && $status ne $ban->{'status'} ) {
        $ban->{'status'} = ( $status eq 'expired' ? 'expired' : 'active' );
        push @set, "status=" . $dbh->quote( $ban->{'status'} );
    }

    # banuntil
    if ( $banuntil && $banuntil ne $ban->{'banuntil'} ) {
        $ban->{'banuntil'} = ( $banuntil && $banuntil ne 'NULL' ) ? $banuntil : 0;
        push @set,
            "banuntil=" . ( $ban->{'banuntil'} ? $dbh->quote( $ban->{'banuntil'} ) : 'NULL' );
    }

    # bandate - must have a value
    if ( $bandate && $bandate ne $ban->{'bandate'} ) {
        $ban->{'bandate'} = $bandate;
        push @set, "bandate=" . $dbh->quote( $ban->{'bandate'} );
    }

    # note - can be changed to blank
    if ( defined $note && $note ne $ban->{'note'} ) {
        $ban->{'note'} = $note;
        push @set, "note=" . $dbh->quote( $ban->{'note'} );
    }

    # do update
    $dbh->do( "UPDATE sysban SET " . join( ", ", @set ) . " WHERE banid=?", undef,
        $ban->{'banid'} );

    # log in statushistory
    my $msg;
    map {
        $msg .= " " if $msg;
        $msg .= "$_=$ban->{$_};"
    } qw(banid status bandate banuntil what value note);
    LJ::statushistory_add( 0, 0, 'sysban_mod', $msg );

    print "MODIFIED: banid=$banid\n";
    exit;
}
