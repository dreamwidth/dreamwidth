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

package LJ::Widget::LinksList;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub authas { 1 }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    return "" unless $u->prop('stylesys') == 2;

    my $post = $class->post_fields($opts{post});
    my $linkobj = LJ::Links::load_linkobj($u, "master");

    my $link_min = $opts{link_min} || 5; # how many do they start with ?
    my $link_more = $opts{link_more} || 5; # how many do they get when they click "more"
    my $order_step = $opts{order_step} || 10; # step order numbers by

# info about the links textareas

    my $ret .= "<fieldset><legend>" . $class->ml('widget.linkslist.title') . "</legend></fieldset>";

# title of this module

    $ret .= "<p class='detail'>" . $class->ml('widget.linkslist.about') . "</p>";

# explanation

    $ret .= "<table summary='' cellspacing='2' cellpadding='0'><tr valign='top'><td>";

    # how many link inputs to show?
    my $showlinks = $post->{numlinks} || @$linkobj;
    my $caplinks = $u->count_max_userlinks;
    $showlinks += $link_more if $post->{'action:morelinks'};
    $showlinks = $link_min if $showlinks < $link_min;
    $showlinks = $caplinks if $showlinks > $caplinks;

    $ret .= "<td><div class='highlight-box'><p class='tips-header'><strong>" . $class->ml('widget.linkslist.tips') . "</strong></p>";
    $ret .= "<ul><li>" . $class->ml('widget.linkslist.about.reorder') . "</li>";
    $ret .= "<li>" . $class->ml('widget.linkslist.about.blank') . "</li>";
    $ret .= "<li>" . $class->ml('widget.linkslist.about.heading') . "</li>";
    $ret .= "<li>" . $class->ml('widget.linkslist.about.hover') . "</li>";
    $ret .= "<li>" . $class->ml('widget.linkslist.about.hoverhead') .
    "</li></ul></div>";
    $ret .= "</td></tr></table>";


# add the table-ey stuff at the top

    $ret .= "<table border='0' cellspacing='5' cellpadding='0'>";
    $ret .= "<thead><tr><th>" . $class->ml('widget.linkslist.table.order') . "</th><th></th>";
    $ret .= "<th>" . $class->ml('widget.linkslist.table.title') . "</th><td>&nbsp;</td></tr></thead>";

# now we're building the textareas
# --- here would be the bit I am interested in ---

    foreach my $ct (1..$showlinks) {
        my $it = $linkobj->[$ct-1] || {};
        # so $linkobj is an array ref?
        # we get it from Links::load_linkobj so let's see what that does.

# builds the order number

        $ret .= "<tr><td>";
        $ret .= $class->html_text(
            name => "link_${ct}_ordernum",
            size => 4,
            value => $ct * $order_step,
        );
        $ret .= "</td>";

# the link itself

        $ret .= "<td>";
        $ret .= "<label>Link</label></td><td>";
        $ret .= $class->html_text(
            name => "link_${ct}_url",
            size => 50,
            maxlength => 255,
            value => $it->{url} || "http://",
        );

# the title of the link

        $ret .= "<tr><td></td><td>";
        $ret .= "<label>Link text</label></td><td>";
        $ret .= $class->html_text(
            name => "link_${ct}_title",
            size => 50,
            maxlength => 255,
            value => $it->{title},
        );
        $ret .= "</td>";

# so here's where we might insert some hover text

        $ret .= "<tr><td></td><td>";
        $ret .= "<label>Hover text<label></td><td>";
        $ret .= $class->html_text(
            name => "link_${ct}_hover",
            size => 50,
            maxlength => 255,
            value => $it->{hover},
        );
        $ret .= "</td><td>&nbsp;</td></tr>";

# --- and here is where the code I'm interested in stops ---

        # more button at the end of the last line, but only if
        # they are allowed more than the minimum
        $ret .= "<td>&nbsp;";
        if ($ct >= $showlinks && $caplinks > $link_min) {
            $ret .= $class->html_submit(
                'action:morelinks' => $class->ml('widget.linkslist.table.more') . " &rarr;",
                { 'disabled' => $ct >= $caplinks, 'noescape' => 1 }
            );
        }
        if ($ct >= $caplinks) {
            $ret .= "</td></tr><tr><td colspan='2'>&nbsp;</td><td>" . LJ::Lang::ml('cprod.links.text3.v1');
        }
        $ret .= "</td></tr>";

        # blank line unless this is the last line
        $ret .= "<tr><td colspan='3'>&nbsp;</td></tr>"
            unless $ct >= $showlinks;

    }

    $ret .= $class->html_hidden( numlinks => $showlinks );
    $ret .= "</table></td>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    return if $post->{'action:morelinks'}; # this is handled in render_body

    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    if ($post_fields_of_parent->{reset}) {
        foreach my $val (keys %$post) {
            next unless $val =~ /^link_\d+_title$/ || $val =~ /^link_\d+_url$/;

            $post->{$val} = "";
        }
    }

    my $linkobj = LJ::Links::make_linkobj_from_form($u, $post);
    LJ::Links::save_linkobj($u, $linkobj);

    return;
}

1;
