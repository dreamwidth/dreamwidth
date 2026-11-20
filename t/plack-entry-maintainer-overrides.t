# t/plack-entry-maintainer-overrides.t
#
# Test community administrator overrides when the poster edits an entry.
#
# Authors:
#      Alex Southwell <saphid@users.noreply.github.com>
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
use LJ::Test qw(temp_comm temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::DISABLED{adult_content} = 0;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryMaintainerOverrides';
my $community = temp_comm();
my $poster    = temp_user();
my $admin     = temp_user();
LJ::set_rel( $community, $admin, 'A' );

sub get_form {
    my ( $client, $url, $id ) = @_;
    my $response = $client->( GET $url );
    is( $response->code, 200, 'edit page loads' );
    my $html   = $response->content;
    my $parser = HTML::TokeParser->new( \$html );
    while ( my $tag = $parser->get_tag('form') ) {
        next unless ( $tag->[1]{id} // '' ) eq $id;
        my %form = ( comment_settings => '' );
        my $in_comments;
        while ( my $tag = $parser->get_tag(qw(input select option /select /form)) ) {
            my ( $name, $attr ) = @$tag;
            last if $name eq '/form';
            if ( $name eq 'input' && $attr->{name} ) {
                $form{inputs}{ $attr->{name} } = $attr;
            }
            elsif ( $name eq 'select' ) {
                $in_comments = ( $attr->{name} // '' ) eq 'comment_settings';
            }
            elsif ( $name eq 'option' && $in_comments && exists $attr->{selected} ) {
                $form{comment_settings} = $attr->{value};
            }
            elsif ( $name eq '/select' ) {
                $in_comments = 0;
            }
        }
        return \%form;
    }
    BAIL_OUT("missing edit form $id");
}

sub submit_form {
    my ( $client, $url, $form, $action, %fields ) = @_;
    return $client->(
        POST $url,
        [
            lj_form_auth     => $form->{inputs}{lj_form_auth}{value},
            "action:$action" => 1,
            %fields,
        ]
    );
}

sub reload_entry {
    my ($entry) = @_;
    LJ::Entry->reset_singletons;
    return LJ::Entry->new( $community, ditemid => $entry->ditemid );
}

test_psgi $app, sub {
    my ($client) = @_;
    foreach my $editor ( 'legacy', 'beta' ) {
        subtest "$editor editor preserves the administrator override" => sub {
            my $journal = $community->user;
            my $entry = $poster->t_post_fake_entry( usejournal => $journal, usejournal_okay => 1 );
            $entry->set_prop( opt_nocomments_maintainer       => 1 );
            $entry->set_prop( adult_content_maintainer        => 'explicit' );
            $entry->set_prop( adult_content_maintainer_reason => 'Community rating' );

            my $ditemid    = $entry->ditemid;
            my $legacy_url = "http://localhost/editjournal?journal=$journal&itemid=$ditemid";
            my $admin_url  = $legacy_url . '&as=' . $admin->user;
            my $poster_url =
                  $editor eq 'legacy'
                ? $legacy_url . '&as=' . $poster->user
                : "http://localhost/entry/$journal/$ditemid/edit?as=" . $poster->user;
            my $id = $editor eq 'legacy' ? 'updateForm' : 'js-post-entry';

            my $form        = get_form( $client, $poster_url, $id );
            my %edit_fields = (
                subject  => 'Edited by the poster',
                event    => 'Entry body',
                security => 'public',
            );
            submit_form( $client, $poster_url, $form, 'save', %edit_fields,
                comment_settings => $form->{comment_settings} );

            $entry = reload_entry($entry);
            is( $entry->subject_raw, 'Edited by the poster', 'text edit was saved' );
            ok( !$entry->comments_disabled_poster,
                'text edit does not disable comments as poster' );
            ok(
                $entry->comments_disabled_maintainer,
                'maintainer override still disables comments'
            );
            is( $entry->adult_content_maintainer, 'explicit', 'maintainer rating survives' );
            is(
                $entry->adult_content_maintainer_reason,
                'Community rating',
                'maintainer rating reason survives'
            );

            $form = get_form( $client, $poster_url, $id );
            submit_form( $client, $poster_url, $form, 'save', %edit_fields,
                comment_settings => 'nocomments' );
            ok(
                reload_entry($entry)->comments_disabled_poster,
                'poster can disable comments separately'
            );

            my $admin_form = get_form( $client, $admin_url, 'updateForm' );
            ok(
                !$admin_form->{inputs}{prop_opt_nocomments_maintainer},
                'admin cannot enable comments while the poster disables them'
            );
            is(
                submit_form( $client, $admin_url, $admin_form, 'savemaintainer',
                    prop_adult_content_maintainer => 'concepts' )->code,
                302,
                'admin can save another override'
            );
            $entry = reload_entry($entry);
            is( $entry->adult_content_maintainer, 'concepts', 'rating was changed' );
            ok(
                $entry->prop('opt_nocomments_maintainer'),
                'rating edit does not clear hidden override'
            );

            $form = get_form( $client, $poster_url, $id );
            submit_form( $client, $poster_url, $form, 'save', %edit_fields,
                comment_settings => 'noemail' );
            $entry = reload_entry($entry);
            ok( !$entry->comments_disabled_poster,    'poster can undo their own comment setting' );
            ok( $entry->comments_disabled_maintainer, 'poster cannot undo the admin override' );

            $admin_form = get_form( $client, $admin_url, 'updateForm' );
            my $checkbox = $admin_form->{inputs}{prop_opt_nocomments_maintainer};
            ok( $checkbox && exists $checkbox->{checked}, 'admin still sees the checked override' );
            is(
                submit_form( $client, $admin_url, $admin_form, 'savemaintainer',
                    prop_adult_content_maintainer => 'concepts' )->code,
                302,
                'admin can clear their own override'
            );
            ok( !reload_entry($entry)->comments_disabled, 'comments are enabled again' );
        };
    }
};

done_testing;
