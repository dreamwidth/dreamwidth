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

package LJ;

use strict;
no warnings 'uninitialized';

use Digest::MD5;
use Math::Random::Secure qw(irand);

my %RAND_CHARSETS = (
    default     => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    urlsafe_b64 => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
);

sub rand_chars {
    my ( $length, $charset ) = @_;
    my $chal      = "";
    my $digits    = $RAND_CHARSETS{ $charset || 'default' };
    my $digit_len = length($digits);
    die "Invalid charset $charset" unless $digits && ( $digit_len > 0 );

    for ( 1 .. $length ) {
        $chal .= substr( $digits, irand($digit_len), 1 );
    }
    return $chal;
}

sub md5_struct {
    my ( $st, $md5 ) = @_;
    $md5 ||= Digest::MD5->new;
    unless ( ref $st ) {

        # later Digest::MD5s die while trying to
        # get at the bytes of an invalid utf-8 string.
        # this really shouldn't come up, but when it
        # does, we clear the utf8 flag on the string and retry.
        # see http://zilla.livejournal.org/show_bug.cgi?id=851
        eval { $md5->add($st); };
        if ($@) {
            $st = LJ::no_utf8_flag($st);
            $md5->add($st);
        }
        return $md5;
    }
    if ( ref $st eq "HASH" ) {
        foreach ( sort keys %$st ) {
            md5_struct( $_,        $md5 );
            md5_struct( $st->{$_}, $md5 );
        }
        return $md5;
    }
    if ( ref $st eq "ARRAY" ) {
        foreach (@$st) {
            md5_struct( $_, $md5 );
        }
        return $md5;
    }
}

sub urandom {
    my %args   = @_;
    my $length = $args{size} or die 'Must Specify size';

    my $result;
    open my $fh, '<', '/dev/urandom' or die "Cannot open random: $!";
    while ($length) {
        my $chars;
        $fh->read( $chars, $length ) or die "Cannot read /dev/urandom: $!";
        $length -= length($chars);
        $result .= $chars;
    }
    $fh->close;

    return $result;
}

sub urandom_int {
    my %args = @_;

    return unpack( 'N', LJ::urandom( size => 4 ) );
}

