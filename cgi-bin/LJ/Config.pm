# this is a module to handle the configuration of a LJ server
package LJ::Config;

use strict;
use warnings;

$LJ::CONFIG_LOADED = 0;
$LJ::CACHE_CONFIG_MODTIME = 0;

# loads all configurations from scratch
sub load {
    my $class = shift;
    my %opts = @_;
    return if ! $opts{force} && $LJ::CONFIG_LOADED;

    # 1. Load ljconfig
    # 2. Load policy configs
    # 3. Load database-backed config overrides
    # 4. Load ljoverrides.pl
    # 5. Load ljdefaults.pl (designed to not clobber stuff)

    __PACKAGE__->load_ljconfig;
    __PACKAGE__->load_policy;
    __PACKAGE__->load_overrides;
    __PACKAGE__->load_defaults;

    $LJ::CONFIG_LOADED = 1;
}

sub reload {
    __PACKAGE__->load( force => 1 );

    eval {
        # these need to be loaded after ljconfig
        #
        $LJ::DBIRole->set_sources(\%LJ::DBINFO);
        LJ::MemCache::reload_conf();
        LJ::ExternalSite->forget_site_objs;
        LJ::EventLogSink->forget_sink_objs;
        LJ::AccessLogSink->forget_sink_objs;

        # reload MogileFS config
        if (LJ::mogclient()) {
            LJ::mogclient()->reload
                ( domain => $LJ::MOGILEFS_CONFIG{domain},
                  root   => $LJ::MOGILEFS_CONFIG{root},
                  hosts  => $LJ::MOGILEFS_CONFIG{hosts},
                  readonly => $LJ::DISABLE_MEDIA_UPLOADS, );
              LJ::mogclient()->set_pref_ip(\%LJ::MOGILEFS_PREF_IP)
                  if %LJ::MOGILEFS_PREF_IP;
          }
    };

    warn "Errors reloading config: $@" if $@;
}

# load user-supplied config changes
sub load_ljconfig {
    do "$ENV{'LJHOME'}/etc/ljconfig.pl";
    $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = time();
}

# load defaults (should not clobber any existing configs)
sub load_defaults {
    do "$ENV{'LJHOME'}/cgi-bin/ljdefaults.pl";
}

# loads policy configuration
sub load_policy {
    my $policyconfig = "$ENV{LJHOME}/etc/policyconfig.pl";
    return unless -e $policyconfig;
    do "$policyconfig";
}

# load config overrides
sub load_overrides {
    if (-e "$ENV{LJHOME}/cgi-bin/ljconfig.pl") {
        warn "You are still using cgi-bin/ljconfig.pl. This has been deprecated, please use etc/ljconfig.pl and etc/ljoverrides.pl instead.";

        # but ignore ljconfig if both exist.
        unless (-e "$ENV{LJHOME}/etc/ljconfig.pl") {
            do "$ENV{LJHOME}/cgi-bin/ljconfig.pl";
        }
    }

    my $overrides = "$ENV{LJHOME}/etc/ljoverrides.pl";
    return unless -e $overrides;
    do $overrides;
}

# handle reloading at the start of a new web request
sub start_request_reload {
    # check the modtime of ljconfig.pl and reload if necessary
    # only do a stat every 10 seconds and then only reload
    # if the file has changed
    my $now = time();
    if ($now - $LJ::CACHE_CONFIG_MODTIME_LASTCHECK > 10) {
        my $modtime = (stat("$ENV{'LJHOME'}/etc/ljconfig.pl"))[9]
            || (stat("$ENV{'LJHOME'}/cgi-bin/ljconfig.pl"))[9];
        if (!$LJ::CACHE_CONFIG_MODTIME || $modtime > $LJ::CACHE_CONFIG_MODTIME) {
            # reload config and update cached modtime
            $LJ::CACHE_CONFIG_MODTIME = $modtime;
            __PACKAGE__->reload;
            $LJ::DEBUG_HOOK{'pre_save_bak_stats'}->() if $LJ::DEBUG_HOOK{'pre_save_bak_stats'};

            $LJ::IMGPREFIX_BAK = $LJ::IMGPREFIX;
            $LJ::STATPREFIX_BAK = $LJ::STATPREFIX;
            $LJ::USERPICROOT_BAK = $LJ::USERPIC_ROOT;

            $LJ::LOCKER_OBJ = undef;
            if ($modtime > $now - 60) {
                # show to stderr current reloads.  won't show
                # reloads happening from new apache children
                # forking off the parent who got the inital config loaded
                # hours/days ago and then the "updated" config which is
                # a different hours/days ago.
                #
                # only print when we're in web-context
                print STDERR "[$$] ljconfig.pl reloaded\n"
                    if eval { Apache->request };
            }
        }
        $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = $now;
    }
}

1;
