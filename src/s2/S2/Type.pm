#!/usr/bin/perl
#

package S2::Type;

use strict;
use S2::Node;
use S2::Type;
use vars qw($VOID $STRING $INT $BOOL $NULL);

$VOID   = new S2::Type("void", 1);
$STRING = new S2::Type("string", 1);
$INT    = new S2::Type("int", 1);
$BOOL   = new S2::Type("bool", 1);
$NULL   = new S2::Type("null", 1);

sub new {
    my ($class, $base, $final) = @_;
    my $this = {
        'baseType' => $base,
        'typeMods' => "",
    };
    $this->{'final'} = 1 if $final;
    bless $this, $class;
}

sub clone {
    my $this = shift;
    my $nt = S2::Type->new($this->{'baseType'});
    $nt->{'typeMods'} = $this->{'typeMods'};
    $nt->{'readOnly'} = $this->{'readOnly'};
    return $nt;
}

# return true if the type can be interpretted in a boolean context
sub isBoolable {
    my $this = shift;

    # everything is boolable but void and null
    #    int:  != 0
    #    bool:  obvious
    #    string:  != ""
    #    Object:  defined
    #    array:  elements > 0
    #    hash:  elements > 0

    return ! $this->equals($VOID) && ! $this->equals($NULL);
}

sub subTypes {
    my ($this, $ck) = @_;
    my $l = [];

    my $nc = $ck->getClass($this->{'baseType'});
    unless ($nc) {
        # no sub-classes.  just return our type.
        push @$l, $this;
        return $l;
    }

    foreach my $der (@{$nc->getDerClasses()}) {
        # add a copy of this type to the list, but with
        # the derivative class type.  that way it
        # saves the varlevels:  A[] .. B[] .. C[], etc
        my $c = $der->{'nc'}->getName();
        my $newt = $this->clone();
        $newt->{'baseType'} = $c;
        push @$l, $newt;
    }

    return $l;
}

sub equals {
    my ($this, $o) = @_;
    return unless $o->isa('S2::Type');
    return $o->{'baseType'} eq $this->{'baseType'} &&
        $o->{'typeMods'} eq $this->{'typeMods'};
}

sub sameMods {
    my ($class, $a, $b) = @_;
    return $a->{'typeMods'} eq $b->{'typeMods'};
}

sub makeArrayOf {
    my ($this) = @_;
    S2::error('', "Internal error") if $this->{'final'};
    S2::error('', "Cannot have an array of ".$this->toString()) unless $this->canBeArray();
    $this->{'typeMods'} .= "[]";
}

sub makeHashOf {
    my ($this) = @_;
    S2::error('', "Internal error") if $this->{'final'};
    S2::error('', "Cannot have an hash of ".$this->toString()) unless $this->canBeHash();
    $this->{'typeMods'} .= "{}";
}

sub canBeHash {
    my ($this) = @_;
    return $this->{'baseType'} ne 'null';
}

sub canBeArray {
    my ($this) = @_;
    return $this->{'baseType'} ne 'null';
}

sub removeMod {
    my ($this) = @_;
    S2::error('', "Internal error") if $this->{'final'};
    $this->{'typeMods'} =~ s/..$//;
}

sub isSimple {
    my ($this) = @_;
    return ! length $this->{'typeMods'};
}

sub isHashOf {
    my ($this) = @_;
    return $this->{'typeMods'} =~ /\{\}$/;
}

sub isArrayOf {
    my ($this) = @_;
    return $this->{'typeMods'} =~ /\[\]$/;
}

sub baseType {
    shift->{'baseType'};
}

sub toString {
    my $this = shift;
    "$this->{'baseType'}$this->{'typeMods'}";
}

sub isPrimitive {
    my $arg = shift;
    my $t;
    if (ref $arg) { $t = $arg; }
    else {
        $t = S2::Type->new($arg);
    }
    return $t->equals($STRING) ||
        $t->equals($INT) ||
        $t->equals($NULL) ||
        $t->equals($BOOL);
}

sub baseIsPrimitive {
    my $self = shift;
    return $self->isPrimitive() ||
           $self->{baseType} eq 'string' ||
           $self->{baseType} eq 'int' ||
           $self->{baseType} eq 'null' ||
           $self->{baseType} eq 'bool';
}

sub isReadOnly {
    shift->{'readOnly'};
}

sub setReadOnly {
    my ($this, $v) = @_;
    S2::error('', "Internal error") if $this->{'final'};
    $this->{'readOnly'} = $v;
}


