#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Redirect;

use strict;

use DW::Controller;
use DW::Routing;

=head1 NAME

DW::Controller::Redirect - Redirects to a specific page given parameters

=head1 SYNOPSIS

=cut

DW::Routing->register_string( "/go", \&go_handler, app => 1 );

sub go_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 0 );
    return $rv unless $ok;

    my $ml_scope = "/go.bml";
    my %status;

    my $r = $rv->{r};
    if ( $r->did_post ) {
        my $post = $r->post_args;

        %status = monthview_url($post)
            if $post->{redir_type} eq "monthview";
    }
    else {
        my $get = $r->get_args;

        %status = threadroot_url($get)
            if ( $get->{redir_type} || "" ) eq "threadroot";

        %status = entry_nav_url($get)
            if $get->{itemid};
    }

    return $r->redirect( $status{url} ) if $status{url};

    my $error = $status{error} || ".defaultbody";
    return error_ml( $ml_scope . $error, $status{error_args} );
}

# S2 monthview
sub monthview_url {
    my ($args) = @_;
    my $user = LJ::canonical_username( $args->{redir_user} );
    my $vhost;
    $vhost = $args->{redir_vhost} if $args->{redir_vhost} =~ /users|tilde|community|front|other/;
    if ( $vhost eq "other" ) {

        # FIXME: lookup their domain alias, and make vhost be "other:domain.com";
    }
    my $base = LJ::journal_base( $user, vhost => $vhost );
    return ( error => ".error.redirkey" ) unless $args->{redir_key} =~ /^(\d\d\d\d)(\d\d)$/;
    my ( $year, $month ) = ( $1, $2 );
    return ( url => "$base/$year/$month/" );
}

# comment thread root
sub threadroot_url {
    my ($args) = @_;
    my $talkid = $args->{talkid} + 0;
    return unless $talkid;

    my $journal = $args->{journal};
    my $u       = LJ::load_user($journal);
    return unless $u;

    my $comment = eval { LJ::Comment->new( $u, dtalkid => $talkid ) };
    return ( error => ".error.nocomment" ) if $@;

    return ( error => ".error.noentry" ) unless $comment->entry && $comment->entry->valid;

    my $threadroot = LJ::Comment->new( $u, jtalkid => $comment->threadrootid );
    my $url        = eval { $threadroot->url( LJ::viewing_style_args(%$args) ) };
    return if $@;

    return ( url => $url );
}

# prev/next entry links
sub entry_nav_url {
    my ($args) = @_;

    my $itemid = $args->{itemid} + 0;
    return unless $itemid;

    my $journal = $args->{journal};
    my $u       = LJ::load_user($journal);
    return ( error => ".error.usernotfound" ) unless $u;

    my $journalid = $u->userid + 0;
    $itemid = int( $itemid / 256 );

    my $jumpid = 0;

    # if doing intra-tag, this exists
    my $tagnav = $u->get_keyword_id( $args->{redir_key}, 0 );

    if ( $args->{dir} eq "next" ) {
        $jumpid = LJ::get_itemid_after2( $u, $itemid, $tagnav );
        return ( error => '.error.noentry.next2', error_args => { journal => $u->ljuser_display } )
            unless $jumpid;
    }
    elsif ( $args->{dir} eq "prev" ) {
        $jumpid = LJ::get_itemid_before2( $u, $itemid, $tagnav );
        return ( error => '.error.noentry.prev2', error_args => { journal => $u->ljuser_display } )
            unless $jumpid;
    }
    return unless $jumpid;

    my $e      = LJ::Entry->new( $u, ditemid => $jumpid );
    my $anchor = $tagnav ? "tagnav-" . LJ::eurl( $args->{redir_key} ) : "";
    return ( url => $e->url( style_opts => LJ::viewing_style_opts(%$args), anchor => $anchor ) );
}

1;
