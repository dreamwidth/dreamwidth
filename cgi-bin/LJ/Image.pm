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

package LJ::Image;
use strict;
use Carp qw(croak);
use Image::Size;

# given an image and some dimensions, will return the dimensions that the image
# should be if it was resized to be no greater than the given dimensions
# (keeping proportions correct).
#
# default dimensions to resize to are:
# 320x240 (for a horizontal image)
# 240x320 (for a vertical image)
# 240x240 (for a square image)
sub get_dimensions_of_resized_image {
    my $class = shift;
    my $imageref = shift;
    my %opts = @_;

    my $given_width = $opts{width} || 320;
    my $given_height = $opts{height} || 240;

    my $percentage = 1;
    my ($width, $height) = Image::Size::imgsize($imageref);
    die "Unable to get image size." unless $width && $height;

    if ($width > $height) {
        if ($width > $given_width) {
            $percentage = $given_width / $width;
        } elsif ($height > $given_height) {
            $percentage = $given_height / $height;
        }
    } elsif ($height > $width) {
        if ($width > $given_height) {
            $percentage = $given_height / $width;
        } elsif ($height > $given_width) {
            $percentage = $given_width / $height;
        }
    } else { # $width == $height
        my $min = $given_width < $given_height ? $given_width : $given_height;
        if ($width > $min) {
            $percentage = $min / $width;
        }
    }

    $width = int($width * $percentage);
    $height = int($height * $percentage);

    return ( width => $width, height => $height );
}

sub prefetch_image_response {
    my $class = shift;
    my $img_url = shift;
    my %opts = @_;

    my $timeout = defined $opts{timeout} ? $opts{timeout} : 3;

    my $ua = LJ::get_useragent( role => 'image_prefetcher', timeout => $timeout ) or die "Unable to get user agent for image";
    $ua->agent("LJ-Image-Prefetch/1.0");

    my $req = HTTP::Request->new( GET => $img_url ) or die "Unable to make HTTP request for image";
    $req->header( Referer => "livejournal.com" );
    my $res = $ua->request($req);

    return $res;
}

# given an image URL, prefetches that image and returns a reference to it
sub prefetch_image {
    my $class = shift;
    my $img_url = shift;
    my %opts = @_;

    my $res = $class->prefetch_image_response($img_url, %opts);

    return undef unless $res->is_success;
    return \$res->content;
}

1;
