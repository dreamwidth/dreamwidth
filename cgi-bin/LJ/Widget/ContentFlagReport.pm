package LJ::Widget::ContentFlagReport;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::ContentFlag;

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote() or die "You must be logged in to flag content";

    if ($opts{flag}) {
        my $url = $opts{flag}->url;

        my $itemtype;
        if ($opts{itemid}) {
            $itemtype = "Entry";
        } else {
            $itemtype = "Journal";
        }

        return qq {
            <p>Thank you for your report. We will process it as soon as possible and take the appropriate action.
                Unfortunately, we can't respond individually to each report we receive.</p>
            <ul>
               <li><a href="$url">Return to $itemtype</a></li>
               <li><a href="$LJ::SITEROOT/site/search.bml">Explore $LJ::SITENAME</a></li>
            </ul>
        }; #' stupid emacs }
    } else {
        $ret .= $class->start_form;

        my $ditemid = $opts{itemid};
        my $user = $opts{user};
        my $journal = LJ::load_user($user) or return "Invalid username";

        my $url = $journal->journal_base;
        if ($ditemid) {
            my $entry = LJ::Entry->new($journal, ditemid => $ditemid);
            return "Invalid entry" unless $entry && $entry->valid;
            $url = $entry->url;
        }

        my $itemtype = $ditemid ? 'entry' : 'journal';
        my $journal_link = "<a href='$url'>Return to " . ucfirst $itemtype . "</a>";

        my $cat_radios;
        my $cats = LJ::ContentFlag->category_names;
        my $cats_ordered = LJ::ContentFlag->category_order;

        foreach my $cat (@$cats_ordered) {
            $cat_radios .= $class->html_check(
                type => 'radio',
                name => 'catid',
                value => $cat,
                id    => "cat_$cat",
                label => $cats->{$cat},
            ) . "<br />";
        }

        $ret .= qq {
            <p>To report anything outside of these categories, please use the <a href="$LJ::SITEROOT/abuse/report.bml">Abuse reporting system</a>.</p>
            <p><em>What is the nature of this content?</em></p>
            <div>
            $cat_radios
            </div>
        };

        $ret .= $class->html_hidden( user => $user, itemid => $ditemid );
        $ret .= "<p>" . $class->html_submit('Submit Report') . " $journal_link</p>";
    }

    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my $journal = LJ::load_user($post->{user}) or die "You must select a journal to report\n";
    my %params = (
        catid => $post->{catid},
        journal => $journal,
        itemid => $post->{itemid},
        type => $post->{itemid} ? LJ::ContentFlag::ENTRY : LJ::ContentFlag::JOURNAL,
    );

    my $remote = LJ::get_remote() or die "You must be logged in to flag content";

    die "You must select the type of abuse you want to report\n"
        unless $params{catid};

    my $cats_to_spamreports = LJ::ContentFlag->categories_to_spamreports;
    foreach my $cat (@$cats_to_spamreports) {
        if ($cat eq $params{catid}) {
            if ($params{itemid}) { # entry
                return BML::redirect("$LJ::SITEROOT/tools/content_flag_spam.bml?user=$post->{user}&itemid=$params{itemid}");
            } else { # journal
                return BML::redirect("$LJ::SITEROOT/tools/content_flag_spam.bml?user=$post->{user}");
            }
        }
    }

    # create flag
    $params{flag} = LJ::ContentFlag->flag(%params, reporter => $remote);

    my $cats_to_abuse = LJ::ContentFlag->categories_to_abuse;
    foreach my $cat (keys %$cats_to_abuse) {
        if ($cat eq $params{catid}) {
            if ($params{itemid}) {
                my $entry = LJ::Entry->new($journal, ditemid => $params{itemid});
                return "Invalid entry" unless $entry && $entry->valid;
                $journal = $entry->poster;
            }
            return BML::redirect("$LJ::SITEROOT/abuse/report.bml?flagid=" . $params{flag}->flagid . "&stage=$cats_to_abuse->{$cat}");
        }
    }

    return %params;
}

1;
