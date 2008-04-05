#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";

require "ljlib.pl";
require "ljprotocol.pl";
require "communitylib.pl";

use LJ::Entry;
use LJ::SMS;
use LJ::SMS::MessageHandler::Read;
use LJ::Test qw(memcache_stress temp_user);

# save the sent message in a global so we can check it
my $SENT_MSG = undef;
$LJ::_T_SMS_SEND = sub { $SENT_MSG = shift };

sub run_tests {

    # ->owns
    {
        # set up test accounts
        my $u = temp_user();
        my $user = $u->{user};

        # set up account settings
        $u->set_sms_number('+15555551212', verified => 'Y');

        $LJ::DISABLED{sms_quota_check} = 1;
        LJ::update_user($u, { status => 'A' });

        # post an entry to this user account
        my $entry = $u->t_post_fake_entry
            (
             subject => "This is a test subject",
             body    => LJ::rand_chars(160*8)
             );

        # special case, $page0 should be equal to $page1 exactly
        my $page0_ret;
        my @pages_ret;

        foreach my $cmd (qw(read ReAd r R)) {

            # common header for each message page
            # -- declared here and modified throughout test
            my $header;

          PAGE:
            foreach my $page (0..25) {
                my $psuf = $page ? ".$page" : "";
                my $text = "$cmd$psuf $user";

                # replace {\d} with page number for matching
                $header =~ s/\(\d+([^\)]*)\)/\($page$1\)/;

                my $msg = LJ::SMS::Message->new
                    (
                     owner => $u,
                     type  => 'incoming',
                     from  => $u,
                     to    => '12345',
                     body_text => $text
                     );

                my $rv = LJ::SMS::MessageHandler::Read->owns($msg);
                ok($rv, "owns: $text");
                $rv = eval { LJ::SMS::MessageHandler->handle($msg) };
                my $ok = $rv && ! $@ && $msg && $msg->is_success && ! $msg->error;
                ok($ok && ref $SENT_MSG, "handle: $text");

                {
                    my $sent = $SENT_MSG;
                    my $sent_text = $sent->body_text;

                    # special case, page 0 (no page specified) should equal page 1
                    if ($page == 0) {
                        $page0_ret = $sent_text;
                        
                        # now find the header out of here
                        my $idx = index($page0_ret, "[" . $entry->subject_orig);
                        $header = substr($page0_ret, 0, $idx);
                    }
                    if ($page == 1) {
                        ok($page0_ret = $sent_text, "page 0 matches page 1: $text")
                    }
                    if ($page > 0) {
                        last PAGE if $page > 1 && $sent_text eq $page0_ret;

                        my $idx = do { use bytes; length($header) };
                        $sent_text = substr($sent_text, $idx);
                        $sent_text =~ s/\.\.\.$//;
                        push @pages_ret, $sent_text;
                    }
                }

                ok($msg->meta("handler_type") eq "Read", "handler_type prop set: $text");
            }

            {
                my $subj = $entry->subject_orig;
                my $body = $entry->event_orig;
                ok(join("", @pages_ret) =~ /^.+?$subj.+?$body\.*$/, "paging adds up: $cmd");
            }
        }
    }

    # protocol failure

    # protocol success


}

run_tests();

