#!/usr/bin/perl
#
# DW::Controller::Admin::SupportCat
#
# Support category admin page.
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::SupportCat;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;
use LJ::Support;
use LJ::TextUtil;
use DW::FormErrors;
use LJ::User;

DW::Routing->register_string( "/admin/supportcat/index", \&index_controller );
DW::Controller::Admin->register_admin_page( '/',
    path => 'supportcat/',
    ml_scope => '/admin/supportcat/index.tt',
    privs => [ 'siteadmin:support' ]
);

DW::Routing->register_string( "/admin/supportcat/category", \&category_controller );

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:support' ] );
    return $rv unless $ok;

    my $cats = LJ::Support::load_cats();
    my @cats = sort { $a->{sortorder} <=> $b->{sortorder} } values %$cats;

    my $vars = { %$rv, categories => \@cats };

    return DW::Template->render_template( 'admin/supportcat/index.tt', $vars );
}

sub category_controller {
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:support' ],
                                  form_auth => 1 );
    return $rv unless $ok;

    my $vars = { %$rv };

    my $r = DW::Request->get;

    my $args = $r->did_post ? $r->post_args : $r->get_args;
    my $catkey = LJ::text_trim( $args->{catkey}, 25, 0 );

    my $cats = LJ::Support::load_cats();
    my $cat = LJ::Support::get_cat_by_key( $cats, $catkey ) || {
                  catkey => $catkey,
                  catname => '',
                  sortorder => 0,
                  basepoints => 1,
                  is_selectable => 1,
                  public_read => 1,
                  public_help => 0, # Database default is wrong, wrong, WRONG
                  allow_screened => 1, # Likewise
                  hide_helpers => 0,
                  user_closeable => 1,
                  replyaddress => '',
                  no_autoreply => 0,
                  scope => 'general'
              };

    my $errors = DW::FormErrors->new;

    if ( $r->did_post ) {
        # Copy fields to $cat, normalizing at the same time.
        $cat->{catkey} = $catkey;
        $cat->{catname} = LJ::text_trim( $args->{catname}, 80, 0 );
        $cat->{$_} = $args->{$_} + 0 foreach ( qw( sortorder basepoints ) );
        $cat->{$_} = $args->{$_} ? 1 : 0
            foreach ( qw( is_selectable public_read public_help allow_screened
                          hide_helpers user_closeable no_autoreply ) );
        $cat->{replyaddress} = LJ::text_trim( $args->{replyaddress}, 50, 0 );
        $cat->{scope} = ( $args->{scope} eq 'local' ) ? 'local' : 'general';

        # Check for errors
        $errors->add( 'catkey', '.error.catkey_empty' ) if $cat->{catkey} eq '';
        $errors->add( 'catname', '.error.catname_empty' )
            if $cat->{catname} eq '';
        $errors->add( 'sortorder', '.error.sortorder_oob' )
            if $cat->{sortorder} < 0 || $cat->{sortorder} > 16777215;
        $errors->add( 'basepoints', '.error.basepoints_oob' )
            if $cat->{basepoints} < 0 || $cat->{basepoints} > 255;
        if ( $cat->{replyaddress} ) {
            my @errors = ();
            LJ::check_email( $cat->{replyaddress}, \@errors );
            $errors->add_string( 'replyaddress', $_ ) foreach @errors;
        }

        unless ( $errors->exist ) {
            if ( LJ::Support::define_cat( $cat ) ) {
                $vars->{saved} = 1;
            } else {
                $errors->add( 'no_such_variable', '.error.dberror' );
            }
        }
    }

    $vars->{cat} = $cat;
    $vars->{errors} = $errors;
    $vars->{newcat} = $args->{newcat};
    return DW::Template->render_template( 'admin/supportcat/category.tt', $vars );
}

1;
