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
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

my $dbh = LJ::get_db_writer();

# dump proplists, etc
print "Dumping proplists.dat\n";
open( my $plg, ">$ENV{LJHOME}/bin/upgrading/proplists.dat" )       or die;
open( my $pll, ">$ENV{LJHOME}/bin/upgrading/proplists-local.dat" ) or die;
foreach my $table ( 'userproplist', 'talkproplist', 'logproplist', 'usermsgproplist' ) {
    my $sth = $dbh->prepare("DESCRIBE $table");
    $sth->execute;
    my @cols = ();
    while ( my $c = $sth->fetchrow_hashref ) {
        die "Where is the 'Extra' column?" unless exists $c->{'Extra'};    # future-proof
        next if $c->{'Extra'} =~ /auto_increment/;
        push @cols, $c;
    }
    @cols = sort { $a->{'Field'} cmp $b->{'Field'} } @cols;
    my $cols = join( ", ", map { $_->{'Field'} } @cols );

    my $pri_key = "name";    # for now they're all 'name'.  might add more tables.
    $sth = $dbh->prepare("SELECT $cols FROM $table ORDER BY $pri_key");
    $sth->execute;
    while ( my @r = $sth->fetchrow_array ) {
        my %vals;
        my $i = 0;
        foreach ( map { $_->{'Field'} } @cols ) {
            $vals{$_} = $r[ $i++ ];
        }
        my $scope = $vals{'scope'} && $vals{'scope'} eq "local" ? "local" : "general";
        my $fh = $scope eq "local" ? $pll : $plg;
        print $fh "$table.$vals{$pri_key}:\n";
        foreach my $c ( map { $_->{'Field'} } @cols ) {
            next if $c eq $pri_key;
            next if $c eq "scope";    # implied by filenamea
            print $fh "  $c: $vals{$c}\n";
        }
        print $fh "\n";
    }

}

# and dump mood info
print "Dumping moods.dat\n";
open( F, ">$ENV{'LJHOME'}/bin/upgrading/moods.dat" ) or die;
my $sth = $dbh->prepare("SELECT moodid, mood, parentmood FROM moods ORDER BY moodid");
$sth->execute;
while ( @_ = $sth->fetchrow_array ) {
    print F "MOOD @_\n";
}

$sth = $dbh->prepare(
    "SELECT moodthemeid, name, des FROM moodthemes WHERE is_public='Y' ORDER BY name");
$sth->execute;
while ( my ( $id, $name, $des ) = $sth->fetchrow_array ) {
    $name =~ s/://;
    print F "MOODTHEME $name : $des\n";
    my $std = $dbh->prepare( "SELECT moodid, picurl, width, height FROM moodthemedata "
            . "WHERE moodthemeid=$id ORDER BY moodid" );
    $std->execute;
    while ( @_ = $std->fetchrow_array ) {
        print F "@_\n";
    }
}
close F;

print "Done.\n";
