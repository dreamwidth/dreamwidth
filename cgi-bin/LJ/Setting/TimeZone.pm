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

package LJ::Setting::TimeZone;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return !$u || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "time_zone";
}

sub label {
    my $class = shift;

    return $class->ml('setting.timezone.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $timezone = $class->get_arg( $args, "timezone" ) || $u->prop("timezone");

    my $map   = DateTime::TimeZone::links();
    my $usmap = { map { $_ => $map->{$_} } grep { m!^US/! && $_ ne "US/Pacific-New" } keys %$map };
    my $camap = { map { $_ => $map->{$_} } grep { m!^Canada/! } keys %$map };

    my @options = ( "", $class->ml('setting.timezone.option.select') );
    push @options, ( map { $usmap->{$_}, $_ } sort keys %$usmap ),
        ( map            { $camap->{$_}, $_ } sort keys %$camap ),
        ( map { $_, $_ } DateTime::TimeZone::all_names() );

    my $ret = LJ::html_select(
        {
            name     => "${key}timezone",
            selected => $timezone,
        },
        @options
    );

    my $errdiv = $class->errdiv( $errs, "timezone" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "timezone" );

    $class->errors( timezone => $class->ml('setting.timezone.error.invalid') )
        unless !$val || grep { $val eq $_ } DateTime::TimeZone::all_names();

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "timezone" );
    $u->set_prop( timezone => $val );

    return 1;
}

1;
