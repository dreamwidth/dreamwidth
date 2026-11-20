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

use File::Temp qw(tempfile);
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

        my $legacy_url = "http://localhost/editjournal?as=$name&itemid=$id";
        my $legacy     = $cb->( GET $legacy_url );
        ok( $legacy->content =~ $selector, 'the legacy editor also offers the control' );
        my ($legacy_token) = $legacy->content =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
        ok( $legacy_token, 'the legacy editor has a CSRF token' );
        my $legacy_saved = $save->(
            $legacy_url,
            'action:save'        => 1,
            hide_crosspost_links => 1,
            lj_form_auth         => $legacy_token
        );
        ok( $legacy_saved->content =~ /entry was edited/i, 'legacy edit saves successfully' );
        is( $links->(), '', 'saving from the legacy editor also hides the link' );
    };
    LJ::delete_entry( $owner, $entry->jitemid, 0, $entry->anum );
    $owner->do( 'DELETE FROM externalaccount WHERE userid=? AND acctid=?',
        undef, $owner->id, $account_id );
};

{
    my $owner   = temp_user();
    my $name    = $owner->user;
    my $account = DW::External::Account->create(
        $owner,
        {
            servicetype => 'lj',
            servicename => 'Example',
            username    => 'test-crosspost',
            password    => 'fixture-password',
            recordlink  => 1,
            options     => {},
        }
    );
    my $account_id = $account->acctid;
    my $target     = 'https://crosspost.example.invalid/129.html';
    my $mapping    = { $account_id => 129 };
    my $details    = { $account_id => { itemid => 129, url => $target } };

    my @jobs;
    my $dispatch = \&DW::TaskQueue::dispatch;
    no warnings 'redefine';
    local *DW::TaskQueue::dispatch = sub {
        my ( $queue, @tasks ) = @_;
        push @jobs, map { $_->args->[0] } grep { $_->isa('DW::Task::XPost') } @tasks;
        return $dispatch->( $queue, grep { !$_->isa('DW::Task::XPost') } @tasks );
    };

    test_psgi $app, sub {
        my $client  = shift;
        my @editors = ( 'beta', 'legacy', 'beta with legacy format' );
        push @editors, 'beta rich text' if $ENV{DW_TEST_RTE};
        for my $editor (@editors) {
            my $legacy_format = $editor eq 'beta with legacy format';
            my $rich_text     = $editor eq 'beta rich text';

            $owner->set_prop( 'entry_editor2', $legacy_format ? 'html_raw0' : 'html_casual1' );
            my $body =
                $rich_text
                ? '<lj-cut>More</lj-cut>'
                : "An older entry in the $editor editor.\nSecond line.";
            my $entry = $owner->t_post_fake_entry( body => $body );
            $entry->set_prop( 'editor', 'html' ) if $legacy_format;
            $entry->set_prop( 'editor', 'rte0' ) if $rich_text;
            my $id = $entry->ditemid;
            DW::External::Account->record_xpost( $entry, $mapping );
            DW::External::Account->record_xpost_detail( $entry, $details );
            $account = DW::External::Account->get_external_account( $owner, $account_id );
            $account->set_recordlink(0);

            my $beta = $editor ne 'legacy';
            my $path = $beta ? "/entry/$name/$id/edit?" : "/editjournal?itemid=$id&";
            my $base =
                $rich_text
                ? ( $ENV{DW_BROWSER_BASE} // 'http://127.0.0.1:8080' )
                : 'http://localhost';
            my $url = "$base${path}as=$name";
            my ( $button, $destination, $checked, $enabled, $tags ) =
                $beta
                ? ( 'action:post', 'crosspost', $account_id, 'crosspost_entry', 'taglist' )
                : ( 'action:save', "prop_xpost_$account_id", 1, 'prop_xpost_check',
                'prop_taglist' );
            my $form = $client->( GET $url )->content;
            like(
                $form,
                qr/<input(?=[^>]*\bname=["']\Q$destination\E["'])(?=[^>]*\bchecked\b)/,
                "$editor preselects the active destination"
            );
            my ($token) = $form =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
            ok( $token, "$editor issues a form token" );
            my ($formats) = $form =~ /<select\b[^>]*\bname=["']editor["'][^>]*>(.*?)<\/select>/s;
            my ($format) =
                ( $formats // '' ) =~ /<option\b(?=[^>]*\bselected\b)[^>]*\bvalue=["']([^"']+)/;
            is( $format, 'html_raw0', 'legacy format falls back to the current editor preference' )
                if $legacy_format;
            is( $format, 'rte0', 'rich-text entry opens in the rich-text editor' ) if $rich_text;

            my $save = sub {
                my ( $hide, %changes ) = @_;
                @jobs = ();
                my $request;
                if ($rich_text) {
                    my ( $html, $filename ) = tempfile( UNLINK => 1 );
                    print {$html} $client->( GET $url )->content;
                    close $html or die $!;
                    open my $browser, '-|', 'node', 't/browser/lib/entry-edit-submit.js',
                        $filename, $url, $hide, $changes{event} // ''
                        or die $!;
                    my $payload = do { local $/; <$browser> };
                    close $browser or die 'Could not submit the rich-text editor form in Chrome';
                    $request = POST $url,
                        Content_Type => 'application/x-www-form-urlencoded',
                        Content      => $payload;
                }
                else {
                    $request = POST $url,
                        Content => [
                        lj_form_auth         => $token,
                        hide_crosspost_links => $hide,
                        $button              => 1,
                        $enabled             => 1,
                        $destination         => $checked,
                        $beta ? ( editor => $format ) : (),
                        subject  => delete $changes{subject}  // 'test suite post.',
                        event    => delete $changes{event}    // $body,
                        security => delete $changes{security} // 'public',
                        %changes,
                        ];
                }
                my $response = $client->($request);
                like(
                    $response->content,
                    qr/edit was successful|entry was edited/i,
                    "$editor save succeeds"
                );
                LJ::Entry->reset_singletons;
                return LJ::Entry->new( $owner, ditemid => $id );
            };

            for my $hide ( 1, 0 ) {
                my $fresh = $save->($hide);
                is( scalar @jobs, 0, "$editor does not queue a crosspost on visibility-only save" );
                is( $fresh->event_raw, $body,
                    'visibility-only rich-text save keeps original markup' )
                    if $rich_text;
                is( $fresh->prop('editor'), 'html', 'visibility-only save keeps the stored format' )
                    if $legacy_format;
                is_deeply( DW::External::Account->xpost_string_to_hash( $fresh->prop('xpost') ),
                    $mapping, "$editor retains the external ID" );
                is_deeply(
                    DW::External::Account->xpost_string_to_hash( $fresh->prop('xpostdetail') ),
                    $details, "$editor retains the saved URL with Record link off" );
                my %currents = LJ::currents( $fresh->props, $owner );
                if ($hide) {
                    is( $currents{Xpost} // '', '', "$editor hides the link" );
                }
                else {
                    like( $currents{Xpost}, qr/\Q$target\E/, "$editor restores the link" );
                }
            }

            my %changes;
            my $hide = 0;
            my @edits =
                $rich_text
                ? ( [ event => 'New text.' ] )
                : (
                [ event    => 'New text.' ],
                [ subject  => 'New subject' ],
                [ $tags    => 'new tag' ],
                [ security => 'private' ],
                );
            unshift @edits, [ editor => 'html_casual1' ] if $legacy_format;
            for my $change (@edits) {
                my ( $field, $value ) = @$change;
                $changes{$field} = $value;
                my $fresh = $save->( $hide = 1 - $hide, %changes );
                like( $fresh->event_raw, qr/\Q$value\E/, 'rich-text edit saves the new text' )
                    if $rich_text;
                is_deeply(
                    [ map { [ @$_{qw(accountid ditemid delete)} ] } @jobs ],
                    [ [ $account_id, $id, 0 ] ],
                    "$editor queues an external edit for changed $field"
                );
            }
            LJ::delete_entry( $owner, $entry->jitemid, 0, $entry->anum );
        }
    };
    $owner->do( 'DELETE FROM externalaccount WHERE userid=? AND acctid=?',
        undef, $owner->id, $account_id );
}

done_testing;
