# t/cleaner-xss.t
#
# Adversarial XSS corpus for LJ::CleanHTML. Pushes a library of known
# cross-site-scripting vectors (classic, HTML5, scheme-obfuscation, CSS, and
# mutation-XSS) through the real clean_event / clean_comment / clean_userbio
# display paths and asserts that no JavaScript-execution vector survives in the
# cleaned output.
#
# The check is a heuristic "does an exec vector remain" oracle (see is_unsafe),
# not exact-output matching, so it stays meaningful as cleaner internals change.
#
# A TODO section documents a known gap: clean_event (permissive allow-most mode)
# lets SVG/MathML foreign content and its SMIL/XML-Events children through with
# only attribute-level filtering, whereas clean_comment (strict allowlist)
# strips them. Those vectors are browser-dependent today but are the class a
# namespace-aware HTML5 sanitizer would close; the TODO assertions flip to
# passing if/when that is fixed.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;
use LJ::Hooks;

# The malformed-markup error path inside clean() calls LJ::Lang::ml; stub it so
# these tests don't need a populated translation DB.
no warnings 'redefine';
local *LJ::Lang::ml = sub { return "[ml:$_[0]]"; };
use warnings 'redefine';

# ---------------------------------------------------------------------------
# Safety oracle: return a list of execution vectors still present in $html.
# Empty list == safe. Quoted attribute VALUES are stripped before scanning for
# event handlers so escaped junk inside e.g. title="...onerror=..." (which is
# inert) does not register as a live handler.
# ---------------------------------------------------------------------------
# Named entities an attacker can hide a URL scheme behind: the colon, plus the
# whitespace ones a browser strips out of a scheme name.
my %NAMED_ENT = ( colon => ':', tab => "\t", newline => "\n" );

# Decode entities ONCE, left to right, the way a browser does at parse time --
# so a raw "&Tab;" becomes a tab (dangerous if inside a scheme) but an already
# escaped "&amp;Tab;" stays literal text (inert) and is not re-decoded.
sub decode_entities_once {
    my ($s) = @_;
    $s =~ s{
        & (?: \#x([0-9a-f]+) | \#(\d+) | ([a-z][a-z0-9]*) ) ;?
    }{
          defined $1                   ? chr( hex $1 )
        : defined $2                   ? chr($2)
        : exists $NAMED_ENT{ lc $3 }   ? $NAMED_ENT{ lc $3 }
        :                                "&$3;"
    }giex;
    return $s;
}

sub is_unsafe {
    my ($html) = @_;
    my %bad;

    $bad{'script-tag'}      = 1 if $html =~ /<\s*script/i;
    $bad{'iframe'}          = 1 if $html =~ /<\s*iframe/i;
    $bad{'object'}          = 1 if $html =~ /<\s*object\b/i;
    $bad{'embed'}           = 1 if $html =~ /<\s*embed\b/i;
    $bad{'base'}            = 1 if $html =~ /<\s*base\b/i;
    $bad{'meta-http-equiv'} = 1 if $html =~ /<\s*meta[^>]*http-equiv/i;
    $bad{'css-expression'}  = 1 if $html =~ /expression\s*\(/i;
    $bad{'css-binding'}     = 1 if $html =~ /-moz-binding/i || $html =~ /\bbehaviou?r\s*:/i;
    $bad{'css-import'}      = 1 if $html =~ /\@import/i;

    while ( $html =~ /(<[a-z!\/][^>]*>)/gi ) {
        my $tag  = $1;
        my $bare = $tag;
        $bare =~ s/"[^"]*"//g;
        $bare =~ s/'[^']*'//g;
        $bad{'event-handler'} = 1 if $bare =~ /[\s"'\/]on[a-z]+\s*=/i;
        $bad{'srcdoc'}        = 1 if $bare =~ /[\s"'\/]srcdoc\s*=/i;

        my $t = decode_entities_once($tag);
        $t =~ s/[\x00-\x20]+//g;    # browsers ignore whitespace/control chars in URLs and schemes
        $bad{'js-uri'} = 1
            if $t =~
/(?:href|src|action|formaction|xlink:href|poster|background|data|to|values|from)=["']?(?:javascript|vbscript|livescript|mocha):/i;
        $bad{'data-html'}  = 1 if $t =~ m{=["']?data:text/html}i;
        $bad{'css-url-js'} = 1 if $t =~ /url\(["']?(?:javascript|vbscript):/i;
    }
    return sort keys %bad;
}

sub clean_with {
    my ( $surface, $payload ) = @_;
    my $data = $payload;
    no strict 'refs';
    "LJ::CleanHTML::$surface"->( \$data );
    return $data;
}

# ---------------------------------------------------------------------------
# Corpus the current cleaner already neutralizes -> hard regression assertions.
# ---------------------------------------------------------------------------
my @corpus = (
    [ 'script-plain'            => q{<script>alert(1)</script>} ],
    [ 'script-src'              => q{<script src="//evil.test/x.js"></script>} ],
    [ 'script-nested-break'     => q{<scr<script>ipt>alert(1)</scr</script>ipt>} ],
    [ 'script-uppercase'        => q{<SCRIPT>alert(1)</SCRIPT>} ],
    [ 'script-null'             => qq{<scri\x00pt>alert(1)</script>} ],
    [ 'img-onerror'             => q{<img src=x onerror=alert(1)>} ],
    [ 'img-onerror-quotes'      => q{<img src="x" onerror="alert(1)">} ],
    [ 'img-onerror-backtick'    => q{<img src=x onerror=alert`1`>} ],
    [ 'img-onerror-tab'         => qq{<img src=x on\terror=alert(1)>} ],
    [ 'img-onerror-formfeed'    => qq{<img src=x\x{0c}onerror=alert(1)>} ],
    [ 'body-onload'             => q{<body onload=alert(1)>} ],
    [ 'input-autofocus'         => q{<input autofocus onfocus=alert(1)>} ],
    [ 'details-ontoggle'        => q{<details open ontoggle=alert(1)>} ],
    [ 'div-onmouseover'         => q{<div onmouseover="alert(1)">x</div>} ],
    [ 'onpointerrawupdate'      => q{<div onpointerrawupdate=alert(1)>x</div>} ],
    [ 'onbeforetoggle'          => q{<div popover onbeforetoggle=alert(1)>x</div>} ],
    [ 'onscrollend'             => q{<div onscrollend=alert(1)>x</div>} ],
    [ 'attr-newline-handler'    => qq{<a href="x"\nonclick="alert(1)">y</a>} ],
    [ 'marquee-onstart'         => q{<marquee onstart=alert(1)>x</marquee>} ],
    [ 'video-source-onerror'    => q{<video><source onerror=alert(1)></video>} ],
    [ 'a-js-href'               => q{<a href="javascript:alert(1)">x</a>} ],
    [ 'a-js-href-entity'        => q{<a href="javascript&#58;alert(1)">x</a>} ],
    [ 'a-js-href-entity-hex'    => q{<a href="javascript&#x3a;alert(1)">x</a>} ],
    [ 'a-js-href-tab'           => qq{<a href="java\tscript:alert(1)">x</a>} ],
    [ 'a-js-href-newline'       => qq{<a href="java\nscript:alert(1)">x</a>} ],
    [ 'a-js-href-leading-space' => q{<a href=" javascript:alert(1)">x</a>} ],
    [ 'a-js-href-mixedcase'     => q{<a href="JaVaScRiPt:alert(1)">x</a>} ],
    [ 'a-js-href-uppercase-key' => q{<a HREF="javascript:alert(1)">x</a>} ],
    [ 'a-js-entity-tab-scheme'  => q{<a href="javasc&Tab;ript:alert(1)">x</a>} ],
    [ 'a-vbscript'              => q{<a href="vbscript:msgbox(1)">x</a>} ],
    [
        'a-data-html' =>
            q{<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">x</a>}
    ],
    [ 'img-data-html'  => q{<img src="data:text/html,<script>alert(1)</script>">} ],
    [ 'iframe-js'      => q{<iframe src="javascript:alert(1)"></iframe>} ],
    [ 'iframe-srcdoc'  => q{<iframe srcdoc="&lt;script&gt;alert(1)&lt;/script&gt;"></iframe>} ],
    [ 'object-data-js' => q{<object data="javascript:alert(1)"></object>} ],
    [ 'embed-src-js'   => q{<embed src="javascript:alert(1)">} ],
    [ 'form-action-js' => q{<form action="javascript:alert(1)"><input type=submit></form>} ],
    [ 'button-formaction-js' => q{<button formaction="javascript:alert(1)">x</button>} ],
    [ 'isindex-formaction'   => q{<isindex type=image formaction=javascript:alert(1)>} ],
    [ 'base-href-js'         => q{<base href="javascript:alert(1)//">} ],
    [ 'meta-refresh-js' => q{<meta http-equiv="refresh" content="0;url=javascript:alert(1)">} ],
    [ 'bgsound-js'      => q{<bgsound src="javascript:alert(1)">} ],
    [ 'style-attr-expression'   => q{<div style="width:expression(alert(1))">x</div>} ],
    [ 'style-attr-expr-comment' => q{<div style="width:expr/**/ession(alert(1))">x</div>} ],
    [ 'style-attr-moz-binding'  => q{<div style="-moz-binding:url(//evil.test/x.xml#x)">x</div>} ],
    [ 'style-attr-behavior'     => q{<div style="behavior:url(#default#time2)">x</div>} ],
    [ 'style-attr-bg-js'        => q{<div style="background:url(javascript:alert(1))">x</div>} ],
    [ 'style-tag-import'        => q{<style>@import "//evil.test/x.css";</style>} ],
    [ 'style-tag-expr'          => q{<style>*{width:expression(alert(1))}</style>} ],
    [ 'link-stylesheet'         => q{<link rel="stylesheet" href="//evil.test/x.css">} ],
    [ 'mxss-noscript'      => q{<noscript><p title="</noscript><img src=x onerror=alert(1)>">} ],
    [ 'mxss-style-img'     => q{<style><style/><img src=x onerror=alert(1)>} ],
    [ 'mxss-style-comment' => q{<style><!--</style><img src=x onerror=alert(1)>--></style>} ],
    [ 'mxss-listing'       => q{<listing>&lt;img src=x onerror=alert(1)&gt;</listing>} ],
    [ 'mxss-xmp'           => q{<xmp><img src=x onerror=alert(1)></xmp>} ],
    [ 'mxss-textarea'      => q{<textarea><img src=x onerror=alert(1)></textarea>} ],
    [ 'mxss-title'         => q{<title><img src=x onerror=alert(1)></title>} ],
    [ 'mxss-template'      => q{<template><img src=x onerror=alert(1)></template>} ],
    [ 'comment-conditional-ie' => q{<!--[if gte IE 4]><script>alert(1)</script><![endif]-->} ],
);

for my $surface (qw( clean_event clean_comment clean_userbio )) {
    for my $case (@corpus) {
        my ( $name, $payload ) = @$case;
        my $out = clean_with( $surface, $payload );
        my @bad = is_unsafe($out);
        ok( !@bad, "$surface neutralizes $name" )
            or diag("surviving vectors: @bad\n  in : $payload\n  out: $out");
    }
}

# ---------------------------------------------------------------------------
# Known gap (documented, not yet fixed): clean_event's permissive allow-most
# mode lets SVG/MathML foreign content and SMIL/XML-Events children through.
# clean_comment's strict allowlist already strips them. These browser-dependent
# vectors are the class a namespace-aware HTML5 sanitizer would close. Wrapped
# in TODO so the suite stays green while recording exactly what is missed.
# ---------------------------------------------------------------------------
my @gaps = (
    [ 'svg-stripped'  => q{<svg onload=alert(1)>x</svg>},              qr/<\s*svg/i ],
    [ 'math-stripped' => q{<math href="javascript:alert(1)">x</math>}, qr/<\s*math/i ],
    [
        'svg-set-onload' => q{<svg><set attributeName=onload to=alert(1)></set></svg>},
        qr/<\s*set\b/i
    ],
    [
        'svg-handler' => q{<svg><handler ev:event="load">alert(1)</handler></svg>},
        qr/<\s*handler\b/i
    ],
    [
        'svg-animate-href' =>
            q{<svg><a><animate attributeName=href to=javascript:alert(1)></animate></a></svg>},
        qr/<\s*animate\b/i
    ],
);

TODO: {
    local $TODO = "clean_event does not yet strip SVG/MathML foreign content "
        . "(namespace-aware sanitizer would; clean_comment already does)";

    for my $case (@gaps) {
        my ( $name, $payload, $must_not_match ) = @$case;
        my $out = clean_with( 'clean_event', $payload );
        unlike( $out, $must_not_match, "clean_event strips $name" );
    }
}

# Sanity: clean_comment's strict allowlist DOES strip the same SVG/MathML
# (these are not TODO -- they pass today, guarding against regression).
for my $case (@gaps) {
    my ( $name, $payload, $must_not_match ) = @$case;
    my $out = clean_with( 'clean_comment', $payload );
    unlike( $out, $must_not_match, "clean_comment strips $name" );
}

# Oracle self-check: the is_unsafe detector must actually SEE a browser-decodable
# obfuscated scheme (else a real cleaner regression could pass silently), and must
# NOT false-positive on an already-escaped, inert vector or on plain body text.
{
    my @seen;
    @seen = is_unsafe(q{<a href="javasc&Tab;ript:alert(1)">x</a>});
    ok( @seen, "oracle sees &Tab;-obfuscated scheme" );
    @seen = is_unsafe(q{<a href="javascript&#X3A;alert(1)">x</a>});
    ok( @seen, "oracle sees hex-entity (uppercase X, A-F) scheme" );
    @seen = is_unsafe(q{<img src=x onerror=alert(1)>});
    ok( @seen, "oracle sees a raw event handler" );

    @seen = is_unsafe(q{<a href="javasc&amp;Tab;ript:alert(1)">x</a>});
    ok( !@seen, "oracle ignores inert already-escaped &amp;Tab;" );
    @seen = is_unsafe(q{<p title="javascript:not-a-link onerror=text">hi</p>});
    ok( !@seen, "oracle ignores scheme/handler text inside a quoted attribute value" );
}

done_testing();
