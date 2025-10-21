# t/clean-embed.t
#
# Test LJ::CleanHTML::clean_embed.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Jen Griffin <kareila@livejournal.com>
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 175;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;
use LJ::EmbedModule;
use LJ::Test qw( temp_user );

note("Testing clean_embed (we provide the contents to be cleaned directly)");
{
    my ( $orig_post, $clean_post, $saved_post );

    my $clean = sub {
        my ($opts) = @_;
        LJ::CleanHTML::clean_embed( \$orig_post, $opts );
    };

    note("no content");
    $orig_post  = qq{};
    $clean_post = qq{};
    $clean->();
    is( $orig_post, $clean_post, "empty" );

    note("simple object");
    $orig_post  = qq{<object></object>};
    $clean_post = qq{<object></object>};
    $clean->();
    is( $orig_post, $clean_post, "basic <object>" );

    note("<object> and <embed> tags, params different case");
    $orig_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowScrIpTaccess" value="always"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowScrIptAccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowScrIpTaccess" value="sameDomain"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="sameDomain" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean->();
    is( $orig_post, $clean_post, "<object> and <embed> tags" );

    note("<object> and <embed> tags");
    $orig_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="sameDomain"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="sameDomain" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean->();
    is( $orig_post, $clean_post, "<object> and <embed> tags" );

    note("<object> and <embed> tags, keep never");
    $orig_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="never"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="never" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="never"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="never" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean->();
    is( $orig_post, $clean_post, "<object> and <embed> tags" );

    note("object tag with data attribute");
    $orig_post  = qq{<object width="123" data="abc" height="456"></object>};
    $clean_post = qq{<object width="123" height="456"></object>};
    $clean->();
    is( $orig_post, $clean_post, "Drop the data attribute" );

    note("script tag");
    $orig_post  = qq{<object><script>bar</script></object>};
    $clean_post = qq{<object></object>};
    $clean->();
    is( $orig_post, $clean_post, "<script> tag" );

    note("iframe tag");
    $orig_post  = qq{<iframe src="http://example.com/randompage"></iframe>};
    $clean_post = qq{};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag" );

    my $id = "ABC123abc-_";
    note("trusted site: youtube");
    $orig_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="sameDomain"></param><embed src="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US" type="application/x-shockwave-flash" allowscriptaccess="sameDomain" allowfullscreen="true" width="640" height="385"></embed></object>};
    $clean->();
    is( $orig_post, $clean_post, "old-style embeds" );

    $orig_post  = qq{<iframe src="http://www.youtube.com/"></iframe>};
    $clean_post = qq{};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: youtube (not an embed url)" );

    $orig_post  = qq{<iframe src="http://www.youtube.com/embed/123"></iframe>};
    $clean_post = qq{};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: youtube (invalid id)" );

    $orig_post  = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>};
    $clean_post = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: www.youtube.com (iframe embed code)" );

    $orig_post  = qq{<iframe src="http://youtube.com/embed/$id"></iframe>};
    $clean_post = qq{<iframe src="http://youtube.com/embed/$id"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: youtube.com (iframe embed code)" );

    $orig_post  = qq{<iframe src="http://abc.youtube.com/embed/$id"></iframe>};
    $clean_post = qq{<iframe src="http://abc.youtube.com/embed/$id"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: abc.youtube.com (iframe embed code)" );

    $orig_post  = qq{<iframe src="http://www.not-youtube.com/embed/$id"></iframe>};
    $clean_post = qq{};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: not-youtube.com" );

    $orig_post  = qq{<iframe src="http://www.not-youtube.com/embed/$id"></iframe>};
    $clean_post = qq{};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: www.not-youtube.com" );

    $orig_post =
qq{<iframe src="http://youtube.com/embed/$id"></iframe> <iframe src="http://www.not-youtube.com/embed/$id"></iframe>};
    $clean_post = qq{<iframe src="http://youtube.com/embed/$id"></iframe> };
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: youtube.com (iframe embed code)" );

# HTML 4 says an iframe can contain fallback content
# HTML 5 says an iframe contains no fallback content
# this doesn't actually concern itself with either. We just want to make sure
# that you can't sneak in malicious code by wrapping it in an iframe from a trusted domain
# (iframe contents are treated as text nodes, not HTML tokens, so these aren't stripped, merely escaped)
    $orig_post =
qq{<iframe src="http://www.youtube.com/embed/$id"><iframe src="http://not-youtube.com/embed/$id"></iframe></iframe>};

    # inner iframe tag closes the iframe; outer tag is discarded
    $clean_post =
qq{<iframe src="http://www.youtube.com/embed/$id">&lt;iframe src="http://not-youtube.com/embed/$id"&gt;</iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: nested trusted and untrusted" );

    $orig_post =
qq{<iframe src="http://www.youtube.com/embed/$id"><script type="text/javascript">alert("hi");</script></iframe>};
    $clean_post =
qq{<iframe src="http://www.youtube.com/embed/$id">&lt;script type="text/javascript"&gt;alert("hi");&lt;/script&gt;</iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: nested trusted with script tags" );

    $orig_post =
qq{<iframe src="http://www.youtube.com/embed/$id"><style type="text/css">alert(document["coo"+"kies"])</style></iframe>};
    $clean_post =
qq{<iframe src="http://www.youtube.com/embed/$id">&lt;style type="text/css"&gt;alert(document["coo"+"kies"])&lt;/style&gt;</iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: nested trusted with style tags" );

    # and also make sure we are cleaning the iframe parameters properly
    $orig_post =
qq{<iframe src="http://www.youtube.com/embed/$id" height="100" onload="alert('hi!');" width="200"></iframe>};
    $clean_post =
        qq{<iframe src="http://www.youtube.com/embed/$id" height="100" width="200"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: trusted with malicious parameters" );

    $orig_post =
qq{<iframe src="http://www.youtube.com/embed/$id" height="100" style="javascript:alert('hi')" width="200"></iframe>};
    $clean_post =
        qq{<iframe src="http://www.youtube.com/embed/$id" height="100" width="200"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: trusted with malicious parameters" );

    $orig_post =
qq{<iframe src="http://www.youtube.com/embed/$id" height="100" style="position: absolute;" width="200"></iframe>};
    $clean_post =
        qq{<iframe src="http://www.youtube.com/embed/$id" height="100" width="200"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: trusted with malicious parameters" );

    $orig_post  = qq{<iframe src="http://www.youtube.com/embed/$id" name="thisname"></iframe>};
    $clean_post = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: with name parameter" );

    # not sure if we need to do anything about this
    $orig_post  = qq{<iframe src="http://www.youtube.com/embed/$id" width="1" height="1"></iframe>};
    $clean_post = qq{<iframe src="http://www.youtube.com/embed/$id" width="1" height="1"></iframe>};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: trying to make it invisible" );

    # what if it's malformed HTML?
TODO: {
        local $TODO =
"Not sure how to handle this. The HTML parser treats iframe like it can't contain other tags, so anything up to a closing iframe tag is text. If it's self-closed or not closed, then everything up to the end is considered text. Currently this means that all text after an unclosed iframe is wiped out and not saved to the db -- see LJ::parse_embed_module";
        $orig_post  = qq{<iframe src="http://www.youtube.com/embed/$id" />end};
        $clean_post = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>end};
        $clean->();
        is( $orig_post, $clean_post, "<iframe> tag: self-closing trusted" );
    }

    $orig_post  = qq{<iframe src="http://not-youtube.com/embed/$id" />end};
    $clean_post = qq{end};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: self-closing untrusted" );
}

note("Testing parse_embed (We parse the embed contents first from a post)");
{
    # it's okay. Users shouldn't see this,
    # because we have additional checks in the callers
    my $invalid_embed = qq{[Invalid lj-embed id 1]};

    my $iframe =
qq{<div class="lj_embedcontent-wrapper" style="[^"]+"><div class="lj_embedcontent-ratio" style="[^"]+"><iframe ([^>]+)></iframe></div></div>(<div><a href=""></a></div>)};

    foreach (
        (
            # [ "title"
            # input (post)
            # post we save in the database
            # expected entry contents when we edit
            # expected contents when we view in a journal
            # contents of iframe we create
            # ],
            [
                "no content",
                qq{},

                qq{},
                qq{},
                qq{},
                $invalid_embed
            ],

            [
                "no embeddable content",
                qq{foo},

                qq{foo},
                qq{foo},
                qq{foo},
                $invalid_embed
            ],

            [
                "empty embeddable content",
                qq{foo <site-embed id="1"> </site-embed> bar},

                qq{foo <site-embed id="1"/> bar},
                qr{foo <site-embed id="1">\s*</site-embed> bar},
                qr{foo $iframe bar},
                qr{\s*},
            ],

            [
                "dimensions: object tag with dimensions in percent",
                qq{<site-embed id="1"><object width="100%" height="100%"></object></site-embed>},
                qq{<site-embed id="1"/>},
                qq{<site-embed id="1"><object width="100%" height="100%"></object></site-embed>},
                qr{width="100%" height="100%"},
                qq{<object width="100%" height="100%"></object>},
            ],

            [
                "dimensions: object tag with mixed units for dimensions",
                qq{<site-embed id="1"><object width="80%" height="200"></object></site-embed>},
                qq{<site-embed id="1"/>},
                qq{<site-embed id="1"><object width="80%" height="200"></object></site-embed>},
                qr{width="80%" height="200"},
                qq{<object width="80%" height="200"></object>},
            ],

            [
                "dimensions: object tag with dimensions in percent -- too big",
                qq{<site-embed id="1"><object width="1000%" height="101%"></object></site-embed>},
                qq{<site-embed id="1"/>},
                qq{<site-embed id="1"><object width="1000%" height="101%"></object></site-embed>},
                qr{width="100%" height="100%"},
                qq{<object width="1000%" height="101%"></object>},
            ],

            [
                "object tag; no site-embed",
                qq{foo <object>bar</object>baz},

                qq{foo <site-embed id="1"/>baz},
                qq{foo <site-embed id="1"><object>bar</object></site-embed>baz},
                qr{foo ${iframe}baz},
                qq{<object>bar</object>},
            ],

            [
                "object tag with site-embed",
                qq{foo <site-embed><object></object></site-embed> baz},

                qq{foo <site-embed id="1"/> baz},
                qq{foo <site-embed id="1"><object></object></site-embed> baz},
                qr{foo $iframe baz},
                qq{<object></object>},
            ],

            [
                "embed tag; no site-embed",
                qq{foo <embed>bar</embed>baz},

                qq{foo <site-embed id="1"/>baz},
                qq{foo <site-embed id="1"><embed>bar</embed></site-embed>baz},
                qr{foo ${iframe}baz},
                qq{<embed>bar</embed>},
            ],

            [
                "embed tag with site-embed",
                qq{foo <site-embed><embed></embed></site-embed> baz},

                qq{foo <site-embed id="1"/> baz},
                qq{foo <site-embed id="1"><embed></embed></site-embed> baz},
                qr{foo $iframe baz},
                qq{<embed></embed>},
            ],

            [
                "iframe tag; no site-embed (untrusted)",
                qq{foo <iframe>bar</iframe>baz},

                # wrap the iframe in a site-embed tag
                qq{foo <site-embed id="1"/>baz},

                # but nested site-embed won't display the untrusted content
                qq{foo <site-embed id="1"></site-embed>baz},
                qr{foo ${iframe}baz},
                qq{},
            ],

            [
                "iframe tag with site-embed (untrusted)",
                qq{foo <site-embed><iframe></iframe></site-embed> baz},

                qq{foo <site-embed id="1"/> baz},
                qq{foo <site-embed id="1"></site-embed> baz},
                qr{foo $iframe baz},
                qq{},
            ],

            [
                "iframe tag; no site-embed (trusted)",
                qq{foo <iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe>baz},

                # wrap the iframe in a site-embed
                qq{foo <site-embed id="1"/>baz},
qq{foo <site-embed id="1"><iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe></site-embed>baz},

                # site-embed iframe
qr{foo <div class="lj_embedcontent-wrapper" style="[^"]+"><div class="lj_embedcontent-ratio" style="[^"]+"><iframe ([^>]+)></iframe></div></div><div><a href="https://www.youtube.com/watch\?v=ABC123abc_-">(?:[^<]+)</a></div>\s*baz},

                # ...which contains the nested iframe with a URL from a trusted source
                qq{<iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe>},
            ],

            [
                "iframe tag with site-embed (trusted)",
qq{foo <site-embed><iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe></site-embed> baz},

                # site-embed as normal
                qq{foo <site-embed id="1"/> baz},
qq{foo <site-embed id="1"><iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe></site-embed> baz},

                # site-embed iframe
qr{foo <div class="lj_embedcontent-wrapper" style="[^"]+"><div class="lj_embedcontent-ratio" style="[^"]+"><iframe ([^>]+)></iframe></div></div><div><a href="https://www.youtube.com/watch\?v=ABC123abc_-">(?:[^<]+)</a></div>\s*baz},

                # ...which contains the nested iframe with a URL from a trusted source
                qq{<iframe src="http://www.youtube.com/embed/ABC123abc_-"></iframe>},
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "object tag left open; no site-embed",
                qq{foo <object>blah bzzt},

                qq{foo },
                qq{foo },
                qq{foo },
                $invalid_embed
            ],

            [
                "object tag left open in site-embed",
                qq{foo <site-embed><object>blah</site-embed> bzzt},

                qq{foo <site-embed id="1"/> bzzt},
                qq{foo <site-embed id="1"><object>blah</object></site-embed> bzzt},
                qr{foo $iframe bzzt},
                qq{<object>blah</object>}
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "embed tag left open; no site-embed",
                qq{foo <embed>blah bzzt},

                qq{foo },
                qq{foo },
                qq{foo },
                $invalid_embed
            ],

            [
                "embed tag left open in site-embed",
                qq{foo <site-embed><embed>blah</site-embed> bzzt},

                qq{foo <site-embed id="1"/> bzzt},
                qq{foo <site-embed id="1"><embed>blah</site-embed> bzzt},
                qr{foo $iframe bzzt},
                qq{<embed>blah}
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "iframe tag left open; no site-embed (untrusted)",
                qq{foo },

                qq{foo },
                qq{foo },
                qq{foo },
                $invalid_embed
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "iframe tag left open in site-embed (untrusted)",
                qq{foo <site-embed><iframe></site-embed> baz},

                qq{foo },
                qq{foo },
                qr{foo },
                $invalid_embed
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "iframe tag left open; no site-embed (trusted)",
                qq{foo },

                qq{foo },
                qq{foo },
                qr{foo },
                $invalid_embed
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "iframe tag left open in site-embed (trusted)",
qq{foo <site-embed><iframe src="http://www.youtube.com/embed/ABC123abc_-"></site-embed> baz},

                qq{foo },
                qq{foo },
                qr{foo },
                $invalid_embed
            ],

            # TODO: DANGER: EATS EVERYTHING PAST THE OPEN TAG
            [
                "site-embed tag left open",
                qq{foo <site-embed>EMBED yo},

                qq{foo },
                qq{foo },
                qq{foo },
                $invalid_embed
            ],

        )
        )
    {
        my ( $title, $orig_post, $expected_save, $expected_edit, $expected_view, $expected_iframe )
            = @$_;

        # new user each time, to make sure our module code doesn't get mixed up
        my $u = temp_user();

        # save the post
        my $got_post_saved = $orig_post;
        LJ::EmbedModule->parse_module_embed( $u, \$got_post_saved );
        is( $got_post_saved, $expected_save, "parse_module_embed: $title" );

        # edit the post
        my $expanded_entry = $got_post_saved;
        LJ::EmbedModule->expand_entry( $u, \$expanded_entry, edit => 1 );
        if ( ref $expected_edit && ref $expected_edit eq "Regexp" ) {
            like( $expanded_entry, $expected_edit, "expand entry: $title" );
        }
        else {
            is( $expanded_entry, $expected_edit, "expand_entry: $title" );
        }

        # view the post in your journal (get iframe if applicable)
        my $viewed_entry = $got_post_saved;

   # any time we call expand_entry for display, we must make sure we have called clean_event as well
        LJ::CleanHTML::clean_event( \$viewed_entry );
        LJ::EmbedModule->expand_entry( $u, \$viewed_entry );

        if ( ref $expected_view && ref $expected_view eq "Regexp" ) {
            like( $viewed_entry, $expected_view, "expand_entry: $title" );
        }
        else {
            is( $viewed_entry, $expected_view, "expand_entry: $title" );
        }

        # check embed attributes (assumes we only have the one embedded item)
        # make sure that the only top-level iframes we have are the ones we generated
        if ( $viewed_entry =~ "<iframe" ) {
            my $userid = $u->userid;
            my %attrs  = $viewed_entry =~ /(id|name|class|src)="?([^"]+)"?/g;
            is( $attrs{id}, "embed_${userid}_1", "iframe id: $title" );
            like( $attrs{name}, qr!embed_${userid}_1_[\w]{5}!, "iframe name: $title" );
            is( $attrs{class}, "lj_embedcontent", "iframe class: $title" );
            like(
                $attrs{src},
                qr!^(https?:)?//$LJ::EMBED_MODULE_DOMAIN/\?journalid=!,
                "iframe src: $title"
            );
        }

        # check the iframe contents
        # LJ::EmbedModule takes the content and cleans it
        my $got_embed =
            LJ::EmbedModule->module_content( journalid => $u->userid, moduleid => 1 )->{content};
        if ( ref $expected_iframe && ref $expected_iframe eq "Regexp" ) {
            like( $got_embed, $expected_iframe, "clean_embed: $title" );
        }
        else {
            is( $got_embed, $expected_iframe, "clean_embed: $title" );
        }
    }
}
