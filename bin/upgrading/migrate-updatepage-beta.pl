#!/usr/bin/perl
#
# bin/upgrading/migrate-updatepage-beta.pl
#
# One-time migration for retiring the "updatepage" beta: stores the advanced
# entry form layout for people who opted into the native editor, so their old
# posting and editing links keep opening it once nothing reads the beta list.
# Run it before expiring "updatepage" with an end_time, because checking any
# beta drops expired keys from a user's beta list. (Deleting the key from
# %LJ::BETA_FEATURES does not drop them.)
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use Getopt::Long;
use LJ::BetaFeatures;

# --userid limits the run to the given accounts (repeatable), e.g. to try it
# on one account first.
my ( $dryrun, @only );
GetOptions( 'dry-run' => \$dryrun, 'userid=i' => \@only )
    or die "Usage: $0 [--dry-run] [--userid=N ...]\n";
my %only = map { $_ => 1 } @only;

my $prop = LJ::get_prop( user => LJ::BetaFeatures->prop_name )
    or die "Can't find the beta features userprop. Database populated?\n";
my $layout_prop = LJ::get_prop( user => 'entryform_layout' )
    or die "Can't find the entryform_layout userprop. Database populated?\n";

# Safe to re-run: accounts that already have a layout are skipped, so a second
# run picks up anyone missed (say, moved between clusters mid-run).
my ( $found, $changed, $failed ) = ( 0, 0, 0 );
foreach my $cid (@LJ::CLUSTERS) {

    # the master, so a lagging replica can't hide a recent beta sign-up
    my $dbcr = LJ::get_cluster_master($cid)
        or die "Can't connect to cluster $cid\n";

    my $rows = $dbcr->selectall_arrayref(
        'SELECT userid, value FROM userproplite2 WHERE upropid = ? AND value LIKE ?',
        undef, $prop->{id}, '%updatepage%' );
    die "cluster $cid: " . $dbcr->errstr if $dbcr->err;

    my @userids = map { $_->[0] } grep {
        grep { $_ eq 'updatepage' } split /\s*,\s*/, $_->[1]
    } @$rows;
    @userids = grep { $only{$_} } @userids if @only;

    while ( my @chunk = splice( @userids, 0, 100 ) ) {
        my $us = LJ::load_userids(@chunk);
        foreach my $u ( grep { defined } values %$us ) {

            # rows left behind on a cluster the user has moved off
            next unless $u->clusterid == $cid;
            $found++;

            # keep a layout the user has already chosen; read it from the
            # master, not memcache, to narrow the window for one chosen while
            # this runs
            my $chosen = $dbcr->selectrow_array(
                'SELECT value FROM userproplite2 WHERE userid = ? AND upropid = ?',
                undef, $u->id, $layout_prop->{id} );
            die "cluster $cid: " . $dbcr->errstr if $dbcr->err;
            next if length( $chosen // '' );

            if ($dryrun) {
                $changed++;
            }
            elsif ( $u->entryform_layout('advanced') ) {
                $changed++;
            }
            else {
                $failed++;
                warn "Could not save the layout for userid " . $u->id . "\n";
            }
        }
    }
}

printf "%d updatepage beta users, %d %s the advanced layout, %d failed.\n", $found, $changed,
    $dryrun ? 'would be set to' : 'set to', $failed;
exit( $failed ? 1 : 0 );
