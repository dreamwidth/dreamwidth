#!/usr/bin/perl
# Standalone iframe used by the rich-text editor's image dialog.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.

package DW::Controller::ImagePreview;
use strict;
use warnings;
use DW::Request;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/imgpreview', \&preview_handler, app => 1 );

sub preview_handler {
    DW::Request->get->content_type('text/html; charset=utf-8');
    return DW::Template->render_template( 'entry/image-preview.tt', {}, { no_sitescheme => 1 } );
}

1;
