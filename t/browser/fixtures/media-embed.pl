#!/usr/bin/perl
# t/browser/fixtures/media-embed.pl
#
# Create a synthetic upload for the image embed browser test.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Carp qw(croak);
use DW::Media;
use File::Temp qw(tempfile);
use Image::Magick;
use JSON;
use LJ::Subscription;

if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    croak 'not a media embed fixture' unless $ARGV[1] =~ /^tbrowser_[a-zA-Z0-9]{6}$/;
    my $user = LJ::load_user( $ARGV[1] ) or exit 0;
    croak 'not a media embed fixture' unless $user->name_orig eq 'Media embed browser test';
    $_->delete for DW::Media->get_active_for_user($user);
    $user->kill_all_sessions;
    LJ::Subscription->delete_all_subs($user);
    $user->delete_and_purge_completely;
    exit 0;
}
croak 'unexpected arguments' if @ARGV;

my ( $file, $filename ) = tempfile( SUFFIX => '.png', UNLINK => 1 );
close $file or die $!;
my $image = Image::Magick->new( size => '1440x900' );
my $error = $image->Read('gradient:#235789-#f1d18a') || $image->Write($filename);
die $error if $error;

my $password = LJ::rand_chars(16);
my $user     = LJ::User->create_personal(
    user     => 'tbrowser_' . LJ::rand_chars(6),
    email    => 'media-embed-test@example.invalid',
    password => $password,
    name     => 'Media embed browser test',
    bdate    => '2000-01-01',
) or die 'Could not create fixture user';
$user->update_self( { status => 'A', statusvis => 'V' } );

my $media = DW::Media->upload_media( user => $user, file => $filename, security => 'public' )
    or die 'Could not upload fixture image';
$media->prop( title   => 'Color study' );
$media->prop( alttext => q{1440x900 gradient: blue & gold} );

print encode_json( { user => $user->user, password => $password } ) . "\n";
