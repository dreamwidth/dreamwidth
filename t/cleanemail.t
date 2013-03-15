# -*-perl-*-

use strict;
use Test::More tests => 6;
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