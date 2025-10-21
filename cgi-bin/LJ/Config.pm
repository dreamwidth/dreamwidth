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
#
# this is a module to handle the configuration of a LJ server
package LJ::Config;

use strict;
use warnings;

$LJ::HOME ||= $ENV{LJHOME};
$LJ::CONFIG_LOADED        = 0;
$LJ::CACHE_CONFIG_MODTIME = 0;

# what files to check for config, ORDER MATTERS, please go from most specific
# to least specific.  files later in the chain should be careful to not clobber
# anything.
@LJ::CONFIG_FILES = $LJ::_T_CONFIG
    ? (
    (
        map { LJ::resolve_file($_) }
            qw(
            t/config-test-private.pl
            t/config-test.pl
            )
    ),
    (
        map { $LJ::HOME . "/" . $_ }
            qw(
            cgi-bin/LJ/Global/Defaults.pm
            )
    )
    )
    : (
    (
        map { LJ::resolve_file($_) }
            qw(
            etc/config-private.pl
            etc/config-local.pl
            etc/config.pl
            )
    ),
    (
        map { $LJ::HOME . "/" . $_ }
            qw(
            cgi-bin/LJ/Global/Defaults.pm
            )
    )
    );

# loads all configurations from scratch
sub load {
    my $class = shift;
    my %opts  = @_;
    return if !$opts{force} && $LJ::CONFIG_LOADED;

    __PACKAGE__->load_config;

    $LJ::CONFIG_LOADED = 1;
}

sub reload {
    __PACKAGE__->load( force => 1 );

    eval {
        # these need to be loaded after ljconfig
        #
        $LJ::DBIRole->set_sources( \%LJ::DBINFO );
        LJ::MemCache::reload_conf();
    };

    warn "Errors reloading config: $@" if $@;
}

# load configuration files
sub load_config {
    foreach my $fn (@LJ::CONFIG_FILES) {
        do $fn
            if -e $fn;
    }
    $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = time();
}

# handle reloading at the start of a new web request
sub start_request_reload {

    # check the modtime of etc/config.pl and reload if necessary
    # only do a stat every 10 seconds and then only reload
    # if the file has changed
    my $now = time();
    if ( $now - $LJ::CACHE_CONFIG_MODTIME_LASTCHECK > 10 ) {

        my $modtime;
        foreach my $fn (@LJ::CONFIG_FILES) {
            next unless -e $fn;
            my $cmodtime = ( stat($fn) )[9];
            $modtime = $cmodtime
                if !defined $modtime || $modtime < $cmodtime;
        }

        if ( !$LJ::CACHE_CONFIG_MODTIME || $modtime > $LJ::CACHE_CONFIG_MODTIME ) {

            # reload config and update cached modtime
            $LJ::CACHE_CONFIG_MODTIME = $modtime;
            __PACKAGE__->reload;
            $LJ::DEBUG_HOOK{'pre_save_bak_stats'}->() if $LJ::DEBUG_HOOK{'pre_save_bak_stats'};

            # save a backup of the original config value
            %LJ::_ORIG_CONFIG = ();
            $LJ::_ORIG_CONFIG{$_} = ${ $LJ::{$_} }
                foreach qw(IMGPREFIX JSPREFIX STATPREFIX WSTATPREFIX USERPIC_ROOT SITEROOT);

            $LJ::LOCKER_OBJ = undef;

            if ( $modtime > $now - 60 ) {

                # show to stderr current reloads.  won't show
                # reloads happening from new apache children
                # forking off the parent who got the inital config loaded
                # hours/days ago and then the "updated" config which is
                # a different hours/days ago.
                #
                # only print when we're in web-context
                print STDERR "[$$] Configuration file(s) reloaded.\n"
                    if eval { BML::get_request() };
            }
        }

        $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = $now;
    }
}

1;
