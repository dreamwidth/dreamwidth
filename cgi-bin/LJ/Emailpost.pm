#!/usr/bin/perl
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.


package LJ::Emailpost;
use strict;
use lib "$LJ::HOME/cgi-bin";
use LJ::Config;

my $workdir = "/tmp";

BEGIN {
    LJ::Config->load;
    if ($LJ::USE_PGP) {
        eval 'use GnuPG::Interface';
        die "Could not load GnuPG::Interface." if $@;
    }
}

require 'ljlib.pl';
use LJ::Emailpost::Web;
use LJ::Protocol;
use Date::Parse;
use HTML::Entities;
use IO::Handle;
use MIME::Words ();
use XML::Simple;
use Unicode::MapUTF8 ();
use Encode;

# $entity -- MIME object
# $to -- left part of email address.  either a username, or "username+PIN"
# $rv - scalar ref from mailgated.
# set to 1 to dequeue, 0 to leave for further processing.
#
sub process {
    my ($entity, $to, $rv) = @_;

    my (
        # journal vars
        $head, $user, $journal,
        $pin, $u, $req, $post_error,

        # email vars
        $from, $addrlist, $return_path,
        $body, $subject, $charset,
        $format, $tent,

        # pict upload vars
       $fb_upload, $fb_upload_errstr,
    );

    $head = $entity->head;
    $head->unfold;

    $$rv = 1;  # default dequeue

    # Parse email for lj specific info
    ($user, $pin) = split(/\+/, $to);
    ($user, $journal) = split(/\./, $user) if $user =~ /\./;
    $u = LJ::load_user($user);
    return unless $u && $u->is_visible;

    # Pick what address to send potential errors to.
    $addrlist = LJ::Emailpost::Web::get_allowed_senders( $u );
    $from = ${(Mail::Address->parse( $head->get('From:') ))[0] || []}[1];
    return unless $from;
    my $err_addr;
    foreach (keys %$addrlist) {
        if (lc($from) eq lc &&
                $addrlist->{$_}->{'get_errors'}) {
            $err_addr = $from;
            last;
        }
    }

    my $err = sub {
        my ($msg, $opt) = @_;

        my $errbody;
        $errbody .= "There was an error during your email posting:\n\n";
        $errbody .= $msg;
        if ($body) {
            $errbody .= "\n\n\nOriginal posting follows:\n\n";
            $errbody .= $body;
        }

        # Rate limit email to 1/5min/address
        if (! $opt->{nomail} && ! $opt->{retry} && $err_addr &&
            LJ::MemCache::add("rate_eperr:$err_addr", 5, 300)) {
            LJ::send_mail({
                    'to' => $err_addr,
                    'from' => $LJ::BOGUS_EMAIL,
                    'fromname' => "$LJ::SITENAME Error",
                    'subject' => "$LJ::SITENAME posting error: $subject",
                    'body' => $errbody
                    });
        }
        $$rv = 0 if $opt->{'retry'};

        $opt->{m} = $msg;
        $opt->{s} = $subject;
        $opt->{e} = 1;
        dblog( $u, $opt ) unless $opt->{nolog};
        return $msg;
    };

    # The return path should normally not ever be perverted enough to require this,
    # but some mailers nowadays do some very strange things.
    $return_path = ${(Mail::Address->parse( $head->get('Return-Path') ))[0] || []}[1];

    # Use text/plain piece first - if it doesn't exist, then fallback to text/html
    $tent = get_entity( $entity );
    $tent = get_entity( $entity, 'html' ) unless $tent;

    $body = $tent ? $tent->bodyhandle->as_string : "";
    $body =~ s/^\s+//;
    $body =~ s/\s+$//;

    # Snag charset and do utf-8 conversion
    my $content_type = $tent ? $tent->head->get('Content-type:') : '';
    $charset = $1 if $content_type =~ /\bcharset=['\"]?(\S+?)['\"]?[\s\;]/i;
    $format = $1 if $content_type =~ /\bformat=['\"]?(\S+?)['\"]?[\s\;]/i;
    my $delsp;
    $delsp = $1 if $content_type =~ /\bdelsp=['\"]?(\w+?)['\"]?[\s\;]/i;

    if (defined($charset) && $charset !~ /^UTF-?8$/i) { # no charset? assume us-ascii
        return $err->("Unknown charset encoding type. ($charset)")
            unless Unicode::MapUTF8::utf8_supported_charset($charset);
        $body = Unicode::MapUTF8::to_utf8({-string=>$body, -charset=>$charset});
    }

    # check subject for rfc-1521 junk
    $subject ||= $head->get('Subject:');
    chomp $subject;
    if ($subject =~ /^=\?/) {
        my @subj_data = MIME::Words::decode_mimewords( $subject );
        my ( $string, $charset ) = ( $subj_data[0][0], $subj_data[0][1] );
        if (@subj_data) {
            if ($subject =~ /utf-8/i) {
                $subject = $string;
            } else {
                return $err->("Unknown subject charset encoding type. ($charset)")
                    unless $charset && Unicode::MapUTF8::utf8_supported_charset($charset);

                $subject = Unicode::MapUTF8::to_utf8({
                    -string  => $string,
                    -charset => $charset,
                });
            }
        }
    }

    # Strip (and maybe use) pin data from viewable areas
    if ($subject =~ s/^\s*\+([a-z0-9]+)\b//i) {
        $pin = $1 unless defined $pin;
    }

    if ($body =~ s/^\s*\+([a-z0-9]+)\b//i) {
        $pin = $1 unless defined $pin;
    }

    # Validity checks.  We only care about these if they aren't using PGP.
    unless (lc($pin) eq 'pgp' && $LJ::USE_PGP) {
        return $err->("No allowed senders have been saved for your account.", { nomail => 1 }) unless
            ref $addrlist && keys %$addrlist;

        # don't mail user due to bounce spam
        return $err->("Unauthorized sender address: $from")
            unless grep { lc($from) eq lc($_) } keys %$addrlist;

        return $err->("Unable to locate your PIN.") unless $pin;
        return $err->("Invalid PIN.")
            unless lc( $pin ) eq lc( $u->prop( 'emailpost_pin' ) );
    }

    return $err->("Email gateway access denied for your account type.")
        unless $LJ::T_ALLOW_EMAILPOST || $u->can_emailpost;

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
    if ($return_path =~ /(?:messaging|pm)\.sprint(?:pcs)?\.com/ &&
        $content_type =~ m#^multipart/alternative#i) {

        $tent = get_entity( $entity, 'html' );

        return $err->("Unable to find Sprint HTML content in PictureMail message.") unless $tent;

        # ok, parse the XML.
        my $html = $tent->bodyhandle->as_string();
        my $xml_string;
        $xml_string = $1 if $html =~ /<!-- lsPictureMail-Share-\w+-comment\n(.+)\n-->/is;
        return $err->(
            "Unable to find XML content in PictureMail message.",
          ) unless $xml_string;

        HTML::Entities::decode_entities( $xml_string );
        my $xml = eval { XML::Simple::XMLin( $xml_string ); };
        return $err->(
            "Unable to parse XML content in PictureMail message.",
          ) if ( ! $xml || $@ );

        return $err->(
            "Sorry, we currently only support image media.",
          ) unless $xml->{messageContents}->{type} eq 'PICTURE';

        my $url =
          HTML::Entities::decode_entities(
            $xml->{messageContents}->{mediaItems}->{mediaItem}->{url} );
        $url = LJ::trim($url);
        $url =~ s#</?url>##g;

        return $err->(
            "Invalid remote SprintPCS URL.",
          ) unless $url =~ m#^http://pictures.sprintpcs.com/#;

        # we've got the url to the full sized image.
        # fetch!
        my ($tmpdir, $tempfile);
        $tmpdir = File::Temp::tempdir( "ljmailgate_" . 'X' x 20, DIR=> $workdir );
        ( undef, $tempfile ) = File::Temp::tempfile(
            'sprintpcs_XXXXX',
            SUFFIX => '.jpg',
            OPEN   => 0,
            DIR    => $tmpdir
        );
        my $ua = LJ::get_useragent(
                                   role => 'emailgateway',
                                   timeout => 20,
                                   );

        $ua->agent("Mozilla");

        my $ua_rv = $ua->get( $url, ':content_file' => $tempfile );

        $body = $xml->{messageContents}->{messageText};
        $body = ref $body ? "" : HTML::Entities::decode( $body );

        if ($ua_rv->is_success) {
            # (re)create a basic mime entity, so the rest of the
            # emailgateway can function without modifications.
            # (We don't need anything but Data, the other parts have
            # already been pulled from $head->unfold)
            $subject = 'Picture Post';
            $entity = MIME::Entity->build( Data => $body );
            $entity->attach(
                Path => $tempfile,
                Type => 'image/jpeg'
            );
        }
        else {
            # Retry if we are unable to connect to the remote server.
            # Otherwise, the image has probably expired.  Dequeue.
            my $reason = $ua_rv->status_line;
            return $err->(
                "Unable to fetch SprintPCS image. ($reason)",
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
    if ($return_path && $return_path =~ /tmomail\.net$/) {
        # if we aren't using their text/plain, then it's just
        # advertising, and nothing else.  kill it.
        $body = "" if $tent->effective_type eq 'text/html';

        # t-mobile has a variety of different file names, so we can't just allow "good"
        # files through; rather, we can just strip out the bad filenames.
        my @imgs;
        foreach my $img ( get_entity($entity, 'image') ) {
            my $path = $img->bodyhandle->path;
            $path =~ s!.*/!!;
            next if $path =~ /^dottedline(350|600).gif$/;
            next if $path =~ /^audio.gif$/;
            next if $path =~ /^tmobilelogo.gif$/;
            next if $path =~ /^tmobilespace.gif$/;
            push @imgs, $img; # it's a good file if it made it this far.
        }
        $entity->parts(\@imgs);
    }

    # alltel. similar logic to t-mobile.
    if ($return_path && $return_path =~ /mms\.alltel\.net$/) {
        my @imgs;
        foreach my $img ( get_entity($entity, 'image') ) {
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
        $entity->parts(\@imgs);
    }

    # verizon crap.  remove paragraphs of text.
    $body =~ s/This message was sent using.+?Verizon.+?faster download\.//s;

    # virgin mobile adds text to the *top* of the message, killing post-headers.
    # Kill this silly (and grammatically incorrect) string.
    if ($return_path && $return_path =~ /vmpix\.com$/) {
        $body =~ s/^This is an? MMS message\.\s+//ms;
    }

    # UK service 'O2' does some bizarre stuff.
    # No concept of a subject - it uses the first 40 characters from the body,
    # truncating the rest.  The first text/plain is all advertising.
    # The text/plain titled 'smil.txt' is the actual body of the message.
    if ($return_path && $return_path =~ /mediamessaging\.o2\.co\.uk$/) {
        foreach my $ent ( get_entity($entity, '*') ) {
            my $path = $ent->bodyhandle->path;
            $path =~ s#.*/##;
            if ( $path eq 'smil.txt' ) {
                $body = $ent->bodyhandle->as_string();
                last;
            }
        }
        $subject = 'Picture Post';
    }

    # PGP signed mail?  We'll see about that.
    if (lc($pin) eq 'pgp' && $LJ::USE_PGP) {
        my %gpg_errcodes = ( # temp mapping until translation
                'bad'         => "PGP signature found to be invalid.",
                'no_key'      => "You don't have a PGP key uploaded.",
                'bad_tmpdir'  => "Problem generating tempdir: Please try again.",
                'invalid_key' => "Your PGP key is invalid.  Please upload a proper key.",
                'not_signed'  => "You specified PGP verification, but your message isn't PGP signed!");
        my $gpgerr;
        my $gpgcode = LJ::Emailpost::check_sig($u, $entity, \$gpgerr);
        unless ($gpgcode eq 'good') {
            my $errstr = $gpg_errcodes{$gpgcode};
            $errstr .= "\nGnuPG error output:\n$gpgerr\n" if $gpgerr;
            return $err->($errstr);
        }

        # Strip pgp clearsigning and any extra text surrounding it
        # This takes into account pgp 'dash escaping' and a possible lack of Hash: headers
        $body =~ s/.*?^-----BEGIN PGP SIGNED MESSAGE-----(?:\n[^\n].*?\n\n|\n\n)//ms;
        $body =~ s/-----BEGIN PGP SIGNATURE-----.+//s;
    }

    $body =~ s/^(?:\- )?[\-_]{2,}(\s|&nbsp;)*\r?\n.*//ms; # trim sigs

    # respect flowed text
    if (lc($format) eq 'flowed') {
        if ($delsp && lc($delsp) eq 'yes') {
            $body =~ s/ \n//g;
        } else {
            $body =~ s/ \n/ /g;
        }
    }


    # trim off excess whitespace (html cleaner converts to breaks)
    $body =~ s/\n+$/\n/;

    # Pull the Date: header details
    my ( $ss, $mm, $hh, $day, $month, $year, $zone ) =
            strptime( $head->get( 'Date:' ) );

    # Find and set entry props.
    my $props = {};
    my (%post_headers, $amask);
    # first look for old style lj headers
    while ($body =~ s/^lj-(.+?):\s*(.+?)\n//is) {
        $post_headers{lc($1)} = LJ::trim($2);
    }
    # next look for new style post headers
    # so if both are specified, this value will be retained
    while ($body =~ s/^post-(.+?):\s*(.+?)\n//is) {
        $post_headers{lc($1)} = LJ::trim($2);
    }
    $body =~ s/^\s*//;

    # If we had an lj/post-date pseudo header, override the real Date header
    ( $ss, $mm, $hh, $day, $month, $year, $zone ) =
        strptime( $post_headers{date} ) if $post_headers{date};

    # TZ is parsed into seconds, we want something more like -0800
    $zone = defined $zone ? sprintf( '%+05d', $zone / 36 ) : 'guess';

    $u->preload_props(
        qw/
          emailpost_userpic emailpost_security
          emailpost_comments emailpost_gallery
          emailpost_imgsecurity /
    );

    # Get post options, using post-headers first, and falling back
    # to user props.  If neither exist, the regular journal defaults
    # are used.
    $props->{taglist} = $post_headers{tags};
    $props->{picture_keyword} = $post_headers{'userpic'} ||
                                $post_headers{'icon'} ||
                                $u->{'emailpost_userpic'};
    if ( my $id = DW::Mood->mood_id( $post_headers{'mood'} ) ) {
        $props->{current_moodid}   = $id;
    } else {
        $props->{current_mood}     = $post_headers{'mood'};
    }
    $props->{current_music}    = $post_headers{'music'};
    $props->{current_location} = $post_headers{'location'};
    $props->{opt_nocomments} = 1
      if $post_headers{comments}    =~ /off/i
      || $u->{'emailpost_comments'} =~ /off/i;
    $props->{opt_noemail} = 1
      if $post_headers{comments}    =~ /noemail/i
      || $u->{'emailpost_comments'} =~ /noemail/i;

    $post_headers{security} = lc($post_headers{security}) || $u->{'emailpost_security'};
    if ( $post_headers{security} =~ /^(public|private|friends|access)$/ ) {
        if ( $1 eq 'friends' or $1 eq 'access' ) {
            $post_headers{security} = 'usemask';
            $amask = 1;
        }
    } elsif ($post_headers{security}) { # Assume a friendgroup if unknown security mode.
        # Get the mask for the requested friends group, or default to private.
        my $group = $u->trust_groups( 'name' => $post_headers{security} );
        if ($group) {
            $amask = (1 << $group->{groupnum});
            $post_headers{security} = 'usemask';
        } else {
            $err->("Access group \"$post_headers{security}\" not found.  Your journal entry was posted privately.",
                   { nolog => 1 });
            $post_headers{security} = 'private';
        }
    }

    # if they specified a imgsecurity header but it isn't valid, default
    # to private.  Otherwise, set to what they specified.
    $post_headers{'imgsecurity'} = lc($post_headers{'imgsecurity'}) ||
                                   $u->{'emailpost_imgsecurity'}  || 'public';
    $post_headers{'imgsecurity'} = 'private'
        unless $post_headers{'imgsecurity'} =~ /^(private|access|public)$/;

    # FIXME: translate security into usemask/allowmask combo

    # upload picture attachments to fotobilder.
    # undef return value? retry posting for later.
    $fb_upload = upload_images(
         $entity, $u,
         \$fb_upload_errstr,
         {
             security => $post_headers{'imgsecurity'},
         }
       ) || return $err->( $fb_upload_errstr, { retry => 1 } );

     # if we found and successfully uploaded some images...
     if (ref $fb_upload eq 'ARRAY') {
         my $fb_html = join( '<br />', map { '<img src="' . $_->url . '" />' } @$fb_upload );

         ##
         ## A problem was here:
         ## $body is utf-8 text without utf-8 flag (see Unicode::MapUTF8::to_utf8),
         ## $fb_html is ASCII with utf-8 flag on (because uploaded image description
         ## is parsed by XML::Simple, see cgi-bin/fbupload.pl, line 153).
         ## When 2 strings are concatenated, $body is auto-converted (incorrectly)
         ## from Latin-1 to UTF-8.
         ##
         $fb_html = Encode::encode("utf8", $fb_html) if Encode::is_utf8($fb_html);
         $body .= $fb_html;
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
         $body .= "\n";
         $body .= "(Your picture was not posted: $fb_upload_errstr)";
     }

     # Fotobilder server error.  Retry.
#     return $err->( $fb_upload_errstr, { retry => 1 } ) if $fb_upload == 500;

    # build lj entry
    $req = {
        usejournal  => $journal,
        ver         => 1,
        username    => $user,
        event       => $body,
        subject     => $subject,
        security    => $post_headers{security},
        allowmask   => $amask,
        props       => $props,
        tz          => $zone,
        year        => $year + 1900,
        mon         => $month + 1,
        day         => $day,
        hour        => $hh,
        min         => $mm,
    };

    # post!
    LJ::Protocol::do_request("postevent", $req, \$post_error, { noauth => 1 });
    return $err->(LJ::Protocol::error_message($post_error)) if $post_error;

    dblog( $u, { s => $subject } );
    return "Post success";
}

# By default, returns first plain text entity from email message.
# Specifying a type will return an array of MIME::Entity handles
# of that type. (image, application, etc)
# Specifying a type of 'all' will return all MIME::Entities,
# regardless of type.
sub get_entity
{
    my ($entity, $type) = @_;

    # old arguments were a hashref
    $type = $type->{'type'} if ref $type eq "HASH";

    # default to text
    $type ||= 'text';

    my $head = $entity->head;
    my $mime_type = $head->mime_type;

    return $entity if $type eq 'text' && $mime_type eq "text/plain";
    return $entity if $type eq 'html' && $mime_type eq "text/html";
    my @entities;

    # Only bother looking in messages that advertise attachments
    my $mimeattach_re = qr{ m|^multipart/(?:alternative|signed|mixed|related)$| };
    if ($mime_type =~ $mimeattach_re) {
        my $partcount = $entity->parts;
        for (my $i=0; $i<$partcount; $i++) {
            my $alte = $entity->parts($i);

            return $alte if $type eq 'text' && $alte->mime_type eq "text/plain";
            return $alte if $type eq 'html' && $alte->mime_type eq "text/html";
            push @entities, $alte if $type eq 'all';

            if ($type eq 'image' &&
                $alte->mime_type =~ m#^application/octet-stream#) {
                my $alte_head = $alte->head;
                my $filename = $alte_head->recommended_filename;
                push @entities, $alte if $filename =~ /\.(?:gif|png|tiff?|jpe?g)$/;
            }
            push @entities, $alte if $alte->mime_type =~ /^$type/ &&
                                     $type ne 'all';

            # Recursively search through nested MIME for various pieces
            if ($alte->mime_type =~ $mimeattach_re) {
                if ($type =~ /^(?:text|html)$/) {
                    my $text_entity = get_entity($entity->parts($i), $type);
                    return $text_entity if $text_entity;
                } else {
                    push @entities, get_entity($entity->parts($i), $type);
                }
            }
        }
    }

    return @entities if $type ne 'text' && scalar @entities;
    return;
}

# Verifies an email pgp signature as being valid.
# Returns codes so we can use the pre-existing err subref,
# without passing everything all over the place.
#
# note that gpg interaction requires gpg version 1.2.4 or better.
sub check_sig {
    my ($u, $entity, $gpg_err) = @_;

    my $key = LJ::isu( $u ) ? $u->prop( 'public_key' ) : undef;
    return 'no_key' unless $key;

    # Create work directory.
    my $tmpdir = File::Temp::tempdir("ljmailgate_" . 'X' x 20, DIR=> $workdir);
    return 'bad_tmpdir' unless -e $tmpdir;

    my ($in, $out, $err, $status,
        $gpg_handles, $gpg, $gpg_pid, $ret);

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
        $gpg->options->hash_init( armor=>1, homedir=>$tmpdir );
        $gpg->options->meta_interactive( 0 );
    };

    # Pull in user's key, add to keyring.
    $gpg_pipe->();
    $gpg_pid = $gpg->import_keys( handles=>$gpg_handles );
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
    return undef;
}

# Upload images to a Fotobilder installation.
# Return codes:
# 1 - no images found in mime entity
# undef - failure during upload
# http_code - failure during upload w/ code
# hashref - { title => url } for each image uploaded
sub upload_images {
    my ( $entity, $u, $rv, $opts ) = @_;

# FIXME: check if user can do this
#     return 1 unless LJ::get_cap($u, 'fb_can_upload') && $LJ::FB_SITEROOT;

    my @imgs = get_entity( $entity, 'image' );
    return 1 unless scalar @imgs;

    my @images;
    foreach my $img_entity ( @imgs ) {
        my $obj = DW::Media->upload_media( user => $u, data => $img_entity->bodyhandle->as_string, %$opts );
        push @images, $obj if $obj;
    }

    return unless scalar @images;
    return \@images;
}

sub dblog
{
    my ( $u, $info ) = @_;
    chomp $info->{s};
    $u->log_event( 'emailpost', $info );
    return;
}

1;

