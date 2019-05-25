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

package LJ::LangDatFile;
use strict;
use warnings;
use Carp qw (croak);

sub new {
    my ( $class, $filename ) = @_;

    my $self = {

        # initialize
        filename => $filename,
        values   => {},          # string -> value mapping
        meta     => {},          # string -> {metakey => metaval}
    };

    bless $self, $class;
    $self->parse;

    return $self;
}

sub parse {
    my $self     = shift;
    my $filename = $self->filename;

    open my $datfile, $filename
        or croak "Could not open file $filename: $!";

    my $lnum = 0;
    my ( $code, $text );
    while ( my $line = <$datfile> ) {
        $lnum++;
        my $del;
        my $action_line;

        if ( $line =~ /^[\#\;]/ ) {

            # comment line
            next;
        }
        elsif ( $line =~ /^(\S+?)=(.*)/ ) {
            ( $code, $text ) = ( $1, $2 );
            $action_line = 1;
        }
        elsif ( $line =~ /^\!\s*(\S+)/ ) {
            $del         = $code;
            $action_line = 1;
        }
        elsif ( $line =~ /^(\S+?)\<\<\s*$/ ) {
            ( $code, $text ) = ( $1, "" );
            while ( my $ln = <$datfile> ) {
                $lnum++;
                last if $ln eq ".\n";
                $ln =~ s/^\.//;
                $text .= $ln;
            }
            chomp $text;    # remove file new-line (we added it)
            $action_line = 1;
        }
        elsif ( $line =~ /\S/ ) {
            croak "$filename:$lnum: Bogus format.";
        }

        if ( $code && $code =~ s/\|(.+)// ) {
            $self->{meta}->{$code} ||= {};
            $self->{meta}->{$code}->{$1} = $text;
            $action_line = 1;
        }
        next unless $action_line;
        $self->{values}->{ lc($code) } = $text;
    }

    close $datfile;
}

sub filename { $_[0]->{filename} }

sub meta {
    my ( $self, $code ) = @_;
    return %{ $self->{meta}->{$code} || {} };
}

sub value {
    my ( $self, $key ) = @_;

    return undef unless $key;
    return $self->{values}->{ lc($key) };
}

sub foreach_key {
    my ( $self, $callback ) = @_;

    foreach my $k ( $self->keys ) {
        $callback->($k);
    }
}

sub keys {
    my $self = shift;
    my @keys = CORE::keys( %{ $self->{values} } );
    return sort @keys;
}

sub values {
    my $self = shift;
    return CORE::values( %{ $self->{values} } );
}

# set a key/value pair
sub set {
    my ( $self, $k, $v ) = @_;

    return 0 unless $k;
    $v ||= '';

    $self->{values}->{ lc($k) } = $v;
    return 1;
}

# save to file
sub save {
    my $self = shift;

    my $filename = $self->filename;

    open my $save, ">$filename"
        or croak "Could not open file $filename for writing: $!";

    # prefix file with utf-8 marker for emacs
    print $save ";; -*- coding: utf-8 -*-\n\n";

    # write out strings to file
    $self->foreach_key(
        sub {
            my $key = shift;
            return unless $key;    # just to make sure

            my $val = $self->value($key) || '';

            # is there metadata?
            my $meta = $self->{meta}->{$key};
            if ($meta) {
                while ( my ( $metakey, $metaval ) = each %$meta ) {
                    print $save "$key|$metakey=$metaval\n";
                }
            }

            # is it multiline?
            if ( $val =~ /\n/ ) {
                print $save "$key<<\n$val\n.\n\n";
            }
            else {
                # normal key-value pair
                print $save "$key=$val\n\n";
            }
        }
    );

    close $save;

    return 1;
}

1;
