# t/emailpost.t
#
# Test posting via email.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Mark Smith <mark@dwscoalition.org>
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

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

use DW::EmailPost;
use LJ::Emailpost::Web;

use LJ::Test;
use FindBin qw($Bin);
use File::Temp;
use MIME::Parser;

local $LJ::T_ALLOW_EMAILPOST = 1; # override caps

my $u = temp_user();
my $emailpin = "emailpin123";

# the brian aker example/bug report
my $mime = get_mime("delspyes", {
    TEMPUSER => $u->user,
    EMAILPIN => $emailpin,
    POSTDOMAIN => "post.$LJ::DOMAIN",
    FROM_EMAIL => 'foo@example.com',
});
ok($mime, "got delspyes MIME");

my ( $email_post, $ok, $msg );
my $user = $u->user;

$email_post = DW::EmailPost->get_handler( $mime );
$email_post->destination( $user );
( $ok, $msg ) = $email_post->process;
ok( ! $ok, "not posted" );
like($msg, qr/No allowed senders have been saved for your account/, "rejected due to no allowed senders");
is( $email_post->dequeue, 1, "and it's deqeueued" );


LJ::Emailpost::Web::set_allowed_senders( $u, { 'foo@example.com' => { get_errors => 1 } } );
is($u->prop("emailpost_allowfrom"), "foo\@example.com(E)", "allowed sender set correctly");


$email_post = DW::EmailPost->get_handler( $mime );
$email_post->destination( $user );
( $ok, $msg ) = $email_post->process;
ok( ! $ok, "not posted" );
like($msg, qr/Unable to locate your PIN/, "rejected due to no PIN");
is( $email_post->dequeue, 1, "and it's deqeueued" );


$email_post = DW::EmailPost->get_handler( $mime );
$email_post->destination( "$user+$emailpin" );
( $ok, $msg ) = $email_post->process;
ok( ! $ok, "not posted" );
like($msg, qr/Invalid PIN/, "rejected due to invalid PIN");
is( $email_post->dequeue, 1, "and it's deqeueued" );


$u->set_prop("emailpost_pin", $emailpin);

$email_post = DW::EmailPost->get_handler( $mime );
$email_post->destination( "$user+$emailpin" );
( $ok, $msg ) = $email_post->process;
ok( $ok, "posted" );
like($msg, qr/Post success/, "posted!");
is( $email_post->dequeue, 1, "and it's deqeueued" );

my $entry = LJ::Entry->new($u, jitemid => 1);
ok($entry->valid, "Entry is valid");
diag("Posted to: " . $entry->url);

my $text = $entry->event_raw;
ok($text !~ qr!http://krow\.livejournal\.com/ 434338\.html!, "no space in URLs.  delsp=yes working.");
ok($text =~ qr!http://krow\.livejournal\.com/434338\.html!, "got correct URL in post, all together.");

sub get_mime {
    my ($filepart, $replace) = @_;
    $replace ||= {};

    my $file = "$Bin/data/emailpost/$filepart.txt";
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    open(my $fh, $file)
        or die "Couldn't open file $file: $!";
    my $outfile = "$tmpdir/email-with-substs-$filepart";
    open(my $newfh, "+>$outfile")
        or die "Couldn't open file $outfile for writing: $!";
    while (<$fh>) {
        s/\$\{(.+?)\}/$replace->{$1} || die "Unknown substitution: $1"/eg;
        print $newfh $_;
    }
    seek($newfh, 0, 0);  # seek to beginning

    my $parser = MIME::Parser->new;
    $parser->output_dir($tmpdir);

    my $entity;
    return eval { $entity = $parser->parse($newfh); };
}


1;
