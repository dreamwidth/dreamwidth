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
use GD::Graph::bars;

our %maint;

$maint{'genstatspics'} = sub {
    my $dbh = LJ::get_db_writer();
    my $sth;

    ### get posts by day data from summary table
    print "-I- new accounts by day.\n";
    $sth = $dbh->prepare(
"SELECT DATE_FORMAT(statkey, '%m-%d') AS 'day', statval AS 'new' FROM stats WHERE statcat='newbyday' ORDER BY statkey DESC LIMIT 60"
    );
    $sth->execute;
    if ( $dbh->err ) { die $dbh->errstr; }

    my @data;
    my $i;
    my $max;
    while ( $_ = $sth->fetchrow_hashref ) {
        my $val = $_->{'new'};
        unshift @{ $data[0] }, ( $i++ % 5 == 0 ? $_->{'day'} : "" );
        unshift @{ $data[1] }, $val;
        if ( $val > $max ) { $max = $val; }
    }

    if (@data) {

        # posts by day graph
        my $g = GD::Graph::bars->new( 520, 350 );
        $g->set(
            x_label     => 'Day',
            y_label     => 'Accounts',
            title       => 'New accounts per day',
            tranparent  => 0,
            y_max_value => $max,
        );

        my $gd = $g->plot( \@data ) or die $g->error;
        open( IMG, ">$LJ::HTDOCS/stats/newbyday.png" ) or die $!;
        binmode IMG;
        print IMG $gd->png;
        close IMG;
    }

    print "-I- done.\n";

};

1;
