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

package LJ::Setting::AdultContent;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return !LJ::is_enabled('adult_content') || !$u || $u->is_identity ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "adult_content_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.adultcontent.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $adultcontent = $class->get_arg( $args, "adultcontent" ) || $u->adult_content;

    my @options = (
        none     => $class->ml('setting.adultcontent.option.select.none'),
        concepts => $class->ml('setting.adultcontent.option.select.concepts'),
        explicit => $class->ml('setting.adultcontent.option.select.explicit'),
    );

    my $ret = "<label for='${key}adultcontent'>"
        . (
          $u->is_community
        ? $class->ml('setting.adultcontent.option.comm')
        : $class->ml('setting.adultcontent.option.self')
        ) . "</label> ";
    $ret .= LJ::html_select(
        {
            name     => "${key}adultcontent",
            id       => "${key}adultcontent",
            selected => $adultcontent,
        },
        @options
    );

    my $errdiv = $class->errdiv( $errs, "adultcontent" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "adultcontent" );

    $class->errors( adultcontent => $class->ml('setting.adultcontent.error.invalid') )
        unless $val =~ /^(none|concepts|explicit)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "adultcontent" );
    $u->set_prop( adult_content => $val );

    return 1;
}

1;
