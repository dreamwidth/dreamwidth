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

package LJ::Setting::SafeSearch;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return
           !LJ::is_enabled('adult_content')
        || !LJ::is_enabled('safe_search')
        || !$u
        || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "adult_content_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.safesearch.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $safesearch = $class->get_arg( $args, "safesearch" ) || $u->safe_search;

    my @options = (
        none => $class->ml('setting.safesearch.option.select.none'),
        10   => $class->ml('setting.safesearch.option.select.explicit'),
        20   => $class->ml('setting.safesearch.option.select.concepts'),
    );

    my $ret = LJ::html_select(
        {
            name     => "${key}safesearch",
            selected => $safesearch,
        },
        @options
    );

    my $errdiv = $class->errdiv( $errs, "safesearch" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "safesearch" );

    $class->errors( safesearch => $class->ml('setting.safesearch.error.invalid') )
        unless $val eq "none" || $val =~ /^\d+$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "safesearch" );
    $u->set_prop( safe_search => $val );

    return 1;
}

1;
