# t/cleanemail.t
#
# Test DW::CleanEmail.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 35;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use DW::CleanEmail;
use LJ::TextUtil;

local $LJ::BOGUS_EMAIL = 'dw_null@dreamwidth.org';    # for testing only

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
yay testing

yes go.

hello

On Wednesday, April 10, 2013 at 12:00 PM, afuna <dw_null@dreamwidth.org> wrote:

>   afuna replied to your Dreamwidth entry in which you said:
> foo bar baz hello hello hey
> The reply was:
> etc etc reply
>
> From here you can:
>   * Reply at the webpage
>   * Delete the comment
>   * View all comments to this entry
>   * View the thread beginning with this comment
> To respond, reply to this email directly. Your comment needs to be the very first thing in the reply email and appear before all other text.
>
    }
    );
    is(
        $nonquoted, q{
yay testing

yes go.

hello
}, "got nonquoted text from an email with quoted and nonquoted text"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
testing 123
foo bar

baaaaz}
    );

    is(
        $nonquoted, q{
testing 123
foo bar

baaaaz}, "got nonquoted text from an email without any quoted text"
    );
}

# seen in the wild: extra address space
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
testing 123
foo bar

baaaaz

On Jan 11, 2017 6:18 AM, "DW Comment" < dw_null@dreamwidth.org> wrote:

A user replied to your Dreamwidth entry "test subject" ( http://testuser.dreamwidth.org/7718044.html ) in which you said:
}
    );

    is(
        $nonquoted, q{
testing 123
foo bar

baaaaz
}, "removed all quoted text when bogus email includes leading space"
    );
}

# gmail fixes
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo
On Tue, Apr 23, 2013 at 2:39 PM, ExampleUser
<test@example.com> wrote:
> blah blah
}
    );
    is(
        $nonquoted, q{
foo}, "got nonquoted text from email, replied via gmail web mail"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo
On 23/04/2013 at 2:39 PM, ExampleUser
<test@example.com> wrote:
> blah blah
}
    );
    is(
        $nonquoted, q{
foo}, "got nonquoted text from email, replied via android"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo
On Apr 22, 2013 11:22 PM, ExampleUser <test@example.com>
wrote:
> blah blah
}
    );
    is(
        $nonquoted, q{
foo}, "got nonquoted text from email, Jan 31, 2013 date format"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo
On 29 Apr 2013 11:22 PM, ExampleUser <test@example.com>
wrote:
> blah blah
}
    );
    is(
        $nonquoted, q{
foo}, "got nonquoted text from email, 31 Jan 2013 date format"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
abc
def
On Monday, someone wrote:
tuv
wxyz}
    );
    is(
        $nonquoted, q{
abc
def}, "'On wrote...' separator a few lines back - cut back to that point"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
abc
def
On Monday, someone wrote:
qrs
tuv
wxyz}
    );
    is(
        $nonquoted, q{
abc
def
On Monday, someone wrote:
qrs
tuv
wxyz}, "'On wrote...' separator too many lines back - don't count as end of the message"
    );
}

# blackberry, etc
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo
---Original Message---
From: etc
Reply-To: etc
some original text here
}
    );

    is(
        $nonquoted, q{
foo}, "---Original Message--- separator"
    )
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo
------Message d'origine------
De: etc
some original text here
}
    );

    is(
        $nonquoted, q{
foo}, "------Message d'origine------ separator"
    )
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        qq{
foo
--- etc - DW Comment <$LJ::BOGUS_EMAIL> schrieb am Do, 25.4.2013:

Von: etc - DW Comment <dw_null\@dreamwidth.org>
Betreff: Reply to your comment. [ exampleusername - 12345 ]
Datum: Donnerstag, 25. April, 2013 21:15 Uhr
}
    );

    is(
        $nonquoted, q{
foo}, "\$LJ::BOGUS_EMAIL"
    )
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        qq{
foo

Von: etc - DW Comment <$LJ::BOGUS_EMAIL>
Betreff: Reply to your comment. [ exampleusername - 12345 ]
Datum: Donnerstag, 25. April, 2013 21:15 Uhr
}
    );

    is(
        $nonquoted, q{
foo
}, "\$LJ::BOGUS_EMAIL"
    )
}

# seen in the wild (#2907): an HTML-only reply, where the quoted header escapes
# the angle brackets around our address. The separator above the header is
# not recognized, so it stays.
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{<div>reply text</div>
<div>&nbsp;</div>
<div>---------------</div>
<div><b>Sent:</b> Saturday, November 20, 2021 7:27 AM<br>
<b>From:</b> "username1 - DW Comment" &lt;dw_null@dreamwidth.org&gt;<br>
<b>To:</b> someone@example.com<br>
<b>Subject:</b> Reply to your comment. [ username1 - 12345 ]</div>
<div>username1 replied to a comment you left in a Dreamwidth entry "subject".</div>
<div>Reply to this comment by replying to this email.</div>
}
    );

    is(
        $nonquoted, q{<div>reply text</div>
<div>&nbsp;</div>
<div>---------------</div>}, "removed the quoted notification from an HTML reply"
    );
}

foreach my $header (
    q{<div>From: &lt;dw_null@dreamwidth.org&gt;</div>},
    q{<p>On Monday, DW Comment <dw_null@dreamwidth.org> wrote:</p>},
    q{<div><b>From:</b> <a href="mailto:dw_null@dreamwidth.org">DW Comment</a></div>},
    )
{
    my $reply = '<div>My reply</div>';
    is( DW::CleanEmail->nonquoted_text("$reply$header<div>Quoted text</div>\nMore quoted text"),
        $reply, "kept the HTML reply before $header on the same line" );
}

foreach my $address (
    q{<dw_null@dreamwidth.org.example>},      q{&lt;dw_null@dreamwidth.org.example&gt;},
    q{mailto:dw_null@dreamwidth.org.example}, q{dw_null@dreamwidth.org.example},
    q{<dw_null@dreamwidth.org-example>},      q{mailto:dw_null@dreamwidth.orgfoo},
    q{mailto:dw_null@dreamwidth.org_example},
    )
{
    my $reply = "My contact is $address.\nThanks!";
    is( DW::CleanEmail->nonquoted_text($reply), $reply, "kept a different address: $address" );
}

foreach my $address (
    q{<DW_NULL@DREAMWIDTH.ORG>},
    q{&LT;DW_NULL@DREAMWIDTH.ORG&GT;},
    q{MAILTO:DW_NULL@DREAMWIDTH.ORG},
    )
{
    is(
        DW::CleanEmail->nonquoted_text("My reply\nFrom: $address\nQuoted text"),
        'My reply',
        "removed the quoted header with uppercase address: $address"
    );
}

# other forms of the quoted address that the check used to miss
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo

From: "username1 - DW Comment" <dw_null@dreamwidth.org<mailto:dw_null@dreamwidth.org>>
username1 replied to a comment you left in a Dreamwidth entry.
}
    );

    is(
        $nonquoted, q{
foo
}, "removed quoted text when the address has a <mailto:...> suffix"
    );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
foo

From: username1 - DW Comment [mailto:dw_null@dreamwidth.org]
Sent: Saturday, November 20, 2021 7:27 AM
username1 replied to a comment you left in a Dreamwidth entry.
}
    );

    is(
        $nonquoted, q{
foo
}, "removed quoted text when the address is given as [mailto:...]"
    );
}

# the reply itself may mention the address without quoting a header
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
Try adding dw_null@dreamwidth.org to your contacts so these stop going to spam.
Also, I loved this chapter!}
    );

    is(
        $nonquoted, q{
Try adding dw_null@dreamwidth.org to your contacts so these stop going to spam.
Also, I loved this chapter!}, "kept a reply that mentions the bare address"
    );
}

# with no address configured, ordinary markup must not end the message
{
    local $LJ::BOGUS_EMAIL = '';
    my $nonquoted = DW::CleanEmail->nonquoted_text(
        q{
<b>foo</b>
bar}
    );

    is(
        $nonquoted, q{
<b>foo</b>
bar}, "kept all text when no bogus address is configured"
    );
}

{
    my $subject = DW::CleanEmail->reply_subject;
    is( $subject, "", "no subject" );
}

{
    my $subject = DW::CleanEmail->reply_subject("just a subject");
    is( $subject, "Re: just a subject", "just a subject" );
}

{
    my $subject = DW::CleanEmail->reply_subject("Re: nested subject");
    is( $subject, "Re: nested subject", "subject has Re:" );
}

{
    my $subject = DW::CleanEmail->reply_subject("Re: Re: Re: very nested subject");
    is( $subject, "Re: very nested subject", "subject has multiple Re:" );
}
