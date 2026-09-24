#!/usr/bin/perl
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

# Copyright (c) 2026 by Dreamwidth Studios, LLC.

package DW::Controller::ImageDialog;
use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/imguploadrte', \&dialog_handler, app => 1, no_cache => 1 );

# FCK's split legacy bundles still request this static-tree spelling.  Static
# pass-through must reach the same standalone native dialog, including .bml.
DW::Routing->register_string(
    '/stc/fck/editor/dialog/imguploadrte', \&dialog_handler,
    app      => 1,
    no_cache => 1
);

sub dialog_handler {

    # POST only redisplays this dialog; no entry or upload is changed here.
    my ( $ok, $rv ) = controller( form_auth => 0 );
    return $rv unless $ok;
    my $r = $rv->{r};

    my $label = LJ::Lang::ml('/entry/image-dialog.tt.insertimage.alt.faqlink');
    $rv->{faq} = LJ::Hooks::run_hook( 'faqlink', 'alttext', $label ) || $label;

    # FCK owns this standalone document and requires the legacy DOM helpers.
    LJ::set_active_resource_group('default');
    LJ::need_res( 'stc/display_none.css', 'js/browserdetect.js' );
    $rv->{resources} = LJ::res_includes();
    $r->content_type('text/html; charset=utf-8');
    return DW::Template->render_template( 'entry/image-dialog.tt', $rv, { no_sitescheme => 1 } );
}

1;
