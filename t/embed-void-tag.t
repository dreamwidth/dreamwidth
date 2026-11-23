# t/embed-void-tag.t
#
# <embed> is an HTML void element: it has no closing tag. The embed parser
# must treat a bare <embed ...> as complete rather than waiting for a close that
# never comes, which used to drop the rest of the entry after it.
#
# Authors:
#      Mark Smith <mark@qq.is>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 32;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;
use LJ::EmbedModule;
use LJ::Test qw( temp_user );

my $u   = temp_user();
my $src = 'src="http://www.youtube.com/v/ABC123abc_-" width="425" height="344"';

sub saved {
    my ($post) = @_;
    LJ::EmbedModule->parse_module_embed( $u, \$post );
    return $post;
}

my $out = saved(qq{<p>before</p><embed $src><p>after</p>});
like( $out, qr/<p>before<\/p>/,       'a bare <embed> keeps the text before it' );
like( $out, qr/<p>after<\/p>/,        '...and the text after it' );
like( $out, qr/<site-embed id="\d+"/, '...and becomes an embed module' );
unlike( $out, qr/<embed/i, '...without leaving the tag behind' );

$out = saved(qq{<p>before</p><embed $src></embed><p>after</p>});
like( $out, qr/<p>after<\/p>/, 'a closed <embed></embed> keeps the text after it' );
unlike( $out, qr/<\/embed>/i, '...and leaves no stray closing tag' );

$out = saved(qq{<p>before</p><embed $src /><p>after</p>});
like( $out, qr/<site-embed id="\d+"/, 'a self-closed <embed /> becomes an embed module' );
like( $out, qr/<p>after<\/p>/,        '...and keeps the text after it' );

$out = saved(qq{one <embed $src> two <embed $src> three});
my @modules = $out =~ /<site-embed id="(\d+)"/g;
is( scalar @modules, 2, 'two bare embeds become two modules' );
like( $out, qr/one .* two .* three/s, '...with the text between them intact' );

# An <embed> inside an <object> is still part of that object's embed.
$out = saved(qq{<p>a</p><object width="1" height="1"><embed $src></embed></object><p>b</p>});
like(
    $out,
    qr/<p>a<\/p><site-embed id="\d+"\/><p>b<\/p>/,
    'an <embed> inside <object> stays one module'
);

# A later </embed> belongs to a later embed, not to the bare one before it.
$out = saved(qq{<embed $src><p>middle</p><embed $src>legacy</embed><p>end</p>});
like( $out, qr/<p>middle<\/p>/,
    'text between a bare <embed> and a later <embed>...</embed> is kept' );
like( $out, qr/<p>end<\/p>/, '...and so is the text after the later one' );
my @both = $out =~ /<site-embed id="(\d+)"/g;
is( scalar @both, 2, '...and both embeds become modules' );

# A </embed> in a comment closes nothing.
$out = saved(qq{<embed $src><p>kept</p><!-- </embed> --><p>also kept</p>});
like(
    $out,
    qr/<p>kept<\/p>.*<p>also kept<\/p>/s,
    'a </embed> inside a comment does not make a bare <embed> a container'
);

# A bare <embed> inside an <object> doesn't unbalance it.
$out = saved(qq{<p>a</p><object width="1"><embed $src></object><p>b</p>});
like(
    $out,
    qr/<p>a<\/p><site-embed id="\d+"\/><p>b<\/p>/,
    'a bare <embed> inside <object> leaves the object balanced'
);

# The older <embed>contents</embed> container form still works.
$out = saved(qq{foo <embed>bar</embed> baz});
like( $out, qr/^foo <site-embed id="\d+"\/> baz$/, '<embed>contents</embed> is still one module' );

# Anything left open hands its text back instead of dropping it.
$out = saved(qq{<p>a</p><object>never closed <b>text</b>});
like( $out, qr/^<p>a<\/p>.*never closed <b>text<\/b>/s, 'an unclosed <object> keeps its text' );
$out = saved(qq{<p>a</p><iframe src="http://example.com/">tail});
like( $out, qr/^<p>a<\/p>.*tail/s, 'an unclosed <iframe> keeps its text' );
$out = saved(qq{<p>a</p><site-embed>never closed});
like( $out, qr/^<p>a<\/p>.*never closed/s, 'an unclosed <site-embed> keeps its text' );
unlike( $out, qr/<site-embed id=/, '...without inventing a module' );

# What a reader sees. Storing is only half of it: the text after an element that
# never closed has to survive being rendered too, and no live embed markup may
# come out of that path (only clean_embed's allowlist makes those).
sub rendered {
    my ($post) = @_;
    $post = saved($post);
    LJ::CleanHTML::clean_event( \$post );
    return $post;
}

$out = rendered(qq{<p>before</p><iframe src="http://example.com/">after the iframe <b>bold</b>});
like( $out, qr/<p>before<\/p>/,   'rendered: text before an unclosed <iframe> shows' );
like( $out, qr/after the iframe/, '...and so does the text after it' );
unlike( $out, qr/<iframe/i, '...with no live iframe' );

$out =
    rendered(qq{<p>before</p><object><param name="movie" value="x">after the object <b>bold</b>});
like( $out, qr/after the object <b>bold<\/b>/, 'rendered: text after an unclosed <object> shows' );
unlike( $out, qr/<object|<param/i, '...with no live object' );

$out = rendered(qq{<p>before</p><title>never closed</title2>the rest of the entry});
like( $out, qr/the rest of the entry/, 'rendered: text after an unclosed <title> shows' );

# Closed ones still swallow their own contents, nesting included.
$out = rendered(qq{<p>a</p><object><object></object>inner stays inside</object><p>after</p>});
like( $out, qr/<p>after<\/p>/, 'rendered: nested closed objects end at the outer close' );
unlike( $out, qr/inner stays inside/, '...and keep their contents out of the page' );

$out = rendered(qq{<p>a</p><iframe src="http://example.com/">x</iframe><p>after</p>});
like( $out, qr/<p>after<\/p>/, 'rendered: a closed <iframe> still ends where it closes' );
unlike( $out, qr/<iframe/i, '...with no live iframe' );

# A <site-embed> nested in a <site-embed> doesn't end the outer one early.
$out = saved(
qq{<p>a</p><site-embed><iframe src="http://example.com/a"></iframe><site-embed></site-embed></site-embed><p>after</p>}
);
like(
    $out,
    qr/^<p>a<\/p><site-embed id="\d+"\/><p>after<\/p>$/,
    'a nested <site-embed> pair is one module'
);
