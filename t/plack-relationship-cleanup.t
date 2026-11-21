# t/plack-relationship-cleanup.t
#
# Test web account operations when relationship cleanup is blocked.
#
# Authors:
#      Dreamwidth contributors
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::RenameToken;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'relationshipCleanup';

test_psgi $app, sub {
    my ($request) = @_;
    my $post = sub {
        my ( $url, @args ) = @_;
        my $form = $request->( GET $url );
        my ($auth) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $auth, 'received form authentication token' ) or diag $form->code;
        return $request->( POST $url, [ lj_form_auth => $auth, @args ] );
    };

    subtest 'web community conversion does not complete on cleanup failure' => sub {
        my $admin    = temp_user();
        my $target   = temp_user();
        my $friend   = temp_user();
        my $password = 'conversion-test-password';
        $target->set_password($password);
        ok( $target->add_edge( $friend, trust => { nonotify => 1 } ), 'sets up outgoing trust' );
        ok( $target->add_edge( $friend, watch => { nonotify => 1 } ), 'sets up outgoing watch' );
        my $lock     = $target->lock_trust_groups or die 'cannot hold owner lock';
        my $url      = 'http://localhost/communities/convert?as=' . $admin->user;
        my @args     = ( cuser => $target->user, cpassword => $password );
        my $response = $post->( $url, @args );
        like(
            $response->content,
            qr/could not remove all outgoing relationships/i,
            'reports incomplete cleanup'
        );
        is( LJ::load_userid( $target->id )->journaltype, 'P', 'account stays personal' );
        is( $target->trustmask_from_primary($friend),    1,   'blocked grant is unchanged' );
        $lock->release;
        $post->( $url, @args );
        is( LJ::load_userid( $target->id )->journaltype, 'C', 'can convert after the lock clears' );
        ok( !$target->trustmask_from_primary($friend), 'grant is gone after conversion' );
        ok( !$target->watches($friend),                'watch is gone after conversion' );
    };

    subtest 'web rename distinguishes a completed rename from incomplete cleanup' => sub {
        my $owner  = temp_user();
        my $friend = temp_user();
        my $admin  = temp_user();
        $owner->update_self( { status => 'A' } );
        $admin->grant_priv( 'siteadmin', 'rename' );
        my $old   = $owner->user;
        my $new   = 'r' . substr( $old, 1 );
        my $token = DW::RenameToken->create_token( ownerid => $owner->id );
        ok( $owner->add_edge( $friend, trust => { nonotify => 1 } ), 'sets up outgoing trust' );
        my $lock   = $owner->lock_trust_groups or die 'cannot hold owner lock';
        my @keep   = map { ( rel_options => $_ ) } qw(trusted_by watched_by watched communities);
        my $rename = $post->(
            'http://localhost/rename/index?as=' . $old . '&giventoken=' . $token->token,
            authas   => $old,
            touser   => $new,
            redirect => 'disconnect',
            @keep
        );
        like(
            $rename->content,
            qr/rename completed.*relationship cleanup.*incomplete/is,
            'rename response acknowledges both outcomes'
        );
        is( LJ::load_user($new)->id, $owner->id, 'username changed despite incomplete cleanup' );
        is( $owner->trustmask_from_primary($friend), 1, 'blocked grant remains' );

        my $url =
            'http://localhost/admin/rename/edit?as=' . $admin->user . '&token=' . $token->token;
        my $settings = $post->( $url, override_relationships => 1, @keep );
        like(
            $settings->content,
            qr/relationship cleanup.*incomplete/i,
            'settings reports incomplete cleanup'
        );
        unlike(
            $settings->content,
            qr/Successfully changed settings/,
            'settings does not report success'
        );
        $lock->release;
        $settings = $post->( $url, override_relationships => 1, @keep );
        like(
            $settings->content,
            qr/Successfully changed settings/,
            'settings can retry after contention'
        );
        ok( !$owner->trustmask_from_primary($friend), 'retried cleanup removes the grant' );
    };
};

done_testing();
