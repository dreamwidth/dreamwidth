package LJ::Widget::LinksList;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub authas { 1 }
sub need_res { qw( stc/widgets/linkslist.css ) }

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

    my $ret .= "<fieldset><legend>" . $class->ml('widget.linkslist.title') . "</legend></fieldset>";

    $ret .= "<p class='detail'>" . $class->ml('widget.linkslist.about') . "</p>";

    $ret .= "<table cellspacing='2' cellpadding='0'><tr valign='top'><td>";

    # how many link inputs to show?
    my $showlinks = $post->{numlinks} || @$linkobj;
    my $caplinks = $u->get_cap("userlinks");
    $showlinks += $link_more if $post->{'action:morelinks'};
    $showlinks = $link_min if $showlinks < $link_min;
    $showlinks = $caplinks if $showlinks > $caplinks;

    $ret .= "<table border='0' cellspacing='5' cellpadding='0'>";
    $ret .= "<tr><th>" . $class->ml('widget.linkslist.table.order') . "</th>";
    $ret .= "<th>" . $class->ml('widget.linkslist.table.title') . "</th><td>&nbsp;</td></tr>";

    foreach my $ct (1..$showlinks) {
        my $it = $linkobj->[$ct-1] || {};

        $ret .= "<tr><td>";
        $ret .= $class->html_text(
            name => "link_${ct}_ordernum",
            size => 4,
            value => $ct * $order_step,
        );
        $ret .= "</td><td>";

        $ret .= $class->html_text(
            name => "link_${ct}_title",
            size => 50,
            maxlength => 255,
            value => $it->{title},
        );
        $ret .= "</td><td>&nbsp;</td></tr>";

        $ret .= "<tr><td>&nbsp;</td><td>";
        $ret .= $class->html_text(
            name => "link_${ct}_url",
            size => 50,
            maxlength => 255,
            value => $it->{url} || "http://",
        );

        # more button at the end of the last line, but only if
        # they are allowed more than the minimum
        $ret .= "<td>&nbsp;";
        if ($ct >= $showlinks && $caplinks > $link_min) {
            $ret .= $class->html_submit(
                'action:morelinks' => $class->ml('widget.linkslist.table.more') . " &rarr;",
                { 'disabled' => $ct >= $caplinks, 'noescape' => 1 }
            );
        }
        my $inline;
        if ($ct >= $caplinks) {
            if ($inline .= LJ::run_hook("cprod_inline", $u, 'Links')) {
                $ret .= $inline;
            } else {
                $ret .= "</td></tr><tr><td colspan='2'>&nbsp;</td><td>" . LJ::Lang::ml('cprod.links.text3.v1');
            }
        }
        $ret .= "</td></tr>";

        # blank line unless this is the last line
        $ret .= "<tr><td colspan='3'>&nbsp;</td></tr>"
            unless $ct >= $showlinks;

    }

    $ret .= $class->html_hidden( numlinks => $showlinks );
    $ret .= "</table></td>";

    $ret .= "<td><div class='tips-box'><p class='tips-header'><strong>" . $class->ml('widget.linkslist.tips') . "</strong></p>";
    $ret .= "<ul class='detail'><li>" . $class->ml('widget.linkslist.about.reorder') . "</li>";
    $ret .= "<li>" . $class->ml('widget.linkslist.about.blank') . "</li>";
    $ret .= "<li>" . $class->ml('widget.linkslist.about.heading') . "</li></ul></div>";
    $ret .= "</td></tr></table>";

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
