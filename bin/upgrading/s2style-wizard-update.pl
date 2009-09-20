#!/usr/bin/perl

use strict;
$| = 1;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $sysid = LJ::get_userid("system");
die "Couldn't find system userid"
    unless $sysid;

my $dbh = LJ::get_db_writer();
die "Could not connect to global master"
    unless $dbh;


# find info on styles based on public layouts

# need to select from:
# s2styles - get style name
# s2stylelayers - get layout s2lid
# s2layers - get userid of layer
# s2info - get redist_uniq

{
    print "Converting styles based on public layouts...";

    my $sth = $dbh->prepare("SELECT s.styleid, i.value " .
                            "FROM s2styles s, s2stylelayers sl, s2layers l, s2info i " .
                            "WHERE s.styleid=sl.styleid AND l.s2lid=sl.s2lid AND i.s2lid=l.s2lid " .
                            "AND l.userid=? AND l.type='layout' AND s.name='wizard' " .
                            "AND i.infokey='redist_uniq'");
    $sth->execute($sysid);
    my $ct = 0;
    while (my ($styleid, $redist_uniq) = $sth->fetchrow_array) {

        my $layout = (split("/", $redist_uniq))[0];
        $dbh->do("UPDATE s2styles SET name=? WHERE styleid=?",
                 undef, "wizard-$layout", $styleid);
        $ct++;
        print "." if $ct % 1000 == 0;
    }

    print " $ct done.\n";
}


# find info on styles based on user layouts

# need to select from:
# s2styles - get style name
# s2stylelayers - get layout s2lid
# s2layers - get userid of layer

{
    print "Converting styles based on user layouts...";

    my $sth = $dbh->prepare("SELECT s.styleid, l.s2lid " .
                            "FROM s2styles s, s2stylelayers sl, s2layers l " .
                            "WHERE s.styleid=sl.styleid AND l.s2lid=sl.s2lid " .
                            "AND l.userid<>? AND l.type='layout' AND s.name='wizard'");
    $sth->execute($sysid);
    my $ct = 0;
    while (my ($styleid, $s2lid) = $sth->fetchrow_array) {

        $dbh->do("UPDATE s2styles SET name=? WHERE styleid=?",
                 undef, "wizard-$s2lid", $styleid);
        $ct++;
        print "." if $ct % 1000 == 0;
    }

    print " $ct done.\n";
}
