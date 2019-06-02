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

package LJ;
use strict;

use LJ::ConvUTF8;
use HTML::TokeParser;
use HTML::Entities;

# <LJFUNC>
# name: LJ::trim
# class: text
# des: Removes whitespace from left and right side of a string.
# args: string
# des-string: string to be trimmed
# returns: trimmed string
# </LJFUNC>
sub trim {
    my $a = $_[0];
    return '' unless defined $a;

    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

# check argument text for see_request links, and strip any auth args

sub strip_request_auth {
    my $a = $_[0];
    return '' unless defined $a;

    $a =~ s/(see_request\S+?)\&auth=\w+/$1/ig;
    return $a;
}

# <LJFUNC>
# name: LJ::get_urls
# class: text
# des: Returns a list of all referenced URLs from a string.
# args: text
# des-text: Text from which to return extra URLs.
# returns: list of URLs
# </LJFUNC>
sub get_urls {
    return ( $_[0] =~ m!https?://[^\s\"\'\<\>]+!g );
}

# similar to decode_url_string below, but a nicer calling convention.  returns
# a hash of items parsed from the string passed in as the only argument.

# FIXME: This method using \0 is being used in legacy locations
#  however should be factored out ( to Hash::MultiValue )
#  as soon as the need for the legacy use is removed.
sub parse_args {
    my $args = $_[0];
    return unless defined $args;

    my %GET;
    foreach my $pair ( split /&/, $args ) {
        my ( $name, $value ) = split /=/, $pair;

        if ( defined $value ) {
            $value =~ tr/+/ /;
            $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        }
        else {
            $value = '';
        }

        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

        $GET{$name} .= $GET{$name} ? "\0$value" : $value;
    }
    return %GET;
}

# <LJFUNC>
# name: LJ::decode_url_string
# class: web
# des: Parse URL-style arg/value pairs into a hash.
# args: buffer, hashref
# des-buffer: Scalar or scalarref of buffer to parse.
# des-hashref: Hashref to populate.
# returns: boolean; true.
# </LJFUNC>
sub decode_url_string {
    my $a       = shift;
    my $buffer  = ref $a ? $a : \$a;
    my $hashref = shift;               # output hash
    my $keyref  = shift;               # array of keys as they were found

    my $pair;
    my @pairs = split( /&/, $$buffer );
    @$keyref = @pairs;
    my ( $name, $value );
    foreach $pair (@pairs) {
        ( $name, $value ) = split( /=/, $pair );
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name  =~ tr/+/ /;
        $name  =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $hashref->{$name} .= $hashref->{$name} ? "\0$value" : $value;
    }
    return 1;
}

# args: hashref of key/values
#       arrayref of keys in order (optional)
# returns: urlencoded string
sub encode_url_string {
    my ( $hashref, $keyref ) = @_;

    return join( '&',
        map { LJ::eurl($_) . '=' . LJ::eurl( $hashref->{$_} ) }
            ( ref $keyref ? @$keyref : keys %$hashref ) );
}

# <LJFUNC>
# name: LJ::eurl
# class: text
# des: Escapes a value before it can be put in a URL.  See also [func[LJ::durl]].
# args: string
# des-string: string to be escaped
# returns: string escaped
# </LJFUNC>
sub eurl {
    my $a = $_[0];
    return '' unless defined $a;

    $a =~ s/([^a-zA-Z0-9_\,\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

# <LJFUNC>
# name: LJ::durl
# class: text
# des: Decodes a value that's URL-escaped.  See also [func[LJ::eurl]].
# args: string
# des-string: string to be decoded
# returns: string decoded
# </LJFUNC>
sub durl {
    my $a = $_[0];
    return '' unless defined $a;

    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

# <LJFUNC>
# name: LJ::exml
# class: text
# des: Escapes a value before it can be put in XML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub exml {
    my $a = $_[0];
    return '' unless defined $a;

    # fast path for the commmon case:
    return $a unless $a =~ /[&\"\'<>\x00-\x08\x0B\x0C\x0E-\x1F]/;

    # what are those character ranges? XML 1.0 allows:
    # #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]

    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    $a =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    return $a;
}

# <LJFUNC>
# name: LJ::ehtml
# class: text
# des: Escapes a value before it can be put in HTML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ehtml {
    my $a = $_[0];
    return '' unless defined $a;

    # fast path for the commmon case:
    return $a unless $a =~ /[&\"\'<>]/;

    # this is faster than doing one substitution with a map:
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}
*eall = \&ehtml;    # old BML syntax required eall to also escape BML.  not anymore.

# <LJFUNC>
# name: LJ::dhtml
# class: text
# des: Decodes a value that's HTML-escaped.  See also [func[LJ::ehtml]].
# args: string
# des-string: string to be decoded
# returns: string decoded
# </LJFUNC>
sub dhtml {
    my $a = $_[0];
    return '' unless defined $a;

    return HTML::Entities::decode_entities($a);
}

# <LJFUNC>
# name: LJ::etags
# class: text
# des: Escapes < and > from a string
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub etags {
    my $a = $_[0];
    return '' unless defined $a;

    # fast path for the commmon case:
    return $a unless $a =~ /[<>]/;

    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

# <LJFUNC>
# name: LJ::ejs
# class: text
# des: Escapes a string value before it can be put in JavaScript.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ejs {
    my $a = $_[0];
    return '' unless defined $a;

    # use zero-width lookahead to insert a backslash where needed
    $a =~ s/(?=[\"\'\\])/\\/g;
    $a =~ s/&quot;/\\&quot;/g;
    $a =~ s/\r?\n/\\n/gs;
    $a =~ s/\r//gs;
    $a =~ s/\xE2\x80[\xA8\xA9]//gs;
    return $a;
}

# given a string, makes it into a string you can put into javascript,
# including protecting against closing </script> tags in the entry.
# does the double quotes for ya.
sub ejs_string {
    my $str = ejs( $_[0] );
    $str =~ s!</script!</scri\" + \"pt!gi;
    return "\"" . $str . "\"";
}

# changes every char in a string to %XX where XX is the hex value
# this is useful for passing strings to javascript through HTML, because
# javascript's "unescape" function expects strings in this format
sub ejs_all {
    my $a = $_[0];
    return '' unless defined $a;

    $a =~ s/(.)/uc sprintf("%%%02x",ord($1))/eg;
    return $a;
}

# strip all HTML tags from a string
sub strip_html {
    my $str = $_[0];
    return '' unless defined $str;

    $str =~
        s/\<(?:lj(?: site=[^\s]+)? user|user(?: site=[^\s]+)? name)\=['"]?([\w-]+)['"]?[^>]*\>/$1/g;
    $str =~ s/\<([^\<])+\>//g;
    return $str;
}

# <LJFUNC>
# name: LJ::is_ascii
# des: checks if text is pure ASCII.
# args: text
# des-text: text to check for being pure 7-bit ASCII text.
# returns: 1 if text is indeed pure 7-bit, 0 otherwise.
# </LJFUNC>
sub is_ascii {
    my $text = $_[0];
    return 1 unless defined $text;
    return ( $text !~ m/[^\x01-\x7f]/ );
}

# <LJFUNC>
# name: LJ::is_utf8
# des: check text for UTF-8 validity.
# args: text
# des-text: text to check for UTF-8 validity
# returns: 1 if text is a valid UTF-8 stream, 0 otherwise.
# </LJFUNC>
sub is_utf8 {
    my $text = shift;

    if ( LJ::Hooks::are_hooks("is_utf8") ) {
        return LJ::Hooks::run_hook( "is_utf8", $text );
    }

    require Unicode::CheckUTF8;
    {
        no strict;
        local $^W = 0;
        *stab = *{"main::LJ::"};
        undef $stab{is_utf8};
    }
    *LJ::is_utf8 = \&LJ::is_utf8_wrapper;
    return LJ::is_utf8_wrapper($text);
}

# <LJFUNC>
# name: LJ::is_utf8_wrapper
# des: wraps the check for UTF-8 validity.
# args: text
# des-text: text to check for UTF-8 validity
# returns: 1 if text is a valid UTF-8 stream, a reference, or null; 0 otherwise.
# </LJFUNC>
sub is_utf8_wrapper {
    my $text = $_[0];

    if ( defined $text && !ref $text && $text ) {

        # we need to make sure $text values are treated as strings
        return Unicode::CheckUTF8::is_utf8( '' . $text );
    }
    else {
        # all possible "false" values for $text are valid unicode
        return 1;
    }
}

# <LJFUNC>
# name: LJ::has_too_many
# des: checks if text is too long
# args: text, maxbreaks, maxchars
# des-text: text to check if too long
# des-maxbreaks: maximum number of linebreak
# des-maxchars: maximum number of characters
# returns: true if text has more than maxbreaks linebreaks or more than maxchars characters
# </LJFUNC>
sub has_too_many {
    my ( $text, %opts ) = @_;

    return 1 if exists $opts{chars} && length($text) > $opts{chars};

    if ( exists $opts{linebreaks} ) {
        my @breaks = $text =~ m/(<br \/>|\n)/g;
        return 1 if scalar @breaks > $opts{linebreaks};
    }

    return 0;
}

# alternate version of "lc" that handles UTF-8
# args: text string for lowercasing
# returns: lowercase string
sub utf8_lc {
    use Encode;    # Perl 5.8 or higher

    # get the encoded text to work with
    my $text = decode( "UTF-8", $_[0] );

    # return the lowercased text
    return encode( "UTF-8", lc $text );
}

# <LJFUNC>
# name: LJ::text_out
# des: force outgoing text into valid UTF-8.
# args: text
# des-text: reference to text to pass to output. Text if modified in-place.
# returns: nothing.
# </LJFUNC>
sub text_out {
    my $rtext = shift;

    # is this valid UTF-8 already?
    return if LJ::is_utf8($$rtext);

    # no. Blot out all non-ASCII chars
    $$rtext =~ s/[\x00\x80-\xff]/\?/g;
    return;
}

# <LJFUNC>
# name: LJ::text_in
# des: do appropriate checks on input text. Should be called on all
#      user-generated text.
# args: text
# des-text: text to check
# returns: 1 if the text is valid, 0 if not.
# </LJFUNC>
sub text_in {
    my $text = shift;

    if ( ref($text) eq "HASH" ) {
        return !( grep { !LJ::is_utf8($_) } values %{$text} );
    }
    if ( ref($text) eq "ARRAY" ) {
        return !( grep { !LJ::is_utf8($_) } @{$text} );
    }
    return LJ::is_utf8($text);
}

# <LJFUNC>
# name: LJ::text_convert
# des: convert old entries/comments to UTF-8 using user's default encoding.
# args: dbs?, text, u, error
# des-dbs: optional. Deprecated; a master/slave set of database handles.
# des-text: old possibly non-ASCII text to convert
# des-u: user hashref of the journal's owner
# des-error: ref to a scalar variable which is set to 1 on error
#            (when user has no default encoding defined, but
#            text needs to be translated).
# returns: converted text or undef on error
# </LJFUNC>
sub text_convert {
    my ( $text, $u, $error ) = @_;

    # maybe it's pure ASCII?
    return $text if LJ::is_ascii($text);

    # load encoding id->name mapping if it's not loaded yet
    LJ::load_codes( { "encoding" => \%LJ::CACHE_ENCODINGS } )
        unless %LJ::CACHE_ENCODINGS;

    if ( $u->{'oldenc'} == 0
        || not defined $LJ::CACHE_ENCODINGS{ $u->{'oldenc'} } )
    {
        $$error = 1;
        return undef;
    }

    # convert!
    my $name = $LJ::CACHE_ENCODINGS{ $u->{'oldenc'} };
    unless ( LJ::ConvUTF8->supported_charset($name) ) {
        $$error = 1;
        return undef;
    }

    return LJ::ConvUTF8->to_utf8( $name, $text );
}

# <LJFUNC>
# name: LJ::text_length
# des: returns both byte length and character length of a string.
#      The function assumes that its argument is a valid UTF-8 string.
# args: text
# des-text: the string to measure
# returns: a list of two values, (byte_length, char_length).
# </LJFUNC>

sub text_length {
    my $text     = shift;
    my $bl       = length($text);
    my $cl       = 0;
    my $utf_char = "([\x00-\x7f]|[\xc0-\xdf].|[\xe0-\xef]..|[\xf0-\xf7]...)";

    while ( $text =~ m/$utf_char/go ) { $cl++; }
    return ( $bl, $cl );
}

# <LJFUNC>
# name: LJ::text_trim
# des: truncate string according to requirements on byte length, char
#      length, or both. "char length" means number of UTF-8 characters.
# args: text, byte_max, char_max
# des-text: the string to trim
# des-byte_max: maximum allowed length in bytes; if 0, there's no restriction
# des-char_max: maximum allowed length in chars; if 0, there's no restriction
# returns: the truncated string.
# </LJFUNC>
sub text_trim {
    my ( $text, $byte_max, $char_max, $didtrim_ref ) = @_;
    $text = defined $text ? LJ::trim($text) : '';
    return $text unless $byte_max or $char_max;

    my $cur      = 0;
    my $utf_char = "([\x00-\x7f]|[\xc0-\xdf].|[\xe0-\xef]..|[\xf0-\xf7]...)";

    # if we don't have a character limit, assume it's the same as the byte limit.
    # we will never have more characters than bytes, but we might have more bytes
    # than characters, so we can't inherit the other way.
    $char_max ||= $byte_max;

    my $fake_scalar;
    my $ref = ref $didtrim_ref ? $didtrim_ref : \$fake_scalar;

    while ( $text =~ m/$utf_char/gco ) {
        unless ($char_max) {
            $$ref = 1;
            last;
        }
        if ( $byte_max and $cur + length($1) > $byte_max ) {
            $$ref = 1;
            last;
        }
        $cur += length($1);
        $char_max--;
    }

    return LJ::trim( substr( $text, 0, $cur ) );
}

# <LJFUNC>
# name: LJ::text_compress
# des: Compresses a chunk of text, to gzip, if configured for site.  Can compress
#      a scalarref in place, or return a compressed copy.  Won't compress if
#      value is too small, already compressed, or size would grow by compressing.
# args: text
# des-text: either a scalar or scalarref
# returns: nothing if given a scalarref (to compress in-place), or original/compressed value,
#          depending on site config.
# </LJFUNC>
sub text_compress {
    my $text = $_[0];
    my $ref  = ref $text;
    die "Invalid reference" if $ref && $ref ne "SCALAR";

    my $tref    = $ref ? $text : \$text;
    my $pre_len = length($$tref);
    unless ( substr( $$tref, 0, 2 ) eq "\037\213" || $pre_len < 100 ) {
        my $gz = Compress::Zlib::memGzip($$tref);
        if ( length($gz) < $pre_len ) {
            $$tref = $gz;
        }
    }

    return $ref ? undef : $$tref;
}

# <LJFUNC>
# name: LJ::text_uncompress
# des: Uncompresses a chunk of text, from gzip, if configured for site.  Can uncompress
#      a scalarref in place, or return a compressed copy.  Won't uncompress unless
#      it finds the gzip magic number at the beginning of the text.
# args: text
# des-text: either a scalar or scalarref.
# returns: nothing if given a scalarref (to uncompress in-place), or original/uncompressed value,
#          depending on if test was compressed or not
# </LJFUNC>
sub text_uncompress {
    my $text = $_[0];
    my $ref  = ref $text;
    die "Invalid reference" if $ref && $ref ne "SCALAR";
    my $tref = $ref ? $text : \$text;

    # check for gzip's magic number
    if ( substr( $$tref, 0, 2 ) eq "\037\213" ) {
        $$tref = Compress::Zlib::memGunzip($$tref);
    }

    return $ref ? undef : $$tref;
}

# function to trim a string containing HTML.  this will auto-close any
# html tags that were still open when the string was truncated
sub html_trim {
    my ( $text, $char_max, $truncated ) = @_;

    return $text unless $char_max;

    my $p = HTML::TokeParser->new( \$text );
    my @open_tags;    # keep track of what tags are open
    my $out         = '';
    my $content_len = 0;

TOKEN:
    while ( my $token = $p->get_token ) {
        my $type = $token->[0];
        my $tag  = $token->[1];
        my $attr = $token->[2];    # hashref

        if ( $type eq "S" ) {
            my $selfclose;

            # start tag
            $out .= "<$tag";

            # assume tags are properly self-closed
            $selfclose = 1 if lc $tag eq 'input' || lc $tag eq 'br' || lc $tag eq 'img';

            # preserve order of attributes. the original order is
            # in element 4 of $token
            foreach my $attrname ( @{ $token->[3] } ) {
                if ( $attrname eq '/' ) {
                    $selfclose = 1;
                    next;
                }

                # FIXME: neaten
                $attr->{$attrname} = LJ::no_utf8_flag( $attr->{$attrname} );
                $out .= " $attrname=\"" . LJ::ehtml( $attr->{$attrname} ) . "\"";
            }

            $out .= $selfclose ? " />" : ">";

            push @open_tags, $tag unless $selfclose;

        }
        elsif ( $type eq 'T' || $type eq 'D' ) {
            my $content = $token->[1];

            if ( length($content) + $content_len > $char_max ) {

                # truncate and stop parsing
                $content = LJ::text_trim( $content, undef, ( $char_max - $content_len ) );
                $out .= $content;
                $$truncated = 1 if ref $truncated;
                last;
            }

            $content_len += length $content;

            $out .= $content;

        }
        elsif ( $type eq 'C' ) {

            # comment, don't care
            $out .= $token->[1];

        }
        elsif ( $type eq 'E' ) {

            # end tag
            if ( $open_tags[-1] eq $tag ) {
                pop @open_tags;
                $out .= "</$tag>";
            }
        }
    }

    $out .= join( "\n", map { "</$_>" } reverse @open_tags );

    return $out;
}

# takes a number, inserts commas where needed
sub commafy {
    my $number = $_[0];
    return '' unless defined $number;
    return $number unless $number =~ /^\d+$/;

    my $punc = LJ::Lang::ml('number.punctuation') || ",";
    $number =~ s/(?<=\d)(?=(\d\d\d)+(?!\d))/$punc/g;
    return $number;
}

# <LJFUNC>
# name: LJ::html_newlines
# des: Replace newlines with HTML break tags.
# args: text
# returns: text, possibly including HTML break tags.
# </LJFUNC>
sub html_newlines {
    my $text = $_[0];
    return '' unless defined $text;

    $text =~ s/\n/<br \/>/gm;
    return $text;
}

# prepend ">" to each line of text to make a blockquote in markdown
# for when text has multiple lines and prepending ">" to the entire
# text will just convert the first line / paragraph
sub markdown_blockquote {
    my $text = $_[0];
    return '' unless defined $text;

    $text =~ s/(^.*)/\> $1/gm;
    return $text;
}

1;
