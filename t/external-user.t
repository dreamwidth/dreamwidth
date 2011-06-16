# -*-perl-*-

use strict;
use Test::More tests => 14;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use DW::External::User;

note( "Username with capital letters" );
{
    my $u = DW::External::User->new(
        user => "ExampleUsername",
        site => "twitter.com"
    );

    is( $u->site->{hostname}, "twitter.com", "Site is twitter.com" );
    is( $u->user, "ExampleUsername", "Keep capital letters" );
}

note( "Username with capital letters (LJ-based site)" );
{
    my $u = DW::External::User->new(
        user => "ExampleUsername",
        site => "livejournal.com"
    );

    is( $u->site->{hostname}, "www.livejournal.com", "Site is livejournal.com" );
    is( $u->user, "exampleusername", "Lowercase this" );
}


note( "Username with spaces" );
{
    my $u = DW::External::User->new(
        user => " exampleusername    ",
        site => "twitter.com"
    );

    is( $u->site->{hostname}, "twitter.com", "Site is twitter.com" );
    is( $u->user, "exampleusername", "Ignore spaces" );
}

note( "Username with spaces (LJ-based site)" );
{
    my $u = DW::External::User->new(
        user => " exampleusername    ",
        site => "livejournal.com"
    );

    is( $u->site->{hostname}, "www.livejournal.com", "Site is livejournal.com" );
    is( $u->user, "exampleusername", "Ignore spaces" );
}


note( "Username with non-alphanumeric punctuation" );
{
    my $u = DW::External::User->new(
        user => "<exampleusername>",
        site => "twitter.com"
    );

    is( $u, undef, "Looks weird. Reject it" );
}

note( "Username with non-alphanumeric punctuation (LJ-based site)" );
{
    my $u = DW::External::User->new(
        user => "<exampleusername>",
        site => "livejournal.com"
    );

    is( $u, undef, "Looks weird. Reject it" );
}


note( "Username with hyphen" );
{
    my $u = DW::External::User->new(
        user => "example-username",
        site => "twitter.com"
    );

    is( $u->site->{hostname}, "twitter.com", "Site is twitter.com" );
    is( $u->user, "example-username", "Hyphens are ok" );
}

note( "Username with hyphen (LJ-based site)" );
{
    my $u = DW::External::User->new(
        user => "example-username",
        site => "livejournal.com"
    );

    is( $u->user, "example_username", "Canonicalize usernames from LJ-based sites" );
    is( $u->site->{hostname}, "www.livejournal.com", "Site is livejournal.com" );
}

1;

