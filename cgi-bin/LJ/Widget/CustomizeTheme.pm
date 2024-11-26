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

sub authas   { 1 }
sub need_res { qw( stc/widgets/customizetheme.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";

    my $headextra = $opts{headextra};
    my $group     = $opts{group} ? $opts{group} : "display";

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $nav_class = sub {
        my $g       = shift;
        my $classes = "";

        if ( $g eq $group ) {
            $classes .= " class='on";
            $classes .= "'";
        }

        return $classes;
    };

    my $propgroup_name = sub {
        my $prop = shift;
        return LJ::Customize->propgroup_name( $prop, $u, $style );
    };

    my %groups      = LJ::Customize->get_propgroups( $u, $style );
    my $group_names = $groups{groups};
    my %has_group   = map { $_ => 1 } @$group_names;

    my $vars = {
        style          => $style,
        u              => $u,
        groups         => \%groups,
        has_group      => \%has_group,
        propgroup_name => $propgroup_name,
        nav_class      => $nav_class,
        group_names    => $group_names,
        group          => $group,
    };

    # Display Group
    if ( $group eq "display" ) {
        my $mood_theme_chooser = LJ::Widget::MoodThemeChooser->new;
        $$headextra .= $mood_theme_chooser->wrapped_js( page_js_obj => "Customize" );

        my $nav_strip_chooser = LJ::Widget::NavStripChooser->new;
        $$headextra .= $nav_strip_chooser->wrapped_js( page_js_obj => "Customize" );

        $vars->{mood_theme_chooser} = $mood_theme_chooser->render;
        $vars->{nav_strip_chooser}  = $nav_strip_chooser->render;
    }

    # Presentation Group
    elsif ( $group eq "presentation" ) {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} = $s2_propgroup->render(
            props             => $groups{props},
            propgroup         => "presentation",
            groupprops        => $groups{groupprops}->{presentation},
            show_lang_chooser => 0,
        );
    }

    # Colors Group
    elsif ( $group eq "colors" ) {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} = $s2_propgroup->render(
            props      => $groups{props},
            propgroup  => "colors",
            groupprops => $groups{groupprops}->{colors},
        );
    }

    # Fonts Group
    elsif ( $group eq "fonts" ) {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} = $s2_propgroup->render(
            props      => $groups{props},
            propgroup  => "fonts",
            groupprops => $groups{groupprops}->{fonts},
        );

    }

    # Images Group
    elsif ( $group eq "images" ) {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} .= $s2_propgroup->render(
            props      => $groups{props},
            propgroup  => "images",
            groupprops => $groups{groupprops}->{images},
        );
    }

    # Text Group
    elsif ( $group eq "text" ) {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} = $s2_propgroup->render(
            props      => $groups{props},
            propgroup  => "text",
            groupprops => $groups{groupprops}->{text},
        );
    }

    # Links List Group
    elsif ( $group eq "linkslist" ) {
        $vars->{linkslist} = LJ::Widget::LinksList->render( post => $opts{post} );
    }

    # Custom CSS Group
    elsif ( $group eq "customcss" ) {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} = $s2_propgroup->render(
            props      => $groups{props},
            propgroup  => "customcss",
            groupprops => $groups{groupprops}->{customcss},
        );
    }

    # Other Groups
    else {
        my $s2_propgroup = LJ::Widget::S2PropGroup->new;
        $$headextra .= $s2_propgroup->wrapped_js( page_js_obj => "Customize" );

        $vars->{s2_propgroup} = $s2_propgroup->render(
            props      => $groups{props},
            propgroup  => $group,
            groupprops => $groups{groupprops}->{$group},
        );
    }

    return DW::Template->template_string( 'widget/customizetheme.tt', $vars );
}

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
