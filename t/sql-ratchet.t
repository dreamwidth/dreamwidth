# t/sql-ratchet.t
#
# Ratchet against unsafe / misplaced SQL. Two rules:
#
#   1. Interpolation: SQL strings that interpolate a variable. New code must
#      build SQL through DW::SQL (values become bind parameters) or use
#      placeholders with a static string.
#
#   2. Ownership: SQL naming a table may live only in that table's owner
#      module, so queries stay next to the memcache logic that pairs with
#      them. Currently enforced for the userpic tables.
#
# Existing offenders are frozen in per-file counts (rule 1:
# t/data/sql-interpolation-allowlist.txt, rule 2: %OWNERSHIP_ALLOWLIST below).
# The counts may only go DOWN: if you removed one, update the allowlist to
# match; if this test fails with a count above the allowlist, don't raise the
# number -- rewrite the query.
#
# Run with --regen to print a fresh interpolation allowlist.

use strict;
use warnings;

use Test::More;
use File::Find ();
use FindBin qw( $Bin );

my $root  = "$Bin/..";
my $regen = grep { $_ eq '--regen' } @ARGV;

# --- Rule 2 config: table -> owner modules --------------------------------

my %TABLE_OWNERS = (
    qr/\buserpic(?:map[23]|blob2|2)\b/ => {
        name   => 'userpic tables',
        owners => {
            'cgi-bin/LJ/Userpic.pm'    => 1,
            'cgi-bin/LJ/User/Icons.pm' => 1,
        },
    },
);

# Frozen out-of-owner sites (migration/maintenance scripts and the id
# allocator). Shrink only.
my %OWNERSHIP_ALLOWLIST = (
    'bin/upgrading/migrate-userpics.pl'       => 7,
    'cgi-bin/DW/User/DVersion/Migrate8To9.pm' => 3,
    'cgi-bin/LJ/DB.pm'                        => 2,
);

# --- Scanner ----------------------------------------------------------------

my $dbi_call = qr/->\s*(?:do|prepare(?:_cached)?|select(?:row|all|col)_\w+)\s*\(/;
my $sql_verb = qr/\b(?:SELECT|INSERT|UPDATE|DELETE|REPLACE)\b/;

my ( %interp_count, %ownership_count );

sub scan_file {
    my ($path) = @_;
    my $rel = $path;
    $rel =~ s{^\Q$root\E/}{};

    open my $fh, '<', $path or die "open $path: $!";
    while ( my $line = <$fh> ) {

        # Rule 1: a double-quoted string that is SQL and interpolates a
        # variable, either at a DBI call site or being assembled nearby.
        # Heuristic by design; it only needs to be deterministic so the
        # ratchet counts are stable.
        my $interpolated = 0;
        while ( $line =~ /"([^"]*)"/g ) {
            my $str = $1;
            next unless $str =~ $sql_verb || $line =~ $dbi_call;
            next unless $str =~ /[\$\@]\w/;
            next unless $str =~ $sql_verb || $str =~ /\b(?:WHERE|FROM|INTO|SET|VALUES)\b/i;
            $interpolated = 1;
        }
        $interp_count{$rel}++ if $interpolated;

        # Rule 2: SQL touching an owned table.
        for my $table_re ( keys %TABLE_OWNERS ) {
            $ownership_count{$table_re}{$rel}++
                if $line =~ /\b(?:FROM|INTO|UPDATE|JOIN|DELETE\s+FROM)\s+$table_re/;
        }
    }
    close $fh;
}

File::Find::find(
    {
        no_chdir => 1,
        wanted   => sub {
            return unless -f && /\.(?:pm|pl)$/;
            scan_file($File::Find::name);
        },
    },
    "$root/cgi-bin",
    "$root/bin",
);

# --- Regen mode -------------------------------------------------------------

if ($regen) {
    print "$_\t$interp_count{$_}\n" for sort keys %interp_count;
    exit 0;
}

# --- Rule 1: compare against allowlist ---------------------------------------

my %allowed;
{
    open my $fh, '<', "$Bin/data/sql-interpolation-allowlist.txt"
        or die "missing allowlist: $!";
    while (<$fh>) {
        chomp;
        next if /^#/ || /^\s*$/;
        my ( $file, $count ) = split /\t/;
        $allowed{$file} = $count;
    }
    close $fh;
}

for my $file ( sort keys %interp_count ) {
    my $have = $interp_count{$file};
    my $ok   = $allowed{$file} // 0;
    cmp_ok( $have, '<=', $ok,
        "$file: interpolated SQL sites ($have) within allowlist ($ok)"
            . ( $have > $ok ? " -- use DW::SQL or placeholders" : "" ) );
}
for my $file ( sort keys %allowed ) {
    my $have = $interp_count{$file} // 0;
    is( $have, $allowed{$file},
              "$file: allowlist is current (have $have, listed $allowed{$file})"
            . " -- ratchet the allowlist down" )
        if $have < $allowed{$file};
}

# --- Rule 2: ownership --------------------------------------------------------

for my $table_re ( keys %TABLE_OWNERS ) {
    my $conf = $TABLE_OWNERS{$table_re};
    for my $file ( sort keys %{ $ownership_count{$table_re} } ) {
        next if $conf->{owners}{$file};
        my $have = $ownership_count{$table_re}{$file};
        my $ok   = $OWNERSHIP_ALLOWLIST{$file} // 0;
        cmp_ok( $have, '<=', $ok,
            "$file: SQL against $conf->{name} ($have) within allowlist ($ok)"
                . ( $have > $ok ? " -- move the query into an owner module" : "" ) );
    }
}

done_testing();
