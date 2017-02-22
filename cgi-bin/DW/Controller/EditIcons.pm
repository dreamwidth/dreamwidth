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
                        # have to store the file, this is the interface that the userpic factory uses
                        # to get files between the N different web processes you might talk to
                        my $rv = DW::BlobStore->store(
                            temp => "upf_${counter}:$u->{userid}",
                            $current_upload{image}
                        );
                        unless ( $rv ) {
                            $current_upload{error} = 'Failed to upload file to storage system.';
                            push @uploads, \%current_upload;
                            next;
                        }

                        eval {
                            my $picinfo = LJ::Userpic->get_upf_scaled(
                                mogkey => "upf_${counter}:$u->{userid}",
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

1;