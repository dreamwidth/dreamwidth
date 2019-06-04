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

use strict;
use LJ::Hooks;

LJ::Hooks::register_hook(
    'page_control_strip_options',
    sub {
        # if you add to the middle of the list, existing preferences will *break*
        return qw(
            journal.this
            journal.withrelationship
            journal.norelationship
        );
    }
);

LJ::Hooks::register_hook(
    'show_control_strip',
    sub {
        return undef unless LJ::is_enabled('control_strip');

        my $remote  = LJ::get_remote();
        my $r       = DW::Request->get;
        my $journal = LJ::get_active_journal();

        return undef if $r->note('no_control_strip');

        # don't display if any of these are unavailable
        return undef unless $r && $journal;

        my @pageoptions = LJ::Hooks::run_hook('page_control_strip_options');
        return undef unless @pageoptions;

        my %pagemask = map { $pageoptions[$_] => 1 << $_ } 0 .. $#pageoptions;

        if ($remote) {

            my $display = $remote->control_strip_display;
            return undef unless $display;

            return $display & $pagemask{'journal.this'} if $remote->equals($journal);

            return $display & $pagemask{'journal.withrelationship'}
                if ( $journal->is_community && $remote->member_of($journal) )
                || $remote->watches($journal)
                || $remote->trusts($journal);

            return $display & $pagemask{'journal.norelationship'};

        }
        else {
            my $display = $journal->control_strip_display;
            return undef unless $display;

            # logged out users follow journal preferences
            return $display & $pagemask{'journal.this'};
        }

        return undef;
    }
);

LJ::Hooks::register_hook(
    'control_strip_stylesheet_link',
    sub {

        my $remote  = LJ::get_remote();
        my $r       = DW::Request->get;
        my $journal = LJ::get_active_journal();

        LJ::need_res('stc/controlstrip.css');

        my $color;
        $color =
              $remote
            ? $remote->prop('control_strip_color')
            : $journal->prop('control_strip_color');
        $color = $color || 'dark';

        if ($color) {
            LJ::need_res("stc/controlstrip-$color.css");
            LJ::need_res("stc/controlstrip-${color}-local.css")
                if -e "$LJ::HTDOCS/stc/controlstrip-${color}-local.css";
        }
    }
);

1;
