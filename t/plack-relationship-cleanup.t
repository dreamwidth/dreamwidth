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
use LJ::Test qw(temp_comm temp_user);

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

    subtest 'relationship addition uses account state after conversion' => sub {
        my $admin    = temp_user();
        my $target   = temp_user();
        my $friend   = temp_user();
        my $password = 'conversion-test-password';
        $target->set_password($password);
        my $acquire = \&DW::User::_lock_trust_group_write;
        my $convert = 1;
        no warnings 'redefine';
        local *DW::User::_lock_trust_group_write = sub {
            if ( $convert && $_[0]->id == $target->id ) {
                $convert = 0;
                my $url = 'http://localhost/communities/convert?as=' . $admin->user;
                $post->( $url, cuser => $target->user, cpassword => $password );
            }
            return $acquire->(@_);
        };
        ok( !$target->add_edge( $friend, watch => { nonotify => 1 }, trust => { nonotify => 1 } ),
            'in-flight addition fails after conversion' );
        is( LJ::load_userid( $target->id, 'force' )->journaltype, 'C', 'conversion committed' );
        ok( !$target->trustmask_from_primary($friend), 'no outgoing grant is written' );
        my ($watch) =
            LJ::get_db_writer()
            ->selectrow_array(
            'SELECT groupmask & (1 << 61) FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
            undef, $target->id, $friend->id );
        ok( !$watch, 'no outgoing watch is written' );
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
        my @cleanup_alerts = $settings->content =~ /Relationship cleanup is incomplete\./g;
        is( scalar @cleanup_alerts, 1, 'settings renders the incomplete-cleanup alert once' );
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

    subtest 'rename discovers incoming relationships on the writer' => sub {
        my $owner   = temp_user();
        my $grantor = temp_user();
        my $admin   = temp_user();
        $owner->update_self( { status => 'A' } );
        $admin->grant_priv( 'siteadmin', 'rename' );
        my $old   = $owner->user;
        my $new   = 'r' . substr( $old, 1 );
        my $token = DW::RenameToken->create_token( ownerid => $owner->id );
        ok( $grantor->add_edge( $owner, watch => { nonotify => 1 }, trust => { nonotify => 1 } ),
            'writes both incoming edges' );
        my $get_cache = \&LJ::MemCache::get;
        my $ownerid   = $owner->id;
        no warnings 'redefine';
        local *LJ::MemCache::get = sub {
            my ($key) = @_;
            return pack( 'N', 50000 )
                if ref $key eq 'ARRAY' && $key->[1] =~ /\A(?:trusted|watched)_by:$ownerid\z/;
            return $get_cache->(@_);
        };
        is( scalar $owner->trusted_by_userids, 0, 'the cached reverse list omits the grant' );
        my $lock   = $grantor->lock_trust_groups or die 'cannot hold grantor lock';
        my @keep   = map { ( rel_options => $_ ) } qw(trusted watched communities);
        my $rename = $post->(
            'http://localhost/rename/index?as=' . $old . '&giventoken=' . $token->token,
            authas   => $old,
            touser   => $new,
            redirect => 'disconnect',
            @keep
        );
        ok(
            $rename->content =~ /rename completed.*relationship cleanup.*incomplete/is,
            'initial rename reports blocked incoming cleanup despite the stale list'
        );
        is( $grantor->trustmask_from_primary($owner), 1, 'blocked grant still exists' );
        my $url =
            'http://localhost/admin/rename/edit?as=' . $admin->user . '&token=' . $token->token;
        my $settings = $post->( $url, override_relationships => 1, @keep );
        ok(
            $settings->content =~ /relationship cleanup.*incomplete/i,
            'rename settings also reports blocked incoming cleanup'
        );
        $lock->release;
        $settings = $post->( $url, override_relationships => 1, @keep );
        like( $settings->content, qr/Successfully changed settings/, 'settings succeeds on retry' );
        ok(
            !$grantor->trustmask_from_primary($owner),
            'the incoming grant is revoked on the writer'
        );
        my ($mask) =
            LJ::get_db_writer()
            ->selectrow_array(
            'SELECT groupmask FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
            undef, $grantor->id, $owner->id );
        ok( !$mask, 'the incoming watch is also removed on the writer' );
    };

    subtest 'failed popular feed subscriptions remain available to retry' => sub {
        my $reader = temp_user();
        my $feed   = temp_user( journaltype => 'Y' );
        $reader->create_content_filter( name => 'default', sortorder => 10 );
        my $name = $feed->user;
        no warnings 'redefine';
        local *LJ::Feed::get_popular_feeds =
            sub { return [ [ $name, 'Example feed', $feed->id, 'https://example.org/feed', 5 ] ] };
        my $url      = 'http://localhost/feeds/index?as=' . $reader->user;
        my @args     = ( userid => $reader->id, 'action:add' => 1, "add_$name" => 1 );
        my $lock     = $reader->lock_trust_groups or die 'cannot hold owner lock';
        my $response = $post->( $url, @args );
        ok( $response->content =~ /could not subscribe/i, 'reports incomplete subscriptions' );
        ok( $response->content =~ /name=['"]add_\Q$name\E['"]/, 'failed feed remains selectable' );
        my $filter =
            sub { LJ::load_userid( $reader->id, 'force' )->content_filters( name => 'default' ) };
        ok( !$filter->()->contains_userid( $feed->id ), 'failed watch does not update the filter' );
        $lock->release;
        $response = $post->( $url, @args );
        unlike( $response->content, qr/name=['"]add_\Q$name\E['"]/, 'saved feed leaves the list' );
        ok( $reader->watches($feed),                   'retry subscribes to the feed' );
        ok( $filter->()->contains_userid( $feed->id ), 'successful watch updates the filter' );
    };

    subtest 'an optional community watch cannot undo successful membership' => sub {
        my $member    = temp_user();
        my $community = temp_comm();
        $member->create_content_filter( name => 'default', sortorder => 10 );
        my $filter = $member->content_filters( name => 'default' );
        my $lock   = $member->lock_trust_groups or die 'cannot hold owner lock';
        ok( $member->join_community( $community, 1, 0 ), 'join succeeds during watch contention' );
        ok( $member->member_of($community), 'membership is saved' );
        ok( !$member->watches($community),  'watch is not saved' );
        ok( !$filter->contains_userid( $community->id ),
            'failed watch does not update the filter' );
        $lock->release;
    };
};

done_testing();
