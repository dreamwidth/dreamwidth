# t/userpics_nokeywords.t
#
# Test LJ::Userpic.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 33;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Userpic;
use LJ::Test qw (temp_user);
use FindBin qw($Bin);
use Digest::MD5;
use LJ::Entry;
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

my $up;

sub run_tests {

    # rename unamed unused userpic
    {
        my $u = temp_user();
        my $up_t1 = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
        ok( $up_t1, "created userpic: no keyword" );
        my $pic_num_keyword_t1 = $up_t1->keywords;
        ok( $pic_num_keyword_t1 =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank (pic\#num) keyword" );
        $up_t1->set_and_rename_keywords( "keyword", $pic_num_keyword_t1 );
        my $new_keyword_t1 = $up_t1->keywords;
        is( $new_keyword_t1, "keyword", "userpic now has keyword: keyword" );

        # rename second unamed unused userpic
        # check first userpic still renamed
        my $up2_t1 = eval { LJ::Userpic->create($u, data => file_contents("good.png")); };
        ok( $up2_t1, "created second userpic: no keyword" );
        my $pic_num_keyword2_t1 = $up2_t1->keywords;
        ok( $pic_num_keyword2_t1 =~ /^\s*pic\#(\d+)\s*$/, "userpic 2 has blank keyword" );
        $up2_t1->set_and_rename_keywords( "keyword2", $pic_num_keyword2_t1 );
        my $new_keyword2_t1 = $up2_t1->keywords;
        is( $new_keyword2_t1, "keyword2", "userpic 2 now has keyword: keyword2" );
        is( $new_keyword_t1, "keyword", "userpic 1 still has keyword: keyword" );

        $up_t1->delete;
        $up2_t1->delete;

        delete_all_userpics( $u );
    }

    # checking post and comments with renaming
    # rename userpic - check userpic still attached to post
    {
        my $u = temp_user();
        my $up_t2 = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
        ok( $up_t2, "created userpic: no keyword" );
        my $pic_num_keyword_t2 = $up_t2->keywords;
        ok( $pic_num_keyword_t2 =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank keyword" );

        my $entry_obj_t2 = $u->t_post_fake_entry;
        $entry_obj_t2->set_prop( 'picture_mapid', $u->get_mapid_from_keyword( $pic_num_keyword_t2 ) );
        my $entry_keyword_t2 = $entry_obj_t2->userpic_kw;
        ok( $entry_obj_t2, "successfully made a post with keyword $pic_num_keyword_t2 - $entry_keyword_t2" );

        $up_t2->set_and_rename_keywords( "keyword", $pic_num_keyword_t2 );
        my $new_keyword_t2 = $up_t2->keywords;
        is( $new_keyword_t2, "keyword", "userpic now has keyword: keyword" );
        my $check_entry_keyword_t2 = $entry_obj_t2->userpic_kw;
        is( $check_entry_keyword_t2, "keyword", "entry now has keyword: keyword" );
        

        # make a comment with an unamed userpic
        # rename userpic - check userpic still attached to comment

        my $up2_t2 = eval { LJ::Userpic->create($u, data => file_contents("good.png")); };
        ok( $up2_t2, "created second userpic: no keyword" );
        my $pic_num_keyword2_t2 = $up2_t2->keywords;
        ok( $pic_num_keyword2_t2 =~ /^\s*pic\#(\d+)\s*$/, "userpic 2 has blank keyword" );

	my $fake_comment_t2 = $entry_obj_t2->t_enter_comment( u => $u );
        ok( $fake_comment_t2, "created a fake comment" );

        $fake_comment_t2->set_prop( 'picture_mapid', $u->get_mapid_from_keyword( $pic_num_keyword2_t2 ) );
	my $comment_kw_t2 = $fake_comment_t2->userpic_kw;
        ok( $comment_kw_t2, "Comment has keyword $comment_kw_t2" );

        $up2_t2->set_and_rename_keywords( "keyword2", $pic_num_keyword2_t2 );
        my $new_keyword2_t2 = $up2_t2->keywords;
        ok( $new_keyword2_t2 eq "keyword2", "userpic 2 now has keyword: keyword2 - $new_keyword2_t2" );
        my $comment_keyword_t2 = $fake_comment_t2->userpic_kw;
        ok( $comment_keyword_t2 eq "keyword2", "comment now has keyword: keyword2 - $comment_keyword_t2" );
        my $entry_keyword2_t2 = $entry_obj_t2->userpic_kw;
        ok( $entry_keyword2_t2 eq "keyword", "entry still has keyword: keyword -  $entry_keyword2_t2" );

        my $dres_t2 = LJ::delete_entry($u, $entry_obj_t2->jitemid);
        ok($dres_t2, "successfully deleted entry");
        $up_t2->delete;
        $up2_t2->delete;

        delete_all_userpics( $u );
    }


    # posting and commenting where keywords are changed but not renamed
    # change usepic keyword without renaming - check userpic no longer attached to post
    {
        my $u = temp_user();
        my $up_t3 = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
        ok( $up_t3, "created userpic: no keyword" );
        my $pic_num_keyword_t3 = $up_t3->keywords;
        ok( $pic_num_keyword_t3 =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank keyword" );

        my $entry_obj_t3 = $u->t_post_fake_entry;
        $entry_obj_t3->set_prop( 'picture_mapid', $u->get_mapid_from_keyword( $pic_num_keyword_t3 ) );
        my $entry_keyword3_t3 = $entry_obj_t3->userpic_kw;
        ok( $entry_obj_t3, "successfully made a post with keyword $pic_num_keyword_t3 - $entry_keyword3_t3" );

        $up_t3->set_keywords( "keyword", $pic_num_keyword_t3 );
        my $new_keyword_t3 = $up_t3->keywords;
        is( $new_keyword_t3, "keyword", "userpic now has keyword: keyword" );
        is( $entry_keyword3_t3, $pic_num_keyword_t3, "entry still has pic num keyword: $pic_num_keyword_t3" );
        
        # make a comment with an unamed userpic
        # change userpic keyword without renaming - check userpic no longer attached to comment

        my $up2_t3 = eval { LJ::Userpic->create($u, data => file_contents("good.png")); };
        ok( $up2_t3, "created second userpic: no keyword" );
        my $pic_num_keyword2_t3 = $up2_t3->keywords;
        ok( $pic_num_keyword2_t3 =~ /^\s*pic\#(\d+)\s*$/, "userpic 2 has blank keyword" );

	my $fake_comment_t3 = $entry_obj_t3->t_enter_comment( u=>$u );
        ok( $fake_comment_t3, "created a fake comment" );

        $fake_comment_t3->set_prop( 'picture_mapid', $u->get_mapid_from_keyword( $pic_num_keyword2_t3 ) );
	my $comment_kw_t3 = $fake_comment_t3->userpic_kw;
        ok( $comment_kw_t3, "Comment has keyword $comment_kw_t3" );

        $up2_t3->set_keywords( "keyword2", $pic_num_keyword2_t3 );
        my $new_keyword2_t3 = $up2_t3->keywords;
        is( $new_keyword2_t3, "keyword2", "userpic 2 now has keyword: keyword2" );
        my $comment_keyword_t3 = $fake_comment_t3->userpic_kw;
        ok( !$comment_keyword_t3, "comment still has no keyword" );
        is( $entry_keyword3_t3, $pic_num_keyword_t3, "entry still has pic num keyword: $pic_num_keyword_t3" );

        my $dres = LJ::delete_entry($u, $entry_obj_t3->jitemid);
        ok( $dres, "successfully deleted entry" );

        $up_t3->delete;
        $up2_t3->delete;

        delete_all_userpics( $u );
    }
}

run_tests();

sub file_contents {
    my $file = shift;
    open (my $fh, $file) or die $!;
    my $ct = do { local $/; <$fh> };
    return \$ct;
}

sub delete_all_userpics {
    my $u = shift;
    my @userpics = LJ::Userpic->load_user_userpics( $u );
    foreach my $up ( @userpics ) {
        $up->delete;
    }
}
