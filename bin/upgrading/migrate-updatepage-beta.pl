#!/usr/bin/perl
#
# bin/upgrading/migrate-updatepage-beta.pl
#
# One-time migration for retiring the "updatepage" beta: people who opted
# into the native entry form keep getting its advanced layout from old
# posting and editing links. Run it before removing "updatepage" from
# %LJ::BETA_FEATURES, because checking any beta drops inactive keys from a
# user's beta list.
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

my $dryrun;
GetOptions( 'dry-run' => \$dryrun )
    or die "Usage: $0 [--dry-run]\n";

my $prop = LJ::get_prop( user => LJ::BetaFeatures->prop_name )
    or die "Can't find the beta features userprop. Database populated?\n";

my ( $found, $changed ) = ( 0, 0 );
foreach my $cid (@LJ::CLUSTERS) {
    my $dbcr = LJ::get_cluster_reader($cid)
        or die "Can't connect to cluster $cid\n";

    my $rows = $dbcr->selectall_arrayref(
        'SELECT userid, value FROM userproplite2 WHERE upropid = ? AND value LIKE ?',
        undef, $prop->{id}, '%updatepage%' );
    die "cluster $cid: " . $dbcr->errstr if $dbcr->err;

    my @userids = map { $_->[0] } grep {
        grep { $_ eq 'updatepage' } split /\s*,\s*/, $_->[1]
    } @$rows;

    while ( my @chunk = splice( @userids, 0, 100 ) ) {
        my $us = LJ::load_userids(@chunk);
        foreach my $u ( values %$us ) {

            # rows left behind on a cluster the user has moved off
            next unless $u->clusterid == $cid;
            $found++;

            # keep a layout the user has already chosen
            next if length( $u->raw_prop('entryform_layout') // '' );

            $changed++;
            next if $dryrun;
            $u->entryform_layout('advanced');
        }
    }
}

printf "%d updatepage beta users, %d %s the advanced layout.\n", $found, $changed,
    $dryrun ? 'would be set to' : 'set to';
