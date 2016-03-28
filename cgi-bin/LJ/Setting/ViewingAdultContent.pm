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

package LJ::Setting::ViewingAdultContent;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return !LJ::is_enabled( 'adult_content' ) || !$u || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "adult_content_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.viewingadultcontent.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $viewingadultcontent = $class->get_arg($args, "viewingadultcontent") || $u->hide_adult_content;

    my @options = (
        {
            value => "none",
            text => $class->ml('setting.viewingadultcontent.option.select.none'),
            disabled => $u->is_minor || ! $u->best_guess_age ? 1 : 0,
        },
        {
            value => "explicit",
            text => $class->ml('setting.viewingadultcontent.option.select.explicit'),
            disabled => ! $u->best_guess_age ? 1 : 0,
        },
        {
            value => "concepts",
            text => $class->ml('setting.viewingadultcontent.option.select.concepts'),
            disabled => 0,
        },
    );

    my $ret = "<label for='${key}viewingadultcontent'>" . $class->ml('setting.viewingadultcontent.option') . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}viewingadultcontent",
        id => "${key}viewingadultcontent",
        selected => $viewingadultcontent,
    }, @options);

    if ( ! $u->best_guess_age ) {
        $ret .= "<br /><span style='font-size: smaller;'> " . LJ::Lang::ml( 'setting.viewingadultcontent.reason', { aopts => "href='$LJ::SITEROOT/manage/profile/'" } ) . "</span>";

    }

    my $errdiv = $class->errdiv($errs, "viewingadultcontent");
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "viewingadultcontent");

    $class->errors( viewingadultcontent => $class->ml('setting.viewingadultcontent.error.invalid') )
        unless $val =~ /^(none|explicit|concepts)$/;

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $val = $class->get_arg($args, "viewingadultcontent");

    if (!$u->best_guess_age) {
        $val = "concepts";
    } elsif ($u->is_minor) {
        $val = "explicit" unless $val eq "concepts";
    }

    $u->set_prop( hide_adult_content => $val );

    return 1;
}

1;
