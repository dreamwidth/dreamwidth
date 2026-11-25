# t/plack-entry-tag-permissions.t
#
# Test effective tag permissions in the advanced and simple entry layouts.
#
# Authors:
#     Alex (SAPHID)
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
use HTML::Parser;
use HTTP::Request::Common;
use JSON::PP qw(decode_json);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;
use LJ::Test qw(temp_comm temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryTagsTest';
local $LJ::DISABLED{tags}             = 0;

sub form_state {
    my ( $html, $journal_select ) = @_;
    my ( %fields, %options, $which_select );
    my $parser = HTML::Parser->new( api_version => 3 );
    $parser->handler(
        start => sub {
            my ( $tag, $attrs ) = @_;
            $fields{ $attrs->{id} } = $attrs if defined $attrs->{id};
            $fields{lj_form_auth} = $attrs
                if $tag eq 'input' && ( $attrs->{name} // '' ) eq 'lj_form_auth';
            $which_select = $attrs->{id} if $tag eq 'select';
            $options{ $attrs->{value} } = $attrs
                if $tag eq 'option'
                && defined $attrs->{value}
                && ( $which_select // '' ) eq $journal_select;
        },
        'tagname, attr'
    );
    $parser->handler( end => sub { undef $which_select if $_[0] eq 'select' }, 'tagname' );
    $parser->parse($html);
    $parser->eof;
    return ( \%fields, \%options );
}

sub notice_is {
    my ( $fields, $expected, $scenario ) = @_;
    my $notice = $fields->{'entry-tag-permission'};
    if ( $expected eq '' ) {
        ok( !$notice || exists $notice->{hidden}, "$scenario has no community notice" );
    }
    else {
        is( $notice && $notice->{'data-tag-permission'}, $expected, "$scenario notice" );
        ok( $notice && !exists $notice->{hidden}, "$scenario shows the notice" );
    }
}

with_fake_memcache {
    my $community = temp_comm();
    my @viewers   = map { temp_user() } 1 .. 3;
    my ( $member, $nonmember, $admin ) = @viewers;
    my @roles = ( 'member', 'nonmember', 'administrator' );

    $_->update_self( { status => 'A' } ) for @viewers;
    LJ::set_rel( $community, $_, 'P' ) for @viewers;
    LJ::set_rel( $community, $member, 'E' );
    LJ::set_rel( $community, $admin,  'A' );

    my $group = $community->create_trust_group( groupname => 'Tag contributors' );
    die 'Cannot create the tag permission group' unless $group;
    my $db = LJ::get_db_writer();
    $db->do( 'INSERT INTO wt_edges (from_userid, to_userid, groupmask) VALUES (?, ?, ?)',
        undef, $community->id, $member->id, 1 | ( 1 << $group ) )
        or die $db->errstr;

    my @personal = map { $_->t_post_fake_entry } @viewers;
    my @posts    = map { $_->t_post_fake_comm_entry($community) } @viewers;
    my $journal  = $community->user;

    my @cases = (
        [ 'public,public',        'create',   'create',   'create' ],
        [ 'public,private',       'existing', 'existing', 'create' ],
        [ 'protected,private',    'existing', 'none',     'create' ],
        [ 'private,protected',    'create',   'none',     'create' ],
        [ 'private,private',      'none',     'none',     'create' ],
        [ "group:$group,private", 'existing', 'none',     'create' ],
        [ 'author_admin,private', 'existing', 'existing', 'create' ],
    );

    test_psgi $app, sub {
        my ($request) = @_;
        subtest 'journal-level tag permission for a nonmember poster' => sub {
            $community->set_prop( opt_tagpermissions => 'author_admin,private' );
            my $username = $nonmember->user;
            my $error    = 0;
            my $post     = LJ::Protocol::do_request(
                'postevent',
                {
                    ver        => $LJ::PROTOCOL_VER,
                    username   => $username,
                    usejournal => $journal,
                    event      => 'A new community entry',
                    props      => { taglist => 'test-tag' },
                    tz         => 'guess',
                },
                \$error,
                { noauth => 1, u => $nonmember }
            );
            ok( !$post, 'postevent rejects tags on a new entry' );
            like( $error, qr/^312(?:$|:)/, 'postevent reports the tag permission error' );

            my $rpc = $request->( GET "http://localhost/__rpc_gettags?as=$username&user=$journal" );
            ok( $rpc->is_success, 'gettags returns a response' );
            my $payload = decode_json( $rpc->content );
            ok( $payload->{error}, 'gettags denies access' );
            like( $payload->{alert} // '', qr/cannot use .* tags/, 'gettags denies tag use' );
        };

        subtest 'simple community form redisplay' => sub {
            $community->set_prop( opt_tagpermissions => 'public,private' );
            my $username = $member->user;
            my $url      = "http://localhost/entry/new?mode=simple&as=$username";
            my $initial  = $request->( GET $url );
            my ($initial_fields) = form_state( $initial->content, 'js-usejournal' );
            my $form_auth = $initial_fields->{lj_form_auth}{value};
            ok( $form_auth, 'the native simple form has a form token' ) or return;
            my $result = $request->(
                POST $url,
                [
                    usejournal   => $journal,
                    showform     => 1,
                    tag_entry    => 1,
                    lj_form_auth => $form_auth,
                ],
            );
            my ( $fields, $options ) = form_state( $result->content, 'js-usejournal' );
            ok( $result->is_success && $fields->{'js-taglist'},
                'redisplays the native tags field' );
            ok( exists $options->{$journal}{selected}, 'keeps the selected community' );
            notice_is( $fields, 'existing', 'redisplay with an unexpected form field' );
        };

        for my $layout ( 'advanced', 'simple' ) {
            subtest $layout => sub {
                for my $index ( 0 .. $#viewers ) {
                    my $username = $viewers[$index]->user;
                    my $get_form = sub {
                        my ( $url, $description ) = @_;
                        my $result =
                            $request->( GET "http://localhost$url?mode=$layout&as=$username" );
                        my ( $fields, $options ) = form_state( $result->content, 'js-usejournal' );
                        ok( $result->is_success && $fields->{'js-taglist'}, "$description form" );
                        return ( $fields, $options );
                    };
                    my $edit_url = sub {
                        my ($entry) = @_;
                        my $target  = $entry->journal->user;
                        my $item    = $entry->ditemid;
                        return "/entry/$target/$item/edit";
                    };

                    my $role = $roles[$index];
                    my ($personal_fields) =
                        $get_form->( $edit_url->( $personal[$index] ), "$role personal edit" );
                    notice_is( $personal_fields, '', "$role personal edit" );

                    for my $case (@cases) {
                        my ( $setting, @expected ) = @$case;
                        $community->set_prop( opt_tagpermissions => $setting );
                        my $scenario = "$role with $setting";
                        my $new_permission =
                            $role eq 'nonmember' && $setting eq 'author_admin,private'
                            ? 'none'
                            : $expected[$index];
                        my ( $new_fields, $options ) = $get_form->( '/entry/new', "$scenario new" );
                        notice_is( $new_fields, '', "$scenario personal target" );
                        ok( exists $options->{''}, "$scenario can switch back to personal" );
                        is( $options->{''}{'data-tag-permission'} // '',
                            '', "$scenario personal option has no community restriction" );
                        is( $options->{$journal}{'data-tag-permission'},
                            $new_permission,
                            "$scenario community option carries the effective permission" );

                        my ($direct) = $get_form->( "/entry/$journal/new", "$scenario direct new" );
                        notice_is( $direct, $new_permission, "$scenario direct new" );

                        my ($edit) = $get_form->( $edit_url->( $posts[$index] ), "$scenario edit" );
                        notice_is( $edit, $expected[$index], "$scenario edit" );
                    }
                }
            };
        }
    };
};

done_testing;
