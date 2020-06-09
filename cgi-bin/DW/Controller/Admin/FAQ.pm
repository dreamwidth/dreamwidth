#!/usr/bin/perl
#
# DW::Controller::Admin::FAQ
#
# For adding, organizing, and maintaining FAQs.
# Requires faqadd, faqedit, and/or faqcat privileges.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::FAQ;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use LJ::Faq;

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'faq',
    ml_scope => '/admin/faq/index.tt',
    privs    => [ 'faqadd', 'faqedit', 'faqcat' ]
);

DW::Routing->register_string( '/admin/faq/index', \&index_handler, app => 1, no_cache => 1 );

sub _page_setup {
    my ($rv) = @_;

    my $vars   = {};
    my $remote = $rv->{remote};

    my %ac_add  = $remote->priv_args("faqadd");
    my %ac_edit = $remote->priv_args("faqedit");

    $vars->{can_add_any}  = %ac_add  ? 1 : 0;
    $vars->{can_edit_any} = %ac_edit ? 1 : 0;

    $vars->{can_add}  = sub { $ac_add{ $_[0] } };
    $vars->{can_edit} = sub { $ac_edit{ $_[0] } };

    $vars->{can_manage} = $remote->has_priv("faqcat");

    $vars->{display_faq} = sub {    # to display FAQ content properly
        return LJ::html_newlines( LJ::trim( $_[0] ) );
    };

    return $vars;
}

sub index_handler {
    my ( $ok, $rv ) = controller( privcheck => [ 'faqadd', 'faqedit', 'faqcat' ] );
    return $rv unless $ok;

    my $vars   = _page_setup($rv);
    my $remote = $rv->{remote};

    {    # load FAQ categories

        my $dbh = LJ::get_db_writer();

        my $faqcat =
            $dbh->selectall_hashref( "SELECT faqcat, faqcatname, catorder FROM faqcat", 'faqcat' );

        my @sorted_cats = sort { $faqcat->{$a}->{catorder} <=> $faqcat->{$b}->{catorder} }
            keys %$faqcat;

        # Ensure 'no category' is last.

        $faqcat->{''} = { faqcat => '', faqcatname => '<No Category>' };

        push @sorted_cats, '';

        $vars->{faqcat}  = $faqcat;
        $vars->{catlist} = \@sorted_cats;
    }

    {    # load FAQ questions

        my $dom  = LJ::Lang::get_dom("faq");
        my $lang = LJ::Lang::get_root_lang($dom);
        my @faqs = LJ::Faq->load_all( lang => $lang->{lncode}, allow_no_cat => 1 );

        my $user     = $remote->user;
        my $user_url = $remote->journal_base;

        LJ::Faq->render_in_place( { lang => $lang, user => $user, url => $user_url }, @faqs );

        # build hash of FAQs keyed by category
        $vars->{faq} = {};
        push( @{ $vars->{faq}->{ $_->faqcat // '' } }, $_ ) foreach @faqs;

        # in each category, produce a sorted list of FAQs in that category
        $vars->{faqlist} = sub {
            [ sort { $a->sortorder <=> $b->sortorder } @{ $vars->{faq}->{ $_[0] } } ]
        };
    }

    return DW::Template->render_template( 'admin/faq/index.tt', $vars );
}

1;
