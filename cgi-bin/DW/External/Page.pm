#!/usr/bin/perl
#
# DW::External::Page
#
# This class is for Page objects, which hold information from pages on other sites.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Page;

use strict;
use warnings;
use HTML::TokeParser;

sub new {
    my ( $class, %opts ) = @_;

    my $url = LJ::durl( $opts{url} );
    return undef unless $url;

    my $ua = LJ::get_useragent( role => 'share' );
    $ua->agent($LJ::SITENAME);
    my $res     = $ua->get($url);
    my $content = $res && $res->is_success ? $res->content : undef;
    return undef unless $content;

    my $p = HTML::TokeParser->new( \$content );

    my $title;
    if ( $p->get_tag('title') ) {
        $title = $p->get_trimmed_text;
    }

    my $description;
    while ( my $token = $p->get_tag('meta') ) {
        next unless $token->[1]{name} && $token->[1]{name} eq 'description';
        $description = LJ::trim( $token->[1]{content} )
            if $token->[1]{content};
    }

    return bless {
        url         => $url,
        title       => $title || '',
        description => $description || '',
    }, $class;
}

sub url         { $_[0]->{url} }
sub title       { $_[0]->{title} }
sub description { $_[0]->{description} }

1;
