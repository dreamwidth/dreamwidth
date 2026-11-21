# t/plack-entry-custom-security.t
#
# Test saving access filters through the entry form.
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
use HTML::TokeParser;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryCustomSecurityTest';
local @LJ::MEMCACHE_SERVERS           = ();
LJ::MemCache::reload_conf();

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $first = $owner->create_trust_group( groupname => 'First filter' );
$owner->create_trust_group( groupname => 'Other filter' );
my $last = $owner->create_trust_group( groupname => 'Last filter' );
my $url  = 'http://localhost/entry/new?as=' . $owner->user;

sub edit_form {
    my ( $request, $entry ) = @_;
    my $url =
          'http://localhost/entry/'
        . $owner->user . '/'
        . $entry->ditemid
        . '/edit?as='
        . $owner->user;
    my $page   = $request->( GET $url );
    my $html   = $page->content;
    my $parser = HTML::TokeParser->new( \$html );
    my ( $security, $security_select, $token );
    my @groups;
    while ( my $tag = $parser->get_tag(qw(select /select option input)) ) {
        my ( $type, $attrs ) = @$tag;
        if ( $type eq '/select' ) {
            $security_select = 0;
            next;
        }
        my $name = $attrs->{name} || '';
        if ( $type eq 'select' ) {
            $security_select = $name eq 'security';
        }
        elsif ( $type eq 'option' && $security_select && exists $attrs->{selected} ) {
            $security = $attrs->{value};
        }
        elsif ( $type eq 'input' && $name eq 'custom_bit' && exists $attrs->{checked} ) {
            push @groups, $attrs->{value};
        }
        elsif ( $type eq 'input' && $name eq 'lj_form_auth' ) {
            $token ||= $attrs->{value};
        }
    }
    return ( $url, $security, \@groups, $token );
}

sub submit_edit {
    my ( $request, $event, $url, $security, $groups, $token ) = @_;
    return $request->(
        POST $url,
        [
            lj_form_auth  => $token,
            'action:post' => 'Save',
            event         => $event,
            security      => $security,
            map { ( custom_bit => $_ ) } @$groups
        ]
    );
}

test_psgi $app, sub {
    my $request = shift;
    my $form    = $request->( GET $url );
    is( $form->code, 200, 'Entry form loads' );
    my ($token) = $form->content =~ /name=["']lj_form_auth["']\s+value=["']([^"']+)/;
    ok( $token, 'Rendered form contains an auth token' ) or return;

    my @fields = (
        lj_form_auth  => $token,
        security      => 'custom',
        'action:post' => 'Post',
    );

    my $empty = $request->( POST $url, [ @fields, event => 'Missing groups' ] );
    ok(
        $empty->content =~ /Choose at least one access group/i,
        'Custom without groups explains why it was not saved'
    );

    $request->(
        POST $url, [ @fields, event => 'Chosen groups', custom_bit => $first, custom_bit => $last ]
    );

    my @entries = $owner->recent_entries( filtered_for => $owner );
    is( scalar @entries, 1, 'Only the submission with selected filters saves' );
    my ($entry) = grep { $_->event_orig eq 'Chosen groups' } @entries;
    ok( $entry, 'Entry with selected filters was saved' ) or return;
    is( $entry->security, 'usemask', 'Entry uses custom security' );
    is(
        $entry->allowmask,
        ( 1 << $first ) | ( 1 << $last ),
        'Persisted mask includes both chosen groups and not the other group'
    );

    my @edit = edit_form( $request, $entry );
    is( $edit[1], 'custom', 'Nonzero custom mask renders as Custom' );
    is_deeply( [ sort @{ $edit[2] } ], [ sort ( $first, $last ) ],
        'Only saved groups are checked' );
    submit_edit( $request, 'Edited with chosen groups', @edit );
    LJ::Entry->reset_singletons;
    my $edited = LJ::Entry->new( $owner, jitemid => $entry->jitemid );
    is( $edited->event_orig, 'Edited with chosen groups', 'Content-only custom edit saves' );
    is( $edited->security, 'usemask', 'Custom edit keeps custom security' );
    is( $edited->allowmask, ( 1 << $first ) | ( 1 << $last ), 'Custom edit keeps the mask' );

    $request->( POST $url, [ @fields, event => 'Deleted group', custom_bit => $first ] );
    my ($orphaned) =
        grep { $_->event_orig eq 'Deleted group' } $owner->recent_entries( filtered_for => $owner );
    ok( $orphaned,                                  'Entry using one filter was saved' ) or return;
    ok( $owner->delete_trust_group( id => $first ), 'Deleted its only access group' );
    LJ::Entry->reset_singletons;
    my $masked = LJ::Entry->new( $owner, jitemid => $orphaned->jitemid );
    is( $masked->security,  'usemask', 'Deleting the group retains the stored security type' );
    is( $masked->allowmask, 0,         'Deleting the group leaves a zero mask' );

    my @private_edit = edit_form( $request, $masked );
    is( $private_edit[1], 'private', 'Zero custom mask renders as Private' );
    submit_edit( $request, 'Edited after deleting group', @private_edit );
    LJ::Entry->reset_singletons;
    my $private = LJ::Entry->new( $owner, jitemid => $masked->jitemid );
    is( $private->event_orig, 'Edited after deleting group', 'Content-only private edit saves' );
    is( $private->security, 'private', 'Content-only edit keeps the entry private' );
};

done_testing();
