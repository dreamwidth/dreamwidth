#!/usr/bin/perl
#

package S2::TokenKeyword;

use strict;
use S2::Token;
use vars qw($VERSION @ISA %keywords);

$VERSION = '1.0';
@ISA = qw(S2::TokenIdent);

%keywords = ();
foreach my $kw (qw(class else elseif function if builtin
                   property propgroup set static var while foreach while for print
                   println not and or xor layerinfo extends
                   return delete defined new true false reverse
                   size isnull null readonly instanceof as isa break continue
                   push pop)) {
    my $uc = uc($kw);
    eval "use vars qw(\$$uc); \$keywords{\"$kw\"} = \$$uc = S2::TokenKeyword->new(\"$kw\");";
}

sub new
{
    my ($class, $ident) = @_;
    bless {
        'chars' => $ident,
    }, $class;
}

sub tokenFromString
{
    my ($class, $ident) = @_;
    return $keywords{$ident};
}

sub toString
{
    my $this = shift;
    "[TokenKeyword] = $this->{'chars'}";
}

sub asHTML
{
    my ($this, $o) = @_;
    $o->write("<span class=\"k\">$this->{'chars'}</span>");
}

1;

