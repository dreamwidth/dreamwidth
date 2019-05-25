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

package LJ::Console::Command::FaqCat;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "faqcat" }

sub desc { "Tool for managing FAQ categories. Requires priv: faqcat." }

sub args_desc {
    [
        'command' =>
"One of: list, delete, add, move.  'list' shows all the defined FAQ categories, including their catkey, name, and sortorder.  Also, it shows all the distinct catkeys that are in use by FAQ. 'add' creates or modifies a FAQ category. 'delete' removes a FAQ category (but not the questions that are in it). 'move' moves a FAQ category up or down in the list.",
        'commandargs' =>
"'add' takes 3 arguments: a catkey, a catname, and a sort order field. 'delete' takes one argument: the catkey value. 'move' takes two arguments: the catkey and either the word 'up' or 'down'."
    ]
}

sub usage { '<command> <commandargs>' }

sub requires_remote { 0 }    # 'list' doesn't need a remote

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("faqcat");
}

sub execute {
    my ( $self, $command, @args ) = @_;

    my $remote = LJ::get_remote();
    return $self->error("You are not authorized to run this command.")
        unless $remote && $remote->has_priv("faqcat");

    my $dbh = LJ::get_db_writer();

    return $self->error("Invalid command. Must be one of 'list', 'move', 'add', or 'delete'.")
        unless $command =~ /^(?:list|move|add|delete)$/;

    if ( $command eq "list" ) {
        my %catdefined;
        $self->info( sprintf( "%-20s %-45s %s", "catkey", "catname", "order" ) );
        $self->info( "-" x 76 );

        my $sth =
            $dbh->prepare("SELECT faqcat, faqcatname, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        while ( my ( $faqcat, $faqcatname, $catorder ) = $sth->fetchrow_array ) {
            $catdefined{$faqcat} = 1;
            $self->info( sprintf( "%-20s %-45s %5d", $faqcat, $faqcatname, $catorder ) );
        }
        $sth->finish;

        $self->info("");
        $self->info("catkeys currently in use:");
        $self->info( "-" x 25 );

        $sth = $dbh->prepare("SELECT faqcat, COUNT(*) FROM faq GROUP BY 1");
        $sth->execute;
        my $total = 0;
        while ( my ( $faqcat, $count ) = $sth->fetchrow_array ) {
            $total += $count;
            my $msg = sprintf( "%-15s by %5d", $faqcat, $count );
            if ( $catdefined{$faqcat} ) {
                $self->info($msg);
            }
            else {
                $self->error($msg);
            }
        }
        $sth->finish;

        $self->info( "=" x 25 );
        $self->info("total faqs: $total");

        return 1;
    }

    if ( $command eq "delete" ) {
        my $catkey = shift @args;
        return $self->error(
            "The 'delete' command takes exactly one argument. Consult the reference.")
            unless $catkey && scalar(@args) == 0;

        my $ct = $dbh->do( "DELETE FROM faqcat WHERE faqcat = ?", undef, $catkey );

        if ( $ct > 0 ) {
            return $self->print("Category deleted");
        }
        else {
            return $self->error("Unknown category: $catkey");
        }
    }

    if ( $command eq "add" ) {
        my ( $catkey, $catname, $catorder ) = @args;
        $catname = LJ::trim($catname);
        return $self->error(
            "The 'add' command takes exactly three arguments. Consult the reference.")
            unless $catkey && $catname && $catorder && scalar(@args) == 3;

        my $faqd  = LJ::Lang::get_dom("faq");
        my $rlang = LJ::Lang::get_root_lang($faqd);
        undef $faqd unless $rlang;

        if ($faqd) {
            LJ::Lang::set_text( $faqd->{'dmid'}, $rlang->{'lncode'},
                "cat.$catkey", $catname, { 'changeseverity' => 1 } );
        }

        $dbh->do( "REPLACE INTO faqcat (faqcat, faqcatname, catorder) VALUES (?, ?, ?)",
            undef, $catkey, $catname, $catorder );

        return $self->print("Category added/changed");
    }

    if ( $command eq "move" ) {
        my ( $catkey, $dir ) = @args;
        return $self->error(
            "The 'move' command takes exactly two arguments. Consult the reference.")
            unless $catkey && $dir && scalar(@args) == 2;

        return $self->error("Direction argument must be 'up' or 'down'.")
            unless $dir eq "up" || $dir eq "down";

        my %pre;         # catkey -> key before
        my %post;        # catkey -> key after
        my %catorder;    # catkey -> order

        my $sth = $dbh->prepare("SELECT faqcat, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        my $last;
        while ( my ( $key, $order ) = $sth->fetchrow_array ) {
            $catorder{$key} = $order;
            $post{$last}    = $key;
            $pre{$key}      = $last;
            $last           = $key;
        }

        my %new;         # catkey -> new order
        if ( $dir eq "up" && $pre{$catkey} ) {
            $new{$catkey} = $catorder{ $pre{$catkey} };
            $new{ $pre{$catkey} } = $catorder{$catkey};
        }
        if ( $dir eq "down" && $post{$catkey} ) {
            $new{$catkey} = $catorder{ $post{$catkey} };
            $new{ $post{$catkey} } = $catorder{$catkey};
        }
        if (%new) {
            foreach my $n ( keys %new ) {
                $dbh->do( "UPDATE faqcat SET catorder=? WHERE faqcat=?", undef, $new{$n}, $n );
            }
            return $self->info("Category order changed.");
        }

        return $self->error("Category can't move $dir anymore.");
    }

    return 1;
}

1;
