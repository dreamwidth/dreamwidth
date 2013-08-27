# -*-perl-*-
use strict;

use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN {
    require 'ljlib.pl'; 
}
use LJ::Test qw ( temp_user temp_comm );

use DW::Draft;
use LJ::Protocol;

plan tests => 20;

# set up user

my $u = temp_user();

# checking.
my $all_drafts = DW::Draft->all_drafts_for_user( $u );
is ( scalar @$all_drafts, 0, "all_drafts_for_user() returning correct value (0)" );


my $req =  {
    posterid => $u->id,
    anum => 1,
    subject => "Test Subject",
    hour => '13',
    min => '53',
    subject => 'test draft',
    allowmask => '1',
    event => "this is a test of draft\n\nText after newlines.\n",
    props => { 
        current_mood => 'moody',
        current_location => 'test world',
        opt_nocomments => 0,
        taglist => 'tagone',
        current_moodid => '68',
        current_music => 'keystrokes',
        opt_preformatted => '0',
        adult_content_reason => 'none',
        picture_keyword => 'test keyword',
        opt_backdated => '0',
        opt_screening => 'R',
        adult_content => 'none',
        opt_noemail => '0',
    },
    day => '19',
    slug => 'slug slug slug slug slug',
    security => 'usemask',
    mon => '06',
    year => '2013',
};

# basic CRUD
my $draft = DW::Draft->create_draft( $u, $req );

my $firstid = $draft->id;

$draft = DW::Draft->create_draft( $u, $req );

ok ( $draft->id > 0 );

$all_drafts = DW::Draft->all_drafts_for_user( $u );

is ( scalar @$all_drafts, 2, "all_drafts_for_user() returning correct value." );

my $all_scheduled = DW::Draft->all_scheduled_posts_for_user( $u );
is ( scalar @$all_scheduled, 0, "all_scheduled_posts_for_user() still returning 0 after 2 drafts created." );

my $id =  $draft->id;
$draft = DW::Draft->by_id( $u, $id );

ok ( $draft->{modtime} > 0, "modtime set" );
ok ( $draft->{createtime} > 0, "createtime set" );
is ( $req->{subject}, $draft->{subject}, "subject set" );
# event is short enough that it should match summary
is ( $req->{event}, $draft->{summary}, "summary" );

$draft->delete();
warn("deleted");
$all_drafts = DW::Draft->all_drafts_for_user( $u );
warn("loaded drafts");

is ( scalar @$all_drafts, 1, "delete() removed draft." );

$draft = DW::Draft->by_id( $u, $firstid);
$draft->delete();

$all_drafts = DW::Draft->all_drafts_for_user( $u );
is ( scalar @$all_drafts, 0, "second delete() removed last draft." );

# test create/load round trip

$draft = DW::Draft->create_draft( $u, $req );

ok ( $draft->id > 0 );

$id =  $draft->id;

$draft = DW::Draft->by_id( $u, $id );
$req->{subject} = "new subject";
$req->{props}->{current_mood} = 'updated';

$draft->set_req( $req );
$draft->update();

$draft = $draft->by_id( $u, $id );
is ( $draft->{subject}, "new subject", "subject updated" );
is ( $draft->req->{subject}, "new subject", "subject updated on req" );
is ( $draft->req->{props}->{current_mood}, 'updated', 'req props updated' );

# test scheduled posts

my $scheduled_req = {
    posterid => $u->id,
    anum => 1,
    subject => "Test Scheduled",
    hour => '13',
    min => '53',
    subject => 'test scheduled',
    allowmask => '1',
    event => "this is a test of draft\n\nText after newlines.\n",
    props => { 
        current_mood => 'moody',
        current_location => 'test world',
        opt_nocomments => 0,
        taglist => 'tagone',
        current_moodid => '68',
        current_music => 'keystrokes',
        opt_preformatted => '0',
        adult_content_reason => 'none',
        picture_keyword => 'test keyword',
        opt_backdated => '0',
        opt_screening => 'R',
        adult_content => 'none',
        opt_noemail => '0',
    },
    day => '19',
    slug => 'slug slug slug slug slug',
    security => 'usemask',
    mon => '06',
    year => '2013',
};

my $scheduled_opts = {
    nextscheduletime => LJ::mysql_time( time ),
};

my $scheduled_once = DW::Draft->create_scheduled_draft( $u, $scheduled_req, { nextscheduletime => LJ::mysql_time( time )} );

$all_scheduled = DW::Draft->all_scheduled_posts_for_user( $u );
is ( scalar @$all_scheduled, 1, "all_scheduled_posts_for_user() for scheduled posts returning correct value after creating a scheduled post." );

my $scheduled_multi = DW::Draft->create_scheduled_draft( $u, $scheduled_req, { nextscheduletime => LJ::mysql_time( time ), recurring_period => 'day' } );

is ( 'day', $scheduled_multi->recurring_period, "recurring period saved correctly." );

# check that the sizes are correct

$all_drafts = DW::Draft->all_drafts_for_user( $u );

# testing both to make sure caching works
is ( scalar @$all_drafts, 1, "all_drafts_for_user() returning correct value after creating two scheduled posts." );

$all_scheduled = DW::Draft->all_scheduled_posts_for_user( $u );
is ( scalar @$all_scheduled, 2, "all_scheduled_posts_for_user() returning correct value after creating a scheduled post." );

$scheduled_multi->delete();
$scheduled_once->delete();
$draft->delete();

$all_drafts = DW::Draft->all_drafts_for_user( $u );

# testing both to make sure caching works
is ( scalar @$all_drafts, 0, "all_drafts_for_user() returning correct value after deleting all drafts" );

$all_scheduled = DW::Draft->all_scheduled_posts_for_user( $u );
is ( scalar @$all_scheduled, 0, "all_scheduled_posts_for_user() returning correct value after delting all scheduled posts." );


