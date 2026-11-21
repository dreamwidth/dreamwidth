#!/usr/bin/perl
#
# t/browser/fixtures/reading-details.pl
#
# Create a reader, a subscription, and an entry with Details and cut tags for
# the reading page browser test. Only operate on accounts with a fixture name.
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

use File::Temp qw(tempdir);
use JSON qw(encode_json);
use LJ::Customize;
use LJ::S2;
use LJ::S2Theme;
use LJ::Test ();

my $prefix = 'tbdetails_';
my $email  = 'reading-details@example.invalid';
local @LJ::INITIAL_SUBSCRIPTIONS = ();
local $LJ::TASK_QUEUE_BACKEND    = 'localdisk';
local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

if (@ARGV) {
    my ( $action, $name, $value ) = @ARGV;
    die 'Not a Details fixture username'
        unless defined $name && $name =~ /\A\Q$prefix\E[a-z0-9]{6}\z/;
    my $u = LJ::load_user($name);
    die 'Not a Details fixture account' if $u && $u->email_raw ne $email;

    if ( $action eq '--delete' ) {
        cleanup($u) if $u;
    }
    elsif ( $action eq '--preference' && $u && defined $value && $value =~ /\A[01]\z/ ) {
        $u->set_prop( 'opt_cut_disable_reading', $value );
    }
    elsif ( $action eq '--theme' && $u && defined $value && $value =~ /\A(?:aulait|abyss)\z/ ) {
        apply_theme( $u, $value );
    }
    else {
        die 'Unknown Details fixture command';
    }
    exit;
}

my $password = LJ::rand_chars(16);
my $reader   = fixture_account('Reading demo');
my $writer;
eval {
    $writer = fixture_account('Field notes');
    apply_theme( $reader, 'aulait' );
    $reader->set_prop( 'opt_cut_disable_reading', 0 );
    $reader->set_prop( 'opt_cut_disable_journal', 0 );
    $reader->add_edge( $writer, watch => { nonotify => 1 } ) or die 'Could not subscribe';

    $writer->t_post_fake_entry(
        subject => 'A walk by the river',
        body    => join( '',
            '<p>A few notes from a quiet walk at the end of the day.</p>',
            '<details><summary>Field notes</summary>',
            '<p>Three herons stood along the far bank.</p>',
            '<details><summary>One more observation</summary>',
            '<p>The last heron flew off just before sunset.</p></details></details>',
            '<cut text="A detour"><details><summary>Detour notes</summary>',
            '<p>The trail ended at an old stone footbridge.</p></details></cut>',
        ),
    );

    print encode_json( { user => $reader->user, poster => $writer->user, password => $password } ),
        "\n";
    1;
} or do {
    my $error = $@;
    cleanup($reader);
    cleanup($writer) if $writer;
    die $error;
};

sub fixture_account {
    my ($name) = @_;
    my $username = $prefix . lc LJ::rand_chars(6);
    die 'Details fixture username is already in use' if LJ::load_user($username);
    my $u = LJ::User->create_personal(
        user     => $username,
        email    => $email,
        password => $password,
        name     => $name,
    ) or die 'Could not create Details fixture account';
    $u->update_self( { status => 'A', statusvis => 'V' } );
    return $u;
}

sub apply_theme {
    my ( $u, $name ) = @_;
    my $theme = LJ::S2Theme->load_by_uniq("abstractia/$name");
    LJ::Customize->apply_theme( $u, $theme );
}

sub cleanup {
    my ($u) = @_;
    for my $entry ( $u->recent_entries ) {
        LJ::delete_entry( $u, $entry->jitemid, 0, $entry->anum );
    }
    LJ::S2::delete_user_style( $u, $_ ) for keys %{ LJ::S2::load_user_styles($u) };
    $u->delete_and_purge_completely;
}
