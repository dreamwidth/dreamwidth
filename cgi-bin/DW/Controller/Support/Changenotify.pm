#!/usr/bin/perl
#
# DW::Controller::Support::Changenotify
#
# Select support notifications by category.
#
# Authors:
#     Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Changenotify;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Support;

DW::Routing->register_string( '/support/changenotify', \&cn_handler, app => 1, no_cache => 1 );

sub cn_handler {
    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    LJ::Support::init_remote($remote);
    my $remote_id = $remote->id;

    my $ml_scope = '/support/changenotify.tt';
    return error_ml( "$ml_scope.error.noemail", { aopts => "/register" } )
        unless $remote->is_validated;

    my $cats        = LJ::Support::load_cats();
    my @filter_cats = LJ::Support::filter_cats( $remote, $cats );

    my $r    = $rv->{r};
    my $vars = {};

    if ( $r->did_post ) {
        my $form = $r->post_args;
        $remote->set_prop( 'opt_getselfsupport' => $form->{opt_getselfsupport} ? 1 : 0 );

        my $dbh = LJ::get_db_writer();
        $dbh->do("DELETE FROM supportnotify WHERE userid=$remote_id");

        my $sql;

        foreach my $cat (@filter_cats) {
            my $id      = $cat->{'spcatid'};
            my $setting = $form->{"spcatid_$id"};
            if ( $setting eq "all" || $setting eq "new" ) {
                if ($sql) {
                    $sql .= ", ";
                }
                else {
                    $sql = "REPLACE INTO supportnotify (spcatid, userid, level) VALUES ";
                }
                $sql .= "($id, $remote_id, '$setting')";
            }
        }

        $dbh->do($sql) if $sql;

        return success_ml(
            "$ml_scope.success.text",
            undef,
            [
                {
                    text => LJ::Lang::ml("$ml_scope.success.fromhere.board"),
                    url  => "$LJ::SITEROOT/support/help"
                },
                {
                    text => LJ::Lang::ml("$ml_scope.success.fromhere.support"),
                    url  => "$LJ::SITEROOT/support"
                },
            ]
        );
    }
    else {
        my %notify;
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT spcatid, level FROM supportnotify WHERE userid=$remote_id");
        $sth->execute;
        while ( my ( $spcatid, $level ) = $sth->fetchrow_array ) {
            if ( LJ::Support::can_read_cat( $cats->{$spcatid}, $remote ) ) {
                $notify{$spcatid} = $level;
            }
        }
        $vars->{remote}      = $remote;
        $vars->{notify}      = \%notify;
        $vars->{filter_cats} = \@filter_cats;

        return DW::Template->render_template( 'support/changenotify.tt', $vars );
    }
}

1;
