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

# $Id: Content.pm 5765 2005-10-19 22:51:22Z mahlon $

package XML::Atom::Content;
use strict;
use base qw( XML::Atom::ErrorHandler );

use Encode;
use XML::Atom;
use XML::Atom::Util qw( set_ns remove_default_ns hack_unicode_entity );
use MIME::Base64 qw( encode_base64 decode_base64 );

sub new {
    my $class = shift;
    my $content = bless {}, $class;
    $content->init(@_) or return $class->error($content->errstr);
    $content;
}

sub init {
    my $content = shift;
    my %param = @_ == 1 ? (Body => $_[0]) : @_;
    $content->set_ns(\%param);
    my $elem;
    unless ($elem = $param{Elem}) {
        if (LIBXML) {
            my $doc = XML::LibXML::Document->createDocument('1.0', 'utf-8');
            $elem = $doc->createElementNS($content->ns, 'content');
            $doc->setDocumentElement($elem);
        } else {
            $elem = XML::XPath::Node::Element->new('content');
        }
    }
    $content->{elem} = $elem;
    if ($param{Body}) {
        $content->body($param{Body});
    }
    if ($param{Type}) {
        $content->type($param{Type});
    }
    $content;
}

sub ns   { $_[0]->{ns} }
sub elem { $_[0]->{elem} }

sub type {
    my $content = shift;
    if (@_) {
        $content->elem->setAttribute('type', shift);
    }
    $content->elem->getAttribute('type');
}

sub mode {
    my $content = shift;
    $content->elem->getAttribute('mode');
}

sub lang { $_[0]->elem->getAttribute('lang') }
sub base { $_[0]->elem->getAttribute('base') }

sub body {
    my $content = shift;
    my $elem = $content->elem;
    if (@_) {
        my $data = shift;
        if (LIBXML) {
            $elem->removeChildNodes;
        } else {
            $elem->removeChild($_) for $elem->getChildNodes;
        }
        if (!_is_printable($data)) {
            my $raw = Encode::encode("utf-8", $data);
            if (LIBXML) {
               $elem->appendChild(XML::LibXML::Text->new(encode_base64($raw, '')));
            } else {
               $elem->appendChild(XML::XPath::Node::Text->new(encode_base64($raw, '')));
            }
            $elem->setAttribute('mode', 'base64');
        } else {
            my $copy = '<div xmlns="http://www.w3.org/1999/xhtml">' .
                       $data .
                       '</div>';
            my $node;
            eval {
                if (LIBXML) {
                    my $parser = XML::LibXML->new;
                    my $tree = $parser->parse_string($copy);
                    $node = $tree->getDocumentElement;
                } else {
                    my $xp = XML::XPath->new(xml => $copy);
                    $node = (($xp->find('/')->get_nodelist)[0]->getChildNodes)[0]
                        if $xp;
                }
            };
            if (!$@ && $node) {
                $elem->appendChild($node);
                $elem->setAttribute('mode', 'xml');
            } else {
                if (LIBXML) {
                    $elem->appendChild(XML::LibXML::Text->new($data));
                } else {
                    $elem->appendChild(XML::XPath::Node::Text->new($data));
                }
                $elem->setAttribute('mode', 'escaped');
            }
        }
    } else {
        unless (exists $content->{__body}) {
            my $mode = $elem->getAttribute('mode') || 'xml';
            if ($mode eq 'xml') {
                my @children = grep ref($_) =~ /Element/,
                    LIBXML ? $elem->childNodes : $elem->getChildNodes;
                if (@children) {
                    if (@children == 1 && $children[0]->getLocalName eq 'div') {
                        @children =
                            LIBXML ? $children[0]->childNodes :
                                     $children[0]->getChildNodes
                    }
                    $content->{__body} = '';
                    for my $n (@children) {
                        remove_default_ns($n) if LIBXML;
                        $content->{__body} .= $n->toString(LIBXML ? 1 : 0);
                    }
                } else {
                    $content->{__body} = LIBXML ? $elem->textContent : $elem->string_value;
                }
                if ($] >= 5.008) {
                    $content->{__body} = hack_unicode_entity($content->{__body});
                }
            } elsif ($mode eq 'base64') {
                my $raw = decode_base64(LIBXML ? $elem->textContent : $elem->string_value);

                # commented out by Mahlon.  This was breaking LifeBlog image posting.
                # Raw data wouldn't be character encoded, anyway?
                # $content->{__body} = Encode::decode("utf-8", $raw);
                $content->{__body} = $raw;

            } elsif ($mode eq 'escaped') {
                $content->{__body} = LIBXML ? $elem->textContent : $elem->string_value;
            } else {
                $content->{__body} = undef;
            }
        }
    }
    $content->{__body};
}

sub _is_printable {
    my $data = shift;

    # try decoding this $data with UTF-8
    my $decoded =
        ( Encode::is_utf8($data)
          ? $data
          : eval { Encode::decode("utf-8", $data, Encode::FB_CROAK) } );

    return ! $@ && $decoded =~ /^\p{IsPrint}*$/;
}

sub as_xml {
    my $content = shift;
    if (LIBXML) {
        my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
        $doc->setDocumentElement($content->elem);
        return $doc->toString(1);
    } else {
        return $content->elem->toString;
    }
}

1;
