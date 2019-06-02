#!/usr/bin/perl
#
# DW::Controller::Media
#
# Displays media for a user.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Media;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::BlobStore;
use DW::Routing;
use DW::Request;
use DW::Controller;
use DW::External::Site;
use POSIX;

my %VALID_SIZES =
    ( map { $_ => $_ } ( 100, 320, 200, 640, 480, 1024, 768, 1280, 800, 600, 720, 1600, 1200 ) );

DW::Routing->register_regex(
    qr!^/file/(\d+)$!, \&media_handler,
    user    => 1,
    formats => 1,
);
DW::Routing->register_regex(
    qr!^/file/(\d+x\d+|full)(/\w:[\d\w]+)*/(\d+)$!,
    \&media_handler,
    user    => 1,
    formats => 1,
);
DW::Routing->register_string( '/file/list', \&media_manage_handler,   app => 1 );
DW::Routing->register_string( '/file/edit', \&media_bulkedit_handler, app => 1 );
DW::Routing->register_string( '/file/new',  \&media_new_handler,      app => 1 );
DW::Routing->register_string( '/file',      \&media_index_handler,    app => 1 );

sub media_manage_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;
    return error_ml(
        'error.openid',
        {
            sitename => $LJ::SITENAMESHORT,
            aopts    => '/create'
        }
    ) if $rv->{remote}->is_identity;

    # load all of a user's media.  this is inefficient and won't be like this forever,
    # but it's simple for now...
    my @media = DW::Media->get_active_for_user( $rv->{remote}, width => 200, height => 200 );

    $rv->{media}          = \@media;
    $rv->{make_embed_url} = \&make_embed_url;
    $rv->{page}           = $rv->{r}->get_args->{page} || '1';
    $rv->{view_type}      = $rv->{r}->get_args->{view} || '';
    $rv->{maxpage}        = POSIX::ceil( scalar @media / 20 );
    $rv->{valid_sizes}    = [%VALID_SIZES];
    $rv->{convert_time}   = \&LJ::mysql_time;

    my $media_usage = DW::Media->get_usage_for_user( $rv->{u} );
    my $media_quota = DW::Media->get_quota_for_user( $rv->{u} );

    $rv->{usage}      = sprintf( "%0.3f MB", $media_usage / 1024 / 1024 );
    $rv->{quota}      = sprintf( "%0.1f MB", $media_quota / 1024 / 1024 );
    $rv->{percentage} = sprintf( "%0.1f%%",  $media_usage / $media_quota * 100 );

    return DW::Template->render_template( 'media/index.tt', $rv );
}

sub media_bulkedit_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;
    return error_ml(
        'error.openid',
        {
            sitename => $LJ::SITENAMESHORT,
            aopts    => '/create'
        }
    ) if $rv->{remote}->is_identity;

    my @security = (
        { value => "public",  text => LJ::Lang::ml('label.security.public2') },
        { value => "usemask", text => LJ::Lang::ml('label.security.accesslist') },
        { value => "private", text => LJ::Lang::ml('label.security.private2') },
    );
    $rv->{security} = \@security;

    my $r = DW::Request->get;
    if ( $r->did_post ) {
        my $post_args = $r->post_args;
        return error_ml('error.invalidauth')
            unless LJ::check_form_auth( $post_args->{lj_form_auth} );

        if ( $post_args->{"action:edit"} ) {
            my %post = %{ $post_args->as_hashref || {} };

            # transform our HTML field names to property names
            # and group by what media object they belong to
            # we don't care if the id or prop might not exist
            # right now, later steps will verify them

            my %props;
            while ( my ( $key, $val ) = each %post ) {
                next if $key eq "delete";
                next unless $key =~ m/^(\w+)-(\d+)/;
                my $mediaid = $2 >> 8;
                if ( exists $props{$mediaid} ) {
                    $props{$mediaid}{$1} = $val;
                }
                else {
                    $props{$mediaid} = { $1 => $val };
                }
            }

            # go through and try to fetch a media object from
            # each id, then try to set it's properties

            for my $media_key ( keys %props ) {
                my $media = DW::Media->new( user => $rv->{u}, mediaid => $media_key );
                next unless $media;

                while ( my ( $key, $val ) = each %{ $props{$media_key} } ) {
                    if ( $key eq 'security' ) {
                        my $amask = $val eq "usemask" ? 1 : 0;
                        $media->set_security( security => $val, allowmask => $amask );
                    }
                    else {
                        $media->prop( $key, $val );
                    }
                }
            }

        }
        elsif ( $post_args->{"action:delete"} ) {

            # FIXME: update with more efficient mass loader
            my @to_delete = $post_args->get_all("delete");
            foreach my $id (@to_delete) {

                # FIXME: error messages
                my $mediaid = $id >> 8;
                my $media   = DW::Media->new( user => $rv->{u}, mediaid => $mediaid );
                next unless $media;

                $media->delete;
            }
        }
    }

    my @media = DW::Media->get_active_for_user( $rv->{remote}, width => 200, height => 200 );

    my $media_usage = DW::Media->get_usage_for_user( $rv->{u} );
    my $media_quota = DW::Media->get_quota_for_user( $rv->{u} );

    $rv->{usage}      = sprintf( "%0.3f MB", $media_usage / 1024 / 1024 );
    $rv->{quota}      = sprintf( "%0.1f MB", $media_quota / 1024 / 1024 );
    $rv->{percentage} = sprintf( "%0.1f%%",  $media_usage / $media_quota * 100 );

    $rv->{ehtml}   = \&LJ::ehtml;
    $rv->{media}   = \@media;
    $rv->{page}    = $r->get_args->{page} || '1';
    $rv->{maxpage} = POSIX::ceil( scalar @media / 20 );
    return DW::Template->render_template( 'media/edit.tt', $rv );
}

sub media_handler {
    my ($opts) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;
    my $r = $rv->{r};

    # Outputs an error message
    my $error_out = sub {
        my ( $code, $message ) = @_;
        $r->status($code);
        return $r->NOT_FOUND if $code == 404;

        # don't cache transient error responses
        $r->header_out( "Cache-Control" => "no-cache" );

        $r->print($message);
        return $r->OK;
    };

    # Old format or new format detection
    my ( $size, $extra, $id ) = @{ $opts->subpatterns };
    my ( $width, $height );
    if ( $size =~ /^(\d+)x(\d+)$/ ) {
        ( $width, $height ) = ( $1, $2 );
    }
    elsif ( $size eq 'full' ) {

        # Do nothing, leave width/height undef
    }
    elsif ( $size =~ /^\d+$/ ) {

        # Should be old style format, so let's assume
        ( $id, $size, $extra ) = ( $size + 0, undef, undef );
    }
    else {
        return $error_out->( 404, 'Not found' );
    }

    # Ensure if a width or height are given, BOTH are given
    return $error_out->( 404, 'Not found' )
        if defined $width xor defined $height;

    # Constrain widths and heights to certain valid sets
    if ( defined $width ) {
        return $error_out->( 404, 'Not found' )
            unless exists $VALID_SIZES{$width}
            && exists $VALID_SIZES{$height};
    }

    # Finalize id and extension checking
    my $ext = $opts->{format};
    return $error_out->( 404, 'Not found' )
        unless $id && $ext;
    my $anum = $id % 256;
    $id = ( $id - $anum ) / 256;

    # Load the account or error
    return $error_out->( 404, 'Need account name as user parameter' )
        unless $opts->username;
    my $u = LJ::load_user_or_identity( $opts->username )
        or return $error_out->( 404, 'Invalid account' );

    # try to get the media object
    my $obj = DW::Media->new(
        user    => $u,
        mediaid => $id,
        width   => $width,
        height  => $height
    ) or return $error_out->( 404, 'Not found' );
    return $error_out->( 404, 'Not found' )
        unless $obj->is_active && $obj->anum == $anum && $obj->ext eq $ext;

    # access control
    my $remote  = $rv->{remote};
    my $viewall = $r->get_args->{viewall} ? 1 : 0;    # did they request it
    $viewall &&= defined $remote;                     # are they logged in
    $viewall &&= $remote->has_priv( 'canview', '*' ); # can they do it
    LJ::statushistory_add( $u->userid, $remote->userid, "viewall", $obj->url )
        if $viewall;
    return $error_out->( 403, 'Not authorized' )
        unless $viewall || $obj->visible_to($remote);

    # remote access, including crossposts
    my $refer_ok = sub {
        return 1 if LJ::check_referer();
        my @xpost = map { $_->{domain} } DW::External::Site->get_xpost_sites;
        my ($ref_dom) = $r->header_in("Referer") =~ m!^https?://([^/]+)!;
        foreach my $domain (@xpost) {
            return 1 if $ref_dom eq $domain;              # top level domain
            return 1 if $ref_dom =~ m!\.\Q$domain\E$!;    # subdomain
        }
        return 0;
    };
    return $error_out->( 403, 'Not authorized' )
        unless $refer_ok->();                             # limit offsite loading

    # load the data for this object
    my $dataref = DW::BlobStore->retrieve( media => $obj->mogkey );
    return $error_out->( 500, 'Unexpected internal error locating file' )
        unless defined $dataref && ref $dataref eq 'SCALAR';

    # now we're done!
    $r->set_last_modified( $obj->{logtime} ) if $obj->{logtime};
    $r->content_type( $obj->mimetype );
    $r->print($$dataref);
    return $r->OK;
}

sub media_new_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;
    return error_ml(
        'error.openid',
        {
            sitename => $LJ::SITENAMESHORT,
            aopts    => '/create'
        }
    ) if $rv->{remote}->is_identity;

    $rv->{security} = [
        { value => "public",  text => LJ::Lang::ml('label.security.public2') },
        { value => "usemask", text => LJ::Lang::ml('label.security.accesslist') },
        { value => "private", text => LJ::Lang::ml('label.security.private2') },
    ];

    $rv->{default_security} = $rv->{remote}->newpost_minsecurity;
    $rv->{default_security} = 'usemask' if $rv->{default_security} eq 'friends';

    return DW::Template->render_template( 'media/new.tt', $rv );
}

sub media_index_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $media_usage = DW::Media->get_usage_for_user( $rv->{u} );
    my $media_quota = DW::Media->get_quota_for_user( $rv->{u} );

    $rv->{usage}      = sprintf( "%0.3f MB", $media_usage / 1024 / 1024 );
    $rv->{quota}      = sprintf( "%0.1f MB", $media_quota / 1024 / 1024 );
    $rv->{percentage} = sprintf( "%0.1f%%",  $media_usage / $media_quota * 100 );

    return DW::Template->render_template( 'media/home.tt', $rv );
}

# a helper function to build the embed code, being sure to
# clean user-entered fields before outputing them.

sub make_embed_url {
    my ( $obj, %opts ) = @_;
    my $url   = $obj->full_url;
    my $alt   = $obj->prop('alttext') || '';
    my $title = $obj->prop('title') || '';
    my $embed;

    if ( defined $opts{type} && $opts{type} eq 'thumbnail' ) {
        my $thumb_url = $obj->url();
        $embed =
              "<a href='$url'><img src='$thumb_url' alt='"
            . LJ::ehtml($alt)
            . "' title='"
            . LJ::ehtml($title)
            . "'/></a>";
    }
    else {
        $embed =
            "<img src='$url' alt='" . LJ::ehtml($alt) . "' title='" . LJ::ehtml($title) . "' />";
    }

    return $embed;
}

1;
