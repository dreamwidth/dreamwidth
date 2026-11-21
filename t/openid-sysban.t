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

my $host          = 'openid-' . lc( LJ::rand_chars(10) ) . '.test';
my $banned_url    = "https://sub.$host/new";
my $existing_url  = "http://$host/existing";
my $allowed_url   = "https://not-$host/new";
my $delegated_url = "https://delegated-$host/new";
my $callback      = 'http://localhost/openid/login?openid.mode=id_res';
my $restricted    = qr/restricted OpenID logins/i;
my $dbh           = LJ::get_db_writer();
my @banids;
my $banid;

END {
    if ($dbh) {
        $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $_ ) for @banids;
        foreach my $url ( $banned_url, $existing_url, $allowed_url, $delegated_url ) {
            my $account = LJ::User::load_existing_identity_user( 'O', $url );
            next unless $account;
            LJ::Session->destroy_all_sessions($account);
            $dbh->do( 'DELETE FROM identitymap WHERE userid = ?', undef, $account->id );
            $account->delete_and_purge_completely;
        }
    }
}

sub run_sysban_cli {
    my $script = <<'PERL';
BEGIN { $LJ::_T_CONFIG = 1 }
open STDERR, '>&', \*STDOUT or die $!;
my $file = shift;
do $file;
die $@ || $!;
PERL
    open my $pipe, '-|', $^X, '-e', $script, '--', "$ENV{LJHOME}/bin/ljsysban.pl", @_
        or die $!;
    my $output = do { local $/; <$pipe> };
    close $pipe;
    return ( $? >> 8, $output // '' );
}

with_fake_memcache {
    test_psgi $app, sub {
        my $request = shift;

        my $verified_url = $existing_url;
        my $provider_url = 'https://provider.test/verify';
        my $delegate_url = 'https://delegate.test/account';
        my $discovered_url;
        my $protocol_version = 1;
        my $fixture          = sub {
            my ( $consumer, $url ) = @_;
            return Net::OpenID::ClaimedIdentity->new(
                consumer         => $consumer,
                identity         => $url,
                server           => $provider_url,
                delegate         => $delegate_url,
                protocol_version => $protocol_version,
                semantic_info    => {},
            );
        };
        no warnings 'redefine';
        local *Net::OpenID::Consumer::verified_identity = sub {
            return Net::OpenID::VerifiedIdentity->new(
                consumer         => $_[0],
                claimed_identity => $fixture->( $_[0], $verified_url ),
                signed_fields    => {},
            );
        };
        local *Net::OpenID::Consumer::claimed_identity = sub {
            return $fixture->( $_[0], $discovered_url // $_[1] );
        };
        local *Net::OpenID::ClaimedIdentity::check_url = sub { $_[0]->identity_server };
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

            for my $invalid (
                "*.$host",                        ".$host",
                "https://$host/user",             "ssh://$host",
                "https://$host\@elsewhere.test/", 'under_score.test',
                'local',                          'a' x 60 . '.' . 'b' x 20 . '.test',
                "b\xC3\xBCcher-$host",            "https://b%C3%BCcher-$host/"
                )
            {
                my $message = LJ::Console->run_commands_text("sysban_add openid_domain $invalid");
                push @banids, $message =~ /Successfully created ban #(\d+)/;
                like( $message, qr/Invalid OpenID domain/i, "Rejects $invalid" );
            }

            my $dbr = LJ::get_db_reader();
            my ($now) = $dbh->selectrow_array('SELECT UNIX_TIMESTAMP()');
            $_->do("SET timestamp = $now") or die $_->errstr for $dbh, $dbr;
            my $input   = 'HTTPS://' . uc($host) . '/';
            my $message = LJ::Console->run_commands_text("sysban_add openid_domain $input 0 test");
            ($banid) = $message =~ /Successfully created ban #(\d+)/;
            push @banids, $banid if $banid;
            my $duplicate = LJ::Console->run_commands_text("sysban_add openid_domain $host");
            push @banids, $duplicate =~ /Successfully created ban #(\d+)/;
            $_->do('SET timestamp = DEFAULT') or die $_->errstr for $dbh, $dbr;
            ok( $banid, 'The console adds an OpenID domain ban' ) or diag $message;
            like( $duplicate, qr/already banned/i, 'Rejects a duplicate in the same SQL second' );
            $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $1 )
                if $duplicate =~ /Successfully created ban #(\d+)/;

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
                LJ::Console->run_commands_text("sysban_add openid_domain sub.$host"),
                qr/already banned/i,
                'An active parent ban covers its subdomains'
            );

            my $idn = "xn--bcher-kva.$host";
            my $idn_message =
                LJ::Console->run_commands_text("sysban_add openid_domain $idn 0 test");
            my ($idn_id) = $idn_message =~ /Successfully created ban #(\d+)/;
            push @banids, $idn_id if $idn_id;
            ok( !$idn_id, 'An active parent ban covers its Punycode subdomain too' );

            $idn         = "xn--bcher-kva.idn-$host";
            $idn_message = LJ::Console->run_commands_text("sysban_add openid_domain $idn 0 test");
            ($idn_id) = $idn_message =~ /Successfully created ban #(\d+)/;
            push @banids, $idn_id if $idn_id;
            ok( $idn_id, 'The console accepts an ASCII Punycode host' ) or diag $idn_message;
            $dbh->do( 'UPDATE sysban SET bandate = NOW() - INTERVAL 1 SECOND WHERE banid = ?',
                undef, $idn_id )
                if $idn_id;

            for my $value ( $idn, "https://b\xC3\xBCcher.idn-$host/",
                "https://b%C3%BCcher.idn-$host/" )
            {
                ok( LJ::Sysban::sysban_check( 'openid_domain', $value ), "Matches the IDN $value" );
            }
            LJ::User->unset_remote;
        };

        subtest 'validate CLI adds and modifies' => sub {
            my $cli_host = "cli-$host";
            my ( $exit, $output ) =
                run_sysban_cli( '--add', '--what=openid_domain',
                '--value=HTTPS://' . uc($cli_host) . '/',
                );
            my ($cli_id) = $output =~ /CREATED: banid=(\d+)/;
            push @banids, $cli_id if $cli_id;
            is( $exit, 0, 'The CLI accepts a root URL' ) or diag $output;
            ok( $cli_id, 'The CLI returns the ban ID' ) or return;
            my $stored = sub {
                return $dbh->selectrow_array( 'SELECT value FROM sysban WHERE banid = ?',
                    undef, $cli_id );
            };
            is( $stored->(), $cli_host, 'The CLI stores the canonical add value' );

            ( $exit, $output ) =
                run_sysban_cli( '--modify', "--banid=$cli_id", "--value=https://sub.$cli_host/", );
            is( $exit, 0, 'The CLI accepts a modified root URL' ) or diag $output;
            is( $stored->(), "sub.$cli_host", 'The CLI stores the canonical modified value' );

            ( $exit, $output ) =
                run_sysban_cli( '--modify', "--banid=$cli_id", "--value=https://$cli_host/path", );
            isnt( $exit, 0, 'The CLI refuses an invalid replacement' );
            like( $output, qr/Invalid OpenID domain/i, 'The CLI explains the invalid replacement' );
            is( $stored->(), "sub.$cli_host", 'The invalid replacement leaves the ban intact' );

            ( $exit, $output ) =
                run_sysban_cli( '--add', '--what=openid_domain', "--value=*.$cli_host", );
            push @banids, $output =~ /CREATED: banid=(\d+)/;
            isnt( $exit, 0, 'The CLI refuses an invalid new ban' );
            like( $output, qr/Invalid OpenID domain/i, 'The CLI explains the invalid new value' );

            my $convert_host = "convert-$host";
            ( $exit, $output ) =
                run_sysban_cli( '--add', '--what=email_domain', "--value=https://$convert_host/", );
            my ($conversion_id) = $output =~ /CREATED: banid=(\d+)/;
            push @banids, $conversion_id if $conversion_id;
            ok( $conversion_id, 'Create a non-OpenID ban to convert' ) or return;
            ( $exit, $output ) =
                run_sysban_cli( '--modify', "--banid=$conversion_id", '--what=openid_domain', );
            is( $exit, 0, 'The CLI can convert a ban with a valid value' ) or diag $output;
            is_deeply(
                $dbh->selectrow_arrayref(
                    'SELECT what, value FROM sysban WHERE banid = ?',
                    undef, $conversion_id
                ),
                [ 'openid_domain', $convert_host ],
                'Converting to an OpenID ban canonicalizes the existing value'
            );
        };

        subtest 'ignore noncanonical OpenID ban types' => sub {
            for my $what ( 'OPENID_DOMAIN', 'openid_domain ' ) {
                my $lookalike_host = ( $what =~ / $/ ? 'padded-' : 'mixed-case-' ) . $host;
                $dbh->do(
'INSERT INTO sysban (what, value, bandate) VALUES (?, ?, NOW() - INTERVAL 1 SECOND)',
                    undef, $what, $lookalike_host
                ) or die $dbh->errstr;
                push @banids, $dbh->{mysql_insertid};
                ok( !LJ::Sysban::sysban_check( 'openid_domain', "https://$lookalike_host/" ),
                    "The row with type '$what' does not ban its domain" );
                is( LJ::Sysban::validate( 'openid_domain', $lookalike_host ),
                    0, "The row with type '$what' does not prevent a canonical ban" );
            }
        };

        subtest 'match and enforce the active ban' => sub {
            for my $value ( $host, uc($host), "http://$host/", $banned_url,
                "https://DEEP.SUB.$host.:8443/profile?x=1" )
            {
                ok( LJ::Sysban::sysban_check( 'openid_domain', $value ), "Bans $value" );
            }

            ok(
                LJ::Sysban::sysban_check( 'openid_domain', " \t$banned_url\r\n" ),
                'A URL with surrounding whitespace still matches its domain ban'
            );
            ok(
                !LJ::Sysban::sysban_check( 'openid_domain', "https://sub .$host/new" ),
                'A hostname with embedded whitespace is still rejected as invalid'
            );

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

        subtest 'enforce bans on discovered and verified OpenID URLs' => sub {
            my $member         = temp_user();
            my $member_session = LJ::Session->create( $member, exptype => 'short' );
            my $member_cookie =
                  'ljmastersession='
                . $member_session->master_cookie_string
                . '; ljloggedin='
                . $member_session->loggedin_cookie_string;
            my $mail_sent = 0;
            no warnings 'redefine';
            local *LJ::send_mail = sub { ++$mail_sent; return 1 };
            use warnings 'redefine';

            for my $source ( 'claimed identity', 'provider endpoint', 'delegate URL' ) {
                $discovered_url = $source eq 'claimed identity' ? $banned_url : $delegated_url;
                $provider_url =
                    $source eq 'provider endpoint' ? $banned_url : 'https://provider.test/verify';
                $delegate_url =
                    $source eq 'delegate URL' ? $banned_url : 'https://delegate.test/account';

                my $login =
                    $request->( POST $login_url, Content => [ openid_url => $allowed_url ] );
                like( $login->content, $restricted, "Login refuses the discovered $source" );

                my ( $ok, $error ) = DW::Controller::Talk::authenticate_user_and_mutate_form(
                    { usertype => 'openid', oidurl => $allowed_url },
                    undef, $member );
                ok( !$ok, "Commenting refuses the discovered $source" );
                like( ref $error ? '' : $error,
                    $restricted, 'The comment refusal gives the reason' );

                my $claim = $request->(
                    POST 'http://localhost/openid/claim',
                    Cookie  => $member_cookie,
                    Content => [ openid_url => $allowed_url ]
                );
                like( $claim->content, $restricted, "Claiming refuses the discovered $source" );

                for my $version ( 1, 2 ) {
                    $protocol_version = $version;
                    $verified_url     = $discovered_url;
                    my $response = $request->( GET $callback );
                    like( $response->content, $restricted,
                        "OpenID $version login refuses the verified $source" );
                    ok(
                        !scalar grep( /^ljmastersession=/, $response->header('Set-Cookie') ),
                        'The refused callback does not issue a session cookie'
                    );

                    my $claimed = $request->(
                        GET 'http://localhost/openid/claimed?openid.mode=id_res',
                        Cookie => $member_cookie
                    );
                    like( $claimed->content, $restricted,
                        "OpenID $version claiming refuses the verified $source" );
                }
            }
            is( $mail_sent, 0, 'Banned claim callbacks send no confirmation mail' );
            ok(
                !LJ::User::load_existing_identity_user( 'O', $delegated_url ),
                'Banned provider and delegate callbacks create no identity account'
            );
            $dbh->do( "DELETE FROM authactions WHERE userid = ? AND action = 'claimopenid'",
                undef, $member->id )
                if $mail_sent;
            $member->writer->do( 'DELETE FROM pendcomments WHERE jid = ?', undef, $member->id );

            $provider_url   = 'https://provider.test/verify';
            $delegate_url   = $host;
            $discovered_url = $delegated_url;
            is(
                $request->( POST $login_url, Content => [ openid_url => $allowed_url ] )
                    ->header('Location'),
                $provider_url,
                'A non-URL delegate is not treated as a domain'
            );
        };

        subtest 'check discovered provider URLs with whitespace' => sub {
            my ( $original_discovery, $original_provider ) = ( $discovered_url, $provider_url );
            $discovered_url = $allowed_url;
            $provider_url   = "https://sub.$host/verify here?q=one two";
            like( $request->( POST $login_url, Content => [ openid_url => $allowed_url ] )->content,
                $restricted, 'Whitespace outside the hostname does not hide a banned provider' );
            $provider_url = "https://sub .$host/verify";
            unlike(
                $request->( POST $login_url, Content => [ openid_url => $allowed_url ] )->content,
                $restricted, 'A hostname containing whitespace does not match' );
            ok( !LJ::Sysban::sysban_check( 'openid_domain', "https://sub.$host/verify here" ),
                'The submitted-URL check still rejects embedded whitespace' );
            ( $discovered_url, $provider_url ) = ( $original_discovery, $original_provider );
        };

        subtest 'allow provider selection when the marker domain is banned' => sub {
            my @original_discovery =
                ( $protocol_version, $discovered_url, $delegate_url, $provider_url );
            my $admin = temp_user();
            $admin->grant_priv( 'sysban', '*' );
            local $LJ::T_NO_COMMAND_PRINT = 1;
            LJ::set_remote($admin);
            my $message =
                LJ::Console->run_commands_text('sysban_add openid_domain specs.openid.net');
            LJ::User->unset_remote;
            my ($id) = $message =~ /Successfully created ban #(\d+)/;
            push @banids, $id if $id;
            ok( $id, 'The marker domain was banned' ) or diag $message;

            my $identifier_select = 'http://specs.openid.net/auth/2.0/identifier_select';
            $protocol_version = 2;
            $discovered_url   = $identifier_select;
            $delegate_url     = $identifier_select;
            $provider_url     = 'https://provider.test/verify';
            my $post_login = sub {
                return $request->( POST $login_url, Content => [ openid_url => $allowed_url ] );
            };
            is( $post_login->()->header('Location'),
                $provider_url, 'Login redirects to the allowed provider' );

            $provider_url = $banned_url;
            like( $post_login->()->content, $restricted, 'The provider endpoint is still checked' );
            $provider_url = 'https://provider.test/verify';
            $delegate_url = " $identifier_select ";
            like( $post_login->()->content, $restricted, 'A padded URL is not the exact marker' );
            ( $protocol_version, $discovered_url, $delegate_url, $provider_url ) =
                @original_discovery;
        };

        subtest 'expire an OpenID domain ban' => sub {
            my $admin = temp_user();
            $admin->grant_priv( 'sysban', 'openid_domain' );
            if ($banid) {
                my $result = LJ::Sysban::modify(
                    actor   => $admin,
                    banid   => $banid,
                    bandays => 'X',
                    note    => 'lifted',
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
            local $LJ::T_NO_COMMAND_PRINT = 1;
            LJ::set_remote($admin);
            my $message = LJ::Console->run_commands_text("sysban_add openid_domain $host");
            my ($replacement) = $message =~ /Successfully created ban #(\d+)/;
            push @banids, $replacement if $replacement;
            ok( $replacement, 'An expired domain ban can be re-added' ) or diag $message;
            $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $replacement ) if $replacement;
            LJ::User->unset_remote;
            $verified_url = $existing_url;
            like( $request->( GET $callback )->header('Location') // '',
                qr{/login$}, 'The previously banned provider can log in again' );
        };
    };
};

done_testing;
