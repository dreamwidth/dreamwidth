# t/openid-sysban.t
#
# Tests OpenID domain sysban management and enforcement.
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

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::OpenID;
use LJ::Session;
use LJ::Sysban;
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $host         = 'openid-' . lc( LJ::rand_chars(10) ) . '.test';
my $banned_url   = "https://sub.$host/new";
my $existing_url = "http://$host/existing";
my $allowed_url  = "https://not-$host/new";
my $callback     = 'http://localhost/openid/login?openid.mode=id_res';
my $restricted   = qr/restricted OpenID logins/i;
my $dbh          = LJ::get_db_writer();
my $banid;

END {
    if ($dbh) {
        $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $banid ) if $banid;
        foreach my $url ( $banned_url, $existing_url, $allowed_url ) {
            my $account = LJ::User::load_existing_identity_user( 'O', $url );
            next unless $account;
            LJ::Session->destroy_all_sessions($account);
            $dbh->do( 'DELETE FROM identitymap WHERE userid = ?', undef, $account->id );
            $account->delete_and_purge_completely;
        }
    }
}

with_fake_memcache {
    test_psgi $app, sub {
        my $request = shift;

        my $verified_url = $existing_url;
        no warnings 'redefine';
        local *Net::OpenID::Consumer::verified_identity = sub {
            return bless { url => $verified_url }, 'OpenIDSysbanTestIdentity';
        };
        local *Net::OpenID::Consumer::claimed_identity = sub {
            return bless { url => $_[1] }, 'OpenIDSysbanTestIdentity';
        };
        use warnings 'redefine';

        my $result = $request->( GET $callback );
        like( $result->header('Location') // '', qr{/login$}, 'An unbanned callback logs in' );
        my $existing = LJ::User::load_existing_identity_user( 'O', $existing_url );
        ok( $existing, 'An unbanned callback creates an account' ) or BAIL_OUT('No OpenID fixture');
        my $session = LJ::Session->create( $existing, exptype => 'short' );
        my $cookie =
              'ljmastersession='
            . $session->master_cookie_string
            . '; ljloggedin='
            . $session->loggedin_cookie_string;
        my $login_url = 'http://localhost/openid/login';
        my $logged_in = GET( $login_url, Cookie => $cookie );
        like(
            $request->($logged_in)->content,
            qr/must first.*log out/i,
            'The existing OpenID session is authenticated before the ban'
        );

        subtest 'manage an OpenID domain ban' => sub {
            my $admin = temp_user();
            $admin->grant_priv( 'sysban', '*' );
            local $LJ::T_NO_COMMAND_PRINT = 1;
            LJ::set_remote($admin);

            ok( scalar grep( $_ eq 'openid_domain', LJ::list_valid_args('sysban') ),
                'openid_domain is available to admins' );

            for my $invalid ( "*.$host", ".$host", "https://$host/user", "ssh://$host",
                "https://$host\@elsewhere.test/",
                'under_score.test', 'local', 'a' x 60 . '.' . 'b' x 20 . '.test' )
            {
                like(
                    LJ::Console->run_commands_text("sysban_add openid_domain $invalid"),
                    qr/Invalid OpenID domain/i,
                    "Rejects $invalid"
                );
            }

            my $input   = 'HTTPS://' . uc($host) . '/';
            my $message = LJ::Console->run_commands_text("sysban_add openid_domain $input 0 test");
            ($banid) = $message =~ /Successfully created ban #(\d+)/;
            ok( $banid, 'The console adds an OpenID domain ban' ) or diag $message;

            if ($banid) {
                $dbh->do( 'UPDATE sysban SET bandate = NOW() - INTERVAL 1 SECOND WHERE banid = ?',
                    undef, $banid );
            }

            my %bans;
            LJ::Sysban::populate_full( \%bans, 'openid_domain', 20, 0 );
            is( $bans{$host}{banid} // 0,
                $banid, 'Listing shows the ban under its canonical domain' );
            is( $bans{$host}{note}, 'test', 'The listed ban has the original note' );

            like(
                LJ::Console->run_commands_text("sysban_add openid_domain $host"),
                qr/already banned/i,
                'The same canonical domain cannot be added twice'
            );
            LJ::User->unset_remote;
        };

        subtest 'match and enforce the active ban' => sub {
            for my $value ( $host, uc($host), "http://$host/", $banned_url,
                "https://DEEP.SUB.$host.:8443/profile?x=1" )
            {
                ok( LJ::Sysban::sysban_check( 'openid_domain', $value ), "Bans $value" );
            }

            for my $value ( $allowed_url, "https://$host.elsewhere.test/" ) {
                ok( !LJ::Sysban::sysban_check( 'openid_domain', $value ), "Allows $value" );
            }

            my $post_login = sub {
                return $request->( POST $login_url, Content => [ openid_url => $_[0] ] );
            };
            like( $post_login->($banned_url)->content, $restricted, 'Login refuses a banned URL' );
            is(
                $post_login->($allowed_url)->header('Location'),
                'https://provider.test/verify',
                'Login still redirects for an allowed URL'
            );

            my ( $ok, $error ) = DW::Controller::Talk::authenticate_user_and_mutate_form(
                { usertype => 'openid', oidurl => $banned_url },
                undef, temp_user() );
            ok( !$ok, 'OpenID comment authentication refuses the banned URL' );
            like( ref $error ? '' : $error, $restricted, 'The comment refusal gives the reason' );

            for my $url ( $banned_url, $existing_url ) {
                $verified_url = $url;
                my $response = $request->( GET $callback );
                like( $response->content, $restricted, "Verification refuses $url" );
                ok( !scalar grep( /^ljmastersession=/, $response->header('Set-Cookie') ),
                    'A refused callback does not issue a session cookie' );
            }
            ok(
                !LJ::User::load_existing_identity_user( 'O', $banned_url ),
                'A banned callback does not create an account'
            );

            like( $request->($logged_in)->header('Location') // '',
                qr{/login$}, 'The existing session no longer authenticates with an active ban' );
            ok(
                !LJ::Session->instance( $existing, $session->id ),
                'The banned session was destroyed, not merely ignored'
            );

            $verified_url = $allowed_url;
            like( $request->( GET $callback )->header('Location') // '',
                qr{/login$}, 'An allowed provider can still complete login' );
            ok(
                LJ::User::load_existing_identity_user( 'O', $allowed_url ),
                'An allowed provider can still create an account'
            );
        };

        subtest 'expire an OpenID domain ban' => sub {
            if ($banid) {
                my $result = LJ::Sysban::modify(
                    banid   => $banid,
                    expire  => 0,
                    bandays => 'X',
                    note    => 'lifted',
                    what    => 'openid_domain',
                    value   => $host,
                );
                isnt( ref $result, 'ERROR', 'The ban can be edited and expired' );
                my $bans =
                    LJ::Sysban::populate_full_by_value_with_expired( $host, 'openid_domain' );
                is( $bans->{openid_domain}[0]{note},
                    'lifted', 'Listing the expired ban shows the edited note' );
            }
            else {
                fail('No ban was added to edit');
            }
            ok( !LJ::Sysban::sysban_check( 'openid_domain', $banned_url ),
                'The expired ban no longer matches' );
            $verified_url = $existing_url;
            like( $request->( GET $callback )->header('Location') // '',
                qr{/login$}, 'The previously banned provider can log in again' );
        };
    };
};

done_testing;

package OpenIDSysbanTestIdentity;

sub url         { $_[0]->{url} }
sub claimed_url { $_[0]->{url} }
sub display     { $_[0]->{url} }
sub check_url   { 'https://provider.test/verify' }
