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

package LJ::Setting::EntryEditor;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "entry_editor_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.entryeditor.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $editor = $class->get_arg( $args, "entryeditor" ) || $u->prop("entry_editor") || "";

    my $ret;
    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}entryeditor",
            id       => "${key}entryeditor_richtext",
            value    => "always_rich",
            selected => $editor eq "always_rich" ? 1 : 0,
        }
        )
        . "<label for='${key}entryeditor_richtext' class='radiotext'>"
        . $class->ml('setting.entryeditor.option.richtext')
        . "</label>";
    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}entryeditor",
            id       => "${key}entryeditor_plaintext",
            value    => "always_plain",
            selected => $editor eq "always_plain" ? 1 : 0,
        }
        )
        . "<label for='${key}entryeditor_plaintext' class='radiotext'>"
        . $class->ml('setting.entryeditor.option.plaintext')
        . "</label>";
    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}entryeditor",
            id       => "${key}entryeditor_lastused",
            value    => "L",
            selected => $editor ne "always_rich" && $editor ne "always_plain" ? 1 : 0,
        }
        )
        . "<label for='${key}entryeditor_lastused' class='radiotext'>"
        . $class->ml('setting.entryeditor.option.lastused')
        . "</label>";

    my $errdiv = $class->errdiv( $errs, "entryeditor" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "entryeditor" );

    $class->errors( entryeditor => $class->ml('setting.entryeditor.error.invalid') )
        unless $val =~ /^(L|always_rich|always_plain)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $editor = $class->get_arg( $args, "entryeditor" );

    # If they said last used, we really mean no setting at all
    $editor = undef if $editor eq "L";

    my $cur = $u->prop('entry_editor') || '';

    # No change needed if they selected last used and that is what is stored
    return 1 if !$editor && $cur =~ /^(rich|plain)$/;

    # No change needed if their "always" selection is the same
    return 1 if $editor && $editor eq $cur;

    # They made a change
    $u->set_prop( "entry_editor", $editor );

    return 1;
}

1;
