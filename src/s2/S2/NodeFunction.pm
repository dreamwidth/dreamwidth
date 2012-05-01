#!/usr/bin/perl
#

package S2::NodeFunction;

use strict;
use S2::Node;
use S2::NodeFormals;
use S2::NodeStmtBlock;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub cleanForFreeze {
    my $this = shift;
    delete $this->{'tokenlist'};
    delete $this->{'docstring'};
    $this->{'formals'}->cleanForFreeze() if $this->{'formals'};
    $this->{'rettype'}->cleanForFreeze() if $this->{'rettype'};
}

sub getDocString { shift->{'docstring'}; }

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::FUNCTION;
}

sub parse {
    my ($class, $toker, $isDecl) = @_;
    my $n = new S2::NodeFunction;

    # get the function keyword
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::FUNCTION));

    # is the builtin keyword on?
    # this is the old way, but still supported.  the new way
    # is function attributes in brackets.
    if ($toker->peek() == $S2::TokenKeyword::BUILTIN) {
        $n->{'attr'}->{'builtin'} = 1;
        $n->eatToken($toker);
    }

    # the class name or function name (if no class)
    $n->{'name'} = $n->getIdent($toker);

    # check for a double colon
    if ($toker->peek() == $S2::TokenPunct::DCOLON) {
        # so last ident was the class name
        $n->{'classname'} = $n->{'name'};
        $n->eatToken($toker);
        $n->{'name'} = $n->getIdent($toker);
    }

    # Argument list is optional.
    if ($toker->peek() == $S2::TokenPunct::LPAREN) {
        $n->addNode($n->{'formals'} = S2::NodeFormals->parse($toker));
    }

    # Attribute list is optional
    if ($toker->peek() == $S2::TokenPunct::LBRACK) {
        $n->eatToken($toker);
        while ($toker->peek() && $toker->peek() != $S2::TokenPunct::RBRACK) {
            my $t = $n->eatToken($toker);
            next if $t == $S2::TokenPunct::COMMA;
            S2::error($t, "Expecting an identifer for an attribute")
                unless $t->isa("S2::TokenIdent");
            my $attr = $t->getIdent();
            unless ($attr eq "builtin" ||   # implemented by system, not in S2
                    $attr eq "fixed" ||     # can't be overridden in derived or same layers
                    $attr eq "notags") {    # return from untrusted layers pass through S2::notags()
                S2::error($t, "Unknown function attribute '$attr'");
            }
            $n->{'attr'}->{$attr} = 1;
        }
        $n->requireToken($toker, $S2::TokenPunct::RBRACK);
    }

    # return type is optional too.
    if ($toker->peek() == $S2::TokenPunct::COLON) {
        $n->requireToken($toker, $S2::TokenPunct::COLON);
        $n->addNode($n->{'rettype'} = S2::NodeType->parse($toker));
    }

    # docstring
    if ($toker->peek()->isa('S2::TokenStringLiteral')) {
        $n->{'docstring'} = $n->eatToken($toker)->getString();
    }

    # if inside a class declaration, only a declaration now.
    if ($isDecl || $n->{'attr'}->{'builtin'}) {
        $n->requireToken($toker, $S2::TokenPunct::SCOLON);
        return $n;
    }

    # otherwise, keep parsing the function definition.
    $n->{'stmts'} = parse S2::NodeStmtBlock $toker;
    $n->addNode($n->{'stmts'});

    return $n;
}

sub getFormals { shift->{'formals'}; }
sub getName { shift->{'name'}->getIdent(); }
sub getReturnType {
    my $this = shift;
    return $this->{'rettype'} ? $this->{'rettype'}->getType() : $S2::Type::VOID;
}

sub check {
    my ($this, $l, $ck) = @_;

    # keep a reference to the checker for later
    $this->{'ck'} = $ck;

    # reset the functionID -> local funcNum mappings
    $ck->resetFunctionNums();

    # tell the checker we've seen a function now so it knows
    # later to complain if it then sees a new class declaration.
    # (builtin functions are okay)
    $ck->setHitFunction(1) unless $this->{'attr'}->{'builtin'};

    my $funcName = $this->{'name'}->getIdent();
    my $cname = $this->className();
    my $funcID = S2::Checker::functionID($cname, $funcName, $this->{'formals'});
    my $t = $this->getReturnType();

    $ck->setInFunction($funcID);

    if ($cname && $cname eq $funcName) {
        $this->{'isCtor'} = 1;
    }

    if ($ck->isFuncBuiltin($funcID)) {
        S2::error($this, "Can't override built-in functions");
    }

    if ($ck->checkFuncAttr($funcID, "fixed") && $l->getType() ne "core") {
        S2::error($this, "Can't override functions with the 'fixed' attribute.");
    }

    if ($this->{'attr'}->{'builtin'} && $l->getType() ne "core") {
        S2::error($this, "Only core layers can declare builtin functions");
    }

    # if this function is global, no declaration is done, but if
    # this is class-scoped, we must check the class exists and
    # that it declares this function.
    if ($cname) {
        my $nc = $ck->getClass($cname);
        unless ($nc) {
            S2::error($this, "Can't declare function $funcID for ".
                      "non-existent class '$cname'");
        }

        my $et = $ck->functionType($funcID);
        unless ($et || ($l->getType() eq "layout" &&
                        $funcName =~ /^lay_/)) {
            S2::error($this, "Can't define undeclared object function $funcID");
        }

        # find & register all the derivative names by which this function
        # could be called.
        my $dercs = $nc->getDerClasses();
        my $fvs = S2::NodeFormals::variations($this->{'formals'}, $ck);
        foreach my $dc (@$dercs) {  # DerItem
            my $c = $dc->{'nc'}; # NodeClass
            foreach my $fv (@$fvs) {
                my $derFuncID = S2::Checker::functionID($c->getName(), $this->getName(), $fv);
                $ck->setFuncDistance($derFuncID, { 'nf' => $this, 'dist' => $dc->{'dist'} });
                $ck->addFunction($derFuncID, $t, $this->{'attr'});
            }
        }
    } else {
        # non-class function.  register all variations of the formals.
        my $fvs = S2::NodeFormals::variations($this->{'formals'}, $ck);
        foreach my $fv (@$fvs) {
            my $derFuncID = S2::Checker::functionID($cname,
                                                    $this->getName(),
                                                    $fv);
            $ck->setFuncDistance($derFuncID, { 'nf' => $this, 'dist' => 0 });

            unless ($l->isCoreOrLayout() || $ck->functionType($derFuncID)) {
                # only core and layout layers can define new functions
                S2::error($this, "Only core, markup and layout layers can define new functions.");
            }

            $ck->addFunction($derFuncID, $t, $this->{'attr'});
        }
    }

    # check the formals
    $this->{'formals'}->check($l, $ck) if $this->{'formals'};


    # check the statement block
    if ($this->{'stmts'}) {
        # prepare stmts to be checked
        $this->{'stmts'}->setReturnType($t);

        # make sure $this is accessible in a class method
        # FIXME: not in static functions, once we have static functions
        if ($cname) {
            $this->{'stmts'}->addLocalVar("this", new S2::Type($cname), "UNDECORATED");
        } else {
            $this->{'stmts'}->addLocalVar("this", $S2::Type::VOID, "UNDECORATED");  # prevent its use
        }

        # make sure $this is accessible in a class method
        # that has a parent.
        my $pname = $ck->getParentClassName($cname); # String
        if (defined $pname) {
            $this->{'stmts'}->addLocalVar("super", new S2::Type($pname), "UNDECORATED");
        } else {
            $this->{'stmts'}->addLocalVar("super", $S2::Type::VOID, "UNDECORATED");  # prevent its use
        }

        $this->{'formals'}->populateScope($this->{'stmts'}) if $this->{'formals'};

        $ck->setCurrentFunctionClass($cname);   # for $.member lookups
        $ck->pushLocalBlock($this->{'stmts'});
        $this->{'stmts'}->check($l, $ck);
        $ck->popLocalBlock();
    }

    # remember the funcID -> local funcNum mappings for the backend
    $this->{'funcNames'} = $ck->getFuncNames();
    $ck->setInFunction(0);
}

sub asS2 {
    my ($this, $o) = @_;
    die "not done";
}

sub attrsJoined {
    my $this = shift;
    return join(',', keys %{$this->{'attr'} || {}});
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    unless ($this->{'classname'}) {
        if ($bp->oo) {
            $o->tabwrite("\$lay->register_global_function(");
        }
        else {
            $o->tabwrite("register_global_function(".$bp->getLayerIDString().",");
        }
        $o->tabwrite($bp->quoteString($this->{'name'}->getIdent() . ($this->{'formals'} ? $this->{'formals'}->toString() : "()")) . "," .
                     $bp->quoteString($this->getReturnType()->toString()));
        $o->write(", " . $bp->quoteString($this->{'docstring'}));
        $o->write(", " . $bp->quoteString($this->attrsJoined));

        $o->writeln(");");
    }

    return if $this->{'attr'}->{'builtin'} && ! $bp->oo;

    if ($bp->oo) {
        $o->tabwrite("\$lay->register_function([");
    }
    else {
        $o->tabwrite("register_function(".$bp->getLayerIDString().", [");
    }

    # declare all the names by which this function would be called:
    # its base name, then all derivative classes which aren't already
    # used.
    foreach my $funcID (@{$this->{'ck'}->getFuncIDs($this)}) {
        $o->write($bp->quoteString($funcID) . ", ");
    }

    $o->writeln("], sub {");
    $o->tabIn();

    # the first time register_function is run, it'll find the
    # funcNames for this session and save those in a list and then
    # return the sub which is a closure and will have fast access
    # to that num -> num hash.  (benchmarking showed two
    # hashlookups on ints was faster than one on strings)

    # The OO mode doesn't use _l2g_func right now, but we still generate
    # the extra wrapped sub so that we can use it in future.
    unless ($bp->oo) {
        if (scalar(@{$this->{'funcNames'}})) {
            $o->tabwriteln("my \@_l2g_func = ( undef, ");
            $o->tabIn();
            foreach my $id (@{$this->{'funcNames'}}) {
                $o->tabwriteln("get_func_num(" .
                               $bp->quoteString($id) . "),");
            }
            $o->tabOut();
            $o->tabwriteln(");");
        }
    }

    if ($this->{'attr'}->{'builtin'}) {
        # Due to an if statement above, this only actually runs in oo mode

        $o->tabwrite("return \\&");

        my $pkg = $bp->getBuiltinPackage() || "S2::Builtin";
        $o->write("${pkg}::");
        if ($this->{'classname'}) {
            $o->write("$this->{'classname'}__");
        }
        $o->write($this->{'name'}->getIdent());

        $o->writeln(";");
    }
    else {
        # now, return the closure
        $o->tabwriteln("return sub {");
        $o->tabIn();

        unless ($bp->oo) {
            # now dump the recursion depth checker
            $o->tabwriteln("S2::check_depth() if ++\$S2::sub_ctr % \$S2::depth_check_every == 0;");
        }

        # setup function argument/ locals
        $o->tabwrite("my (\$_ctx");
        if ($this->{'classname'} && ! $this->{'isCtor'}) {
            $o->write(", \$this");
        }

        if ($this->{'formals'}) {
            my $nts = $this->{'formals'}->getFormals();
            foreach my $nt (@$nts) {
                $o->write(", \$" . $nt->getName());
            }
        }

        $o->writeln(") = \@_;");
        # end function locals

        $this->{'stmts'}->asPerl($bp, $o, 0);

        $o->tabOut();
        $o->tabwriteln("};");
    }

    # end the outer sub
    $o->tabOut();
    $o->tabwriteln("});");

}

sub toString {
    my $this = shift;
    return $this->className() . "...";
}

sub isBuiltin { shift->{'builtin'}; }

# private
sub className {
    my $this = shift;
    return undef unless $this->{'classname'};
    return $this->{'classname'}->getIdent();

}

# private
sub totalName {
    my $this = shift;
    my $sb;
    my $clas = $this->className();
    $sb .= "${clas}::" if $clas;
    $sb .= $this->{'name'}->getIdent();
    return $sb;
}

# called by NodeClass
sub registerFunction {
    my ($this, $ck, $cname) = @_;

    my $fname = $this->getName();
    my $funcID = S2::Checker::functionID($cname, $fname,
                                         $this->{'formals'});
    my $et = $ck->functionType($funcID);
    my $rt = $this->getReturnType();

    # check that function is either currently undefined or
    # defined with the same type, otherwise complain
    if ($et && ! $et->equals($rt)) {
        S2::error($this, "Can't redefine function '$fname' with return ".
                  "type of '" . $rt->toString . "' masking ".
                  "earlier definition of type '". $et->toString ."'.");
    }

    $ck->addFunction($funcID, $rt, $this->{'attr'});  # Register
}

__END__


    public void asS2 (Indenter o)
    {
        o.tabwrite("function " + totalName());
        if (formals != null) {
            o.write(" ");
            formals.asS2(o);
        }
        if (rettype != null) {
            o.write(" : ");
            rettype.asS2(o);
        }
        if (stmts != null) {
            o.write(" ");
            stmts.asS2(o);
            o.newline();
        } else {
            o.writeln(";");
        }
    }



