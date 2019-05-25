#!/usr/bin/perl
#
# DW::Hooks::SiteSearch
#
# Hooks for Site Search functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::SiteSearch;

use strict;
use LJ::Hooks;

sub _sphinx_db {

    # ensure we can talk to our system
    return unless @LJ::SPHINX_SEARCHD;
    my $dbh = LJ::get_dbh('sphinx_search')
        or die "Unable to get sphinx_search database handle.\n";
    return $dbh;
}

LJ::Hooks::register_hook(
    'setprop',
    sub {
        my %opts = @_;
        return unless $opts{prop} eq 'opt_blockglobalsearch';

        my $dbh = _sphinx_db() or return 0;
        $dbh->do(
            q{UPDATE items_raw SET allow_global_search = ?, touchtime = UNIX_TIMESTAMP()
          WHERE journalid = ?},
            undef, $opts{value} eq 'Y' ? 0 : 1, $opts{u}->id
        );
        die $dbh->errstr if $dbh->err;

        # looks good
        return 1;
    }
);

# set when the user's status(vis) changes
# the user may still undelete or be unsuspended
# so we don't want to remove from indexing just yet
sub _mark_deleted {
    my ( $u, $is_deleted ) = @_;

    my $dbh = _sphinx_db() or return 0;
    $dbh->do(
        q{UPDATE items_raw SET is_deleted = ?, touchtime = UNIX_TIMESTAMP()
          WHERE journalid = ?},
        undef, $is_deleted, $u->id
    );
    die $dbh->errstr if $dbh->err;

    return 1;
}

LJ::Hooks::register_hook( 'account_delete', sub { _mark_deleted( $_[0], 1 ) } );
LJ::Hooks::register_hook( 'account_cancel', sub { _mark_deleted( $_[0], 1 ) } );
LJ::Hooks::register_hook(
    'account_makevisible',
    sub {
        my ( $u, %opts ) = @_;

        my $old = $opts{old_statusvis};
        _mark_deleted( $u, 0 ) if $old eq "D" || $old eq "S";
    }
);

LJ::Hooks::register_hook(
    'purged_user',
    sub {
        my ($u) = @_;

        my $sclient = LJ::theschwartz() or die;

       # queue up a copier job, which will notice that the entries by this user have been deleted...
        $sclient->insert_jobs(
            TheSchwartz::Job->new_from_array(
                'DW::Worker::Sphinx::Copier', { userid => $u->id, source => "purghook" }
            )
        );

    }
);

1;
