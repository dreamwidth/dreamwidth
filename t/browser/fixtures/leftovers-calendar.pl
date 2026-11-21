# t/browser/fixtures/leftovers-calendar.pl
#
# Create and remove a Leftovers journal with a sidebar calendar.
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

use File::Temp qw(tempdir);
use JSON qw(encode_json);
use LJ::S2;
use LJ::S2Theme;
use LJ::Test ();

my $prefix = 'tbrowser_cal_';
my $email  = 'leftovers-calendar@example.invalid';
local $LJ::TASK_QUEUE_BACKEND    = 'localdisk';
local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

sub cleanup {
    my ($user) = @_;
    die 'Not a calendar fixture' unless $user->email_raw eq $email;
    for my $entry ( $user->recent_entries ) {
        LJ::delete_entry( $user, $entry->jitemid, 0, $entry->anum );
    }
    if ( my $style = $user->prop('s2_style') ) {
        my $layers = LJ::S2::get_style_layers( $user, $style );
        LJ::S2::delete_layer( $user, $layers->{user} ) if $layers->{user};
        LJ::S2::delete_user_style( $user, $style );
    }
    $user->delete_and_purge_completely;
}

if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    die 'Not a fixture username' unless $ARGV[1] =~ /\A\Q$prefix\E[a-z0-9]{6}\z/;
    my $user = LJ::load_user( $ARGV[1] ) or exit 0;
    cleanup($user);
    exit 0;
}

my ( $theme_name, $section, $sidebar_width ) = @ARGV;
die 'Expected a Leftovers theme, sidebar section, and width in em'
    unless $theme_name =~ /\A(?:fruitsalad|elegantbrown)\z/
    && $section =~ /\A(?:one|two)\z/
    && $sidebar_width =~ /\A[1-9][0-9]?\z/;
my $theme    = LJ::S2Theme->load_by_uniq("leftovers/$theme_name") or die 'Missing Leftovers theme';
my $username = $prefix . lc LJ::rand_chars(6);
die 'Fixture username already exists' if LJ::load_user($username);
local @LJ::INITIAL_SUBSCRIPTIONS = ();
my $user = LJ::User->create_personal(
    user     => $username,
    email    => $email,
    password => LJ::rand_chars(24),
    name     => 'Leftovers calendar demo',
) or die 'Could not create fixture user';

eval {
    $user->update_self( { status => 'A', statusvis => 'V' } );
    my $style = LJ::S2::create_style( $user, 'Leftovers calendar' ) or die 'Could not create style';
    $user->set_prop( s2_style     => $style );
    $user->set_prop( stylesys     => 2 );
    $user->set_prop( journaltitle => 'Leftovers calendar demo' );

    my $layout = $theme->layoutid;
    my $layer  = LJ::S2::create_layer( $user, $layout, 'user' ) or die 'Could not create layer';
    LJ::S2::set_style_layers(
        $user, $style,
        core   => $theme->coreid,
        layout => $layout,
        theme  => $theme->themeid,
        user   => $layer
    ) or die 'Could not set style layers';
    my $source = <<"S2";
layerinfo type = "user";
layerinfo name = "Leftovers calendar";
set layout_type = "three-columns-sides";
set module_calendar_section = "$section";
set sidebar_width = "${sidebar_width}em";
S2
    my $error;
    LJ::S2::layer_compile( $layer, \$error, { s2ref => \$source } ) or die $error;

    $user->t_post_fake_entry(
        subject => 'A walk in the park',
        body    => 'The leaves have turned, and there is a chill in the air.',
    );

    print encode_json( { user => $username, path => "/users/$username/" } ), "\n";
    1;
} or do {
    my $error = $@;
    cleanup($user);
    die $error;
};
