#!/usr/bin/perl
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
use FileHandle;
use IPC::Open2;
use POSIX ":sys_wait_h";

use vars qw($VERSION);
$VERSION = '1.0';

# Good spellcommand values:
#    ispell -a -h  (default)
#    /usr/local/bin/aspell pipe -H --sug-mode=fast --ignore-case

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;

    $self->{'command'} = $args->{'spellcommand'} || "ispell -a -h";
    $self->{'color'} = $args->{'color'} || "#FF0000";
    return $self;
}

# This function takes a block of text to spell-check and returns HTML 
# to show suggesting correction, if any.  If the return from this 
# function is empty, then there were no misspellings found.

sub check_html {
    my $self = shift;
    my $journal = shift;
    
    my $iread = new FileHandle;
    my $iwrite = new FileHandle;
    my $ierr = new FileHandle;
    my $pid;

    # work-around for mod_perl
    my $tie_stdin = tied *STDIN;
    untie *STDIN if $tie_stdin;

    $iwrite->autoflush(1);

    $pid = open2($iread, $iwrite, $self->{'command'}) || die "spell process failed";
    die "Couldn't find spell checker\n" unless $pid;
    my $banner = <$iread>;
    die "banner=$banner\n" unless ($banner =~ /^@\(\#\)/);
    print $iwrite "!\n";
    
    my $output = "";
    my $footnotes = "";
    
    my ($srcidx, $lineidx, $mscnt, $other_bad);
    $lineidx = 1;
    $mscnt = 0;
    foreach my $inline (split(/\n/, $$journal)) {
	$srcidx = 0;
	chomp($inline);
	print $iwrite "^$inline\n";
	
	my $idata;
	do {
	    $idata = <$iread>;
	    chomp($idata);
	    
	    if ($idata =~ /^& /) {
		$idata =~ s/^& (\S+) (\d+) (\d+): //;
		$mscnt++;
		my ($word, $sugcount, $ofs) = ($1, $2, $3);
		$ofs -= 1; # because ispell reports "1" for first character
		
		$output .= LJ::ehtml(substr($inline, $srcidx, $ofs-$srcidx));
		$output .= "<font color=\"$self->{'color'}\">".LJ::ehtml($word)."</font>";
		
		$footnotes .= "<tr valign=top><td align=right><font color=$self->{'color'}>".LJ::ehtml($word).
                              "</font></td><td>".LJ::ehtml($idata)."</td></tr>";
		
		$srcidx = $ofs + length($word);
	    } elsif ($idata =~ /^\# /) {
		$other_bad = 1;
		$idata =~ /^\# (\S+) (\d+)/;
		my ($word, $ofs) = ($1, $2);
		$ofs -= 1; # because ispell reports "1" for first character
		$output .= LJ::ehtml(substr($inline, $srcidx, $ofs-$srcidx));
		$output .= "<font color=\"$self->{'color'}\">".LJ::ehtml($word)."</font>";
		$srcidx = $ofs + length($word);
	    }
	} while ($idata ne "");
	$output .= LJ::ehtml(substr($inline, $srcidx, length($inline)-$srcidx)) . "<br>\n";
	$lineidx++;
    }

    $iread->close;
    $iwrite->close;
 
    $pid = waitpid($pid, 0);

    # return mod_perl to previous state, though not necessary?
    tie *STDIN, $tie_stdin if $tie_stdin;

    return (($mscnt || $other_bad) ? "$output<p><b>Suggestions:</b><table cellpadding=3 border=0>$footnotes</table>" : "");
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

Sometimes the opened spell process hangs and eats up tons of CPU.  Fixed now, though... I think.

check_html returns HTML we like.  You may not.  :)

=head1 AUTHORS

Evan Martin, evan@livejournal.com
Brad Fitzpatrick, bradfitz@livejournal.com

=cut
