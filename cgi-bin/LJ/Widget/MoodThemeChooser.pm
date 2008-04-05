package LJ::Widget::MoodThemeChooser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Customize );

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/moodthemechooser.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";

    my $preview_moodthemeid = defined $opts{preview_moodthemeid} ? $opts{preview_moodthemeid} : $u->{moodthemeid};
    my $forcemoodtheme = defined $opts{forcemoodtheme} ? $opts{forcemoodtheme} : $u->{opt_forcemoodtheme} eq 'Y';

    my $ret = "<fieldset><legend>" . $class->ml('widget.moodthemechooser.title') . "</legend>";
    $ret .= "</fieldset>" if $u->prop('stylesys') == 2;
    $ret .= "<p class='detail'>" . $class->ml('widget.moodthemechooser.desc') . " " . LJ::help_icon('mood_themes') . "</p>";

    my @themes = LJ::Customize->get_moodtheme_select_list($u);

    $ret .= "<br /><br /><div class='moodtheme-form'>";
    $ret .= $class->html_select(
        { name => 'moodthemeid',
          id => 'moodtheme_dropdown',
          selected => $preview_moodthemeid },
        map { {value => $_->{moodthemeid}, text => $_->{name}, disabled => $_->{disabled}} } @themes,
    ) . "<br />";
    $ret .= $class->html_check(
        name => 'opt_forcemoodtheme',
        id => 'opt_forcemoodtheme',
        selected => $forcemoodtheme,
    );
    $ret .= "<label for='opt_forcemoodtheme'>" . $class->ml('widget.moodthemechooser.forcetheme') . "</label>";

    my $journalarg = $getextra ? "?journal=" . $u->user : "";
    $ret .= "<ul class='moodtheme-links nostyle'>";
    $ret .= "<li><a href='$LJ::SITEROOT/moodlist.bml$journalarg'>" . $class->ml('widget.moodthemechooser.links.allthemes') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/manage/moodthemes.bml$getextra'>" . $class->ml('widget.moodthemechooser.links.customthemes') . "</a></li>";
    $ret .= "</ul>";
    $ret .= "</div>";

    my $moodtheme_extra = LJ::run_hook("mood_theme_extra_content", $u, \@themes);
    my $show_special = $moodtheme_extra ? "special" : "nospecial";

    LJ::load_mood_theme($preview_moodthemeid);
    my @show_moods = ('happy', 'sad', 'angry', 'tired');

    if ($preview_moodthemeid) {
        my $count = 0;

        $ret .= "<div class='moodtheme-preview moodtheme-preview-$show_special'>";
        $ret .= "<table>";
        $ret .= "<tr>" unless $moodtheme_extra;
        foreach my $mood (@show_moods) {
            my %pic;
            if (LJ::get_mood_picture($preview_moodthemeid, LJ::mood_id($mood), \%pic)) {
                $ret .= "<tr>" if $moodtheme_extra && $count % 2 == 0;
                $ret .= "<td><img class='moodtheme-img' align='absmiddle' alt='$mood' src=\"$pic{pic}\" width='$pic{w}' height='$pic{h}' /><br />$mood</td>";
                $ret .= "</tr>" if $moodtheme_extra && $count % 2 != 0;
                $count++;
            }
        }
        if ($moodtheme_extra) {
            $ret .= "<tr><td colspan='2'>";
        } else {
            $ret .= "<td>";
        }
        $ret .= "<p><a href='$LJ::SITEROOT/moodlist.bml?moodtheme=$preview_moodthemeid'>" . $class->ml('widget.moodthemechooser.viewtheme') . "</a></p>";
        $ret .= "</td></tr></table>";
        $ret .= "</div>";
    }

    $ret .= $moodtheme_extra;

    $ret .= "</fieldset>" unless $u->prop('stylesys') == 2;

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    my ($given_moodthemeid, $given_forcemoodtheme);
    if ($post_fields_of_parent->{reset}) {
        $given_moodthemeid = 1;
        $given_forcemoodtheme = 0;
    } else {
        $given_moodthemeid = $post->{moodthemeid};
        $given_forcemoodtheme = $post->{opt_forcemoodtheme};
    }

    my %update;
    my $moodthemeid = LJ::Customize->validate_moodthemeid($u, $given_moodthemeid);
    $update{moodthemeid} = $moodthemeid;
    $update{opt_forcemoodtheme} = $given_forcemoodtheme ? "Y" : "N";

    # update 'user' table
    foreach (keys %update) {
        delete $update{$_} if $u->{$_} eq $update{$_};
    }
    LJ::update_user($u, \%update) if %update;

    # reload the user object to force the display of these changes
    $u = LJ::load_user($u->user, 'force');

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            DOM.addEventListener($('moodtheme_dropdown'), "change", function (evt) { self.previewMoodTheme(evt) });
        },
        previewMoodTheme: function (evt) {
            var opt_forcemoodtheme = 0;
            if ($('opt_forcemoodtheme').checked) opt_forcemoodtheme = 1;

            this.updateContent({
                preview_moodthemeid: $('moodtheme_dropdown').value,
                forcemoodtheme: opt_forcemoodtheme
            });
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
