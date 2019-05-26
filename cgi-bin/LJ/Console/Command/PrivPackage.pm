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

package LJ::Console::Command::PrivPackage;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "priv_package" }

sub desc {
"Manage packages of admin privs. Basic workflow: priv_package create mypkg \"Test Package\", priv_package add mypkg admin:*, priv_package list. To actually grant a package to someone, priv grant #mypkg username. Works for revoke as well. Requires priv: admin.";
}

sub args_desc {
    [
        'command' => 'One of "list", "create", "add", "remove", "delete".',
        'package' => 'The package to operate on.  Use a short name.',
        'arg' =>
'If command is "list", no argument to see all packages, or provide a package to see the privs inside. For "create" and "delete" of a package, no argument.  For "add" and "remove", arg is the privilege being granted in "privname:privarg" format.',
    ]
}

sub usage { '<command> [ <package> [ <arg> ] ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("admin");
}

sub execute {
    my ( $self, $cmd, $pkg, $arg, @args ) = @_;

    return $self->error("This command takes one, two, or three arguments. Consult the reference.")
        unless $cmd && scalar(@args) == 0;

    return $self->error("Invalid command. Consult the reference.")
        unless $cmd =~ /^(?:list|create|add|remove|delete)$/;

    return $self->error("'$cmd' requires an argument.")
        if $cmd =~ /^(?:add|remove)$/ && !$arg;

    $pkg =~ s/^#//;    # just in case they put a # on it

    my $dbh    = LJ::get_db_writer();
    my $remote = LJ::get_remote();
    my ( $pkgid, $cpkg ) =
        $dbh->selectrow_array( 'SELECT pkgid, name FROM priv_packages WHERE name = ?', undef,
        $pkg );
    return $self->error( "Database error: " . $dbh->errstr )
        if $dbh->err;

    # canonical package name is "#" plus whatever is in the db
    $cpkg = "#$cpkg";

    # list created packages, or contents of one
    if ( $cmd eq 'list' ) {
        if ( $pkg && $pkg ne 'all' ) {
            return $self->error("Package with that name does not exist")
                unless $pkgid;

            my $contents = $dbh->selectall_arrayref(
                'SELECT privname, privarg FROM priv_packages_content WHERE pkgid = ?',
                undef, $pkgid );
            return $self->error( "Database error: " . $dbh->errstr )
                if $dbh->err;

            $self->info("Contents of $cpkg:");
            foreach my $row ( @{ $contents || [] } ) {
                $self->info("   $row->[0]:$row->[1]");
            }
        }
        else {
            my $packages = $dbh->selectall_arrayref(
                      'SELECT pkgid, name, lastmoduserid, lastmodtime FROM priv_packages '
                    . 'ORDER BY name' );
            return $self->error( "Database error: " . $dbh->errstr )
                if $dbh->err;

            $self->info("Available packages:");

            foreach my $row ( @{ $packages || [] } ) {
                my $u    = LJ::load_userid( $row->[2] );
                my $time = LJ::mysql_time( $row->[3] );
                $self->info(
                    sprintf( "%5d  %-20s%-20s\%s", $row->[0], $row->[1], $u->{user}, $time ) );
            }
        }
        return 1;

        # create a package
    }
    elsif ( $cmd eq 'create' ) {
        return $self->error("Package with that name already exists.")
            if $pkgid;

        return $self->error(
            "Package names can only contain letters, numbers, underscores, hyphens, or underscores."
        ) unless $pkg =~ /^[a-z0-9_\-:\(\)\[\]]+$/i;

        $dbh->do(
            "INSERT INTO priv_packages (pkgid, name, lastmoduserid, lastmodtime) "
                . "VALUES (NULL, ?, ?, UNIX_TIMESTAMP())",
            undef, $pkg, $remote->id
        );

        return $self->print("Package '$pkg' created.");

        # delete a package
    }
    elsif ( $cmd eq 'delete' ) {
        return $self->error("Package with that name does not exist.")
            unless $pkgid;

        $dbh->do( "DELETE FROM priv_packages WHERE pkgid = ?", undef, $pkgid );
        return $self->error( "Database error: " . $dbh->errstr )
            if $dbh->err;

        $dbh->do( "DELETE FROM priv_packages_content WHERE pkgid = ?", undef, $pkgid );
        return $self->error( "Database error: " . $dbh->errstr )
            if $dbh->err;

        return $self->print("Package '$cpkg' deleted.");

        # add or remove a privilige to a package
    }
    elsif ( $cmd eq 'add' || $cmd eq 'remove' ) {
        return $self->error("Package with that name does not exist.")
            unless $pkgid;

        my ( $pname, $parg ) = split( /:/, $arg );
        return $self->error(
            "Argument must be in format of 'priv:arg' with optional arg.  (The colon is required.)")
            unless $pname && defined $parg;

        # valid priv or not
        my $valid = $dbh->selectrow_array( 'SELECT COUNT(*) FROM priv_list WHERE privcode = ?',
            undef, $pname );
        return $self->error("'$pname' is not a valid privilege.")
            unless $valid;

        # exists or not
        my $exists = $dbh->selectrow_array(
            'SELECT COUNT(*) FROM priv_packages_content '
                . 'WHERE pkgid = ? AND privname = ? AND privarg = ?',
            undef, $pkgid, $pname, $parg
        );
        return $self->error( "Database error: " . $dbh->errstr )
            if $dbh->err;

        if ( $cmd eq 'add' ) {
            return $self->error("Privilege already exists in package.")
                if $exists;
            $dbh->do(
                "INSERT INTO priv_packages_content (pkgid, privname, privarg) VALUES (?, ?, ?)",
                undef, $pkgid, $pname, $parg );
            return $self->error( "Database error: " . $dbh->errstr )
                if $dbh->err;
            $dbh->do(
"UPDATE priv_packages SET lastmoduserid = ?, lastmodtime = UNIX_TIMESTAMP() WHERE pkgid = ?",
                undef, $remote->id, $pkgid
            );
            return $self->print("Privilege ($pname:$parg) added to package $cpkg.");
        }
        else {    # a removal
            return $self->error("Privilege does not exist in package.")
                unless $exists;
            $dbh->do(
"DELETE FROM priv_packages_content WHERE pkgid = ? AND privname = ? AND privarg = ?",
                undef, $pkgid, $pname, $parg
            );
            return $self->error( "Database error: " . $dbh->errstr )
                if $dbh->err;
            $dbh->do(
"UPDATE priv_packages SET lastmoduserid = ?, lastmodtime = UNIX_TIMESTAMP() WHERE pkgid = ?",
                undef, $remote->id, $pkgid
            );
            return $self->print("Privilege ($pname:$parg) removed from package $cpkg.");
        }
    }
}

1;
