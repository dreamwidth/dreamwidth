#!/usr/bin/perl
#
# DW::Controller::Support::Submit
#
# Controller for submitting a new support request, converted from
# /support/submit.bml, LJ::Widget::SubmitRequest, and
# LJ::Widget::SubmitRequest::Support
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Support::Submit;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

DW::Routing->register_string( '/support/submit', \&submit_handler, app => 1 );

sub submit_handler {
    my ( $opts ) = @_;

    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $remote = LJ::get_remote();

    my $vars = {};

    if ( $r->did_post ) {
        my $post_args = $r->post_args;
        my $errors = DW::FormErrors->new;
        my %req = ();

        if ( $remote ) {
            $req{reqtype} = 'user';
            $req{requserid} = $remote->id;
            $req{reqemail} = $remote->email_raw || $post_args->{email};
            $req{reqname} = $remote->name_html;
        } else {
            $req{reqtype} = 'email';
            $req{reqemail} = $post_args->{email};
            $req{reqname} = $post_args->{reqname};
        }

        if ( $post_args->{email} ) {
            my @errors = ();
            LJ::check_email( $post_args->{email}, \@errors, $post_args, \( $vars->{email_checkbox} ) );
            $errors->add_string( 'email', $_ ) foreach @errors;
        } elsif ( $req{reqtype} eq 'email' ) {
            $errors->add( 'email', '.error.email.required' );
        }

        unless ( $remote ) {
            my $captcha = DW::Captcha->new( 'support_submit_anon',
                                            %{$post_args || {}} );
            my $captcha_error;
            $errors->add_string( 'no_such_variable', $captcha_error )
                unless $captcha->validate( err_ref => \$captcha_error );
        }

        if ( LJ::is_enabled( 'support_request_language' ) ) {
            $req{language} = $post_args->{language};
            $req{language} = $LJ::DEFAULT_LANG
                unless grep { $req{language} eq $_ } ( @LJ::LANGS, 'xx' );
        }

        $req{body} = $post_args->{message};
        $req{subject} = $post_args->{subject};
        $req{spcatid} = $post_args->{spcatid};
        $req{uniq} = LJ::UniqCookie->current_uniq;
        $req{no_autoreply} = 0;

        # insert diagnostic information
        $req{useragent} = $r->header_in( 'User-Agent' )
            if $LJ::SUPPORT_DIAGNOSTICS{track_useragent};

        unless ( $errors->exist ) {
            my @errors = ();
            my $spid = LJ::Support::file_request( \@errors, \%req );
            if ( @errors ) {
                $errors->add_string( 'no_such_variable', $_ ) foreach @errors;
            } else {
                my $auth = LJ::Support::mini_auth( LJ::Support::load_request( $spid, undef, { db_force => 1 } ) );
                $vars->{url} = "$LJ::SITEROOT/support/see_request?id=$spid&amp;auth=$auth";
            }
        }

        $vars->{errors} = $errors;
        $vars->{$_} = $post_args->{$_}
            foreach ( qw( reqname email spcatid subject message ) );
        $vars->{language} = $post_args->{language}
            if LJ::is_enabled( 'support_request_language' );
    }

    # If not logged in and logged-out requests are disabled, give a fatal error
    unless ( $remote || LJ::is_enabled( 'loggedout_support_requests' ) ) {
        my $errors = DW::FormErrors->new;
        $errors->add( 'no_such_variable', '.error.mustbeloggedin' );
        $vars->{errors} = $errors;
        $vars->{fatal_errors} = 1;
    }

    # Include name if not logged in, email address if not logged in or empty
    $vars->{include_name} = $remote ? 0 : 1;
    $vars->{include_email} = ($remote && $remote->email_raw) ? 0 : 1;

    my $cats = LJ::Support::load_cats();
    my $catarg = $r->get_args->{cat} || $r->get_args->{category};
    my $cat;
    if ( ( $cat = LJ::Support::get_cat_by_key( $cats, $catarg ) )
        && $cat->{is_selectable} ) {
        # Passed in ?category=, display name and hide spcatid
        $vars->{spcatid} = $cat->{spcatid};
        $vars->{catname} = $cat->{catname};
        $vars->{cat_type} = 'fixed';
    } else {
        # Not forced, offer dropdown
        $vars->{cat_type} = 'dropdown';
        my @cat_list = ();
        my $has_nonpublic = 0;

        foreach my $cat ( sort { $a->{sortorder} <=> $b->{sortorder} }
                              values %$cats ) {
            next unless $cat->{is_selectable};

            my $catname = $cat->{catname};
            unless ( $cat->{public_read} ) {
                $catname .= "*";
                $has_nonpublic = 1;
            }

            push @cat_list, { spcatid => $cat->{spcatid}, catname => $catname };
        }

        $vars->{cat_list} = \@cat_list;
        $vars->{cat_has_nonpublic} = $has_nonpublic;
    }

    if ( LJ::is_enabled( "support_request_language" ) ) {
        my $lang_list = LJ::Lang::get_lang_names();
        my @langs = ();
        for ( my $i = 0; $i < @$lang_list; $i = $i+2 ) {
            push @langs, { id => $lang_list->[$i], name => $lang_list->[$i+1] }
                if $LJ::LANGS_FOR_SUPPORT_REQUESTS{$lang_list->[$i]}
        }

        $vars->{language} ||= $LJ::DEFAULT_LANG;
        # Pushing xx in template to avoid dealing with ML scope issues here
        $vars->{lang_list} = \@langs;
    }

    # Defer captcha creation until template is rendered
    $vars->{print_captcha} = sub { return DW::Captcha->new( $_[0] )->print; }
        if !$remote && DW::Captcha->enabled( 'support_submit_anon' );

    return DW::Template->render_template( 'support/submit.tt', $vars );
}

1;
