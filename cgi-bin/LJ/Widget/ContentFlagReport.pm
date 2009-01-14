package LJ::Widget::ContentFlagReport;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::ContentFlag;

sub need_res { qw( stc/widgets/contentflagreport.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote() or die "<?needlogin?>";

    if ($opts{flag}) {
        my $url = $opts{flag}->url;

        my $itemtype = $opts{itemid} ? "entry" : "journal";
        my $return_text = $itemtype eq "entry" ? $class->ml('widget.contentflagreport.btn.returnentry') : $class->ml('widget.contentflagreport.btn.returnjournal');

        $ret .= "<p>" . $class->ml('widget.contentflagreport.done') . "</p>";
        $ret .= "<ul><li><a href='$url'>$return_text</a></li>";
        $ret .= "<li><a href='$LJ::SITEROOT/explore/'>" . $class->ml('widget.contentflagreport.explore', { sitenameabbrev => $LJ::SITENAMEABBREV }) . "</a></li></ul>";

        return $ret;
    } else {
        my $ditemid = $opts{itemid};
        my $user = $opts{user};
        my $journal = LJ::load_user($user) or return $class->ml('widget.contentflagreport.error.invalidusername');

        my $url = $journal->journal_base;
        if ($ditemid) {
            my $entry = LJ::Entry->new($journal, ditemid => $ditemid);
            return $class->ml('widget.contentflagreport.error.invalidentry') unless $entry && $entry->valid;
            $url = $entry->url;
        }

        my $itemtype = $ditemid ? "entry" : "journal";
        my $btn_text = $itemtype eq "entry" ? $class->ml('widget.contentflagreport.btn.returnentry') : $class->ml('widget.contentflagreport.btn.returnjournal');

        if ($opts{confirm}) {
            my $back_url = $itemtype eq "entry" ? "$LJ::SITEROOT/tools/content_flag.bml?user=$user&itemid=$ditemid" : "$LJ::SITEROOT/tools/content_flag.bml?user=$user";

            $ret .= $class->ml('widget.contentflagreport.confirm', { aopts => "href='$back_url'" });

            $ret .= $class->start_form;
            $ret .= $class->html_hidden( user => $user, itemid => $ditemid );
            $ret .= "<p>" . $class->html_submit($class->ml('widget.contentflagreport.btn.submit')) . " <a href='$url'>$btn_text</a></p>";
            $ret .= $class->end_form;
        } else {
            my $spam_url = $itemtype eq "entry" ? "$LJ::SITEROOT/tools/content_flag_spam.bml?user=$user&itemid=$ditemid" : "$LJ::SITEROOT/tools/content_flag_spam.bml?user=$user";
            my $confirm_url = $itemtype eq "entry" ? "$LJ::SITEROOT/tools/content_flag.bml?user=$user&itemid=$ditemid&confirm=1" : "$LJ::SITEROOT/tools/content_flag.bml?user=$user&confirm=1";

            $ret .= "<p>" . $class->ml('widget.contentflagreport.note') . "</p>";
            $ret .= $class->ml('widget.contentflagreport.description', {
                sitename => $LJ::SITENAMESHORT,
                spamaopts => "href='$spam_url'",
                confirmaopts => "href='$confirm_url'",
            });

            $ret .= $class->start_form;
            $ret .= $class->html_hidden( url => $url );
            $ret .= "<p>" . $class->html_submit( return => $btn_text ) . "</p>";
            $ret .= $class->end_form;
        }
    }

    return $ret;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my $remote = LJ::get_remote() or die "<?needlogin?>";

    if ($post->{return}) {
        my $url = LJ::CleanHTML::canonical_url($post->{url});

        die $class->ml('widget.contentflagreport.error.invalidurl') unless $url;
        return BML::redirect($url);
    }

    my $journal = LJ::load_user($post->{user}) or die $class->ml('widget.contentflagreport.error.invalidusername');
    my %params = (
        catid => LJ::ContentFlag::EXPLICIT_ADULT_CONTENT,
        journal => $journal,
        itemid => $post->{itemid},
        type => $post->{itemid} ? LJ::ContentFlag::ENTRY : LJ::ContentFlag::JOURNAL,
    );

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
                return $class->ml('widget.contentflagreport.error.invalidentry') unless $entry && $entry->valid;
                $journal = $entry->poster;
            }
            return BML::redirect("$LJ::SITEROOT/abuse/report.bml?flagid=" . $params{flag}->flagid . "&stage=$cats_to_abuse->{$cat}");
        }
    }

    return %params;
}

1;
