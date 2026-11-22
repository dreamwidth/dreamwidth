# t/s2-entry-tags-position.t
#
# Test where Core2 renders entry tags.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use S2;
use S2::Compiler;

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-entry-tags-position');

sub load_style_layer {
    my ( $id, $type, $source ) = @_;
    my $compiled;
    $compiler->compile_source(
        {
            type           => $type,
            source         => \$source,
            output         => \$compiled,
            layerid        => $id,
            builtinPackage => 'S2::Builtin::LJ',
        }
    );
    S2::load_layer( $id, $compiled, 0 );
}

my $core = do {
    open my $source, '<', "$ENV{LJHOME}/styles/core2.s2" or die "Cannot open core2.s2: $!";
    local $/;
    <$source>;
};
load_style_layer( 1, 'core', $core );

my $user = bless { userid => 1, user => 'testjournal', journaltype => 'P', statusvis => 'V' },
    'LJ::User';
my $journal = { _type => 'UserLite', _u => $user, username => 'testjournal', journal_type => 'P' };
my $tag_url = 'https://testjournal.example/tag/example';
my $entry   = {
    _type         => 'Entry',
    itemid        => 1,
    journal       => $journal,
    poster        => $journal,
    subject       => 'An example entry',
    permalink_url => 'https://testjournal.example/1.html',
    text          => 'Entry body goes here.',
    time          => LJ::S2::DateTime_unix(1_799_999_999),
    metadata      => { location => 'At home' },
    tags          => [ { _type => 'Tag', name => 'example', url => $tag_url } ],
    comments      => LJ::S2::CommentInfo( { count => 0 } ),
};
my $preview = {
    _type             => 'EntryPreviewPage',
    view              => 'entry',
    journal           => $journal,
    preview_warn_text => 'Preview only',
};
my $month = {
    _type    => 'MonthPage',
    view     => 'month',
    journal  => $journal,
    prev_url => '',
    next_url => '',
    months   => [],
    redir    => {
        _type => 'Redirector',
        type  => 'month',
        user  => 'testjournal',
        vhost => '',
        url   => '/go'
    },
    days => [
        { _type => 'MonthDay', has_entries => 1, day => 15, url => '/day', entries => [$entry] }
    ],
};

sub render {
    my ( $ctx, $method, $page, @args ) = @_;
    my $html = '';
    local $LJ::S2::CURR_PAGE = $page;
    local $S2::pout          = sub { $html .= join '', @_ };
    local $S2::pout_s        = $S2::pout;
    S2::run_code( $ctx, $method, $page, @args );
    return $html;
}

sub entry_sections {
    my ($html) = @_;
    return [
        $html =~ /<div class="(tag|entry-content|metadata (?:top|bottom)-metadata|footer)">/g
    ];
}

my $default = S2::make_context(1);
is( S2::get_property_value( $default, 'entry_tags_position' ), 'bottom', 'tags default to bottom' );
my $default_entry    = render( $default, 'Page::print_entry(Entry)', $preview, $entry );
my $body_html        = '<div class="entry-content">Entry body goes here.</div>';
my $footer_with_tags = qr{<div class="footer">\s*<div class="inner">\s*<div class="tag">};
like(
    $default_entry,
    qr{\Q$body_html\E.*$footer_with_tags}s,
    'the default renders tags in the footer after the entry text'
);

my $default_month = render( $default, 'MonthPage::print_body()', $month );
like(
    $default_month,
    qr{<dd>.*<a rel="tag" href="\Q$tag_url\E">example</a>.*</dd>}s,
    'the month overview renders the entry tag link inside the day summary'
);

load_style_layer( 2, 'user', 'layerinfo type = "user"; set entry_tags_position = "top";' );
load_style_layer( 3, 'user', 'layerinfo type = "user"; set entry_metadata_position = "top";' );
my $top       = S2::make_context( 1, 2 );
my $top_entry = render( $top, 'Page::print_entry(Entry)', $preview, $entry );
is_deeply(
    entry_sections($top_entry),
    [ 'tag', 'entry-content', 'metadata bottom-metadata', 'footer' ],
    'top tags appear once, before the entry text with metadata below it'
);
my $top_metadata =
    render( S2::make_context( 1, 2, 3 ), 'Page::print_entry(Entry)', $preview, $entry );
is_deeply(
    entry_sections($top_metadata),
    [ 'tag', 'metadata top-metadata', 'entry-content', 'footer' ],
    'top tags appear once, before both top metadata and entry text'
);

is( render( $top, 'MonthPage::print_body()', $month ),
    $default_month, 'placing tags above entry text does not change the month overview' );

load_style_layer( 4, 'user', 'layerinfo type = "user"; set entry_tags_position = "unexpected";' );
is( render( S2::make_context( 1, 4 ), 'Page::print_entry(Entry)', $preview, $entry ),
    $default_entry, 'an unexpected position leaves tags in the footer' );

done_testing;
