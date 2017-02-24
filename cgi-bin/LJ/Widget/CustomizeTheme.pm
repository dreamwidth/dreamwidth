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

package LJ::Widget::CustomizeTheme;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub authas { 1 }
sub need_res { qw( stc/widgets/customizetheme.css ) }

=head2 C<< $class->nav_link( $u, $remote, $label, $group ) >>

Internal.  Given a user class, who the remote is, the label for the navigation link,
and the group it belongs to, return a customize-nav-group link suitable for use
in the side navigation on the customize options page.

=cut

sub nav_link {
    my ( $class, $u, $remote, $label, $group ) = @_;

    my $opts;
    $opts->{keep_args} = [ 's2id' ];
    push $opts->{keep_args}, 'authas' if ( $u->userid != $remote->userid );
    $opts->{args}->{group} = $group;

    return '<a class="customize-nav-group" href="' . LJ::create_url( "/customize/options",
        %$opts ) . '">' . $label . '</a>';
}

=head2 C<< $class->render_body( $opts ) >>

Renders the body of this widget.  Options are:

* headextra
* group -- if none given, defaults to "presentation"
* style -- id number of a specific style being customized, if not the user's default

=cut

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote = LJ::get_remote();

    my $headextra = $opts{headextra};
    my $group = $opts{group} ? $opts{group} : "presentation";

    my $styleid = $opts{styleid} =~ /[0-9]+/ ? $opts{styleid} : $u->prop( 's2_style' );
    my $style = LJ::S2::load_style( $styleid );

    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $ret;

    # want to give some indication that they are not editing their applied style
    if ( $u->prop( 's2_style' ) != $styleid ) {
        my $journalbase = $u->journal_base;
        $ret .= "<div class='highlight-box'><p>";
        $ret .= $class->ml('widget.customizetheme.customstyle', {
            'name' => LJ::ehtml( $style->{name} ),
            'aopts' => "href='$journalbase/?s2id=$styleid'", 'id' => $styleid } );
        $ret .= "</p></div>";
    }

    $ret .= "<h2 class='widget-header'>" . $class->ml( 'widget.customizetheme.title' ) . "</h2>";

    $ret .= $class->start_form( id => "customize-form" );

    $ret .= "<div class='customize-inner-wrapper section-nav-inner-wrapper'>";
    $ret .= "<div class='customize-nav section-nav'>";

    my $nav_class = sub {
        my $g = shift;
        my $classes = "";

        if ($g eq $group) {
            $classes .= " class='on";
            $classes .= "'";
        }

        return $classes;
    };

    my %groups = LJ::Customize->get_propgroups($u, $style);
    my $group_names = $groups{groups};
    my %has_group = map { $_ => 1 } @$group_names;

    ### Navigation ###

    $ret .= "<ul class='customize-nav nostyle' id='customize_theme_nav_links'>";
    $ret .= "<li" . $nav_class->( "display" ) . ">" . $class->nav_link( $u, $remote, $class->ml( 'widget.customizetheme.nav.display' ), "display" );
    $ret .= "</li>";

    foreach my $g ( @$group_names ) {
        next if $g eq "customcss";

        my $name = LJ::Customize->propgroup_name( $g, $u, $style );
        $ret .= "<li" . $nav_class->( $g ) . ">" . $class->nav_link( $u, $remote, $name, $g ) . "</li>";
    }

    $ret .= "<li" . $nav_class->( "linkslist" ) . ">" . $class->nav_link( $u, $remote, $class->ml( 'widget.customizetheme.nav.linkslist' ), 'linkslist' )
        . "</li>";

    if ( $has_group{customcss} ) {
        my $name = LJ::Customize->propgroup_name( "customcss", $u, $style );
        $ret .= "<li" . $nav_class->( "customcss" ) . ">" . $class->nav_link( $u, $remote, $name, 'customcss' ) . "</li>";
    }

    $ret .= "</ul>";
    $ret .= "</div>";


    ### Content ###

    $ret .= "<div class='customize-content section-nav-content'>";

    # Display Group
    if ($group eq "display") {
        $ret .= "<div id='display-group' class='customize-group'>";

        my $mood_theme_chooser = LJ::Widget::MoodThemeChooser->new;
        $$headextra .= $mood_theme_chooser->wrapped_js( page_js_obj => "Customize" );

        my $nav_strip_chooser = LJ::Widget::NavStripChooser->new;
        $$headextra .= $nav_strip_chooser->wrapped_js( page_js_obj => "Customize" );

        $ret .= "<div class='pkg'>";
        $ret .= $mood_theme_chooser->render;
        $ret .= "</div>";

        $ret .= "<div class='pkg'>";
        $ret .= $nav_strip_chooser->render;
        $ret .= "</div>";

        $ret .= "</div>";
    }

    # Presentation Group
    elsif ($group eq "presentation") {
        $ret .= "<div id='presentation-group' class='customize-group'>";

        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= "<div class='pkg'>";
        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => "presentation",
            groupprops => $groups{groupprops}->{presentation},
            show_lang_chooser => 0,
            styleid => $styleid,
        );
        $ret .= "</div>";

        $ret .= "</div>";
    }

    # Colors Group
    elsif ($group eq "colors") {
        $ret .= "<div id='colors-group' class='customize-group'>";

        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => "colors",
            groupprops => $groups{groupprops}->{colors},
            styleid => $styleid,
        );

        $ret .= "</div>";
    }

    # Fonts Group
    elsif ($group eq "fonts") {
        $ret .= "<div id='fonts-group' class='customize-group'>";

        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => "fonts",
            groupprops => $groups{groupprops}->{fonts},
            styleid => $styleid,
        );

        $ret .= "</div>";
    }

    # Images Group
    elsif ($group eq "images") {
        $ret .= "<div id='images-group' class='customize-group'>";

        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => "images",
            groupprops => $groups{groupprops}->{images},
            styleid => $styleid,
        );

        $ret .= "</div>";
    }

    # Text Group
    elsif ($group eq "text") {
        $ret .= "<div id='text-group' class='customize-group'>";

        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => "text",
            groupprops => $groups{groupprops}->{text},
        );

        $ret .= "</div>";
    }

    # Links List Group
    elsif ($group eq "linkslist") {
        $ret .= "<div id='linkslist-group' class='customize-group'>";
        $ret .= LJ::Widget::LinksList->render( post => $opts{post} );
        $ret .= "</div>";
    }

    # Custom CSS Group
    elsif ($group eq "customcss") {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= "<div id='customcss-group' class='customize-group pkg'>";
        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => "customcss",
            groupprops => $groups{groupprops}->{customcss},
            styleid => $styleid,
        );
        $ret .= "</div>";
    }

    # Other Groups
    else {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $ret .= "<div id='$group-group' class='customize-group pkg'>";
        $ret .= $s2_propgroup->render(
            props => $groups{props},
            propgroup => $group,
            groupprops => $groups{groupprops}->{$group},
            styleid => $styleid,
        );
        $ret .= "</div>";
    }

    $ret .= "<div class='customize-buttons action-bar'>";
    $ret .= $class->html_submit( save => $class->ml('widget.customizetheme.btn.save'), { raw => "class='customize-button'" } ) . " ";
    $ret .= $class->html_submit( reset => $class->ml('widget.customizetheme.btn.reset'), { raw => "class='customize-button' id='reset_btn_bottom'" } );
    $ret .= "</div>";

    $ret .= "</div><!-- end .customize-content -->";
    $ret .= "</div><!-- end .customize-inner-wrapper -->";

    $ret .= $class->end_form;

    return $ret;
}


=head2 C<< $class->render_body( $opts ) >>

Returns the JavaScript code for this widget.

=cut

sub js {
    q [
        initWidget: function () {
            var self = this;

            // confirmation when reseting the form
            DOM.addEventListener($('reset_btn_top'), "click", function (evt) { self.confirmReset(evt) });
            DOM.addEventListener($('reset_btn_bottom'), "click", function (evt) { self.confirmReset(evt) });

            self.form_changed = false;

            // capture onclicks on the nav links to confirm form saving
            var links = $('customize_theme_nav_links').getElementsByTagName('a');
            for (var i = 0; i < links.length; i++) {
                if (links[i].href != "") {
                    DOM.addEventListener(links[i], "click", function (evt) { self.navclick_save(evt) })
                }
            }

            // register all form changes to confirm them later
            var selects = $('customize-form').getElementsByTagName('select');
            for (var i = 0; i < selects.length; i++) {
                DOM.addEventListener(selects[i], "change", function (evt) { self.form_change() });
            }
            var inputs = $('customize-form').getElementsByTagName('input');
            for (var i = 0; i < inputs.length; i++) {
                DOM.addEventListener(inputs[i], "change", function (evt) { self.form_change() });
            }
            var textareas = $('customize-form').getElementsByTagName('textarea');
            for (var i = 0; i < textareas.length; i++) {
                DOM.addEventListener(textareas[i], "change", function (evt) { self.form_change() });
            }
        },
        confirmReset: function (evt) {
            if (! confirm("Are you sure you want to reset all changes on this page to their defaults?")) {
                Event.stop(evt);
            }
        },
        navclick_save: function (evt) {
            var confirmed = false;
            if (this.form_changed == false) {
                return true;
            } else {
                confirmed = confirm("Save your changes?");
            }

            if (confirmed) {
                $('customize-form').submit();
            }
        },
        form_change: function () {
            if (this.form_changed == true) { return; }
            this.form_changed = true;
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
