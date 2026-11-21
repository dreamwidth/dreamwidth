# t/schwartz-stock-config.t
#
# Check that the stock TheSchwartz queue matches the global database schema.
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

use Test::More;

my $home = $ENV{LJHOME};
do "$home/etc/config-private.pl.example" or BAIL_OUT( $@ || $! );

my ( $master, $queue ) = do {
    no warnings 'once';
    ( $LJ::DBINFO{master}, $LJ::THESCHWARTZ_DBS[0] );
};
my ( $database, @options ) = split /;/, $queue->{dsn};
is( $database, "dbi:mysql:$master->{dbname}", 'the stock queue uses the global database' );
is_deeply(
    [ sort @options ],
    [ "host=$master->{host}", "port=$master->{port}" ],
    'the stock queue uses the global database host and port'
);
is( $queue->{user}, $master->{user}, 'the stock queue uses the global database user' );
is( $queue->{pass}, $master->{pass}, 'the stock queue uses the global database password' );

local $ENV{DW_TEST} = 1;
open my $updater, '-|', $^X, "$home/bin/upgrading/update-db.pl", '--cluster=0', '--listtables'
    or BAIL_OUT("Cannot run the database upgrader: $!");
chomp( my @tables = <$updater> );
close $updater or BAIL_OUT("Cannot list the global schema: exit status $?");

my %table   = map { $_ => 1 } @tables;
my $prefix  = $queue->{prefix} // '';
my @missing = grep { !$table{ $prefix . $_ } } qw(error exitstatus funcmap job note);
is_deeply( \@missing, [], 'the global upgrade schema provides all configured queue tables' );

done_testing();
