# t/plack-edit-crosspost-links.t
#
# Test editing the visibility of links to existing crossposts.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::External::Account;
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'editCrosspostLinks';
local $LJ::BETA_FEATURES{updatepage}  = {};

with_fake_memcache {
    my $owner           = temp_user();
    my $visitor         = temp_user();
    my $name            = $owner->user;
    my $entry           = $owner->t_post_fake_entry( body => 'An older entry.' );
    my $id              = $entry->ditemid;
    my $target          = 'https://crosspost.example.invalid/129.html';
    my $deleted_account = DW::External::Account->create(
        $owner,
        {
            servicetype => 'lj',
            servicename => 'Example',
            username    => 'test-crosspost',
            recordlink  => 1,
            options     => {},
        }
    );
    my $account_id = $deleted_account->acctid;
    my $mapping    = { $account_id => 129, $account_id + 1 => 142 };
    my $details    = {
        $account_id     => { itemid => 129, url => $target },
        $account_id + 1 => { itemid => 142 },
    };
    DW::External::Account->record_xpost( $entry, $mapping );
    DW::External::Account->record_xpost_detail( $entry, $details );
    $owner->do( "UPDATE externalaccount SET active='0', password=NULL WHERE userid=? AND acctid=?",
        undef, $owner->id, $account_id )
        or die $owner->errstr;
    is( scalar( DW::External::Account->get_external_accounts($owner) ),
        0, 'the crossposting account is no longer active' );

    my $links = sub {
        LJ::Entry->reset_singletons;
        my $fresh    = LJ::Entry->new( $owner, ditemid => $id );
        my %currents = LJ::currents( $fresh->props, $owner );
        return $currents{Xpost} // '';
    };
    like( $links->(), qr/\Q$target\E/, 'the old crosspost link still renders' );

    test_psgi $app, sub {
        my $cb       = shift;
        my $url      = "http://localhost/entry/$name/$id/edit?as=$name";
        my $selector = qr/name=["']hide_crosspost_links["']/;
        my $form     = $cb->( GET $url );
        is( $form->code, 200, 'edit page loads' );
        ok( $form->content =~ $selector,
            'edit form offers a visibility control after account deletion' );
        my $unlinked = $owner->t_post_fake_entry;
        DW::External::Account->record_xpost_detail( $unlinked,
            { $account_id => { itemid => 130 } } );
        my $unlinked_form =
            $cb->( GET "http://localhost/entry/$name/" . $unlinked->ditemid . "/edit?as=$name" );
        ok( $unlinked_form->content !~ $selector,
            'entries crossposted without a link have no control' );
        LJ::delete_entry( $owner, $unlinked->jitemid, 0, $unlinked->anum );
        my ($token) = $form->content =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
        ok( $token, 'form has a CSRF token' );

        my $save = sub {
            my ( $path, %extra ) = @_;
            my %fields = (
                lj_form_auth => $token,
                subject      => 'Edited entry',
                event        => 'An edited older entry.',
                security     => 'public',
                editor       => 'html',
                %extra,
            );
            return $cb->( POST $path, Content => [%fields] );
        };

        $save->( $url, 'action:preview' => 1, hide_crosspost_links => 1 );
        like( $links->(), qr/\Q$target\E/, 'preview does not change the live entry' );

        $save->( $url, 'action:post' => 1, hide_crosspost_links => 1, lj_form_auth => 'invalid' );
        like( $links->(), qr/\Q$target\E/, 'an invalid form token cannot hide links' );

        my $foreign_url  = "http://localhost/entry/$name/$id/edit?as=" . $visitor->user;
        my $foreign_form = $cb->( GET "http://localhost/entry/new?as=" . $visitor->user );
        my ($foreign_token) =
            $foreign_form->content =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
        ok( $foreign_token, 'another user has their own form token' );
        $save->(
            $foreign_url,
            'action:post'        => 1,
            hide_crosspost_links => 1,
            lj_form_auth         => $foreign_token
        );
        like( $links->(), qr/\Q$target\E/, 'another user cannot hide links' );

        my $res = $save->( $url, 'action:post' => 1, hide_crosspost_links => 1 );
        ok( $res->content =~ /edit was successful/i, 'saving the entry succeeds' );
        is( $links->(), '', 'saving with links hidden removes the link from the entry' );

        my $reopened = $cb->( GET $url );
        ok( $reopened->content =~ /$selector[^>]*>.*?<option value="1" selected/s,
            'reopening the editor shows the saved visibility' );

        $save->( $url, 'action:post' => 1 );
        is( $links->(), '', 'a later edit without the field leaves links hidden' );

        my $fresh = LJ::Entry->new( $owner, ditemid => $id );
        is_deeply( DW::External::Account->xpost_string_to_hash( $fresh->prop('xpost') ),
            $mapping, 'the IDs used to edit crossposts are preserved' );
        is_deeply( DW::External::Account->xpost_string_to_hash( $fresh->prop('xpostdetail') ),
            $details, 'the original crosspost references are preserved' );

        $save->( $url, 'action:post' => 1, hide_crosspost_links => 0 );
        like( $links->(), qr/\Q$target\E/, 'the owner can show the link again' );

        my $simple_url = "$url&mode=simple";
        my $simple     = $cb->( GET $simple_url );
        ok( $simple->content =~ $selector, 'the simple layout also offers the control' );
        my ($simple_token) = $simple->content =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
        ok( $simple_token, 'the simple layout has a CSRF token' );
        my $simple_saved = $save->(
            $simple_url,
            'action:post'        => 1,
            hide_crosspost_links => 1,
            lj_form_auth         => $simple_token
        );
        ok( $simple_saved->content =~ /edit was successful/i, 'simple layout edit saves successfully' );
        is( $links->(), '', 'saving from the simple layout also hides the link' );
    };
    LJ::delete_entry( $owner, $entry->jitemid, 0, $entry->anum );
    $owner->do( 'DELETE FROM externalaccount WHERE userid=? AND acctid=?',
        undef, $owner->id, $account_id );
};

done_testing;
