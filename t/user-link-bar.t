# t/user-link-bar.t
#
# Test guest navigation and authenticated action restrictions in user link bars.
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

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Logic::UserLinkBar;

{

    package Local::LinkBarAccount;
    sub new { my ( $class, %args ) = @_; return bless { visible => 1, %args }, $class; }
    sub user          { return 'linkbar_target'; }
    sub is_personal   { return $_[0]{type} eq 'P'; }
    sub is_community  { return $_[0]{type} eq 'C'; }
    sub is_syndicated { return $_[0]{type} eq 'Y'; }
    sub is_identity   { return $_[0]{type} eq 'I'; }
    sub is_visible    { return $_[0]{visible}; }
    sub equals        { return defined $_[1] && $_[0] == $_[1]; }
    sub watches       { return $_[0]{watches}; }
    sub can_post_to   { return $_[0]{can_post}; }
}

local $LJ::SITEROOT              = 'https://example.test';
local $LJ::IMGPREFIX             = 'https://example.test/img';
local $LJ::DISABLED{tellafriend} = 0;

subtest 'guests get links to the home page' => sub {
    for my $type (qw(P C Y I)) {
        my $bar = linkbar( Local::LinkBarAccount->new( type => $type ) );
        is( $bar->watch->{url}, "$LJ::SITEROOT/", "$type subscribe leads to home" );

        my $post = $bar->post;
        if ( $type eq 'C' ) {
            is( $post->{url}, "$LJ::SITEROOT/", 'community post leads to home' );
        }
        else {
            ok( !$post, "$type does not acquire a post-to-journal action" );
        }

        my $tell = $bar->tellafriend;
        if ( $type eq 'I' ) {
            ok( !$tell, 'identity account still has no Tell Someone action' );
        }
        else {
            is( $tell && $tell->{url}, "$LJ::SITEROOT/", "$type Tell Someone leads to home" );
        }
    }

    my $hidden = linkbar( Local::LinkBarAccount->new( type => 'P', visible => 0 ) );
    ok( !$hidden->watch->{url}, 'unavailable journal offers guests no subscribe link' );

    local $LJ::SITEROOT = '';
    my $bar = linkbar( Local::LinkBarAccount->new( type => 'C' ) );
    is( $bar->watch->{url}, '/', 'subscribe URL remains nonempty with request-relative roots' );
    is( $bar->post->{url},  '/', 'post URL remains nonempty with request-relative roots' );
    my $tell = $bar->tellafriend;
    is( $tell && $tell->{url},
        '/', 'Tell Someone URL remains nonempty with request-relative roots' );
};

subtest 'signed-in destinations and permission failures are unchanged' => sub {
    my $u      = Local::LinkBarAccount->new( type => 'C' );
    my $remote = Local::LinkBarAccount->new( type => 'P', can_post => 1 );
    my $bar = linkbar( $u, $remote );
    is(
        $bar->watch->{url},
        "$LJ::SITEROOT/manage/circle/add?user=linkbar_target&action=subscribe",
        'subscribe keeps its target'
    );
    is(
        $bar->post->{url},
        "$LJ::SITEROOT/update?usejournal=linkbar_target",
        'permitted post keeps its target'
    );
    is(
        $bar->tellafriend->{url},
        "$LJ::SITEROOT/tools/tellafriend?user=linkbar_target",
        'Tell Someone keeps its target'
    );
    $remote->{can_post} = 0;
    ok( !$bar->post->{url}, 'lack of posting permission does not acquire a home link' );
    $remote->{type}     = 'I';
    $remote->{can_post} = 1;
    ok( !$bar->post->{url}, 'identity viewer cannot post to a community' );
    $u->{visible} = 0;
    ok( !$bar->watch->{url}, 'unavailable journal remains unsubscribable' );
    $remote->{watches} = 1;
    ok( $bar->watch->{url}, 'existing subscription can still be managed' );
};

subtest 'disabled Tell Someone remains absent for every viewer' => sub {
    local $LJ::DISABLED{tellafriend} = 1;
    my $u = Local::LinkBarAccount->new( type => 'P' );
    ok( !linkbar($u)->tellafriend, 'disabled feature has no guest action' );
    ok( !linkbar( $u, $u )->tellafriend, 'disabled feature has no signed-in action' );
};

done_testing();

sub linkbar {
    my ( $u, $remote ) = @_;
    return bless { u => $u, remote => $remote, class_prefix => 'userlinkbar' },
        'DW::Logic::UserLinkBar';
}
