#!/usr/bin/perl
#
# DW::Controller::EditIcons
#
# This controller is for creating and managing icons.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2016-2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::EditIcons;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger( __PACKAGE__ );

use File::Type;

use DW::BlobStore;
use LJ::Userpic;

use LJ::Global::Constants;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/icons", \&editicons_handler, app => 1 );
DW::Routing->register_string( "/tools/userpicfactory", \&factory_handler, app => 1 );
DW::Routing->register_string( "/misc/mogupic", \&mogupic_handler, app => 1, formats => 1 );

sub editicons_handler {
    # don't automatically check form_auth: causes problems with
    # processing multipart/form-data where the post arguments
    # have to be parsed out of $r->uploads
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 0 );
    return $rv unless $ok;

    my $u = $rv->{u};  # authas || remote
    my $r = $rv->{r};  # DW::Request

    # error pages must be returned from handler context, not subroutines!
    # this is basically error_ml without the implicit ML call
    my $err = sub {
        return DW::Template->render_template( 'error.tt', { message => $_[0] } )
    };

    return $err->( $LJ::MSG_READONLY_USER ) if $u->is_readonly;

    # update this user's activated pics
    $u->activate_userpics;

    # get userpics and count 'em
    my @userpics = LJ::Userpic->load_user_userpics( $u );

    # get the maximum number of icons for this user
    my $max = $u->count_max_userpics;

    # keep track of fatal errors vs. non-fatal/informative messages
    my $errors = DW::FormErrors->new;
    my @info;

    if ( $r->did_post ) {
        my $post = $r->post_args;
        return error_ml( "error.utf8" ) unless LJ::text_in( $post );

        ### save changes to existing pics
        if ( $post->{'action:save'} ) {
            # form being posted isn't multipart, so check form_auth
            return error_ml( 'error.invalidform' )
                unless LJ::check_form_auth( $post->{lj_form_auth} );

            my $refresh = update_userpics( $post, \@info, \@userpics, $u );

            # reload the pictures to account for deleted
            @userpics = LJ::Userpic->load_user_userpics( $u ) if $refresh;
        }

        unless ( %$post ) {
            ### no post data, so we'll parse the multipart data -
            ### this means that we have a new pic to handle.
            my $size = $r->header_in( "Content-Length" );
            return error_ml( "error.editicons.contentlength" ) unless $size;

            my $MAX_UPLOAD = LJ::Userpic->max_allowed_bytes( $u );
            my $parsetomogile = $size > $MAX_UPLOAD + 2048;

            # array of map references
            my @uploaded_userpics;

            # Three possibilities here: (a) small upload, in which case we
            # just parse it; (b) large upload, in which case we save the
            # files to temp storage; or (c) coming from the factory.

            unless ( $parsetomogile ) {  # for options (a) and (c)
                my $uploads = eval { $r->uploads };  # multipart/form-data
                return $err->( $@ ) if $@;

                $post->{$_->{name}} = $_->{body} foreach @$uploads;

                # parse the post parameters into an array of new pics
                @uploaded_userpics = parse_post_uploads( $post, $u, $MAX_UPLOAD );
            }

            # if we're (c) coming from the factory, then we don't
            # need to save the image to temporary storage again
            my $used_factory = $post->{src} && $post->{src} eq 'factory';
            $parsetomogile = 0 if $used_factory;

            if ( $parsetomogile ) {
                # (b) save large images to temporary storage and populate %$post
                my $error;
                parse_large_upload( $post, \$error, $u );

                # was there an error parsing the multipart form?
                return $err->( $error ) if $error;

                # parse the post parameters into an array of new pics
                @uploaded_userpics = parse_post_uploads( $post, $u, $MAX_UPLOAD );

            } elsif ( $used_factory ) {
                # (c) parse the data submitted from the factory
                my $scaledsizemax = $post->{'scaledSizeMax'};
                my ( $x1, $x2, $y1, $y2 ) = map { $_ + 0 }
                                            @$post{qw( x1 x2 y1 y2 )};

                return error_ml( "error.editicons.parse.factory" )
                    unless $scaledsizemax && $x2;

                my $picinfo = eval {
                    LJ::Userpic->get_upf_scaled(
                        x1     => $x1,
                        y1     => $y1,
                        x2     => $x2,
                        y2     => $y2,
                        border => $post->{border},
                        userid => $u->userid,
                        mogkey => mogkey( $u, $post->{index} ),
                    );
                };
                return error_ml( "error.editicons.get_upf_scaled", { err => $@ } )
                    unless $picinfo;

                # create image data hash for userpic array
                my %current_upload = (
                    key   => 'userpic_0',
                    image => \${$picinfo->[0]},
                    index => 0,
                );
                $current_upload{$_} = $post->{$_}
                    foreach qw/ keywords default comments descriptions make_default /;
                push @uploaded_userpics, \%current_upload;
            }

            # throw an error if @uploaded_userpics is still empty
            return error_ml( $post->{src}
                             ? "error.editicons.empty." . $post->{src}
                             : "error.editicons.parse.nodata" )
                unless @uploaded_userpics;

            # count how many icons the user already has
            my $userpic_count = scalar @userpics;

            my $factory_redirect;
            my $success_count = 0;

            my $index_sort = sub { $a->{index} cmp $b->{index} };
            my $current_index = 0;

            my $message_prefix = sub {
                my $idx = $_[0];
                return "" unless scalar @uploaded_userpics > 1;
                return LJ::Lang::ml( "/edit/icons.tt.icon.msgprefix",
                                     { num => $idx } ) . " ";
            };

            # go through each userpic and try to create it
            foreach my $cur_upload_ref ( sort $index_sort @uploaded_userpics ) {
                $current_index++;
                my %current_upload = %$cur_upload_ref;

                ## see if they are trying to go over their limit
                if ( $userpic_count >= $max ) {
                    $errors->add( undef, "error.editicons.toomanyicons",
                                         { num => $max } );
                    last;
                }

                my $mp = $message_prefix->( $current_index );
                my $err_add = sub { $errors->add_string( undef, $mp . $_[0] ) };
                my $info_add = sub { push( @info, $mp . $_[0] ) };

                if ( $current_upload{error} ) {
                    # error returned from parse_post_uploads
                    $err_add->( $current_upload{error} );
                    next;
                }

                if ( $current_upload{requires_factory} ) {
                    $factory_redirect = factory_prepare( \%current_upload, $u );

                    # go ahead and add this error message to @info; it
                    # will get displayed only if we can't do the redirect.
                    $info_add->( LJ::Lang::ml( "error.editicons.toolarge" ) );
                    next;
                }

                # save this userpic
                my $userpic = eval { LJ::Userpic->create( $u, data => $current_upload{image} ); };

                if ( ! $userpic ) {
                    $@ = $@->as_html if $@->isa('LJ::Error');
                    $err_add->( $@ );

                } else {
                    $info_add->( LJ::Lang::ml( "/edit/icons.tt.upload.success" ) );
                    $success_count++;

                    set_userpic_info( $userpic, \%current_upload );
                    $userpic_count++;
                }
            }

            # yay we (probably) created new pics, reload the @userpics
            @userpics = LJ::Userpic->load_user_userpics( $u );

            # did we designate an image to redirect to the factory?
            if ( $factory_redirect && ! $errors->exist ) {
                $factory_redirect->{successcount} = $success_count
                    if $success_count;

                return $r->redirect(
                    LJ::create_url( "/tools/userpicfactory",
                                    keep_args => [ 'authas' ],
                                    args => $factory_redirect ) );
            }
        }

        # make the processed post data accessible to the template
        # in case there was an error and they need to resubmit
        $rv->{formdata} = $post if $errors->exist;
    }
    #  finished post processing

    # if we're disabling media, say so
    $rv->{uploads_disabled} = $LJ::DISABLE_MEDIA_UPLOADS;
    $errors->add( undef, 'error.mediauploadsdisabled' )
        if $LJ::DISABLE_MEDIA_UPLOADS;

    $rv->{errors} = $errors;
    $rv->{messages} = \@info;

    my $args = $r->get_args;
    $rv->{sort_by_kw} = $args->{'keywordSort'} ? 1 : 0;

    $rv->{selflink} = sub {
        my $want_kw = $_[0] // $args->{'keywordSort'};
        my $keyword_sort = $want_kw ? { 'keywordSort' => 1 } : {};
        return LJ::create_url( "/manage/icons", keep_args => [ 'authas' ],
                                                args => $keyword_sort );
    };

    $rv->{icons} = $args->{'keywordSort'} ? [ LJ::Userpic->sort( \@userpics ) ]
                                          : \@userpics;
    $rv->{num_icons} = scalar @userpics;
    $rv->{max_icons} = $max;

    # Check for default userpic keywords
    foreach my $pic ( @userpics ) {
        if ( substr( $pic->keywords, 0, 4 ) eq "pic#" ) {
            $rv->{uses_default_keywords} = 1;
            last;
        }
    }

    $rv->{display_rename} = LJ::is_enabled( "icon_renames" ) ? 1 : 0;
    $rv->{help_icon} = sub { LJ::help_icon_html( @_ ) };
    $rv->{alttext_faq} = sub { LJ::Hooks::run_hook( 'faqlink', 'alttext', $_[0] ) };

    $rv->{maxlength} = { comment => LJ::CMAX_UPIC_COMMENT,
                         description => LJ::CMAX_UPIC_DESCRIPTION };

    return DW::Template->render_template( 'edit/icons.tt', $rv );
}

sub factory_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $u = $rv->{u};  # authas || remote
    my $args = $rv->{r}->get_args;

    my $w = int( $args->{'imageWidth'}  // 0 );
    my $h = int( $args->{'imageHeight'} // 0 );

    my $mogkey = mogkey( $u, $args->{index} );

    # make sure index is given and points to a valid file
    my $has_index = defined $args->{index} && length $args->{index} ? 1 : 0;
    $has_index &&= DW::BlobStore->exists( temp => $mogkey );

    $rv->{no_index} = $has_index ? 0 : 1;

    if ( $has_index && ! ($w && $h) ) {
        # we do not have the width and height passed in, must compute it
        my $upf = LJ::Userpic->get_upf_scaled( userid => $u->id,
                                               mogkey => $mogkey );
        ( $w, $h ) = ( $upf->[2], $upf->[3] )
            if $upf && $upf->[2];
    }

    $rv->{upf_w} = $w;
    $rv->{upf_h} = $h;

    $rv->{scaledSizeMax} = 640;

    $rv->{successcount} = $args->{successcount};

    my %keepargs = map { $_ => $args->{$_} }
                   qw( keywords comments descriptions make_default index );
    $rv->{form_keepargs} = LJ::html_hidden( %keepargs );

    return DW::Template->render_template( 'tools/userpicfactory.tt', $rv );
}

sub mogupic_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $u = $rv->{u};  # authas || remote
    my $r = $rv->{r};  # DW::Request
    my $args = $r->get_args;

    return $r->FORBIDDEN
        unless $r->header_in( "Referer" )  # can't load page directly
            && LJ::check_referer( '/tools/userpicfactory' );

    my $mogkey = mogkey( $u, $args->{index} );
    my $size = int( $args->{size} // 0 );
    $size = 640 if $size <= 0 || $size > 640;

    my $upf = LJ::Userpic->get_upf_scaled( size   => $size,
                                           userid => $u->id,
                                           mogkey => $mogkey );

    return $r->NOT_FOUND unless $upf;

    my $blob = $upf->[0];
    my $mime = $upf->[1];

    # return the image
    $r->content_type( $mime );
    $r->print( $$blob );

    return $r->OK;
}


sub mogkey {
    my ( $u, $index ) = @_;
    $log->logcroak( "No user given" ) unless LJ::isu( $u );

    my $key = 'upf';
    $key .= "_$index" if defined $index && length $index;
    $key .= ':' . $u->id;

    return $key;
}

sub set_userpic_info {
    my ( $userpic, $upload ) = @_;

    $userpic->make_default if $upload->{make_default};
    $userpic->set_keywords( $upload->{keywords} )
        if defined $upload->{keywords};
    $userpic->set_comment( $upload->{comments} )
        if $upload->{comments};
    $userpic->set_description( $upload->{descriptions} )
        if $upload->{descriptions};
    $userpic->set_fullurl( $upload->{url} ) if $upload->{url};
}

# prepare to send a particular upload to the factory
sub factory_prepare {
    my ( $upload, $u ) = @_;

    # save the file
    DW::BlobStore->store( temp => mogkey( $u, $upload->{index} ),
                          $upload->{image} );

    # save the arguments for the factory URL
    my $args = { imageWidth  => $upload->{imagew},
                 imageHeight => $upload->{imageh} };

    $args->{$_} = $upload->{$_} foreach qw/ keywords comments descriptions
                                            make_default index /;

    return $args;
}

# save changes to existing userpics
sub update_userpics {
    my ( $POST, $errors, $userpicsref, $u ) = @_;
    my @userpics = @$userpicsref;
    my $display_rename = LJ::is_enabled( "icon_renames" ) ? 1 : 0 ;

    my @delete; # userpic objects to delete
    my @inactive_picids;
    my %picid_of_kwid;
    my %used_keywords;

    # we need to count keywords based on what the user provided, in order
    # to find duplicates. $up->keywords doesn't work, because re-using a
    # keyword will remove it from the other userpic without our knowing
    my $count_keywords = sub {
        my $kwlist = $_[0];
        $used_keywords{$_}++ foreach split(/,\s*/, $kwlist);
    };

    foreach my $up (@userpics) {
        my $picid = $up->id;

        # delete this pic
        if ($POST->{"delete_$picid"}) {
            push @delete, $up;
            next;
        }

        # we're only going to modify keywords/comments on active pictures
        if ($up->inactive || $POST->{"pic_inactive_$picid"}) {
            # use 'orig' because we don't POST disabled fields
            $count_keywords->($POST->{"kw_orig_$picid"});
            next;
        }

        $count_keywords->($POST->{"kw_$picid"});

        # only modify if changing the data, make sure not colliding with other edits, etc
        if ($POST->{"kw_$picid"} ne $POST->{"kw_orig_$picid"}) {
            my $kws = $POST->{"kw_$picid"};

            if ( $POST->{"rename_keyword_$picid"} ) {
                if ( $display_rename && $u->userpic_have_mapid ) {
                    eval {
                       $up->set_and_rename_keywords($kws, $POST->{"kw_orig_$picid"});
                    } or push @$errors, $@->as_html;
                } else {
                    push @$errors,
                         LJ::Lang::ml( 'error.iconkw.rename.disabled' );
                }
            } else {
                eval {
                    $up->set_keywords($kws);
                } or push @$errors, $@->as_html;
            }
        }

        eval {
            $up->set_comment ($POST->{"com_$picid"})
                unless ( $POST->{"com_$picid"} // '' )
                    eq ( $POST->{"com_orig_$picid"} // '' );
        } or push @$errors, $@;

        eval {
            $up->set_description ($POST->{"desc_$picid"})
                unless ( $POST->{"desc_$picid"} // '' )
                    eq ( $POST->{"desc_orig_$picid"} // '' );
        } or push @$errors, $@;

    }

    foreach my $kw (keys %used_keywords) {
        next unless $used_keywords{$kw} > 1;
        push @$errors,
             LJ::Lang::ml( 'error.iconkw.rename.multiple', { ekw => $kw } );
    }

    if (@delete && $LJ::DISABLE_MEDIA_UPLOADS) {
        push @$errors, LJ::Lang::ml( 'error.editicons.nomediauploads.delete' );

    } elsif (@delete) {

        # delete pics
        foreach my $up (@delete) {
            eval { $up->delete; } or push @$errors, $@;
        }

        # if any of the userpics they want to delete are active, then we want to
        # re-run activate_userpics() - turns out it's faster to not check to
        # see if we need to do this
        $u->activate_userpics;
    }

    my $new_default = $POST->{'defaultpic'}+0;
    if ($POST->{"delete_${new_default}"}) {
        # deleting default
        $new_default = 0;
    }

    if ($new_default && $new_default != $u->{'defaultpicid'}) {
        my ($up) = grep { $_->id == $new_default } @userpics;

        # see if they are trying to make an inactive userpic their default
        if ($up && !$up->inactive) {
            $up->make_default;
        }
    } elsif ($new_default eq '0' && $u->{'defaultpicid'}) {
        # selected the "no default picture" option
        $u->update_self( { defaultpicid => 0 } );
        $u->{'defaultpicid'} = 0;
    }

    return scalar @delete;
}

# parse the post parameters into an array of new pics
sub parse_post_uploads {
    my ( $POST, $u, $MAX_UPLOAD ) = @_;
    my @uploads;

    # if we find a userpic that requires the factory, save it here.
    # we can only have one.
    my $requires_factory;

    # go through each key and create a %current_upload for it, then
    # put it in @uploads.
    foreach my $userpic_key ( keys %$POST ) {
        next unless $userpic_key =~ /^(?:userpic|urlpic)_\d+$/;

        my @tokens = split(/_/, $userpic_key);
        my $counter = $tokens[1];
        my $make_default = $POST->{make_default} // '';

        my %current_upload = (
            comments     => $POST->{"comments_$counter"},
            descriptions => $POST->{"descriptions_$counter"},
            index        => $counter,
            key          => $userpic_key,
            keywords     => $POST->{"keywords_$counter"},
            make_default => $make_default eq $counter,
        );

        # check input text for comments, descriptions, and keywords
        unless ( LJ::text_in( \%current_upload ) ) {
           $current_upload{error} = LJ::Lang::ml( "error.utf8" );
           push @uploads, \%current_upload;
           next;
        }

        # uploaded pics
        if ($userpic_key =~ /userpic_.*/) {
            # only use userpic_0 if we selected file for the source
            next if $userpic_key eq "userpic_0" && $POST->{"src"} ne "file";

            # Some callers to the function pass data, others pass
            # a reference to data.  Figure out which type we got.
            $current_upload{image} = ref $POST->{$userpic_key} ?
                                         $POST->{$userpic_key} :
                                        \$POST->{$userpic_key};

            my $size = length ${$current_upload{image}};
            if ( $size == 0 ) {
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.empty.file' );
                push @uploads, \%current_upload;
                next;
            }

            my ( $imagew, $imageh, $filetype ) =
                Image::Size::imgsize( $current_upload{image} );

            # couldn't parse the file
            if ( !$imagew || !$imageh ) {
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.unsupportedtype', {
                        filetype => $filetype,
                    } );

            # file is too big, no matter what.
            } elsif ( $imagew > 5000 || $imageh > 5000 ) {
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.dimstoolarge' );

            # let's try to use the factory
            } elsif ( int($imagew) > 100 || int($imageh) > 100 || $size > $MAX_UPLOAD ) {
                # file wrong type for factory
                if ( $filetype ne 'JPG' && $filetype ne 'PNG' ) {
                    # factory only works on jpegs and pngs
                    # because Image::Magick has issues
                    if ( int($imagew) > 100 || int($imageh) > 100 ) {
                        $current_upload{error} =
                            LJ::Lang::ml( 'error.editicons.giffiledimensions' );
                    } else {
                        $current_upload{error} =
                            LJ::Lang::ml( 'error.editicons.filetoolarge', {
                                maxsize => int($MAX_UPLOAD / 1024),
                            } );
                    }

                # if it's the right size, just too large a file,
                # see if we can resize it down
                } elsif ( $imagew <= 100 && $imageh <= 100 ) {
                    # have to store the file, this is the interface that
                    # the userpic factory uses to get files between
                    # the N different web processes you might talk to
                    my $mogkey = mogkey( $u, $counter );
                    my $rv = DW::BlobStore->store(
                        temp => $mogkey,
                        $current_upload{image}
                    );
                    unless ( $rv ) {
                        $current_upload{error} =
                            LJ::Lang::ml( 'error.editicons.blobstore' );
                        push @uploads, \%current_upload;
                        next;
                    }

                    eval {
                        my $picinfo = LJ::Userpic->get_upf_scaled(
                            mogkey => $mogkey,
                            size   => 100,
                            u      => $u,
                        );

                        # success! don't go to the factory, and
                        # pretend the user just uploaded the file
                        # and continue on normally
                        $current_upload{image} = $picinfo->[0];
                    };

                    if ( $@ || length ${$current_upload{image}} > $MAX_UPLOAD ) {
                        $current_upload{error} =
                            LJ::Lang::ml( 'error.editicons.filetoolarge', {
                                maxsize => int($MAX_UPLOAD / 1024),
                            } );
                    }

                # this is a candidate for the userpicfactory.
                } else {
                    # we can only do a single pic in the factory, so if there are two,
                    # then error out for both.
                    if ($requires_factory) {
                        $requires_factory->{error} = $current_upload{error} =
                            LJ::Lang::ml( 'error.editicons.multipleresize' );
                        $requires_factory->{requires_factory} = 0;
                    } else {
                        $current_upload{requires_factory} = 1;
                        $current_upload{imageh} = $imageh;
                        $current_upload{imagew} = $imagew;
                        if ( $POST->{"spool_data_$counter"} ) {
                            $current_upload{spool_data} = $POST->{"spool_data_$counter"};
                        }
                        $requires_factory = \%current_upload;
                    }
                }
            }

            push @uploads, \%current_upload;

        } elsif ($userpic_key =~ /urlpic_.*/) {
            # go through the URL uploads
            next if $userpic_key eq "urlpic_0" && $POST->{src} ne "url";

            if ( !$POST->{$userpic_key} ) {
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.empty.url' );
            } elsif ( $POST->{$userpic_key} !~ /^https?:\/\// ) {
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.url.format' );
            } else {
                my $ua = LJ::get_useragent(
                    role     => 'userpic',
                    max_size => $MAX_UPLOAD + 1024,
                    timeout  => 10,
                );
                my $res = $ua->get( $POST->{$userpic_key} );
                $current_upload{image} = \$res->content
                    if $res && $res->is_success;
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.url.fetch' )
                        unless $current_upload{image};
                $current_upload{error} =
                    LJ::Lang::ml( 'error.editicons.url.filetoolarge' )
                        if $current_upload{image} &&
                            length ${$current_upload{image}} > $MAX_UPLOAD;
                $current_upload{url} = $POST->{$userpic_key};
            }
            push @uploads, \%current_upload;
        }
    }

    return @uploads;
}

# save large images to temporary storage and populate post parameters
sub parse_large_upload {
    my ( $POST, $errref, $u ) = @_;

    my %upload = (); # { spool_data, spool_file_name, filename, bytes, md5sum, md5ctx, mime }
    my @uploaded_files = ();
    my $curr_name;

    # subref to set $$errref and return false
    my $err = sub { $$errref = LJ::Lang::ml( @_ ); return 0 };

    # called when the beginning of an upload is encountered
    my $hook_newheaders = sub {
        my ( $name, $filename ) = @_;
        $curr_name = $name;
        $POST->{$curr_name} = '';
        return 1 unless $curr_name =~ /userpic.*/;

        # new file, need to create a filehandle, etc
        %upload = ();
        $upload{filename} = $filename;
        $upload{md5ctx} = new Digest::MD5;

        my @tokens = split(/_/, $curr_name);
        my $counter = $tokens[1];

        $upload{spool_file_name} = mogkey( $u, $counter );
        $upload{spool_data} = '';

        push @uploaded_files, $upload{spool_file_name};
        return 1;
    };

    # called as data is received
    my $hook_data = sub {
        my ( $len, $data ) = @_;
        unless ( $curr_name =~ /userpic.*/ ) {
            $POST->{$curr_name} .= $data;
            return 1;
        }

        # check that we've not exceeded the max read limit
        my $max_read = (1<<20) * 5; # 5 MiB
        $upload{bytes} += $len;
        if ( $upload{bytes} > $max_read ) {
            return $err->( "error.editicons.parse.maxread",
                           { max_read => $max_read, bytes => $upload{bytes} } );
        }

        $upload{md5ctx}->add($data);
        $upload{spool_data} .= $data;

        return 1;
    };

    # called when the end of an upload is encountered
    my $hook_enddata = sub {
        return 1 unless $curr_name =~ /userpic.*/;

        # since we've just finished a potentially slow upload, we need to
        # make sure the database handles in DBI::Role's cache haven't expired,
        # so we'll just trigger a revalidation now so that subsequent database
        # calls will be safe.
        $LJ::DBIRole->clear_req_cache();

        # don't try to operate on 0-length spoolfiles
        unless ( $upload{bytes} ) {
            %upload = ();
            return 1;
        }
        unless ( length $upload{spool_data} > 0 ) {
            return $err->( "error.editicons.parse.nosize" );
        }

        # Get MIME type from magic bytes
        $upload{mime} = File::Type->new->mime_type( $upload{spool_data} );
        unless ( $upload{mime} ) {
            return $err->( "error.editicons.parse.unknowntype" );
        }

        # finished adding data for md5, create digest (but don't destroy original)
        $upload{md5sum} = $upload{md5ctx}->digest;
        $POST->{$curr_name} = \$upload{spool_data};
        return 1;
    };


    # parse multipart-mime submission, one chunk at a time, calling
    # our hooks as we go to put uploads in temporary file storage
    my $retval = eval { parse_multipart_interactive(
                            $errref, { newheaders => $hook_newheaders,
                                       data       => $hook_data,
                                       enddata    => $hook_enddata,
                                     } );
                      };

    unless ( $retval ) {
        # if we hit a parse error, delete the uploaded files
        foreach my $mogkey ( @uploaded_files ) {
            DW::BlobStore->delete( temp => $mogkey );
        }

        # $errref is already set by parse_multipart_interactive
        return 0;
    }

    return $retval;
}

sub parse_multipart_interactive {
    my ($errref, $hooks) = @_;
    my $apache_r = DW::Request->get;

    # subref to set $@ and $$errref, then return false
    my $err = sub { $$errref = $@ = $_[0]; return 0 };

    my $run_hook = sub {
        my $name = shift;
        my $ret = eval { $hooks->{$name}->(@_) };
        return $err->($@) if $@;

        # return a default hook error if the hook didn't set $$errref
        return $err->( $$errref ? $$errref : "Hook: '$name' returned false" )
            unless $ret;

        return 1;
    };

    my $mimetype = $apache_r->header_in( "Content-Type" );
    my $size     = $apache_r->header_in( "Content-length" );

    unless ( $mimetype =~ m!^multipart/form-data;\s*boundary=(\S+)! ) {
        return $err->( LJ::Lang::ml( "error.editicons.parse.boundary",
                                     { type => $mimetype } ) );
    }
    my $sep = "--$1";
    my $seplen = length($sep) + 2;  # plus \r\n

    my $window = '';
    my $to_read = $size;
    my $max_read = 8192;

    my $seen_chunk = 0;  # have we seen any chunk yet?

    my $state = 0;  # what we last parsed
    # 0 = nothing  (looking for a separator)
    # 1 = separator (looking for headers)
    # 0 = headers   (looking for data)
    # 0 = data      (looking for a separator)

    while (1) {
        my $read = -1;
        if ($to_read) {
            $read = $apache_r->read($window,
                             $to_read < $max_read ? $to_read : $max_read,
                             length($window));
            $to_read -= $read;

            # prevent loops.  Opera, in particular, alerted us to
            # this bug, since it doesn't upload proper MIME on
            # reload and its Content-Length header is correct,
            # but its body tiny
            if ($read == 0) {
                return $err->( LJ::Lang::ml( "error.editicons.parse.nodata" ) );
            }
        }

        # starting case, or data-reading case (looking for separator)
        if ($state == 0) {
            my $idx = index($window, $sep);

            # didn't find a separator.  emit the previous data
            # which we know for sure is data and not a possible
            # new separator
            if ($idx == -1) {
                # bogus if we're done reading and didn't find what we're
                # looking for:
                if ($read == -1) {
                    return $err->( LJ::Lang::ml( "error.editicons.parse.notfound",
                                                 { what => 'separator' } ) );
                }

                if ($seen_chunk) {

                    # data hook is required
                    my $len = length($window) - $seplen;
                    $run_hook->('data', $len, substr($window, 0, $len, ''))
                        or return 0;
                }
                next;
            }

            # we found a separator.  emit the previous read's
            # data and enddata.
            if ($seen_chunk) {
                my $len = $idx - 2;
                if ($len > 0) {

                    # data hook is required
                    $run_hook->('data', $len, substr($window, 0, $len))
                        or return 0;
                }

                # enddata hook is required
                substr($window, 0, $idx, '');
                $run_hook->('enddata')
                    or return 0;
            }

            # we're now looking for a header
            $seen_chunk = 1;
            $state = 1;

            # have we hit the end?
            return 1 if $to_read <= 2 && length($window) <= $seplen + 4;
        }

        # read a separator, looking for headers
        if ($state == 1) {
            my $idx = index($window, "\r\n\r\n");
            if ($idx == -1) {
                if (length($window) > 8192) {
                    return $err->( LJ::Lang::ml( "error.editicons.parse.window",
                                                 { len => length($window) } ) );
                }

                # bogus if we're done reading and didn't find what we're
                # looking for:
                if ($read == -1) {
                    return $err->( LJ::Lang::ml( "error.editicons.parse.notfound",
                                                 { what => 'headers' } ) );
                }

                next;
            }

            # +4 is \r\n\r\n
            my $header = substr($window, 0, $idx+4, '');
            my @lines = split(/\r\n/, $header);

            my %hdval;
            my $lasthd;
            foreach (@lines) {
                if (/^(\S+?):\s*(.+)/) {
                    $lasthd = lc($1);
                    $hdval{$lasthd} = $2;
                } elsif (/^\s+.+/) {
                    $hdval{$lasthd} .= $&;
                }
            }

            my ($name, $filename);
            if ($hdval{'content-disposition'} =~ /\bNAME=\"(.+?)\"/i) {
                $name = $1;
            }
            if ($hdval{'content-disposition'} =~ /\bFILENAME=\"(.+?)\"/i) {
                $filename = $1;
            }

            # newheaders hook is required
            $run_hook->('newheaders', $name, $filename)
                or return 0;

            $state = 0;
        }

    }
    return 1;
}

1;
