# t/sysban-import.t
#
# Tests for the command-line email domain sysban importer.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Fcntl qw(O_RDWR);
use File::Temp qw(tempdir tempfile);
use IPC::Open3 qw(open3);
use POSIX qw(mkfifo);
use Test::More;
use Time::HiRes qw(sleep time);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;

my $suffix            = "sysban-import-$$.test";
my $user_parent       = "alias-parent-$$.test";
my $user_domain       = "mail.$user_parent";
my $incoming_parent   = "incoming-parent-$$.test";
my $incoming_domain   = "mx.$incoming_parent";
my $existing          = "existing.$suffix";
my $new               = "new.$suffix";
my $last              = "last.$suffix";
my $temporary         = "temporary.$suffix";
my $short_ban         = "short.$suffix";
my $min_ban           = "min.$suffix";
my $delayed_first     = "delayed1.$suffix";
my $delayed_second    = "delayed2.$suffix";
my $concurrent_shared = "concurrent-shared.$suffix";
my $concurrent_only1  = "concurrent-one.$suffix";
my $concurrent_only2  = "concurrent-two.$suffix";
my $audit_fail        = "audit-fail.$suffix";
my $audit_partial     = "audit-partial.$suffix";
my $underscore_ban    = "a_b.$suffix";
my $site              = "site.$suffix";
my $note              = "Import test $$";
my $dbh               = LJ::get_db_writer();

END {
    if ($dbh) {
        eval { $dbh->rollback } unless $dbh->{AutoCommit};
        $dbh->do( "DELETE FROM sysban WHERE note IN (?, ?)", undef, $note, "Original $note" );
        $dbh->do(
            "DELETE FROM statushistory "
                . "WHERE userid = 0 AND adminid = 0 AND shtype = 'sysban_add' "
                . "AND (notes LIKE ? OR notes LIKE ?)",
            undef, "%note=$note;%", "%note=Original $note;%",
        );
    }
}

sub spawn_import_path {
    my ( $path, $fail_audit, @options ) = @_;
    my $pid = open3(
        my $input, my $output, undef, $^X, '-e',
        q{
            BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
            local $LJ::DOMAIN                 = shift @ARGV;
            local $LJ::USER_DOMAIN            = shift @ARGV;
            local @LJ::INCOMING_EMAIL_DOMAINS = ( shift @ARGV );
            my $fail_audit                    = shift @ARGV;
            if ($fail_audit) {
                no warnings 'redefine';
                *LJ::statushistory_add = sub { return 0 };
            }
            $0 = shift @ARGV;
            do $0;
            die $@ if $@;
            die $! if $!;
        },
        '--', $site, $user_domain, $incoming_domain, $fail_audit ? 1 : 0,
        "$ENV{LJHOME}/bin/ljsysban.pl", "--import-email-domains=$path", @options,
    );
    close $input;
    return ( $pid, $output );
}

sub finish_import {
    my ( $pid, $output ) = @_;
    my $log = do { local $/; <$output> };
    close $output;
    waitpid $pid, 0;
    return ( $? >> 8, $log );
}

sub import_domains {
    my ( $lines,   @options ) = @_;
    my ( $fixture, $path )    = tempfile( UNLINK => 1 );
    print {$fixture} $lines;
    close $fixture or die "Cannot close import fixture: $!";
    return finish_import( spawn_import_path( $path, 0, @options ) );
}

sub wait_for_sysban_match {
    my ( $email, $timeout ) = @_;
    my $deadline = time() + ( $timeout // 3 );
    while ( time() < $deadline ) {
        return 1 if LJ::sysban_check( 'email', $email );
        sleep 0.1;
    }
    return LJ::sysban_check( 'email', $email ) ? 1 : 0;
}

my $original = LJ::Sysban::create(
    what     => 'email_domain',
    value    => $existing,
    bandays  => 0,
    note     => "Original $note",
    noremote => 1,
);
BAIL_OUT('Could not seed existing domain sysban') if ref $original;

# CLI flag validation
my ( $status, $log ) =
    import_domains( "$new\n", '--add', '--what=ip', "--value=$new", "--note=$note" );
isnt( $status, 0, 'import cannot be combined with a different sysban action' );
( $status, $log ) = import_domains("$new\n");
isnt( $status, 0, 'a shell operator must supply an audit note' );
is( $dbh->selectrow_array( 'SELECT COUNT(*) FROM sysban WHERE value = ?', undef, $new ),
    0, 'rejected invocations did not write any bans' );

# Normalization, validation, and protected site-configured domains
my $uppercase = uc $new;
my $oversize  = ( 'a' x 63 ) . ".$suffix";
( $status, $log ) = import_domains(
    join( "\n",
        "# reviewed list\r", " $uppercase \r", '',           $new,
        $existing,           "*.bad.$suffix",  $site,        $suffix,
        $oversize,           $user_domain,     $user_parent, $incoming_domain,
        $incoming_parent,    $last, ),
    "--note=$note",
);
isnt( $status, 0, 'mixed results return failure so an operator sees rejected lines' );
like( $log, qr/line 6:.*invalid/i,    'wildcards are rejected with a line number' );
like( $log, qr/line 7:.*protected/i,  'the configured site domain is protected' );
like( $log, qr/line 8:.*protected/i,  'parent domains of the site are also protected' );
like( $log, qr/line 9:.*invalid/i,    'domains too long for sysban storage are rejected' );
like( $log, qr/line 10:.*protected/i, 'the configured USER_DOMAIN alias is protected' );
like( $log, qr/line 11:.*protected/i, 'parent domains of USER_DOMAIN are also protected' );
like( $log, qr/line 12:.*protected/i, 'configured INCOMING_EMAIL_DOMAINS are protected' );
like( $log, qr/line 13:.*protected/i, 'parent domains of INCOMING_EMAIL_DOMAINS are protected' );

is_deeply(
    $dbh->selectall_arrayref(
        'SELECT what, value FROM sysban WHERE note = ? ORDER BY value',
        undef, $note
    ),
    [ [ 'email_domain', $last ], [ 'email_domain', $new ] ],
    'only valid, unique domains are added, including the last line after an error',
);
is(
    $dbh->selectrow_array( 'SELECT note FROM sysban WHERE banid = ?', undef, $original ),
    "Original $note",
    'existing ban and audit note are preserved'
);

# Verify statushistory audit rows were written for successful imports
for my $added_domain ( $new, $last ) {
    my $banid =
        $dbh->selectrow_array( 'SELECT banid FROM sysban WHERE what = ? AND value = ? AND note = ?',
        undef, 'email_domain', $added_domain, $note, );
    my $audit_rows = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM statushistory '
            . 'WHERE userid = 0 AND adminid = 0 AND shtype = ? '
            . 'AND notes LIKE ? AND notes LIKE ? AND notes LIKE ?',
        undef,
        'sysban_add',
        "%banid=$banid;%",
        "%what=email_domain; value=$added_domain;%",
        "%note=$note;%",
    );
    is( $audit_rows, 1, "sysban_add statushistory row recorded for $added_domain" );
}

# Serial repeat idempotency
( $status, $log ) = import_domains( "$new\n$last\n", "--note=$note" );
is( $status, 0, 'a valid repeat import succeeds' );
is( $dbh->selectrow_array( 'SELECT COUNT(*) FROM sysban WHERE note = ?', undef, $note ),
    2, 'repeat import does not add duplicate rows' );

# Temporary ban duration: 1h, unsupported 1s minimum, 2s boundary, and delayed import
( $status, $log ) = import_domains( "$temporary\n", "--note=$note", '--banlength=1h' );
is( $status, 0, 'import accepts a ban duration' );
my $remaining = $dbh->selectrow_array(
    'SELECT TIMESTAMPDIFF(SECOND, NOW(), banuntil) FROM sysban WHERE note = ? AND value = ?',
    undef, $note, $temporary, );
ok( defined $remaining && $remaining > 3500 && $remaining <= 3600,
    'temporary ban expires in an hour' );

( $status, $log ) = import_domains( "$short_ban\n", "--note=$note", '--banlength=1s' );
isnt( $status, 0, 'a 1s banlength is rejected because it has no effective window' );
is(
    $dbh->selectrow_array(
        'SELECT COUNT(*) FROM sysban WHERE what = ? AND value = ?', undef,
        'email_domain',                                             $short_ban,
    ),
    0,
    'rejected 1s banlength wrote no ban row'
);

( $status, $log ) = import_domains( "$min_ban\n", "--note=$note", '--banlength=2s' );
is( $status, 0, 'a 2s minimum banlength is accepted' );
my $min_span = $dbh->selectrow_array(
    'SELECT TIMESTAMPDIFF(SECOND, bandate, banuntil) FROM sysban WHERE note = ? AND value = ?',
    undef, $note, $min_ban, );
is( $min_span, 2, '2s ban stores a 2-second interval from its bandate' );
ok(
    wait_for_sysban_match( "user\@$min_ban", 2.5 ),
    '2s minimum-duration ban takes effect in real email lookup'
);

# Delayed import crossing initial duration deadline
{
    my $dir  = tempdir( CLEANUP => 1 );
    my $fifo = "$dir/delayed.fifo";
    mkfifo( $fifo, 0600 ) or die "mkfifo $fifo failed: $!";
    sysopen( my $writer, $fifo, O_RDWR ) or die "sysopen $fifo failed: $!";
    my $old_fh = select $writer;
    $| = 1;
    select $old_fh;

    my ( $pid, $out ) = spawn_import_path( $fifo, 0, "--note=$note", '--banlength=4s' );
    print {$writer} "$delayed_first\n";
    sleep 5;
    print {$writer} "$delayed_second\n";
    close $writer;

    my ( $delay_status, $delay_log ) = finish_import( $pid, $out );
    is( $delay_status, 0, 'delayed temporary import completes cleanly' );
    my $delayed_span = $dbh->selectrow_array(
        'SELECT TIMESTAMPDIFF(SECOND, bandate, banuntil) FROM sysban WHERE note = ? AND value = ?',
        undef, $note, $delayed_second,
    );
    is( $delayed_span, 4, 'ban inserted after initial deadline still gets full duration' );
    ok( wait_for_sysban_match( "user\@$delayed_second", 3.5 ),
        'ban inserted after initial deadline takes effect in real email lookup' );
}

# Concurrent overlapping imports serialize deduplication
{
    my $dir   = tempdir( CLEANUP => 1 );
    my $fifo1 = "$dir/concurrent1.fifo";
    my $fifo2 = "$dir/concurrent2.fifo";
    mkfifo( $fifo1, 0600 ) or die "mkfifo $fifo1 failed: $!";
    mkfifo( $fifo2, 0600 ) or die "mkfifo $fifo2 failed: $!";
    sysopen( my $w1, $fifo1, O_RDWR ) or die "sysopen $fifo1 failed: $!";
    sysopen( my $w2, $fifo2, O_RDWR ) or die "sysopen $fifo2 failed: $!";

    my ( $pid1, $out1 ) = spawn_import_path( $fifo1, 0, "--note=$note" );
    my ( $pid2, $out2 ) = spawn_import_path( $fifo2, 0, "--note=$note" );
    sleep 1;

    print {$w1} "$concurrent_shared\n$concurrent_only1\n";
    close $w1;
    print {$w2} "$concurrent_shared\n$concurrent_only2\n";
    close $w2;

    my ( $st1, $log1 ) = finish_import( $pid1, $out1 );
    my ( $st2, $log2 ) = finish_import( $pid2, $out2 );
    is( $st1, 0, 'first concurrent importer succeeds' );
    is( $st2, 0, 'second concurrent importer succeeds' );

    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM sysban WHERE what = ? AND value = ?', undef,
            'email_domain',                                             $concurrent_shared,
        ),
        1,
        'concurrent overlapping imports insert shared domain only once'
    );
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM sysban WHERE what = ? AND value = ?', undef,
            'email_domain',                                             $concurrent_only1,
        ),
        1,
        'first concurrent importer inserts its unique domain'
    );
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM sysban WHERE what = ? AND value = ?', undef,
            'email_domain',                                             $concurrent_only2,
        ),
        1,
        'second concurrent importer inserts its unique domain'
    );
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM statushistory '
                . 'WHERE userid = 0 AND adminid = 0 AND shtype = ? '
                . 'AND notes LIKE ? AND notes LIKE ?',
            undef,
            'sysban_add',
            "%what=email_domain; value=$concurrent_shared;%",
            "%note=$note;%",
        ),
        1,
        'concurrent overlapping imports record only one audit row for shared domain'
    );
}

# Audit write failure: CLI reports failure, exits nonzero, and rolls back ban
{
    my ( $fixture, $path ) = tempfile( UNLINK => 1 );
    print {$fixture} "$audit_fail\n";
    close $fixture or die "Cannot close audit failure fixture: $!";

    my ( $audit_status, $audit_log ) =
        finish_import( spawn_import_path( $path, 1, "--note=$note" ) );
    isnt( $audit_status, 0, 'audit write failure returns nonzero exit status' );
    like( $audit_log, qr/audit/i, 'audit write failure is reported clearly' );
    like(
        $audit_log,
        qr/0 added, 0 duplicates, 1 rejected/,
        'failed audit is not counted as added'
    );
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM sysban WHERE what = ? AND value = ?', undef,
            'email_domain',                                             $audit_fail,
        ),
        0,
        'ban row is rolled back when audit write fails under InnoDB'
    );
}

# Audit write failure when caller holds an outer transaction: reports partial write explicitly
{
    no warnings 'redefine';
    local *LJ::statushistory_add = sub { return 0 };
    $dbh->begin_work;
    my $res = LJ::Sysban::create(
        what          => 'email_domain',
        value         => $audit_partial,
        bandays       => 0,
        note          => $note,
        noremote      => 1,
        require_audit => 1,
    );
    $dbh->rollback;
    is( ref($res), 'ERROR', 'require_audit returns ERROR when audit fails inside caller txn' );
    ok( ref($res) eq 'ERROR' && $res->{persisted}, 'partial write flags persisted ban' );
    like(
        ref($res) eq 'ERROR' ? $res->{message} : '',
        qr/persisted without statushistory/i,
        'partial write message reports un-audited ban explicitly'
    );
}

# Email domain lookup semantics (exact, multi-level subdomain, case, boundary, literal underscore)
my $underscore_id = LJ::Sysban::create(
    what     => 'email_domain',
    value    => $underscore_ban,
    bandays  => 0,
    note     => "Original $note",
    noremote => 1,
);
BAIL_OUT('Could not seed underscore domain sysban') if ref $underscore_id;

ok(
    wait_for_sysban_match( "user\@child.$last", 3 ),
    'imported bans apply to email addresses on subdomains'
);
ok( LJ::sysban_check( 'email', "user\@$last" ), 'imported bans match exact email domain' );
ok(
    LJ::sysban_check( 'email', "user\@deep.child.$last" ),
    'imported bans match multi-level subdomains'
);
ok( LJ::sysban_check( 'email', "USER\@CHILD." . uc($last) ),
    'imported bans match case-insensitively' );
ok(
    !LJ::sysban_check( 'email', "user\@not$last" ),
    'domain bans do not match non-dot-bounded suffixes'
);
ok(
    !LJ::sysban_check( 'email', "user\@other.$suffix" ),
    'unrelated sibling domains are not blocked'
);
ok(
    wait_for_sysban_match( "user\@sub.$underscore_ban", 3 ),
    'domain with underscore matches its own subdomain literally'
);
ok( !LJ::sysban_check( 'email', "user\@sub.axb.$suffix" ),
    'underscore in stored email_domain does not act as a SQL LIKE wildcard' );

# Schema index definition for indexed email-domain lookups
{
    open my $fh, '<', "$ENV{LJHOME}/bin/upgrading/update-db-general.pl"
        or die "Cannot open update-db-general.pl: $!";
    my $schema = do { local $/; <$fh> };
    close $fh;
    like(
        $schema,
        qr/CREATE TABLE sysban\b.*?INDEX\s+status_what_value\s*\(\s*status,\s*what,\s*value\s*\)/s,
        'sysban table definition includes composite (status, what, value) index'
    );
    like(
        $schema,
qr/index_name\(\s*"sysban",\s*"INDEX:status-what-value"\s*\).*?ADD INDEX status_what_value\s*\(\s*status,\s*what,\s*value\s*\)/s,
        'update-db-general.pl registers alter to add (status, what, value) index on sysban'
    );
}

done_testing;
