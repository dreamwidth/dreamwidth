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
use DW::Media;
use HTTP::Status qw(HTTP_CONFLICT);
use POSIX;

my %VALID_SIZES =
    ( map { $_ => $_ } ( 100, 320, 200, 640, 480, 1024, 768, 1280, 800, 600, 720, 1600, 1200 ) );

DW::Routing->register_regex(
    qr!^/file/(\d+)$!, \&media_handler,
    user     => 1,
    formats  => 1,
    no_cache => 1,
);
DW::Routing->register_regex(
    qr!^/file/(\d+x\d+|full)(/\w:[\d\w]+)*/(\d+)$!,
    \&media_handler,
    user     => 1,
    formats  => 1,
    no_cache => 1,
);
DW::Routing->register_string( '/file/list', \&media_manage_handler,   app => 1 );
DW::Routing->register_string( '/file/edit', \&media_bulkedit_handler, app => 1 );
DW::Routing->register_string( '/file/new',  \&media_new_handler,      app => 1 );
DW::Routing->register_string( '/file',      \&media_index_handler,    app => 1 );

sub media_manage_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my ( $remote, $r ) = ( $rv->{remote}, $rv->{r} );

    return error_ml(
        'error.openid',
        {
            sitename => $LJ::SITENAMESHORT,
            aopts    => '/create'
        }
    ) if $remote->is_identity;

    my $u         = $remote;
    my $adminmode = $u && $u->has_priv( 'canview', 'images' );
    my $user      = LJ::canonical_username( $r->get_args->{user} || $r->post_args->{user} );

    if ( $adminmode && $user ) {
        $u = LJ::load_user($user);
        return error_ml('error.username_notfound') unless $u;
        return error_ml('error.purged.text') if $u->is_expunged;
        $user = undef if $remote->equals($u);
    }
    else {
        $user = undef;
    }

    # load all of a user's media.  this is inefficient and won't be like this forever,
    # but it's simple for now...
    my @media = DW::Media->get_active_for_user( $u, width => 200, height => 200 );

    $rv->{media}          = \@media;
    $rv->{make_embed_url} = \&make_embed_url;
    $rv->{page}           = $r->get_args->{page} || '1';
    $rv->{view_type}      = $r->get_args->{view} || '';
    $rv->{maxpage}        = POSIX::ceil( scalar @media / 20 );
    $rv->{valid_sizes}    = [%VALID_SIZES];
    $rv->{convert_time}   = \&LJ::mysql_time;
    $rv->{adminmode}      = $adminmode ? 1 : 0;
    $rv->{user}           = $user;

    my $media_usage = DW::Media->get_usage_for_user($u);
    my $media_quota = DW::Media->get_quota_for_user($u);

    $rv->{usage}      = sprintf( "%0.3f MB", $media_usage / 1024 / 1024 );
    $rv->{quota}      = sprintf( "%0.1f MB", $media_quota / 1024 / 1024 );
    $rv->{percentage} = sprintf( "%0.1f%%",  $media_usage / $media_quota * 100 );

    return DW::Template->render_template( 'media/index.tt', $rv );
}

sub security_form_options {
    my ($rv)     = @_;
    my $groups   = $rv->{u}->trust_groups( force_database => 1 ) or return;
    my $revision = $rv->{u}->trust_group_revision;
    return unless defined $revision;

    my @groups = sort { $a->{sortorder} <=> $b->{sortorder} || $a->{groupname} cmp $b->{groupname} }
        grep { $_->{groupnum} >= 1 && $_->{groupnum} <= 60 } values %$groups;
    $rv->{security} = [
        { value => "public",  text => LJ::Lang::ml('label.security.public2') },
        { value => "usemask", text => LJ::Lang::ml('label.security.accesslist') },
        { value => "private", text => LJ::Lang::ml('label.security.private2') },
    ];
    $rv->{custom_groups}  = \@groups;
    $rv->{group_revision} = $revision;
    push @{ $rv->{security} }, { value => 'custom', text => LJ::Lang::ml('label.security.custom') }
        if @groups;
    return 1;
}

sub media_security_error {
    my ( $r, $status, $message ) = @_;
    $r->status($status);
    return DW::Template->render_template( 'error.tt', { message => $message } );
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

    my $r = DW::Request->get;
    my ( $lock, $groups, $revision );
    if ( $r->did_post ) {
        my $post_args = $r->post_args;
        return error_ml('error.invalidauth')
            unless LJ::check_form_auth( $post_args->{lj_form_auth} );

        if ( $post_args->{"action:edit"} ) {
            $lock = $rv->{u}->lock_trust_groups
                or return media_security_error( $r, HTTP_CONFLICT,
                'Access filters are busy. Try again.' );
            my %post = %{ $post_args->as_hashref || {} };

            # transform our HTML field names to property names
            # and group by what media object they belong to
            # we don't care if the id or prop might not exist
            # right now, later steps will verify them

            my %props;
            while ( my ( $key, $val ) = each %post ) {
                next unless $key =~ /\A(security|title|alttext|description)-([0-9]+)\z/;
                $props{$2}{$1} = $val;
            }

            my %updates;
            for my $displayid ( keys %props ) {
                my $media = DW::Media->new( user => $rv->{u}, mediaid => $displayid >> 8 );
                next unless $media && $media->displayid == $displayid;

                my $selection = delete $props{$displayid}{security};
                my $mask      = 0;
                if ( defined $selection ) {
                    if ( $selection eq 'keep' ) {
                        return media_security_error( $r, $r->HTTP_BAD_REQUEST,
                            'Invalid image security or access filter. Reload and try again.' )
                            unless $media->security eq 'usemask'
                            && ( $media->allowmask & 1 )
                            && ( $media->allowmask & ~1 );
                        $selection = undef;
                    }
                    elsif ( $selection eq 'custom' ) {
                        $groups   //= $rv->{u}->trust_groups( force_database => 1 );
                        $revision //= $rv->{u}->trust_group_revision;
                        return media_security_error( $r, $r->SERVER_ERROR,
                            'Unable to read access filters' )
                            unless $groups && defined $revision;
                        $selection = 'usemask';
                        $mask      = DW::Media->allowmask_for_groups( $groups, $revision,
                            [ $post_args->get_all("group-$displayid") ], 1 );
                    }
                    elsif ( $selection eq 'usemask' ) {
                        $mask = 1;
                    }
                    return media_security_error( $r, $r->HTTP_BAD_REQUEST,
                        'Invalid image security or access filter. Reload and try again.' )
                        if defined $selection
                        && ( !defined $mask || $selection !~ /\A(?:public|private|usemask)\z/ );
                }
                $updates{$displayid} = [ $media, $selection, $mask ];
            }

            for my $displayid ( keys %updates ) {
                my ( $media, $security, $mask ) = @{ $updates{$displayid} };
                $media->set_security( security => $security, allowmask => $mask )
                    if defined $security;
                while ( my ( $key, $val ) = each %{ $props{$displayid} } ) {
                    $media->prop( $key, $val );
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

    $lock ||= $rv->{u}->lock_trust_groups
        or return media_security_error( $r, HTTP_CONFLICT, 'Access filters are busy. Try again.' );
    return media_security_error( $r, $r->SERVER_ERROR, 'Unable to read access filters' )
        unless security_form_options($rv);
    $lock->release;

    my @groups = @{ $rv->{custom_groups} };
    my @media  = DW::Media->get_active_for_user( $rv->{remote}, width => 200, height => 200 );
    foreach my $media (@media) {
        my $id = $media->displayid;
        $rv->{security_selection}{$id} = $media->security;
        next unless $media->security eq 'usemask';
        if ( $media->allowmask & 1 ) {
            next unless $media->allowmask & ~1;
            $rv->{security_selection}{$id} = 'keep';
            $rv->{security_options}{$id}   = [
                @{ $rv->{security} },
                { value => 'keep', text => 'Keep current (Access List + Custom)' },
            ];
            $rv->{selected_groups}{$id} = {
                map  { $_->{groupnum} => 1 }
                grep { $media->allowmask & ( 1 << $_->{groupnum} ) } @groups
            };
            next;
        }
        $rv->{security_selection}{$id} = @groups ? 'custom' : 'private';
        $rv->{selected_groups}{$id}    = {
            map  { $_->{groupnum} => 1 }
            grep { $media->allowmask & ( 1 << $_->{groupnum} ) } @groups
        };
    }

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

        $r->no_cache;
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

    my $r    = $rv->{r};
    my $lock = $rv->{u}->lock_trust_groups
        or return media_security_error( $r, HTTP_CONFLICT, 'Access filters are busy. Try again.' );
    return media_security_error( $r, $r->SERVER_ERROR, 'Unable to read access filters' )
        unless security_form_options($rv);
    $lock->release;

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
