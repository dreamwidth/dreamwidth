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

BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

sub usage {
    die "Usage: [--swap --force] <from_user> <to_user>\n";
}

my %args = ( swap => 0, force => 0 );
usage()
    unless GetOptions(
    'swap'  => \$args{swap},
    'force' => \$args{force},
    );

my $error;

my $from = shift @ARGV;
my $to   = shift @ARGV;
usage() unless $from =~ /^\w{1,25}$/ && $to =~ /^\w{1,25}$/;

my $dbh = LJ::get_db_writer() or die "Could not get DB handle";

unless ( $args{swap} ) {
    if ( rename_user( $from, $to ) ) {
        print "Success.  Renamed $from -> $to.\n";
    }
    else {
        print "Failed: $error\n";
    }
    exit;
}

### check that emails/passwords match, and that at least one is verified
unless ( $args{force} ) {
    my @acct = grep { $_ } LJ::DB::no_cache(
        sub {
            return ( LJ::load_user($from), LJ::load_user($to) );
        }
    );
    unless ( @acct == 2 ) {
        print "Both accounts aren't valid.\n";
        exit 1;
    }
    unless ( $acct[0]->has_same_email_as( $acct[1] ) ) {
        print "Email addresses don't match.\n";
        print "   " . $acct[0]->email_raw . "\n";
        print "   " . $acct[1]->email_raw . "\n";
        exit 1;
    }
    unless ( $acct[0]->password eq $acct[1]->password ) {
        print "Passwords don't match.\n";
        exit 1;
    }
    unless ( $acct[0]->{'status'} eq "A" || $acct[1]->{'status'} eq "A" ) {
        print "At least one account isn't verified.\n";
        exit 1;
    }
}

my $swapnum = 0;
print "Swapping 1/3...\n";
until ( $swapnum == 10 || rename_user( $from, "lj_swap_$swapnum" ) ) {
    $swapnum++;
}
if ( $swapnum == 10 ) {
    print "Couldn't find a swap position?\n";
    exit 1;
}

print "Swapping 2/3...\n";
unless ( rename_user( $to, $from ) ) {
    print "Swap failed in the middle, from $to -> $from failed.\n";
    exit 1;
}

print "Swapping 3/3...\n";
unless ( rename_user( "lj_swap_$swapnum", $to ) ) {
    print "Swap failed in the middle, from lj_swap_$swapnum -> $to failed.\n";
    exit 1;
}

# check for circular 'renamedto' references
{

    # if the fromuser had redirection on, make sure it points to the new $to user
    my $fromu   = LJ::load_user( $from, 'force' );
    my $fromu_r = $fromu ? $fromu->prop('renamedto') : undef;
    if ( $fromu_r && $fromu_r ne $to ) {
        print "Setting redirection: $from => $to\n";
        unless ( $fromu->set_prop( 'renamedto' => $to ) ) {
            print "Error setting 'renamedto' userprop for $from\n";
            exit 1;
        }
    }

    # if the $to user had redirection, they shouldn't anymore
    my $tou = LJ::load_user( $to, 'force' );
    if ( $tou && $tou->prop('renamedto') ) {
        print "Removing redirection for user: $to\n";
        unless ( $tou->set_prop( 'renamedto' => undef ) ) {
            print "Error setting 'renamedto' userprop for $to\n";
            exit 1;
        }
    }
}

print "Swapped.\n";
exit 0;

sub rename_user {
    my $from = shift;
    my $to   = shift;

    my $qfrom = $dbh->quote( LJ::canonical_username($from) );
    my $qto   = $dbh->quote( LJ::canonical_username($to) );

    print "Renaming $from -> $to\n";

    my $u = LJ::load_user( $from, 'force' );
    unless ($u) {
        $error = "Invalid source user: $from";
        return 0;
    }

    if ( LJ::load_user( $to, 'force' ) ) {
        $error = "User already exists: $to";
        return 0;
    }

    foreach my $table (qw(user useridmap)) {
        $dbh->do("UPDATE $table SET user=$qto WHERE user=$qfrom");
        if ( $dbh->err ) {
            $error = $dbh->errstr;
            return 0;
        }
    }

    # from user is now invalidated
    LJ::memcache_kill( $u->{userid}, "userid" );
    LJ::MemCache::delete("uidof:$from");
    LJ::MemCache::delete("uidof:$to");

    LJ::Procnotify::add(
        "rename_user",
        {
            user   => $u->user,
            userid => $u->userid
        }
    );

    $dbh->do(
        "INSERT INTO renames (renid, auth, cartid, renuserid, fromuser, touser, rendate) "
            . "VALUES ( NULL, '[manual]', 0, ?, $qfrom, $qto, ? )",
        undef, $u->userid, time
    );

    return 1;
}
