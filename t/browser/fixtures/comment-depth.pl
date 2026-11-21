# t/browser/fixtures/comment-depth.pl
#
# Create and remove a journal with a partially collapsed comment tree.
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

my $prefix = 'tbrowser_depth_';
my $email  = 'comment-depth@example.invalid';
local $LJ::TASK_QUEUE_BACKEND    = 'localdisk';
local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

sub cleanup {
    my ($user) = @_;
    die 'Not a comment depth fixture' unless $user->email_raw eq $email;
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

my $theme =
    LJ::S2Theme->load_by_uniq( $ENV{DW_COMMENT_DEPTH_THEME} || 'practicality/ableconstructs' )
    or die 'Missing Practicality theme';
my $username = $prefix . lc LJ::rand_chars(6);
die 'Fixture username already exists' if LJ::load_user($username);
local @LJ::INITIAL_SUBSCRIPTIONS = ();
my $user = LJ::User->create_personal(
    user     => $username,
    email    => $email,
    password => LJ::rand_chars(24),
    name     => 'Comment depth demo',
) or die 'Could not create fixture user';

eval {
    $user->update_self( { status => 'A', statusvis => 'V', opt_gettalkemail => 'X' } );
    $user->add_to_class('paid_user') or die 'Could not enable thread expansion';

    my $style = LJ::S2::create_style( $user, 'Comment depth demo' ) or die 'Could not create style';
    $user->set_prop( s2_style                    => $style );
    $user->set_prop( stylesys                    => 2 );
    $user->set_prop( use_journalstyle_entry_page => 'Y' );

    my $layout = $theme->layoutid;
    my $layer  = LJ::S2::create_layer( $user, $layout, 'user' ) or die 'Could not create layer';
    LJ::S2::set_style_layers(
        $user, $style,
        core   => $theme->coreid,
        layout => $layout,
        theme  => $theme->themeid,
        user   => $layer
    ) or die 'Could not set style layers';
    my $source = <<'S2';
layerinfo type = "user";
layerinfo name = "Comment depth demo";
set comment_indent_style = "responsive";
set comment_indent_limit_mobile = 1;
S2
    my $error;
    LJ::S2::layer_compile( $layer, \$error, { s2ref => \$source } ) or die $error;

    my $entry = $user->t_post_fake_entry(
        subject => 'Comment thread depth',
        body    => 'Expand a nested reply to see its depth in the thread.',
    );
    my $root =
        $entry->t_enter_comment( subject => 'Start of the thread', body => 'First comment.' );
    my $middle = $root->t_reply( subject => 'Nested thread', body => 'Replies begin here.' );
    my @replies =
        map { $middle->t_reply( subject => "Nested reply $_", body => "This is nested reply $_." ) }
        1 .. 50;
    my $target = $replies[25];
    my $child =
        $target->t_reply( subject => 'One level deeper', body => 'This reply expands too.' );

    print encode_json(
        {
            user   => $user->user,
            path   => '/users/' . $user->user . '/' . $entry->ditemid . '.html',
            middle => $middle->dtalkid,
            target => $target->dtalkid,
            child  => $child->dtalkid,
        }
        ),
        "\n";
    1;
} or do {
    my $error = $@;
    cleanup($user);
    die $error;
};
