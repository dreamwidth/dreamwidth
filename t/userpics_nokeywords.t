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

use Test::More tests => 36;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Userpic;
use LJ::Test qw (temp_user);
use FindBin qw($Bin);
use Digest::MD5;
use LJ::Entry;
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

my $up;
my $u = temp_user();
ok($u, "temp user");
die unless $u;

sub run_tests {

    # rename unamed unused userpic
    {
        my $up = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
        ok( $up, "created userpic: no keyword" );
        my $pic_num_keyword = $up->keywords;
        ok( $pic_num_keyword =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank (pic\#num) keyword" );
        $up->set_and_rename_keywords( "keyword", $pic_num_keyword );
        my $new_keyword = $up->keywords;
        ok( $new_keyword eq "keyword", "userpic now has keyword: keyword - $new_keyword" );

        # rename second unamed unused userpic
        # check first userpic still renamed
        my $up2 = eval { LJ::Userpic->create($u, data => file_contents("good.png")); };
        ok( $up2, "created second userpic: no keyword" );
        my $pic_num_keyword2 = $up2->keywords;
        ok( $pic_num_keyword2 =~ /^\s*pic\#(\d+)\s*$/, "userpic 2 has blank keyword" );
        $up2->set_and_rename_keywords( "keyword2", $pic_num_keyword2 );
        my $new_keyword2 = $up2->keywords;
        ok( $new_keyword2 eq "keyword2", "userpic 2 now has keyword: keyword2 - $new_keyword2" );
        ok( $new_keyword eq "keyword", "userpic 1 still has keyword: keyword - $new_keyword" );

        $up->delete;
        $up2->delete;
    }

    # checking post and comments with renaming
    # rename userpic - check userpic still attached to post
    {
        my $up = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
        ok( $up, "created userpic: no keyword" );
        my $pic_num_keyword = $up->keywords;
        ok( $pic_num_keyword =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank keyword" );

        my %entry_props = ( picture_keyword=>$pic_num_keyword );
        my %requests = ( tz => "guess", subject => "post subject", event => "test post", username=>$u->user, props=>\%entry_props );
        my $req = \%requests;
        my $err = 0;
        my %flags = %{ delete $requests{flags} || {} };
        my $res = LJ::Protocol::do_request( "postevent", $req, \$err, { noauth => 1, nocheckcap => 1, %flags } );
        my $ditemid = $res->{'itemid'};
        my $entry_obj = LJ::Entry->new( $u, jitemid => $ditemid );
        my $initial_entry_keyword = $entry_obj->userpic_kw;
        ok( $res, "successfully made a post ($ditemid) with keyword $pic_num_keyword = $initial_entry_keyword" );

        $up->set_and_rename_keywords( "keyword", $pic_num_keyword );
        my $new_keyword = $up->keywords;
        ok( $new_keyword eq "keyword", "userpic now has keyword: keyword - $new_keyword" );
        ok( $entry_obj, "re-accessed entry" );
        my $entry_keyword = $entry_obj->userpic_kw;
        ok( $entry_keyword eq "keyword", "entry now has keyword: keyword -  $entry_keyword" );
        

        # make a comment with an unamed userpic
        # rename userpic - check userpic still attached to comment

        my $up2 = eval { LJ::Userpic->create($u, data => file_contents("good.png")); };
        ok( $up2, "created second userpic: no keyword" );
        my $pic_num_keyword2 = $up2->keywords;
        ok( $pic_num_keyword2 =~ /^\s*pic\#(\d+)\s*$/, "userpic 2 has blank keyword" );

	my $fake_comment = $entry_obj->t_enter_comment( u => $u );
        ok( $fake_comment, "created a fake comment" );

        $fake_comment->set_prop( 'picture_mapid', $u->get_mapid_from_keyword($pic_num_keyword2) );
	my $comment_kw = $fake_comment->userpic_kw;
        ok( $comment_kw, "Comment has keyword $comment_kw" );

        $up2->set_and_rename_keywords( "keyword2", $pic_num_keyword2 );
        my $new_keyword2 = $up2->keywords;
        ok( $new_keyword2 eq "keyword2", "userpic 2 now has keyword: keyword2 - $new_keyword2" );
        my $comment_keyword = $fake_comment->userpic_kw;
        ok( $comment_keyword eq "keyword2", "comment now has keyword: keyword2 - $comment_keyword" );
        ok( $entry_keyword eq "keyword", "entry still has keyword: keyword -  $entry_keyword" );

        my $dres = LJ::delete_entry($u, $ditemid);
        ok($dres, "successfully deleted $ditemid");
        $up->delete;
        $up2->delete;

    }

    # posting and commenting where keywords are changed but not renamed
    # change usepic keyword without renaming - check userpic no longer attached to post
    {
        my $up = eval { LJ::Userpic->create($u, data => file_contents("good.jpg")); };
        ok( $up, "created userpic: no keyword" );
        my $pic_num_keyword = $up->keywords;
        ok( $pic_num_keyword =~ /^\s*pic\#(\d+)\s*$/, "userpic has blank keyword" );

        my %entry_props = ( picture_keyword=>$pic_num_keyword );
        my %requests = ( tz => "guess", subject => "post subject", event => "test post", username=>$u->user, props=>\%entry_props );
        my $req = \%requests;
        my $err = 0;
        my %flags = %{ delete $requests{flags} || {} };
        my $res = LJ::Protocol::do_request( "postevent", $req, \$err, { noauth => 1, nocheckcap => 1, %flags } );
        my $ditemid = $res->{'itemid'};
        ok( $res, "successfully made a post ($ditemid) with keyword $pic_num_keyword" );

        $up->set_keywords( "keyword", $pic_num_keyword );
        my $new_keyword = $up->keywords;
        ok( $new_keyword eq "keyword", "userpic now has keyword: keyword - $new_keyword" );
        my $entry_obj = LJ::Entry->new( $u, jitemid => $ditemid );
        my $entry_keyword = $entry_obj->userpic_kw;
        ok( $entry_keyword eq $pic_num_keyword, "entry still has pic num keyword: $entry_keyword" );
        
        # make a comment with an unamed userpic
        # change userpic keyword without renaming - check userpic no longer attached to comment

        my $up2 = eval { LJ::Userpic->create($u, data => file_contents("good.png")); };
        ok( $up2, "created second userpic: no keyword" );
        my $pic_num_keyword2 = $up2->keywords;
        ok( $pic_num_keyword2 =~ /^\s*pic\#(\d+)\s*$/, "userpic 2 has blank keyword" );

	my $fake_comment = $entry_obj->t_enter_comment( u=>$u );
        ok( $fake_comment, "created a fake comment" );

        $fake_comment->set_prop( 'picture_mapid', $u->get_mapid_from_keyword($pic_num_keyword2) );
	my $comment_kw = $fake_comment->userpic_kw;
        ok( $comment_kw, "Comment has keyword $comment_kw" );

        $up2->set_keywords("keyword2", $pic_num_keyword2);
        my $new_keyword2 = $up2->keywords;
        ok( $new_keyword2 eq "keyword2", "userpic 2 now has keyword: keyword2 - $new_keyword2" );
        my $comment_keyword = $fake_comment->userpic_kw;
        ok( $comment_keyword eq $pic_num_keyword2, "comment still has pic num keyword: $comment_keyword" );
        ok( $entry_keyword eq $pic_num_keyword, "entry still has pic num keyword: $entry_keyword" );

        my $dres = LJ::delete_entry($u, $ditemid);
        ok( $dres, "successfully deleted $ditemid" );

        $up->delete;
        $up2->delete;
    }
}

eval { delete_all_userpics($u) };
ok( !$@, "deleted all userpics, if any existed" );

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
