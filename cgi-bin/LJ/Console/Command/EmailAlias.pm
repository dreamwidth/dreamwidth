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

package LJ::Console::Command::EmailAlias;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "email_alias" }

sub desc { "View and edit email aliases. Requires priv: reset_email." }

sub args_desc {
    [
        action =>
            "One of: 'show' (to view recipient), 'delete' (to delete), or 'set' (to set a value)",
        alias => "The first portion of the email alias (eg, just the username)",
        value =>
            "Value to set the email alias to, if using 'set'. Append '!' to override spell-check.",
    ]
}

sub usage { '<action> <alias> [ <value> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("reset_email");
}

sub execute {
    my ( $self, $action, $alias, $value, @args ) = @_;

    return $self->error("This command takes two or three arguments. Consult the reference.")
        unless $action && $alias && scalar(@args) == 0;

    return $self->error("Invalid action. Must be either 'show', 'delete', or 'set'.")
        unless $action =~ /^(?:show|delete|set)$/;

    # canonicalize
    $alias =~ s/\@.*//;
    $alias .= "@" . $LJ::USER_DOMAIN;

    my $dbh = LJ::get_db_writer();

    if ( $action eq "set" ) {
        my @emails = split( /\s*,\s*/, $value );

        return $self->error("You must specify a recipient for the email alias.")
            unless scalar(@emails);

        $value = join( ",", @emails );
        return $self->error("Total length of recipient addresses cannot exceed 200 characters.")
            if length $value > 200;

        my @errors;
        for (@emails) {
            my $force_spelling = s/!$//;

            # "lj" as a recipient is magical
            next if $_ eq 'lj';
            my ( $bad_spelling, @errors_here );
            LJ::check_email( $_, \@errors_here, { force_spelling => $force_spelling },
                \$bad_spelling );
            push @errors_here, "Append '!' to override spell-check."
                if ( $bad_spelling && !$force_spelling );
            @errors = ( @errors, @errors_here );
        }
        return $self->error( join( "\n", @errors ) ) if @errors;

        $dbh->do( "REPLACE INTO email_aliases VALUES (?, ?)", undef, $alias, $value );
        return $self->error( "Database error: " . $dbh->errstr )
            if $dbh->err;
        return $self->print("Successfully set $alias => $value");

    }
    elsif ( $action eq "delete" ) {
        $dbh->do( "DELETE FROM email_aliases WHERE alias=?", undef, $alias );
        return $self->error( "Database error: " . $dbh->errstr )
            if $dbh->err;
        return $self->print("Successfully deleted $alias alias.");

    }
    else {

        my ($rcpt) =
            $dbh->selectrow_array( "SELECT rcpt FROM email_aliases WHERE alias=?", undef, $alias );
        return $self->error( "Database error: " . $dbh->errstr )
            if $dbh->err;

        if ($rcpt) {
            return $self->print("$alias aliases to $rcpt");
        }
        else {
            return $self->error("$alias is not currently defined.");
        }
    }

}

1;
