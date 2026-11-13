# t/cleaner-ugc.t
#
# User-authored hyperlinks retain their behavior and carry UGC metadata.
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
use HTML::TokeParser;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;
use LJ::Sendmail;

sub links {
    my ($html) = @_;
    my $p = HTML::TokeParser->new( \$html );
    my @links;
    while ( my $token = $p->get_tag( 'a', 'area' ) ) {
        push @links, $token->[1] if exists $token->[1]{href};
    }
    return \@links;
}

my @surfaces = (
    [ entry => sub { my $s = shift; LJ::CleanHTML::clean_event( \$s, @_ ); $s } ],
    [ comment => sub { my $s = shift; LJ::CleanHTML::clean_comment( \$s, @_ ); $s } ],
    [ bio => sub { my $s = shift; LJ::CleanHTML::clean_userbio( \$s, @_ ); $s } ],
);

for my $surface (@surfaces) {
    my ( $name, $clean ) = @$surface;
    subtest $name => sub {
        for my $rel ( '', '0', 'nofollow', 'noreferrer noopener sponsored', 'UGC nofollow',
            'not-ugc', 'ugc-extra', 'nofollow &#117;gc' )
        {
            my $out = $clean->(
                qq{<a href="https://example.test/path?a=1&amp;b=2" rel="$rel"}
                    . q{ target="_blank" title="A &amp; B">chosen link</a>}
            );
            my $anchors = links($out);
            is( scalar @$anchors, 1, "$rel: one link remains" );
            my $a = $anchors->[0] || {};
            is( $a->{href}, 'https://example.test/path?a=1&b=2', 'destination preserved' );
            is( $a->{target}, '_blank', 'target preserved' );
            is( $a->{title}, 'A & B', 'escaped title preserved' );
            like( $out, qr/>chosen link<\/a>/, 'link text preserved' );
            my @tokens = split /\s+/, $a->{rel} || '';
            is( scalar( grep { lc $_ eq 'ugc' } @tokens ), 1, 'exactly one UGC token' );
            for my $token ( split /\s+/, $rel ) {
                next if $token eq '&#117;gc';
                ok( scalar( grep { $_ eq $token } @tokens ), "$token preserved" );
            }
            is( $clean->($out), $out, 'cleaning again is stable' );
        }

        my $out = $clean->(q{Visit https://example.test/plain?a=1&amp;b=2});
        my $a = links($out)->[0] || {};
        is( $a->{rel}, 'ugc', 'plain URL autolink marked' );
        is( $a->{href}, 'https://example.test/plain?a=1&b=2', 'autolink query preserved' );

        $out = $clean->(q{<a href="/relative">relative</a><a href="#part">fragment</a>});
        is_deeply( [ map { $_->{rel} } @{ links($out) } ], [ 'ugc', 'ugc' ],
            'user-chosen relative and fragment links marked' );

        $out = $clean->(q{<map name="m"><area href="https://example.test/map" rel="nofollow"></map>});
        $a = links($out)->[0] || {};
        is( $a->{rel}, 'nofollow ugc', 'image-map hyperlink marked' );

        $out = $clean->(q{<a name="part">anchor</a><img src="https://example.test/image.png">});
        unlike( $out, qr/\brel=/, 'named anchors and images are not hyperlinks' );

        $out = $clean->(q{<a href="javascript:alert(1)" onclick="alert(2)">unsafe</a>});
        is( scalar @{ links($out) }, 0, 'unsafe destination stays removed' );
        unlike( $out, qr/onclick|javascript|\brel=/i, 'no handler or new link on rejected href' );

        $out = $clean->(q{<a href="https://example.test/safe" rel="javascript:bad">safe</a>});
        $a = links($out)->[0] || {};
        is( $a->{rel}, 'ugc', 'unsafe rel removed before adding metadata' );
        is( scalar( () = $out =~ /\brel=/g ), 1, 'removed rel attribute is emitted only once' );

        local @LJ::BLOCKED_LINKS = ( qr/example\.test/ );
        local $LJ::BLOCKED_LINK_SUBSTITUTE = 'https://blocked.test/';
        $out = $clean->(q{<a href="https://example.test/blocked">blocked</a>});
        $a = links($out)->[0] || {};
        is( $a->{href}, 'https://blocked.test/', 'blocked-link replacement preserved' );
        is( $a->{rel}, 'ugc', 'replaced authored link marked' );
    };
}

for my $surface ( @surfaces[ 0, 1 ] ) {
    my ( $name, $clean ) = @$surface;
    subtest "$name formats" => sub {
        for my $input (
            '[label](https://example.test/markdown)',
            "[label][ref]\n\n[ref]: https://example.test/reference",
            '<https://example.test/autolink>',
            '<a href="https://example.test/raw" rel="nofollow">raw</a>'
            )
        {
            my $out = $clean->( $input, { editor => 'markdown0' } );
            my $anchors = links($out);
            is( scalar @$anchors, 1, 'Markdown produces a link' );
            like( $anchors->[0]{rel} || '', qr/(?:^|\s)ugc(?:\s|$)/, 'Markdown link marked' );
        }
        my $out = $clean->( 'https://example.test/raw', { preformatted => 1 } );
        is( scalar @{ links($out) }, 0, 'raw formatting still disables autolinks' );
        $out = $clean->( '<a href="https://example.test/raw">raw</a>', { preformatted => 1 } );
        is( links($out)->[0]{rel}, 'ugc', 'explicit raw HTML link marked' );
    };
}

my $anonymous = q{<a href="https://example.test/anon">anonymous</a> https://example.test/plain};
LJ::CleanHTML::clean_comment( \$anonymous, { anon_comment => 1 } );
is( scalar @{ links($anonymous) }, 0, 'anonymous extraction still removes links' );
like( $anonymous, qr/<b>anonymous<\/b> \(https:\/\/example.test\/anon\)/,
    'anonymous extraction preserves readable destination' );

my $unverified = q{<a href="https://example.test/bio">bio</a> https://example.test/plain};
LJ::CleanHTML::clean_userbio( \$unverified, 1 );
is( scalar @{ links($unverified) }, 0, 'unverified bio still strips links' );

my $cut = q{<cut>hidden</cut>};
LJ::CleanHTML::clean_event( \$cut, { cuturl => 'https://journal.test/1.html' } );
is( scalar @{ links($cut) }, 1, 'cut expansion control remains a link' );
ok( !links($cut)->[0]{rel}, 'generated cut control is not marked' );

my $platform = '<a href="https://example.test/platform">platform</a>';
LJ::CleanHTML::clean( \$platform, { mode => 'allow' } );
ok( !links($platform)->[0]{rel}, 'generic cleaner does not mark platform HTML' );

my $mixed = '<a href="https://example.test/readmore">Read more</a> https://example.test/plain';
LJ::CleanHTML::clean_event( \$mixed, { ugc_links => 0 } );
is( scalar @{ links($mixed) }, 2, 'mixed-content caller keeps explicit and automatic links' );
ok( !scalar( grep { $_->{rel} } @{ links($mixed) } ), 'mixed-content caller can omit UGC metadata' );

my ($mail) = LJ::format_mail('[Site help](https://example.test/help)');
ok( scalar @{ links($mail) }, 'site email still contains links' );
ok( !scalar( grep { ( $_->{rel} || '' ) =~ /\bugc\b/i } @{ links($mail) } ),
    'platform email links are not marked as user content' );

done_testing();
