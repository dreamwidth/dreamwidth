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

use Test::More tests => 11;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

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
