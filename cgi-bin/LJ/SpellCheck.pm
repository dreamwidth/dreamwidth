#!/usr/bin/perl
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC.
#
# LJ::SpellCheck class
# See perldoc documentation at the end of this file.
#
# -------------------------------------------------------------------------
#
# This package is released under the LGPL (GNU Library General Public License)
#
# A copy of the license has been included with the software as LGPL.txt.
# If not, the license is available at:
#      http://www.gnu.org/copyleft/library.txt
#
# -------------------------------------------------------------------------


package LJ::SpellCheck;

use strict;
use warnings;

use Config;
use constant PERLIO_IS_ENABLED => $Config{useperlio};

use vars qw( $VERSION );
$VERSION = '2.0';

# Good spellcommand values:
#    /usr/bin/ispell -a -h
#    /usr/bin/aspell pipe -H --sug-mode=fast --ignore-case
#
# Use the full path to the command, not just the command name.
#
# If you want to include an external dictionary containing site-specific
# terms, you can add a "-p /path/to/dictionary" to the program arguments

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;

    my $command = $args->{spellcommand} || "/usr/bin/aspell pipe -H --sug-mode=fast --ignore-case";
    my @command_args = split /\s+/, $command;

    $self->{command} = shift @command_args;
    $self->{command_args} = \@command_args;

    $self->{color} = $args->{color} || "#FF0000";
    return $self;
}

# This function takes a block of text to spell-check and returns HTML
# to show suggesting correction, if any.  If the return from this
# function is empty, then there were no misspellings found.

sub check_html {
    my $self = shift;
    my $journal = shift;

    return "" unless $$journal;

    my $r = DW::Request->get;
    my ( $iwrite, $iread ) = $r->spawn( $self->{command}, $self->{command_args} );
    
    my $read_data = sub {
        my ( $fh ) = @_;
        my $data;
        $data = <$fh> if PERLIO_IS_ENABLED || IO::Select->new( $fh )->can_read( 10 );
        return defined $data ? $data : '';
    };

    # header from aspell/ispell
    my $banner = $read_data->( $iread );
    return "<?errorbar Spell checker not set up properly. banner=$banner errorbar?>" unless $banner =~ /^@\(#\)/;

    # send the command to shell-escape
    print $iwrite "!\n";

    my $output = "";
    my $footnotes = "";
    
    my ( $srcidx, $lineidx, $mscnt, $other_bad );
    $lineidx = 1;
    $mscnt = 0;
    foreach my $inline ( split( /\n/, $$journal ) ) {
        $srcidx = 0;
        chomp( $inline );
        print $iwrite "^$inline\n";
        
        my $idata;
        do {
            $idata = $read_data->( $iread );
            chomp( $idata );
            
            if ( $idata =~ /^& / ) {
                $idata =~ s/^& (\S+) (\d+) (\d+): //;
                $mscnt++;
                my ( $word, $sugcount, $ofs ) = ( $1, $2, $3 );
                $ofs -= 1; # because ispell reports "1" for first character
                
                $output .= LJ::ehtml( substr( $inline, $srcidx, $ofs - $srcidx ) );
                $output .= "<font color=\"$self->{'color'}\">" . LJ::ehtml( $word ) . "</font>";
                
                $footnotes .= "<tr valign=top><td align=right><font color=$self->{'color'}>" . LJ::ehtml( $word ) .
                              "&nbsp;</font></td><td>" . LJ::ehtml( $idata ) . "</td></tr>";
                
                $srcidx = $ofs + length( $word );
            } elsif ($idata =~ /^\# /) {
                $other_bad = 1;
                $idata =~ /^\# (\S+) (\d+)/;
                my ( $word, $ofs ) = ( $1, $2 );
                $ofs -= 1; # because ispell reports "1" for first character
                $output .= LJ::ehtml( substr( $inline, $srcidx, $ofs - $srcidx ) );
                $output .= "&nbsp;<font color=\"$self->{'color'}\">" . LJ::ehtml( $word ) . "</font>&nbsp;";
                $srcidx = $ofs + length( $word );
            }
        } while ( $idata ne "" );
            $output .= LJ::ehtml( substr( $inline, $srcidx, length( $inline ) - $srcidx ) ) . "<br>\n";
            $lineidx++;
    }

    $iread->close;
    $iwrite->close;


    return ( ( $mscnt || $other_bad ) ? "$output<p><b>Suggestions:</b><table cellpadding=3 border=0>$footnotes</table>" : "" );
}

1;
__END__

=head1 NAME

LJ::SpellCheck - let users check spelling on web pages

=head1 SYNOPSIS

  use LJ::SpellCheck;
  my $s = new LJ::SpellCheck { 'spellcommand' => 'ispell -a -h',
                   'color' => '#ff0000',
               };

  my $text = "Lets mispell thigns!";
  my $correction = $s->check_html(\$text);
  if ($correction) {
      print $correction;  # contains a ton of HTML
  } else {
      print "No spelling problems.";
  }

=head1 DESCRIPTION

The object constructor takes a 'spellcommand' argument.  This has to be some ispell compatible program, like aspell.  Optionally, it also takes a color to highlight mispelled words.

The only method on the object is check_html, which takes a reference to the text to check and returns a bunch of HTML highlighting misspellings and showing suggestions.  If it returns nothing, then there no misspellings found.

=head1 BUGS

Version 1.0 had some logic to do a waitpid, I suspect to fix a problem where sometimes the opened spell process would and eats up tons of CPU. Because this calls aspell in another manner (doesn't return the PID and may not trigger the bug), the waitpid has been removed. If any issues crop up, revisit this.

check_html returns HTML we like.  You may not.  :)

=head1 AUTHORS

Evan Martin, evan@livejournal.com
Brad Fitzpatrick, bradfitz@livejournal.com
Afuna, coder.dw@afunamatata.com
=cut
