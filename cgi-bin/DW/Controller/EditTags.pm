#!/usr/bin/perl
#
# DW::Controller::EditTags
#
# Page for updating an entry's tags
#
# Authors:
#      Cocoa <momijizukamori@gmail.com>
#
# Copyright (c) 20123 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::EditTags;

use v5.10;
use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use LJ::Hooks;

DW::Routing->register_string( '/edittags', \&edittags_handler, app => 1 );

sub edittags_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;
    my $remote = $rv->{remote};

    my $scope = '/edittags.tt';

    my ( $ret, $msg );

    return error_ml("$scope.invalid.link")
        unless LJ::did_post() || ( $GET->{journal} && $GET->{itemid} );

    my $journal = $GET->{journal} || $POST->{journal};
    my $u       = LJ::load_user($journal);
    return error_ml("$scope.invalid.journal") unless $u;
    return error_ml("$scope.readonly.journal") if $u->is_readonly;
    return error_ml("$scope.invalid.journal") unless $u->is_visible;

    my $ditemid = ( $GET->{itemid} || $POST->{itemid} ) + 0;
    my $anum    = $ditemid % 256;
    my $jitemid = $ditemid >> 8;
    return error_ml("$scope.invalid.entry") unless $jitemid;

    my $logrow = LJ::get_log2_row( $u, $jitemid );
    return error_ml("$scope.invalid.entry") unless $logrow;
    return error_ml("$scope.invalid.entry") unless $logrow->{anum} == $anum;

    my $ent = LJ::Entry->new_from_item_hash($logrow)
        or die "Unable to create entry object.\n";
    return error_ml("$scope.invalid.notauthorized")
        unless $ent->visible_to($remote);

    if ( $r->did_post ) {
        my $tagerr = "";
        my $rv     = LJ::Tags::update_logtags(
            $u, $jitemid,
            {
                set_string => $POST->{edittags},
                remote     => $remote,
                err_ref    => \$tagerr,
            }
        );
        return error_ml($tagerr) unless $rv;
        return $r->msg_redirect( "Tags successfully updated", $r->SUCCESS, $ent->url );
    }

    my $lt2 = LJ::get_logtext2( $u, $jitemid );
    my ( $subj, $evt ) = @{ $lt2->{$jitemid} || [] };
    return error_ml("$scope.error.db") unless $evt;

    my ( %props, %opts );
    LJ::load_log_props2( $u->{userid}, [$jitemid], \%props );
    $opts{'preformatted'} = $props{$jitemid}{'opt_preformatted'};

    LJ::CleanHTML::clean_subject( \$subj );
    LJ::CleanHTML::clean_event( \$evt, \%opts );
    LJ::expand_embedded( $u, $ditemid, $remote, \$evt );

    # prevent BML tags interpretation inside post body
    $subj =~ s/<\?/&lt;?/g;
    $subj =~ s/\?>/?&gt;/g;
    $evt  =~ s/<\?/&lt;?/g;
    $evt  =~ s/\?>/?&gt;/g;

    my $logtags  = LJ::Tags::get_logtags( $u, $jitemid );
    my $usertags = LJ::Tags::get_usertags( $u, { remote => $remote } ) || {};
    my @usertags;
    if ( scalar keys %$usertags ) {
        @usertags = sort { $a->{name} cmp $b->{name} } values %$usertags;
    }
    $logtags = $logtags->{$jitemid} || {};
    my $logtagstr = join ', ', map { LJ::ejs($_) } sort values %$logtags;

    my $vars = {
        u         => $u,
        journal   => $journal,
        ent       => $ent,
        logtagstr => $logtagstr,
        edittags  => ( join ', ', sort values %$logtags ),
        remote    => $remote,
        can_add_entry_tags =>
            LJ::Tags::can_add_entry_tags( $remote, LJ::Entry->new( $u, ditemid => $ditemid ) ),
        itemid           => $GET->{itemid} || $POST->{itemid},
        subj             => $subj,
        evt              => $evt,
        can_control_tags => \&LJ::Tags::can_control_tags,
        usertags         => \@usertags,
    };

    return DW::Template->render_template( 'edittags.tt', $vars );
}

1;
