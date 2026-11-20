#!/usr/bin/perl
#
# t/browser/fixtures/customize-community.pl
#
# Disposable accounts and a private S2 theme for the community customize test.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Carp qw(croak);
use JSON qw(encode_json);
use LJ::S2 ();

my $prefix = 'tbrowser_';

sub remove_account {
    my ($account) = @_;
    LJ::S2::delete_layer( $_, $account ) for keys %{ LJ::S2::get_layers_of_user($account) };
    LJ::S2::delete_user_style( $account, $_ ) for keys %{ LJ::S2::load_user_styles($account) };
    $account->kill_all_sessions;
    $account->delete_and_purge_completely;
}

if ( @ARGV == 2 && $ARGV[0] =~ /\A--(?:delete|state)\z/ ) {
    my ( $action, $name ) = @ARGV;
    croak 'not a fixture account' unless $name =~ /\A${prefix}c[0-9a-z]{5}\z/;
    my $account = LJ::load_user($name) or exit 0;
    if ( $action eq '--delete' ) {
        remove_account($account);
    }
    else {
        my $style_id = $account->prop('s2_style');
        my $layers   = $style_id ? LJ::S2::get_style_layers( $account, $style_id ) : {};
        print encode_json(
            {
                title  => $account->prop('journaltitle'),
                style  => $style_id,
                theme  => $layers->{theme},
                styles => LJ::S2::load_user_styles($account),
            }
        );
    }
    exit 0;
}

my $layout = LJ::S2::get_public_layers()->{'abstractia/layout'}->{s2lid}
    or croak 'install the public S2 layers before running this test';
my $password = LJ::rand_chars(16);
my ( $admin, $community );
my $created;

END {
    unless ($created) {
        remove_account($_) for grep { defined $_ } ( $community, $admin );
    }
}

until ($admin) {
    $admin = LJ::User->create_personal(
        user     => $prefix . 'c' . lc LJ::rand_chars(5),
        email    => 'browser-test@example.com',
        password => $password,
        name     => 'Style Test Maintainer',
    );
}
$admin->update_self( { status => 'A', statusvis => 'V' } );
$admin->set_prop( journaltitle => 'Maintainer Journal' );
until ($community) {
    $community = LJ::User->create_community(
        user         => $prefix . 'c' . lc LJ::rand_chars(5),
        name         => 'Style Test Community',
        admin_userid => $admin->id,
        membership   => 'open',
        postlevel    => 'members',
    );
}
$community->update_self( { caps => 8 } );
$community->set_prop( journaltitle => 'Community Journal' );
croak 'fixture needs a community that can use custom layers'
    unless $community->can_create_s2_styles;
my $theme  = LJ::S2::create_layer( $community, $layout, 'theme' ) or croak 'create theme';
my $source = <<'S2';
layerinfo "type" = "theme";
layerinfo "name" = "Community Custom Theme";
set color_page_background = "#ddeeff";
S2
my $error;
LJ::S2::layer_compile( $theme, \$error, { s2ref => \$source } ) or croak $error;

$created = 1;
print encode_json(
    {
        user      => $admin->user,
        password  => $password,
        community => $community->user,
        theme     => $theme,
    }
);
