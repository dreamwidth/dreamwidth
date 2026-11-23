# t/plack-talkpost.t
#
# Tests for comment posting previews through /talkpost_do: a preview reflects
# the entry and parent as the commenter would see them, and the unscreen-parent
# option follows the same permission check as the form control that offers it.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# ?as= impersonation is dev-only; form auth binds to a fixed uniq below.
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'talkpostTest';

my $owner    = temp_user();
my $author   = temp_user();
my $stranger = temp_user();

# Validated email, so they're allowed to comment.
$_->update_self( { status => 'A' } ) for ( $owner, $author, $stranger );

my $public  = $owner->t_post_fake_entry;
my $private = $owner->t_post_fake_entry(
    subject  => 'ENTRY_SUBJECT_TOKEN',
    body     => 'ENTRY_BODY_TOKEN',
    security => 'private',
);
my $screened = $public->t_enter_comment(
    u       => $author,
    state   => 'S',
    subject => 'PARENT_SUBJECT_TOKEN',
    body    => 'PARENT_BODY_TOKEN',
);

# Record or no-op the side effects we don't want to run for real.
my @unscreened;
no warnings 'redefine';
local *LJ::Talk::unscreen_comment = sub { push @unscreened, [@_]; 1 };
local *LJ::User::set_suspended    = sub { 1 };
my $run_hooks = \&LJ::Hooks::run_hooks;
local *LJ::Hooks::run_hooks = sub {
    return if $_[0] eq 'spam_check';
    return $run_hooks->(@_);
};
use warnings 'redefine';

with_fake_memcache {
    test_psgi $app, sub {
        my $cb = shift;

        # POST a comment (or a preview of one) to $entry, optionally replying to
        # $parent, as $viewer (undef = anonymous), via dev ?as= impersonation.
        my $talkpost = sub {
            my ( $viewer, $entry, $parent, %extra ) = @_;
            my $as = $viewer ? $viewer->user : 'nobody_exists';

            # Mint a form-auth token bound to this viewer and the fixed uniq,
            # which is what the app recomputes for the ?as= request.
            LJ::set_remote($viewer);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $form_auth = LJ::form_auth(1);
            LJ::set_remote(undef);

            my $parenttalkid = $parent ? $parent->jtalkid : 0;
            return $cb->(
                POST "http://localhost/talkpost_do?as=$as",
                Content => [
                    lj_form_auth => $form_auth,
                    chrp1        => LJ::Talk::generate_chrp1( $entry->journalid, $entry->ditemid ),
                    journal      => $entry->journal->user,
                    itemid       => $entry->ditemid,
                    parenttalkid => $parenttalkid,
                    replyto      => $parenttalkid,
                    (
                        $viewer
                        ? ( usertype => 'cookieuser', cookieuser => $viewer->user )
                        : ( usertype => 'anonymous' )
                    ),
                    subject => 'reply subject',
                    body    => 'reply body ' . rand(),
                    %extra,
                ],
            );
        };

        # 1. A preview reflects the entry and parent only when the commenter can
        #    read them.
        for my $viewer ( undef, $stranger ) {
            my $who = $viewer ? 'a logged-in stranger' : 'an anonymous visitor';

            my $res = $talkpost->( $viewer, $private, undef, submitpreview => 1 );
            unlike(
                $res->content,
                qr/ENTRY_(?:SUBJECT|BODY)_TOKEN/,
                "preview renders no unreadable entry for $who"
            );

            $res = $talkpost->( $viewer, $public, $screened, submitpreview => 1 );
            unlike(
                $res->content,
                qr/PARENT_(?:SUBJECT|BODY)_TOKEN/,
                "preview renders no unreadable parent for $who"
            );
        }

        # 2. The unscreen-parent option follows the same permission as the form
        #    checkbox: the parent comment's own author sees it but can't unscreen.
        @unscreened = ();
        $talkpost->( $author, $public, $screened, unscreen_parent => 1 );
        is( scalar @unscreened, 0, 'unscreen-parent option is ignored without permission' );

        # And it still works for someone who can (the journal owner).
        @unscreened = ();
        $talkpost->( $owner, $public, $screened, unscreen_parent => 1 );
        ok( scalar @unscreened, 'unscreen-parent option works with permission' );
    };
};

done_testing();
