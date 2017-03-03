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

package LJ::Setting::BoolSetting;
use base 'LJ::Setting';
use strict;
use warnings;
use Carp qw(croak);

# if override to something non-undef, current_value and save_text work
# assuming a userprop vs. user field.
sub prop_name { undef }
sub user_field { undef }

# must override these with values you want checked/unchecked to be
sub checked_value { croak }
sub unchecked_value { croak }

sub current_value {
    my ($class, $u) = @_;
    if (my $propname = $class->prop_name) {
        return $u->prop($propname);
    } elsif (my $field = $class->user_field) {
        return $u->{$field};
    }
    croak;
}

sub is_selected {
    my ($class, $u) = @_;
    my $current_value = $class->current_value($u);
    my $checked_value = $class->checked_value // '';
    return 0 unless defined( $current_value );
    return $current_value eq $checked_value;
}

sub label { croak; }

sub des { "" }

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    my $html =
        LJ::html_check({
            name     => "${key}val",
            value    => 1,
            id       => "${key}check",
            selected => $class->is_selected($u),
        }) . " <label for='${key}check'>";
    $html .=  $class->des || $class->label;
    $html .= "</label>";

    return $html;
}

sub save {
    my ($class, $u, $args) = @_;
    my $new_val = $args->{val} ? $class->checked_value : $class->unchecked_value;
    $new_val //= '';
    my $current_value = $class->current_value( $u );
    return 1 if (defined $current_value and $new_val eq $current_value);
    if (my $prop = $class->prop_name) {
        return $u->set_prop($prop, $new_val);
    } elsif (my $field = $class->user_field) {
        return $u->update_self( { $field => $new_val } );
    }
    croak "No prop_name or user_field set";
}

1;
