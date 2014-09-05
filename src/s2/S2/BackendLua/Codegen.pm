#!/usr/bin/perl

# This file inserts appropriate implementations of asLua()
# in every applicable Node class.

use strict;

package S2::Node;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->tabwriteln("--[[-- ${this}::asLua not implemented --]]");
}

package S2::NodeArguments;

sub asLua {
    my ($this, $bp, $o, $parens) = @_;
    $parens = 1 unless defined $parens;
    $o->write("(") if $parens;
    my $didFirst = 0;
    foreach my $n (@{$this->{'args'}}) {
        $o->write(", ") if $didFirst++;
        $n->asLua($bp, $o);
    }
    $o->write(")") if $parens;
}

package S2::NodeArrayLiteral;

sub asLua {
    my ($this, $bp, $o) = @_;

    my $size = scalar @{$this->{'vals'}};

    if ($size == 0) {
        $o->write("{}");
        return;
    }

    $o->writeln("{");
    $o->tabIn();

    for (my $i=0; $i<$size; $i++) {
        $o->tabwrite("");
        if ($this->{'isHash'}) {
            $this->{'keys'}->[$i]->asLua($bp, $o);
            $o->write(" = ");
        }
        $this->{'vals'}->[$i]->asLua($bp, $o);
        $o->writeln(",");
    }
    $o->tabOut();
    $o->tabwrite("}");
}


package S2::NodeAssignExpr;

sub asLua {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}->asLua($bp, $o);

    my $need_notags = $bp->untrusted() && 
        $this->{'lhs'}->isProperty() &&
        $this->{'lhs'}->getType()->equals($S2::Type::STRING);

    $o->write(" = ");
    $o->write("s2.runtime.notags(") if $need_notags;
    $this->{'rhs'}->asLua($bp, $o);
    $o->write(")") if $need_notags;

}

package S2::NodeClass;

sub asLua {
    my ($this, $bp, $o) = @_;

    # TODO: Add documentation support here too
    
    $o->tabwrite("l:registerClass(".$bp->quoteString($this->getName()));

    if ($this->{'parentName'}) {
        $o->write(", ".$bp->quoteString($this->getParentName()));
    }
    $o->writeln(")");
}

package S2::NodeCondExpr;

# Lua doesn't have anything like this operator, so
# instead there's a runtime helper function.

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->write("s2.runtime.ifop(");
    $this->{'test_expr'}->asLua_bool($bp, $o);
    $o->write(", ");
    $this->{'true_expr'}->asLua($bp, $o);
    $o->write(", ");
    $this->{'false_expr'}->asLua($bp, $o);
    $o->write(")");
}

package S2::NodeDeleteStmt;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("");
    $this->{'var'}->asLua($bp, $o);
    $o->writeln(" = nil");
}

package S2::NodeEqExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asLua($bp, $o);
    if ($this->{'op'} == $S2::TokenPunct::EQ) {
        $o->write(" == ");
    } else {
        $o->write(" ~= ");
    }
    $this->{'rhs'}->asLua($bp, $o);
}

package S2::NodeExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    $this->{'expr'}->asLua($bp, $o);
}

sub asLua_bool {
    my ($this, $bp, $o) = @_;
    my $ck = $S2::CUR_COMPILER->{'checker'};
    my $s2type = $this->getType($ck);
    
    if ($s2type->equals($S2::Type::BOOL)) {
        $this->asLua($bp, $o);
        return;
    }

    if ($s2type->equals($S2::Type::INT)) {
        $o->write("(");
        $this->asLua($bp, $o);
        $o->write(" ~= 0)");
        return;
    }

    if ($s2type->equals($S2::Type::STRING)) {
        $o->write("(");
        $this->asLua($bp, $o);
        $o->write(" ~= \"\")");
        return;
    }

    if ($s2type->isSimple()) {
        $o->write("s2.runtime.isObjectDefined(");
        $this->asLua($bp, $o);
        $o->write(")");
        return;
    }

    if ($s2type->isArrayOf()) {
        $o->write("s2.runtime.isArrayDefined(");
        $this->asLua($bp, $o);
        $o->write(")");
        return;
    }

    if ($s2type->isHashOf()) {
        $o->write("s2.runtime.isHashDefined(");
        $this->asLua($bp, $o);
        $o->write(")");
        return;
    }
    
    $o->write("--[[ Unhandled case in asLua_bool! ]] false");
}

package S2::NodeExprStmt;

# Lua doesn't allow bare expressions as statements, so
# we must wrap them in a no-op function call unless
# it's something legal.

sub asLua {
    my ($this, $bp, $o) = @_;
    
    my $expr = $this->{'expr'};
    if (($expr->isa('S2::NodeTerm')
            && ($expr->{type} == $S2::NodeTerm::FUNCCALL
                || $expr->{type} == $S2::NodeTerm::METHCALL))
         || $expr->isa('S2::NodeAssignExpr')) {
        $this->{'expr'}->asLua($bp, $o);        
    } else {
        $o->tabwrite("s2.runtime.discard(");
        $this->{'expr'}->asLua($bp, $o);
        $o->writeln(")");
    }
}

package S2::NodeForeachStmt;

# NOTE: Due to Lua's design, iterator variables
#     don't "escape" out of the loop scope.
#       Fortunately, few layers use this questionable
#     technique anyway.

sub asLua {
    my ($this, $bp, $o) = @_;

    my $varname;
    if ($this->{'vardecl'}) {
        $varname = sub {
            $o->write($this->{'vardecl'}->{'nt'}->getName());
        };
    }
    else {
        $varname = sub {
            $this->{'varref'}->asLua($bp, $o);
        };
    }
    
    my $realexpr = $this->{'listexpr'}->isa('S2::NodeExpr') ?
                   $this->{'listexpr'}->{expr} :
                   $this->{'listexpr'};

    # Optimise the foreach (x .. y) idion to a lua numeric for
    if ($realexpr->isa('S2::NodeRange')) {
        my $range = $realexpr;
        $o->tabwrite("for ");
        $varname->();
        $o->write(" = ");
        $range->{'lhs'}->asLua($bp, $o);    
        $o->write(",");
        $range->{'rhs'}->asLua($bp, $o);
        $o->write(" ");
    } else {
        $o->tabwrite("for ");

        if ($this->{'isHash'}) {
            $varname->();
            $o->write(" in pairs(");
        } elsif ($this->{'isString'}) {
            $varname->();
            $o->write(" in s2.runtime.stringiter(");
        } else {
            $o->write("___, ");
            $varname->();
            $o->write(" in ipairs(");
        }

        $this->{'listexpr'}->asLua($bp, $o);

        $o->write(") ");
    }

    $this->{'stmts'}->asLua($bp, $o);
    $o->newline();
}

package S2::NodeForStmt;

# Lua doesn't have a for loop in the same vein as C-like languages,
# so we just simplify it to the equivalent while loop.

sub asLua {
    my ($this, $bp, $o) = @_;

    $o->tabwriteln("do");
    $o->tabIn();

    if ($this->{'vardecl'}) {
        $this->{'vardecl'}->asLua($bp, $o);
    }
    else {
        $o->tabwrite("");
        $this->{'initexpr'}->asLua($bp, $o);
        $o->writeln(";");
    }

    $o->tabwrite("while (");
    $this->{'condexpr'}->asPerl($bp, $o);
    $o->writeln(") do");
    $o->tabIn();

    $this->{'stmts'}->asLua($bp, $o, 0);
    $o->newline();

    $o->tabwrite();
    $this->{'iterexpr'}->asPerl($bp, $o);
    $o->writeln(";");

    $o->tabOut();
    $o->tabwriteln("end");
    $o->tabOut();
    $o->tabwriteln("end");

}

package S2::NodeFunction;

sub asLua {
    my ($this, $bp, $o) = @_;
    unless ($this->{'classname'}) {
        # TODO: Spew out global function documentation if docs are enabled
    }

    return if $this->{'attr'}->{'builtin'};

    $o->tabwrite("l:registerFunction(");
    $o->write(($this->{classname} ? $this->{classname}->getIdent()."::" : "") .
              $bp->quoteString($this->{'name'}->getIdent() .
              ($this->{'formals'} ? $this->{'formals'}->toString() : "()")));

    $o->writeln(", function ()");
    $o->tabIn();

    # TODO: maybe throw some pre-resolved functions into the closure here,
    #    but must be careful not to cause new class cascade effects.

    # now, return the closure
    $o->tabwrite("return function (");
        
    # setup function argument/ locals
    $o->write("_ctx");
    if ($this->{'classname'} && ! $this->{'isCtor'}) {
        $o->write(", this");
    }

    if ($this->{'formals'}) {
        my $nts = $this->{'formals'}->getFormals();
        foreach my $nt (@$nts) {
            $o->write(", " . $nt->getName());
        }
    }

    $o->writeln(")");
    # end function locals

    $o->tabIn();
    
    $this->{'stmts'}->asLua($bp, $o, 0);
    $o->tabOut();
    $o->tabwriteln("end");
    
    # end the outer function
    $o->tabOut();
    $o->tabwriteln("end)");
}

package S2::NodeIfStmt;

sub asLua {
    my ($this, $bp, $o) = @_;

    # if
    $o->tabwrite("if (");
    $this->{'expr'}->asLua_bool($bp, $o);
    $o->writeln(") then");
    $o->tabIn();
    $this->{'thenblock'}->asLua($bp, $o, 0);
    $o->tabOut();
        
    # else-if
    my $i = 0;
    foreach my $expr (@{$this->{'elseifexprs'}}) {
        my $block = $this->{'elseifblocks'}->[$i++];
        $o->tabwrite("elseif (");
        $expr->asLua_bool($bp, $o);
        $o->writeln(") then");
        $o->tabIn();
        $block->asLua($bp, $o, 0);
        $o->tabOut();
    }

    # else
    if ($this->{'elseblock'}) {
        $o->tabwriteln("else");
        $o->tabIn();
        $this->{'elseblock'}->asLua($bp, $o, 0);
        $o->tabOut();
    }

    $o->tabwriteln("end");

}

package S2::NodeIncExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    if ($this->{'bPre'}) {
        # Pre-increment is easy
        my $op;
        if ($this->{'op'}->equals($S2::TokenPunct::INCR)) {
            $op = " + 1";
        }
        else {
            $op = " - 1";
        }
        $o->write("(");
        $this->{'expr'}->asLua($bp, $o);
        $o->write(" = ");
        $this->{'expr'}->asLua($bp, $o);
        $o->write($op);
        $o->write(")");
    }
    else {
        # Post-increment needs a helper function
        $o->write("s2.runtime.post");
        if ($this->{'op'}->equals($S2::TokenPunct::INCR)) {
            $o->write("inc(");
        }
        else {
            $o->write("dec(");
        }
        $this->{'expr'}->asLua($bp, $o);
        $o->write(")");
    }
}

package S2::NodeLayerInfo;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->tabwriteln("l:setLayerInfo(" .
                   $bp->quoteString($this->{'key'}) . "," .
                   $bp->quoteString($this->{'val'}) . ")");
}

package S2::NodeLogAndExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asLua($bp, $o);
    $o->write(" and ");
    $this->{'rhs'}->asLua($bp, $o);
}

package S2::NodeLogOrExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asLua($bp, $o);
    $o->write(" or ");
    $this->{'rhs'}->asLua($bp, $o);
}

package S2::NodePrintStmt;

sub asLua {
    my ($this, $bp, $o) = @_;
    if ($bp->untrusted() || $this->{'safe'}) {
        $o->tabwrite("s2.runtime.safePrint(");
    } else {
        $o->tabwrite("s2.runtime.print(");
    }
    $this->{'expr'}->asLua($bp, $o);
    $o->write("..\"\\n\"") if $this->{'doNewline'};
    $o->writeln(");");
}

package S2::NodeProduct;

sub asLua {
    my ($this, $bp, $o) = @_;

    
    if ($this->{'op'} == $S2::TokenPunct::MOD) {
        # No modulus operator in Lua
        
        $o->write("s2.runtime.mod(");
        $this->{'lhs'}->asLua($bp, $o);
        $o->write(" , ");
        $this->{'rhs'}->asLua($bp, $o);
        $o->write(")");
    }
    else {
        $o->write("s2.runtime.int(") if $this->{'op'} == $S2::TokenPunct::DIV;
        $this->{'lhs'}->asLua($bp, $o);

        if ($this->{'op'} == $S2::TokenPunct::MULT) {
            $o->write(" * ");
        } elsif ($this->{'op'} == $S2::TokenPunct::DIV) {
            $o->write(" / ");
        }

        $this->{'rhs'}->asLua($bp, $o);
        $o->write(")") if $this->{'op'} == $S2::TokenPunct::DIV;     
    }
}

package S2::NodeProperty;

# TODO: Output properties if the property option is on

sub asLua {
    # For now, do nothing.
}

package S2::NodePropGroup;

# TODO: Output property groups if the property option is on
# For now, must see if there are any property assignments inside.

sub asLua {
    my ($this, $bp, $o) = @_;

    foreach (@{$this->{'list_sets'}}) {
        $_->asLua($bp, $o);
    }
}

package S2::NodeRange;

# This operator doesn't exist in Lua (or in any other language
# than Perl, as far as I know!) so we need another runtime
# library helper.

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->write("s2.runtime.makerange(");
    $this->{'lhs'}->asLua($bp, $o);
    $o->write(", ");
    $this->{'rhs'}->asLua($bp, $o);
    $o->write(")");
}

package S2::NodeRelExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asLua($bp, $o);

    if ($this->{'op'} == $S2::TokenPunct::LT) {
        $o->write(" < ");
    } elsif ($this->{'op'} == $S2::TokenPunct::LTE) {
        $o->write(" <= ");
    } elsif ($this->{'op'} == $S2::TokenPunct::GT) {
        $o->write(" > ");
    } elsif ($this->{'op'} == $S2::TokenPunct::GTE) {
        $o->write(" >= ");
    }
    
    $this->{'rhs'}->asLua($bp, $o);
}

package S2::NodeReturnStmt;

# Lua only allows return to occur at the end of a block,
# so this emits "do return end" unless the caller tells
# us we're the last statement by setting the $atend
# parameter.

sub asLua {
    my ($this, $bp, $o, $atend) = @_;
    $o->tabwrite("");
    $o->write("do ") unless $atend;
    $o->write("return");
    if ($this->{'expr'}) {
        my $need_notags = $bp->untrusted() && $this->{'notags_func'};
        $o->write(" ");
        $o->write("s2.runtime.notags(") if $need_notags;
        $this->{'expr'}->asLua($bp, $o);
        $o->write(")") if $need_notags;
    }
    $o->write(" end") unless $atend;
    $o->writeln("");
}

package S2::NodeSet;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("l:setProperty(".
                 $bp->quoteString($this->{'key'}).",");
    $this->{'value'}->asLua($bp, $o);
    $o->writeln(")");
    return;
}

package S2::NodeStmtBlock;

sub asLua {
    my ($this, $bp, $o, $delimit) = @_;
    $delimit = 1 unless defined $delimit;

    if ($delimit) {
        $o->writeln("do");
        $o->tabIn();
    }

    my $stmtc = $#{$this->{'stmtlist'}};
    my $i = 0;
    foreach my $ns (@{$this->{'stmtlist'}}) {
        $ns->asLua($bp, $o, $i == $stmtc);
        $i++;
    }

    if ($delimit) {
        $o->tabOut();
        $o->tabwrite("end");
    }
}

package S2::NodeSum;

sub asLua {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asLua($bp, $o);

    if ($this->{'myType'} == $S2::Type::STRING) {
        $o->write(" .. ");
    } elsif ($this->{'op'} == $S2::TokenPunct::PLUS) {
        $o->write(" + ");
    } elsif ($this->{'op'} == $S2::TokenPunct::MINUS) {
        $o->write(" - ");
    }
     
    $this->{'rhs'}->asLua($bp, $o);
}

package S2::NodeTerm;

# This one's a big 'un, and it'll break if new term
# types are added. Bad historical design, I'm afraid.

sub asLua {
    my ($this, $bp, $o) = @_;
    my $type = $this->{'type'};

    if ($type == $INTEGER) {
        $this->{'tokInt'}->asLua($bp, $o);
        return;
    }

    if ($type == $STRING) {
        if (defined $this->{'nodeString'}) {
            $o->write("(");
            $this->{'nodeString'}->asLua($bp, $o);
            $o->write(")");
            return;
        }
        if ($this->{'ctorclass'}) {
            my $pkg = $bp->getBuiltinPackage() || "s2.builtin";
            $o->write("${pkg}.$this->{'ctorclass'}__$this->{'ctorclass'}(");
        }
        $this->{'tokStr'}->asLua($bp, $o);
        $o->write(")") if $this->{'ctorclass'};
        return;
    }

    if ($type == $BOOL) {
        $o->write($this->{'boolValue'} ? "true" : "false");
        return;
    }

    if ($type == $SUBEXPR) {
        $o->write("(");
        $this->{'subExpr'}->asLua($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $ARRAY) {
        $this->{'subExpr'}->asLua($bp, $o);
        return;
    }

    if ($type == $NEW) {
        $o->write("{[\".type\" = ".
                  $bp->quoteString($this->{'newClass'}->getIdent()) .
                  "}");
        return;
    }

    if ($type == $NEWNULL) {
        $o->write("{\".type\" = ".
                  $bp->quoteString($this->{'newClass'}->getIdent()) .
                  ", \".isnull\" =  1}");
        return;
    }

    if ($type == $REVERSEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("s2.runtime.reverseArray(");
            $this->{'subExpr'}->asLua($bp, $o);
            $o->write(")");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("s2.runtime.reverseString(");
            $this->{'subExpr'}->asLua($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $SIZEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("s2.runtime.arraySize(");
            $this->{'subExpr'}->asLua($bp, $o);
            $o->write(")");
        } elsif ($this->{'subType'}->isHashOf()) {
            $o->write("s2.runtime.hashSize(");
            $this->{'subExpr'}->asLua($bp, $o);
            $o->write(")");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("s2.runtime.stringSize(");
            $this->{'subExpr'}->asLua($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $DEFINEDTEST) {
        $o->write("s2.runtime.isDefined(");
        $this->{'subExpr'}->asLua($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $ISNULLFUNC) {
        $o->write("(not s2.runtime.isDefined(");
        $this->{'subExpr'}->asLua($bp, $o);
        $o->write("))");
        return;
    }

    if ($type == $VARREF) {
        $this->{'var'}->asLua($bp, $o);
        return;
    }

    if ($type == $OBJ_INTERPOLATE) {
        $o->write("s2.runtime.toString(_ctx, ");
        $this->{'var'}->asLua($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $FUNCCALL || $type == $METHCALL) {

        # builtin functions can be optimized.
        if ($this->{'funcBuiltin'}) {
            # these built-in functions can be inlined.
            if ($this->{'funcID'} eq "string(int)") {
                $this->{'funcArgs'}->asLua($bp, $o, 0);
                return;
            }
            if ($this->{'funcID'} eq "int(string)") {
                # cast from string to int by adding zero to it
                $o->write("s2.runtime.int(");
                $this->{'funcArgs'}->asLua($bp, $o, 0);
                $o->write(" + 0)");
                return;
            }

            # otherwise, call the builtin function (avoid a layer
            # of indirection), unless it's for a class that has
            # children (won't know until run-time which class to call)
            my $pkg = $bp->getBuiltinPackage() || "s2.builtin";
            $o->write("${pkg}.");
            if ($this->{'funcClass'}) {
                $o->write("$this->{'funcClass'}__");
            }
            $o->write($this->{'funcIdent'}->getIdent());
        } else {
            if ($type == $METHCALL && $this->{'funcClass'} ne "string") {
                $o->write("s2.runtime.getMethod(_ctx, ");
                $this->{'var'}->asLua($bp, $o);
                $o->write(",");
                $o->write($bp->quoteString($this->{'funcID_noclass'}));
                $o->write(",l,");          # The layer itself
                $o->write($this->{'derefLine'}+0);
                if ($this->{'var'}->isSuper()) {
                    $o->write(",true");
                }
                $o->write(")");
            } else {
                $o->write("s2.runtime.getFunction(_ctx, ");
                $o->write($bp->quoteString($this->{'funcID'}));
                $o->write(")");
            }
        }

        $o->write("(_ctx, ");
        
        # this pointer
        if ($type == $METHCALL) {
            $this->{'var'}->asLua($bp, $o);
            $o->write(", ");
        }
        
        $this->{'funcArgs'}->asLua($bp, $o, 0);
        
        $o->write(")");
        return;
    }

    die "Unknown term type";
}

package S2::NodeUnaryExpr;

sub asLua {
    my ($this, $bp, $o) = @_;
    if ($this->{'bNot'}) { $o->write("not "); }
    if ($this->{'bNegative'}) { $o->write("-"); }
    $this->{'expr'}->asLua($bp, $o);
}

package S2::NodeUnnecessary;

sub asLua {
    my ($this, $bp, $o) = @_;
    # do nothing when making the Lua output
}

package S2::NodeVarDecl;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->write("local " . $this->{'nt'}->getName());
}

package S2::NodeVarDeclStmt;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("");
    $this->{'nvd'}->asLua($bp, $o);
    if ($this->{'expr'}) {
        $o->write(" = ");
        $this->{'expr'}->asLua($bp, $o);
    } else {
        # Must initialize the variables otherwise they will have
        # type "nil" and we'll have exceptions galore.
        my $t = $this->{'nvd'}->getType();
        if (! $t->isSimple()) {
            $o->write(" = {}");
        } elsif ($t->equals($S2::Type::STRING)) {
            $o->write(" = \"\"");
        } elsif ($t->equals($S2::Type::BOOL)) {
            $o->write(" = false");
        } elsif ($t->equals($S2::Type::INT)) {
            $o->write(" = 0");
        } else {
            $o->write(" = {}");
        }
    }
    $o->writeln(";");
}

package S2::NodeVarRef;

sub asLua {
    my ($this, $bp, $o) = @_;
    my $first = 1;

    if ($this->{'type'} == $OBJECT) {
        $o->write("this");
    } elsif ($this->{'type'} == $PROPERTY) {
        $o->write("_ctx.props");
        $first = 0;
    }

    foreach my $lev (@{$this->{'levels'}}) {
        if (! $first || $this->{'type'} == $OBJECT) {
            $o->write(".$lev->{'var'}");
        } else {
            my $v = $lev->{'var'};
            if ($first && $this->{'type'} == $LOCAL &&
                $v eq "super") {
                $v = "this";
            }
            $o->write($v);
            $first = 0;
        }

        foreach my $d (@{$lev->{'derefs'}}) {
            $o->write(".["); # [ or {
            $d->{'expr'}->asLua($bp, $o);
            $o->write("]");
        }
    } # end levels

    if ($this->{'useAsString'}) {
        $o->write(".as_string");
    }
}

package S2::NodeWhileStmt;

sub asLua {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("while (");
    $this->{'expr'}->asLua($bp, $o);
    $o->write(") ");

    $this->{'stmts'}->asLua($bp, $o, 1);
    $o->newline();
}

package S2::TokenStringLiteral;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->write($bp->quoteString($this->{'text'}));
}

package S2::TokenIntegerLiteral;

sub asLua {
    my ($this, $bp, $o) = @_;
    $o->write($this->{'chars'});
}

1;
