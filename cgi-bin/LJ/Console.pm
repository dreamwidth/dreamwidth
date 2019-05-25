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

# LJ::Console family of libraries
#
# Initial structure:
#
# LJ::Console.pm                 # wrangles commands, parses input, etc
# LJ::Console::Command.pm        # command base class
# LJ::Console::Command::Foo.pm   # individual command implementation
# LJ::Console::Response.pm       # success/failure, very simple
#
# Usage:
#
# my $out_html = LJ::Console->run_commands_html($user_input);
# my $out_text = LJ::Console->run_commands_text($user_text);
#

package LJ::Console;

use strict;
use Carp qw(croak);
use LJ::ModuleLoader;

my @CLASSES   = LJ::ModuleLoader->module_subclasses("LJ::Console::Command");
my @DWCLASSES = LJ::ModuleLoader->module_subclasses("DW::Console::Command");

my %cmd2class;
foreach my $class ( @CLASSES, @DWCLASSES ) {
    eval "use $class";
    die "Error loading class '$class': $@" if $@;
    $cmd2class{ $class->cmd } = $class;
}

# takes a set of console commands, returns command objects
sub parse_text {
    my $class = shift;
    my $text  = shift;

    my @ret;

    foreach my $line ( split( /\n/, $text ) ) {
        my @args = LJ::Console->parse_line($line);
        push @ret, LJ::Console->parse_array(@args);
    }

    return @ret;
}

# takes an array including a command name and its arguments
# returns the corresponding command object
sub parse_array {
    my ( $class, $cmd, @args ) = @_;
    return unless $cmd;

    $cmd = lc($cmd);
    my $cmd_class = $cmd2class{$cmd} || "LJ::Console::Command::InvalidCommand";

    return $cmd_class->new( command => $cmd, args => \@args );
}

# parses each console command, parses out the arguments
sub parse_line {
    my $class = shift;
    my $cmd   = shift;

    return () unless $cmd =~ /\S/;

    $cmd =~ s/^\s+//;
    $cmd =~ s/\s+$//;
    $cmd =~ s/\t/ /g;

    my $state = 'a';    # w=whitespace, a=arg, q=quote, e=escape (next quote isn't closing)

    my @args;
    my $argc = 0;
    my $len  = length($cmd);
    my ( $lastchar, $char );

    for ( my $i = 0 ; $i < $len ; $i++ ) {
        $lastchar = $char;
        $char     = substr( $cmd, $i, 1 );

        ### jump out of quots
        if ( $state eq "q" && $char eq '"' ) {
            $state = "w";
            next;
        }

        ### keep ignoring whitespace
        if ( $state eq "w" && $char eq " " ) {
            next;
        }

        ### finish arg if space found
        if ( $state eq "a" && $char eq " " ) {
            $state = "w";
            next;
        }

        ### if non-whitespace encountered, move to next arg
        if ( $state eq "w" ) {
            $argc++;
            if ( $char eq '"' ) {
                $state = "q";
                next;
            }
            else {
                $state = "a";
            }
        }

        ### don't count this character if it's a quote
        if ( $state eq "q" && $char eq '"' ) {
            $state = "w";
            next;
        }

        ### respect backslashing quotes inside quotes
        if ( $state eq "q" && $char eq "\\" ) {
            $state = "e";
            next;
        }

        ### after an escape, next character is literal
        if ( $state eq "e" ) {
            $state = "q";
        }

        $args[$argc] .= $char;
    }

    return @args;
}

# takes a set of response objects and returns string implementation
sub run_commands_text {
    my ( $pkg, $text ) = @_;

    my $out;
    foreach my $c ( LJ::Console->parse_text($text) ) {
        $out .= $c->as_string . "\n" unless $LJ::T_NO_COMMAND_PRINT;
        $c->execute_safely;
        $out .= join( "\n", map { $_->as_string } $c->responses );
    }

    return $out;
}

sub run_commands_html {
    my ( $pkg, $text ) = @_;

    my $out;
    foreach my $c ( LJ::Console->parse_text($text) ) {
        $out .= $c->as_html;
        $out .= "<pre><span class='console_text'>";
        $c->execute_safely;
        $out .= join( "\n", map { $_->as_html } $c->responses );
        $out .= "</span></pre>";
    }

    return $out;
}

sub command_list_html {
    my $pkg = shift;

    my $ret = "<ul>";
    foreach ( sort keys %cmd2class ) {
        next if $cmd2class{$_}->is_hidden;
        next unless $cmd2class{$_}->can_execute;

        $ret .= "<li><a href='#cmd.$_'>$_</a></li>\n";
    }
    $ret .= "</ul>";
    return $ret;
}

sub command_reference_html {
    my $pkg = shift;

    my $ret;

    foreach my $cmd ( sort keys %cmd2class ) {
        my $class = $cmd2class{$cmd};
        my $style = $class->can_execute ? "enabled" : "disabled";

        $ret .= "<hr /><div class='$style'><h2 id='cmd.$cmd'><code><b>$cmd</b> ";
        $ret .= LJ::ehtml( $class->usage );
        $ret .= "</code>";
        $ret .= " (unavailable)" unless $class->can_execute;
        $ret .= "</h2>\n";
        $ret .= "<p><em><?_ml error.console.notpermitted _ml?></em></p>" unless $class->can_execute;

        $ret .= $class->desc;

        if ( $class->args_desc ) {
            my $args = $class->args_desc;
            $ret .= "<dl>";
            while ( my ( $arg, $des ) = splice( @$args, 0, 2 ) ) {
                $ret .= "<dt><strong><em>$arg</em></strong></dt><dd>$des</dd>\n";
            }
            $ret .= "</dl>";
        }
        $ret .= "</div>";
    }

    return $ret;
}

1;
