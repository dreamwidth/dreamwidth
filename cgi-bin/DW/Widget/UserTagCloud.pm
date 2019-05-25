#!/usr/bin/perl
#
# DW::Widget::UserTagCloud
#
# User's tag cloud
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

package DW::Widget::UserTagCloud;

use strict;
use base qw/ LJ::Widget /;

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return "";

    my $tags = $remote->tags;
    return "" unless $tags;

    my $limit = $opts{limit} || 10;
    my $ret   = "<h2>" . $class->ml('widget.usertagcloud.title') . "</h2>";

    my @by_size = sort { $tags->{$b}->{uses} <=> $tags->{$a}->{uses} } keys %$tags;
    @by_size = splice @by_size, 0, $limit;
    my %popular_tags = map { $_ => 1 } @by_size;

    my $tag_items;
    my $tag_base_url = $remote->journal_base . "/tag/";
    while ( my ( $id, $tag ) = each %$tags ) {
        next unless $popular_tags{$id};
        $tag_items->{ $tag->{name} } = {
            url   => $tag_base_url . LJ::eurl( $tag->{name} ),
            value => $tag->{uses},
        };
    }

    $ret .= LJ::tag_cloud($tag_items);
    return $ret;
}

1;

