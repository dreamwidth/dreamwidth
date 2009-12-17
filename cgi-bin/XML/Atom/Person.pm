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

# $Id: Person.pm 5542 2005-09-22 20:28:00Z mahlon $

package XML::Atom::Person;
use strict;

use XML::Atom;
use base qw( XML::Atom::ErrorHandler );
use XML::Atom::Util qw( set_ns first );

sub new {
    my $class = shift;
    my $person = bless {}, $class;
    $person->init(@_) or return $class->error($person->errstr);
    $person;
}

sub init {
    my $person = shift;
    my %param = @_;
    $person->set_ns(\%param);
    my $elem;
    unless ($elem = $param{Elem}) {
        if (LIBXML) {
            my $doc = XML::LibXML::Document->createDocument('1.0', 'utf-8');
            $elem = $doc->createElementNS($person->ns, 'author'); ## xxx
            $doc->setDocumentElement($elem);
        } else {
            $elem = XML::XPath::Node::Element->new('author'); ## xxx
            my $ns = XML::XPath::Node::Namespace->new('#default' => $person->ns);
            $elem->appendNamespace($ns);
        }
    }
    $person->{elem} = $elem;
    $person;
}

sub ns   { $_[0]->{ns} }
sub elem { $_[0]->{elem} }

sub get {
    my $person = shift;
    my($name) = @_;
    my $node = first($person->elem, $person->ns, $name) or return;
    my $val = LIBXML ? $node->textContent : $node->string_value;
    if ($] >= 5.008) {
        require Encode;
        Encode::_utf8_off($val);
    }
    $val;
}

sub set {
    my $person = shift;
    my($name, $val) = @_;
    my $elem;
    unless ($elem = first($person->elem, $person->ns, $name)) {
        if (LIBXML) {
            $elem = XML::LibXML::Element->new($name);
            $elem->setNamespace($person->ns);
        } else {
            $elem = XML::XPath::Node::Element->new($name);
            my $ns = XML::XPath::Node::Namespace->new('#default' => $person->ns);
            $elem->appendNamespace($ns);
        }
        $person->elem->appendChild($elem);
    }
    if (LIBXML) {
        $elem->removeChildNodes;
        $elem->appendChild(XML::LibXML::Text->new($val));
    } else {
        $elem->removeChild($_) for $elem->getChildNodes;
        $elem->appendChild(XML::XPath::Node::Text->new($val));
    }
    $val;
}

sub as_xml {
    my $person = shift;
    if (LIBXML) {
        my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
        $doc->setDocumentElement($person->elem);
        return $doc->toString(1);
    } else {
        return '<?xml version="1.0" encoding="utf-8"?>' . "\n" .
            $person->elem->toString;
    }
}

sub DESTROY { }

use vars qw( $AUTOLOAD );
sub AUTOLOAD {
    (my $var = $AUTOLOAD) =~ s!.+::!!;
    no strict 'refs';
    *$AUTOLOAD = sub {
        @_ > 1 ? $_[0]->set($var, @_[1..$#_]) : $_[0]->get($var)
    };
    goto &$AUTOLOAD;
}

1;
__END__

=head1 NAME

XML::Atom::Person - Author or contributor object

=head1 SYNOPSIS

    my $author = XML::Atom::Person->new;
    $author->email('foo@example.com');
    $author->name('Foo Bar');
    $entry->author($author);

=head1 DESCRIPTION

I<XML::Atom::Person> represents an author or contributor element in an
Atom feed or entry.

=cut
