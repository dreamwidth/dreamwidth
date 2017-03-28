#!/usr/bin/perl
#
# DW::Controller::EditIcons
#
# This controller is for creating and managing icons. NOTE: The actual file
# is still a BML file, this is just a forward looking controller to help us
# migrate.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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

use DW::Controller;
use DW::Routing;

DW::Routing->register_string( "/misc/mogupic", \&mogupic_handler, app => 1, formats => 1 );

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

sub update_userpics {
    my ( $POST, $errors, $userpicsref, $u, $err ) = @_;
    my @userpics = @$userpicsref;
    my $display_rename = LJ::is_enabled( "icon_renames" ) ? 1 : 0 ;

    # form being posted isn't multipart, since we were able to read from %POST
    unless (LJ::check_form_auth()) {
        return $err->(LJ::Lang::ml('error.invalidform'));
    }

    my @delete; # userpic objects to delete
    my @inactive_picids;
    my %picid_of_kwid;
    my %used_keywords;

    # we need to count keywords based on what the user provided, in order
    # to find duplicates. $up->keywords doesn't work, because re-using a
    # keyword will remove it from the other userpic without our knowing
    my $count_keywords = sub {
        my $kwlist = shift;
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
                    push @$errors, LJ::Lang::ml('.label.rename.disabled');
                }
            } else {
                eval {
                    $up->set_keywords($kws);
                } or push @$errors, $@->as_html;
            }
        }

        eval {
            $up->set_comment ($POST->{"com_$picid"})
                unless $POST->{"com_$picid"} eq $POST->{"com_orig_$picid"};
        } or push @$errors, $@;

        eval {
            $up->set_description ($POST->{"desc_$picid"})
                unless $POST->{"desc_$picid"} eq $POST->{"desc_orig_$picid"};
        } or push @$errors, $@;

    }

    foreach my $kw (keys %used_keywords) {
        next unless $used_keywords{$kw} > 1;
        push @$errors, LJ::Lang::ml('.error.keywords', {ekw => $kw});
    }

    if (@delete && $LJ::DISABLE_MEDIA_UPLOADS) {
        push @$errors, LJ::Lang::ml('.error.nomediauploads.delete');

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

        # uploaded pics
        if ($userpic_key =~ /userpic_.*/) {
            # Some callers to the function pass data, others pass
            # a reference to data.  Figure out which type we got.
            $current_upload{image} = ref $POST->{$userpic_key} ?
                                         $POST->{$userpic_key} :
                                        \$POST->{$userpic_key};

            # only use userpic_0 if we selected file for the source
            next if $userpic_key eq "userpic_0" && $POST->{"src"} ne "file";

            my $size = length ${$current_upload{image}};
            if ( $size == 0 ) {
                $current_upload{error} = LJ::Lang::ml('.error.nofile');
            } else {
                my ( $imagew, $imageh, $filetype ) =
                    Image::Size::imgsize( $current_upload{image} );

                # couldn't parse the file
                if ( !$imagew || !$imageh ) {
                    $current_upload{error} = LJ::Lang::ml( '.error.unsupportedtype', {
                        filetype => $filetype } );

                # file is too big, no matter what.
                } elsif ( $imagew > 5000 || $imageh > 5000 ) {
                    $current_upload{error} = 'The dimensions of this image are too large.';

                # let's try to use the factory
                } elsif ( int($imagew) > 100 || int($imageh) > 100 || $size > $MAX_UPLOAD ) {
                    # file wrong type for factory
                    if ( $filetype ne 'JPG' && $filetype ne 'PNG' ) {
                        # factory only works on jpegs and pngs because Image::Magick has issues
                        if ( int($imagew) > 100 || int($imageh) > 100 ) {
                            $current_upload{error} = LJ::Lang::ml('.error.giffiledimensions');
                        } else {
                            $current_upload{error} = LJ::Lang::ml( '.error.filetoolarge',
                                { 'maxsize' => int($MAX_UPLOAD / 1024) } );
                        }

                    # if it's the right size, just too large a file, see if we can resize it down
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
                            $current_upload{error} = 'Failed to upload file to storage system.';
                            push @uploads, \%current_upload;
                            next;
                        }

                        eval {
                            my $picinfo = LJ::Userpic->get_upf_scaled(
                                mogkey => $mogkey,
                                size   => 100,
                                u      => $u,
                            );

                            # success! don't go to the factory, and pretend the user just uploaded the file
                            # and continue on normally
                            $current_upload{image} = $picinfo->[0];
                        };

                        if ( $@ || length ${$current_upload{image}} > $MAX_UPLOAD ) {
                            $current_upload{error} = LJ::Lang::ml( '.error.filetoolarge',
                                { maxsize => int($MAX_UPLOAD / 1024) } );
                        }

                    # this is a candidate for the userpicfactory.
                    } else {
                        # we can only do a single pic in the factory, so if there are two,
                        # then error out for both.
                        if ($requires_factory) {
                            $requires_factory -> {error} = LJ::Lang::ml('.error.multipleresize');
                            $current_upload{error} = LJ::Lang::ml('.error.multipleresize');
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
            }
            push @uploads, \%current_upload;

        } elsif ($userpic_key =~ /urlpic_.*/) {
            # go through the URL uploads
            next if $userpic_key eq "urlpic_0" && $POST->{src} ne "url";

            if ( !$POST->{$userpic_key} ) {
                $current_upload{error} = LJ::Lang::ml('.error.nourl');
            } elsif ( $POST->{$userpic_key} !~ /^https?:\/\// ) {
                $current_upload{error} = LJ::Lang::ml('.error.badurl');
            } else {
                my $ua = LJ::get_useragent(
                    role     => 'userpic',
                    max_size => $MAX_UPLOAD + 1024,
                    timeout  => 10,
                );
                my $res = $ua->get( $POST->{$userpic_key} );
                $current_upload{image} = \$res->content
                    if $res && $res->is_success;
                $current_upload{error} = LJ::Lang::ml('.error.urlerror')
                    unless $current_upload{image};
                $current_upload{error} = LJ::Lang::ml('.error.urlfiletoolarge')
                    if $current_upload{image} && length ${$current_upload{image}} > $MAX_UPLOAD;
            }
            push @uploads, \%current_upload;
        }
    }

    return @uploads;
}

sub parse_large_upload {
    my ( $POST, $errorref, $u, $err ) = @_;

    my %upload = (); # { spool_data, spool_file_name, filename, bytes, md5sum, md5ctx, mime }
    my @uploaded_files = ();
    my $curr_name;

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
            $$errorref = "Upload max $max_read exceeded at $upload{bytes} bytes";
            return $err->( $$errorref );
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
            $$errorref = "Failed to read a file";
            return $err->( $$errorref );
        }

        # Get MIME type from magic bytes
        $upload{mime} = File::Type->new->mime_type( $upload{spool_data} );
        unless ( $upload{mime} ) {
            $$errorref = "Unknown format for upload";
            return $err->( $$errorref );
        }

        # finished adding data for md5, create digest (but don't destroy original)
        $upload{md5sum} = $upload{md5ctx}->digest;
        $POST->{$curr_name} = \$upload{spool_data};
        return 1;
    };


    # parse multipart-mime submission, one chunk at a time,
    # calling our hooks as we go to put uploads in temporary
    # MogileFS filehandles
    my $retval = eval { parse_multipart_interactive($errorref, {
        newheaders => $hook_newheaders,
        data       => $hook_data,
        enddata    => $hook_enddata,
                                                         }); };

    # if parse_multipart_interactive failed, we need to add
    # all of our gpics to the gpic_delete queue.  if any of them
    # still have refcounts, they won't really be deleted because
    # the async job will realize and leave them alone
    unless ( $retval ) {
        # if we hit a parse error, delete the uploaded files
        foreach my $mogkey ( @uploaded_files ) {
            DW::BlobStore->delete( temp => $mogkey );
        }

        if (index(lc($$errorref), 'unknown format') == 0) {
            $$errorref = LJ::Lang::ml(".error.unknowntype");
        } else {
            $$errorref = "couldn't parse upload: $$errorref";
        }
        # the error page is printed in the caller
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
        return $err->("No MIME boundary.  Bogus Content-type? $mimetype");
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
                return $err->("No data from client.  Possibly a refresh?");
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
                    return $err->("Couldn't find separator, no more data to read");
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
                    return $err->("Window too large: " . length($window) . " bytes > 8192");
                }

                # bogus if we're done reading and didn't find what we're
                # looking for:
                if ($read == -1) {
                    return $err->("Couldn't find headers, no more data to read");
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
