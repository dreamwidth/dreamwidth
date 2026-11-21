# t/plack-editjournal.t
#
# Test /editjournal save and delete handling for pasted control characters and
# malformed UTF-8 in entry subjects and bodies.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use LJ::Entry;
use LJ::Test qw( temp_user );

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'editjournalTest';

my $u     = temp_user();
my $entry = $u->t_post_fake_entry(
    subject => 'Initial subject',
    body    => 'Initial body',
);
my $ditemid = $entry->ditemid;

my $run_hooks = \&LJ::Hooks::run_hooks;
no warnings 'redefine';
local *LJ::Hooks::run_hooks = sub {
    return if $_[0] eq 'spam_check';
    return $run_hooks->(@_);
};
use warnings 'redefine';

test_psgi $app, sub {
    my $cb = shift;

    my $submit = sub {
        my (%fields) = @_;
        LJ::set_remote($u);
        delete $LJ::REQ_GLOBAL{form_auth_chal};
        my $form_auth = LJ::form_auth(1);
        LJ::set_remote(undef);

        return $cb->(
            POST 'http://localhost/editjournal?as=' . $u->user,
            Content => [
                lj_form_auth => $form_auth,
                itemid       => $ditemid,
                mode         => 'edit',
                security     => 'public',
                %fields,
            ],
        );
    };

    my $clean_subject = "\xe2\x80\x98Edited journey\xe2\x80\xa6\xe2\x80\x99";
    my $clean_body    = "caf\xc3\xa9, cafe\xcc\x81, \xf0\x9f\x8e\x89\nThis happened in 2000.";

    subtest 'save strips pasted controls while preserving valid UTF-8' => sub {
        my $res = $submit->(
            'action:save' => 1,
            subject       => "$clean_subject\x08",
            event         => "\x0b"
                . "caf\xc3\xa9, cafe\xcc\x81, \xf0\x9f\x8e\x89\nThis happened in \x082000.\x1f",
        );
        is( $res->code, 200, 'edit save responds 200' );
        unlike(
            $res->content,
            qr/bml\.badinput|not a valid UTF-8 stream|Bad Unicode Input/i,
            'no UTF-8 error shown on save'
        );

        LJ::Entry->reset_singletons;
        my $saved = LJ::Entry->new( $u, ditemid => $ditemid );
        is( $saved->subject_raw, $clean_subject, 'subject saved with controls stripped' );
        is( $saved->event_raw,   $clean_body,    'body saved with controls stripped' );
    };

    subtest 'save rejects malformed UTF-8 and NUL without modifying entry' => sub {
        for my $bad ( "\xc3\x08\xa9", "2000\x00" ) {
            my $res = $submit->(
                'action:save' => 1,
                subject       => 'Should not save',
                event         => $bad,
            );
            is( $res->code, 200, 'rejected edit responds 200' );
            like(
                $res->content,
qr/bml\.badinput|Bad Unicode Input|not a valid UTF-8 stream|isn't recognised as valid text/i,
                'rejected edit reports invalid UTF-8'
            );

            LJ::Entry->reset_singletons;
            my $unchanged = LJ::Entry->new( $u, ditemid => $ditemid );
            is( $unchanged->subject_raw, $clean_subject, 'subject unchanged after rejection' );
            is( $unchanged->event_raw,   $clean_body,    'body unchanged after rejection' );
        }
    };

    subtest 'delete is not blocked by malformed text in submitted form' => sub {
        my $res = $submit->(
            'action:delete' => 1,
            subject         => "\xff\xfe",
            event           => "\xc3\x08\xa9\x00",
        );
        is( $res->code, 200, 'delete responds 200' );
        unlike(
            $res->content,
            qr/bml\.badinput|Bad Unicode Input|not a valid UTF-8 stream/i,
            'delete does not fail UTF-8 check'
        );

        LJ::Entry->reset_singletons;
        my $deleted = LJ::Entry->new( $u, ditemid => $ditemid );
        ok( !$deleted->valid, 'entry was deleted' );
    };
};

done_testing;
