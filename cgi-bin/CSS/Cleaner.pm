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
#
# From: http://code.livejournal.org/svn/CSS-Cleaner/
#
#
# Note:  this is a very early version of a CSS cleaner.  The plan is to eventually
#        make it a white-listing CSS cleaner (deny by default) with a nice
#        interface where you can build policy about what's allowed, like
#        HTML::Sanitize/::Scrub/etc, but for now this is almost a null cleaner,
#        just parsing and reserializing the CSS, removing two trivial ways to
#        inject javascript.
#
#        The plan now is to integrate this interface into LiveJournal, then improve
#        this module over time.
#
# Note2:  we tried 4 different CSS parsers for this module to use, and all 4 sucked.
#         so for now this module sucks, until we can find a suitable parser.  for the
#         record, CSS::Tiny, CSS, and CSS::SAC all didn't work.  and csstidy wasn't
#         incredibly hot either.  CSS.pm's grammar was buggy, and CSS::SAC had the
#         best interface (SAC) but terrible parsing of selectors.  we'll probably
#         have to write our own, based on the Mozilla CSS parsing code.

package CSS::Cleaner;
use strict;
use vars qw($VERSION);
$VERSION = '0.01';

sub new {
    my $class = shift;
    my %opts  = @_;

    my $self = bless {}, $class;

    if ( defined( $opts{rule_handler} ) ) {
        my $rule_handler = $opts{rule_handler};
        die "rule_handler needs to be a coderef if supplied" unless ref($rule_handler) eq 'CODE';
        $self->{rule_handler} = $rule_handler;
    }

    if ( defined( $opts{pre_hook} ) ) {
        my $pre_hook = $opts{pre_hook};
        die "pre_hook needs to be a coderef if supplied" unless ref($pre_hook) eq 'CODE';
        $self->{pre_hook} = $pre_hook;
    }

    return $self;
}

# cleans CSS
sub clean {
    my ( $self, $target ) = @_;
    $self->_stupid_clean( \$target );
    return $target;
}

# cleans CSS properties, as if it were in a style="" attribute
sub clean_property {
    my ( $self, $target ) = @_;
    $self->_stupid_clean( \$target );
    return $target;
}

# this is so stupid.  see notes at top.
#  returns 1 if it was okay, 0 if possibly malicious
sub _stupid_clean {
    my ( $self, $ref ) = @_;

    my $reduced = $$ref;
    if ( defined( $self->{pre_hook} ) ) {
        $self->{pre_hook}->( \$reduced );
    }

    $reduced =~ s/&\#(\d+);?/chr($1)/eg;
    $reduced =~ s/&\#x(\w+);?/chr(hex($1))/eg;

    if ( $reduced =~ /[\x00-\x08\x0B\x0C\x0E-\x1F]/ ) {
        $$ref = "/* suspect CSS: low bytes */";
        return;
    }

    if ( $reduced =~ /[\x7f-\xff]/ ) {
        $$ref = "/* suspect CSS: high bytes */";
        return;
    }

    # returns 1 if something bad was found
    my $check_for_bad = sub {
        if ( $reduced =~ m!<\w! ) {
            $$ref = "/* suspect CSS: start HTML tag? */";
            return 1;
        }

        my $with_white = $reduced;
        $reduced =~ s/[\s\x0b]+//g;

        if ( $reduced =~ m!\\[a-f0-9]!i ) {
            $$ref = "/* suspect CSS: backslash hex */";
            return;
        }

        $reduced =~ s/\\//g;

        if ( $reduced =~ /\@(import|charset)([\s\x0A\x0D]*[^\x0A\x0D]*)/i ) {
            my $what  = $1;
            my $value = $2;
            if ( defined( $self->{rule_handler} ) ) {
                return $self->{rule_handler}->( $ref, $what, $value );
            }
            else {
                $$ref = "/* suspect CSS: $what rule */";
                return;
            }
        }

        if ( $reduced =~ /&\#/ ) {
            $$ref = "/* suspect CSS: found irregular &# */";
            return;
        }

        if ( $reduced =~ m!</! ) {
            $$ref = "/* suspect CSS: close HTML tag */";
            return;
        }

        # returns 1 if bad phrases found
        my $check_phrases = sub {
            my $str = shift;
            if (
                $$str =~ m/(\bdata:\b|javascript|jscript|livescript|vbscript|expression|eval|cookie
                |\bwindow\b|\bparent\b|\bthis\b|behaviou?r|moz-binding)/ix
                )
            {
                my $what = lc $1;
                $$ref = "/* suspect CSS: potential scripting: $what */";
                return 1;
            }
            return 0;
        };
        return 1 if $check_phrases->( \$reduced );

        # restore whitespace
        $reduced = $with_white;
        $reduced =~ s!/\*.*?\*/!!sg;
        $reduced =~ s!\<\!--.*?--\>!!sg;
        $reduced =~ s/[\s\x0b]+//g;
        $reduced =~ s/\\//g;
        return 1 if $check_phrases->( \$reduced );

        return 0;
    };

    # check for bad stuff before/after removing comment lines
    return 0 if $check_for_bad->();
    $reduced =~ s!//.*!!g;
    return 0 if $check_for_bad->();
    return 1;
}

1;
