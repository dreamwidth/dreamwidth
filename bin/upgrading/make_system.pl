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
BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

my $dbh = LJ::get_dbh("master");

print "
This tool will create your $LJ::SITENAMESHORT 'system' account and
set its password.  Or, if you already have a system user, it'll change
its password to whatever you specify.
";

print "Enter password for the 'system' account: ";
my $pass = <STDIN>;
chomp $pass;

print "\n";

print "Creating system account...\n";
my $u = LJ::User->create( user => 'system',
                          name => 'System Account',
                          password => $pass );
unless ( $u ) {
    print "Already exists.\nModifying 'system' account...\n";
    my $id = LJ::get_userid("system");
    $dbh->do("UPDATE password SET password=? WHERE userid=?",
             undef, $pass, $id);
}

$u ||= LJ::load_user( "system" );
unless ( $u ) {
    print "ERROR: can't find newly-created system account.\n";
    exit 1;
}

print "Giving 'system' account 'admin' priv on all areas...\n";
if ( $u->has_priv( "admin", "*" ) ) {
    print "Already has it.\n";
} else {
    my $sth = $dbh->prepare("INSERT INTO priv_map (userid, prlid, arg) ".
                            "SELECT $u->{'userid'}, prlid, '*' ".
                            "FROM priv_list WHERE privcode='admin'");
    $sth->execute;
    if ($dbh->err || $sth->rows == 0) {
        print "Couldn't grant system account admin privs\n";
        exit 1;
    }
}

print "Done.\n\n";


