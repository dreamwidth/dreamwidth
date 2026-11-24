# t/s2-layout-quickreply.t
#
# Test S2 quick-reply markup on journal entries.
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

sub read_style {
    my ($file) = @_;
    open my $source, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$source>;
}

sub load_style_layer {
    my ( $compiler, $id, $type, $source ) = @_;
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

my $user = bless { userid => 1, user => 'testjournal', journaltype => 'P', statusvis => 'V' },
    'LJ::User';
my $journal = { _type => 'UserLite', _u => $user, username => 'testjournal', journal_type => 'P' };
my $page      = { _type => 'RecentPage', view => 'recent', journal => $journal, _u => $user };
my $entry_url = 'https://testjournal.example/1.html';
my $target    = 'entry-testjournal-1-reply';

sub render_recent_entry {
    my ( $ctx, $count, $enabled ) = @_;
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
                enabled              => $enabled,
                read_url             => $entry_url,
                post_url             => "$entry_url?mode=reply",
                show_readlink        => $enabled && $count > 0,
                show_readlink_hidden => $enabled,
                show_postlink        => $enabled,
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
        my $compiler = S2::Compiler->new( {} );
        S2::set_domain("test-quick-reply-$layout");
        load_style_layer( $compiler, 1, 'core', read_style('core2.s2') );
        my $source = read_style("$layout/layout.s2");
        $source = read_style('core2base/layout.s2') . $source if $layout eq 'database';
        load_style_layer( $compiler, 2, 'layout', $source );

        for my $count ( 0, 1, 2, 4 ) {
            my $html = render_recent_entry( S2::make_context( 1, 2 ), $count, 1 );
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

        if ( $layout eq 'zesty' ) {
            my $html = render_recent_entry( S2::make_context( 1, 2 ), 0, 0 );
            like( $html, qr/There are no comments/, 'disabled comments retain the empty state' );
            like(
                $html,
                qr/Comments are disabled/,
                'disabled comments explain why replies are off'
            );
            unlike( $html, qr/class="entry-readlink"/,
                'disabled comments have no hidden read link' );
            unlike( $html, qr/quickreply\(/, 'disabled comments have no quick-reply link' );
        }
    };
}

done_testing;
