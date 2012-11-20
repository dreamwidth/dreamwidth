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

package LJ::Widget::CustomTextModule;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub ajax { 1 }
sub authas { 1 }

sub render_body {
    my $class = shift;
    my $count = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $ret;

    # if userprops are blank, populate with S2 layer data instead
    my ($theme, @props, %prop_is_used, %module_custom_text_title, %module_custom_text_url,  %module_custom_text_content);
    if ($u->prop('stylesys') == 2) {
        $theme = LJ::Customize->get_current_theme($u);
        @props = S2::get_properties($theme->layoutid);
        %prop_is_used = map { $_ => 1 } @props;

        my $style = LJ::S2::load_style($u->prop('s2_style'));
        die "Style not found." unless $style && $style->{userid} == $u->id;

        %module_custom_text_title = LJ::Customize->get_s2_prop_values("text_module_customtext", $u, $style);
        %module_custom_text_url = LJ::Customize->get_s2_prop_values("text_module_customtext_url", $u, $style);
        %module_custom_text_content = LJ::Customize->get_s2_prop_values("text_module_customtext_content", $u, $style);

    }

    # fill text if it's totally empty.
    my $custom_text_title = $u->prop( 'customtext_title' ) ne ''
        ? $u->prop( 'customtext_title' )
        : "Custom Text";
    my $custom_text_url = $u->prop( 'customtext_url' ) || $module_custom_text_url{override};
    my $custom_text_content = $u->prop( 'customtext_content' ) || $module_custom_text_content{override};

    my $row_class = $count % 2 == 0 ? " even" : " odd";

    $ret .= "<tr class='prop-row ". $row_class ."' valign='top' width='100%'><td class='prop-header' valign='top'>" . $class->ml('widget.customtext.title') . "</td>"; #FIXME: needs new labels
    $ret .= "<td valign='top'>" . $class->html_text(
        name => "module_customtext_title",
        size => 20,
        value => $custom_text_title,
    ) . "</td></tr>";

    $count++;
    $row_class = $count % 2 == 0 ? " even" : " odd";

    $ret .= "<tr class='prop-row ". $row_class ."' valign='top' width='100%'><td class='prop-header' valign='top'>" . $class->ml('widget.customtext.url') . "</td>";
    $ret .= "<td valign='top'>" . $class->html_text(
        name => "module_customtext_url",
        size=> 20,
        value => $custom_text_url,
    ) . "</td></tr>";


    $count++;
    $row_class = $count % 2 == 0 ? " even" : " odd";

    $ret .= "<tr class='prop-row ". $row_class ."' valign='top' width='100%'><td class='prop-header' valign='top'>" . $class->ml('widget.customtext.content') . "<br />";
    $ret .= "<td valign='top'>" . $class->html_textarea(
        name => "module_customtext_content",
        rows => 10,
        cols => 50,
        wrap => 'soft',
        value => $custom_text_content,
    ) . "</td></tr>";
    $ret .= "</div>";
    warn "We've rendered the module!";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;
    warn "my post is ".$post;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);


    my %override;
    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    my ( $given_control_strip_color, $props );
    if ($post_fields_of_parent->{reset}) {
        warn "we're resetting!";
        $u->set_prop( 'customtext_title', "Custom Text" );
        $u->clear_prop( 'customtext_url' );
        $u->clear_prop( 'customtext_content' );

    } else {
        warn "we're not resetting!";
        warn LJ::D($post);
        $u->set_prop( 'customtext_title', $post->{module_customtext_title} );
        $u->set_prop( 'customtext_url', $post->{module_customtext_url} );
        $u->set_prop( 'customtext_content', $post->{module_customtext_content} );
    }

#    if ($u->prop('stylesys') == 2) {
#        my $style = LJ::S2::load_style($u->prop('s2_style'));
#        die "Style not found." unless $style && $style->{userid} == $u->id;
#        LJ::Customize->save_s2_props($u, $style, \%override);
#    }

    return;
}

sub should_render {
    my $class = shift;

    return 1;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            if (!$('control_strip_color_layout_default')) return;

            self.hideSubDivs();
            if ($('control_strip_color_layout_default').checked) this.showSubDiv("layout_default_subdiv");
            if ($('control_strip_color_custom').checked) this.showSubDiv("custom_subdiv");

            DOM.addEventListener($('control_strip_color_dark'), "click", function (evt) { self.hideSubDivs() });
            DOM.addEventListener($('control_strip_color_light'), "click", function (evt) { self.hideSubDivs() });
            DOM.addEventListener($('control_strip_color_layout_default'), "click", function (evt) { self.showSubDiv("layout_default_subdiv") });
            DOM.addEventListener($('control_strip_color_custom'), "click", function (evt) { self.showSubDiv("custom_subdiv") });
        },
        hideSubDivs: function () {
            $('layout_default_subdiv').style.display = "none";
            $('custom_subdiv').style.display = "none";
        },
        showSubDiv: function (div) {
            this.hideSubDivs();
            $(div).style.display = "block";
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
