#!/usr/bin/perl
#
# DW::Hooks::Community
#
# This file contains the hooks used to show DW-specific FAQs and comms
# on community/index.bml.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2011-2013 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.

package DW::Hooks::Community;

use strict;
use LJ::Hooks;

# returns: dreamwidth.org specific FAQs for info on communities. calling
# context should already have the <ul> inside it, so just <li> on each.
LJ::Hooks::register_hook(
    'community_faqs',
    sub {

        my $ret;
        my @faqs = qw/ 223 17 201 /;

        foreach my $faq (@faqs) {
            my $faqobj = LJ::Faq->load($faq);
            $ret .=
                  "<li><a href='$LJ::SITEROOT/support/faqbrowse?faqid="
                . $faq . "'>"
                . $faqobj->question_html
                . "</a></li>"
                if $faqobj;
        }

        return $ret;
    }
);

# returns: dreamwidth.org specific FAQs for info on managing communities.
# calling context should already have the <ul> inside it, so just a <li>
# on each.
LJ::Hooks::register_hook(
    'community_manage_links',
    sub {

        my $ret;
        my @faqs = qw/ 19 100 208 101 102 109 205 110 111 /;

        foreach my $faq (@faqs) {
            my $faqobj = LJ::Faq->load($faq);
            $ret .=
                  "<li><a href='$LJ::SITEROOT/support/faqbrowse?faqid="
                . $faq . "'>"
                . $faqobj->question_html
                . "</a></li>"
                if $faqobj;
        }

        return $ret;
    }
);

# returns: dw_community_promo, formatted as user tag, with explanation
LJ::Hooks::register_hook(
    'community_search_links',
    sub {
        my $ret;
        my $promo = LJ::load_user("dw_community_promo");
        return unless $promo;

        $ret .= "<li>"
            . $promo->ljuser_display . ": "
            . LJ::Lang::ml('/community/index.tt.promo.explain') . "</li>";
        return $ret;
    }
);

# returns: a selection of dreamwidth.org official comms for people to
# subscribe to. (only public-facing official comms, or things that might
# be of use to the general public -- none of the project-specific comms
# that aren't available for general membership.)
LJ::Hooks::register_hook(
    'official_comms',
    sub {
        my $ret;
        my @official =
            qw/ dw_news dw_maintenance dw_biz dw_suggestions dw_nifty dw_dev dw_styles dw_design /;

        $ret .= "<h2>"
            . LJ::Lang::ml( '/community/index.tt.official.title',
            { sitename => $LJ::SITENAMESHORT } )
            . "</h2>"
            . LJ::Lang::ml( '/community/index.tt.official.explain',
            { sitename => $LJ::SITENAMESHORT } )
            . "<ul>";

        foreach my $comm (@official) {
            my $commu = LJ::load_user($comm);
            $ret .= "<li>" . $commu->ljuser_display . "</li>" if $commu;
        }

        $ret .= "</ul>";

        return $ret;
    }
);

1;
