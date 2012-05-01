#!/usr/bin/perl
#

package S2::Checker;

use strict;
use vars qw($VERSION);
use Storable;

# version should be incremented whenever any internals change.
# the external mechanisms which serialize checker objects should
# then include in their hash/db/etc the version, so any change
# in version invalidates checker caches and forces a full re-compile
$VERSION = '1.0';

#    // combined (all layers)
#    private Hashtable classes;      // class name    -> NodeClass
#    private Hashtable props;        // property name -> Type
#    private Hashtable funcs;        // FuncID -> return type
#    private Hashtable funcAttr;     // FuncID -> attr string -> Boolean (has attr)
#    private LinkedList localblocks; // NodeStmtBlock scopes .. last is deepest (closest)
#    private Type returnType;
#    private String funcClass;       // current function class
#    private Hashtable derclass;     // classname  -> LinkedList<classname>
#    private boolean inFunction;     // checking in a function now?
#    private boolean crippledFlowControl; // If set, we don't allow "for" or "while" loops

#    // per-layer
#    private Hashtable funcDist;     // FuncID -> [ distance, NodeFunction ]
#    private Hashtable funcIDs;      // NodeFunction -> Set<FuncID>
#    private boolean hitFunction;    // true once a function has been declared/defined
#    private Hashtable methodNoImpl  // Methods which have been declared but not yet implemented (FuncID => 1)
#    private Hashtable propNoSet     // Properties that have been declared but not set

#    // per function
#    private int funcNum = 0;
#    private Hashtable funcNums;     // FuncID -> Integer(funcnum)
#    private LinkedList funcNames;   // Strings

sub new
{
    my $class = shift;
    my $this = {
        'classes' => {},
        'props' => {},
        'funcs' => {},
        'funcAttr' => {},
        'derclass' => {},   # classname -> arrayref<classname>
        'localblocks' => [],
    };
    bless $this, $class;
}

sub cleanForFreeze {
    my $this = shift;
    delete $this->{'funcDist'};
    delete $this->{'funcIDs'};
    delete $this->{'hitFunction'};
    delete $this->{'funcNum'};
    delete $this->{'funcNums'};
    delete $this->{'funcNames'};
    $this->{'localBlocks'} = [];
    delete $this->{'returnType'};
    delete $this->{'funcClass'};
    delete $this->{'inFunction'};
    delete $this->{'crippledFlowControl'};
    foreach my $nc (values %{$this->{'classes'}}) {
        $nc->cleanForFreeze();
    }
}

sub clone {
    my $this = shift;
    
    $this->cleanForFreeze();

    # HACK: Throw it through Storable and back to get a deep copy of the object.
    return Storable::thaw(Storable::freeze($this));
}

sub crippledFlowControl {
    my ($this, $set) = @_;
    
    return $this->{crippledFlowControl} = ($set ? 1 : 0) if defined($set);
    return $this->{crippledFlowControl};
}

sub addClass {
    my ($this, $name, $nc) = @_;
    $this->{'classes'}->{$name} = $nc;

    # make sure that the list of classes that derive from 
    # this one exists.
    $this->{'derclass'}->{$name} ||= [];

    # and if this class derives from another, add ourselves
    # to that list
    my $parent = $nc->getParentName();
    if ($parent) {
        my $l = $this->{'derclass'}->{$parent};
        die "Internal error: can't append to empty list" unless $l;
        push @$l, $name;
    }
}

sub getClass {
    my ($this, $name) = @_;
    return undef unless $name;
    return $this->{'classes'}->{$name};
}

sub getParentClassName {
    my ($this, $name) = @_;
    my $nc = $this->getClass($name);
    return undef unless $nc;
    return $nc->getParentName();
}

sub isValidType {
    my ($this, $t) = @_;
    return 0 unless $t;
    return 1 if $t->baseIsPrimitive();
    return defined $this->getClass($t->baseType());
}

# property functions
sub addProperty {
    my ($this, $name, $t, $builtin) = @_;
    $this->{'props'}->{$name} = $t;
    $this->{'prop_builtin'}->{$name} = 1 if $builtin;
}

sub propertyType {
    my ($this, $name) = @_;
    return $this->{'props'}->{$name};
}

sub propertyBuiltin {
    my ($this, $name) = @_;
    return $this->{'prop_builtin'}->{$name};
}

# return type functions (undef means no return type)
sub setReturnType {
    my ($this, $t) = @_;
    $this->{'returnType'} = $t;
}

sub getReturnType {
    shift->{'returnType'};
}

# funtion functions
sub addFunction {
    my ($this, $funcid, $t, $attrs) = @_;
    my $existing = $this->functionType($funcid);
    if ($existing && ! $existing->equals($t)) {
        S2::error(undef, "Can't override function '$funcid' with new return type.");
    }
    $this->{'funcs'}->{$funcid} = $t;

    # enable all attributes specified
    if (defined $attrs) {
        die "Internal error.  \$attrs is defined, but not a hashref."
            if ref $attrs ne "HASH";
        foreach my $k (keys %$attrs) {
            $this->{'funcAttr'}->{$funcid}->{$k} = 1;
        }
    }
}

sub functionType {
    my ($this, $funcid) = @_;
    $this->{'funcs'}->{$funcid};
}

sub checkFuncAttr {
    my ($this, $funcid, $attr) = @_;
    $this->{'funcAttr'}->{$funcid}->{$attr};
}

sub isFuncBuiltin {
    my ($this, $funcid) = @_;
    return $this->checkFuncAttr($funcid, "builtin");
}

# returns true if there's a string -> t class constructor
sub isStringCtor {
    my ($this, $t) = @_;
    return 0 unless $t && $t->isSimple();
    my $cname = $t->baseType();
    my $ctorid = "${cname}::${cname}(string)";
    my $rt = $this->functionType($ctorid);
    return $rt && $rt->isSimple() && $rt->baseType() eq $cname &&
        $this->isFuncBuiltin($ctorid);
}

# setting/getting the current function class we're in
sub setCurrentFunctionClass { my $this = shift; $this->{'funcClass'} = shift; }
sub getCurrentFunctionClass { shift->{'funcClass'}; }

# setting/getting whether in a function now
sub setInFunction { my $this = shift; $this->{'inFunction'} = shift; }
sub getInFunction { shift->{'inFunction'}; }

sub pushBreakable { shift->{inBreakable}++; }
sub popBreakable { shift->{inBreakable}--; }
sub inBreakable { return shift->{inBreakable} > 0; }

# variable lookup
sub pushLocalBlock {
    my ($this, $nb) = @_;  # nb  = NodeStmtBlock
    push @{$this->{'localblocks'}}, $nb;
}
sub popLocalBlock {
    my ($this) = @_;
    pop @{$this->{'localblocks'}};
}

sub getLocalScope {
    my $this = shift;
    return undef unless @{$this->{'localblocks'}};
    return $this->{'localblocks'}->[-1];
}

sub localType {
    my ($this, $local) = @_;
    return undef unless @{$this->{'localblocks'}};
    foreach my $nb (reverse @{$this->{'localblocks'}}) {
        my $t = $nb->getLocalVar($local);
        return $t if $t;
    }
    return undef;
}

sub getVarScope {
    my ($this, $local) = @_;
    return undef unless @{$this->{'localblocks'}};
    foreach my $nb (reverse @{$this->{'localblocks'}}) {
        my $t = $nb->getLocalVar($local);
        return $nb if $t;
    }
    return undef;
}

sub memberType {
    my ($this, $clas, $member) = @_;
    my $nc = $this->getClass($clas);
    return undef unless $nc;
    return $nc->getMemberType($member);
}

sub setHitFunction { my $this = shift; $this->{'hitFunction'} = shift; }
sub getHitFunction { shift->{'hitFunction'}; }

sub hasDerClasses {
    my ($this, $clas) = @_;
    return scalar @{$this->{'derclass'}->{$clas}};
}

sub getDerClasses {
    my ($this, $clas) = @_;
    return $this->{'derclass'}->{$clas};
}

sub setFuncDistance {
    my ($this, $funcID, $df) = @_; # df = hashref with 'dist' and 'nf' key

    my $existing = $this->{'funcDist'}->{$funcID};

    if (! defined $existing || $df->{'dist'} < $existing->{'dist'}) {
        $this->{'funcDist'}->{$funcID} = $df;

        # keep the funcIDs hashes -> FuncID set up-to-date
        # removing the existing funcID from the old set first
        if ($existing) {
            delete $this->{'funcIDs'}->{$existing->{'nf'}}->{$funcID};
        }
        
        # add to new set
        $this->{'funcIDs'}->{$df->{'nf'}}->{$funcID} = 1;
    }
}

sub getFuncIDs {
    my ($this, $nf) = @_;
    return [ sort keys %{$this->{'funcIDs'}->{$nf}} ];
}

# per function
sub resetFunctionNums {
    my $this = shift;
    $this->{'funcNum'} = 0;
    $this->{'funcNums'} = {};
    $this->{'funcNames'} = [];
}

sub functionNum {
    my ($this, $funcID) = @_;
    my $num = $this->{'funcNums'}->{$funcID};
    unless (defined $num) {
        $num = ++$this->{'funcNum'};
        $this->{'funcNums'}->{$funcID} = $num;
        push @{$this->{'funcNames'}}, $funcID;
    }
    return $num;
}

sub getFuncNums { shift->{'funcNums'}; }
sub getFuncNames { shift->{'funcNames'}; }

# check if type 't' is a subclass of 'w'
sub typeIsa {
    my ($this, $t, $w) = @_;
    return 0 unless S2::Type->sameMods($t, $w);

    my $is = $t->baseType();
    my $parent = $w->baseType();
    while ($is) {
        return 1 if $is eq $parent;
        my $nc = $this->getClass($is);
        $is = $nc ? $nc->getParentName() : undef;
    }
    return 0;
}

# check to see if a class or parents has a "toString()" or "as_string()" method.
# returns the method name found.
sub classHasToString {
    my ($this, $clas) = @_;
    foreach my $methname (qw(toString as_string)) {
        my $et = $this->functionType("${clas}::$methname()");
        return $methname if $et && $et->equals($S2::Type::STRING);
    }
    return undef;
}

# check to see if a class or parents has an "as_string" string member
sub classHasAsString {
    my ($this, $clas) = @_;
    my $et = $this->memberType($clas, "as_string");
    return $et && $et->equals($S2::Type::STRING);
}

# ---------------

sub checkLayer {
    my ($this, $lay) = @_; # lay = Layer

    # initialize layer-specific data structures
    $this->{'funcDist'} = {};  # funcID -> "derItem" hashref ('dist' scalar and 'nf' NodeFormal)
    $this->{'funcIDs'} = {};
    $this->{'hitFunction'} = 0;

    # check to see that they declared the layer type, and that
    # it isn't bogus.
    {
        # what the S2 source says the layer is
        my $dtype = $lay->getDeclaredType();
        S2::error(undef, "Layer type not declared") unless $dtype;
        
        # what type s2compile thinks it is
        my $type = $lay->getType();

        S2::error(undef, "Layer is declared $dtype but expecting a $type layer")
            unless $type eq $dtype;

        # now that we've validated their type is okay
        $lay->setType($dtype);
    }

    my $nodes = $lay->getNodes();
    foreach my $n (@$nodes) {
        $n->check($lay, $this);
    }
}

sub functionID {
    my ($clas, $func, $o) = @_;
    my $sb;
    $sb .= "${clas}::" if $clas;
    $sb .= "$func(";
    if (! defined $o) {
        # do nothing
    } elsif (ref $o && $o->isa('S2::NodeFormals')) {
        $sb .= $o->typeList();
    } else {
        $sb .= $o;
    }
    $sb .= ")";
    return $sb;
}


1;
