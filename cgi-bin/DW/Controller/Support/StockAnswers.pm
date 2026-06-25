#!/usr/bin/perl
#
# DW::Controller::Support::StockAnswers
#
# Manage the canned ("stock") support answers for each support category.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Support::StockAnswers;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Support;

DW::Routing->register_string(
    '/support/stock_answers', \&stock_answers_handler,
    app      => 1,
    no_cache => 1
);

sub stock_answers_handler {
    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $r        = $rv->{r};
    my $remote   = $rv->{remote};
    my $get      = $r->get_args;
    my $post     = $r->post_args;
    my $ml_scope = '/support/stock_answers.tt';

    # most things have a category id
    my $spcatid = ( $get->{spcatid} || $post->{spcatid} || 0 ) + 0;
    my $cats    = LJ::Support::load_cats();
    return error_ml("$ml_scope.category.not.exist")
        unless !$spcatid || $cats->{$spcatid};

    # editing requires the supporthelp priv for this category (or globally)
    my $canedit =
        ( $spcatid && $remote->has_priv( 'admin', "supporthelp/$cats->{$spcatid}->{catkey}" ) )
        || $remote->has_priv( 'admin', 'supporthelp' );

    # POST actions require edit access (form auth already checked by controller())
    return error_ml("$ml_scope.not.have.access.to.actions")
        if $r->did_post && !$canedit;

    # viewing requires supportviewstocks on at least one category
    my %canview;
    foreach my $cat ( values %$cats ) {
        $canview{ $cat->{spcatid} } = 1
            if LJ::Support::support_check_priv( { _cat => $cat }, $remote, 'supportviewstocks' );
    }
    return error_ml("$ml_scope.not.have.access.to.view.answers")
        unless %canview;
    return error_ml("$ml_scope.not.have.access.to.view.answers.in.cat")
        if $spcatid && !$canview{$spcatid};

    # filter the category list down to the viewable ones
    $cats = { map { $_->{spcatid} => $_ } grep { $canview{ $_->{spcatid} } } values %$cats };

    my $ansid = ( $get->{ansid} || 0 ) + 0;
    my $self  = "$LJ::SITEROOT/support/stock_answers";

    # ---- POST: delete an answer ----
    if ( $post->{'action:delete'} ) {
        my $dbh = LJ::get_db_writer()
            or return error_ml("$ml_scope.unable.get.database.handle");

        my $ct = $dbh->do( "DELETE FROM support_answers WHERE ansid = ? AND spcatid = ?",
            undef, $ansid, $spcatid );
        return error_ml("$ml_scope.error") if $dbh->err;
        return error_ml("$ml_scope.no.answer") unless $ct;
        return $r->redirect("$self?spcatid=$spcatid&deleted=1");
    }

    # ---- POST: create or update an answer ----
    if ( $post->{'action:new'} || $post->{'action:save'} ) {
        my ( $subj, $body ) = ( $post->{subject}, $post->{body} );
        foreach my $ref ( \$subj, \$body ) {
            $$ref =~ s/^\s+//;
            $$ref =~ s/\s+$//;
        }

        return error_ml("$ml_scope.fill.out.all.friends")
            unless $spcatid && $subj && $body;

        my $dbh = LJ::get_db_writer()
            or return error_ml("$ml_scope.unable.database.handle");

        if ( $post->{'action:new'} ) {
            my $newid = LJ::alloc_global_counter('A')
                or return error_ml("$ml_scope.unable.allocate.counter");

            $dbh->do(
                "INSERT INTO support_answers "
                    . "(ansid, spcatid, subject, body, lastmodtime, lastmoduserid) "
                    . "VALUES (?, ?, ?, ?, UNIX_TIMESTAMP(), ?)",
                undef, $newid, $spcatid, $subj, $body, $remote->userid
            );
            return error_ml("$ml_scope.error") if $dbh->err;
            return $r->redirect("$self?spcatid=$spcatid&ansid=$newid&added=1");
        }
        else {
            return error_ml("$ml_scope.no.answer.id") unless $ansid;

            $dbh->do(
                "UPDATE support_answers SET subject = ?, body = ?, "
                    . "lastmodtime = UNIX_TIMESTAMP(), lastmoduserid = ? WHERE ansid = ?",
                undef, $subj, $body, $remote->userid, $ansid
            );
            return error_ml("$ml_scope.error") if $dbh->err;
            return $r->redirect("$self?spcatid=$spcatid&ansid=$ansid&saved=1");
        }
    }

    # viewable categories, sorted by name (used for the selects and the listing)
    my @sorted_cats = sort { $cats->{$a}->{catname} cmp $cats->{$b}->{catname} } keys %$cats;

    # ---- GET: new-answer form ----
    if ( $get->{new} ) {
        my @items = ( 0, LJ::Lang::ml("$ml_scope.select.please") );
        push @items, ( $_, $cats->{$_}->{catname} ) foreach @sorted_cats;

        $rv->{mode}      = 'new';
        $rv->{spcatid}   = $spcatid;
        $rv->{cat_items} = \@items;
        return DW::Template->render_template( 'support/stock_answers.tt', $rv );
    }

    # ---- GET: default listing ----
    my $dbr = LJ::get_db_reader()
        or return error_ml("$ml_scope.no.database.available");

    my $cols = "ansid, spcatid, subject, lastmodtime, lastmoduserid";
    $cols .= ", body" if $ansid;

    my $sql = "SELECT $cols FROM support_answers";
    my @bind;
    if ( $spcatid || $ansid ) {
        $sql .= " WHERE ";
        if ($spcatid) {
            $sql .= "spcatid = ?";
            push @bind, $spcatid;
        }
        if ($ansid) {
            $sql .= ( $spcatid ? " AND " : "" ) . "ansid = ?";
            push @bind, $ansid;
        }
    }

    my $sth = $dbr->prepare($sql);
    $sth->execute(@bind);
    return error_ml("$ml_scope.error") if $sth->err;

    my %answers;
    while ( my $row = $sth->fetchrow_hashref ) {
        $answers{ $row->{spcatid} }->{ $row->{ansid} } = {
            subject     => $row->{subject},
            body        => $row->{body},
            lastmodtime => $row->{lastmodtime},
            lastmoduser => LJ::load_userid( $row->{lastmoduserid} ),
        };
    }

    my @filter_items = ( 0, LJ::Lang::ml("$ml_scope.select.none") );
    push @filter_items, ( $_, $cats->{$_}->{catname} ) foreach @sorted_cats;

    # build the per-category display structure
    my @categories;
    foreach my $catid (@sorted_cats) {
        my $override      = $LJ::SUPPORT_STOCKS_OVERRIDE{ $cats->{$catid}->{catkey} };
        my $show_override = $override && ( !$spcatid || $catid == $spcatid );

        next unless %{ $answers{$catid} || {} } || $show_override;

        my @ans;
        foreach my $aid (
            sort { $answers{$catid}->{$a}->{subject} cmp $answers{$catid}->{$b}->{subject} }
            keys %{ $answers{$catid} }
            )
        {
            my $a = $answers{$catid}->{$aid};
            push @ans,
                {
                ansid       => $aid,
                subject     => $a->{subject},
                body        => $a->{body},
                has_body    => ( $a->{body} ? 1 : 0 ),
                lastmoduser => $a->{lastmoduser},
                lastmodtime => LJ::mysql_time( $a->{lastmodtime} ),
                };
        }

        push @categories,
            {
            spcatid          => $catid,
            catname          => $cats->{$catid}->{catname},
            answers          => \@ans,
            override_catname => $show_override
            ? ( $cats->{$override} ? $cats->{$override}->{catname} : undef )
            : undef,
            };
    }

    $rv->{mode}         = 'list';
    $rv->{spcatid}      = $spcatid;
    $rv->{canedit}      = $canedit;
    $rv->{filter_items} = \@filter_items;
    $rv->{categories}   = \@categories;
    $rv->{message} =
          $get->{added}   ? 'added'
        : $get->{saved}   ? 'saved'
        : $get->{deleted} ? 'deleted'
        :                   undef;

    return DW::Template->render_template( 'support/stock_answers.tt', $rv );
}

1;
