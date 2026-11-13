# t/entry-success-viewing-style.t
#
# Preserve viewing styles on success links after real entry mutations.
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
use File::Temp qw(tempdir);
use HTTP::Request;
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Controller::Entry;
use DW::Request::Standard;
use LJ::Entry;
use LJ::Test qw(temp_user temp_comm);

# Prime the real reload cache before installing process-local queue settings.
{
    local $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = 0;
    LJ::Config->start_request_reload;
}
local $LJ::TASK_QUEUE_BACKEND = 'localdisk';
local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

my $poster = temp_user();
my $community = temp_comm();
$_->update_self( { status => 'A' } ) for $poster, $community;
$poster->join_community( $community, 1, 1 );

# Authentication is supplied at the controller boundary. Persistence and URL
# construction are real; only final template rendering is captured. Routed auth,
# legacy BML forms and rendered HTML require separate integration coverage.
{
    no warnings 'redefine';
    local *DW::Template::render_template = sub {
        my ( $class, $template, $vars ) = @_;
        is( $template, 'entry/success.tt', 'render the entry success template' );
        return $vars;
    };

    my @cases = (
        [ 'no explicit style', {}, {} ],
        [ 'site style', { style => 'site' }, { style => 'site' } ],
        [ 'own style', { style => 'mine' }, { style => 'mine' } ],
        [ 'original style', { style => 'original' }, { style => 'original' } ],
        [ 'light style', { style => 'light' }, { style => 'light' } ],
        [ 'light format and BML fallback',
            { format => 'light', fallback => 'bml' },
            { format => 'light', fallback => 'bml' } ],
        [ 'combined style parameters',
            { style => 'site', format => 'light', fallback => 's2', s2id => '123' },
            { style => 'site', format => 'light', fallback => 's2', s2id => '123' } ],
        [ 'invalid and unrelated parameters',
            { style => 'site&admin=1', format => 'html', fallback => 'other',
                s2id => '123x', poster => 'other', usejournal => 'other',
                redirect => 'https://example.invalid/' }, {} ],
    );

    for my $journal ( $poster, $community ) {
        for my $case (@cases) {
            my ( $name, $args, $expected ) = @$case;
            subtest( ( $journal->is_community ? 'community: ' : 'personal: ' ) . $name => sub {
                my $uri = URI->new('http://localhost/entry/new');
                $uri->query_form(%$args);
                DW::Request->reset;
                DW::Request::Standard->new( HTTP::Request->new( POST => $uri ) );
                LJ::set_remote($poster);

                my $auth = { poster => $poster, journal => $journal };
                my $form = {
                    event => 'Viewing-style regression entry',
                    subject => 'Viewing-style regression',
                    security => 'public',
                    props => { editor => 'html' },
                };
                my %posted = DW::Controller::Entry::_do_post(
                    $form, { noauth => 1, u => $poster }, $auth
                );
                is( $posted{status}, 'ok', 'real entry creation succeeds' );
                BAIL_OUT('entry creation failed') unless $posted{status} && $posted{status} eq 'ok';

                my ( $jitemid, $anum ) = $journal->selectrow_array(
                    'SELECT jitemid, anum FROM log2 WHERE journalid=? AND posterid=? '
                        . 'ORDER BY jitemid DESC LIMIT 1',
                    undef, $journal->id, $poster->id
                );
                BAIL_OUT('created entry not found') unless $jitemid;
                my $ditemid = $jitemid * 256 + $anum;
                my $entry = LJ::Entry->new( $journal, ditemid => $ditemid );
                is( $entry->event_raw, $form->{event}, 'created entry body persisted' );
                check_links( $posted{render}, $journal, $entry, $expected, 'posted' );

                $form->{event} = 'Edited viewing-style regression entry';
                my %edited = DW::Controller::Entry::_do_edit( $ditemid, $form, $auth );
                is( $edited{status}, 'ok', 'real entry edit succeeds' );
                BAIL_OUT('entry edit failed') unless $edited{status} && $edited{status} eq 'ok';
                my $updated = LJ::Entry->new( $journal, ditemid => $ditemid );
                is( $updated->event_raw, $form->{event}, 'edited entry body persisted' );
                check_links( $edited{render}, $journal, $updated, $expected, 'edited' );

                $form->{event} = '';
                my %deleted = DW::Controller::Entry::_do_edit( $ditemid, $form, $auth );
                is( $deleted{status}, 'ok', 'real entry deletion succeeds' );
                BAIL_OUT('entry deletion failed') unless $deleted{status} && $deleted{status} eq 'ok';
                my ($remaining) = $journal->selectrow_array(
                    'SELECT COUNT(*) FROM log2 WHERE journalid=? AND jitemid=?',
                    undef, $journal->id, $jitemid
                );
                is( $remaining, 0, 'deleted entry is absent from log2' );
                check_links( $deleted{render}, $journal, $updated, $expected, 'deleted' );
                # Protocol deletion queues its secondary cleanup. Finish it here
                # without running a worker against any unrelated queued tasks.
                LJ::delete_entry( $journal, $jitemid, 0, $anum );
                my ($texts) = $journal->selectrow_array(
                    'SELECT COUNT(*) FROM logtext2 WHERE journalid=? AND jitemid=?',
                    undef, $journal->id, $jitemid
                );
                is( $texts, 0, 'entry text cleanup completed synchronously' );
                DW::Request->reset;
                LJ::set_remote(undef);
            } );
        }
    }
}

done_testing;

sub check_url {
    my ( $actual, $destination, $expected, $label ) = @_;
    my $uri = URI->new( $actual // '' );
    my $target = URI->new($destination);
    is( $uri->scheme, $target->scheme, "$label: scheme" );
    is( $uri->authority, $target->authority, "$label: host" );
    is( $uri->path, $target->path, "$label: destination" );
    my @pairs = $uri->query_form;
    my %query;
    while (@pairs) {
        my ( $key, $value ) = splice @pairs, 0, 2;
        push @{ $query{$key} }, $value;
    }
    is_deeply( \%query, { map { $_ => [ $expected->{$_} ] } keys %$expected },
        "$label: only expected query parameters, once each" );
    ok( !defined $uri->fragment, "$label: no unexpected fragment" );
}

sub check_links {
    my ( $vars, $journal, $entry, $expected, $status ) = @_;
    is( $vars->{poststatus}->{status}, $status, 'correct success state' );
    check_url( $vars->{poststatus}->{url}, $journal->journal_base . '/',
        $expected, 'journal status link' );
    my %links = map { $_->{ml_string} => $_->{url} } @{ $vars->{links} };
    if ( $status eq 'deleted' ) {
        ok( !exists $links{'.links.viewentry'}, 'no view link after deletion' );
        ok( !exists $links{'.links.editentry'}, 'no edit link after deletion' );
    }
    else {
        check_url( $vars->{entry_url}, $entry->url, $expected, 'primary entry link' );
        check_url( $links{'.links.viewentry'}, $entry->url, $expected, 'view entry link' );
        check_url( $links{'.links.editentry'},
            "$LJ::SITEROOT/entry/" . $journal->user . '/' . $entry->ditemid . '/edit',
            $expected, 'edit entry link' );
    }
    if ( $journal->is_community ) {
        check_url( $links{'.links.myentries'}, $journal->journal_base,
            { %$expected, poster => $poster->user }, 'community poster filter' );
    }
    else {
        ok( !exists $links{'.links.myentries'}, 'personal journal has no community poster filter' );
    }
}
