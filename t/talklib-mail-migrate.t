# t/talklib-mail-migrate.t
#
# Test TODO what?
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

use Test::More tests => 1;

use FindBin qw($Bin);
chdir "$Bin/data/userpics" or die "Failed to chdir to t/data/userpics";

package LJ;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::HTMLControls;
use LJ::Talk;

use LJ::Test qw(temp_user memcache_stress);

# preload userpics so we don't have to read the file hundreds of times
open (my $fh, 'good.png') or die $!;
my $USERPIC_DATA = do { local $/; <$fh> };

sub run_tests {

    # * commentu is undef
    #   + targetu is entryu
    #     - parent is entry
    #     - parent is comment
    #   + targetu is otheru
    # * commentu is not undef
    #   + targetu is commentu
    #     - parent is entry
    #     - parent is comment
    #   + targetu is entryu
    #     - parent is entry
    #     - parent is comment
    #   + targetu is otheru

    # other vectors:
    # -- html/text mails
    # -- (comment state is 'S' and $targetu has 'A' rel to entryu)
    # -- html/no html (preformatting)
    # -- userpic/no userpic/default userpic
    # -- subjecticon
    # -- mail encoding

    foreach my $commentu (0, temp_user()) {

        my $entryu = temp_user();
        my $entry  = $entryu->t_post_fake_entry;
        my $otheru = temp_user();

        # hacky manual keys in $entry, yay!
        $entry->{journalu} = $entryu;
        $entry->{entryu}   = $entryu;
        $entry->{itemid}   = $entry->jitemid;
        $entry->{subject}  = $entry->subject_raw;
        $entry->{body}     = $entry->event_raw;

        foreach my $targetu ($commentu, $entryu, $otheru) {
            # skip $targetu=$commentu=undef case
            next unless $targetu;

            foreach my $ispost (0, 1) {
                my $parent = $ispost ? $entry :
                    $entry->t_enter_comment
                    ( u       => temp_user(),
                      subject => "A parent comment subject, w00t!",
                      body    => "OMG that Whitaker's mom is pretty much awesome",
                      );

                # magical flag 'ispost' is used by talklib
                # to determine if the $parent is an entry or comment
                $parent->{ispost} = $ispost;
                $parent->{u}      = $parent->journal;

                # is there a subjecticon associated with this comment?
                foreach my $icon ("md01", undef) {

                    # does the user have an explicit userpic?  no userpic?  default userpic?
                    foreach my $picmode (qw(yes no default)) {

                        my $pic = undef;
                        if ($commentu) {

                            # reset this from where it was modified in a previous iteration
                            delete $commentu->{defaultpicid};

                            unless ($picmode eq 'no') {
                                my $data = $USERPIC_DATA;
                                $pic = LJ::Userpic->create($commentu, data => \$data);

                                # talklib expects 'width' and 'height' in its objects
                                $pic->load_row;

                                if ($picmode eq 'yes') {
                                    $pic->set_keywords('foo');
                                } elsif ($picmode eq 'default') {
                                    $commentu->{defaultpicid} = $pic->{picid};
                                }
                            }
                        }


                        # does the body contain html or no?
                        foreach my $bodytext
                            ("OMG that Whitaker is pretty much awesome",
                             "<h1>OMFGZ</h1> I'm so <i>excited</i> by this <a href='foo'><img src='img.gif'></a>")
                        {

                            foreach my $state (qw(A S)) {

                                my $pic_kw = $picmode eq 'yes' ? 'foo' : undef;

                                my $comment = $entry->t_enter_comment
                                    ( u       => $commentu,
                                      subject => "A comment subject, w00t!",
                                      body    => $bodytext,
                                      parent  => ($ispost ? undef : $parent),

                                      # metadata
                                      picture_keyword => $pic_kw,
                                      subjecticon => $icon,
                                      );

                                # talkurl is really the entry base url, with no thread info
                                my $talkurl = $entry->url;

                                # t_enter_comment returns a real comment object,
                                # which is actually pretty different from what
                                # talklib looks for, bleh!
                                $comment->{state}   = $state;
                                $comment->{u}       = $commentu;
                                $comment->{talkid}  = $comment->jtalkid;
                                $comment->{anum}    = $entry->anum;

                                # metadata
                                $comment->{picture_keyword} = $pic_kw;
                                $comment->{pic} = $pic_kw ? $pic : undef;
                                $comment->{subjecticon} = $icon;

                                if ($state eq 'S') {
                                    LJ::set_rel($targetu, $entryu, 'A');
                                } else {
                                    LJ::clear_rel($targetu, $entryu, 'S');
                                }

                                my %senders =
                                    (
                                     html => [ sub { LJ::Talk::Post::format_html_mail
                                                         ($targetu, $parent, $comment,
                                                          "UTF-8", $talkurl, $entry) },
                                               sub { $comment->format_html_mail(\%{$targetu}) },
                                               ],

                                     text => [ sub { LJ::Talk::Post::format_text_mail
                                                         ($targetu, $parent, $comment,
                                                          $talkurl, $entry) },
                                               sub { $comment->format_text_mail(\%{$targetu}) },
                                               ],
                                     );

                                # initial iteration over text vs html email results
                                foreach my $stype (sort keys %senders) {
                                    my ($smeth_old, $smeth_new) = @{$senders{$stype}};

                                    # call this internal method to load the subject and body
                                    # members of the comment so that the old LJ::Talk APIs will
                                    # be able to access the members they expect
                                    # -- even if a previous old-school API call destroyed the body
                                    #    or subject by cleaning by reference
                                    foreach my $obj ($comment, $parent, $entry) {
                                        $obj->_load_text;
                                    }

                                    my $case_des = sub {
                                        return
                                            "$stype, " .
                                            "screened state=$state, " .
                                            "parent ispost=$ispost, " .
                                            ($targetu == $commentu ? "targetu=commentu" :
                                             ($targetu == $entryu  ? "targetu=entryu" :
                                              ($targetu == $otheru ? "targetu=otheru" : "targetu=unknown!")
                                              )
                                             ) . ", " .
                                             ($bodytext =~ /\</ ? "bodytext=html" : "bodytext=text") . ", " .
                                             "picmode=$picmode, " .
                                             ($icon ? "icon=yes" : "icon=no") . ", " .
                                             "commentu=" . (ref $commentu ? "user" : "0");
                                    };

                                    my $old_rv = $smeth_old->();
                                    my $new_rv = $smeth_new->();
                                    my $des = $case_des->();

                                    my $eq = $old_rv eq $new_rv;
                                    Test::More::ok($eq, "$des");
                                    next if $eq;

                                    # sanity check that a userpic exists if we're in a userpic mode
                                    if ($commentu && $stype eq 'html' &&
                                        ($picmode eq 'yes' || $picmode eq 'default'))
                                    {
                                        unless ($old_rv =~ /$LJ::USERPIC_ROOT/ &&
                                                $new_rv =~ /$LJ::USERPIC_ROOT/)
                                        {
                                            print
                                                "Unexpected output: picmode=$picmode, but " .
                                                "$LJ::USERPIC_ROOT not present? [$des]\n";
                                        }
                                    }

                                    # sanity check that a subjecticon exists if we're testing for one
                                    if ($icon && $stype eq 'html') {
                                        unless ($old_rv =~ /$icon/ && $new_rv =~ /$icon/) {
                                            print
                                                "Unexpected output: icon=$icon, but not " .
                                                "present? [$des]\n";
                                        }
                                    }

                                    # otherwise warn with a diff if Text::Diff is installed and someone
                                    # is debugging this code... uncomment the next block to see useful
                                    # failure info.

                                    #print ("="x80) . "\n$des\n\n";
                                    #
                                    #use Text::Diff;
                                    #my $diff = diff(\$old_rv, \$new_rv, { STYLE => "Unified" });
                                    #print "DIFF:\n $diff\n";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

SKIP: {
    Test::More::skip "These tests are broken and useless for the moment.", 1;
    memcache_stress {
        run_tests;
    }
}
