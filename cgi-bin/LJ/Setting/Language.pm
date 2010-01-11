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

package LJ::Setting::Language;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && $u->is_community ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "change_language";
}

sub label {
    my $class = shift;

    return $class->ml('setting.language.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $lang = $class->get_arg($args, "lang") || BML::get_language();
    my $lang_list = LJ::Lang::get_lang_names();

    my $ret = LJ::html_select({
        name => "${key}lang",
        selected => $lang,
    }, @$lang_list);

    my $errdiv = $class->errdiv($errs, "lang");
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "lang");

    $class->errors( lang => $class->ml('setting.language.error.invalid') )
        unless $val && grep { $val eq $_ } @{LJ::Lang::get_lang_names()};

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $val = $class->get_arg($args, "lang");
    LJ::Lang::set_lang($val);

    return 1;
}

1;
