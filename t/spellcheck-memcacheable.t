# t/spellcheck-memcacheable.t
#
# Test the spellchecker pipe protocol and versioned cache records without ljlib.
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
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::MemCache;
use LJ::MemCacheable;
use LJ::SpellCheck;
use LJ::TextUtil;

{

    package Local::CacheClient;

    sub set {
        my ( $self, $key, $value, $expires ) = @_;
        $self->{ $key->[1] } = [ $value, $expires ];
        return 1;
    }

    sub get {
        my ( $self, $key ) = @_;
        my $record = $self->{ $key->[1] };
        return $record ? $record->[0] : undef;
    }

    sub delete {
        my ( $self, $key ) = @_;
        return delete $self->{ $key->[1] };
    }
}

{

    package Local::CacheRecord;

    use parent 'LJ::MemCacheable';

    sub _memcache_id           { $_[0]->{id} }
    sub _memcache_key_prefix   { 'test-record' }
    sub _memcache_stored_props { ( 2, qw( id name count note ) ) }
    sub _memcache_expires      { 300 }

    sub _memcache_hashref_to_object {
        my ( $class, $fields ) = @_;
        return bless $fields, $class;
    }
}

subtest 'spellchecker pipe protocol' => sub {
    my $pipe_program = <<'PERL';
$| = 1;
alarm 15;
if ( $ARGV[0] eq 'bad-banner' ) {
    print "invalid header\n";
    exit;
}
print "\@(#) test spellchecker\n";
my $control = <STDIN>;
exit unless defined $control && $control eq "!\n";
my %responses = (
    "^correct\n"             => "*\n",
    "^<tag> wrng & tail\n"    => "& wrng 2 7: wrong, rock&roll\n",
    "^then zzzz.\n"          => "# zzzz 6\n",
);
while ( my $request = <STDIN> ) {
    exit unless exists $responses{$request};
    print "$responses{$request}\n";
}
PERL

    local $LJ::SPELLER = 1;
    my $checker = LJ::SpellCheck->new(
        { command => $^X, command_args => [ '-e', $pipe_program, 'valid-banner' ] } );
    my $correct = 'correct';
    is( $checker->check_html( \$correct ), '', 'correct text needs no markup' );

    my $misspelled = "<tag> wrng & tail\nthen zzzz.";
    my $html       = $checker->check_html( \$misspelled );
    my $text_link  = qr{<a href='#spellcheck-1-suggestion' id='spellcheck-1-text'[^>]*>wrng</a>};
    my $suggestion_link =
        qr{<a href='#spellcheck-1-text' id='spellcheck-1-suggestion'[^>]*>wrng</a>};
    my $no_suggestion = qr{then &nbsp;<span[^>]*>zzzz</span>&nbsp;\.};
    like(
        $html,
        qr{&lt;tag&gt; $text_link &amp; tail},
        'suggestion link highlights only the misspelled word at its reported offset'
    );
    like( $html, $no_suggestion,
        'a word with no suggestions is highlighted on the next line without a link' );
    like(
        $html,
        qr{$suggestion_link.*?<td>wrong, rock&amp;roll</td>},
        'the suggestions are escaped and link back to the misspelled word'
    );
    my $unknown = 'then zzzz.';
    like( $checker->check_html( \$unknown ),
        $no_suggestion, 'a misspelling is reported even when there are no suggestions at all' );
    like(
        $checker->check_html( \$misspelled, 1 ),
        qr{<tag> <a .*?</a> & tail},
        'the caller can opt out of HTML escaping'
    );

    my $bad_checker = LJ::SpellCheck->new(
        { command => $^X, command_args => [ '-e', $pipe_program, 'bad-banner' ] } );
    like(
        $bad_checker->check_html( \$correct ),
        qr/banner=invalid header/,
        'a non-ispell banner is reported as an error'
    );
    $LJ::SPELLER = 0;
    like(
        $checker->check_html( \$correct ),
        qr/not configured/,
        'a disabled spellchecker is reported as a configuration error'
    );
};

subtest 'versioned cache records' => sub {
    my $cache = bless {}, 'Local::CacheClient';
    LJ::MemCache::set_memcache($cache);

    my $record = bless { id => 'abc', name => 'sample', count => 0, private => 'not cached' },
        'Local::CacheRecord';
    my $key = [ 13604, 'test-record:abc' ];
    is_deeply( $record->_memcache_key, $key, 'a string ID uses its CRC32 routing bucket' );
    is_deeply(
        Local::CacheRecord->_memcache_key(42),
        [ 42, 'test-record:42' ],
        'a numeric ID routes directly'
    );

    ok( !defined Local::CacheRecord->_load_from_memcache('abc'),
        'a missing record is a cache miss' );
    $record->_store_to_memcache;
    is_deeply(
        $cache->{ $key->[1] },
        [ [ 2, 'abc', 'sample', 0, undef ], 300 ],
        'the stored record contains only versioned fields and the configured expiration'
    );
    my $restored = Local::CacheRecord->_load_from_memcache('abc');
    isa_ok( $restored, 'Local::CacheRecord' );
    is_deeply(
        $restored,
        bless( { id => 'abc', name => 'sample', count => 0, note => undef }, 'Local::CacheRecord' ),
        'loading preserves zero and undefined values'
    );

    $record->_remove_from_memcache;
    ok( !defined Local::CacheRecord->_load_from_memcache('abc'), 'removing a record evicts it' );
    LJ::MemCache::set( $key, [ 1, 'abc', 'stale', 0, undef ], 300 );
    ok( !defined Local::CacheRecord->_load_from_memcache('abc'),
        'a stale version is a cache miss' );
    LJ::MemCache::set( $key, { version => 2, id => 'abc' }, 300 );
    ok( !defined Local::CacheRecord->_load_from_memcache('abc'),
        'an invalid record is a cache miss' );
};

ok( !( grep { m{(?:\A|/)ljlib\.pl\z} } ( keys %INC, values %INC ) ), 'ljlib.pl was not loaded' );

done_testing();
