# Service configuration compatibility for self-hosted and AWS installations.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
# Licensed under the same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use File::Temp qw/ tempdir /;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::TaskQueue;
use DW::BlobStore::S3;
use DW::Task::SendEmail;

{
    local $LJ::TASK_QUEUE_BACKEND;
    local %LJ::SQS;
    local $LJ::IS_DEV_SERVER = 1;
    is( DW::TaskQueue->backend_name, 'localdisk', 'dev default remains local' );
    $LJ::SQS{region} = 'us-east-1';
    is( DW::TaskQueue->backend_name, 'sqs', 'SQS still wins automatic selection' );
    $LJ::IS_DEV_SERVER = 0;
    is( DW::TaskQueue->backend_name, 'sqs', 'production AWS default unchanged' );
    $LJ::TASK_QUEUE_BACKEND = 'localdisk';
    is( DW::TaskQueue->backend_name, 'localdisk', 'explicit local queue works without dev mode' );
    $LJ::TASK_QUEUE_BACKEND = 'typo';
    eval { DW::TaskQueue->backend_name };
    like( $@, qr/must be auto/, 'unknown backend rejected' );
    $LJ::TASK_QUEUE_BACKEND = 'auto';
    %LJ::SQS                = ();
    eval { DW::TaskQueue->backend_name };
    like( $@, qr/SELF-HOSTING/, 'unconfigured production gets actionable error' );
}
{
    my $dir = tempdir( CLEANUP => 1 );
    local $LJ::TASK_QUEUE_LOCAL_PATH = "$dir/nested/queue";
    my $q = DW::TaskQueue::LocalDisk->init;
    ok( -d $LJ::TASK_QUEUE_LOCAL_PATH, 'custom queue directory created' );
    $q->send( map { DW::Task::SendEmail->new( { sequence => $_ } ) } 1 .. 3 );
    is( scalar @{ $q->receive( 'DW::Task::SendEmail', 1, 0 ) }, 1, 'receive honors batch limit' );
    open my $fh, '>', "$LJ::TASK_QUEUE_LOCAL_PATH/dw-task-sendemail/.incomplete" or die $!;
    print {$fh} 'not a serialized message';
    close $fh;
    my $messages = $q->receive( 'DW::Task::SendEmail', 10, 0 );
    is( scalar @$messages, 3, 'unfinished messages invisible to consumers' );
    $q->completed( 'DW::Task::SendEmail', map { $_->[0] } @$messages );
    is( scalar @{ $q->receive( 'DW::Task::SendEmail', 10, 0 ) }, 0, 'completed messages removed' );
}
{
    local $ENV{AWS_ACCESS_KEY_ID}     = 'environment-key';
    local $ENV{AWS_SECRET_ACCESS_KEY} = 'environment-secret';
    local $ENV{AWS_ACCESS_KEY}        = 'environment-key';
    local $ENV{AWS_SECRET_KEY}        = 'environment-secret';
    my %base = ( bucket => 'media', region => 'us-east-1' );
    my $aws  = DW::BlobStore::S3->init(%base);
    isa_ok( $aws->{s3}->credentials, 'Paws::Credential::ProviderChain' );
    my $store = DW::BlobStore::S3->init(
        %base,
        endpoint      => 'http://storage:9000/',
        access_key    => 'test-key',
        secret_key    => 'test-secret',
        session_token => 'test-token',
    );
    is( $store->{s3}->endpoint->as_string, 'http://storage:9000',
        'custom endpoint passed to Paws' );
    is( $aws->{s3}->access_key,      'environment-key', 'default credential discovery preserved' );
    is( $store->{s3}->access_key,    'test-key',        'explicit access key used' );
    is( $store->{s3}->session_token, 'test-token',      'explicit session token used' );
    my %alias = DW::BlobStore::S3->validate_config( bucket_name => 'media', region => 'us-east-1' );
    is( $alias{bucket}, 'media', 'documented legacy bucket alias accepted' );

    for my $case (
        [ { %base, bucket_name => 'other' },                        qr/disagree/ ],
        [ { %base, access_key  => 'alone' },                        qr/both/ ],
        [ { %base, endpoint    => 'ftp://storage' },                qr/endpoint/ ],
        [ { %base, endpoint    => 'https://user:secret\@storage' }, qr/endpoint/ ],
        )
    {
        eval { DW::BlobStore::S3->validate_config( %{ $case->[0] } ) };
        like( $@, $case->[1], 'invalid S3 configuration rejected' );
    }
}
{
    ok( DW::Task::SendEmail->validate_config( hostname => 'relay' ),
        'unauthenticated relay allowed' );
    eval { DW::Task::SendEmail->validate_config( hostname => 'relay', username => 'alone' ) };
    like( $@, qr/both/, 'incomplete SMTP credentials rejected' );
    eval { DW::Task::SendEmail->validate_config( hostname => 'relay', port => 0 ) };
    like( $@, qr/port/, 'invalid SMTP port rejected' );
    local %LJ::SMTP_SERVER = ( hostname => 'relay', username => 'user', password => 'password' );
    my @calls;
    my $tls_ok = 0;
    no warnings qw/ redefine once /;
    local *Net::SMTP::new     = sub { bless {}, 'TestSMTP' };
    local *TestSMTP::starttls = sub { push @calls, 'starttls'; return $tls_ok };
    local *TestSMTP::auth     = sub { push @calls, 'auth'; return 0 };
    local *TestSMTP::mail     = sub { push @calls, 'mail'; return 1 };
    my $task = DW::Task::SendEmail->new( {} );
    is( $task->work('test'), DW::Task::FAILED, 'failed TLS leaves message for retry' );
    is_deeply( \@calls, ['starttls'], 'no credentials or mail sent after TLS failure' );
    local *TestSMTP::code    = sub { 535 };
    local *TestSMTP::message = sub { 'Authentication rejected' };
    $tls_ok = 1;
    @calls  = ();
    is( $task->work('test'), DW::Task::FAILED, 'authentication failure retries' );
    is_deeply( \@calls, [ 'starttls', 'auth' ], 'authenticate only after successful TLS' );
    $LJ::SMTP_SERVER{plaintext} = 1;
    @calls = ();
    is( $task->work('test'), DW::Task::FAILED, 'plaintext authentication failure retries' );
    is_deeply( \@calls, ['auth'], 'explicit plaintext relay skips STARTTLS' );
}
done_testing;
