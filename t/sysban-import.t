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

use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;

my $suffix    = "sysban-import-$$.test";
my $existing  = "existing.$suffix";
my $new       = "new.$suffix";
my $last      = "last.$suffix";
my $temporary = "temporary.$suffix";
my $site      = "site.$suffix";
my $note      = "Import test $$";
my $dbh       = LJ::get_db_writer();

END {
    $dbh->do( "DELETE FROM sysban WHERE note IN (?, ?)", undef, $note, "Original $note" )
        if $dbh;
}

sub import_domains {
    my ( $lines,   @options ) = @_;
    my ( $fixture, $path )    = tempfile( UNLINK => 1 );
    print {$fixture} $lines;
    close $fixture or die "Cannot close import fixture: $!";

    my $pid = open3(
        my $input, my $output, undef, $^X, '-e',
        q{
            BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
            local $LJ::DOMAIN = shift @ARGV;
            $0 = shift @ARGV;
            do $0;
            die $@ if $@;
            die $! if $!;
        },
        '--', $site, "$ENV{LJHOME}/bin/ljsysban.pl", "--import-email-domains=$path", @options,
    );
    close $input;
    my $log = do { local $/; <$output> };
    close $output;
    waitpid $pid, 0;
    return ( $? >> 8, $log );
}

my $original = LJ::Sysban::create(
    what     => 'email_domain',
    value    => $existing,
    bandays  => 0,
    note     => "Original $note",
    noremote => 1,
);
BAIL_OUT('Could not seed existing domain sysban') if ref $original;

my ( $status, $log ) =
    import_domains( "$new\n", '--add', '--what=ip', "--value=$new", "--note=$note" );
isnt( $status, 0, 'import cannot be combined with a different sysban action' );
( $status, $log ) = import_domains("$new\n");
isnt( $status, 0, 'a shell operator must supply an audit note' );
is( $dbh->selectrow_array( 'SELECT COUNT(*) FROM sysban WHERE value = ?', undef, $new ),
    0, 'rejected invocations did not write any bans' );

my $uppercase = uc $new;
my $oversize  = ( 'a' x 63 ) . ".$suffix";
( $status, $log ) = import_domains(
"# reviewed list\r\n $uppercase \r\n\n$new\n$existing\n*.bad.$suffix\n$site\n$suffix\n$oversize\n$last",
    "--note=$note",
);
isnt( $status, 0, 'mixed results return failure so an operator sees rejected lines' );
like( $log, qr/line 6:.*invalid/i,   'wildcards are rejected with a line number' );
like( $log, qr/line 7:.*protected/i, 'the configured site domain is protected' );
like( $log, qr/line 8:.*protected/i, 'parent domains of the site are also protected' );
like( $log, qr/line 9:.*invalid/i,   'domains too long for sysban storage are rejected' );

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

( $status, $log ) = import_domains( "$new\n$last\n", "--note=$note" );
is( $status, 0, 'a valid repeat import succeeds' );
is( $dbh->selectrow_array( 'SELECT COUNT(*) FROM sysban WHERE note = ?', undef, $note ),
    2, 'repeat import does not add duplicate rows' );

( $status, $log ) = import_domains( "$temporary\n", "--note=$note", '--banlength=1h' );
is( $status, 0, 'import accepts a ban duration' );
my $remaining = $dbh->selectrow_array(
    'SELECT TIMESTAMPDIFF(SECOND, NOW(), banuntil) FROM sysban WHERE note = ? AND value = ?',
    undef, $note, $temporary, );
ok( defined $remaining && $remaining > 3500 && $remaining <= 3600,
    'temporary ban expires in an hour' );

sleep 1;
ok(
    LJ::sysban_check( 'email', "user\@child.$last" ),
    'imported bans apply to email addresses on subdomains'
);

done_testing;
