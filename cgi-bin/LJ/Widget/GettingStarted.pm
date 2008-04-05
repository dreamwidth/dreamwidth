package LJ::Widget::GettingStarted;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( stc/widgets/gettingstarted.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    return "" unless $remote;

    # do we really even want to render this?
    return "" unless $class->should_render($remote);

    # epoch -> pretty
    my $date_format = sub {
        my $epoch = shift;
        my $exp = $epoch ? DateTime->from_epoch( epoch => $epoch ) : "";
        return $exp ? $exp->date() : "";
    };

    my $ret = "<h2><span>" . $class->ml('.widget.gettingstarted.title') . " " . LJ::help_icon_html('getting_started') . "</span></h2>";
    $ret .= "<div class='getting-started-items'>";

    unless ($remote->postreg_completed) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.profile.note2') . "<br />";
        $ret .= "<a href='$LJ::SITEROOT/postreg/' class='arrow-link'>" . $class->ml('.widget.gettingstarted.profile.link') . "</a></p>";
    }

    unless ($class->has_enough_friends($remote)) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.friends.note', {'num' => $remote->friends_added_count}) . "<br />";
        $ret .= "<a href='$LJ::SITEROOT/postreg/find.bml' class='arrow-link'>" . $class->ml('.widget.gettingstarted.friends.link') . "</a></p>";
    }

    if ($remote->number_of_posted_posts < 1) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.entry.note') . "<br />";
        $ret .= "<a href='$LJ::SITEROOT/update.bml' class='arrow-link'>" . $class->ml('.widget.gettingstarted.entry.link') . "</a></p>";
    }

    if ($remote->get_userpic_count < 1) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.userpics.note') . "<br />";
        $ret .= "<a href='$LJ::SITEROOT/editpics.bml' class='arrow-link'>" . $class->ml('.widget.gettingstarted.userpics.link') . "</a></p>";
    }

    $ret .= "</div>";
    $ret .= "<p class='account-controls'><strong>" . LJ::name_caps($remote->{caps}) . "</strong>";
    if ($remote->in_class('paid') && !$remote->in_class('perm')) {
        my $exp_epoch = LJ::Pay::get_account_exp($remote);
        my $exp = $date_format->($exp_epoch);
        $ret .= " (<a href='$LJ::SITEROOT/manage/payments/'>" . $class->ml('.widget.gettingstarted.expires', {'date' => $exp}) . "</a>)"
            if $exp;
    }
    $ret .= "</p>";
    $ret .= "<p class='account-controls-manage'><a href='$LJ::SITEROOT/manage/horizon.bml'>" . $class->ml('.widget.gettingstarted.manage') . "</a></p>";

    return $ret;
}

sub should_render {
    my $class = shift;

    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless $remote->has_enabled_getting_started;

    return 1 unless $class->tasks_completed($remote);

    return 0;
}

# has $u completed all of the tasks?
# if $u is not given, remote is used
sub tasks_completed {
    my $class = shift;
    my $u = shift;

    $u = LJ::get_remote() unless $u;
    die "Invalid user" unless $u;

    return 0 unless $u->postreg_completed;
    return 0 unless $class->has_enough_friends($u);

    return 0 unless $u->number_of_posted_posts > 0;
    return 0 unless $u->get_userpic_count > 0;

    return 1;
}

# helper functions used within this widget, but don't
# make a lot of sense out of context

sub has_enough_friends {
    my $self = shift;
    my $u = shift;

    # need 4 friends for us to stop bugging them
    return $u->friends_added_count < 4 ? 0 : 1;
}

1;
