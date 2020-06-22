# DW::Controller::Editor
#
# Single-purpose routes for setting the editor userprops, which determine the
# default formatting type when writing new entries/comments/etc in the web UI.
#
# Authors:
#   Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Controller::Editor;

use strict;
use LJ::JSON;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Formats;
use Carp;

DW::Routing->register_string( "/default_editor", \&default_editor_handler, app => 1 );

DW::Routing->register_rpc(
    "default_editor", \&default_editor_rpc_handler,
    format  => 'json',
    methods => { POST => 1 },
);

# Returns (1, "format_id") on success, (0, "error") on error.
sub default_editor_helper {
    my ( $remote, $type, $new_editor ) = @_;
    my $userprop;

    my $err = sub { return ( 0, $_[0] ); };

    return $err->('nouser') unless $remote;

    $new_editor = DW::Formats::validate($new_editor);

    if ( $type eq 'comment' ) {
        $userprop = 'comment_editor';
    }
    elsif ( $type eq 'entry' ) {
        $userprop = 'entry_editor2';
    }
    else {
        return $err->('unknowntype');
    }

    $remote->set_prop( $userprop, $new_editor );
    return ( 1, $new_editor );
}

# zero-javascript version
sub default_editor_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $remote = $rv->{remote};
    return error_ml('/default_editor.tt.error.nouser') unless $remote;

    my $type       = $POST->{type};
    my $new_editor = $POST->{new_editor};
    my $exit_text  = $POST->{exit_text};
    my $exit_url   = $POST->{exit_url};

    my ( $set_ok, $set_result ) = default_editor_helper( $remote, $type, $new_editor );

    unless ($set_ok) {
        return error_ml( "/default_editor.tt.error.$set_result", { type => $type } );
    }

    return DW::Template->render_template(
        'default_editor.tt',
        {
            title      => ".title.$type",
            type       => $type,
            new_format => DW::Formats::display_name($set_result),
            exit_text  => $exit_text,
            exit_url   => $exit_url,
        }
    );
}

sub default_editor_rpc_handler {
    my $r    = DW::Request->get;
    my $POST = $r->post_args;

    # make sure we have a user of some sort
    my $remote = LJ::get_remote();
    return DW::RPC->err('Unable to load user for call.') unless $remote;

    my $type       = $POST->{type};
    my $new_editor = $POST->{new_editor};

    my ( $set_ok, $set_result ) = default_editor_helper( $remote, $type, $new_editor );

    return DW::RPC->err( LJ::Lang::ml( "/default_editor.tt.error.$set_result", { type => $type } ) )
        unless $set_ok;

    return DW::RPC->out(
        success    => 1,
        new_editor => $set_result,
        message    => LJ::ehtml(
            LJ::Lang::ml(
                '/default_editor.tt.success',
                { type => $type, new_format => DW::Formats::display_name($set_result) }
            )
        )
    );
}

1;
