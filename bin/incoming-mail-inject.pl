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
use v5.10;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Digest::MD5 qw/ md5_hex /;
use DW::BlobStore;

my $sclient = LJ::theschwartz() or die "No schwartz config.\n";

my $tempfail = sub {
    my $msg = shift;
    warn "Failure: $msg\n" if $msg;

    # makes postfix do temporary failure:
    exit 75;
};

# below this size, we put in database directly.  if over,
# we put in mogile.
sub IN_MEMORY_THRES () {
    return $ENV{T_MAILINJECT_THRES_SIZE}
        || 768 * 1024;
}

my $msg = '';    # in-memory message
my $len = 0;     # length of message

eval {
    my ( $buf, $rv );
    while ( $rv = sysread STDIN, $buf, 1024 * 64 ) {
        $len += $rv;
        $msg .= $buf;
    }
    $tempfail->("Error reading: $!")
        unless defined $rv;

    if ( should_ignore($msg) ) {
        $log->info("Received probable spam message of $len bytes, dropping");
        exit 0;
    }

    $log->info("Received email of $len bytes, saving for handling");
};
$tempfail->($@) if $@;

if ( $len > IN_MEMORY_THRES ) {
    my $md5 = md5_hex($msg);
    DW::BlobStore->store( temp => "ie:$md5", \$msg );
    $log->info("Storing email in blobstore at key: ie:$md5");

    # Overwrite $msg so that the incoming-email worker knows that this
    # is a key it should look up in the storage system
    $msg = "ie:$md5";
}

my $h = $sclient->insert(
    TheSchwartz::Job->new(
        funcname => "LJ::Worker::IncomingEmail",
        arg      => $msg,
    ),
);
exit 0 if $h;
exit 75;    # temporary error

# it pays to get rid of as many bounces and gibberish now, before we
# have to put it in the database, mogile, allocate ids, run workers,
# move disks around, etc..  so these are just quick & dirty checks.
sub should_ignore {
    my $msg = shift;
    return 0 unless $msg;
    return 1 if $msg =~ /^Return-Path:\s+<>/im;

    my ($subject) = $msg =~ /^Subject: (.+)/im;
    if ($subject) {
        return 1
            if $subject =~ /auto.?(response|reply)/i
            || $subject =~
            /^(Undelive|Mail System Error - |ScanMail Message: |\+\s*SPAM|Norton AntiVirus)/i
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
