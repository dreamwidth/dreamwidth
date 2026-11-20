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
use DateTime::TimeZone;
use DW::Request;
use LJ::Web;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_community ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "time_zone";
}

sub label {
    my $class = shift;

    return $class->ml('setting.timezone.label');
}

sub _submitted_timezone {
    my ( $class, $args ) = @_;
    return $args->{ $class->pkgkey . 'timezone' } // $args->{timezone};
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $timezone = $class->_submitted_timezone($args);
    if ( !defined $timezone || $timezone ne '' && !LJ::is_valid_timezone($timezone) ) {
        $timezone = $u ? $u->prop('timezone') : LJ::anonymous_timezone();
    }

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
            selected => $timezone // '',
        },
        @options
    );

    my $errdiv = $class->errdiv( $errs, "timezone" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->_submitted_timezone($args);

    $class->errors( timezone => $class->ml('setting.timezone.error.invalid') )
        if defined $val && $val ne '' && !LJ::is_valid_timezone($val);

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    my $val = $class->_submitted_timezone($args);
    return 1 unless defined $val;
    $class->error_check( $u, $args );

    if ($u) {
        $u->set_prop( timezone => $val );
    }
    else {
        my $r      = DW::Request->get;
        my %cookie = (
            name     => 'dw_timezone',
            domain   => ".$LJ::DOMAIN",
            path     => '/',
            httponly => 1,
            SameSite => 'Lax',
        );
        if ( $val eq '' ) {
            $r->delete_cookie(%cookie);
        }
        else {
            $r->add_cookie( %cookie, value => $val, expires => time() + 86400 * 365 * 10 );
        }
    }

    return 1;
}

1;
