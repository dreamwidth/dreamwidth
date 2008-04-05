#!/usr/bin/perl
#

use strict;
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbh = LJ::get_dbh("master");

print "
This tool will create your LiveJournal 'system' account and
set its password.  Or, if you already have a system user, it'll change
its password to whatever you specify.
";

print "Enter password for the 'system' account: ";
my $pass = <STDIN>;
chomp $pass;

print "\n";

print "Creating system account...\n";
unless (LJ::create_account({ 'user' => 'system',
                             'name' => 'System Account',
                             'password' => $pass }))
{
    print "Already exists.\nModifying 'system' account...\n";
    my $id = LJ::get_userid("system");
    $dbh->do("UPDATE password SET password=? WHERE userid=?",
             undef, $pass, $id);
}

my $u = LJ::load_user("system");
unless ($u) {
    print "ERROR: can't find newly-created system account.\n";
    exit 1;
}

print "Giving 'system' account 'admin' priv on all areas...\n";
if (LJ::check_priv($u, "admin", "*")) {
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


