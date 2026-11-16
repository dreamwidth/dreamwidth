#!/usr/bin/perl
#
# DW::Importer::Signature
#
# Verifies the signature on an export file a user uploads to be imported.
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

package DW::Importer::Signature;

=head1 NAME

DW::Importer::Signature - Ed25519 signature verification for uploaded exports

=head1 SYNOPSIS

    my $error;
    if ( DW::Importer::Signature->verify(
        source    => 'pillowfort',
        data      => $uploaded_bytes,
        signature => $signature_text,
        error     => \$error,
    ) ) {
        # the file is what the source signed
    }
    else {
        warn "not accepting the upload: $error";
    }

=head1 DESCRIPTION

A source that exports to a file signs the exact bytes of that file with an Ed25519
key, so that we know the export came from the source and wasn't edited on the way.
The signature is detached (it is sent next to the file, not inside it) and covers the
raw bytes as uploaded, with no canonicalization: re-serializing the JSON, changing
line endings or trimming whitespace breaks it.

=head2 Configuring keys

The public keys we trust for each source are listed in C<%LJ::IMPORTER_SIGNING_KEYS>,
an arrayref per source, so that a new key can be added before the old one is removed
when the source rotates its keys:

    %LJ::IMPORTER_SIGNING_KEYS = (
        pillowfort => [ '<base64 of the 32-byte public key>', $next_key ],
    );

A key is either the 32 bytes of the public key as base64 (standard or URL-safe), or a
PEM C<PUBLIC KEY> block. A signature verifies if any of the source's keys verifies it.
Private keys are refused. A source with no usable key can't verify anything: this
fails closed.

=head2 Signatures

The signature is the 64 bytes Ed25519 produces, as base64 text, standard or URL-safe,
with or without padding, and with any whitespace (including line breaks) ignored.

=cut

use strict;
use warnings;

use Crypt::PK::Ed25519;
use Log::Log4perl;
use MIME::Base64 qw( decode_base64 );

my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head2 C<< DW::Importer::Signature->verify( %args ) >>

Arguments:

=over

=item source

Name of the source, used to find its keys.

=item data

The bytes that were signed, as a string or a reference to one.

=item signature

The detached signature, as base64 text.

=item error

Optional reference to a scalar that receives why verification failed.

=back

Returns true if the signature is valid for the data under one of the source's keys,
false otherwise. It never dies, whatever it is given; the reason for a failure is
logged and put in C<error>.

=cut

sub verify {
    my ( $class, %args ) = @_;

    my $result = eval { $class->_verify(%args) };
    unless ( defined $result ) {
        my $reason = $@ ? "internal error: $@" : 'internal error';
        $reason =~ s/\s+\z//;
        $result = _failed( $args{error}, $args{source}, $reason );
    }
    return $result;
}

sub _verify {
    my ( $class, %args ) = @_;
    my ( $source, $err ) = ( $args{source}, $args{error} );

    return _failed( $err, $source, 'no source given' )
        unless defined $source && length $source;
    return _failed( $err, $source, 'no data given' ) unless defined $args{data};
    return _failed( $err, $source, 'no signature given' )
        unless defined $args{signature} && length $args{signature};

    my $data = ref $args{data} eq 'SCALAR' ? ${ $args{data} } : $args{data};
    return _failed( $err, $source, 'data is not a string of bytes' ) if ref $data;
    return _failed( $err, $source, 'data is not bytes (it has wide characters)' )
        unless utf8::downgrade( my $bytes = $data, 1 );

    my $signature = _decode_base64( $args{signature} );
    return _failed( $err, $source, 'signature is not valid base64' ) unless defined $signature;
    return _failed( $err, $source, 'signature is ' . length($signature) . ' bytes, not 64' )
        unless length $signature == 64;

    my $configured = $LJ::IMPORTER_SIGNING_KEYS{$source};
    my @keys       = ref $configured eq 'ARRAY' ? @$configured : ();
    my @loaded     = grep { defined } map { _load_key( $_, $source ) } @keys;
    return _failed( $err, $source, 'no usable signing keys are configured' ) unless @loaded;

    foreach my $key (@loaded) {
        return 1 if eval { $key->verify_message( $signature, $bytes ) };
    }

    return _failed( $err, $source, 'signature does not match the data under any configured key' );
}

# records why a verification failed and returns false
sub _failed {
    my ( $err, $source, $reason ) = @_;

    $source //= '(none)';
    $log->warn("Signature verification for source '$source' failed: $reason");
    $$err = $reason if ref $err eq 'SCALAR';
    return 0;
}

# standard or URL-safe base64, padded or not, with whitespace ignored; undef if it isn't base64
sub _decode_base64 {
    my ($text) = @_;

    ( my $b64 = $text ) =~ s/\s+//g;
    return undef unless $b64 =~ m{\A[A-Za-z0-9+/_-]*={0,2}\z};

    $b64 =~ tr{-_}{+/};
    $b64 =~ s/=+\z//;
    return undef if length($b64) % 4 == 1;

    return decode_base64($b64);
}

# a configured key as a public key object, or undef (and a log line) if it can't be used
sub _load_key {
    my ( $text, $source ) = @_;

    my $key = eval {
        die "not a string\n" if !defined $text || ref $text;

        my $pk = Crypt::PK::Ed25519->new;
        if ( $text =~ /-----BEGIN/ ) {
            $pk = Crypt::PK::Ed25519->new( \$text );
        }
        else {
            my $raw = _decode_base64($text);
            die "not base64\n" unless defined $raw;
            die 'a raw key is 32 bytes, this is ' . length($raw) . "\n" unless length $raw == 32;
            $pk->import_key_raw( $raw, 'public' );
        }
        die "this is a private key, only public keys belong in the configuration\n"
            if $pk->is_private;
        $pk;
    };
    unless ($key) {
        ( my $why = $@ || 'unknown error' ) =~ s/\s+\z//;
        $log->warn("Ignoring unusable signing key for source '$source': $why");
        return undef;
    }
    return $key;
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
