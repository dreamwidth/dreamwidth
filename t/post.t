# t/post.t
#
# Test posting.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 133;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );

use DW::Routing::CallInfo;
use DW::Controller::Entry;
use DW::FormErrors;

use LJ::Community;
use LJ::Entry;

use Hash::MultiValue;

use FindBin qw($Bin);
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

# preload userpics so we don't have to read the file hundreds of times
open (my $fh, 'good.png') or die $!;
my $ICON1 = do { local $/; <$fh> };

open (my $fh2, 'good.jpg') or die $!;
my $ICON2 = do { local $/; <$fh2> };

$LJ::CAP{$_}->{moodthemecreate} = 1
    foreach( 0.. 15 );

note( "Not logged in - init" );
{
    my $vars = DW::Controller::Entry::_init();

    # user
    ok( ! $vars->{remote} );

    # icon
    ok( ! @{$vars->{icons}}, "No icons." );
    ok( ! $vars->{defaulticon}, "No default icon." );

    # mood theme
    ok( ! keys %{$vars->{moodtheme}}, "No mood theme." );

    TODO: {
        local $TODO = "usejournal";
    }
}

note( "Logged in - init" );
{
    my $u = temp_user();
    LJ::set_remote( $u );

    my $vars;
    $vars = DW::Controller::Entry::_init( { remote => $u } );

    ok( $u->equals( $vars->{remote} ), "Post done as currently logged in user." );

    note( "# Icons " );
    note( "  no icons" );
    ok( ! @{$vars->{icons}}, "No icons." );
    ok( ! $vars->{defaulticon}, "No default icon." );

    note( "  no default icon" );
    my $icon1 = LJ::Userpic->create( $u, data => \$ICON1 );
    my $icon2 = LJ::Userpic->create( $u, data => \$ICON2 );
    $icon1->set_keywords( "b, z" );
    $icon2->set_keywords( "a, c, y" );

    $vars = DW::Controller::Entry::_init( { remote => $u } );
    is( @{$vars->{icons}}, 6, "Has icons (including a blank one in the list for default)" );
    ok( ! $vars->{defaulticon}, "No default icon." );

    my @icon_order = (
        # keyword, userpic object
        [ undef, undef ],
        [ "a", $icon2 ],
        [ "b", $icon1 ],
        [ "c", $icon2 ],
        [ "y", $icon2 ],
        [ "z", $icon1 ],
    );
    my $count = 0;
    foreach my $icon ( @{$vars->{icons}} ) {
        if ( $count == 0 ) {
            is( $icon->{keyword}, undef, "No default icon; no keyword.");
            is( $icon->{userpic}, undef, "No default icon.");
        } else {
            is( $icon->{keyword}, $icon_order[$count]->[0], "Keyword is in proper order." );
            is( $icon->{userpic}->id, $icon_order[$count]->[1]->id, "Icon is proper icon." );
        }
        $count++;
    }

    note( "  with default icon" );
    $icon1->make_default;
    $vars = DW::Controller::Entry::_init( { remote => $u } );
    ok( $vars->{defaulticon}, "Has default icon." );

    $icon_order[0] = [ undef, $icon1 ];
    $count = 0;
    foreach my $icon ( @{$vars->{icons}} ) {
        is( $icon->{keyword}, $icon_order[$count]->[0], "Keyword is in proper order." );
        is( $icon->{userpic}->id, $icon_order[$count]->[1]->id, "Icon is proper icon." );
        $count++;
    }


    note( "# Moodtheme" );
    note( "  default mood theme" );
    $vars = DW::Controller::Entry::_init( { remote => $u } );
    my $moods = DW::Mood->get_moods;

    SKIP: {
        skip "Default mood theme not defined.", 1 unless $LJ::USER_INIT{moodthemeid};
        ok( $vars->{moodtheme}->{id} == $LJ::USER_INIT{moodthemeid}, "Default mood theme." );
    };
    is( scalar keys %{$vars->{moodtheme}->{pics}}, scalar keys %$moods, "Complete mood theme." );

    note( "  no mood theme" );
    $u->update_self( { moodthemeid => undef } );
    $u = LJ::load_user($u->user, 'force');

    $vars = DW::Controller::Entry::_init();
    ok( ! %{ $vars->{moodtheme} }, "No mood theme." );

    note( "  custom mood theme with incomplete moods" );
    my $themeid = $u->create_moodtheme( "testing", "testing a custom mood theme with missing moods." );
    my $customtheme = DW::Mood->new( $themeid );
    $u->update_self( { moodthemeid => $customtheme->id } );
    $u = LJ::load_user($u->user, 'force');

    # we used to pick a random mood here - whichever moodid was the
    # first one returned from the keys array - but the test would
    # fail if we picked a mood that had other moods inherit from it,
    # so now we pick a mood that is known to be childless
    my $testmoodid = 105;  # quixotic
    my $err;
    $customtheme->set_picture( $testmoodid, { picurl => "http://example.com/moodpic", width => 10, height => 20 }, \$err );

    $vars = DW::Controller::Entry::_init( { remote => $u } );
    is( $vars->{moodtheme}->{id}, $customtheme->id, "Custom mood theme." );
    is( scalar keys %{$vars->{moodtheme}->{pics}}, 1, "Only provide picture information for moods with valid pictures." );
    is( $vars->{moodtheme}->{pics}->{$testmoodid}->{pic}, "http://example.com/moodpic", "Confirm picture URL matches." );
    is( $vars->{moodtheme}->{pics}->{$testmoodid}->{width}, 10, "Confirm picture width matches." );
    is( $vars->{moodtheme}->{pics}->{$testmoodid}->{height}, 20, "Confirm picture height matches." );
    is( $vars->{moodtheme}->{pics}->{$testmoodid}->{name}, $moods->{$testmoodid}->{name}, "Confirm mood name matches.");

    note( "Security levels ");
    $vars = DW::Controller::Entry::_init( { remote => $u } );
    is( scalar @{$vars->{security}}, 3, "Basic security levels" );
    is( $vars->{security}->[0]->{label}, '.select.security.public.label', "Public security" );
    is( $vars->{security}->[0]->{value}, "public", "Public security" );
    is( $vars->{security}->[1]->{label}, '.select.security.access.label', "Access-only security" );
    is( $vars->{security}->[1]->{value}, "access", "Access-only security" );
    is( $vars->{security}->[2]->{label}, '.select.security.private.label', "Private security" );
    is( $vars->{security}->[2]->{value}, "private", "Private security" );

    $u->create_trust_group( groupname => "test" );
    $vars = DW::Controller::Entry::_init( { remote => $u } );
    is( scalar @{$vars->{security}}, 4, "Security with custom groups" );
    is( $vars->{security}->[0]->{label}, '.select.security.public.label', "Public security" );
    is( $vars->{security}->[0]->{value}, "public", "Public security" );
    is( $vars->{security}->[1]->{label}, '.select.security.access.label', "Access-only security" );
    is( $vars->{security}->[1]->{value}, "access", "Access-only security" );
    is( $vars->{security}->[2]->{label}, '.select.security.private.label', "Private security" );
    is( $vars->{security}->[2]->{value}, "private", "Private security" );
    is( $vars->{security}->[3]->{label}, '.select.security.custom.label', "Custom security" );
    is( $vars->{security}->[3]->{value}, "custom", "Custom security" );
    is( @{$vars->{customgroups}}, 1, "Custom group list");
    is( $vars->{customgroups}->[0]->{label}, "test" );
    is( $vars->{customgroups}->[0]->{value}, 1 );

    note( "# Usejournal" );
    note( "  No communities." );
    $vars = DW::Controller::Entry::_init( { remote => $u } );
    is( scalar @{$vars->{journallist}}, 1,  "One journal (yourself)" );
    ok( $vars->{journallist}->[0]->equals( $u ), "First journal in the list is yourself." );


    my $comm_canpost = temp_comm();
    my $comm_nopost = temp_comm();
    $u->join_community( $comm_canpost, 1, 1 );
    $u->join_community( $comm_nopost, 1, 0 );

    note( "  With communities." );
    $vars = DW::Controller::Entry::_init( { remote => $u } );
    is( scalar @{$vars->{journallist}}, 2,  "Yourself and one community." );
    ok( $vars->{journallist}->[0]->equals( $u ), "First journal in the list is yourself." );
    ok( $vars->{journallist}->[1]->equals( $comm_canpost ), "Second journal in the list is a community you can post to." );
    ok( ! $vars->{usejournal}, "No usejournal argument." );
}

note( " Usejournal - init" );
{
    my $u = temp_user();
    LJ::set_remote( $u );
    my $comm_canpost = temp_comm();
    my $comm_nopost = temp_comm();
    $u->join_community( $comm_canpost, 1, 1 );
    $u->join_community( $comm_nopost, 1, 0 );

    note( "  With usejournal argument (can post)" );
    my $vars = DW::Controller::Entry::_init( { usejournal => $comm_canpost->user, remote => $u } );
    is( scalar @{$vars->{journallist}}, 1,  "Usejournal." );
    ok( $vars->{journallist}->[0]->equals( $comm_canpost ), "Only item in the list is usejournal value." );
    ok( $vars->{usejournal}->equals( $comm_canpost ), "Usejournal argument." );

    note( " checking community security levels ");
    is( scalar @{$vars->{security}}, 3, "Basic security levels" );
    is( $vars->{security}->[0]->{label}, '.select.security.public.label', "Public security" );
    is( $vars->{security}->[0]->{value}, "public", "Public security" );
    is( $vars->{security}->[1]->{label}, '.select.security.members.label', "Members-only security" );
    is( $vars->{security}->[1]->{value}, "access", "Access-only security" );
    is( $vars->{security}->[2]->{label}, '.select.security.admin.label', "Admin-only security" );
    is( $vars->{security}->[2]->{value}, "private", "Private security" );

    # TODO:
    # tags ( fetched by JS )
    # mood, icons, comments, age restriction don't change

    # crosspost: shouldn't show up? or is that another thing to be hidden by JS?


    # allow this, because the user can still log in as another user in order to complete the post
    note( "  With usejournal argument (cannot post)" );
    $vars = DW::Controller::Entry::_init( { usejournal => $comm_nopost->user, remote => $u } );
    is( scalar @{$vars->{journallist}}, 1,  "Usejournal." );
    ok( $vars->{journallist}->[0]->equals( $comm_nopost ), "Only item in the list is usejournal value." );
    ok( $vars->{usejournal}->equals( $comm_nopost ), "Usejournal argument." );
}

note( "Altlogin - init" );
{
    my $u = temp_user();
    my $alt = temp_user();
    LJ::set_remote( $u );

    my $vars = DW::Controller::Entry::_init( { altlogin => 1 } );

    ok( ! $vars->{remote}, "Altlogin means form has no remote" );
    ok( ! $vars->{poster}, "\$alt doesn't show up in the form on init" );

    ok( ! $vars->{tags}, "No tags" );
    ok( ! keys %{$vars->{moodtheme}}, "No mood theme." );
    ok( ! @{$vars->{icons}}, "No icons." );
    ok( ! $vars->{defaulticon}, "No default icon." );
    is( @{$vars->{security}}, 3, "Default security dropdown" );
    ok( ! @{$vars->{journallist}}, "No journal dropdown" );

    # TODO:
    # comments
    # age restriction
    # crosspost
    # scheduled
}


my $postdata = {
    subject => "here is a subject",
    event   => "here is some event data",
};

my $postdecoded_bare = {
    event   => $postdata->{event},
    subject => undef,
    slug    => '',

    security    => 'public',
    allowmask   => 0,

    crosspost_entry => 0,
    sticky_entry => undef,
    update_displaydate => undef,

    props => {
        taglist => "",

        opt_nocomments      => 0,
        opt_noemail         => 0,
        opt_screening       => '',

        opt_preformatted    => 0,
        opt_backdated       => 0,

        adult_content        => '',
        adult_content_reason => '',

        admin_post          => 0,
    }
};

note( "Not logged in - post" );
TODO: {
    local $TODO = "Handle not logged in (post)";
}

note( "Not logged in - post (community)" );
TODO: {
    local $TODO = "post to a community while not logged in";
}

sub post_with {
    my %opts = @_;

    my $remote = temp_user();
    LJ::set_remote( $remote );

    $opts{event} = $postdata->{event} unless exists $opts{event};
    $opts{chal} = LJ::challenge_generate();

    # if we'd been in a handler, this would have been put into $vars->{formdata}
    # and automatically converted to Hash::MultiValue. We're not, though, so fake it
    my $post = Hash::MultiValue->from_mixed( \%opts );

    my %flags;
    my %auth;
    %auth = DW::Controller::Entry::_auth( \%flags, $post, $remote, $LJ::SITEROOT );

    my %req;
    my $errors = DW::FormErrors->new;
    DW::Controller::Entry::_form_to_backend( \%req, $post, errors => $errors );

    my $res = DW::Controller::Entry::_save_new_entry( \%req, \%flags, \%auth );
    delete $req{props}->{unknown8bit}; # TODO: remove this from protocol at some point

    return ( \%req, $res, $remote, $errors );
}

note( "Logged in - post (bare minimum)" );
{
    # only have the event
    my ( $req, $res, $u, $errors ) = post_with( undef => undef );
    is_deeply( $req, $postdecoded_bare, "decoded entry form" );
    is_deeply( $errors->get_all, [], "no errors" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->subject_orig, '', "subject" );
    is( $entry->event_orig, $postdata->{event}, "event text" );
}

note( "Post - subject" );
{
    my ( $req, $res, $u, $errors ) = post_with( subject => $postdata->{subject} );
    is_deeply( $req, { %$postdecoded_bare,
        subject => $postdata->{subject},
    } );
    is_deeply( $errors->get_all, [], "no errors" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->subject_orig, $postdata->{subject} );
    is( $entry->event_orig, $postdata->{event} );
}

note( "Post - lacking required info" );
{
    my ( $req, $res, $u, $errors ) = post_with( subject => $postdata->{subject}, event => undef );
    is_deeply( $req, { %$postdecoded_bare,
        subject => $postdata->{subject},
        event   => "",
    }, "decoded entry form" );
    my $error_list = $errors->get_all;
    is( scalar @$error_list, 1, "one error returned" );
    is( $error_list->[0]->{'ml_key'}, '.error.noentry', "no entry text" );

    is_deeply( $res, {
        errors  => LJ::Protocol::error_message( 200 ),
    }, "failed, lacking required arguments" );
}

note( "Post - security:public" );
{
    my ( $req, $res, $u ) = post_with( security => "" );
    is_deeply( $req, { %$postdecoded_bare,
        security => "public",
    }, "decoded entry form" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "public", "Public security" );


    ( $req, $res, $u ) = post_with( security => "public" );
    is_deeply( $req, { %$postdecoded_bare,
        security => "public",
    }, "decoded entry form" );

    $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "public", "Public security" );
}

note( "Post - security:access" );
{
    my ( $req, $res, $u ) = post_with( security => "access" );
    is_deeply( $req, { %$postdecoded_bare,
        security  => "usemask",
        allowmask => 1,
    }, "decoded entry form for access-locked entry" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "usemask", "Locked security" );
}

note( "Post - security:private" );
{
    my ( $req, $res, $u ) = post_with( security => "private" );
    is_deeply( $req, { %$postdecoded_bare,
        security => "private"
    }, "decoded entry form for private entry" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "private", "Private security" );
}

note( "Post - security:custom" );
{
    my ( $req, $res, $u ) = post_with( security => "custom", custom_bit => [1, 2] );
    is_deeply( $req, { %$postdecoded_bare,
        security => "usemask",
        allowmask => 6,
    }, "decoded entry form for entry with custom security" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "usemask", "Custom security" );
    is( $entry->allowmask, 6, "Custom security allowmask" );
}

note( "Post - security:custom no allowmask" );
{
    my ( $req, $res, $u ) = post_with( security => "custom" );
    is_deeply( $req, { %$postdecoded_bare,
        security => "usemask",
        allowmask => 0,
    }, "decoded entry form for entry with custom security" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "usemask", "Custom security" );
    is( $entry->allowmask, 0, "Custom security allowmask" );
}

note( "Post - security:public, but with allowmask (probably changed their mind)" );
{
    my ( $req, $res, $u ) = post_with( security => "public", custom_bit => [1, 2] );
    is_deeply( $req, { %$postdecoded_bare,
        security => "public",
        allowmask => 0,
    }, "decoded entry form" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->security, "public", "Public security, not custom" );
    is( $entry->allowmask, 0, "No custom security allowmask" );
}

note( "Post - currents" );
{
    my ( $req, $res, $u ) = post_with(
        current_mood => 1,
        current_mood_other => "etc",
        current_location => "beside the thing",
        current_music => "things that go bump in the night"
    );
    is_deeply( $req, { %$postdecoded_bare,
        props => {
            %{$postdecoded_bare->{props}},
            current_moodid     => 1,
            current_mood       => "etc",
            current_music      => "things that go bump in the night",
            current_location   => "beside the thing",
        }
    }, "decoded entry form with metadata" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->prop( "current_moodid" ), 1  );
    is( $entry->prop( "current_mood" ), "etc" );
    is( $entry->prop( "current_music" ), "things that go bump in the night" );
    is( $entry->prop( "current_location" ), "beside the thing" );
    is( $entry->prop( "current_coords" ), undef );
}

note( "Post - mood_other matches mood with a moodid" );
{
    my $moodid = 1;
    my $mood_other_id = 2;
    my $mood_other_name = DW::Mood->mood_name( $mood_other_id );

    my ( $req, $res, $u ) = post_with(
        current_moodid => $moodid,
        current_mood_other => $mood_other_name
    );
    is_deeply( $req, { %$postdecoded_bare,
        props => { %{$postdecoded_bare->{props}}, current_moodid     => $mood_other_id }
    }, "decoded entry form with metadata" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->prop( "current_moodid" ), $mood_other_id );
    is( $entry->prop( "current_mood" ), undef );
}

note( "Post - with tags, nothing fancy" );
{
    my ( $req, $res, $u ) = post_with(
        taglist => "foo, bar, baz",
    );
    is_deeply( $req, { %$postdecoded_bare,
        props => { %{$postdecoded_bare->{props}}, taglist     => "foo, bar, baz" }
    }, "decoded entry form with metadata" );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->prop( "taglist" ), "foo, bar, baz", "tag list as string prop" );
    is_deeply( { map { $_ => 1 } $entry->tags }, { map { $_ => 1 } qw( bar baz foo ) },
            "tag list as parsed array (order doesn't matter)" );
}

note( "Logged in - post (community)" );
TODO: {
    local $TODO = "post to a community";
}

note( "Altlogin with remote - no longer allowed" );
{
    my $alt = temp_user();
    my $alt_pass = "abc123!" . rand();
    $alt->set_password( $alt_pass );

    my ( $req, $res, $remote, $errors ) = post_with(
        username => $alt->user,
        password => $alt_pass
    );

    ok( ! $remote->equals( $alt ), "Remote and altlogin aren't the same user" );

    my $entry = LJ::Entry->new( $alt, jitemid => $res->{itemid} );
    ok( ! $entry->valid, "didn't post to alt" );

    my $no_entry = LJ::Entry->new( $remote, jitemid => $res->{itemid} );
    ok( $no_entry->valid, "posted to remote instead" );

}


note( "Editing a draft" );
TODO: {
    local $TODO = "Editing a draft";
}

# note( "Editing an entry with the wrong ditemid" );
# {
#     my ( $req, $res, $u, $errors ) = post_with( undef => undef );
#     is_deeply( $req, $postdecoded_bare, "decoded entry form" );
#     is_deeply( $errors->get_all, [], "no errors" );

#     my $anum_fake = $res->{anum} == 0 ? $res->{anum} + 1 : $res->{anum} - 1;
#     my $ditemid_fake = $res->{ditemid} * 256 + $anum_fake;

#     my $rq = HTTP::Request->new( GET => "$LJ::SITEROOT/entry/".$u->username."/$ditemid_fake/edit" );
#     my $r = DW::Request::Standard->new( $rq );
#     DW::Controller::Entry::_edit( {}, $u->username, $ditemid_fake );
# }

note( "Editing an existing entry" );
TODO: {
    local $TODO = "Editing an existing entry";
}

note( "openid - post" );
TODO: {
    my $u = temp_user( journaltype => "I" );
    LJ::set_remote( $u );

    my $vars;
    $vars = DW::Controller::Entry::_init( { remote => $u } );
}

note( "openid - edit" );
TODO: {
    local $TODO = "Editing an existing entry as openid";
}


done_testing();

1;
