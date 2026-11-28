# t/sysban-privs.t
#
# Tests the per-type authorization rule for web sysban management.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::Session;
use LJ::Sysban;
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::User;

sub moderator {
    my (@scopes) = @_;
    return bless {
        _privloaded => { sysban => 1 },
        _priv       => @scopes ? { sysban => { map { $_ => 1 } @scopes } } : {},
        },
        'LJ::User';
}

my $scoped = moderator('fixture_alpha');
my $full   = moderator('*');

ok( LJ::Sysban::can_manage_type( $scoped, 'fixture_alpha' ), 'Matching scope allows the type' );
ok( !LJ::Sysban::can_manage_type( $scoped, 'fixture_beta' ),  'Other types need their own scope' );
ok( !LJ::Sysban::can_manage_type( $scoped, 'FIXTURE_ALPHA' ), 'Scope matching is exact' );
ok( !LJ::Sysban::can_manage_type( $scoped, undef ), 'Missing type does not use the page grant' );
ok( LJ::Sysban::can_manage_type( $full, 'fixture_alpha' ), 'Wildcard allows the first type' );
ok( LJ::Sysban::can_manage_type( $full, 'fixture_beta' ),  'Wildcard allows another type' );
ok( !LJ::Sysban::can_manage_type( $full,         '*' ), 'Wildcard is not itself a ban type' );
ok( !LJ::Sysban::can_manage_type( moderator(''), '' ),  'An empty grant does not name a type' );
ok( !LJ::Sysban::can_manage_type( moderator(), 'fixture_alpha' ), 'The grant is required' );

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $dbh = LJ::get_db_writer();
my @banids;

END {
    $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $_ ) for @banids;
}

with_fake_memcache {
    my $openid_admin = temp_user();
    $openid_admin->grant_priv( 'sysban', 'openid_domain' );
    my $email_admin = temp_user();
    $email_admin->grant_priv( 'sysban', 'email_domain' );
    my $wildcard_admin = temp_user();
    $wildcard_admin->grant_priv( 'sysban', '*' );

    my $host    = 'scope-' . lc( LJ::rand_chars(10) ) . '.test';
    my $add_ban = sub {
        my ( $type, $value, $note, $expiry ) = @_;
        $dbh->do(
            'INSERT INTO sysban (what, value, note, bandate, banuntil) '
                . 'VALUES (?, ?, ?, NOW() - INTERVAL 2 DAY, NOW() + INTERVAL ? DAY)',
            undef, $type, $value, $note, $expiry
        ) or die $dbh->errstr;
        push @banids, $dbh->{mysql_insertid};
        return $banids[-1];
    };
    my $banid = $add_ban->( 'openid_domain', $host, 'Scoped active ban', 2 );
    $add_ban->( 'openid_domain', $host, 'Scoped expired ban', -1 );
    my $email_banid = $add_ban->( 'email_domain', $host, 'Other type ban', 2 );
    $add_ban->( 'OPENID_DOMAIN',  $host,         'Uppercase type ban',                 2 );
    $add_ban->( 'openid_domain ', $host,         'Padded type ban',                    2 );
    $add_ban->( 'OPENID_DOMAIN',  "sub.$host",   'Uppercase type with distinct value', 2 );
    $add_ban->( 'openid_domain',  "exact-$host", 'Different exact value',              2 );
    my $legacy_email = "legacy\@$host";
    my $legacy_id    = $add_ban->( 'EMAIL', $legacy_email, 'Legacy mixed-case ban', 2 );

    subtest 'case-insensitive lookups still find legacy types' => sub {
        my %bans;
        LJ::Sysban::populate_full( \%bans, 'email' );
        is( $bans{$legacy_email}{banid}, $legacy_id, 'The email list includes the EMAIL row' );
        for my $lookup ( \&LJ::Sysban::populate_full_by_value,
            \&LJ::Sysban::populate_full_by_value_with_expired )
        {
            my $bans = $lookup->( $legacy_email, 'email', 'openid_domain' );
            is( $bans->{EMAIL}[0]{banid},
                $legacy_id, 'Exact-value lookup also finds the mixed-case email row' );
            my $all_legacy = $lookup->($host);
            ok( exists $all_legacy->{email_domain},
                'No type restriction still includes legacy bans' );
            ok( !exists $all_legacy->{openid_domain}, 'OpenID bans always require the exact type' );
        }
    };

    subtest 'cannot edit a ban of a different type' => sub {
        my $stored = sub {
            return $dbh->selectrow_arrayref( 'SELECT note, banuntil FROM sysban WHERE banid = ?',
                undef, $banid );
        };
        my $before = $stored->();
        LJ::User->set_remote($email_admin);
        my $result = LJ::Sysban::modify(
            banid   => $banid,
            expire  => 0,
            bandays => 'X',
            note    => 'Unauthorized replacement',
            what    => 'email_domain',
            value   => $host,
        );
        LJ::User->unset_remote;
        is( ref $result, 'ERROR', 'Edit fails without the stored type grant' );
        is_deeply( $stored->(), $before, 'The stored note and expiry are unchanged' );
    };

    subtest 'scope the admin listing and exact-value search' => sub {
        test_psgi $app, sub {
            my $request = shift;
            my $url     = 'http://localhost/admin/sysban';
            my $visit   = sub {
                my ($admin) = @_;
                DW::Request->reset;
                DW::Request::Standard->new( GET $url );
                my $session = LJ::Session->create( $admin, exptype => 'short' );
                my $cookie =
                      'ljmastersession='
                    . $session->master_cookie_string
                    . '; ljloggedin='
                    . $session->loggedin_cookie_string;
                my $page = $request->( GET $url, Cookie => $cookie );
                my ($token) = $page->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
                ok( $token, 'The administrator receives a form auth token' ) or return;
                return $page->content, sub {
                    return $request->(
                        POST $url,
                        Cookie  => $cookie,
                        Content => [ lj_form_auth => $token, @_ ]
                    )->content;
                };
            };
            my $menu = sub {
                my ($page) = @_;
                my ($select) =
                    $page =~ /<select\b[^>]*\bname=['"]bantype['"][^>]*>(.*?)<\/select>/s;
                return [ sort( ( $select // '' ) =~ /<option\b[^>]*\bvalue=['"]([^'"]*)['"]/g ) ];
            };
            my ( $scoped_page, $scoped_post ) = $visit->($openid_admin);
            return unless $scoped_post;
            is_deeply( $menu->($scoped_page), ['openid_domain'], 'The menu shows only the grant' );

            my $list = $scoped_post->( query => 1, bantype => 'openid_domain' );
            like( $list, qr/Scoped active ban/, 'Type listing includes the active canonical row' );
            unlike(
                $list,
                qr/Scoped expired ban|Other type ban|Uppercase type|Padded type/,
                'Type listing excludes expired and nonmatching types'
            );
            unlike(
                $scoped_post->( query => 1, bantype => 'OPENID_DOMAIN' ),
                qr/Scoped active ban/,
                'A case variant does not bypass the OpenID type match'
            );
            my ( undef, $email_post ) = $visit->($email_admin);
            return unless $email_post;
            unlike(
                $email_post->( query => 1, bantype => 'openid_domain' ),
                qr/Scoped active ban/,
                'A legacy scoped moderator cannot list canonical OpenID bans'
            );

            my $active = $scoped_post->( queryone => 1, queryvalue => $host );
            like( $active, qr/Scoped active ban/, 'Exact search finds the active row' );
            unlike(
                $active,
qr/Scoped expired ban|Other type ban|Uppercase type|Padded type|Different exact value/,
                'Active exact search excludes expired rows, other types and other values'
            );

            my @with_expired = ( queryone => 1, queryvalue => $host, expiredcheck => 1 );
            my $expired      = $scoped_post->(@with_expired);
            like( $expired, qr/Scoped active ban/,  'Expanded exact search keeps the active row' );
            like( $expired, qr/Scoped expired ban/, 'Expanded exact search includes expired rows' );
            unlike(
                $expired,
                qr/Other type ban|Uppercase type|Padded type|Different exact value/,
                'Expanded exact search is still scoped by type and value'
            );

            my ( $wildcard_page, $wildcard_post ) = $visit->($wildcard_admin);
            return unless $wildcard_post;
            is_deeply(
                $menu->($wildcard_page),
                [ sort grep { length && $_ ne '*' } LJ::list_valid_args('sysban') ],
                'A wildcard menu lists all registered types'
            );
            my $all = $wildcard_post->(@with_expired);
            like( $all, qr/Scoped active ban/,  'Wildcard search includes the active OpenID ban' );
            like( $all, qr/Scoped expired ban/, 'Wildcard search includes the expired OpenID ban' );
            like( $all, qr/Other type ban/, 'Wildcard search includes the registered email type' );
            unlike(
                $all,
                qr/Uppercase type|Padded type|Different exact value/,
                'Wildcard search does not include unregistered types or other values'
            );

            subtest 'legacy web listing and editing still use the page grant' => sub {
                like(
                    $scoped_post->( query => 1, bantype => 'email_domain' ),
                    qr/Other type ban/,
                    'The page grant still allows listing a legacy type'
                );

                my $expire = $dbh->selectrow_array(
                    'SELECT UNIX_TIMESTAMP(banuntil) FROM sysban WHERE banid = ?',
                    undef, $email_banid );
                my @edit = (
                    modify  => 1,
                    expire  => $expire,
                    bandays => 'E',
                    bantype => 'email_domain',
                    value   => $host,
                    note    => 'Edited legacy ban'
                );
                like( $scoped_post->( @edit, banid => $email_banid ),
                    qr/Success/i, 'The edit form reports success' );
                is_deeply(
                    $dbh->selectrow_arrayref(
                        'SELECT note, UNIX_TIMESTAMP(banuntil) FROM sysban WHERE banid = ?',
                        undef, $email_banid
                    ),
                    [ 'Edited legacy ban', $expire ],
                    'The original form parameters edit the note without changing expiry'
                );
            };
        };
    };
};

done_testing;
