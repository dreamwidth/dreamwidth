#!/usr/bin/perl

package LJ::FBUpload;
use strict;

use lib "$ENV{LJHOME}/cgi-bin";
use LJ::Config;
LJ::Config->load;

require "ljlib.pl";

use MIME::Words ();
use XML::Simple;
use IO::Handle;
use LWP::UserAgent;
use URI::Escape;
use Digest::MD5 ();
use File::Basename ();

*hash = \&Digest::MD5::md5_hex;

# This has bitten us one too many times.
# Don't let startup continue unless LWP is ok.
die "* Installed version of LWP is too old! *" if LWP->VERSION < 5.803;

sub make_auth
{
    my ($chal, $password) = @_;
    return unless $chal && $password;
    return "crp:$chal:" . hash($chal . hash($password));
}

sub get_challenge
{
    my ($u, $ua, $err) = @_;
    return unless $u && $ua;

    my $req = HTTP::Request->new(GET => "$LJ::FB_SITEROOT/interface/simple");
    $req->push_header("X-FB-Mode" => "GetChallenge");
    $req->push_header("X-FB-User" => $u->{'user'});

    my $res = $$ua->request($req);
    if ($res->is_success()) {

        my $xmlres = XML::Simple::XMLin($res->content);
        my $methres = $xmlres->{GetChallengeResponse};
        return $methres->{Challenge};

    } else {
        $$err = $res->content();
        return;
    }
}

# <LJFUNC>
# name: LJ::FBUpload::do_upload
# des: Uploads an image to FotoBilder from LiveJournal.
# args: path, rawdata?, imgsec, caption?, galname
# des-path: => path to image on disk, or title to use if 'rawdata' isn't on disk.
# des-rawdata: => optional image data scalar ref.
# des-imgsec: => bitmask for image security. Defaults to private on
#             unknown strings. Lack of an imgsec opt means public.
# des-caption: => optional image description.
# des-galname: => gallery to upload image to.
# info:
# returns: FB protocol data structure, regardless of FB success or failure. 
#         It's the callers responsibility to check the structure 
#         for FB return values.
#         On HTTP failure, returns numeric HTTP error code, and
#         sets $rv reference with errorstring. Or undef on unrecoverable failure.
# </LJFUNC>
sub do_upload
{
    my ($u, $rv, $opts) = @_;
    unless ($u && $opts->{'path'}) {
        $$rv = "Invalid parameters to do_upload()";
        return;
    }

    my $ua = LWP::UserAgent->new;
    $ua->agent("LiveJournal_FBUpload/0.2");

    my $err;
    my $chal = get_challenge($u, \$ua, \$err);
    unless ($chal) {
        $$rv = "Error getting challenge from FB server: $err";
        return;
    }

    my $rawdata = $opts->{'rawdata'};
    unless ($rawdata) {
        # no rawdata was passed, so slurp it in ourselves
        unless (open (F, $opts->{'path'})) {
            $$rv = "Couldn't read image file: $!\n";
            return;
        }
        binmode(F);
        my $data;
        { local $/ = undef; $data = <F>; }
        $rawdata = \$data;
        close F;
    }

    # convert strings to security masks/
    # default to private on unknown strings.
    # lack of an imgsec opt means public.
    $opts->{imgsec} ||= 255;
    unless ($opts->{imgsec} =~ /^\d+$/) {
        my %groupmap = (
            private  => 0,   regusers => 253,
            friends  => 254, public => 255
        );
        $opts->{imgsec} = 'private' unless $groupmap{ $opts->{imgsec} };
        $opts->{imgsec} = $groupmap{ $opts->{imgsec} };
    }

    my $basename = File::Basename::basename($opts->{'path'});
    my $length = length $$rawdata;

    my $req = HTTP::Request->new(PUT => "$LJ::FB_SITEROOT/interface/simple");
    my %headers = (
        'X-FB-Mode'                    => 'UploadPic',
        'X-FB-UploadPic.ImageLength'   => $length,
        'Content-Length'               => $length,
        'X-FB-UploadPic.Meta.Filename' => $basename,
        'X-FB-UploadPic.MD5'           => hash($$rawdata),
        'X-FB-User'                    => $u->{'user'},
        'X-FB-Auth'                    => make_auth( $chal, $u->password ),
        ':X-FB-UploadPic.Gallery._size'=> 1,
        'X-FB-UploadPic.PicSec'        => $opts->{'imgsec'},
        'X-FB-UploadPic.Gallery.0.GalName' => $opts->{'galname'} || 'LJ_emailpost',
        'X-FB-UploadPic.Gallery.0.GalSec'  => 255
    );

    $headers{'X-FB-UploadPic.Meta.Title'} = $opts->{title}
      if $opts->{title};

    $headers{'X-FB-UploadPic.Meta.Description'} = $opts->{caption}
      if $opts->{caption};

    $req->push_header($_, $headers{$_}) foreach keys %headers;

    $req->content($$rawdata);
    my $res = $ua->request($req);

    my $res_code = $1 if $res->status_line =~ /^(\d+)/;
    unless ($res->is_success) {
        $$rv = "HTTP error uploading pict: " . $res->content();
        return $res_code;
    }

    my $xmlres;
    eval { $xmlres = XML::Simple::XMLin($res->content); };
    if ($@) {
        $$rv = "Error parsing XML: $@";
        return;
    }
    my $methres = $xmlres->{UploadPicResponse};
    $methres->{Title} = $basename;

    return $methres;
}

# args:
#       $u,
#       arrayref of { title, url, width, height, caption }
#       optional opts overrides hashref.
#               (if not supplied, userprops are used.)
# returns: html string suitable for entry post body
# TODO: Hook this like the Fotobilder "post to journal"
#       caption posting page.  More pretty. (layout keywords?)
sub make_html
{
    my ($u, $images, $opts) = @_;
    my ($icount, $html);

    $icount = scalar @$images;
    return "" unless $icount;

    # Merge overrides with userprops that might
    # have been passed in.
    $opts = {} unless $opts && ref $opts;
    my @props = qw/ emailpost_imgsize emailpost_imglayout emailpost_imgcut /;

    LJ::load_user_props( $u, @props );
    foreach (@props) {
        my $prop = $_;
        $prop =~ s/emailpost_//;
        $opts->{$prop} = lc($opts->{$prop}) || $u->{$_};
    }

    $html .= "\n";

    # set journal image display size
    my @valid_sizes = qw/ 100x100 320x240 640x480 /;
    $opts->{imgsize} = '320x240' unless grep { $opts->{imgsize} eq $_; } @valid_sizes;
    my ($width, $height) = split 'x', $opts->{imgsize};
    my $size = '/s' . $opts->{imgsize};

    # force lj-cut on images larger than 320 in either direction
    $opts->{imgcut} = 'count'
      if ( $width > 320 || $height > 320 ) && ! $opts->{imgcut};

    # insert image links into post body
    my $horiz = $opts->{imglayout} =~ /^horiz/i;
    $html .=
      "<lj-cut text='$icount "
      . ( ( $icount == 1 ) ? 'image' : 'images' ) . "'>"
          if $opts->{imgcut} eq 'count';
    $html .= "<table border='0'><tr>" if $horiz;

    foreach my $i (@$images) {
        my $title = LJ::ehtml($i->{'title'});

        # don't set a size on images smaller than the requested width/height
        # (we never scale larger, just smaller)
        undef $size if $i->{width} <= $width || $i->{height} <= $height;

        $html .= "<td>" if $horiz;
        $html .= "<lj-cut text=\"$title\">" if $opts->{imgcut} eq 'titles';
        $html .= "<a href=\"$i->{url}/\">";
        $html .= "<img src=\"$i->{url}$size\" alt=\"$title\" border=\"0\"></a><br />";
        $html .= "$i->{caption}<br />" if $i->{caption};
        $html .= $horiz ? '</td>' : '<br />';
        $html .= "</lj-cut> " if $opts->{imgcut} eq 'titles';
    }
    $html .= "</tr></table>" if $horiz;
    $html .= "</lj-cut>\n" if $opts->{imgcut} eq 'count';

    return $html;
}

1;
