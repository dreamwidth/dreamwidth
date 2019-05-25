#!/usr/bin/perl
#
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

package HTMLCleaner;

use strict;
use base 'HTML::Parser';
use CSS::Cleaner;

sub new {
    my ( $class, %opts ) = @_;

    my $p = new HTML::Parser(
        'api_version'   => 3,
        'start_h'       => [ \&start, 'self, tagname, attr, attrseq, text' ],
        'end_h'         => [ \&end, 'self, tagname' ],
        'text_h'        => [ \&text, 'self, text' ],
        'declaration_h' => [ \&decl, 'self, tokens' ],
    );

    $p->{'output'}               = $opts{'output'} || sub { };
    $p->{'cleaner'}              = CSS::Cleaner->new;
    $p->{'valid_stylesheet'}     = $opts{'valid_stylesheet'} || sub { 1 };
    $p->{'allow_password_input'} = $opts{'allow_password_input'} || 0;

    $p->utf8_mode(1);

    $p->{'eat_tag'} = { map { $_ => 1 } qw(script object iframe applet embed param) };

    ## Enabling tag 'iframe' if need
    delete $p->{'eat_tag'}->{'iframe'} if $opts{'enable_iframe'};

    bless $p, $class;
}

my %bad_attr = ( map { $_ => 1 } qw(datasrc datafld) );

my @eating;    # push tagname whenever we start eating a tag

sub start {
    my ( $self, $tagname, $attr, $seq, $text ) = @_;
    $tagname =~ s/<//;

    my $slashclose = 0;    # xml-style
    if ( $tagname =~ s!/(.*)!! ) {
        if ( length($1) ) { push @eating, "$tagname/$1"; }    # basically halt parsing
        else              { $slashclose = 1; }
    }

    my @allowed_tags = ('lj-embed');

    push @eating, $tagname
        if ( $self->{'eat_tag'}->{$tagname} && !grep { lc $tagname eq $_ } @allowed_tags )
        || $tagname =~ /^(?:g|fb):/;

    return if @eating;

    my $clean_res = eval {
        my $cleantag = $tagname;
        $cleantag =~ s/^.*://s;
        $cleantag =~ s/[^\w]//g;
        no strict 'subs';
        my $meth = "CLEAN_$cleantag";
        my $code = $self->can($meth)
            or return 1;    # don't clean, if no element-specific cleaner method
        return $code->( $self, $seq, $attr );
    };
    return if !$@ && !$clean_res;

    my $ret = "<$tagname";
    foreach (@$seq) {
        if ( $_ eq "/" ) { $slashclose = 1; next; }
        next if $bad_attr{ lc($_) };
        next if /^on/i;
        next if /(?:^=)|[\x0b\x0d]/;

        if ( $_ eq "style" ) {
            $attr->{$_} = $self->{cleaner}->clean_property( $attr->{$_} );
        }

        if (   $tagname eq 'input'
            && $_ eq 'type'
            && $attr->{'type'} =~ /^password$/i
            && !$self->{'allow_password_input'} )
        {
            delete $attr->{'type'};
        }

        my $nospace = $attr->{$_};
        $nospace =~ s/[\s\0]//g;

        # IE is brain-dead and lets javascript:, vbscript:, and about: have spaces mixed in
        if ( $nospace =~ /(?:(?:(?:vb|java)script)|about):/i ) {
            delete $attr->{$_};
        }
        $ret .= " $_=\"" . ehtml( $attr->{$_} ) . "\"";
    }
    $ret .= " /" if $slashclose;
    $ret .= ">";

    if ( $tagname eq "style" ) {
        $self->{'_eating_style'}   = 1;
        $self->{'_style_contents'} = "";
    }

    $self->{'output'}->($ret);
}

sub CLEAN_meta {
    my ( $self, $seq, $attr ) = @_;

    # don't allow refresh because it can refresh to javascript URLs
    # don't allow content-type because they can set charset to utf-7
    # why do we even allow meta tags?
    my $equiv = lc $attr->{"http-equiv"};
    if ($equiv) {
        $equiv =~ s/[\s\x0b]//;
        return 0 if $equiv =~ /refresh|content-type|link|set-cookie/;
    }
    return 1;
}

sub CLEAN_link {
    my ( $self, $seq, $attr ) = @_;

    if ( $attr->{rel} =~ /\bstylesheet\b/i ) {
        my $href = $attr->{href};
        return 0 unless $href =~ m!^https?://([^/]+?)(/.*)$!;
        my ( $host, $path ) = ( $1, $2 );

        my $rv = $self->{'valid_stylesheet'}->( $href, $host, $path );
        if ( $rv =~ /^\d+$/ ) {
            return 1 if $rv == 1;
        }
        if ($rv) {
            $attr->{href} = $rv;
            return 1;
        }
        return 0;
    }

# Allow blank <link> tags through so RSS S2 styles can work again without the 'rel="alternate"' hack
    return 1 if ( keys(%$attr) == 0 );

    return 1 if $attr->{rel} =~ /^(?:service|openid)\.\w+$/;
    my %okay =
        map { $_ => 1 }
        (
        qw(icon shortcut alternate next prev index made start search top help up author edituri file-list previous home contents bookmark chapter section subsection appendix glossary copyright child)
        );
    return 1 if $okay{ lc( $attr->{rel} ) };

    # Allow link tags with only an href tag. This is an implied rel="alternate"
    return 1 if ( exists( $attr->{href} ) and ( keys(%$attr) == 1 ) );

# Allow combinations of rel attributes through as long as all of them are valid, most notably "shortcut icon"
    return 1 unless grep { !$okay{$_} } split( /\s+/, $attr->{rel} );

    # unknown link tag
    return 0;
}

sub end {
    my ( $self, $tagname ) = @_;
    if (@eating) {
        pop @eating if $eating[-1] eq $tagname;
        return;
    }

    if ( $self->{'_eating_style'} ) {
        $self->{'_eating_style'} = 0;
        $self->{'output'}->( $self->{cleaner}->clean( $self->{'_style_contents'} ) );
    }

    $self->{'output'}->("</$tagname>");
}

sub text {
    my ( $self, $text ) = @_;
    return if @eating;

    if ( $self->{'_eating_style'} ) {
        $self->{'_style_contents'} .= $text;
        return;
    }

    # this string is magic [hack].  (See $out_straight in
    # cgi-bin/LJ/S2.pm) callers can print "<!-- -->" to HTML::Parser
    # just to make it flush, since HTML::Parser has no
    # ->flush_outstanding text tag.
    return if $text eq "<!-- -->";

    # the parser gives us back text whenever it's confused
    # on really broken input.  sadly, IE parses really broken
    # input, so let's escape anything going out this way.
    $self->{'output'}->( eangles($text) );
}

sub decl {
    my ( $self, $tokens ) = @_;
    $self->{'output'}->( "<!" . join( " ", map { eangles($_) } @$tokens ) . ">" );
}

sub eangles {
    my $a = shift;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

sub ehtml {
    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

1;
