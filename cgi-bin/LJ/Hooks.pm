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

package LJ::Hooks;

use strict;
use LJ::ModuleLoader;

my $hooks_dir_scanned = 0;    # bool: if we've loaded everything from cgi-bin/LJ/Hooks/

# <LJFUNC>
# name: LJ::Hooks::are_hooks
# des: Returns true if the site has one or more hooks installed for
#      the given hookname.
# args: hookname
# </LJFUNC>
sub are_hooks {
    my $hookname = shift;
    _load_hooks_dir() unless $hooks_dir_scanned;
    return defined $LJ::HOOKS{$hookname};
}

# <LJFUNC>
# name: LJ::Hooks::run_hooks
# des: Runs all the site-specific hooks of the given name.
# returns: list of arrayrefs, one for each hook ran, their
#          contents being their own return values.
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hooks {
    my ( $hookname, @args ) = @_;
    _load_hooks_dir() unless $hooks_dir_scanned;

    my @ret;
    foreach my $hook ( @{ $LJ::HOOKS{$hookname} || [] } ) {
        push @ret, [ $hook->(@args) ];
    }
    return @ret;
}

# <LJFUNC>
# name: LJ::Hooks::run_hook
# des: Runs single site-specific hook of the given name.
# returns: return value from hook
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hook {
    my ( $hookname, @args ) = @_;
    _load_hooks_dir() unless $hooks_dir_scanned;

    return undef unless @{ $LJ::HOOKS{$hookname} || [] };
    return $LJ::HOOKS{$hookname}->[0]->(@args);
}

# <LJFUNC>
# name: LJ::register_hook
# des: Installs a site-specific hook.
# info: Installing multiple hooks per hookname is valid.
#       They're run later in the order they're registered.
# args: hookname, subref
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_hook {
    my ( $hookname, $subref ) = @_;
    push @{ $LJ::HOOKS{$hookname} ||= [] }, $subref;
}

# loads all of the hooks in the hooks directory
sub _load_hooks_dir {
    return if $hooks_dir_scanned++;

    # eh, not actually subclasses... just files named $class.pm
    # $a::$b ==> cgi-bin/$a/$b
    foreach my $class (
        LJ::ModuleLoader->module_subclasses("LJ::Hooks"),
        LJ::ModuleLoader->module_subclasses("DW::Hooks")
        )
    {
        eval "use $class;";
        die "Error loading $class: $@" if $@;
    }
}

# <LJFUNC>
# name: LJ::register_setter
# des: Installs code to run for the "set" command in the console.
# info: Setters can be general or site-specific.
# args: key, subref
# des-key: Key to set.
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_setter {
    my ( $key, $subref ) = @_;
    $LJ::SETTER{$key} = $subref;
}

1;
