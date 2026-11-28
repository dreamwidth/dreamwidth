# t/console-sysban-history.t
#
# Test read-only sysban history lookup through the console.
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
use LJ::Console;
use LJ::Test qw(temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $operator = temp_user();
my $value    = 'sysban-history-' . $operator->id . '.example.invalid';
my $lookup   = 'sysban_history ' . $value;
my $run      = sub { LJ::Console->run_commands_text(shift) };
my $dbh      = LJ::get_db_writer();
my @ids;

END {
    $dbh->do( 'DELETE FROM sysban WHERE banid IN (' . join( ',', ('?') x @ids ) . ')', undef, @ids )
        if $dbh && @ids;
}
LJ::set_remote(undef);
is( $run->($lookup), 'error: You must be logged in to run this command.', 'requires login' );
LJ::set_remote($operator);
is( $run->($lookup), 'error: You are not authorized to run this command.', 'requires privilege' );
$operator->grant_priv( 'sysban', 'email_domain' );
is(
    $run->($lookup),
    'error: You are not authorized to run this command.',
    'a type-specific sysban privilege does not grant all history'
);
$operator->grant_priv( 'sysban', '*' );
is(
    $run->('sysban_history'),
    'error: This command takes exactly one argument. Consult the reference.',
    'requires a value'
);
is(
    $run->( $lookup . ' extra' ),
    'error: This command takes exactly one argument. Consult the reference.',
    'rejects extra arguments'
);
is( $run->($lookup), 'info: No sysban history found for ' . $value . '.', 'no matching records' );

my $add = sub {
    my ( $what, $val, $until, $note, $status, $future ) = @_;
    $dbh->do(
"INSERT INTO sysban (what,value,bandate,banuntil,note,status) VALUES (?,?,?,FROM_UNIXTIME(?),?,?)",
        undef,
        $what,
        $val,
        $future ? '2100-01-01 00:00:00' : '2000-01-01 00:00:00',
        $until,
        $note,
        $status || 'active'
    );
    die $dbh->errstr if $dbh->err;
    push @ids, $dbh->{mysql_insertid};
};
$add->( 'email_domain', $value,            1893456000, 'current fixture' );
$add->( 'email_domain', $value,            946684800,  'expired fixture' );
$add->( 'email_domain', $value,            undef,      'permanent fixture' );
$add->( 'talk_ip_test', $value,            1893456000, 'another type fixture' );
$add->( 'unknown_type', $value,            undef,      'unknown type fixture' );
$add->( 'email_domain', 'other-' . $value, undef,      'other value fixture' );
$add->( 'email_domain', $value,            undef,      'revoked fixture', 'expired' );
$add->( 'email_domain', $value,            undef,      'future fixture', 'active', 1 );
my $snapshot = sub {
    $dbh->selectall_arrayref( 'SELECT * FROM sysban WHERE value=? ORDER BY banid', undef, $value );
};
my $before = $snapshot->();
my $result = $run->($lookup);
like(
    $result,
    qr/Type: email_domain; Expires: 2030-01-01 00:00:00 UTC; Note: current fixture/,
    'current ban appears with UTC expiration'
);
like(
    $result,
    qr/Type: email_domain; Expires: 2000-01-01 00:00:00 UTC; Note: expired fixture/,
    'expired ban is included'
);
like(
    $result,
    qr/Type: email_domain; Expires: never; Note: permanent fixture/,
    'permanent ban has no expiration'
);
like(
    $result,
    qr/Type: talk_ip_test; .*Note: another type fixture/,
    'all valid ban types are included'
);
unlike( $result, qr/unknown type fixture/, 'unknown types match the admin page filtering' );
unlike( $result, qr/other value fixture/,  'lookup matches the exact value' );
unlike( $result, qr/revoked fixture/,      'inactive rows match the admin page filtering' );
unlike( $result, qr/future fixture/,       'future rows match the admin page filtering' );
is_deeply( $snapshot->(), $before, 'lookup changes no sysban data' );
my @notes = $result =~ /Note: ([^\n]+)/g;
is_deeply(
    \@notes,
    [ 'current fixture', 'expired fixture', 'permanent fixture', 'another type fixture' ],
    'results are ordered by type and ban id'
);

my $quoted = "quote'value.example.invalid";
$add->( 'email_domain', $quoted, undef, 'quoted value fixture' );
like(
    $run->( 'sysban_history "' . $quoted . '"' ),
    qr/Note: quoted value fixture/,
    'quoted input is passed as a bound value'
);
LJ::set_remote(undef);
done_testing;
