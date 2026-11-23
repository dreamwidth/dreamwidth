# t/s2-comment-icon-links.t
#
# Test S2 links on entry and comment icons.
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
use HTML::Parser;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use S2;
use S2::Compiler;

sub read_style {
    my ($file) = @_;
    open my $source, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$source>;
}

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-comment-icon-links');

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

my ($dawn_flush) = read_style('compartmentalize/themes.s2') =~
    /^#NEWLAYER: compartmentalize\/dawnflush\n(.*?)(?=^#NEWLAYER:|\z)/ms;
BAIL_OUT('Dawn Flush is missing') unless defined $dawn_flush;

load_style_layer( 1, 'core', read_style('core2.s2') );
load_style_layer( 2, 'layout',
    read_style('core2base/layout.s2') . read_style('compartmentalize/layout.s2') );
load_style_layer( 3, 'theme', $dawn_flush );
load_style_layer( 4, 'user',  'layerinfo type = "user"; set use_shared_pic = true;' );

my $journal_icons = 'https://journal.example/icons';
my $poster_icons  = 'https://poster.example/icons';
my $guest_icons   = 'https://guest.example/icons';
my $poster_image  = 'https://images.example/poster.png';
my $guest_image   = 'https://images.example/guest.png';
my $journal_image = 'https://images.example/journal.png';

sub links_on_icon {
    my ( $ctx, $type, $poster, $image ) = @_;
    my $html = '';
    local $S2::pout   = sub { $html .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code(
        $ctx,
        "${type}::print_userpic()",
        {
            _type   => $type,
            journal => { userpic_listing_url => $journal_icons },
            poster  => { userpic_listing_url => $poster },
            userpic => $image
                && { _type => 'Image',
                url     => $image,
                width   => 100,
                height  => 100,
                alttext => '',
                extra   => { title => '' }
                },
        }
    );

    my ( @links, $href );
    my $parser = HTML::Parser->new(
        api_version => 3,
        start_h     => [
            sub {
                my ( $tag, $attr ) = @_;
                $href = $attr->{href} if $tag eq 'a';
                push @links, [ $attr->{src}, $href ] if $tag eq 'img';
            },
            'tagname,attr'
        ],
        end_h => [ sub { undef $href if $_[0] eq 'a' }, 'tagname' ],
    );
    $parser->parse($html)->eof;
    return \@links;
}

my $default = S2::make_context( 1, 2, 3 );
my $shared  = S2::make_context( 1, 2, 3, 4 );

for my $style ( [ $default, 'default' ], [ $shared, 'shared icons enabled' ] ) {
    my ( $ctx, $name ) = @$style;
    is_deeply(
        links_on_icon( $ctx, 'Comment', $poster_icons, $poster_image ),
        [ [ $poster_image, $poster_icons ] ],
        "$name: comment icon links to its author"
    );
    is_deeply(
        links_on_icon( $ctx, 'Comment', $guest_icons, $guest_image ),
        [ [ $guest_image, $guest_icons ] ],
        "$name: another author's icon has its own link"
    );
}

is_deeply(
    links_on_icon( $default, 'Entry', $poster_icons, $poster_image ),
    [ [ $poster_image, $poster_icons ] ],
    'default: entry icon links to the poster'
);
is_deeply(
    links_on_icon( $shared, 'Entry', $poster_icons, $journal_image ),
    [ [ $journal_image, $journal_icons ] ],
    'shared icons enabled: entry icon links to the journal'
);
is_deeply( links_on_icon( $shared, 'Comment', $poster_icons, undef ),
    [], 'shared icons enabled: no image is rendered for an iconless comment' );

my $user = bless { userid => 1, user => 'testjournal', journaltype => 'P', statusvis => 'V' },
    'LJ::User';
my $journal = { _type => 'UserLite', _u => $user, username => 'testjournal', journal_type => 'P' };
my $page      = { _type => 'RecentPage', view => 'recent', journal => $journal, _u => $user };
my $entry_url = 'https://testjournal.example/1.html';
my $target    = 'entry-testjournal-1-reply';

sub render_recent_entry {
    my ( $count, $layout_id ) = @_;
    my $ctx   = S2::make_context( 1, $layout_id );
    my $entry = {
        _type         => 'Entry',
        itemid        => 1,
        dom_id        => 'entry-testjournal-1',
        journal       => $journal,
        poster        => $journal,
        subject       => 'An example entry',
        permalink_url => $entry_url,
        text          => 'Entry body goes here.',
        time          => LJ::S2::DateTime_unix(1_799_999_999),
        comments      => LJ::S2::CommentInfo(
            {
                count                => $count,
                enabled              => 1,
                read_url             => $entry_url,
                post_url             => "$entry_url?mode=reply",
                show_readlink        => $count > 0,
                show_readlink_hidden => 1,
                show_postlink        => 1,
            }
        ),
    };

    my $html = '';
    local $LJ::S2::CURR_PAGE = $page;
    local $S2::pout          = sub {
        $html .= join '', grep { defined } @_;
    };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'Page::print_entry(Entry)', $page, $entry );
    return $html;
}

for my $layout (qw(zesty negatives database)) {
    subtest "$layout recent entry quick reply" => sub {
        $compiler = S2::Compiler->new( {} );
        S2::set_domain("test-quick-reply-$layout");
        load_style_layer( 1, 'core', read_style('core2.s2') );
        load_style_layer( 2, 'layout',
            read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );

        for my $count ( 0, 1, 2, 4 ) {
            my $html = render_recent_entry( $count, 2 );
            like(
                $html,
                qr{data-quickreply-container="\Q$target\E"},
                "$count comments: reply form has the entry target"
            );
            like(
                $html,
                qr{quickreply\("\Q$target\E",},
                "$count comments: reply link opens that target"
            );
            my ( $wrapper, $anchor, $text ) =
                $html =~ m{data-quickreply-target="\Q$target\E"[^>]*>.*?
                   <(?:li|span)\s+class="entry-readlink"([^>]*)>\s*<a\b([^>]*)>(.*?)</a>}sx;
            ok( defined $anchor, "$count comments: target contains a comment link" );
            next unless defined $anchor;
            is(
                ( $wrapper =~ /display:\s*none/ ? 1 : 0 ),
                ( $count == 0                   ? 1 : 0 ),
                "$count comments: comment link is hidden only at zero"
            );
            like(
                $anchor,
                qr{href="\Q$entry_url\E(?:\#comments)?"},
                "$count comments: comment link leads to the entry"
            );

            my %attributes = $anchor =~ /([\w-]+)="([^"]*)"/g;
            if ( $layout eq 'zesty' ) {
                is_deeply(
                    [ @attributes{qw(data-sing data-dual data-plur)} ],
                    [
                        'There is 1 comment on this entry.',
                        'There are 2 comments on this entry.',
                        'There are 3 comments on this entry.'
                    ],
                    "$count comments: quick reply has singular, dual and plural sentences"
                );
                if ($count) {
                    like(
                        $text,
                        qr{\b$count comments? on this entry},
                        "$count comments: rendered count matches the entry"
                    );
                    unlike(
                        $html,
                        qr/There are no comments on this entry/,
                        "$count comments: no empty-state message"
                    );
                }
                else {
                    like(
                        $html,
                        qr{</a>\s*</span>\s*<span class="entry-readlink-empty">[^<]*no comments},
                        'zero comments: the empty-state message follows the hidden link wrapper'
                    );
                }
            }
            elsif ( $layout eq 'negatives' ) {
                is_deeply(
                    [ @attributes{qw(data-sing data-dual data-plur)} ],
                    [ '1 comment', '2 comments', '3 comments' ],
                    "$count comments: quick reply has singular, dual and plural counts"
                );
            }
            else {
                like( $text, qr{^$count\s+<img\b}, "$count comments: count still uses an icon" );
            }
        }
    };
}

done_testing;
