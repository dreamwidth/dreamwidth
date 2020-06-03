# t/cleaner-markdown.t
#
# Test LJ::CleanHTML with Markdown text. Validate that Markdown is used in
# appropriate circumstances.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2017-2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 27;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;

my $lju_sys         = LJ::ljuser('system');
my $lju_sys_no_link = LJ::ljuser( 'system', { no_link => 1 } );
my $url             = 'https://medium.com/@username/title-of-page';

my $clean = sub {
    my ( $text, %opts ) = @_;
    unless (%opts) {
        %opts = ( editor => 'markdown' );
    }
    LJ::CleanHTML::clean_event( \$text, \%opts );
    chomp $text;
    return $text;
};

# plain text user tag
is( $clean->('@system'), "<p>$lju_sys</p>", 'user tag in plain text converted' );

# escaped plain text user tag
is( $clean->('\@system'), '<p>@system</p>',
    'escaped user tag in plain text not converted, backslash removed' );

# don't convert user tags (or escaped user tags) in excluded HTML elements
is( $clean->('<pre>@system</pre>'),
    '<pre>@system</pre>', 'md: unescaped user tag is not converted within pre tag' );
is( $clean->( '<pre>@system</pre>', editor => undef ),
    '<pre>@system</pre>', 'html: unescaped user tag is not converted within pre tag' );
is( $clean->('<pre>\@system</pre>'),
    '<pre>\@system</pre>', 'md: escaped user tag is not de-escaped within pre tag' );
is( $clean->( '<pre>\@system</pre>', editor => undef ),
    '<pre>\@system</pre>', 'html: escaped user tag is not de-escaped within pre tag' );
is(
    $clean->('inline `@system` code span'),
    '<p>inline <code>@system</code> code span</p>',
    'md: unescaped user tag is not converted within code tag'
);
is(
    $clean->( '<textarea>@system</textarea>', editor => undef ),
    '<textarea>@system</textarea>',
    'html: unescaped user tag is not converted within textarea tag'
);

# plain URL containing user tag
is(
    $clean->($url),
    '<p>https://medium.com/@username/title-of-page</p>',
    'user tag in URL not converted'
);

# plain URL containing user tag, with autolinks enabled
is(
    $clean->( $url, editor => undef, preformatted => 0, noautolinks => 0 ),
'<a href="https://medium.com/@username/title-of-page">https://medium.com/@username/title-of-page</a>',
    'user tag in auto-linked URL not converted'
);

# linked URL containing user tag
is(
    $clean->("[link from \@system]($url)"),
    qq{<p><a href="$url">link from $lju_sys_no_link</a></p>},
    'user tag in href not converted, but user tag in link text converted (using de-linked form) []'
);

# user tags at ends of sentences
is(
    $clean->('hi @system.'),
    "<p>hi $lju_sys.</p>",
    "bare usertag before period is converted, keeping period"
);
my $ao3_user = DW::External::User->new( user => 'system', site => 'ao3' );
my $lju_ao3  = $ao3_user->ljuser_display;
is(
    $clean->('hi @system.ao3.'),
    qq{<p>hi $lju_ao3.</p>},
    "shortcut sitename usertag before period is converted, keeping period"
);
my $gh_user = DW::External::User->new( user => 'system', site => 'github.com' );
my $lju_gh  = $gh_user->ljuser_display;
is(
    $clean->('hi @system.github.com.'),
    qq{<p>hi $lju_gh.</p>},
    "full sitename usertag before period is converted, keeping period"
);

# TODO: add a test to properly handle @user.hyphenated-sitename.com.
# This SHOULD work fine, but testing it isn't practical until DW::External::Site
# includes at least ONE site with a hyphenated hostname.

# HTML within Markdown is passed through, but Markdown can build new tags around it and user tags get processed
is(
    $clean->(qq{<a href="$url">link from \@system</a>}),
    qq{<p><a href="$url">link from $lju_sys_no_link</a></p>},
    'user tags work the same in HTML-in-Markdown as in plain Markdown'
);

# Now validate that we only fire the cleaner in expected situations
sub check_uses_markdown {
    my ( $desc, %opts ) = @_;
    is( $clean->( qq{*test*}, %opts ), qq{<p><em>test</em></p>}, $desc );
}

sub check_doesnt_use_markdown {
    my ( $desc, %opts ) = @_;
    is( $clean->( qq{*test*}, %opts ), qq{*test*}, $desc );
}

# local content, converts users when not inside html
check_doesnt_use_markdown( 'local entry made in old editor', editor => undef );
check_uses_markdown( 'local entry made in markdown editor', editor => 'markdown' );
is( $clean->( '@system', editor => undef ),
    $lju_sys, 'user tag in plain text converted (undef editor)' );
is( $clean->( '@system', editor => 'markdown' ),
    "<p>$lju_sys</p>", 'user tag in plain text converted (markdown)' );
is( $clean->( '<pre>@system</pre>', editor => 'markdown' ),
    "<pre>\@system</pre>", 'user tag in pre unconverted and unmarkeddown (markdown)' );

# Local content from before ~May 2019 doesn't expect user conversion either.
is( $clean->( '@system', logtime_mysql => '2018-10-10', editor => undef ),
    '@system', 'old content - user tag in plain text unconverted (undef editor)' );

# imported content obeys the same rules, except isn't considered local content
# so doesn't convert users
check_doesnt_use_markdown( 'imported content w/o editor set', is_imported => 1, editor => undef );
check_uses_markdown( 'imported content w/editor set', is_imported => 1, editor => 'markdown' );
is( $clean->( '@system', is_imported => 1, editor => undef ),
    '@system', 'imported content - user tag in plain text unconverted (undef editor)' );

# syndicated content is always post-processed (even if we get it from another DW/LJ)
# so it can't have any editor settings
check_doesnt_use_markdown( 'syndicated content', is_syndicated => 1 );
is( $clean->( '@system', is_syndicated => 1 ),
    '@system', 'syndicated content - user tag in plain text unconverted' );
is( $clean->( '<pre>@system</pre>', is_syndicated => 1 ),
    "<pre>\@system</pre>", 'syndicated content - user tag in pre unconverted' );
