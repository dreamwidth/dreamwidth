# t/search-enrich.t
#
# Tests for search results that outlive the indexed comment's visibility.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use File::Temp qw( tempdir );
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Search;
use LJ::Talk;
use LJ::Test qw( temp_user );

$LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

{

    package SearchSnippetDB;

    sub new { return bless {}, shift }
    sub err { return 0 }

    sub selectall_arrayref {
        my ( $self, $sql, $attrs, @binds ) = @_;
        die 'Expected a Manticore SNIPPETS request' unless $sql =~ /\ACALL SNIPPETS\(/;
        splice @binds, -2;
        return [ map { [$_] } @binds ];
    }
}

my $owner   = temp_user();
my $reader  = temp_user();
my $poster  = temp_user();
my $entry   = $owner->t_post_fake_entry( body => 'a public entry' );
my $removed = $owner->t_post_fake_entry( body => 'an entry later purged' );

END { LJ::delete_entry( $owner, $entry->jitemid ) if $entry; }

my $live      = $entry->t_enter_comment( body => 'a visible comment about kangaroos' );
my $html_only = $entry->t_enter_comment( body => '<hr />' );
my $deleted   = $entry->t_enter_comment( body => 'a deleted comment about kangaroos' );
my $screened  = $entry->t_enter_comment( body => 'a screened comment about kangaroos' );
my $suspended =
    $entry->t_enter_comment( u => $poster, body => 'a suspended comment about kangaroos' );
my $purged = $removed->t_enter_comment( body => 'a purged comment about kangaroos' );

my @stale_hits =
    map { { journalid => $owner->id, jitemid => $_->entry->jitemid, jtalkid => $_->jtalkid, } }
    ( $live, $html_only, $deleted, $screened, $suspended, $purged );

ok( $deleted->delete, 'delete the indexed comment' );
LJ::Talk::screen_comment( $owner, $entry->jitemid, $screened->jtalkid );
$poster->set_statusvis('S');
ok( LJ::delete_entry( $owner, $removed->jitemid ), 'purge the other entry and its comments' );

LJ::start_request();

sub excerpts_for {
    my ($viewer) = @_;
    my $result = DW::Search::_enrich_journal(
        { query => 'kangaroos', remoteid => $viewer->id, _dbh => SearchSnippetDB->new },
        { total => scalar @stale_hits, matches => [ map { +{%$_} } @stale_hits ] },
    );
    return { map { $_->{jtalkid} => $_->{excerpt} } @{ $result->{matches} } };
}

my $excerpts = excerpts_for($reader);
ok( !exists $excerpts->{ $deleted->jtalkid }, 'a reader does not see a deleted comment' );
like(
    $excerpts->{ $live->jtalkid },
    qr/visible comment about kangaroos/,
    'a live comment still shows its excerpt'
);
like(
    $excerpts->{ $html_only->jtalkid },
    qr/only contains html content/i,
    'a live HTML-only comment keeps its placeholder'
);
ok( !exists $excerpts->{ $screened->jtalkid },  'a reader does not see a screened comment' );
ok( !exists $excerpts->{ $suspended->jtalkid }, 'a reader does not see a suspended comment' );
ok( !exists $excerpts->{ $purged->jtalkid },    'a reader does not see a purged comment' );

my $owner_excerpts = excerpts_for($owner);
ok( !exists $owner_excerpts->{ $deleted->jtalkid }, 'the owner does not see a deleted comment' );
like(
    $owner_excerpts->{ $screened->jtalkid },
    qr/screened comment about kangaroos/,
    'the journal owner still sees a screened comment'
);

done_testing();
