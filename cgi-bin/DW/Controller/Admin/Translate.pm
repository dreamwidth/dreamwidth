#!/usr/bin/perl
#
# DW::Controller::Admin::Translate
#
# Frontend for finding and editing strings in the translation system.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::Translate;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'translate',
    ml_scope => '/admin/translate/index.tt',
);

DW::Routing->register_string( "/admin/translate/index",         \&index_controller,      app => 1 );
DW::Routing->register_string( "/admin/translate/edit",          \&edit_controller,       app => 1 );
DW::Routing->register_string( "/admin/translate/search",        \&search_controller,     app => 1 );
DW::Routing->register_string( "/admin/translate/searchform",    \&searchform_controller, app => 1 );
DW::Routing->register_string( "/admin/translate/help-severity", \&severity_controller,   app => 1 );
DW::Routing->register_string( "/admin/translate/welcome",       \&welcome_controller,    app => 1 );

sub index_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $vars = {};

    my %lang;

    {    # load language info from database into %lang

        my $dbr = LJ::get_db_reader();
        my $sth;

        $sth = $dbr->prepare("SELECT lnid, lncode, lnname, lastupdate FROM ml_langs");
        $sth->execute;
        $lang{ $_->{'lnid'} } = $_ while $_ = $sth->fetchrow_hashref;

        $sth = $dbr->prepare("SELECT lnid, staleness > 1, COUNT(*) FROM ml_latest GROUP by 1, 2");
        $sth->execute;
        while ( my ( $lnid, $stale, $ct ) = $sth->fetchrow_array ) {
            next unless exists $lang{$lnid};
            $lang{$lnid}->{'_total'} += $ct;
            $lang{$lnid}->{'_good'}  += ( 1 - $stale ) * $ct;
            $lang{$lnid}->{'percent'} =
                100 * $lang{$lnid}->{'_good'} / ( $lang{$lnid}->{'_total'} || 1 );
        }
    }

    $vars->{rows} = [ sort { $a->{lnname} cmp $b->{lnname} } values %lang ];

    $vars->{cols} = [
        {
            ln_key => 'lncode',
            ml_key => '.table.code',
            format => sub { $_[0]->{lncode} }
        },
        {
            ln_key => 'lnname',
            ml_key => '.table.langname',
            format => sub {
                my $r = $_[0];
                "<a href='edit?lang=$r->{lncode}'>$r->{lnname}</a>";
            }
        },
        {
            ln_key => 'percent',
            ml_key => '.table.done',
            format => sub {
                my $r   = $_[0];
                my $pct = sprintf( "%.02f%%", $r->{percent} );
                "<b>$pct</b><br />$r->{'_good'}/$r->{'_total'}";
            }
        },
        {
            ln_key => 'lastupdate',
            ml_key => '.table.lastupdate',
            format => sub { $_[0]->{lastupdate} }
        }
    ];

    return DW::Template->render_template( 'admin/translate/index.tt', $vars );
}

sub edit_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;

    return $r->redirect('/admin/translate/') unless $form_args->{lang};

    return DW::Template->render_template( 'admin/translate/edit.tt', $form_args,
        { no_sitescheme => 1 } );
}

sub search_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;
    my $vars      = { lang => $form_args->{lang} };

    my $l = LJ::Lang::get_lang( $vars->{lang} );

    my $err = sub { DW::Template->render_string( $_[0], { no_sitescheme => 1 } ) };

    return $err->("<b>Invalid language</b>") unless $l;

    my $dbr = LJ::get_db_reader();
    my $sql;

    # construct database query
    {
        # all queries in production use the visible flag
        my $vis_flag = $LJ::IS_DEV_SERVER ? '' : 'AND i.visible = 1';

        if ( $form_args->{search} eq 'sev' ) {
            my $what = ">= 1";
            if ( $form_args->{stale} =~ /^(\d+)(\+?)$/ ) {
                $what = ( $2 ? ">=" : "=" ) . $1;
            }
            $sql = qq(
                SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l
                WHERE l.lnid=$l->{'lnid'} AND l.staleness $what AND l.dmid=i.dmid
                AND l.itid=i.itid $vis_flag ORDER BY i.dmid, i.itcode
            );
        }

        if ( $form_args->{search} eq 'txt' ) {
            my $remote = $rv->{remote};
            return $err->("This search type is restricted to $l->{'lnname'} translators.")
                unless $remote
                && ( $remote->has_priv( "translate", $l->{'lncode'} )
                || $remote->has_priv( "faqedit", "*" ) );    # FAQ admins can search too

            my $qtext     = $dbr->quote( $form_args->{searchtext} );
            my $dmid      = $form_args->{searchdomain} + 0;
            my $dmidwhere = $dmid ? "AND i.dmid=$dmid" : "";

            if ( $form_args->{searchwhat} eq "code" ) {
                $sql = qq{
                    SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l
                    WHERE l.lnid=$l->{'lnid'} AND l.dmid=i.dmid AND i.itid=l.itid $vis_flag
                    $dmidwhere AND LOCATE($qtext, i.itcode)
                };
            }
            else {
                my $lnid = $l->{'lnid'};
                $lnid = $l->{'parentlnid'} if $form_args->{searchwhat} eq "parent";

                $sql = qq{
                    SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l, ml_text t
                    WHERE l.lnid=$lnid AND l.dmid=i.dmid AND i.itid=l.itid
                    $dmidwhere AND t.dmid=l.dmid AND t.txtid=l.txtid
                    AND LOCATE($qtext, t.text) $vis_flag ORDER BY i.itcode
                };
            }
        }

        if ( $form_args->{search} eq 'flg' ) {
            return $err->("This type of search isn't available for this language.")
                unless $l->{'lncode'} eq $LJ::DEFAULT_LANG || !$l->{'parentlnid'};

            my $whereflags = join ' AND ',
                map  { $form_args->{"searchflag$_"} eq 'yes' ? "$_ = 1" : "$_ = 0" }
                grep { $form_args->{"searchflag$_"} ne 'whatev' } qw(proofed updated);
            $whereflags = "AND $whereflags" if $whereflags ne '';

            $sql = qq(
                SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l
                WHERE l.lnid=$l->{lnid} AND l.dmid=i.dmid AND l.itid=i.itid $whereflags $vis_flag
                ORDER BY i.dmid, i.itcode
            );
        }

        return $err->("Bogus or unimplemented query type.") unless $sql;
    }

    # each row contains 3 elements: (dmid, itid, itcode)
    $vars->{rows} = $dbr->selectall_arrayref($sql);

    # helper function for constructing links in template
    $vars->{join} = sub {
        my $pages = $_[0];
        return LJ::eurl( join( ",", map { "$_->[0]:$_->[1]" } @$pages ) );
    };

    return DW::Template->render_template( 'admin/translate/search.tt',
        $vars, { no_sitescheme => 1 } );
}

sub searchform_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;
    my $vars      = { lang => $form_args->{lang} };

    $vars->{l} = LJ::Lang::get_lang( $vars->{lang} );

    return $r->redirect('/admin/translate/') unless $vars->{l};

    $vars->{pl} = LJ::Lang::get_lang_id( $vars->{l}->{parentlnid} );

    $vars->{domains} = [ sort { $a->{dmid} <=> $b->{dmid} } LJ::Lang::get_domains() ];

    $vars->{def_lang} = $LJ::DEFAULT_LANG;

    return DW::Template->render_template( 'admin/translate/searchform.tt',
        $vars, { no_sitescheme => 1 } );
}

sub severity_controller {

    # this could be a static page if register_static supported no_sitescheme

    return DW::Template->render_template( 'admin/translate/help-severity.tt',
        {}, { no_sitescheme => 1 } );
}

sub welcome_controller {

    # this could be a static page if register_static supported no_sitescheme

    return DW::Template->render_template( 'admin/translate/welcome.tt', {},
        { no_sitescheme => 1 } );
}

1;
