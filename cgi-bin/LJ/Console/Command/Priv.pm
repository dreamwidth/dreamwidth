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

package LJ::Console::Command::Priv;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "priv" }

sub desc {
"Grant or revoke user privileges, or list available privileges and their arguments. Requires priv: admin.";
}

sub args_desc {
    [
        'action' =>
            "'list', 'grant', 'revoke', or 'revoke_all' to revoke all args for a given priv.",
        'privs' =>
"Comma-delimited list of priv names, priv:arg pairs, or package names (prefixed with #). Required for all actions except 'list'. Using 'list' with no arguments will return results for all privs.",
        'usernames' => "Comma-delimited list of usernames (not used for 'list').",
    ]
}

sub usage { '<action> [ <privs> [ <usernames> ] ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return ( $remote && $remote->has_priv("admin") ) || $LJ::IS_DEV_SERVER;
}

sub execute {
    my ( $self, $action, $privs, $usernames, @args ) = @_;

    return $self->error("This command takes one, two, or three arguments. Consult the reference.")
        unless $action && scalar(@args) == 0;

    return $self->error("Action must be one of 'list', 'grant', 'revoke', or 'revoke_all'")
        unless $action =~ /(?:list|grant|revoke|revoke\_all)/;

    return $self->error("'$action' requires two arguments. Consult the reference.")
        if $action ne 'list' && !$usernames;

    my $dbh = LJ::get_db_reader();

    my @privs;
    if ( $action eq 'list' && !$privs ) {

        # list all privs
        $privs = $dbh->selectcol_arrayref("SELECT privcode FROM priv_list ORDER BY privcode");
        push @privs, [ $_, undef ] foreach @$privs;
    }
    else {
        foreach my $priv ( split /,/, $privs ) {
            if ( $priv !~ /^#/ ) {
                push @privs, [ split /:/, $priv, 2 ];
            }
            else {
                # now we have a priv package
                if ( $action eq 'list' ) {
                    $self->error("Use the priv_package command to list packages.");
                    next;
                }
                my $pname = substr( $priv, 1 );
                my $privs = $dbh->selectall_arrayref(
                    "SELECT c.privname, c.privarg "
                        . "FROM priv_packages p, priv_packages_content c "
                        . "WHERE c.pkgid = p.pkgid AND p.name = ?",
                    undef, $pname
                );
                push @privs, [@$_] foreach @{ $privs || [] };
            }
        }
    }

    return $self->error("No privs or priv packages specified")
        unless @privs;

    my $remote = LJ::get_remote();
    foreach my $pair (@privs) {
        my ( $priv, $arg ) = @$pair;
        my $parg = defined $arg ? $arg : '';    # for printing undefs

        if ( $action eq "list" ) {
            my $args    = LJ::list_valid_args($priv);
            my @arglist = sort keys %$args;
            if (@arglist) {
                $self->info("Accepted arguments for $priv:");
                $self->info(" '$_' - $args->{$_}") foreach @arglist;
            }
            else {
                $self->error("No arguments available for $priv.");
            }
            next;
        }

        unless (
            $remote
            && (   $remote->has_priv( "admin", "$priv" )
                || $remote->has_priv( "admin", "$priv/$parg" ) )
            )
        {
            $self->error("You are not permitted to $action $priv:$parg");
            next;
        }

        # To reduce likelihood that someone will do 'priv revoke foo'
        # intending to remove 'foo:*' and accidentally only remove 'foo:'
        if ( $action eq "revoke" and not defined $arg ) {
            $self->error("You must explicitly specify an empty argument when revoking a priv.");
            $self->error(
"For example, specify 'revoke foo:', not 'revoke foo', to revoke 'foo' with no argument."
            );
            next;
        }

        if ( $action eq "revoke_all" and defined $arg ) {
            $self->error("Do not explicitly specify priv arguments when using revoke_all.");
            next;
        }

        foreach my $user ( split /,/, $usernames ) {
            my $u = LJ::load_user($user);
            unless ($u) {
                $self->error("Invalid username: $user");
                next;
            }

            my $shmsg;
            my $rv;
            if ( $action eq "grant" ) {
                if ( $u && $u->has_priv( $priv, $arg ) ) {
                    $self->error("$user already has $priv:$parg");
                    next;
                }
                $rv    = $u->grant_priv( $priv, $arg );
                $shmsg = "Granting: '$priv' with arg '$parg'";
            }
            elsif ( $action eq "revoke" ) {
                unless ( $u && $u->has_priv( $priv, $arg ) ) {
                    $self->error("$user does not have $priv:$parg");
                    next;
                }
                $rv    = $u->revoke_priv( $priv, $arg );
                $shmsg = "Denying: '$priv' with arg '$parg'";
            }
            else {    # revoke_all
                unless ( $u && $u->has_priv($priv) ) {
                    $self->error("$user does not have any $priv privs");
                    next;
                }
                $rv    = $u->revoke_priv_all($priv);
                $shmsg = "Denying: '$priv' with all args";
            }

            return $self->error("Unable to $action $priv:$parg")
                unless $rv;

            my $shtype = ( $action eq "grant" ) ? "privadd" : "privdel";
            LJ::statushistory_add( $u, $remote, $shtype, $shmsg );

            $self->info( $shmsg . " for user '" . $u->user . "'." );
        }
    }

    return 1;
}

1;
