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

package LJ;

use strict;
use LJ::Hooks;

LJ::Hooks::register_setter(
    'synlevel',
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ /^(title|cut|summary|full)$/ ) {
            $$err = "Illegal value.  Must be 'title', 'cut', 'summary', or 'full'";
            return 0;
        }

        $u->set_prop( "opt_synlevel", $value );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "newpost_minsecurity",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ /^(public|access|members|private|friends)$/ ) {
            $$err =
"Illegal value.  Must be 'public', 'access' (for personal journals), 'members' (for communities), or 'private'";
            return 0;
        }

        # Don't let commmunities be access-locked
        if ( $u->is_community ) {
            if ( $value eq "access" ) {
                $$err =
"newpost_minsecurity cannot be access-locked for communities (use 'members' instead)";
                return 0;
            }
        }
        if ( $u->is_individual && $value eq "members" ) {
            $$err =
"newpost_minsecurity members not applicable to non-community journals. (use 'access' instead)";
            return 0;
        }

        $value = ""        if $value eq "public";
        $value = "friends" if $value eq "access" || $value eq "members";

        $u->set_prop( "newpost_minsecurity", $value );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "maximagesize",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ m/^(\d+)[x,|](\d+)$/ ) {
            $$err = "Illegal value.  Must be width,height.";
            return 0;
        }
        $value = "$1|$2";
        $u->set_prop( "opt_imagelinks", $value );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "opt_cut_disable_journal",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ /^(0|1)$/ ) {
            $$err = "Illegal value. Must be '0' or '1'";
            return 0;
        }
        $u->set_prop( "opt_cut_disable_journal", $value );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "opt_cut_disable_reading",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ /^(0|1)$/ ) {
            $$err = "Illegal value. Must be '0' or '1'";
            return 0;
        }
        $u->set_prop( "opt_cut_disable_reading", $value );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "disable_quickreply",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ /^(0|1)$/ ) {
            $$err = "Illegal value. Must be '0' or '1'";
            return 0;
        }
        $u->set_prop( "opt_no_quickreply", $value );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "icbm",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        my $loc = eval { LJ::Location->new( coords => $value ); };
        unless ($loc) {
            $u->set_prop( "icbm", "" );    # unset
            $$err = "Illegal value.  Not a recognized format." if $value;
            return 0;
        }
        $u->set_prop( "icbm", $loc->as_posneg_comma );
        return 1;
    }
);

LJ::Hooks::register_setter(
    "no_mail_alias",
    sub {
        my ( $u, $key, $value, $err ) = @_;

        unless ( $value =~ /^[01]$/ ) {
            $$err = "Illegal value.  Must be '0' or '1'.";
            return 0;
        }

        $u->set_prop( "no_mail_alias", $value );
        $value ? $u->delete_email_alias : $u->update_email_alias;

        return 1;
    }
);

LJ::Hooks::register_setter(
    "latest_optout",
    sub {
        my ( $u, $key, $value, $err ) = @_;
        unless ( $value =~ /^(?:yes|no)$/i ) {
            $$err = "Illegal value.  Must be 'yes' or 'no'.";
            return 0;
        }
        $value = lc $value eq 'yes' ? 1 : 0;
        $u->set_prop( "latest_optout", $value );
        return 1;
    }
);

1;
