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
use LJ::Config;
use LJ::Subscription;
use Plack::Runner;

sub delete_fixture {
    my ($user) = @_;
    $_->delete for DW::Media->get_active_for_user($user);
    $user->kill_all_sessions;
    LJ::Subscription->delete_all_subs($user);
    $user->delete_and_purge_completely;
}

if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    croak 'not a media embed fixture' unless $ARGV[1] =~ /^tbrowser_[a-zA-Z0-9]{6}$/;
    my $user = LJ::load_user( $ARGV[1] ) or exit 0;
    croak 'not a media embed fixture' unless $user->name_orig eq 'Media embed browser test';
    delete_fixture($user);
    exit 0;
}

if ( @ARGV == 2 && $ARGV[0] eq '--serve' ) {
    my $port = $ARGV[1];
    croak 'expected a nonprivileged port' unless $port =~ /^\d+$/ && $port > 1023 && $port < 65536;
    my ( $config, $filename ) = tempfile( UNLINK => 1 );
    print {$config} <<'CONFIG';
$LJ::DOMAIN          = 'dw-embed.test';
$LJ::USER_DOMAIN     = $LJ::DOMAIN;
$LJ::DOMAIN_WEB      = "www.$LJ::DOMAIN";
$LJ::SITEROOT        = "http://$LJ::DOMAIN_WEB";
$LJ::COOKIE_DOMAIN   = ".$LJ::DOMAIN";
$LJ::SUBDOMAIN_RULES = { %{$LJ::SUBDOMAIN_RULES}, P => [ 1, '' ] };
1;
CONFIG
    close $config or die $!;
    push @LJ::CONFIG_FILES, $filename;
    LJ::Config->reload;
    my $runner = Plack::Runner->new;
    $runner->parse_options( '--server', 'Starman', '--listen', "127.0.0.1:$port",
        '--workers', 2, '--no-default-middleware', "$ENV{LJHOME}/app.psgi" );
    $runner->run;
    exit 0;
}
my $large_only = @ARGV == 1 && $ARGV[0] eq '--large-only';
croak 'unexpected arguments' if @ARGV && !$large_only;

sub upload_image {
    my ( $user, $size, $title ) = @_;
    my ( $file, $filename ) = tempfile( SUFFIX => '.png', UNLINK => 1 );
    close $file or die $!;
    my $image = Image::Magick->new( size => $size );
    my $error = $image->Read('gradient:#235789-#f1d18a') || $image->Write($filename);
    die $error if $error;

    my $media = DW::Media->upload_media( user => $user, file => $filename, security => 'public' )
        or die 'Could not upload fixture image';
    $media->prop( title   => $title );
    $media->prop( alttext => "$size gradient: blue & gold" );
    return $media->displayid;
}

my $password = LJ::rand_chars(16);
my $user     = LJ::User->create_personal(
    user     => 'tbrowser_' . LJ::rand_chars(6),
    email    => 'media-embed-test@example.invalid',
    password => $password,
    name     => 'Media embed browser test',
    bdate    => '2000-01-01',
) or die 'Could not create fixture user';
my $fixture = eval {
    $user->update_self( { status => 'A', statusvis => 'V' } );
    my %fixture = (
        user     => $user->user,
        password => $password,
        large    => upload_image( $user, '1440x900', 'Color study' ),
    );
    $fixture{small} = upload_image( $user, '240x180', 'Small color study' ) unless $large_only;
    encode_json( \%fixture );
};
if ( my $error = $@ ) {
    eval { delete_fixture($user) };
    warn "Could not clean up fixture user: $@" if $@;
    die $error;
}
print "$fixture\n";
