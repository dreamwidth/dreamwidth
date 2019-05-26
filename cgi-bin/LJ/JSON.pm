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

package LJ::JSON;
use strict;

use base qw(Exporter);
@LJ::JSON::EXPORT = qw( from_json to_json );

=head1 NAME

LJ::JSON - Wrapper for JSON which handles text encoding

=head1 SYNOPSIS

  use LJ::JSON; # never use JSON! That could introduce subtle encoding issues

  my $is_yummy = 1;
  my $json_string = to_json( { a => "apple",
                        yummy  => LJ::JSON->to_boolean( $is_yummy ) # true/false
                        yummy2 => $is_yummy                         # 1/0
                                                                    # both can work in JS, but prefer true/false
                    } );
  my $object      = from_json( q!{ "a": "apple" }! );

=cut

my $wrap;

sub to_json ($@) {
    my (@args) = @_;
    return $wrap->encode(@args);
}

sub from_json ($@) {
    my ($dump) = @_;

    return unless $dump;
    return $wrap->decode($dump);
}

sub class {
    return ref $wrap;
}

sub true  { $wrap->true }
sub false { $wrap->false }

sub to_boolean {
    my ( $class, $what ) = @_;
    return $what ? $wrap->true : $wrap->false;
}

sub to_number {
    my ( $class, $what ) = @_;

    # not using int deliberately because we may be handling floats here
    return $what + 0;
}

foreach my $class (qw(LJ::JSON::XS LJ::JSON::JSONv2 LJ::JSON::JSONv1)) {
    if ( $class->can_load ) {
        $wrap = $class->new;
        last;
    }
}
die unless $wrap;

1;

package LJ::JSON::Wrapper;

use Encode qw();

sub traverse {
    my ( $class, $what, $sub ) = @_;

    my $type = ref $what;

    # simple scalar
    if ( $type eq '' ) {
        return $sub->($what);
    }

    # hashref
    if ( $type eq 'HASH' ) {
        my %ret;
        foreach my $k ( keys %$what ) {
            $ret{ $sub->($k) } = $class->traverse( $what->{$k}, $sub );
        }
        return \%ret;
    }

    # arrayref
    if ( $type eq 'ARRAY' ) {
        my @ret;
        foreach my $v (@$what) {
            push @ret, $class->traverse( $v, $sub );
        }
        return \@ret;
    }

    # unknown type; let the subclass decode it to a scalar
    # (base class function defaults to plain stringification)
    return $sub->( $class->decode_unknown_type($what) );
}

sub traverse_fix_encoding {
    my ( $class, $what ) = @_;

    return $class->traverse(
        $what,
        sub {
            my ($scalar) = @_;

            return $scalar unless Encode::is_utf8($scalar);

            # if the string does indeed contain wide characters (which happens
            # in case the source string literals contained chars specified as
            # '\u041c'), encode stuff as utf8
            if ( $scalar =~ /[^\x01-\xff]/ ) {
                return Encode::encode( "utf8", $scalar );
            }

            return Encode::encode( "iso-8859-1", $scalar );
        }
    );
}

sub decode_unknown_type {
    my ( $class, $what ) = @_;

    return "$what";
}

package LJ::JSON::XS;

our @ISA;
BEGIN { @ISA = qw(LJ::JSON::Wrapper JSON::XS); }

sub can_load {
    eval { require JSON::XS; JSON::XS->import; };
    return !$@;
}

sub new {
    my ($class) = @_;
    return $class->SUPER::new->latin1;
}

sub decode {
    my ( $class, $dump ) = @_;

    my $decoded = $class->SUPER::decode($dump);
    $decoded = $class->traverse_fix_encoding($decoded);
    return $decoded;
}

sub decode_unknown_type {
    my ( $class, $what ) = @_;

    # booleans get converted to undef for false and 1 for true
    return $what ? 1 : undef if JSON::XS::is_bool($what);

    # otherwise, stringify
    return "$what";
}

1;

package LJ::JSON::JSONv2;

our @ISA;
BEGIN { @ISA = qw(LJ::JSON::Wrapper JSON); }

sub can_load {
    eval { require JSON };
    return !$@ && $JSON::VERSION ge 2;
}

sub new {
    my ($class) = @_;
    return $class->SUPER::new->latin1;
}

sub decode {
    my ( $class, $dump ) = @_;

    my $decoded = $class->SUPER::decode($dump);
    $decoded = $class->traverse_fix_encoding($decoded);
    return $decoded;
}

sub decode_unknown_type {
    my ( $class, $what ) = @_;

    # booleans get converted to undef for false and 1 for true
    return $what ? 1 : undef if JSON::is_bool($what);

    # otherwise, stringify
    return "$what";
}

1;

package LJ::JSON::JSONv1;

our @ISA;
BEGIN { @ISA = qw(LJ::JSON::Wrapper JSON); }

sub can_load {
    eval { require JSON };
    return !$@ && $JSON::VERSION ge 1;
}

*encode = \&JSON::objToJson;
*decode = \&JSON::jsonToObj;

1;
