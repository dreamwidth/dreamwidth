# t/userpics_nokeywords.t
#
# Tests for the use of userpics with the keyword '0'
# NB.  Although this tests commenting and posting backends it
# doesn't test the User Interface or Protocol.  Nor anything to do
# with messaging.
#
# Copyright (c) 2008-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modigy it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 22;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Userpic;
use LJ::Test qw (temp_user);
use FindBin qw($Bin);
use Digest::MD5;
use LJ::Entry;
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

my $up;
my $u = temp_user();
ok( $u, "temp user" );
die unless $u;

sub run_tests {

    # renaming of a userpic, then posting with that userpic
    {
        # rename unamed unused userpic 0
        my $up_t1 = eval { LJ::Userpic->create( $u, data => file_contents("good.jpg") ); };
        ok( $up_t1, "created userpic: no keyword" );
        $up_t1->set_keywords("keyword");
        my $pic_num_keyword_t1 = $up_t1->keywords;
        ok( $pic_num_keyword_t1 eq "keyword", "userpic has keyword : keyword" );
        $up_t1->set_and_rename_keywords( "0", $pic_num_keyword_t1 );
        my $new_keyword_t1 = $up_t1->keywords;
        ok( $new_keyword_t1 eq "0", "userpic now has keyword: 0 - $new_keyword_t1" );

        # post an entry with the renamed userpic
        my $entry_obj_t1 = $u->t_post_fake_entry;
        $entry_obj_t1->set_prop( 'picture_mapid', $u->get_mapid_from_keyword("0") );
        my $entry_keyword_t1 = $entry_obj_t1->userpic_kw;
        ok( $entry_obj_t1, "successfully made a post with keyword 0 - $entry_keyword_t1" );

        $up_t1->delete;
    }

    # renaming a userpic after it's been used in a post
    {
        # Setting up a userpic with a "non 0" keyword and then posting with it
        my $up_t2 = eval { LJ::Userpic->create( $u, data => file_contents("good.jpg") ); };
        ok( $up_t2, "created userpic: no keyword" );
        my $pic_num_keyword_t2 = $up_t2->keywords;
        ok( $pic_num_keyword_t2 =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank keyword" );

        my $entry_obj_t2 = $u->t_post_fake_entry;
        $entry_obj_t2->set_prop( 'picture_mapid', $u->get_mapid_from_keyword($pic_num_keyword_t2) );
        my $entry_keyword_t2 = $entry_obj_t2->userpic_kw;
        ok( $entry_obj_t2,
            "successfully made a post with keyword $pic_num_keyword_t2 - $entry_keyword_t2" );

        # renaming the userpic after posting
        $up_t2->set_and_rename_keywords( "0", $pic_num_keyword_t2 );
        my $new_keyword_t2 = $up_t2->keywords;
        ok( $new_keyword_t2 eq "0", "userpic now has keyword: 0 - $new_keyword_t2" );
        my $check_entry_keyword_t2 = $entry_obj_t2->userpic_kw;
        ok( $check_entry_keyword_t2 eq "0", "entry now has keyword: 0 -  $check_entry_keyword_t2" );

        my $dres = LJ::delete_entry( $u, $entry_obj_t2->jitemid );
        ok( $dres, "successfully deleted entry" );

        $up_t2->delete;
    }

    # checking user of 0 keyword userpics in comments
    {
        my $up_t3 = eval { LJ::Userpic->create( $u, data => file_contents("good.jpg") ); };
        ok( $up_t3, "created userpic: no keyword" );
        my $pic_num_keyword_t3 = $up_t3->keywords;
        ok( $pic_num_keyword_t3 =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank keyword" );

        my $entry_obj_t3 = $u->t_post_fake_entry;
        $entry_obj_t3->set_prop( 'picture_mapid', $u->get_mapid_from_keyword($pic_num_keyword_t3) );
        my $entry_keyword3_t3 = $entry_obj_t3->userpic_kw;
        ok( $entry_obj_t3,
            "successfully made a post with keyword $pic_num_keyword_t3 - $entry_keyword3_t3" );

        # make a comment with an unamed userpic
        # change userpic keyword without renaming - check userpic no longer attached to comment

        my $up2_t3 = eval { LJ::Userpic->create( $u, data => file_contents("good.png") ); };
        ok( $up2_t3, "created second userpic: no keyword" );
        $up2_t3->set_keywords("keyword");
        my $pic_num_keyword2_t3 = $up2_t3->keywords;
        ok( $pic_num_keyword2_t3 eq "keyword", "userpic 2 has keyword" );

        my $fake_comment_t3 = $entry_obj_t3->t_enter_comment( u => $u );
        ok( $fake_comment_t3, "created a fake comment" );

        $fake_comment_t3->set_prop( 'picture_mapid',
            $u->get_mapid_from_keyword($pic_num_keyword2_t3) );
        my $mapid         = $u->get_mapid_from_keyword($pic_num_keyword2_t3);
        my $comment_kw_t3 = $fake_comment_t3->userpic_kw;
        ok( $comment_kw_t3, "Comment has keyword $comment_kw_t3: mapid $mapid " );

        $up2_t3->set_and_rename_keywords( "0keyword", $pic_num_keyword2_t3 );
        my $new_keyword2_t3 = $up2_t3->keywords;
        my $nmapid          = $u->get_mapid_from_keyword($new_keyword2_t3);
        ok( $new_keyword2_t3 eq "0keyword",
            "userpic 2 now has keyword: 0keyword - $new_keyword2_t3 : mapid $nmapid" );
        my $comment_keyword_t3 = $fake_comment_t3->userpic_kw;
        ok( $comment_keyword_t3 eq "0keyword",
            "comment has keyword 0keyword - $comment_keyword_t3" );

        my $dres = LJ::delete_entry( $u, $entry_obj_t3->jitemid );
        ok( $dres, "successfully deleted entry" );

        $up_t3->delete;
        $up2_t3->delete;
    }
}

eval { delete_all_userpics($u) };
ok( !$@, "deleted all userpics, if any existed" );

run_tests();

sub file_contents {
    my $file = shift;
    open( my $fh, $file ) or die $!;
    my $ct = do { local $/; <$fh> };
    return \$ct;
}

sub delete_all_userpics {
    my $u        = shift;
    my @userpics = LJ::Userpic->load_user_userpics($u);
    foreach my $up (@userpics) {
        $up->delete;
    }
}
