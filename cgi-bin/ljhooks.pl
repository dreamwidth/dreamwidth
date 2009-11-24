package LJ;
use strict;
use LJ::ModuleLoader;

my $hooks_dir_scanned = 0;  # bool: if we've loaded everything from cgi-bin/LJ/Hooks/

# <LJFUNC>
# name: LJ::are_hooks
# des: Returns true if the site has one or more hooks installed for
#      the given hookname.
# args: hookname
# </LJFUNC>
sub are_hooks
{
    my $hookname = shift;
    load_hooks_dir() unless $hooks_dir_scanned;
    return defined $LJ::HOOKS{$hookname};
}

# <LJFUNC>
# name: LJ::run_hooks
# des: Runs all the site-specific hooks of the given name.
# returns: list of arrayrefs, one for each hook ran, their
#          contents being their own return values.
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hooks
{
    my ($hookname, @args) = @_;
    load_hooks_dir() unless $hooks_dir_scanned;

    my @ret;
    foreach my $hook (@{$LJ::HOOKS{$hookname} || []}) {
        push @ret, [ $hook->(@args) ];
    }
    return @ret;
}

# <LJFUNC>
# name: LJ::run_hook
# des: Runs single site-specific hook of the given name.
# returns: return value from hook
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hook
{
    my ($hookname, @args) = @_;
    load_hooks_dir() unless $hooks_dir_scanned;

    return undef unless @{$LJ::HOOKS{$hookname} || []};
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
sub register_hook
{
    my $hookname = shift;
    my $subref = shift;
    push @{$LJ::HOOKS{$hookname}}, $subref;
}

sub load_hooks_dir {
    return if $hooks_dir_scanned++;
    
    # eh, not actually subclasses... just files named $class.pm
    # $a::$b ==> cgi-bin/$a/$b
    foreach my $class (LJ::ModuleLoader->module_subclasses("LJ::Hooks"),
                       LJ::ModuleLoader->module_subclasses("DW::Hooks")) {
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
sub register_setter
{
    my $key = shift;
    my $subref = shift;
    $LJ::SETTER{$key} = $subref;
}

register_setter('synlevel', sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ /^(title|cut|summary|full)$/) {
        $$err = "Illegal value.  Must be 'title', 'cut', 'summary', or 'full'";
        return 0;
    }

    $u->set_prop("opt_synlevel", $value);
    return 1;
});

register_setter("newpost_minsecurity", sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ /^(public|access|members|private|friends)$/) {
        $$err = "Illegal value.  Must be 'public', 'access' (for personal journals), 'members' (for communities), or 'private'";
        return 0;
    }
    # Don't let commmunities be access-locked
    if ( $u->is_community ) {
       if ( $value eq "access" ) {
            $$err = "newpost_minsecurity cannot be access-locked for communities (use 'members' instead)";
            return 0;
        }
    }
    if ( $u->is_individual && $value eq "members" ) {
        $$err = "newpost_minsecurity members not applicable to non-community journals. (use 'access' instead)";
        return 0;
    }
    
    $value = "" if $value eq "public";
    $value = "friends" if $value eq "access" || $value eq "members";

    $u->set_prop("newpost_minsecurity", $value);
    return 1;
});

register_setter("maximagesize", sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ m/^(\d+)[x,|](\d+)$/) {
        $$err = "Illegal value.  Must be width,height.";
        return 0;
    }
    $value = "$1|$2";
    $u->set_prop("opt_imagelinks", $value);
    return 1;
});

register_setter("opt_cut_disable_journal", sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    $u->set_prop( "opt_cut_disable_journal", $value );
    return 1;
});

register_setter("opt_cut_disable_reading", sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    $u->set_prop( "opt_cut_disable_reading", $value );
    return 1;
});

register_setter("disable_quickreply", sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    $u->set_prop("opt_no_quickreply", $value);
    return 1;
});

register_setter("icbm", sub {
    my ($u, $key, $value, $err) = @_;
    my $loc = eval { LJ::Location->new(coords => $value); };
    unless ($loc) {
        $u->set_prop("icbm", "");  # unset
        $$err = "Illegal value.  Not a recognized format." if $value;
        return 0;
    }
    $u->set_prop("icbm", $loc->as_posneg_comma);
    return 1;
});

register_setter("no_mail_alias", sub {
    my ($u, $key, $value, $err) = @_;

    unless ($value =~ /^[01]$/) {
        $$err = "Illegal value.  Must be '0' or '1'.";
        return 0;
    }

    $u->set_prop( "no_mail_alias", $value );
    $value ? $u->delete_email_alias : $u->update_email_alias;

    return 1;
});

register_setter("latest_optout", sub {
    my ($u, $key, $value, $err) = @_;
    unless ($value =~ /^(?:yes|no)$/i) {
        $$err = "Illegal value.  Must be 'yes' or 'no'.";        return 0;
    }
    $value = lc $value eq 'yes' ? 1 : 0;
    $u->set_prop("latest_optout", $value);
    return 1;
});

1;
