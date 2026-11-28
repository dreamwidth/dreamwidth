# t/tempdir-identity-nulljob.t
#
# Test temporary directory cleanup, identity access, and the import dry-run job.
#
# Authors:
#      Alex Southwell <saphid@gmail.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use Test::More;

use LJ::TempDir;
use LJ::Identity;
use DW::Importer::NullJob;

my $scalar_directory;
{
    my $guard = LJ::TempDir->new;
    $scalar_directory = $guard->directory;
    ok( -d $scalar_directory, 'scalar constructor owns a directory' );
}
ok( !-e $scalar_directory, 'directory is removed when its owner goes out of scope' );

my ( $directory, $guard ) = LJ::TempDir->new;
is( $guard->directory, $directory, 'list constructor returns the directory owned by its guard' );
mkdir "$directory/nested" or die "Cannot create nested directory: $!";
my $file = "$directory/nested/data";
open my $contents, '>', $file or die "Cannot create $file: $!";
close $contents or die "Cannot close $file: $!";
ok( -f $file, 'nested file exists while the guard is alive' );
undef $guard;
ok( !-e $directory, 'releasing the guard removes the directory and its contents' );

my $identity_url = 'https://example.org/id?name=journal%20user';
my $identity     = LJ::Identity->new( typeid => 'O', value => $identity_url );
is( $identity->typeid,      'O',           'identity preserves the supplied type code' );
is( $identity->value,       $identity_url, 'identity preserves the supplied URL verbatim' );
is( $identity->pretty_type, 'OpenID',      'the OpenID type code has a human-readable name' );

my $unknown = LJ::Identity->new( typeid => '?', value => $identity_url );
like( $unknown->pretty_type, qr/invalid .*type/i, 'an unknown type is not labeled OpenID' );

eval { $identity->typeid('?') };
like( $@, qr/Cannot set/, 'the type accessor rejects mutation' );
is( $identity->typeid, 'O', 'the rejected mutation leaves the type code unchanged' );

eval { $identity->value('https://example.org/other') };
like( $@, qr/Cannot set/, 'the value accessor rejects mutation' );
is( $identity->value, $identity_url, 'the rejected mutation leaves the URL unchanged' );

my $job       = DW::Importer::NullJob->new;
my $timestamp = time + 3600;
$job->debug('Dry-run job');
$job->grabbed_until($timestamp);
$job->run_after($timestamp);
$job->declined(1);
$job->save;

is( scalar $job->grabbed_until, undef, 'the dry run does not retain a queue lease' );
is( scalar $job->run_after,     undef, 'the dry run is not rescheduled by a delay' );
is( scalar $job->declined,      undef, 'the dry run does not record a queue decline' );
is( $job->arg,                  undef, 'the dry run has no queued payload' );
is( $job->failures,             0,     'the dry run does not count queue failures' );
is( $job->max_retries,          0,     'the dry run has no queue retries' );
is( $job->funcname, 'DW::Importer::NullJob', 'the dry run identifies itself as a stand-in' );

ok( !( grep { m{(?:^|/)ljlib\.pl\z} } keys %INC ), 'the test process did not load ljlib.pl' );

done_testing;
