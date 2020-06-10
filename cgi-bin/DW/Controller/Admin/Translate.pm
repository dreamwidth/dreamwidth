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

DW::Routing->register_string( "/admin/translate/index",         \&index_controller,    app => 1 );
DW::Routing->register_string( "/admin/translate/edit",          \&edit_controller,     app => 1 );
DW::Routing->register_string( "/admin/translate/help-severity", \&severity_controller, app => 1 );
DW::Routing->register_string( "/admin/translate/welcome",       \&welcome_controller,  app => 1 );

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
