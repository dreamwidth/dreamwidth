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

use Test::More tests => 17;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::CleanEmail;

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
