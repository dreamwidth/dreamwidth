#!/usr/bin/perl
#
# DW::Hooks::NavStrip
#
# Implements logic for showing the navigation strip according to the Dreamwidth
# site logic.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::NavStrip;

LJ::register_hook( 'page_control_strip_options', sub {
    # if you add to the middle of the list, existing preferences will *break*
    return qw(
        journal.own
        readlist.own
        community.belongto
        community.notbelongto
        journal.watching
        journal.notwatching
        comment.custom
        journal.loggedout
        readlist.loggedout
    );
});

LJ::register_hook( 'show_control_strip', sub {

    return undef unless $LJ::USE_CONTROL_STRIP;
    return undef if $LJ::DISABLED{'control_strip'};

    my $remote = LJ::get_remote();
    my $r = DW::Request->get;
    my $journal = LJ::get_active_journal();

    # don't display if any of these are unavailable
    return undef unless $r && $journal;
    
    my @pageoptions = LJ::run_hook( 'page_control_strip_options' );
    return undef unless @pageoptions;

    my %pagemask = map { $pageoptions[$_] => 1 << $_ } 0..$#pageoptions;

    if ( $remote ) {

        my $display = $remote->control_strip_display;
        return undef unless $display;

        # customized comment pages (both entry and reply)
        if ( $r->note('view') eq 'entry' || $r->note('view') eq 'reply' ) {
            return $display & $pagemask{'comment.custom'};
        }

        # on your journal, all pages except readlist respect journal setting
        if ( $remote->equals( $journal ) ) {
            return $r->note( 'view' ) eq 'read'
                ? $display & $pagemask{'readlist.own'}
                : $display & $pagemask{'journal.own'};
        }

        if ( $journal->is_community ) {
            return $remote->member_of( $journal )
                ? $display & $pagemask{'community.belongto'}
                : $display & $pagemask{'community.notbelongto'};
        }

        # all other journal types (personal, openid, syn, news, staff)
        # readlist is treated by the same rule as all other journal pages
        return $remote->watches( $journal )
            ? $display & $pagemask{'journal.watching'}
            : $display & $pagemask{'journal.notwatching'};

    } else {
        my $display = $journal->control_strip_display;
        return undef unless $display;

        return $r->note( 'view' ) eq 'read'
            ?  $display & $pagemask{'readlist.loggedout'}
            : $display & $pagemask{'journal.loggedout'};
    }

    return undef;
});

LJ::register_hook( 'control_strip_stylesheet_link', sub {

    my $remote = LJ::get_remote();
    my $r = DW::Request->get;
    my $journal = LJ::get_active_journal();

    LJ::need_res('stc/controlstrip.css');

    my $color;
    my %GET = LJ::parse_args( $r->query_string );
    $color = $GET{style} eq 'mine' && $remote
        ? $remote->prop( 'control_strip_color' )
        : $journal->prop( 'control_strip_color' );
    $color = $color || 'dark';

    if ( $color ) {
        LJ::need_res("stc/controlstrip-$color.css");
        LJ::need_res("stc/controlstrip-${color}-local.css")
            if -e "$LJ::HOME/htdocs/stc/controlstrip-${color}-local.css";
    }
});

1;
