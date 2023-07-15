#!/usr/bin/perl
#
# DW::Widget::LatestNews
#
# The latest site news.
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

package DW::Widget::LatestNews;

use strict;
use base qw/ LJ::Widget /;
use DW::Template;

# define the news journal in your site config
sub should_render { $LJ::NEWS_JOURNAL ? 1 : 0; }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $news_journal = LJ::load_user($LJ::NEWS_JOURNAL)
        or return;

    # do getevents request
    my %res = ();
    LJ::do_request(
        {
            mode       => 'getevents',
            selecttype => 'one',
            ver        => $LJ::PROTOCOL_VER,
            user       => $news_journal->user,
            itemid     => -1
        },
        \%res,
        { noauth => 1 }
    );

    return unless $res{success} eq 'OK';

    my $entry = LJ::Entry->new( $news_journal,
        ditemid => ( $res{events_1_itemid} << 8 ) + $res{events_1_anum} );

    return unless $entry->valid;

    my $vars = {
        remote       => $remote,
        news_journal => $news_journal,
        entry        => $entry
    };

    my $ret = DW::Template->template_string( 'widget/latestnews.tt', $vars );

    LJ::warn_for_perl_utf8($ret);
    return $ret;
}

1;

