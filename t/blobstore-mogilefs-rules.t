# t/blobstore-mogilefs-rules.t
#
# Test the MogileFS adapter, default business rules, incoming mail task,
# and importer dry-run job without the application bootstrap.
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

use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use File::Temp qw/ tempdir /;
use IO::Handle ();
use Log::Log4perl qw/ :levels /;
use Test::Exception;
use Test::MockObject;
use Test::More;

BEGIN {
    my $extension_free_home = tempdir( CLEANUP => 1 );
    mkdir "$extension_free_home/ext" or die "Cannot create test extension directory: $!";

    # LJ::Directories scans LJHOME when loaded. Wait until it points to the empty
    # extension tree so ext/dw-nonfree cannot override the default business rules.
    local $ENV{LJHOME} = $extension_free_home;
    require LJ::Directories;

    # Replace the processor before the task loads it: post-by-email loads ljlib.pl.
    Test::MockObject->fake_module('DW::IncomingEmail');
}

use DW::BlobStore;

# The isolated directory setup disables BlobStore's backend discovery.
use DW::BlobStore::LocalDisk;
use DW::BlobStore::MogileFS;
use DW::BusinessRules::InviteCodeRequests;
use DW::BusinessRules::Pay;
use DW::Importer::NullJob;
use DW::InviteCodeRequests;
use DW::InviteCodes;
use DW::Task::IncomingEmail;

Log::Log4perl->easy_init($OFF);

subtest 'MogileFS writes by storage class and reads and deletes by global key' => sub {
    my $client = Test::MockObject->new;
    my %blobs;
    $client->mock(
        new_file => sub {
            my ( $client, $key, $storage_class ) = @_;
            return unless $storage_class eq 'images';
            open my $handle, '>', \$blobs{$key} or die "Cannot open in-memory blob: $!";
            return $handle;
        }
    );
    $client->mock( get_paths => sub { return exists $blobs{ $_[1] } ? ('http://storage/blob') : () }
    );
    $client->mock( get_file_data => sub { return exists $blobs{ $_[1] } ? \$blobs{ $_[1] } : undef }
    );
    $client->mock( delete => sub { return defined delete $blobs{ $_[1] } } );
    Test::MockObject->fake_module(
        'MogileFS::Client',
        new => sub {
            my ( $class, %options ) = @_;
            return $options{domain} eq 'dreamwidth' ? $client : undef;
        }
    );

    throws_ok { DW::BlobStore::MogileFS->init( domain => 'unknown' ) }
    qr/Could not initialize MogileFS/, 'a failed client constructor is rejected';

    my $store = DW::BlobStore::MogileFS->init( domain => 'dreamwidth' );
    my $key   = 'objects/example';
    my $blob  = "\x00first\r\nsecond\xff";

    throws_ok { $store->store( images => $key, \'' ) }
    qr/empty file/, 'empty writes are rejected';
    throws_ok { $store->store( unknown => $key, \$blob ) }
    qr/Failed to create file/, 'a rejected write fails instead of creating an object';
    ok( !$store->exists( images => $key ), 'failed writes did not create the key' );

    ok( $store->store( images => $key, \$blob ), 'a valid write succeeds' );
    ok( $store->exists( other => $key ), 'the key exists regardless of storage class' );
    is_deeply( $store->retrieve( other => $key ), \$blob, 'retrieval preserves the binary bytes' );
    ok( $store->delete( other => $key ),   'deletion uses the global key' );
    ok( !$store->exists( images => $key ), 'deleted key no longer exists' );
    is( $store->retrieve( images => $key ), undef, 'a missing key yields no blob' );
    ok( !$store->delete( images => $key ), 'deleting a missing key reports failure' );
};

subtest 'default invite rule requires an eligible person with no existing invites or request' =>
    sub {
    no warnings qw/ once redefine /;
    my $user = Test::MockObject->new;
    $user->set_always( id => 42 );
    $user->set_true('is_person');

    my ( %unused, %outstanding, %banned );
    local *DW::InviteCodes::unused_count = sub {
        my ( $class, %options ) = @_;
        return $unused{ $options{userid} };
    };
    local *DW::InviteCodeRequests::outstanding_count = sub {
        my ( $class, %options ) = @_;
        return $outstanding{ $options{userid} };
    };
    local *DW::InviteCodeRequests::invite_sysbanned = sub {
        my ( $class, %options ) = @_;
        return $banned{ $options{user}->id };
    };

    ok( DW::BusinessRules::InviteCodeRequests::can_request( user => $user ),
        'eligible person can request' );
    my $community = Test::MockObject->new;
    $community->set_always( id => 43 );
    $community->set_false('is_person');
    ok( !DW::BusinessRules::InviteCodeRequests::can_request( user => $community ),
        'a non-person account cannot request' );

    $unused{42} = 2;
    ok( !DW::BusinessRules::InviteCodeRequests::can_request( user => $user ),
        'unused invite codes prevent another request' );

    $unused{42}      = 0;
    $outstanding{42} = 1;
    ok( !DW::BusinessRules::InviteCodeRequests::can_request( user => $user ),
        'a pending request prevents another request' );

    $outstanding{42} = 0;
    $banned{42}      = 1;
    ok(
        !DW::BusinessRules::InviteCodeRequests::can_request( user => $user ),
        'an invite-system ban prevents a request even without invites or a pending request'
    );
    };

subtest 'default paid-time conversion adds 30-day months, days, and seconds' => sub {
    is( DW::BusinessRules::Pay::convert( 'paid', 'premium', 1, 2, 3 ),
        2_764_803, 'paid time is combined into seconds with no rate adjustment' );
    is( DW::BusinessRules::Pay::convert( undef, undef, undef, undef, 1 ),
        1, 'a single second needs neither account types nor larger units' );
    throws_ok { DW::BusinessRules::Pay::convert( 'paid', 'premium', 0, 0, 0 ) }
    qr/no amount of time/, 'a zero duration is rejected';
};

subtest 'incoming mail task passes through message bytes and distinguishes retries' => sub {
    no warnings 'once';
    local *LJ::in_test = sub { 1 };
    my @messages;
    my $accepted = 1;
    local *DW::IncomingEmail::process = sub {
        my ( $class, $raw_email ) = @_;
        push @messages, $raw_email;
        return $accepted;
    };

    my $inline = "Subject: inline\r\n\r\ninline body\r\n";
    my $stored = "Subject: stored\r\n\r\nstored body\xff\r\n";
    my $key    = 'ie:message';
    ok( DW::BlobStore->store( temp => $key, \$stored ), 'message is stored in the temp namespace' );

    is( DW::Task::IncomingEmail->new($inline)->work, DW::Task::COMPLETED, 'inline mail completes' );
    is( DW::Task::IncomingEmail->new($key)->work,    DW::Task::COMPLETED, 'stored mail completes' );

    $accepted = 0;
    is( DW::Task::IncomingEmail->new($key)->work,
        DW::Task::FAILED, 'a processing failure allows the queue to retry' );
    is( DW::Task::IncomingEmail->new('ie:missing')->work,
        DW::Task::COMPLETED, 'a missing blob is dropped rather than retried' );
    is_deeply(
        \@messages,
        [ $inline, $stored, $stored ],
        'the processor only receives available messages, with their bytes intact'
    );
};

subtest 'importer dry-run job ignores real queue operations' => sub {
    my $job = DW::Importer::NullJob->new;
    $job->debug('dry run');
    $job->grabbed_until(100);
    $job->run_after(200);
    $job->declined(1);
    $job->save;

    is( $job->arg,           undef, 'no queued job arguments' );
    is( $job->grabbed_until, undef, 'no persisted lease' );
    is( $job->run_after,     undef, 'no retry scheduled' );
    is( $job->declined,      undef, 'no recorded decline' );
    is( $job->failures,      0,     'no recorded failures' );
    is( $job->max_retries,   0,     'no retries configured' );
};

ok( !( grep { defined && m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC ) ),
    'ljlib.pl was not loaded' );
done_testing();
