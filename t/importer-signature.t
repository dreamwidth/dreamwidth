# t/importer-signature.t
#
# Tests verification of the detached Ed25519 signatures on uploaded exports.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

use Crypt::PK::Ed25519;
use Log::Log4perl qw( :levels );
use MIME::Base64 qw( encode_base64 );

use lib "$ENV{LJHOME}/cgi-bin";
use DW::Importer::Signature;

Log::Log4perl->easy_init($OFF);

my $sig = 'DW::Importer::Signature';

# a source's signing key pair
sub new_key {
    my $sk = Crypt::PK::Ed25519->new;
    $sk->generate_key;
    return $sk;
}

sub raw_public { return encode_base64( $_[0]->export_key_raw('public'), '' ) }
sub pem_public { return $_[0]->export_key_pem('public') }

sub b64 { return encode_base64( $_[0], '' ) }

sub url_safe {
    my $text = b64( $_[0] );
    $text =~ tr{+/}{-_};
    $text =~ s/=+$//;
    return $text;
}

sub check {
    my (%args) = @_;
    my $err;
    my $ok = $sig->verify( source => 'pillowfort', error => \$err, %args );
    return wantarray ? ( $ok, $err ) : $ok;
}

# the export is JSON; it is signed as the bytes it is, so these include a newline and UTF-8
my $export = qq({"posts":[{"title":"caf\xc3\xa9","body":"hello"}],\n"version":1}\n);

my $key       = new_key();
my $signature = $key->sign_message($export);

local %LJ::IMPORTER_SIGNING_KEYS = ( pillowfort => [ raw_public($key) ] );

# a valid signature verifies
{
    ok( check( data => $export, signature => b64($signature) ), 'a valid signature verifies' );
    ok(
        check( data => \$export, signature => b64($signature) ),
        'also when the data is passed by reference'
    );
}

# any change to the data breaks it
{
    foreach my $offset ( 0, length($export) >> 1, length($export) - 1 ) {
        my $altered = $export;
        substr( $altered, $offset, 1 ) = chr( ord( substr( $altered, $offset, 1 ) ) ^ 1 );
        my ( $ok, $err ) = check( data => $altered, signature => b64($signature) );
        ok( !$ok, "a byte flipped at offset $offset fails" );
        like( $err, qr/does not match/, 'and says the signature did not match' );
    }
    ok( !check( data => $export . "\n", signature => b64($signature) ), 'an added byte fails' );
    ok( !check( data => substr( $export, 0, -1 ), signature => b64($signature) ),
        'a missing byte fails' );
    ok( !check( data => '', signature => b64($signature) ), 'empty data fails' );
}

# a signature from another key does not verify
{
    my $other = new_key();
    ok( !check( data => $export, signature => b64( $other->sign_message($export) ) ),
        'a signature from a key we do not trust fails' );
}

# keys may be listed as raw base64 or PEM, and a second key allows rotation
{
    local %LJ::IMPORTER_SIGNING_KEYS = ( pillowfort => [ pem_public($key) ] );
    ok( check( data => $export, signature => b64($signature) ), 'a PEM public key works' );

    my $old = new_key();
    my $new = new_key();
    local %LJ::IMPORTER_SIGNING_KEYS = ( pillowfort => [ raw_public($old), pem_public($new) ] );
    ok( check( data => $export, signature => b64( $old->sign_message($export) ) ),
        'the first key verifies' );
    ok( check( data => $export, signature => b64( $new->sign_message($export) ) ),
        'and so does the second' );
    ok( !check( data => $export, signature => b64( $key->sign_message($export) ) ),
        'a key that was removed does not' );
}

# the signature may be base64 in either alphabet, with or without padding, and with whitespace
{
    # find a signature whose base64 uses the characters that differ between alphabets
    my ( $special, $special_sig );
    foreach my $n ( 1 .. 500 ) {
        my $data = "attempt $n";
        my $s    = $key->sign_message($data);
        if ( b64($s) =~ m{[+/]} ) {
            ( $special, $special_sig ) = ( $data, $s );
            last;
        }
    }
    ok( $special_sig, 'found a signature with + or / in it' );

    ok( check( data => $special, signature => b64($special_sig) ), 'standard base64 works' );
    ok( check( data => $special, signature => url_safe($special_sig) ),
        'URL-safe base64 without padding works' );
    ( my $wrapped = b64($special_sig) ) =~ s/(.{20})/$1\n/g;
    ok(
        check( data => $special, signature => "  $wrapped\r\n" ),
        'line breaks and surrounding whitespace are ignored'
    );
    ok( check( data => $special, signature => join( ' ', split //, b64($special_sig) ) ),
        'so is whitespace anywhere' );
}

# malformed input fails without dying
{
    my @bad = (
        [ 'not base64',             '!!!not base64!!!' ],
        [ 'an empty signature',     '' ],
        [ 'an undefined signature', undef ],
        [ 'a short signature',      b64('too short') ],
        [ 'a long signature',       b64( $signature . 'x' ) ],
        [ 'a truncated signature', substr( b64($signature), 0, 40 ) ],
        [ 'a signature of zeros',  b64( "\0" x 64 ) ],
    );
    foreach my $case (@bad) {
        my ( $name, $text ) = @$case;
        my ( $ok, $err );
        ok( eval { ( $ok, $err ) = check( data => $export, signature => $text ); 1 },
            "$name does not die" );
        ok( !$ok, "$name fails" );
        ok( $err, "$name says why" );
    }

    ok( !check( signature => b64($signature) ), 'no data fails' );
    ok( !check( data => "caf\x{e9} \x{263a}", signature => b64($signature) ),
        'wide characters fail' );
    ok( !$sig->verify( data => $export, signature => b64($signature) ), 'no source fails' );
    ok( !$sig->verify(), 'no arguments fail' );
    ok( !$sig->verify( source => 'pillowfort', data => [], signature => {} ),
        'references where text belongs fail' );
}

# unusable keys are skipped, and never make a bad signature pass
{
    my $good = new_key();
    local %LJ::IMPORTER_SIGNING_KEYS = (
        pillowfort => [
            'garbage', '!!!', b64('short'),
            "-----BEGIN PUBLIC KEY-----\nnonsense\n-----END PUBLIC KEY-----\n",
            undef, [], $good->export_key_pem('private'),
            raw_public($good),
        ],
    );
    ok( check( data => $export, signature => b64( $good->sign_message($export) ) ),
        'a usable key still works among unusable ones' );
    ok( !check( data => $export, signature => b64( $key->sign_message($export) ) ),
        'and unusable keys do not let other signatures through' );

    local %LJ::IMPORTER_SIGNING_KEYS = ( pillowfort => [ $good->export_key_pem('private') ] );
    my ( $ok, $err ) = check( data => $export, signature => b64( $good->sign_message($export) ) );
    ok( !$ok, 'a private key in the configuration is not accepted' );
    like( $err, qr/no usable signing keys/, 'it is as if there were no key' );
}

# with no keys, nothing verifies
{
    my $signed = b64($signature);

    foreach my $case (
        [ 'an empty key list',             { pillowfort => [] } ],
        [ 'no entry for the source',       { other      => [ raw_public($key) ] } ],
        [ 'a key list that is not a list', { pillowfort => raw_public($key) } ],
        [ 'no configuration',              {} ],
        )
    {
        my ( $name, $config ) = @$case;
        local %LJ::IMPORTER_SIGNING_KEYS = %$config;
        my ( $ok, $err ) = check( data => $export, signature => $signed );
        ok( !$ok, "$name: fails closed" );
        like( $err, qr/no usable signing keys/, "$name: says why" );
    }

    # keys are per source
    local %LJ::IMPORTER_SIGNING_KEYS = ( other => [ raw_public($key) ] );
    ok( !check( data => $export, signature => $signed ), "another source's key does not apply" );
    ok( $sig->verify( source => 'other', data => $export, signature => $signed ),
        'but it does for that source' );
}

done_testing();
