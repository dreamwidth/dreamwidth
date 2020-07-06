#!/usr/bin/perl
#
# DW::Controller::Admin::VirtualGift
#
# Management pages for virtual gifts in the shop.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::VirtualGift;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use DW::VirtualGift;
use DW::FormErrors;

use Image::Size;

my $vgift_privs = [
    'vgifts',
    'siteadmin:vgifts',
    sub {
        return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
    }
];

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'vgifts',
    ml_scope => '/admin/vgifts/index.tt',
    privs    => $vgift_privs
);

DW::Routing->register_string( "/admin/vgifts/index",    \&index_controller,    app => 1 );
DW::Routing->register_string( "/admin/vgifts/inactive", \&inactive_controller, app => 1 );

sub _loose_refer {
    my $baseuri = $_[0];
    my $refer   = DW::Request->get->header_in('Referer');
    return 1 unless $refer;

    # annoyingly, we get different results for /index vs /
    if ( $baseuri =~ m(/$) ) {
        return 1 if LJ::check_referer("${baseuri}index");
    }
    return LJ::check_referer($baseuri);
}

sub _strict_refer {

    # make sure we have a referer header. check_referer doesn't care.
    my $ret = DW::Request->get->header_in('Referer') && _loose_refer( $_[0] );
    return $ret;
}

sub _check_id {
    my $err_ml = $_[1] // \undef;

    if ( my $id = $_[0] ) {
        my $vgift = DW::VirtualGift->new($id);
        return $vgift if $vgift && $vgift->name;
        $$err_ml = "vgift.error.badid";
    }
    else {
        $$err_ml = "error.invalidform";
    }
}

sub index_controller {
    my ( $ok, $rv ) = controller( form_auth => 0, privcheck => $vgift_privs );
    return $rv unless $ok;

    my $r     = $rv->{r};
    my $scope = '/admin/vgifts/index.tt';
    my $vars  = {};

    my $remote    = $rv->{remote};
    my $siteadmin = $remote->has_priv( 'siteadmin', 'vgifts' ) || $LJ::IS_DEV_SERVER;

    my $form_args = $r->did_post ? $r->post_args : $r->get_args;

    # process multipart form
    if ( $r->did_post && !%$form_args ) {
        my $size = $r->header_in("Content-Length");
        return error_ml("$scope.error.upload.noheader") unless $size;

        my $uploads = eval { $r->uploads };
        return error_ml( "$scope.error.upload.content", { err => $@ } ) if $@;

        foreach my $h (@$uploads) {
            $form_args->{ $h->{name} } = $h->{body};
        }

        # now uploaded data is in $form_args, we can continue
    }

    my $checkid = sub { return _check_id( $form_args->{id}, $_[0] ) };

    my $mode = lc( $form_args->{mode} || $r->get_args->{mode} || '' );

    # process post request, but only if we have a mode
    if ( $r->did_post && $mode ) {

        # check auth manually in case we had a multipart form
        return error_ml("error.invalidform")
            unless LJ::check_form_auth( $form_args->{lj_form_auth} );

        $mode = '' unless _loose_refer("/admin/vgifts/");

        my $errors = DW::FormErrors->new;

        my $loadpic = sub {
            my ($id) = @_;

            my $imgposted = length( $form_args->{"data_$id"} ) || length( $form_args->{"url_$id"} );
            return undef unless $imgposted;

            my $data;

            if ( $form_args->{$id} eq 'url' ) {
                $data = $form_args->{"url_$id"};

                if ( length($data) == 0 ) {
                    $errors->add( '', "$scope.error.upload.nourl" );
                }
                elsif ( $data !~ m!^https?://! ) {
                    $errors->add( '', "$scope.error.upload.badurl" );
                }
                else {
                    my $ua  = LJ::get_useragent( role => 'vgift' );
                    my $res = $ua->get($data);
                    if ( $res && $res->is_success ) {
                        $data = $res->content;
                    }
                    else {
                        $errors->add( '', "$scope.error.upload.urlerror" );
                    }
                }
            }
            elsif ( $form_args->{$id} eq 'file' ) {
                $data = $form_args->{"data_$id"};
                $errors->add( '', "$scope.error.upload.nofile" )
                    unless length($data);
            }
            else {
                $errors->add( '', 'error.invalidform' );
            }

            return undef if $errors->exist;

            # further processing
            my ( $width, $height, $filetype ) = Image::Size::imgsize( \$data );
            unless ( $width && $height ) {
                $errors->add( '', "$scope.error.upload.badtype", { filetype => $filetype } );
            }
            elsif ( ( $width > 100 || $height > 100 ) && $id eq 'img_small' ) {
                $errors->add(
                    '',
                    "$scope.error.upload.dimstoolarge",
                    { imagesize => "${width}x$height", maxsize => "100x100" }
                );
            }
            elsif ( ( $width > 300 || $height > 300 ) && $id eq 'img_large' ) {
                $errors->add(
                    '',
                    "$scope.error.upload.dimstoolarge",
                    { imagesize => "${width}x$height", maxsize => "300x300" }
                );
            }
            elsif ( length($data) > 250 * 1024 ) {    # 250KB (arbitrary)
                $errors->add( '', "$scope.error.upload.filetoolarge", { maxsize => "250" } );
            }
            else {
                # data should be good, return a reference to it
                return \$data;
            }

            # check $errors to see what went wrong
            return undef;
        };

        my ( $redirect_args, $err_ml, $errmsg );

        if ( $mode eq 'create' ) {
            return error_ml( "$scope.error.denied", { action => $mode } )
                unless $remote->has_priv('vgifts') || $siteadmin;

            $errors->add( 'name', "$scope.error.create.noname" ) unless $form_args->{name};
            $errors->add( 'desc', "$scope.error.create.nodesc" ) unless $form_args->{desc};

            my $creatorid;

            if ( $form_args->{creator} && $siteadmin ) {
                my $u = LJ::load_user_or_identity( $form_args->{creator} );
                if ( $u && $u->is_individual ) {
                    $creatorid = $u->id;
                }
                else {
                    $errors->add(
                        'creator',
                        "$scope.error.create.badusername",
                        { name => $form_args->{creator} }
                    );
                }
            }

            my ( $img_small, $img_large );

            $img_small = $loadpic->('img_small') unless $errors->exist;
            $img_large = $loadpic->('img_large') unless $errors->exist;

            unless ( $errors->exist ) {
                my $vgift = DW::VirtualGift->create(
                    error       => \$errmsg,
                    name        => $form_args->{name},
                    description => $form_args->{desc},
                    img_small   => $img_small,
                    img_large   => $img_large,
                    creatorid   => $creatorid
                );
                return error_ml( "$scope.error.create.failure", { err => $errmsg } )
                    unless $vgift;

                # hallelujah, the vgift was created.
                $redirect_args = { mode => 'view', title => 'created', id => $vgift->id };
            }

            # return template below if there were correctable errors
            $vars->{mode} = '';
        }

        elsif ( $mode eq 'edit' ) {
            return error_ml($err_ml) unless my $vgift = $checkid->( \$err_ml );

            return error_ml( "$scope.error.denied", { action => $mode } )
                unless $vgift->can_be_edited_by($remote);

            my ( $img_small, $img_large );

            $img_small = $loadpic->('img_small') unless $errors->exist;
            $img_large = $loadpic->('img_large') unless $errors->exist;

            # Don't honor null attributes.
            delete $form_args->{name} unless length $form_args->{name};
            delete $form_args->{desc} unless length $form_args->{desc};

            # Note: this resets any existing approval status.
            unless ( $errors->exist ) {
                my $ok = $vgift->edit(
                    error       => \$errmsg,
                    approved    => '',
                    name        => $form_args->{name},
                    description => $form_args->{desc},
                    img_small   => $img_small,
                    img_large   => $img_large
                );
                return error_ml( "$scope.error.edit.failure", { err => $errmsg } )
                    unless $ok;

                $redirect_args = { mode => 'view', title => 'edited', id => $vgift->id };
            }

            # return template below if there were correctable errors
            $vars->{mode} = 'view';
        }

        elsif ( $mode eq 'approve' ) {
            return error_ml($err_ml) unless my $vgift = $checkid->( \$err_ml );

            return error_ml( "$scope.error.denied", { action => $mode } )
                unless $vgift->can_be_approved_by($remote);

            my $id = $vgift->id;

            return error_ml("$scope.error.changed")
                if $form_args->{"${id}_chksum"} ne $vgift->checksum;

            if ( exists $form_args->{"${id}_approve"} ) {
                if ( $form_args->{"${id}_approve"} ) {
                    my $ok = $vgift->edit(
                        error        => \$errmsg,
                        approved     => $form_args->{"${id}_approve"},
                        approved_why => $form_args->{"${id}_comment"},
                        approved_by  => $remote->userid
                    );
                    return error_ml( "$scope.error.edit.failure", { err => $errmsg } )
                        unless $ok;

                    $vgift->notify_approved;
                }
                else {
                    # this error isn't fatal
                    $errors->add( "${id}_approve", "$scope.error.yn" );
                }
            }

            if ( $form_args->{"${id}_featured"} || $form_args->{"${id}_cost"} ) {
                my %opts;
                foreach my $k (qw( featured cost )) {
                    $opts{$k} = $form_args->{"${id}_$k"} if $form_args->{"${id}_$k"};
                }
                my $ok = $vgift->edit( error => \$errmsg, %opts );
                return error_ml( "$scope.error.edit.failure", { err => $errmsg } )
                    unless $ok;
            }

            if ( $form_args->{"${id}_tags"} ) {
                my $ok = $vgift->tags(
                    $form_args->{"${id}_tags"},
                    error      => \$errmsg,
                    autovivify => $siteadmin
                );
                return error_ml( "$scope.error.edit.failure", { err => $errmsg } )
                    unless $ok;
            }

            unless ( $errors->exist ) {
                return $r->redirect("/admin/vgifts/inactive")
                    if $form_args->{activation};

                # return to review page for item
                $redirect_args = { mode => 'review', title => 'approved', id => $id };
                my $days = $form_args->{days} ? $form_args->{days} + 0 : 0;
                $redirect_args->{days} = $days if $days;
            }

            # return template below if there were correctable errors
            $vars->{mode} = 'review';
        }

        elsif ( $mode eq 'confirm' ) {
            return error_ml($err_ml) unless my $vgift = $checkid->( \$err_ml );

            my $ok = $vgift->delete($remote);
            return error_ml("$scope.error.delete") unless $ok;

            my $re_mode = $remote->userid == $vgift->creatorid ? 'view' : 'review';

            $redirect_args = { mode => $re_mode, title => 'deleted' };
        }

        else {
            # if we get here, check_referer failed or something weird happened
            return $r->redirect("$LJ::SITEROOT/admin/vgifts/");
        }

        if ( defined $redirect_args ) {
            return $r->redirect( LJ::create_url( undef, args => $redirect_args ) );
        }
        else {
            $vars->{errors}   = $errors;
            $vars->{formdata} = $form_args;

            # fall through to template
        }
    }    # end did_post

    # transform get arguments into template variables (id -> vgift; user -> vu)

    if ( $form_args->{title} && _strict_refer("/admin/vgifts/") ) {
        $vars->{title} = $form_args->{title};
    }

    $vars->{mode} //= $form_args->{mode};

    if ( $form_args->{id} ) {
        return error_ml("$scope.error.badid") unless $vars->{vgift} = $checkid->();
    }

    if ( $form_args->{user} ) {
        $vars->{vu} = LJ::load_user( $form_args->{user} );
        return error_ml( "$scope.error.baduser", { user => $form_args->{user} } )
            unless LJ::isu( $vars->{vu} );
    }

    $vars->{remote}    = $remote;
    $vars->{siteadmin} = $siteadmin;

    $vars->{inactive} = $form_args->{title} ? $form_args->{title} eq 'inactive' : 0;
    $vars->{days}     = $form_args->{days}  ? $form_args->{days} + 0            : 0;

    $vars->{review_list} = sub {
        my $days = $vars->{days};
        return [ DW::VirtualGift->list_recent($days) ] if $days;
        return [ DW::VirtualGift->list_queued() ];
    };

    $vars->{display_creatorlist} = sub { DW::VirtualGift->display_creatorlist( $_[0] ) };

    $vars->{list_created_by} = sub { [ DW::VirtualGift->list_created_by( $_[0] ) ] };

    return DW::Template->render_template( 'admin/vgifts/index.tt', $vars );
}

sub inactive_controller {
    my $privs = [ $vgift_privs->[1], $vgift_privs->[2] ];

    my ( $ok, $rv ) = controller( privcheck => $privs );
    return $rv unless $ok;

    my $r     = $rv->{r};
    my $scope = '/admin/vgifts/inactive.tt';
    my $vars  = {};

    my $remote    = $rv->{remote};
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;

    my $mode = lc( $form_args->{mode} || $r->get_args->{mode} || '' );

    # process post request, but only if we have a mode
    if ( $r->did_post && $mode ) {

        $mode = '' unless _loose_refer("/admin/vgifts/inactive");

        if ( $mode eq 'activate' ) {
            my @vgs;
            foreach ( keys %$form_args ) {
                my ($id) = ( $_ =~ /^(\d+)_activate$/ );
                next unless $id;

                my $err_ml;
                my $vg = _check_id( $id, $err_ml );
                return error_ml($err_ml) unless $vg;

                next if $vg->is_active;    # already active

                return error_ml( "$scope.error.notags", { name => $vg->name_ehtml } )
                    if $vg->is_untagged;

                return error_ml( "$scope.error.changed", { name => $vg->name_ehtml } )
                    if $form_args->{"${id}_chksum"} ne $vg->checksum;

                push @vgs, $vg;
            }

            # now that we're clear of possible errors, do the activation
            $_->mark_active foreach @vgs;
            my $ids = join ', ', map { $_->id } @vgs;
            LJ::statushistory_add( 0, $remote, 'vgifts', "Activated: $ids" )
                if $ids;

            # go back to where we were
            return $r->redirect( $r->header_in('Referer') );
        }

        else {
            # if we get here, check_referer failed or something weird happened
            return $r->redirect("$LJ::SITEROOT/admin/vgifts/inactive");
        }
    }    # end did_post

    my @vgs;

    if ( $mode eq 'tags' ) {
        my $tag = $form_args->{tag} || '';

        if ($tag) {
            return error_ml("$scope.error.badid")
                unless DW::VirtualGift->get_tagid($tag);

            $vars->{tag}   = $tag;
            $vars->{count} = scalar grep { $_->is_approved } DW::VirtualGift->list_untagged;

            @vgs = DW::VirtualGift->list_tagged_with($tag);

            # list_tagged_with includes active gifts
            @vgs = grep { $_->is_inactive } @vgs;
        }
        else {
            @vgs = DW::VirtualGift->list_untagged;
        }

        my $app = DW::VirtualGift->fetch_tagcounts_approved;
        my $act = DW::VirtualGift->fetch_tagcounts_active;

        $vars->{approved_inactive} = {};
        $vars->{approved_inactive}->{$_} = $app->{$_} - ( $act->{$_} // 0 ) foreach keys %$app;
    }
    else {
        # DEFAULT PAGE DISPLAY
        @vgs = DW::VirtualGift->list_inactive;
    }

    # don't include queued or rejected gifts
    @vgs = grep { $_->is_approved } @vgs;

    $vars->{feat}    = [ grep { $_->is_featured } @vgs ];
    $vars->{nonfeat} = [ grep { !$_->is_featured } @vgs ];
    $vars->{nonpriv} = { map  { $_ => 1 } DW::VirtualGift->list_nonpriv_tags };

    $vars->{mode}  = $mode;
    $vars->{modes} = [ '', 'tags' ];    # ordered
    $vars->{tabs}  = {
        ''     => '.tab.default',
        'tags' => '.tab.tags',
    };

    return DW::Template->render_template( 'admin/vgifts/inactive.tt', $vars );
}

1;
