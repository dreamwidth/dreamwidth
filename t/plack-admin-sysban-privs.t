# t/plack-admin-sysban-privs.t
#
# Request-level coverage for scoped read-only and writable system ban access.
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::Console;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sysbanPrivTest';
local $LJ::T_NO_COMMAND_PRINT = 1;

my @roles = (
    [ 'unprivileged', [], [], [] ],
    [ 'scoped reader', [ [ 'sysbanview', 'talk_ip_test' ] ], ['talk_ip_test'], [] ],
    [ 'wildcard reader', [ [ 'sysbanview', '*' ] ], [ 'talk_ip_test', 'email_domain' ], [] ],
    [ 'scoped writer', [ [ 'sysban', 'talk_ip_test' ] ], ['talk_ip_test'], ['talk_ip_test'] ],
    [ 'wildcard writer', [ [ 'sysban', '*' ] ],
        [ 'talk_ip_test', 'email_domain' ], [ 'talk_ip_test', 'email_domain' ] ],
    [ 'mixed grants', [ [ 'sysban', 'talk_ip_test' ], [ 'sysbanview', 'email_domain' ] ],
        [ 'talk_ip_test', 'email_domain' ], ['talk_ip_test'] ],
    [ 'wildcard read with scoped write',
        [ [ 'sysbanview', '*' ], [ 'sysban', 'talk_ip_test' ] ],
        [ 'talk_ip_test', 'email_domain' ], ['talk_ip_test'] ],
    [ 'empty reader argument', [ [ 'sysbanview', '' ] ], [], [] ],
);

my $dbh = LJ::get_db_writer();
my $prefix = 'sysbanpriv-' . temp_user()->user . '-';
my $value = '192.0.2.254';
my %bans;

# Fixed bandates avoid sleeping for the strict NOW() > bandate comparison.
# No connection-blocking IP or cached sysban types are created.
for my $type ( 'talk_ip_test', 'email_domain' ) {
    $dbh->do(
        "INSERT INTO sysban (what, value, note, bandate, banuntil) "
            . "VALUES (?, ?, ?, NOW() - INTERVAL 1 DAY, NULL)",
        undef, $type, $value, $prefix . $type
    );
    die $dbh->errstr if $dbh->err;
    $bans{$type} = $dbh->{'mysql_insertid'};
}
$dbh->do(
    "INSERT INTO sysban (what, value, note, bandate, banuntil) "
        . "VALUES ('email_domain', ?, ?, NOW() - INTERVAL 2 DAY, NOW() - INTERVAL 1 DAY)",
    undef, $value, $prefix . 'expired'
);
die $dbh->errstr if $dbh->err;

END {
    # Includes successful additions and edits, which retain the unique prefix.
    if ( $dbh && $prefix ) {
        $dbh->do( 'DELETE FROM sysban WHERE note LIKE ?', undef, "$prefix%" );
        $dbh->do( "DELETE FROM statushistory WHERE shtype IN ('sysban_add', 'sysban_modify') "
                . 'AND notes LIKE ?', undef, "%$prefix%" );
    }
}

my $snapshot = sub {
    return $dbh->selectall_arrayref(
        'SELECT banid, what, value, note, bandate, banuntil, status FROM sysban '
            . 'WHERE note LIKE ? ORDER BY banid', undef, "$prefix%"
    );
};

is_deeply( [ sort( LJ::list_valid_args('sysbanview') ) ],
    [ sort( LJ::list_valid_args('sysban') ) ], 'both privileges advertise the same types' );

with_fake_memcache {
    test_psgi $app, sub {
        my $cb = shift;
        my $request = sub {
            my ( $u, $path, $post ) = @_;
            my $url = 'http://localhost' . $path . '?as=' . $u->user;
            return $cb->( GET $url ) unless $post;
            LJ::set_remote($u);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $token = LJ::form_auth(1);
            LJ::set_remote(undef);
            return $cb->( POST $url, Content => [ lj_form_auth => $token, %$post ] );
        };

        for my $role (@roles) {
            my ( $name, $grants, $reads, $writes ) = @$role;
            subtest $name => sub {
                my $u = temp_user();
                for my $grant (@$grants) {
                    $u->grant_priv(@$grant)
                        or BAIL_OUT('Privilege seed missing: run update-db.pl -p before this test');
                }
                my %can_read = map { $_ => 1 } @$reads;
                my %can_write = map { $_ => 1 } @$writes;
                my $index = $request->( $u, '/admin/sysban' );
                isnt( $index->code, 500, 'index does not fail' );
                if (@$writes) {
                    like( $index->content, qr/name=['"]addnew['"]/, 'writer sees Add New' );
                }
                else {
                    unlike( $index->content, qr/name=['"]addnew['"]/, 'no Add New for readers' );
                }

                for my $type ( 'talk_ip_test', 'email_domain' ) {
                    my $option = qr/<option\b[^>]*value=['"]\Q$type\E['"]/;
                    if ( $can_read{$type} ) {
                        like( $index->content, $option, 'readable type appears in menu' );
                    }
                    else {
                        unlike( $index->content, $option, 'unreadable type absent from menu' );
                    }
                    my $query = $request->( $u, '/admin/sysban', { query => 1, bantype => $type } );
                    isnt( $query->code, 500, "$type query does not fail" );
                    if ( $can_read{$type} ) {
                        like( $query->content, qr/\Q$prefix$type\E/, 'permitted row is visible' );
                    }
                    else {
                        unlike( $query->content, qr/\Q$prefix$type\E/, 'other type is hidden' );
                    }
                    if ( $can_write{$type} ) {
                        like( $query->content, qr/name=['"]modify['"]/, 'writer can modify' );
                    }
                    else {
                        unlike( $query->content, qr/name=['"](?:modify|bandays|note)['"]/,
                            'no write controls without the type-specific write grant' );
                    }

                    my $before = $snapshot->();
                    my $addnew = $request->( $u, '/admin/sysban', { addnew => 1, bantype => $type } );
                    if (@$writes) {
                        like( $addnew->content, qr/name=['"]add['"]/, 'writer can open add form' );
                        if ( $can_write{$type} ) {
                            like( $addnew->content, $option, 'writable type appears in add menu' );
                        }
                        else {
                            unlike( $addnew->content, $option, 'read-only type absent from add menu' );
                        }
                    }
                    else {
                        unlike( $addnew->content, qr/name=['"]add['"]/, 'direct add form denied' );
                    }
                    next if $can_write{$type};
                    my @attempts = (
                        { add => 1, bantype => $type, value => '192.0.2.253',
                            bandays => 0, note => $prefix . 'denied' },
                        { modify => 1, bantype => $type, banid => $bans{$type},
                            expire => 0, bandays => 'E', value => $value, note => $prefix . 'edited' },
                        # Remove an active ban using the UI's "expire now" action.
                        { modify => 1, bantype => $type, banid => $bans{$type},
                            expire => 0, bandays => 'X', value => $value, note => $prefix . 'removed' },
                    );
                    for my $post (@attempts) {
                        my $res = $request->( $u, '/admin/sysban', $post );
                        isnt( $res->code, 500, 'forged mutation does not fail internally' );
                        is_deeply( $snapshot->(), $before, 'forged mutation leaves all bans unchanged' );
                    }
                }

                if (@$reads) {
                    my $admin = $request->( $u, '/admin/' );
                    like( $admin->content, qr/href=['"]\/admin\/sysban['"]/, 'admin index offers sysban page' );
                }

                for my $expired ( 0, 1 ) {
                    my $res = $request->( $u, '/admin/sysban',
                        { queryone => 1, queryvalue => $value, expiredcheck => $expired } );
                    for my $type ( 'talk_ip_test', 'email_domain' ) {
                        if ( $can_read{$type} ) {
                            like( $res->content, qr/\Q$prefix$type\E/, 'value lookup includes permitted type' );
                        }
                        else {
                            unlike( $res->content, qr/\Q$prefix$type\E/, 'value lookup excludes other type' );
                        }
                    }
                    if ( $expired && $can_read{email_domain} ) {
                        like( $res->content, qr/\Q${prefix}expired\E/, 'permitted expired ban is shown' );
                    }
                    else {
                        unlike( $res->content, qr/\Q${prefix}expired\E/, 'expired ban stays hidden' );
                    }
                }

                if ( $can_write{talk_ip_test} && !$can_write{email_domain} ) {
                    my $before = $snapshot->();
                    $request->( $u, '/admin/sysban',
                        { modify => 1, bantype => 'talk_ip_test', banid => $bans{email_domain},
                            expire => 0, bandays => 'X', value => $value, note => $prefix . 'forged' } );
                    is_deeply( $snapshot->(), $before, 'forged type cannot authorize another ban ID' );
                }

                unless (@$writes) {
                    LJ::set_remote($u);
                    is( LJ::Console->run_commands_text('sysban_add talk_ip_test 192.0.2.253 0 denied'),
                        'error: You are not authorized to run this command.',
                        'read privilege does not authorize console writes' );
                    LJ::set_remote(undef);
                }
            };
        }

        subtest 'stored values and denied types render as text' => sub {
            my $writer = temp_user();
            my $reader = temp_user();
            ok( $writer->grant_priv( 'sysban', 'email_domain' ), 'grant domain writer' );
            ok( $reader->grant_priv( 'sysbanview', 'email_domain' ), 'grant domain reader' );
            my $markup = 'example.<img src=x onerror=window.__sysbanXss=1>';
            my $note = $prefix . 'html-value';
            my $added = $request->( $writer, '/admin/sysban',
                { add => 1, bantype => 'email_domain', value => $markup,
                    bandays => 0, note => $note } );
            isnt( $added->code, 500, 'normal domain add does not fail internally' );
            my ($id) = $dbh->selectrow_array(
                'SELECT banid FROM sysban WHERE what=? AND value=? AND note=?',
                undef, 'email_domain', $markup, $note
            );
            ok( $id, 'normal authorized add stores the markup-bearing domain' );
            return unless $id;

            # Listing requires NOW() > bandate, even immediately after creation.
            $dbh->do( 'UPDATE sysban SET bandate=NOW() - INTERVAL 1 SECOND WHERE banid=?',
                undef, $id );
            for my $u ( $reader, $writer ) {
                my $query = $request->( $u, '/admin/sysban',
                    { query => 1, bantype => 'email_domain' } );
                is( $query->code, 200, 'authorized domain query renders' );
                like( $query->content, qr/\Q$note\E/, 'query includes the stored fixture' );
                like( $query->content,
                    qr/example\.&lt;img src=x onerror=window\.__sysbanXss=1&gt;/,
                    'stored markup is visible as escaped text' );
                unlike( $query->content, qr/<img\b[^>]*onerror=/i,
                    'stored value cannot create an image element' );
            }

            my $denied = $request->( $reader, '/admin/sysban',
                { query => 1, bantype => '<img src=x onerror=window.__sysbanXss=2>' } );
            like( $denied->content,
                qr/&lt;img src=x onerror=window\.__sysbanXss=2&gt;/,
                'denied type is escaped in the privilege error' );
            unlike( $denied->content, qr/<img\b[^>]*onerror=/i,
                'denied type cannot create an image element' );
        };

        subtest 'anonymous and invalid form-auth requests cannot mutate' => sub {
            my $before = $snapshot->();
            my $anonymous = $cb->( GET 'http://localhost/admin/sysban?as=nobody_exists' );
            unlike( $anonymous->content, qr/\Q$prefix\E/, 'anonymous user cannot view fixture' );
            my $u = temp_user();
            ok( $u->grant_priv( 'sysban', '*' ), 'grant writer for invalid form-auth check' );
            $cb->( POST 'http://localhost/admin/sysban?as=' . $u->user,
                Content => [ modify => 1, bantype => 'talk_ip_test', banid => $bans{talk_ip_test},
                    expire => 0, bandays => 'X', note => $prefix . 'csrf' ] );
            is_deeply( $snapshot->(), $before, 'missing form-auth prevents even a writer from mutating' );
        };

        subtest 'existing and mixed administrators retain real writes' => sub {
            for my $role ( grep { @{ $_->[3] } } @roles ) {
                my $u = temp_user();
                ok( $u->grant_priv(@$_), "grant $role->[0]" ) for @{ $role->[1] };
                my $note = $prefix . 'added-' . $u->user;
                my $res = $request->( $u, '/admin/sysban',
                    { add => 1, bantype => 'talk_ip_test', value => '192.0.2.253',
                        bandays => 0, note => $note } );
                isnt( $res->code, 500, 'add request does not fail' );
                my ($id) = $dbh->selectrow_array('SELECT banid FROM sysban WHERE note = ?', undef, $note);
                ok( $id, 'ban was really added' );
                $request->( $u, '/admin/sysban',
                    { modify => 1, bantype => 'talk_ip_test', banid => $id, expire => 0,
                        bandays => 'E', value => '192.0.2.253', note => $note . '-edited' } );
                is( $dbh->selectrow_array('SELECT note FROM sysban WHERE banid = ?', undef, $id),
                    $note . '-edited', 'ban note was really edited' );
                $request->( $u, '/admin/sysban',
                    { modify => 1, bantype => 'talk_ip_test', banid => $id, expire => 0,
                        bandays => 'X', value => '192.0.2.253', note => $note . '-removed' } );
                ok( $dbh->selectrow_array(
                    'SELECT banuntil IS NOT NULL AND banuntil <= NOW() FROM sysban WHERE banid = ?',
                    undef, $id ), 'ban was really expired' );
            }
        };
    };
};

done_testing();
