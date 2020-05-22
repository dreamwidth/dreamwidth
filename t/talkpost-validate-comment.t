# t/talkpost-authenticate-user.t
#
# Test the thing that authenticates users when submitting a comment through the
# web forms.
#
# Authors:
#      Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );

use LJ::Entry;
use LJ::Talk;

plan tests => 6;

# Refresher on form structure:
#   - body
#   - subject
#   - prop_something (various)
#   - editid and editreason, if editing
#   - parenttalkid: integer, comment being replied to (0 if replying to entry)
#   - replyto: duplicate of parenttalkid, for some reason
#   - subjecticon
#   - any captcha-related fields from the talkform (varies by captcha type)
#   - all other fields are ignored. MOST NOTABLY, this function stays away from
#   the user info fields.

my $journalu = temp_user();
my $entry    = $journalu->t_post_fake_entry();

note("Comment form from a logged in user:");

my $form = {
    body        => "Comment body",
    subject     => "Comment subject",
    subjecticon => "none",
};

my $commenter    = temp_user();
my $need_captcha = 0;
my @errors       = ();
my $comment;

# There's a nasty observer effect due to this cache: once something asks whether
# two users have a particular relationship, you can never again modify that
# relationship. And prepare_and_validate_comment asks about basically every
# possible relationship. So SCORCH THE EARTH.
my $reset = sub {
    foreach ( keys %LJ::REQ_CACHE_REL ) {
        delete $LJ::REQ_CACHE_REL{$_};
    }
    $comment      = undef;
    @errors       = ();
    $need_captcha = 0;
};

note("...who ain't validated:");
$comment = LJ::Talk::Post::prepare_and_validate_comment( $form, $commenter, $entry, \$need_captcha,
    \@errors );
ok( !defined $comment, "Returned undef, not allowed." );
note( scalar @errors . " Validation errors: " . join( "\n", @errors ) );
$reset->();

note("...who has validated their email:");
$commenter->update_self( { status => 'A' } );
$comment = LJ::Talk::Post::prepare_and_validate_comment( $form, $commenter, $entry, \$need_captcha,
    \@errors );
ok( ref $comment eq 'HASH', "Succeeded, returned comment" );
ok( scalar @errors == 0,    "Didn't append any errors" );
note( scalar @errors . " Validation errors: " . join( "\n", @errors ) );
ok( $comment->{body} eq $form->{body}, "Comment body survived" );
ok( $comment->{subjecticon} eq '',     "'none' subjecticon (w/ left beef) munged to empty string" );
$reset->();

note("...who's banned:");
$journalu->ban_user($commenter);
$comment = LJ::Talk::Post::prepare_and_validate_comment( $form, $commenter, $entry, \$need_captcha,
    \@errors );
ok( !defined $comment, "Returned undef, not allowed." );
note( scalar @errors . " Validation errors: " . join( "\n", @errors ) );
$reset->();

