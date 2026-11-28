# t/s2-transmogrified-subject-wrap.t
#
# Test the CSS emitted for Transmogrified entry and comment subjects.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use S2;
use S2::Compiler;

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-transmogrified-subject-wrap');

sub load_style_layer {
    my ( $id, $type, $file ) = @_;
    open my $style, '<', "$ENV{LJHOME}/$file" or die "Cannot open $file: $!";
    my $source = do { local $/; <$style> };
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

load_style_layer( 1, 'core',   'styles/core2.s2' );
load_style_layer( 2, 'layout', 'ext/dw-nonfree/styles/transmogrified/layout.s2' );

my $ctx = S2::make_context( 1, 2 );
LJ::S2::populate_system_props($ctx);
my $css = '';
local $S2::pout   = sub { $css .= join '', @_ };
local $S2::pout_s = $S2::pout;
S2::run_code( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );

for my $title ( '.entry-title', '.comment-title' ) {
    my $wraps_subject;
    while ( $css =~ /([^{}]+)\{([^{}]*)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        next unless $selectors =~ /(?:\A|,)\s*\Q$title\E\s*(?:,|\z)/;
        $wraps_subject ||= $declarations =~ /(?:\A|;)\s*word-wrap:\s*break-word\s*;/
            && $declarations =~ /(?:\A|;)\s*overflow-wrap:\s*anywhere\s*;/;
    }
    ok( $wraps_subject, "$title wraps long unbroken subjects" );
}

done_testing;
