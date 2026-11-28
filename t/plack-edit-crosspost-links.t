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
use HTML::Form;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::External::Account;
use LJ::Test qw(temp_user with_fake_memcache);

my $temporary_logproplist;

END {
    $temporary_logproplist->do('DROP TEMPORARY TABLE logproplist')
        if $temporary_logproplist && $temporary_logproplist->{Active};
}

unless ( LJ::get_prop( 'log', 'opt_hide_xpost_links' ) ) {
    my $reader = LJ::get_db_reader();
    local $reader->{RaiseError} = 1;
    $reader->do('CREATE TEMPORARY TABLE logproplist SELECT * FROM logproplist');
    $temporary_logproplist = $reader;
    my ($propid) = $reader->selectrow_array('SELECT MAX(propid) + 1 FROM logproplist');
    $reader->do(
        q{INSERT INTO logproplist
          (propid, name, datatype, scope, des, prettyname, sortorder, ownership)
          VALUES (?, ?, 'bool', 'general', ?, ?, 107, 'user')},
        undef, $propid, 'opt_hide_xpost_links',
        q{Do not display this entry's links to crossposts}, 'Hide Links to Crossposts'
    );
    delete $LJ::CACHE_PROP{log};
    delete $LJ::CACHE_PROPID{log};
    LJ::load_props('log');
}

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'editCrosspostLinks';

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
        ok(
            $simple_saved->content =~ /edit was successful/i,
            'simple layout edit saves successfully'
        );
        is( $links->(), '', 'saving from the simple layout also hides the link' );
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
        my @editors = (
            [ 'advanced',                    'html_casual1' ],
            [ 'simple',                      'html_casual1' ],
            [ 'advanced with legacy format', 'html' ],
            [ 'simple with legacy format',   'html' ],
            [ 'advanced rich text',          'rte1' ],
            [ 'advanced retired rich text',  'rte0' ],
            [ 'simple retired rich text',    'used_rte' ],
            [ 'advanced retired rich text with an edit', 'rte0', 0, 1 ],
        );
        if ( $ENV{DW_TEST_RTE} ) {
            push @editors, [ 'advanced rich text in Chrome', 'rte1', 1 ],
                [ 'simple retired rich text in Chrome', 'rte0', 1 ];
        }
        for my $case (@editors) {
            my ( $label, $saved_format, $chrome, $edit_first ) = @$case;
            my $legacy_format = $saved_format eq 'html';
            my $retired       = $saved_format eq 'rte0' || $saved_format eq 'used_rte';
            my $rich_text     = $retired || $saved_format eq 'rte1';

            $owner->set_prop( 'entry_editor2', $legacy_format ? 'html_raw0' : 'html_casual1' );
            my $body =
                  $saved_format eq 'used_rte' ? '<p>Single-line legacy rich text.</p>'
                : $rich_text                  ? "<lj-cut>More\nin the $label editor.</lj-cut>"
                :   "An older entry in the $label editor.\nSecond line.";
            my $expected_body = $body;
            $expected_body =~ s/\n/<br \/>/g if $retired;
            my $entry = $owner->t_post_fake_entry( body => $body );

            if ( $saved_format eq 'used_rte' ) {
                $entry->set_prop( 'editor',   undef );
                $entry->set_prop( 'used_rte', 1 );
            }
            else {
                $entry->set_prop( 'editor', $saved_format );
            }
            my $id = $entry->ditemid;
            DW::External::Account->record_xpost( $entry, $mapping );
            DW::External::Account->record_xpost_detail( $entry, $details );
            $account = DW::External::Account->get_external_account( $owner, $account_id );
            $account->set_recordlink(0);

            my $base =
                $chrome
                ? ( $ENV{DW_BROWSER_BASE} // 'http://127.0.0.1:8080' )
                : 'http://localhost';
            my $url = "$base/entry/$name/$id/edit?as=$name";
            $url .= '&mode=simple' if $label =~ /\Asimple\b/;
            my $html = $client->( GET $url )->content;
            like(
                $html,
                qr/<input(?=[^>]*\bname=["']crosspost["'])(?=[^>]*\bchecked\b)/,
                "$label preselects the active destination"
            );
            my ($form) = grep { $_->find_input('event') } HTML::Form->parse( $html, $url );
            $form->action($url);
            ok( $form->value('lj_form_auth'), "$label issues a form token" );

            if ($legacy_format) {
                is( $form->value('editor'),
                    'html_raw0', 'legacy entry opens in the preferred HTML format' );
                $owner->set_prop( 'entry_editor2', 'html_casual1' );
            }
            if ($rich_text) {
                is( $form->value('editor'), 'rte1',
                    "$label opens in the current rich-text editor" );
                is( $form->value('event'), $expected_body,
                    "$label opens with the expected source" );
            }

            my $save = sub {
                my ( $hide, %changes ) = @_;
                @jobs = ();
                my $request;
                if ($chrome) {
                    my ( $file, $filename ) = tempfile( UNLINK => 1 );
                    print {$file} $client->( GET $url )->content;
                    close $file or die $!;
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
                    $form->value( hide_crosspost_links => $hide );
                    $form->value( $_                   => $changes{$_} ) for keys %changes;
                    $request = $form->click('action:post');
                }
                my $response = $client->($request);
                like( $response->content, qr/edit was successful/i, "$label save succeeds" );
                LJ::Entry->reset_singletons;
                return LJ::Entry->new( $owner, ditemid => $id );
            };

            for my $hide ( $edit_first ? () : ( 1, 0 ) ) {
                my $fresh = $save->($hide);
                is( scalar @jobs, 0, "$label does not queue a crosspost on visibility-only save" );
                if ($rich_text) {
                    is( $fresh->event_raw, $expected_body, "$label saves the expected markup" );
                    is( $fresh->prop('editor'), 'rte1', "$label saves in the current format" );
                }
                is( $fresh->prop('editor'),
                    'html',
                    'visibility-only save keeps the stored format after a preference change' )
                    if $legacy_format;
                is_deeply( DW::External::Account->xpost_string_to_hash( $fresh->prop('xpost') ),
                    $mapping, "$label retains the external ID" );
                is_deeply(
                    DW::External::Account->xpost_string_to_hash( $fresh->prop('xpostdetail') ),
                    $details, "$label retains the saved URL with Record link off" );
                my %currents = LJ::currents( $fresh->props, $owner );
                if ($hide) {
                    is( $currents{Xpost} // '', '', "$label hides the link" );
                }
                else {
                    like( $currents{Xpost}, qr/\Q$target\E/, "$label restores the link" );
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
                [ taglist  => 'new tag' ],
                [ security => 'private' ],
                );
            unshift @edits, [ editor => 'html_casual1' ] if $legacy_format;
            for my $change (@edits) {
                my ( $field, $value ) = @$change;
                $changes{$field} = $value;
                my $fresh = $save->( $hide = 1 - $hide, %changes );
                like( $fresh->event_raw, qr/\Q$value\E/, "$label saves the new text" )
                    if $rich_text;
                is( $fresh->prop('editor'), $value, 'deliberate format change is saved' )
                    if $field eq 'editor';
                is_deeply(
                    [ map { [ @$_{qw(accountid ditemid delete)} ] } @jobs ],
                    [ [ $account_id, $id, 0 ] ],
                    "$label queues an external edit for changed $field"
                );
            }
            LJ::delete_entry( $owner, $entry->jitemid, 0, $entry->anum );
        }
    };
    $owner->do( 'DELETE FROM externalaccount WHERE userid=? AND acctid=?',
        undef, $owner->id, $account_id );
}

done_testing;
