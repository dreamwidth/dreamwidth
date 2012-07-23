#!/usr/bin/perl
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
use warnings;
BEGIN {
    $ENV{LJHOME} ||= "/home/lj";
}
use lib "$ENV{LJHOME}/cgi-bin";
use lib "$ENV{LJHOME}/extlib/lib/perl5";
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
use Class::Autouse qw(
                      LJ::IncomingEmailHandle
                      );

my $sclient = LJ::theschwartz() or die "No schwartz config.\n";

my $tempfail = sub {
    my $msg = shift;
    warn "Failure: $msg\n" if $msg;
    # makes postfix do temporary failure:
    exit(75);
};

# below this size, we put in database directly.  if over,
# we put in mogile.
sub IN_MEMORY_THRES () {
    return
        $ENV{T_MAILINJECT_THRES_SIZE} ||
        768 * 1024;
}

my $buf;
my $msg = '';  # in-memory message
my $rv;
my $len = 0;
my $ieh;
my $ignore_message = 0;  # bool: to ignore rest of message.
eval {
    while ($rv = sysread(STDIN, $buf, 1024*64)) {
        next if $ignore_message;
        $len += $rv;
        if ($ieh) {
            $ieh->append($buf);
        } else {
            $msg .= $buf;
        }

        if ($len > IN_MEMORY_THRES && ! $ieh) {
            if (should_ignore($msg)) {
                $ignore_message = 1;
                next;
            }

            # allocate a mogile filehandle once we cross the line of
            # what's too big to store in memory and in a schwartz arg
            $ieh = LJ::IncomingEmailHandle->new;
            $ieh->append($msg);
            undef $msg;  # no longer used.
        }
    }
    $tempfail->("Error reading: $!") unless defined $rv;

    if ($ieh) {
        $ieh->closetemp;
        $tempfail->("Size doesn't match") unless $ieh->tempsize == $len;
        $ieh->insert_into_mogile;
    }
};

# just shut postfix up
if ($ignore_message || should_ignore($msg)) {
    exit(0);
}

$tempfail->($@) if $@;

my $h = $sclient->insert(TheSchwartz::Job->new(funcname => "LJ::Worker::IncomingEmail",
                                               arg      => ($ieh ? $ieh->id : $msg)));
exit 0 if $h;
exit(75);  # temporary error

# it pays to get rid of as many bounces and gibberish now, before we
# have to put it in the database, mogile, allocate ids, run workers,
# move disks around, etc..  so these are just quick & dirty checks.
sub should_ignore {
    my $msg = shift;
    return 0 unless $msg;
    return 1 if $msg =~ /^Return-Path:\s+<>/im;

    my ($subject) = $msg =~ /^Subject: (.+)/im;
    if ($subject) {
        return 1 if
            $subject =~ /auto.?(response|reply)/i
            || $subject =~ /^(Undelive|Mail System Error - |ScanMail Message: |\+\s*SPAM|Norton AntiVirus)/i
            || $subject =~ /^(Mail Delivery Problem|Mail delivery failed)/i
            || $subject =~ /^failure notice$/i
            || $subject =~ /\[BOUNCED SPAM\]/i
            || $subject =~ /^Symantec AVF /i
            || $subject =~ /Attachment block message/i
            || $subject =~ /Use this patch immediately/i
            || $subject =~ /^don\'t be late! ([\w\-]{1,15})$/i
            || $subject =~ /^your account ([\w\-]{1,15})$/i
            || $subject =~ /Message Undeliverable/i;
    }

    return 0;
}
