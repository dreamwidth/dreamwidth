#!/usr/bin/perl

# This file contains an asPHP function for each Node subclass in the S2 compiler.
# If new nodes are added to the S2 compiler in future, this will need to be updated.

package S2::Node;

sub asPHP {
    die "asPHP not implemented for $_[0]";
}

sub asPHP_bool {
    my ($this, $bp, $o) = @_;
    my $ck = $S2::CUR_COMPILER->{'checker'};
    my $s2type = $this->getType($ck);

    # already boolean
    if ($s2type->equals($S2::Type::BOOL) || $s2type->equals($S2::Type::INT)) {
        $this->asPHP($bp, $o);
        return;
    }
    
    # S2 semantics and perl semantics differ ("0" is true in S2)
    if ($s2type->equals($S2::Type::STRING)) {
        $o->write("((");
        $this->asPHP($bp, $o);
        $o->write(") !== '')");
        return;
    }

    # is the object defined?
    if ($s2type->isSimple()) {
        $o->write("\$this->is_object_defined(");
        $this->asPHP($bp, $o);
        $o->write(")");
        return;
    }

    # does the array have elements?
    if ($s2type->isArrayOf() || $s2type->isHashOf()) {
        $o->write("(!empty(");
        $this->asPHP($bp, $o);
        $o->write("))");
        return;
    }

    S2::error($this, "Unhandled internal case for NodeTerm::asPHP_bool()");
}

package S2::NodeArguments;

sub asPHP {
    my ($this, $bp, $o, $make_array) = @_;
    $make_array = 1 unless defined($make_array);

    $o->write("array(") if $make_array;
    my $didFirst = 0;
    foreach my $n (@{$this->{'args'}}) {
        $o->write(", ") if $didFirst++;
        $n->asPHP($bp, $o);
    }
    $o->write(")") if $make_array;

}

package S2::NodeArrayLiteral;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->writeln("array(");
    $o->tabIn();

    my $size = scalar @{$this->{'vals'}};
    for (my $i=0; $i<$size; $i++) {
        $o->tabwrite("");
        if ($this->{'isHash'}) {
            $this->{'keys'}->[$i]->asPHP($bp, $o);
            $o->write(" => ");
        }
        $this->{'vals'}->[$i]->asPHP($bp, $o);
        $o->writeln(",");
    }
    $o->tabOut();
    $o->tabwrite(")");
}

package S2::NodeAssignExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asPHP($bp, $o);
    $o->write(" = ");
    $this->{'rhs'}->asPHP($bp, $o);

}

package S2::NodeBranchStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    if ($this->{type} == $S2::TokenKeyword::BREAK) {
        $o->tabwriteln("break;");
    }
    else {
        $o->tabwriteln("continue;");
    }
}

package S2::NodeClass;

sub asPHP {
    my ($this, $bp, $o) = @_;

    # {TODO}
}

package S2::NodeClassVarDecl;

sub asPHP {
    my ($this, $bp, $o) = @_;

    # {TODO}
}

package S2::NodeCondExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->write("(");
    $this->{'test_expr'}->asPHP_bool($bp, $o);
    $o->write(" ? ");
    $this->{'true_expr'}->asPHP($bp, $o);
    $o->write(" : ");
    $this->{'false_expr'}->asPHP($bp, $o);
    $o->write(")");
}

package S2::NodeDeleteStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("unset(");
    $this->{'var'}->asPHP($bp, $o);
    $o->writeln(");");
}

package S2::NodeEqExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asPHP($bp, $o);
    if ($this->{'op'} == $S2::TokenPunct::EQ) {
        $o->write(" === ");
    } else {
        $o->write(" !== ");
    }
    $this->{'rhs'}->asPHP($bp, $o);

}

package S2::NodeExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;
    $this->{'expr'}->asPHP($bp, $o);
}

package S2::NodeExprStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("");
    $this->{'expr'}->asPHP($bp, $o);
    $o->writeln(";");
}

package S2::NodeForeachStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("foreach (");

    $o->write("$this->get_string_characters(") if ($this->{'isString'});
    $this->{'listexpr'}->asPHP($bp, $o);
    $o->write(")") if ($this->{'isString'});
    
    $o->write(" as ");

    $this->{'vardecl'}->asPHP($bp, $o) if $this->{'vardecl'};
    $this->{'varref'}->asPHP($bp, $o) if $this->{'varref'};

    if ($this->{'isHash'}) {
        $o->write(" => $__dummy");
    }

    $o->write(") ");

    $this->{'stmts'}->asPHP($bp, $o);
    $o->newline();
}

package S2::NodeFormals;

# Not called directly during code generation

package S2::NodeFunction;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->tabwriteln("// ".S2::Checker::functionID($this->{classname} ? $this->{classname}->getIdent() : undef, $this->{name}->getIdent(), $this->{formals}));

    unless ($this->{'attr'}->{'builtin'}) {

        # We recieve our args in a PHP local variable called $funcargs.
        # When the function is called, we copy the values therein
        # into the local variable array.

        my $argnum = 0;
        if ($this->{'classname'} && ! $this->{'isCtor'}) {
            $o->tabwriteln("\$locals['this'] = \$funcargs[".($argnum++)."];");
        }

        if ($this->{'formals'}) {
            my $nts = $this->{'formals'}->getFormals();
            foreach my $nt (@$nts) {
                $o->tabwriteln("\$locals['".$bp->decorateLocal($nt->getName(), $this->{'stmts'})."'] = \$funcargs[".($argnum++)."];");
            }
        }

        if ($this->{'stmts'}) {
            $this->{'stmts'}->asPHP($bp, $o, 0);
        }
        
    }
    else {
        # Generate a stub for the builtin function

        $o->write("\$this->call_builtin_function(\"");
        if ($this->{'classname'}) {
            $o->write($bp->quoteStringInner($this->{'classname'}));
        }
        $o->write('", "');
        $o->write($bp->quoteStringInner($this->{'name'}->getIdent()).'", $funcargs);');
    }

}

package S2::NodeIfStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    # if
    $o->tabwrite("if (");
    $this->{'expr'}->asPHP_bool($bp, $o);
    $o->write(") ");
    $this->{'thenblock'}->asPHP($bp, $o);
    $o->newline();
    
    # else-if
    my $i = 0;
    foreach my $expr (@{$this->{'elseifexprs'}}) {
        my $block = $this->{'elseifblocks'}->[$i++];
        $o->tabwrite("elseif (");
        $expr->asPHP_bool($bp, $o);
        $o->write(") ");
        $block->asPHP($bp, $o);
        $o->newline();
    }

    # else
    if ($this->{'elseblock'}) {
        $o->tabwrite("else ");
        $this->{'elseblock'}->asPHP($bp, $o);
        $o->newline();
    }
    $o->newline();
}

package S2::NodeIncExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->write("(");
    if ($this->{'bPre'}) { $o->write($this->{'op'}->getPunct()); }
    $this->{'expr'}->asPHP($bp, $o);
    if ($this->{'bPost'}) { $o->write($this->{'op'}->getPunct()); }    
    $o->write(")");
}

package S2::NodeInstanceOf;

sub asPHP {
    my ($this, $bp, $o) = @_;

    if ($this->{exact}) {
        $o->write("((");
        $this->{'expr'}->asPHP($bp, $o);
        $o->write(")['_type'] === ".$bp->quoteString($this->{qClass}).")");
    }
    else {
        $o->write("\$this->object_isa(");
        $this->{'expr'}->asPHP($bp, $o);
        $o->write(",".$bp->quoteString($this->{qClass}).")");
    }
}

package S2::NodeLayerInfo;

# {TODO}

package S2::NodeLogAndExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asPHP_bool($bp, $o);
    $o->write(" && ");
    $this->{'rhs'}->asPHP_bool($bp, $o);
}

package S2::NodeLogOrExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asPHP_bool($bp, $o);
    $o->write(" || ");
    $this->{'rhs'}->asPHP_bool($bp, $o);
}

package S2::NodeNamedType;

# Not called directly during code generation

package S2::NodePrintStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("echo(");
    $this->{'expr'}->asPHP($bp, $o);
    $o->write(" . \"\\n\"") if $this->{'doNewline'};
    $o->writeln(");");
}

package S2::NodeProduct;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->write("floor") if $this->{'op'} == $S2::TokenPunct::DIV;
    $o->write("(");
    $this->{'lhs'}->asPHP($bp, $o);

    if ($this->{'op'} == $S2::TokenPunct::MULT) {
        $o->write(" * ");
    } elsif ($this->{'op'} == $S2::TokenPunct::DIV) {
        $o->write(" / ");
    } elsif ($this->{'op'} == $S2::TokenPunct::MOD) {
        $o->write(" % ");
    }
    
    $this->{'rhs'}->asPHP($bp, $o);
    $o->write(")");

}

package S2::NodeProperty;

# {TODO}

package S2::NodePropertyPair;

# {TODO}

package S2::NodePropGroup;

# {TODO}

package S2::NodeRange;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->write("\$this->make_range_array(");
    $this->{'lhs'}->asPHP($bp, $o);
    $o->write(", ");
    $this->{'rhs'}->asPHP($bp, $o);
    $o->write(")");
}

package S2::NodeRelExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asPHP($bp, $o);

    if ($this->{'op'} == $S2::TokenPunct::LT) {
        $o->write(" < ");
    }
    elsif ($this->{'op'} == $S2::TokenPunct::LTE) {
        $o->write(" <= ");
    }
    elsif ($this->{'op'} == $S2::TokenPunct::GT) {
        $o->write(" > ");
    }
    elsif ($this->{'op'} == $S2::TokenPunct::GTE) {
        $o->write(" >= ");
    }
    
    $this->{'rhs'}->asPHP($bp, $o);

}

package S2::NodeReturnStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("return");
    if ($this->{'expr'}) {
        $o->write(" ");
        $this->{'expr'}->asPHP($bp, $o);
    }
    $o->writeln(";");
}

package S2::NodeSet;

# {TODO}

package S2::NodeStmt;

# Abstract class. Never called in code generation.

package S2::NodeStmtBlock;

sub asPHP {
    my ($this, $bp, $o, $doCurlies) = @_;

    $doCurlies = 1 unless defined $doCurlies;

    if ($doCurlies) {
        $o->writeln("{");
        $o->tabIn();
    }

    foreach my $ns (@{$this->{'stmtlist'}}) {
        $ns->asPHP($bp, $o);
    }

    if ($doCurlies) {
        $o->tabOut();
        $o->tabwrite("}");
    }
}

package S2::NodeSum;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asPHP($bp, $o);

    if ($this->{'myType'} == $S2::Type::STRING) {
        $o->write(" . ");
    } elsif ($this->{'op'} == $S2::TokenPunct::PLUS) {
        $o->write(" + ");
    } elsif ($this->{'op'} == $S2::TokenPunct::MINUS) {
        $o->write(" - ");
    }
     
    $this->{'rhs'}->asPHP($bp, $o);

}

package S2::NodeTerm;

sub asPHP {
    my ($this, $bp, $o) = @_;

    my $type = $this->{'type'};

    if ($type == $S2::NodeTerm::INTEGER) {
        $this->{'tokInt'}->asPHP($bp, $o);
        return;
    }

    if ($type == $S2::NodeTerm::STRING) {
        if (defined $this->{'nodeString'}) {
            $o->write("(");
            $this->{'nodeString'}->asPHP($bp, $o);
            $o->write(")");
            return;
        }
        if ($this->{'ctorclass'}) {
            my $pkg = $bp->getBuiltinPackage() || "S2::Builtin";
            $o->write("\$this->construct_object(".$bp->quoteString($this->{'ctorclass'}).", ");
            $this->{'tokStr'}->asPHP($bp, $o);
            $o->write(")");
            return;
        }
        $this->{'tokStr'}->asPHP($bp, $o);
        return;
    }

    if ($type == $S2::NodeTerm::BOOL) {
        $o->write($this->{'boolValue'} ? "TRUE" : "FALSE");
        return;
    }

    if ($type == $S2::NodeTerm::SUBEXPR) {
        $o->write("(");
        $this->{'subExpr'}->asPHP($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $S2::NodeTerm::ARRAY) {
        $this->{'subExpr'}->asPHP($bp, $o);
        return;
    }

    if ($type == $S2::NodeTerm::NEW) {
        $o->write("array('_type'=>" .
                  $bp->quoteString($this->{'newClass'}->getIdent()) .
                  ")");
        return;
    }

    if ($type == $S2::NodeTerm::NEWNULL) {
        $o->write("NULL");
        return;
    }

    if ($type == $S2::NodeTerm::REVERSEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("array_reverse(");
            $this->{'subExpr'}->asPHP($bp, $o);
            $o->write(")");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("strrev(");
            $this->{'subExpr'}->asPHP($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $S2::NodeTerm::SIZEFUNC) {
        if ($this->{'subType'}->isArrayOf() || $this->{'subType'}->isHashOf()) {
            $o->write("count(");
            $this->{'subExpr'}->asPHP($bp, $o);
            $o->write(")");
        }
        elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("strlen(");
            $this->{'subExpr'}->asPHP($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $S2::NodeTerm::DEFINEDTEST) {
        $o->write("\$this->is_object_defined(");
        $this->{'subExpr'}->asPHP($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $S2::NodeTerm::ISNULLFUNC) {
        $o->write("(!\$this->is_object_defined(");
        $this->{'subExpr'}->asPHP($bp, $o);
        $o->write("))");
        return;
    }

    if ($type == $S2::NodeTerm::VARREF) {
        $this->{'var'}->asPHP($bp, $o);
        return;
    }

    if ($type == $S2::NodeTerm::OBJ_INTERPOLATE) {
        $o->write("\$this->stringify_object(");
        $this->{'var'}->asPHP($bp, $o);
        $o->write(", '$this->{'objint_method'}()'");
        $o->write(", '$this->{'funcClass'}'");
        $o->write(")");
        return;
    }

    if ($type == $S2::NodeTerm::FUNCCALL || $type == $S2::NodeTerm::METHCALL) {

        # builtin functions can be optimized.
        if ($this->{'funcBuiltin'}) {
            # these built-in functions can be inlined.
            if ($this->{'funcID'} eq "string(int)") {
                $this->{'funcArgs'}->asPHP($bp, $o, 0);
                return;
            }
            if ($this->{'funcID'} eq "int(string)") {
                # cast from string to int by adding zero to it
                $o->write("floor(");
                $this->{'funcArgs'}->asPHP($bp, $o, 0);
                $o->write("+0)");
                return;
            }

            $o->write("\$this->call_builtin_function(\"");
            if ($this->{'funcClass'}) {
                $o->write($bp->quoteStringInner($this->{'funcClass'}));
            }
            $o->write('", "');
            $o->write($bp->quoteStringInner($this->{'funcIdent'}->getIdent()).'"');
        } else {

            if ($type == $S2::NodeTerm::METHCALL && ! { map { $_=>1 } qw(string int bool) }->{$this->{'funcClass'}}) {
                $o->write("\$this->call_method(");
                $this->{var}->asPHP($bp, $o);
                $o->write(",");
                $o->write($bp->quoteString($this->{'funcID_noclass'}));
                $o->write(",");
                $o->write($bp->quoteString($this->{'funcClass'}));
                $o->write($this->{'var'}->isSuper() ? ",TRUE" : ",FALSE");
                $o->write(",");
            }
            else {
                $o->write("\$this->call_function(");
                $o->write($bp->quoteString($this->{'funcID'}));
                $o->write(",");
            }


        }

        $o->write("array(");

        # "this" pointer
        if ($type == $S2::NodeTerm::METHCALL) {
            $this->{'var'}->asPHP($bp, $o);
            $o->write(", ");
        }
        
        $this->{'funcArgs'}->asPHP($bp, $o, 0);
        
        $o->write("))");
        return;
    }

    die "Unknown term type";

}

package S2::NodeText;

# Not used directly during code generation

package S2::NodeType;

# Not used directly during code generation

package S2::NodeTypeCastOp;

sub asPHP {
    my ($this, $bp, $o) = @_;

    if (! $this->{downcast}) {
        $this->{expr}->asPHP($bp, $o);
        return;
    }
    
    # For downcasts, need to call function at runtime to ensure the
    # object is of the correct type.
    $o->write("\$this->downcast_object(");
    $this->{'expr'}->asPHP($bp, $o);
    $o->write(",".$bp->quoteString($this->{toClass}).")");
}

package S2::NodeUnaryExpr;

sub asPHP {
    my ($this, $bp, $o) = @_;

    $o->write("(");
    if ($this->{'bNot'}) { $o->write("! "); }
    if ($this->{'bNegative'}) { $o->write("-"); }
    $this->{'expr'}->asPHP($bp, $o);
    $o->write(")");
}

package S2::NodeUnnecessary;

sub asPHP {
    my ($this, $bp, $o) = @_;

    # Do nothing for PHP output.
}

package S2::NodeVarDecl;

sub asPHP {
    my ($this, $bp, $o) = @_;

    # PHP doesn't have declarations, so we compile this just like a VarRef
    $o->write("\$locals[".$bp->quoteString($bp->decorateLocal($this->{'nt'}->getName(), $this->{owningScope}))."]");
}

package S2::NodeVarDeclStmt;

sub asPHP {
    my ($this, $bp, $o) = @_;

    # Since PHP doesn't have declarations, we just initialize the variable.

    $o->tabwrite("");
    $this->{'nvd'}->asPHP($bp, $o);
    if ($this->{'expr'}) {
        $o->write(" = ");
        $this->{'expr'}->asPHP($bp, $o);
    } else {
        my $t = $this->{'nvd'}->getType();
        if ($t->equals($S2::Type::STRING)) {
            $o->write(" = \"\"");
        }
        elsif ($t->equals($S2::Type::INT)) {
            $o->write(" = 0");
        }
        elsif ($t->equals($S2::Type::BOOL)) {
            $o->write(" = FALSE");
        }
        elsif ($t->isArrayOf || $t->isHashOf) {
            $o->write(" = array()");
        }
        else {
            $o->write(" = NULL");
        }
    }
    $o->writeln(";");
}

package S2::NodeVarRef;

sub asPHP {
    my ($this, $bp, $o) = @_;

    if ($this->{'type'} == $LOCAL) {
        $o->write("\$locals");
    } elsif ($this->{'type'} == $OBJECT) {
        $o->write("\$locals['this']");
    } elsif ($this->{'type'} == $PROPERTY) {
        $o->write("\$this->properties");
        $first = 0;
    }

    my $first = 1;

    foreach my $lev (@{$this->{'levels'}}) {
        if ($first && $this->{'type'} == $LOCAL) {
            $o->write("['".$bp->decorateLocal($lev->{'var'}, $this->{owningScope})."']");
        }
        else {
            $o->write("['".$lev->{'var'}."']");
        }

        foreach my $d (@{$lev->{'derefs'}}) {
            $o->write("["); # [ or {
            $d->{'expr'}->asPHP($bp, $o);
            $o->write("]");
        }
        
        $first = 0;
    }

    if ($this->{'useAsString'}) {
        $o->write("['as_string']");
    }

}

package S2::TokenStringLiteral;

sub asPHP {
    my ($this, $bp, $o) = @_;
    $o->write($bp->quoteString($this->{'text'}));
}

package S2::TokenIntegerLiteral;

sub asPHP {
    my ($this, $bp, $o) = @_;
    $o->write($this->{'chars'});
}

1;
