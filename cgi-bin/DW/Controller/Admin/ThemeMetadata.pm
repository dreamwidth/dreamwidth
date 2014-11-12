#!/usr/bin/perl
#
# DW::Controller::Admin::ThemeMetadata
#
# Theme metadata admin page.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::ThemeMetadata;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

DW::Routing->register_string( "/admin/themes/index", \&index_controller );
DW::Controller::Admin->register_admin_page( '/',
    path => 'themes/',
    ml_scope => '/admin/themes/index.tt',
    privs => [ 'siteadmin:themes' ]
);

DW::Routing->register_string( "/admin/themes/theme", \&theme_controller );
DW::Routing->register_string( "/admin/themes/category", \&category_controller );

my %system_cats = (
    featured => 1,
);

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:themes" ] );
    return $rv unless $ok;

    my $pub = LJ::S2::get_public_layers();

    my @themes = grep { $_ !~ /^\d+$/ && $pub->{$_}->{type} eq 'theme' } keys %$pub;
    my %layers = ();
    foreach my $uniq ( @themes ) {
        my ( $lay, $theme ) = split('/', $uniq);
        push @{ $layers{$lay} }, $theme;
    }

    my $vars = {
        %$rv,

        layers => \%layers,
        categories => [ LJ::S2Theme->all_categories( all => 1, special => 1 ) ],
    };

    return DW::Template->render_template( 'admin/themes/index.tt', $vars );
}

sub _validate_category {
    return 1 if $_[0] =~ /^[a-zA-Z0-9 ]+$/;
    return 0;
}

sub theme_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:themes" ] );
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $args = $r->did_post ? $r->post_args : $r->get_args;
    my $uniq = $args->{theme};
 
    my $pub = LJ::S2::get_public_layers();
    my $s2lid = $pub->{$uniq}->{s2lid};
    return $r->redirect( "/admin/themes/" ) unless $s2lid;
    
    my $theme = LJ::S2Theme->new( themeid => $s2lid );
    return $r->redirect( "/admin/themes/" ) unless $theme;

    if ( $r->method eq 'POST' ) {
        return $r->redirect( "/admin/themes/theme?theme=$uniq" ) unless LJ::check_form_auth( $args->{lj_form_auth} );

        # FIXME: This should be in S2Themes
        my $cats = $theme->metadata->{cats};
        my %kwid_map = map { $_->{kwid} => $_ } values %$cats;
        my @kwids = keys %kwid_map;

        my %change_act;
        my %delete;

        foreach my $kwid ( @kwids ) {
            my $act_db = $kwid_map{$kwid}->{active};
            if ( $args->{"cat_remove_$kwid"} ) {
                $delete{$kwid} = 1;
            } else {
                $change_act{$kwid} = 1
                    if $args->{"cat_act_$kwid"} && ! $act_db;
                $change_act{$kwid} = 0
                    if ! $args->{"cat_act_$kwid"} && $act_db
                        && exists $kwid_map{$kwid};
            }
        }

        foreach my $kw ( split(',', $args->{cat_add} ) ) {
            $kw = LJ::trim( $kw );
            next unless _validate_category( $kw );
            my $kwid = LJ::get_sitekeyword_id( $kw, 1, allowmixedcase => 1 );
            next if $delete{ $kwid };
            my $add = 1;
            $add = 0 if $kwid_map{$kwid} && $kwid_map{$kwid}->{active};
            $change_act{$kwid} = 1 if $add;
        }

        my $dbh = LJ::get_db_writer();

        if ( %change_act ) { 
            my @bind;
            my @vals;

            foreach my $kwid ( keys %change_act ) {
                push @vals, "(?,?,?)";
                push @bind, ( $s2lid, $kwid, $change_act{$kwid} );
            }

            $dbh->do( "REPLACE INTO s2categories ( s2lid, kwid, active ) " .
                "VALUES " . join( ',', @vals ), undef, @bind )
                    or die $dbh->errstr;
        }

        if ( %delete ) {
            $dbh->do( "DELETE FROM s2categories where s2lid = ? " .
                "AND kwid IN ( " .
                join( ',', map { $dbh->quote( $_ ) } keys %delete ) .
                " )", undef, $s2lid ) or die $dbh->errstr;
        }

        $theme->clear_cache;
        LJ::S2Theme->clear_global_cache;
        return $r->redirect( "/admin/themes/theme?theme=$uniq" );
    }
    
    my %cats = %{ $theme->metadata->{cats} };

    my @cat_keys = sort {
        my $ah = $cats{$a};
        my $bh = $cats{$b};
        return ( $ah->{order} || 0 ) <=> ( $bh->{order} || 0 ) ||
            ( $bh->{active} || 0 )  <=> ( $ah->{active} || 0 ) ||
            $ah->{keyword} cmp $bh->{keyword}
    } keys %cats;

    my $vars = {
        %$rv,

        theme_arg => $uniq,
        theme => $theme,
        cats => \%cats,
        cat_keys => \@cat_keys,
    };

    return DW::Template->render_template( 'admin/themes/theme.tt', $vars );
}

sub category_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:themes" ] );
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $args = $r->did_post ? $r->post_args : $r->get_args;
    my $cat = $args->{category};

    $cat = undef unless _validate_category( $cat );
    return $r->redirect( "/admin/themes/" ) unless $cat;

    my $pub = LJ::S2::get_public_layers();

    my @themes = grep { $_ !~ /^\d+$/ && $pub->{$_}->{type} eq 'theme' } keys %$pub;
    my %layers = ();
    foreach my $uniq ( @themes ) {
        my ( $lay, $theme ) = split('/', $uniq);
        $layers{$lay}->{$theme} = $pub->{$uniq};
    }

    my %s2lid_act = map { $_->s2lid => 1 } LJ::S2Theme->load_by_cat( $cat );

    my $can_delete = 0;
    my $is_system = $system_cats{$cat} ? 1 : 0;

    $can_delete = ( %s2lid_act ? 0 : 1 ) unless $is_system;

    if ( $r->method eq 'POST' ) {
        return $r->redirect( "/admin/themes/category?category=$cat" ) unless LJ::check_form_auth( $args->{lj_form_auth} );

        my $dbh = LJ::get_db_writer();

        if ( $args->{delete} ) {
            return $r->redirect( "/admin/themes/category?category=$cat" )
                unless $can_delete;

            my $kwid = LJ::get_sitekeyword_id( $cat, 1, allowmixedcase => 1 );
            my $to_clear = $dbh->selectall_arrayref( "SELECT s2lid FROM s2categories WHERE kwid = ?", undef, $kwid ) or die $dbh->errstr;

            $dbh->do( "DELETE FROM s2categories WHERE kwid = ?", undef, $kwid ) or die $dbh->errstr;

            LJ::S2Theme->new( themeid => $_->[0] )->clear_cache
                foreach @$to_clear;
            LJ::S2Theme->clear_global_cache;

            return $r->redirect( "/admin/themes/" );
        } else {
            my %change_act;
            foreach my $theme ( @themes ) {
                my $s2lid = $pub->{$theme}->{s2lid};
                my $db_act = $s2lid_act{ $s2lid };
                my $act = $args->{ "s2lid_act_$s2lid" } || 0;

                $change_act{$s2lid} = 1 if $act && ! $db_act; 
                $change_act{$s2lid} = 0 if ! $act && $db_act; 
            }

            if ( %change_act ) { 
                my @bind;
                my @vals;

                my $kwid = LJ::get_sitekeyword_id( $cat, 1, allowmixedcase => 1 ); 
                foreach my $s2lid ( keys %change_act ) {
                    push @vals, "(?,?,?)";
                    push @bind, ( $s2lid, $kwid, $change_act{$s2lid} );
                }

                $dbh->do( "REPLACE INTO s2categories ( s2lid, kwid, active ) " .
                    "VALUES " . join(',', @vals), undef, @bind )
                        or die $dbh->errstr;
            }

            LJ::S2Theme->new( themeid => $_ )->clear_cache
                foreach keys %change_act;
            LJ::S2Theme->clear_global_cache;
            return $r->redirect( "/admin/themes/category?category=$cat" );
        }
    }

    my $vars = {
        %$rv,

        category => $cat,
        layers => \%layers,
        active => \%s2lid_act,
        can_delete => $can_delete,
        is_system => $is_system,
    };

    return DW::Template->render_template( 'admin/themes/category.tt', $vars );
}

1;
