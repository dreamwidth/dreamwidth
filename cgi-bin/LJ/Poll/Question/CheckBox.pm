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

package LJ::Poll::Question::CheckBox;
use strict;
use base qw/ LJ::Poll::Question::MultiChoice /;

sub translate_individual_answer {
    my ($self, $value, $items) = @_;
    return join(", ", map {  __PACKAGE__ . $items->{$_} } split(/,/, $value));
}

sub process_tag_options {
    my ($opts, $qopts,$err) = @_;

    my $checkmin = 0;
    my $checkmax = 255;

    if (defined $opts->{'checkmin'}) {
        $checkmin = int($opts->{'checkmin'});
    }
    if (defined $opts->{'checkmax'}) {
        $checkmax = int($opts->{'checkmax'});
    }
    if ($checkmin < 0) {
        return $err->('poll.error.checkmintoolow');
    }
    if ($checkmax < $checkmin) {
        return $err->('poll.error.checkmaxtoolow');
    }

    $qopts->{'opts'} = "$checkmin/$checkmax";
    return $qopts;
}

sub is_valid_answer {
    my ($self, $val) = @_;
    my $opts = $self->opts;
    my ($checkmin, $checkmax) = split( m!/!, $opts );
        $checkmin ||= 0;
        $checkmax ||= 255;

    $val = join(",", sort { $a <=> $b } split(/,/, $val));
    if (length($val) > 0) { # if the user answered to this question
        my @num_opts = split( /,/, $val );
        my $num_opts = scalar @num_opts;  # returns the number of options they answered


        if($num_opts < $checkmin) {
            return (LJ::Lang::ml( 'poll.error.checkfewoptions3', {'question' => $self->pollqid, 'options' => $checkmin} ), 2);
        }
        if($num_opts > $checkmax) {
            return (LJ::Lang::ml(  'poll.error.checktoomuchoptions3', {'question' =>  $self->pollqid, 'options' => $checkmax} ), 2);
        }
    }
    return 1; 
}


sub previewing_snippet_preamble {
    my $self = shift;
    my $opts = $self->opts;
    my ( $mincheck, $maxcheck ) = split( m!/!, $opts );
    my $ret = '';
    $mincheck ||= 0;
    $maxcheck ||= 255;

    if ($mincheck > 0 && $mincheck eq $maxcheck ) {
        $ret .= "<i>". LJ::Lang::ml( "poll.checkexact2", { options => $mincheck } ). "</i><br />\n";
    }
    else {
        if ($mincheck > 0) {
            $ret .= "<i>". LJ::Lang::ml( "poll.checkmin2", { options => $mincheck } ). "</i><br />\n";
        }

        if ($maxcheck < 255) {
            $ret .= "<i>". LJ::Lang::ml( "poll.checkmax2", { options => $maxcheck } ). "</i><br />\n";
        }
    }
    return $ret;
}

sub boxtype{"check"}


sub decompose_votes{my ($self,$val) = @_; return split(/,/ ,$val)  }


1;