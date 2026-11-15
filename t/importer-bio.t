# t/importer-bio.t
#
# Tests the LiveJournal bio import job end to end against a canned remote site.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use HTTP::Response;
use File::Path qw( remove_tree );
use LJ::Test qw( temp_user );

use DW::Worker::ContentImporter::LiveJournal::Bio;

my $class = 'DW::Worker::ContentImporter::LiveJournal::Bio';

# the remote site, keyed by the exact URL asked for; anything else is a 404
my %remote;
my @asked;
{

    package Test::CannedUA;
    sub new { return bless {}, shift }

    sub get {
        my ( $self, $url ) = @_;
        push @asked, $url;
        my $body = $remote{$url};
        return HTTP::Response->new( 404, 'Not Found' ) unless defined $body;
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content($body);
        return $r;
    }
}
{
    no warnings 'redefine';
    *LJ::get_useragent = sub { return Test::CannedUA->new };
}

# just enough of a TheSchwartz job to see how the job ended
{

    package Test::FakeJob;
    sub new { my ( $class, %args ) = @_; return bless { result => undef, %args }, $class }
    sub arg               { $_[0]->{arg} }
    sub failures          { 0 }
    sub funcname          { 'DW::Worker::ContentImporter::LiveJournal::Bio' }
    sub debug             { }
    sub completed         { $_[0]->{result} = 'completed' }
    sub failed            { $_[0]->{result} = 'failed: ' . $_[1] }
    sub permanent_failure { $_[0]->{result} = 'permanent: ' . $_[1] }
}

my $u = temp_user();
$remote{'http://some-user.remote.example/data/foaf'} = q{<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:ya="http://blogs.yandex.ru/schema/foaf/">
<foaf:Person><foaf:name>Some User</foaf:name><ya:bio>Imported from afar</ya:bio><foaf:interest dc:title="knitting"/></foaf:Person>
</rdf:RDF>};

LJ::get_db_writer()->do(
    'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) '
        . 'VALUES (?, 1, ?, ?, ?)',
    undef, $u->id, 'remote.example', 'some_user', 'x'
);

my $job = Test::FakeJob->new( arg => { userid => $u->id, import_data_id => 1 } );
$class->work($job);

is( $job->{result}, 'completed', 'the job completes' ) or diag("@asked");

# the job works on its own copy of the user, so look at the saved state
my $saved = LJ::load_userid( $u->id, 'force' );
is( $saved->bio, 'Imported from afar', 'the remote bio is saved' );
is_deeply( [ keys %{ $saved->interests } ], ['knitting'], 'and the remote interests' );
is_deeply(
    \@asked,
    ['http://some-user.remote.example/data/foaf'],
    'the profile was fetched from the user\'s journal, once'
);

remove_tree( "$LJ::HOME/logs/imports/" . $u->id );
done_testing();
