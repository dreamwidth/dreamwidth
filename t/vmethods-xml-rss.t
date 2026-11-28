#!/usr/bin/perl
#
# t/vmethods-xml-rss.t
#
# Standalone tests for template list sorting and XML and RSS parsing.
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
use lib "$ENV{LJHOME}/cgi-bin";

use Test::More;
use Template;
use DW::Template::VMethods;
use DW::XML::Parser;
use DW::XML::RSS;

sub check_external_entity_handlers {
    my ( $parser, $label ) = @_;
    my %handlers = $parser->setHandlers( ExternEnt => undef, ExternEntFin => undef );

    for my $event (qw(ExternEnt ExternEntFin)) {
        my $result = eval { $handlers{$event}->() };
        is( $result, '', "$label $event callback returns no data" );
    }
}

subtest 'sort_by_key in a template' => sub {
    my $template = Template->new;
    my $records  = [
        { title => 'delta',   sequence => '3',  order => 0 },
        { title => 'bravo',   sequence => '10', order => 0 },
        { title => 'charlie', sequence => '2',  order => 0 },
        { title => 'alpha',   sequence => '11' },
    ];
    my @cases = (
        [ "'sequence'",            'bravo,alpha,charlie,delta', 'sorts as strings by default' ],
        [ "'sequence', 'numeric'", 'charlie,delta,bravo,alpha', 'sorts numerically on request' ],
        [ "'title', 'order'", 'alpha,bravo,charlie,delta', 'breaks order ties alphabetically' ],
        [
            "'sequence', 'order', 'numeric'",
            'charlie,delta,bravo,alpha',
            'breaks order ties numerically on request'
        ],
        [ "'title', 'unknown'", 'delta,bravo,charlie,alpha', 'ignores an unknown sort type' ],
        [
            "'title', 'order', 'unknown'",
            'delta,bravo,charlie,alpha',
            'ignores an unknown tie-breaking type'
        ],
    );

    for my $case (@cases) {
        my ( $arguments, $expected, $description ) = @$case;
        my $source = "[% FOREACH record IN records.sort_by_key($arguments) %]"
            . "[% record.title %][% ',' UNLESS loop.last %][% END %]";
        my $output = '';
        if ( $template->process( \$source, { records => $records }, \$output ) ) {
            is( $output, $expected, $description );
        }
        else {
            fail($description);
            diag( $template->error );
        }
    }
};

subtest 'XML parser events and malformed input' => sub {
    my ( @elements, $text );
    my $parser = DW::XML::Parser->new(
        Namespaces => 1,
        Handlers   => {
            Start => sub {
                my ( $expat, $name, %attributes ) = @_;
                push @elements, [ $name, $expat->namespace($name), $attributes{id} ];
            },
            Char => sub { $text .= $_[1]; },
        },
    );

    $parser->parse('<root xmlns:d="urn:dreamwidth:test"><d:item id="42">A &amp; B</d:item></root>');
    is_deeply(
        \@elements,
        [ [ 'root', undef, undef ], [ 'item', 'urn:dreamwidth:test', '42' ] ],
        'delivers local names, namespace URIs, and attributes to the start handler'
    );
    is( $text, 'A & B', 'delivers decoded character data to the text handler' );

    eval { DW::XML::Parser->new->parse('<root><item></root>'); };
    like( $@, qr/mismatched tag/i, 'rejects mismatched element tags' );
};

subtest 'RSS channel and item data' => sub {
    my $feed = <<'RSS';
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Notes &amp; News</title>
    <link>https://example.org/</link>
    <description>Updates</description>
    <item>
      <title>First entry</title>
      <link>https://example.org/first</link>
      <description><![CDATA[<p>First & latest</p>]]></description>
    </item>
    <item>
      <title>Caf&#233;</title>
      <link>https://example.org/second</link>
    </item>
  </channel>
</rss>
RSS

    my $rss = DW::XML::RSS->new;
    $rss->parse($feed);
    is( $rss->channel('title'), 'Notes & News', 'decodes the channel title' );
    is_deeply(
        [ map { [ $_->{title}, $_->{link} ] } @{ $rss->{items} } ],
        [
            [ 'First entry', 'https://example.org/first' ],
            [ "Caf\x{e9}",   'https://example.org/second' ]
        ],
        'preserves item order, links, and Unicode titles'
    );
    is( $rss->{items}[0]{description}, '<p>First & latest</p>', 'preserves CDATA in descriptions' );

    eval { DW::XML::RSS->new->parse('<rss version="2.0"><channel><title>Unfinished'); };
    like( $@, qr/no element found/i, 'rejects a truncated feed' );
};

subtest 'external entity policy without resource access' => sub {
    check_external_entity_handlers( DW::XML::Parser->new, 'XML' );

    my $rss_parser = DW::XML::RSS->new->_get_parser;
    isa_ok( $rss_parser, 'DW::XML::Parser', 'RSS parser' );
    ok( $rss_parser->{NoExpand}, 'RSS enables NoExpand' );
    is( $rss_parser->{ParseParamEnt}, 0, 'RSS disables parsing parameter entities' );
    check_external_entity_handlers( $rss_parser, 'RSS' );
};

ok( !( grep { m{(?:\A|/)ljlib\.pl\z} } keys %INC ), 'did not load ljlib.pl' );

done_testing;
