#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013-2018 by Dreamwidth Studios, LLC.
#
# This code is a refactoring and extension of code originally forked
# from the LiveJournal project owned and operated by Live Journal, Inc.
# The code has been refactored, modified, and expanded by Dreamwidth
# Studios, LLC. These files were originally licensed under the terms
# of the license supplied by Live Journal, Inc, which can currently
# be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# This file is a refactoring of "cgi-bin/LJ/Emailpost.pm"
# from the original LiveJournal repository

package DW::EmailPost::Entry;

use base qw(DW::EmailPost::Base);
use strict;

use LJ::Protocol;

use Date::Parse;
use IO::Handle;
use XML::Simple;
use DW::Media;

my $workdir = "/tmp";

BEGIN {
    if ( $LJ::USE_PGP ) {
        eval 'use GnuPG::Interface';
        die "Could not load GnuPG::Interface." if $@;
    }
}


=head1 NAME

DW::EmailPost::Entry - Handle entries posted through email

=cut

sub _find_destination {
    my ( $class, @to_addresses ) = @_;

    foreach my $dest ( @to_addresses ) {
        next unless $dest =~ /^(\S+?)\@\Q$LJ::EMAIL_POST_DOMAIN\E$/i;
        return $1;
    }
    return;
}

sub _parse_destination {
    my ( $self, $auth_string ) = @_;

    # user and journal
    my ( $user, $journal, $pin );

    # ignore pin, handle it later
    ( $user, $pin ) = split /\+/, $auth_string;
    ( $user, $journal ) = split /\./, $user if $user =~ /\./;

    $self->{u} = LJ::load_user( $user );
    return unless $self->{u};

    $self->{journal} = $journal || $self->{u}->user;

    return 1;
}

sub _process {
    my $self = $_[0];

    $self->_extract_pin;
    $self->_check_pin_validity or return $self->send_error;

    $self->_cleanup_mobile_carriers or return $self->send_error;

    # not sure why this isn't with $self->_check_pin_validity
    # maybe need to go through mobile cleanup first?
    $self->_check_pgp_validity or return $self->send_error;

    # figure out what entryprops should be based on post headers in email
    # and user's defaults
    $self->_set_props( $self->{u}, $self->{email_date}, %{ $self->{post_headers} || {} } )
        or return $self->send_error;

    # insert any images.
    # must be done after we've processed the props, to make sure we respect security settings
    $self->insert_images;

    # do a final cleanup of the body text
    $self->cleanup_body_final;

    # build the entry
    my $time = $self->{time};
    my $req = {
        usejournal  => $self->{journal},
        ver         => 1,
        username    => $self->{u}->user,
        event       => $self->{body},
        subject     => $self->{subject},
        security    => $self->{security},
        allowmask   => $self->{amask},
        props       => $self->{props},
        tz          => $time->{zone},
        year        => $time->{year} + 1900,
        mon         => $time->{mon} + 1,
        day         => $time->{day},
        hour        => $time->{hour},
        min         => $time->{min},
    };

    # post!
    my $post_error;
    LJ::Protocol::do_request( "postevent", $req, \$post_error, { noauth => 1, allow_truncated_subject => 1 } );
    return $self->send_error( LJ::Protocol::error_message( $post_error ) ) if $post_error;

    $self->dblog( s => $self->{subject} );
    return ( 1, "Post success" );
}

sub _extract_pin {
    my $self = $_[0];

    my ( undef, $pin ) = split /\+/, $self->{destination};
    $self->{pin} = $pin;

    # Strip (and maybe use) pin data from viewable areas
    my $strip_pin = sub {
        my $textref = $_[0];
        my $pin;

        if ( $$textref =~ s/^\s*\+([a-z0-9]+)\b//i ) {
            $pin = $1;
        }

        return $pin;
    };
    $self->{pin} ||= $strip_pin->( \ $self->{subject} );
    $self->{pin} ||= $strip_pin->( \ $self->{body} );
}

sub _set_props {
    my ( $self, $u, $email_date, %post_headers ) = @_;

    my $props = {};
    my $time = {};

    # Pull the Date: header details
    my ( $ss, $mm, $hh, $day, $month, $year, $zone ) =
            strptime( $email_date );

    # If we had an lj/post-date pseudo header, override the real Date header
    ( $ss, $mm, $hh, $day, $month, $year, $zone ) =
        strptime( $post_headers{date} ) if $post_headers{date};

    # TZ is parsed into seconds, we want something more like -0800
    $zone = defined $zone ? sprintf( '%+05d', $zone / 36 ) : 'guess';

    $time = {
        sec  => $ss,
        min  => $mm,
        hour => $hh,
        day  => $day,
        mon  => $month,
        year => $year,
        zone => $zone,
    };

    $u->preload_props(
        qw/
          emailpost_userpic emailpost_security
          emailpost_comments emailpost_gallery
        /
    );

    # Get post options, using post-headers first, and falling back
    # to user props.  If neither exist, the regular journal defaults
    # are used.
    $props->{taglist} = $post_headers{tags};
    $props->{picture_keyword} = $post_headers{userpic} ||
                                $post_headers{icon} ||
                                $u->{emailpost_userpic};
    if ( my $id = DW::Mood->mood_id( $post_headers{mood} ) ) {
        $props->{current_moodid}   = $id;
    } else {
        $props->{current_mood}     = $post_headers{mood};
    }
    $props->{current_music}    = $post_headers{music};
    $props->{current_location} = $post_headers{location};
    $props->{opt_nocomments} = 1
      if $post_headers{comments}    =~ /off/i
      || $u->{emailpost_comments} =~ /off/i;
    $props->{opt_noemail} = 1
      if $post_headers{comments}    =~ /noemail/i
      || $u->{emailpost_comments} =~ /noemail/i;
    if ( exists $post_headers{screenlevel} ) {
        if ( $post_headers{screenlevel} =~ /^all$/i ) {
            $props->{opt_screening} = 'A';
        } elsif ( $post_headers{screenlevel} =~ /^untrusted$/i ) {
            $props->{opt_screening} = 'F';
        } elsif ( $post_headers{screenlevel} =~ /^(anonymous|anon)$/i ) {
            $props->{opt_screening} = 'R'; # needs-Remote
        } elsif ( $post_headers{screenlevel} =~ /^(disabled|none)$/i ) {
            $props->{opt_screening} = 'N';
        } elsif ( $post_headers{screenlevel} ne '' ) {
            $props->{opt_screening} = 'A';
            $self->send_error( "Unrecognized screening keyword. Your entry was posted with all comments screened.",
                               { nolog => 1 } );
        } else { # blank
            $props->{opt_screening} = ''; # User default
        }
    } else { # unspecified
        $props->{opt_screening} = ''; # User default
    }

    my $security;
    my $amask;
    # "lc" is right here because groupnames are forcibly lowercased in
    # LJ::User->trust_groups;
    $security = lc $post_headers{security} ||
        $u->emailpost_security; # FIXME: relies on emailpost_security ne 'usemask'?

    if ( $security =~ /^(public|private|friends|access)$/ ) {
        if ( $1 eq 'friends' or $1 eq 'access' ) {
            $security = 'usemask';
            $amask = 1;
        }
    } elsif ( $security ) { # Assume a trust group list if unknown security.
        # Get the mask for the requested trust group list, discarding those
        # that don't exist.
        $amask = 0;
        my @unrecognized = ();
        foreach my $groupname ( split( /\s*,\s*/, $security ) ) {
            my $group = $u->trust_groups( name => $groupname );
            if ( $group ) {
                $amask |= ( 1 << $group->{groupnum} )
            } else {
                push @unrecognized, $groupname;
            }
        }

        $security = 'usemask';

        if ( @unrecognized ) {
            # send the error, but not shortcircuiting the posting process
            # probably the only time that we call $self->send_error inside of a convenience sub
            my $unrecognized = join( ', ', @unrecognized );
            $self->send_error( "Access group(s) \"$unrecognized\" not found. Your journal entry was posted to the other groups, or privately if no groups exist.",
                   { nolog => 1 }
            );
        }
    }

    $self->{props} = $props;
    $self->{security} = $security;
    $self->{amask} = $amask;
    $self->{time} = $time;

    return 1;
}

=head2 C<< $self->insert_images >>

Take images from the email body and insert them into the entry

=cut
# could hypothetically be refactored out into Base.pm so that other subclasses could use
# but you'd probably want to pass in the variables instead of referring to $self
sub insert_images {
    my ( $self ) = @_;

    # upload picture attachments
    # undef return value? retry posting for later.
    my $fb_upload = $self->_upload_images(
             security => $self->{security},
             allowmask => $self->{amask},
       );

     # if we found and successfully uploaded some images...
     if ( ref $fb_upload eq 'ARRAY' ) {
         my $fb_html = join( '<br />', map { '<img src="' . $_->url . '" />' } @$fb_upload );

         ##
         ## A problem was here:
         ## $body is utf-8 text without utf-8 flag (see Unicode::MapUTF8::to_utf8),
         ## $fb_html is ASCII with utf-8 flag on (because uploaded image description
         ## is parsed by XML::Simple, see cgi-bin/fbupload.pl, line 153).
         ## When 2 strings are concatenated, $body is auto-converted (incorrectly)
         ## from Latin-1 to UTF-8.
         ##
         $fb_html = Encode::encode( "utf8", $fb_html ) if Encode::is_utf8( $fb_html );
         $self->{body} .= '<br />' . $fb_html;
     }

     # at this point, there are either no images in the message ($fb_upload == 1)
     # or we had some error during upload that we may or may not want to retry
     # from.  $fb_upload contains the http error code.
     if (   $fb_upload == 400   # bad http request
         || $fb_upload == 1401  # user has exceeded the fb quota
         || $fb_upload == 1402  # user has exceeded the fb quota
     ) {
         # don't retry these errors, go ahead and post the body
         # to the journal, postfixed with the remote error.
         $self->{body} .= "\n";
         $self->{body} .= "(Your picture was not posted)";
     }
}

# Return codes
# 1 - no images found in mime entity
# undef - failure during upload
# http_code - failure during upload w/ code
# hashref - { title => url } for each image uploaded
sub _upload_images {
    my ( $self, %opts ) = @_;

    my @imgs = $self->get_entity( $self->{_entity}, 'image' );
    return 1 unless scalar @imgs;

    return 1401 unless DW::Media->can_upload_media( $self->{u} );  # error code from insert_images

    my @images;
    foreach my $img_entity ( @imgs ) {
        my $obj = DW::Media->upload_media(
             user => $self->{u},
             data => $img_entity->bodyhandle->as_string,
             %opts, # Should contain security.
        );
        push @images, $obj if $obj;
    }

    return unless scalar @images;
    return \@images;
}

sub _check_pin_validity {
    my $self = $_[0];

    my $from = $self->{from};
    my $pin = $self->{pin};
    my $u = $self->{u};

    # pgp is handled elsewhere
    return 1 if lc $pin eq 'pgp' && $LJ::USE_PGP;

    # Validity checks.  We only care about these if they aren't using PGP.
    my $addrlist = LJ::Emailpost::Web::get_allowed_senders( $self->{u} );
    unless ( ref $addrlist && keys %$addrlist ) {
        return $self->err( "No allowed senders have been saved for your account.",
            { nomail => 1 } );
        return;
    }

    return $self->err( "Unauthorized sender address: $from" )
        unless grep { lc $from eq lc $_ } keys %$addrlist;

    return $self->err( "Unable to locate your PIN." )
        unless $pin;
    return $self->err( "Invalid PIN." )
        unless lc $pin eq lc $u->prop( 'emailpost_pin' );

    return 1;
}

sub _check_pgp_validity {
    my $self = $_[0];

    return 1 unless lc $self->{pin} eq 'pgp' && $LJ::USE_PGP;

    # PGP signed mail?  We'll see about that.
    my %gpg_errcodes = ( # temp mapping until translation
            'bad'         => "PGP signature found to be invalid.",
            'no_key'      => "You don't have a PGP key uploaded.",
            'bad_tmpdir'  => "Problem generating tempdir: Please try again.",
            'invalid_key' => "Your PGP key is invalid.  Please upload a proper key.",
            'not_signed'  => "You specified PGP verification, but your message isn't PGP signed!"
    );

    my $gpgerr;
    my $gpgcode = $self->_check_sig( $self->{u}, $self->{_entity}, \$gpgerr );
    unless ( $gpgcode eq 'good' ) {
        my $errstr = $gpg_errcodes{$gpgcode};
        $errstr .= "\nGnuPG error output:\n$gpgerr\n" if $gpgerr;
        return $self->err( $errstr );
    }

    # Strip pgp clearsigning and any extra text surrounding it
    # This takes into account pgp 'dash escaping' and a possible lack of Hash: headers
    $self->{body} =~ s/.*?^-----BEGIN PGP SIGNED MESSAGE-----(?:\n[^\n].*?\n\n|\n\n)//ms;
    $self->{body} =~ s/-----BEGIN PGP SIGNATURE-----.+//s;

    return 1;
}


# Verifies an email pgp signature as being valid.
# Returns codes so we can use the pre-existing err subref,
# without passing everything all over the place.
#
# note that gpg interaction requires gpg version 1.2.4 or better.
sub _check_sig {
    my ( $self, $u, $entity, $gpg_err ) = @_;

    my $key = LJ::isu( $u ) ? $u->prop( 'public_key' ) : undef;
    return 'no_key' unless $key;

    # Create work directory.
    my $tmpdir = File::Temp::tempdir("ljmailgate_" . 'X' x 20, DIR => $workdir);
    return 'bad_tmpdir' unless -e $tmpdir;

    my ( $in, $out, $err, $status,
        $gpg_handles, $gpg, $gpg_pid, $ret );

    my $check = sub {
        my %rets =
            (
             'NODATA 1'     => 1,   # no key or no signed data
             'NODATA 2'     => 2,   # no signed content
             'NODATA 3'     => 3,   # error checking sig (crc)
             'IMPORT_RES 0' => 4,   # error importing key (crc)
             'BADSIG'       => 5,   # good crc, bad sig
             'GOODSIG'      => 6,   # all is well
            );
        while (my $gline = <$status>) {
            foreach (keys %rets) {
                next unless $gline =~ /($_)/;
                return $rets{$1};
            }
        }
        return 0;
    };

    my $gpg_cleanup = sub {
        close $in;
        close $out;
        waitpid $gpg_pid, 0;
        undef foreach $gpg, $gpg_handles;
    };

    my $gpg_pipe = sub {
        $_ = IO::Handle->new() foreach $in, $out, $err, $status;
        $gpg_handles = GnuPG::Handles->new( stdin  => $in,  stdout=> $out,
                                            stderr => $err, status=> $status );
        $gpg = GnuPG::Interface->new();
        $gpg->options->hash_init( armor => 1, homedir => $tmpdir );
        $gpg->options->meta_interactive( 0 );
    };

    # Pull in user's key, add to keyring.
    $gpg_pipe->();
    $gpg_pid = $gpg->import_keys( handles => $gpg_handles );
    print $in $key;
    $gpg_cleanup->();
    $ret = $check->();
    if ($ret && $ret == 1 || $ret == 4) {
        $$gpg_err .= "    $_" while (<$err>);
        return 'invalid_key';
    }

    my ($txt, $txt_f, $txt_e, $sig_e);
    $txt_e = (get_entity($entity))[0];
    return 'bad' unless $txt_e;

    if ($entity->effective_type() eq 'multipart/signed') {
        # attached signature
        $sig_e = (get_entity($entity, 'application/pgp-signature'))[0];
        $txt = $txt_e->as_string();
        my $txt_fh;
        ($txt_fh, $txt_f) =
            File::Temp::tempfile('plaintext_XXXXXXXX', DIR => $tmpdir);
        print $txt_fh $txt;
        close $txt_fh;
    } # otherwise, it's clearsigned

    # Validate message.
    # txt_e->bodyhandle->path() is clearsigned message in its entirety.
    # txt_f is the ascii text that was signed (in the event of sig-as-attachment),
    #     with MIME headers attached.
    $gpg_pipe->();
    $gpg_pid =
        $gpg->wrap_call( handles => $gpg_handles,
                         commands => [qw( --trust-model always --verify )],
                         command_args => $sig_e ?
                             [$sig_e->bodyhandle->path(), $txt_f] :
                             $txt_e->bodyhandle->path()
                    );
    $gpg_cleanup->();
    $ret = $check->();
    if ($ret && $ret != 6) {
        $$gpg_err .= "    $_" while (<$err>);
        return 'bad' if $ret =~ /[35]/;
        return 'not_signed' if $ret =~ /[12]/;
    }

    return 'good' if $ret == 6;
    return;
}

sub _cleanup_mobile_carriers {
    my $self = $_[0];

    # Is this message from a sprint PCS phone?  Sprint doesn't support
    # MMS (yet) - when it does, we should just be able to rip this block
    # of code completely out.
    #
    # Sprint has two methods of non-mms mail sending.
    #   -  Normal text messaging just sends a text/plain piece.
    #   -  Sprint "PictureMail".
    # PictureMail sends a text/html piece, that contains XML with
    # the location of the image on their servers - and a text/plain as well.
    # (The text/plain used to be blank, now it's really text/plain.  We still
    # can't use it, however, without heavy and fragile parsing.)
    # We assume the existence of a text/html means this is a PictureMail message,
    # as there is no other method (headers or otherwise) to tell the difference,
    # and Sprint tells me that their text messaging never contains text/html.
    # Currently, PictureMail can only contain one image per message
    # and the image is always a jpeg. (2/2/05)
    my $return_path = $self->{return_path};
    my $content_type = $self->{content_type};
    my $tent = $self->{_tent};

    if ( $return_path =~ /(?:messaging|pm)\.sprint(?:pcs)?\.com/ &&
         $content_type->{"_orig"} =~ m#^multipart/alternative#i ) {

        $tent = $self->get_entity( $self->{_entity}, 'html' );

        return $self->err( "Unable to find Sprint HTML content in PictureMail message." )
            unless $tent;

        # ok, parse the XML.
        my $html = $tent->bodyhandle->as_string();
        my $xml_string;
        $xml_string = $1 if $html =~ /<!-- lsPictureMail-Share-\w+-comment\n(.+)\n-->/is;
        return $self->err( "Unable to find XML content in PictureMail message." )
            unless $xml_string;

        LJ::dhtml( $xml_string ); # $xml_string is being modified by this function call
                                  # special characters are replaced with equivalent HTML entities
        my $xml = eval { XML::Simple::XMLin( $xml_string ); };
        return $self->err( "Unable to parse XML content in PictureMail message." )
            if ! $xml || $@;

        return $self->err( "Sorry, we currently only support image media." )
            unless $xml->{messageContents}->{type} eq 'PICTURE';

        my $url =
          LJ::dhtml( $xml->{messageContents}->{mediaItems}->{mediaItem}->{url} );
        $url = LJ::trim($url);
        $url =~ s#</?url>##g;

        return $self->err( "Invalid remote SprintPCS URL." )
            unless $url =~ m#^http://pictures.sprintpcs.com/#;

        # we've got the url to the full sized image.
        # fetch!
        my ( $tmpdir, $tempfile );
        $tmpdir = File::Temp::tempdir( "ljmailgate_" . 'X' x 20, DIR => $workdir );
        ( undef, $tempfile ) = File::Temp::tempfile(
            'sprintpcs_XXXXX',
            SUFFIX => '.jpg',
            OPEN   => 0,
            DIR    => $tmpdir
        );
        my $ua = LJ::get_useragent(
                                   role    => 'emailgateway',
                                   timeout => 20,
                                   );

        $ua->agent( "Mozilla" );

        my $ua_rv = $ua->get( $url, ':content_file' => $tempfile );

        $self->{body} = $xml->{messageContents}->{messageText};
        $self->{body} = ref $self->{body} ? "" : LJ::dhtml( $self->{body} );

        if ($ua_rv->is_success) {
            # (re)create a basic mime entity, so the rest of the
            # emailgateway can function without modifications.
            # (We don't need anything but Data, the other parts have
            # already been pulled from $head->unfold)
            $self->{subject} = 'Picture Post';
            $self->{_entity} = MIME::Entity->build( Data => $self->{body} );
            $self->{_entity}->attach(
                Path => $tempfile,
                Type => 'image/jpeg'
            );
        }
        else {
            # Retry if we are unable to connect to the remote server.
            # Otherwise, the image has probably expired.  Dequeue.
            my $reason = $ua_rv->status_line;
            return $self->err( "Unable to fetch SprintPCS image. ($reason)",
                {
                    retry => $reason =~ /Connection refused/
                }
            );
        }
    }

    # tmobile hell.
    # if there is a message, then they send text/plain and text/html,
    # with a slew of their tmobile specific images.  If no message
    # is attached, there is no text/plain piece, and the journal is
    # polluted with their advertising.  (The tmobile images (both good
    # and junk) are posted to scrapbook either way.)
    # gross.  do our best to strip out the nasty stuff.
    if ( $return_path && $return_path =~ /tmomail\.net$/ ) {
        # if we aren't using their text/plain, then it's just
        # advertising, and nothing else.  kill it.
        $self->{body} = "" if $tent->effective_type eq 'text/html';

        # t-mobile has a variety of different file names, so we can't just allow "good"
        # files through; rather, we can just strip out the bad filenames.
        my @imgs;
        foreach my $img ( $self->get_entity( $self->{_entity}, 'image' ) ) {
            my $path = $img->bodyhandle->path;
            $path =~ s!.*/!!;
            next if $path =~ /^dottedline(350|600).gif$/;
            next if $path =~ /^audio.gif$/;
            next if $path =~ /^tmobilelogo.gif$/;
            next if $path =~ /^tmobilespace.gif$/;
            push @imgs, $img; # it's a good file if it made it this far.
        }
        $self->{entity}->parts(\@imgs);
    }

    # alltel. similar logic to t-mobile.
    if ( $return_path && $return_path =~ /mms\.alltel\.net$/ ) {
        my @imgs;
        foreach my $img ( $self->get_entity( $self->{_entity}, 'image' ) ) {
            my $path = $img->bodyhandle->path;
            $path =~ s!.*/!!;
            next if $path =~ /^divider\.gif$/;
            next if $path =~ /^spacer\.gif$/;
            next if $path =~ /^bluebar\.gif$/;
            next if $path =~ /^header\.gif$/;
            next if $path =~ /^greenbar\.gif$/;
            next if $path =~ /^alltel_logo\.jpg$/;

            push @imgs, $img; # it's a good file if it made it this far.
        }
        $self->{_entity}->parts(\@imgs);
    }

    # verizon crap.  remove paragraphs of text.
    $self->{body} =~ s/This message was sent using.+?Verizon.+?faster download\.//s;

    # virgin mobile adds text to the *top* of the message, killing post-headers.
    # Kill this silly (and grammatically incorrect) string.
    if ( $return_path && $return_path =~ /vmpix\.com$/ ) {
        $self->{body} =~ s/^This is an? MMS message\.\s+//ms;
    }

    # UK service 'O2' does some bizarre stuff.
    # No concept of a subject - it uses the first 40 characters from the body,
    # truncating the rest.  The first text/plain is all advertising.
    # The text/plain titled 'smil.txt' is the actual body of the message.
    if ($return_path && $return_path =~ /mediamessaging\.o2\.co\.uk$/) {
        foreach my $ent ( $self->get_entity( $self->{_entity}, '*' ) ) {
            my $path = $ent->bodyhandle->path;
            $path =~ s#.*/##;
            if ( $path eq 'smil.txt' ) {
                $self->{body} = $ent->bodyhandle->as_string();
                last;
            }
        }
        $self->{subject} = 'Picture Post';
    }

    return 1;
}

1;
