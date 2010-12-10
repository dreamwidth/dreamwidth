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

# $Id: Atom.pm 5542 2005-09-22 20:28:00Z mahlon $

package XML::Atom;
use strict;

BEGIN {
    @XML::Atom::EXPORT = qw( LIBXML );
    if (eval { require XML::LibXML }) {
        *{XML::Atom::LIBXML} = sub() {1};
    } else {
        require XML::XPath;
        *{XML::Atom::LIBXML} = sub() {0};
    }
    local $^W = 0;
    *XML::XPath::Function::namespace_uri = sub {
        my $self = shift;
        my($node, @params) = @_;
        my $ns = $node->getNamespace($node->getPrefix);
        if (!$ns) {
            $ns = ($node->getNamespaces)[0];
        }
        XML::XPath::Literal->new($ns ? $ns->getExpanded : '');
    };
}

use base qw( XML::Atom::ErrorHandler Exporter );

# This is actually version 0.13_01, but I'm renaming it to 0.13
# so our Atom version checks don't complain about non-numeric comparisons.
our $VERSION = '0.13';

package XML::Atom::Namespace;
use strict;

sub new {
    my $class = shift;
    my($prefix, $uri) = @_;
    bless { prefix => $prefix, uri => $uri }, $class;
}

sub DESTROY { }

our $AUTOLOAD;
sub AUTOLOAD {
    (my $var = $AUTOLOAD) =~ s!.+::!!;
    no strict 'refs';
    ($_[0], $var);
}

1;
__END__

=head1 NAME

XML::Atom - Atom feed and API implementation

=head1 SYNOPSIS

    use XML::Atom;

=head1 DESCRIPTION

Atom is a syndication, API, and archiving format for weblogs and other
data. I<XML::Atom> implements the feed format as well as a client for the
API.

=head1 LICENSE

I<XML::Atom> is free software; you may redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR & COPYRIGHT

Except where otherwise noted, I<XML::Atom> is Copyright 2003-2005
Benjamin Trott, cpan@stupidfool.org. All rights reserved.

=head1 CO-MAINTAINER

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=cut
