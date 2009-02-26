#!/usr/bin/perl
#
# DW::Worker::ContentImporter::Local::Userpics
#
# Local data utilities to handle importing of userpics into the local site.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::Local::Userpics;
use strict;

use Carp qw/ croak /;

=head1 NAME

DW::Worker::ContentImporter::Local::Userpics - Local data utilities for userpics

=head1 Userpics

These functions are all part of the Saving API and handle saving data to
the local site.  These are not to be called outside of the import pipeline.

=head2 C<< $class->import_userpics( $user, $errors, $default, $userpics ) >>

Import the following userpics, default first, but only import the other
ones if they *all* fit.  This will return an array of userpic IDs that were
imported.

$errors is an arrayref that errors will be appended to.

=cut

sub import_userpics {
    my ( $class, $u, $errors, $default, $upics ) = @_;
    $u = LJ::want_user( $u )
        or croak 'invalid user object';
    $errors ||= [];

    my $count = $u->get_userpic_count;
    my $max = $u->userpic_quota;
    my $left = $max - $count;

    my ( @imported, %skip_ids );

    warn "Content importer: import_userpics: $u->{user}($u->{userid}) has=$count, max=$max, importing=" . scalar(@$upics) . "\n";

    # but do nothing if we have no room...
    return () if $left <= 0;

    # import helper
    my $import_userpic = sub {
        my $pic = shift;
        warn "Attempting to import $pic->{src}\n";

        return if $skip_ids{$pic->{id}};

        if ( my $ret = $class->import_userpic( $u, $errors, $pic ) ) {
            $left--
                if $ret == 1; # 1 == success, new picture created
            push @imported, $pic->{id};
        }

        $skip_ids{$pic->{id}} = 1;
    };

    # attempt to import the default userpic first, if they have at least one
    # slot available
    $import_userpic->( $default );

    # now bail out if we don't have room for everything
    return @imported
        unless $left >= scalar( @{ $upics || [] } );

    # now import the list, or try
    $import_userpic->( $_ )
        foreach @{ $upics || [] };

    return @imported;
}

=head2 C<< $class->import_userpic( $user, $errors, $userpic ) >>

$userpic is a hashref representation of a single icon, with the following format:

  {
    url => 'http://some.tld/some.jpg', # URL to image
    default => 0,                      # Is this the default image?
    keywords => [
        'keyword',
        'another keyword',
    ],
    comment => 'This is my icon!',     # The comment for the icon
  }

$errors is an arrayref that errors will be appended to.

This will return 0 if it failed, 1 if it suceeded, and 2 if it was an existing pic.

=cut

sub import_userpic {
    my ( $class, $u, $errors, $upic ) = @_;
    $u = LJ::want_user( $u )
        or croak 'invalid user object';

    my $ua = LJ::get_useragent(
        role     => 'userpic',
        max_size => LJ::Userpic->max_allowed_bytes( $u ) + 1024,
        timeout  => 20,
    ) or croak 'unable to create useragent';

    my $identifier = $upic->{keywords}->[0] || $upic->{id};

    my $resp = $ua->get( $upic->{src} );
    unless ( $resp && $resp->is_success ) {
        push @$errors, "Icon '$identifier': unable to download from server.";
        return 0;
    }

    my $ret = 2;
    my $data = $resp->content;
    my $userpic = LJ::Userpic->new_from_md5( $u, Digest::MD5::md5_base64( $data ) );

    # if we didn't get one, this is a brand new userpic, that we created
    unless ( $userpic ) {
        $ret = 1;

        my $count = $u->get_userpic_count;
        my $max = $u->userpic_quota;

        if ( $count >= $max ) {
            push @$errors, "Icon '$identifier': You are at your limit of $max " . ($max == 1 ? "userpic" : "userpics") .
                           ". You cannot upload any more userpics right now.";
            return 0;

        } else {
            $userpic = eval { LJ::Userpic->create( $u, data => \$data ); };
            unless ( $userpic ) {
                push @$errors, "Icon '$identifier': " . $@->as_string;
                return 0;
            }
        }
    }

    my @keywords = $userpic->keywords( raw => 1 );
    $userpic->make_default if $upic->{default};
    $userpic->set_keywords( @keywords, @{$upic->{keywords}} );
    $userpic->set_comment( $upic->{comment} ) if $upic->{comment};

    return $ret;
}


1;
