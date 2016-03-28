#!/usr/bin/perl
# TODO: check license
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use DW::Captcha;
use DW::Captcha::textCAPTCHA;

our %maint;

$maint{cache_textcaptcha} = sub {
    return unless DW::Captcha->new( undef, want => "textcaptcha" )->site_enabled;
    print " - I - Caching textcaptcha items.\n";

    my $MAX_CACHED = $LJ::TEXTCAPTCHA_MAX_PREFETCH || 500;

    my $count = DW::Captcha::textCAPTCHA::Logic->unused_count;
    my $need;

    if ( $count >= $MAX_CACHED ) {
        print "already have enough textcaptcha items.\n";
        return;
    }

    my $need = $MAX_CACHED - $count;
    print "pre-fetching $need textcaptcha items.\n";

    # pre-fetch. Gradually ease off the timer if we were unable to get a captcha.
    # If we tried and failed too many times, stop for now.
    # We can always try again next time we run maint tasks
    my @backoff_timer = ( 1, 3, 5, 0 );
    my $delay = 1;
    my @fetched_captchas = ();
    foreach my $i ( 1...$need ) {
        my $captcha = DW::Captcha::textCAPTCHA::Logic->get_from_remote_server;

        if ( $captcha ) {
            push @fetched_captchas, $captcha;
        } else {
            $delay = shift @backoff_timer;
            print $delay ? "setting delay to $delay.\n" : "ending on attempt #$i with " . scalar @fetched_captchas . " fetched.\n";
            last unless $delay;
        }

        if ( scalar @fetched_captchas >= 10 ) {
            print "...flushing to DB\n";
            DW::Captcha::textCAPTCHA::Logic->save_multi( @fetched_captchas );
            @fetched_captchas = ();
        }

        sleep $delay;
    }

    DW::Captcha::textCAPTCHA::Logic->save_multi( @fetched_captchas ) if @fetched_captchas;
    return 1;
};

$maint{clean_captchas} = sub {
    print " - I - Cleaning captchas.\n";

    my $count = DW::Captcha::textCAPTCHA::Logic->cleanup;

    print "Done: deleted $count expired captchas.\n";

    return 1;
};

1;
