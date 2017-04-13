# t/emailpost-comment.t
#
# Test replying to comments via email.
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

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::EmailPost::Comment;
use LJ::Test;

my $subject;
my $u = temp_user();

my $e = $u->t_post_fake_entry;

my $username = $u->display_name;
my $ditemid = $e->ditemid;
my $generated = " [ $username - $ditemid ]";

my $c_parent = $e->t_enter_comment;
my $c1 = $e->t_enter_comment( parent => $c_parent );

#   email subject       parent comment subject
#    generated                  none                 - none
#    generated                  custom               - Re: custom parent
#    custom                     none                 - custom from email
#    custom                     custom               - custom from email

$c_parent->set_subject( "" );
$subject = DW::EmailPost::Comment->determine_subject(
    "Re: Reply to an entry. $generated",
    $u, $ditemid, $c_parent->dtalkid
);
is( $subject, "", "default parent subject, default email subject" );

$c_parent->set_subject( "Some custom subject" );
$subject = DW::EmailPost::Comment->determine_subject(
    "Re: Some custom subject $generated",
    $u, $ditemid, $c_parent->dtalkid
);
is( $subject, "Re: Some custom subject", "custom parent subject, default email subject" );

$c_parent->set_subject( "Make sure punctuation isn't escaped" );
$subject = DW::EmailPost::Comment->determine_subject(
    "Re: Make sure punctuation isn't escaped $generated",
    $u, $ditemid, $c_parent->dtalkid
);
is( $subject, "Re: Make sure punctuation isn't escaped", "punctuated parent subject, default email subject" );

$c_parent->set_subject( "" );
$subject = DW::EmailPost::Comment->determine_subject(
    "Change of topic mid-thread",
    $u, $ditemid, $c_parent->dtalkid
);
is( $subject, "Change of topic mid-thread", "default parent subject, custom email subject" );

$c_parent->set_subject( "Some custom subject" );
$subject = DW::EmailPost::Comment->determine_subject(
    "Change of topic mid-thread",
    $u, $ditemid, $c_parent->dtalkid
);
is( $subject, "Change of topic mid-thread", "custom parent subject, custom email subject" );

$subject = DW::EmailPost::Comment->determine_subject(
    "Make sure punctuation isn't escaped",
    $u, $ditemid, $c_parent->dtalkid
);
is( $subject, "Make sure punctuation isn't escaped", "custom parent subject, punctuated email subject" );
