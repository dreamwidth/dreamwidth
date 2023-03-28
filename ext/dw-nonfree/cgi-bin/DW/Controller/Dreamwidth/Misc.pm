#!/usr/bin/perl
#
# DW::Controller::Dreamwidth::Misc
#
# Controller for Dreamwidth specific miscellaneous pages.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2016 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Controller::Dreamwidth::Misc;

use strict;
use warnings;
use DW::Routing;

DW::Routing->register_static( '/about', 'misc/about.tt', app => 1 );

DW::Routing->register_static( '/site/bot',    'site/bot.tt',    app => 1 );
DW::Routing->register_static( '/site/brand',  'site/brand.tt',  app => 1 );
DW::Routing->register_static( '/site/policy', 'site/policy.tt', app => 1 );

DW::Routing->register_string( "/internal/local/404", \&error_404_handler, app => 1 );

sub error_404_handler {
    my @quips = (
        "I accidentally your page :(",
        "Invisible Content!",
        "We can't stop here... this is 404 country!",
        "Not found page is not found.",
        "That's no moon - it's a 404!",
        "Fetch, or fetch not. There is no 404",
        "Quoth the server: four oh four.",
        "Tonight, we browse in 404!",
        "Curse your sudden but inevitable 404!",
        "404: the lights have gone out. Careful, you might get eaten by a grue.",
        "Why did the 404 cross the road? Because it couldn't find a page to cross.",
        "404: the page is a lie.",
        "404 ALL the things?",
        "Never gonna run around and 404 you...",
        "THERE ... ARE ... 404 ... LIGHTS!",
        "We'll always have 404.",
        "The sky above the port was the color of television tuned to a 404'd page.",
        "There was a PAGE here. it's gone now.",
        "Oh dear.",
        "It's dangerous to browse alone! Take this.",
        "Thank you, Mario! But the page is in another castle.",
        "Holy flying 404, Batman!",
        "KHAAAAAAAAAAAANNNNNNNNNNN!",
        "What is your quest? 404!",
        "But WHY is the page gone?",
        "Ia! Ia! 404 fthagn!",
        "418 I'm A Teapot ... wait, no, 404 Not Found.",
        "i'm in ur server, 404ing ur pages",
        "These are not the 404s you're looking for.",
        "Heisenberg may or may not have 404ed here.",
    );

    my $quip = $quips[ int( rand( scalar @quips ) ) ];
    return DW::Template->render_template( 'error/404.tt', { quip => $quip } );
}

1;
