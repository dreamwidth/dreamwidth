# -*-perl-*-

use strict;
use Test::More tests => 11;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use DW::CleanEmail;

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
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
    });
    is( $nonquoted, q{
yay testing

yes go.

hello
}, "got nonquoted text from an email with quoted and nonquoted text" );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
testing 123
foo bar

baaaaz});

    is( $nonquoted, q{
testing 123
foo bar

baaaaz}, "got nonquoted text from an email without any quoted text");
}

# gmail fixes
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
foo
On Tue, Apr 23, 2013 at 2:39 PM, ExampleUser
<test@example.com> wrote:
> blah blah
});
    is( $nonquoted, q{
foo}, "got nonquoted text from email, replied via gmail web mail" );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
foo
On 23/04/2013 at 2:39 PM, ExampleUser
<test@example.com> wrote:
> blah blah
});
    is( $nonquoted, q{
foo}, "got nonquoted text from email, replied via android");
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
foo
On Apr 22, 2013 11:22 PM, ExampleUser <test@example.com>
wrote:
> blah blah
});
    is( $nonquoted, q{
foo}, "got nonquoted text from email, other date format");
}
{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
abc
def
On Monday, someone wrote:
tuv
wxyz});
    is( $nonquoted, q{
abc
def}, "'On wrote...' separator a few lines back - cut back to that point" );
}

{
    my $nonquoted = DW::CleanEmail->nonquoted_text(q{
abc
def
On Monday, someone wrote:
qrs
tuv
wxyz});
    is( $nonquoted, q{
abc
def
On Monday, someone wrote:
qrs
tuv
wxyz}, "'On wrote...' separator too many lines back - don't count as end of the message" );
}

{
    my $subject = DW::CleanEmail->reply_subject;
    is( $subject, "", "no subject" );
}

{
    my $subject = DW::CleanEmail->reply_subject( "just a subject" );
    is( $subject, "Re: just a subject", "just a subject" );
}

{
    my $subject = DW::CleanEmail->reply_subject( "Re: nested subject" );
    is( $subject, "Re: nested subject", "subject has Re:" );
}

{
    my $subject = DW::CleanEmail->reply_subject( "Re: Re: Re: very nested subject" );
    is( $subject, "Re: very nested subject", "subject has multiple Re:" );
}
