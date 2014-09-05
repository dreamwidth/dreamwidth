#!/usr/bin/perl

# This file inserts appropriate implementations of asJS()
# in every applicable Node class.

use strict;

package S2::Node;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->tabwriteln("--[[-- ${this}::asJS not implemented --]]");
}

# This should really be in S2::NodeExpr, but the compiler has
# some bad historical design: not all expressions inherit from
# NodeExpr. :(
sub asJS_bool {
    my ($this, $bp, $o) = @_;
    my $ck = $S2::CUR_COMPILER->{'checker'};
    my $s2type = $this->getType($ck);
    
    if ($s2type->equals($S2::Type::BOOL)) {
        $this->asJS($bp, $o);
        return;
    }

    if ($s2type->equals($S2::Type::INT)) {
        $o->write("(");
        $this->asJS($bp, $o);
        $o->write(" != 0)");
        return;
    }

    if ($s2type->equals($S2::Type::STRING)) {
        $o->write("(");
        $this->asJS($bp, $o);
        $o->write(" != \"\")");
        return;
    }

    if ($s2type->isSimple()) {
        $this->asJS($bp, $o);
        return;
    }

    if ($s2type->isArrayOf()) {
        $o->write("((");
        $this->asJS($bp, $o);
        $o->write(").length > 0)");
        return;
    }

    if ($s2type->isHashOf()) {
        $o->write("s2.runtime.hashToBool(");
        $this->asJS($bp, $o);
        $o->write(")");
        return;
    }
    
    $o->write("--[[ Unhandled case in asJS_bool! ]] false");
}



package S2::NodeArguments;

sub asJS {
    my ($this, $bp, $o, $parens, $initcomma) = @_;
    $parens = 1 unless defined $parens;
    $o->write("(") if $parens;
    my $didFirst = $initcomma ? 1 : 0;
    foreach my $n (@{$this->{'args'}}) {
        $o->write(", ") if $didFirst++;
        $n->asJS($bp, $o);
    }
    $o->write(")") if $parens;
}

package S2::NodeArrayLiteral;

sub asJS {
    my ($this, $bp, $o) = @_;

    my $size = scalar @{$this->{'vals'}};

    my $isHash = $this->{isHash};

    if ($size == 0) {
        $o->write($isHash ? "{}" : "[]");
        return;
    }

    $o->writeln($isHash ? "{" : "[");
    $o->tabIn();

    my $first = 1;
    for (my $i=0; $i<$size; $i++) {
        $o->writeln(",") unless $first;
        $o->tabwrite("");
        if ($isHash) {
            $this->{'keys'}->[$i]->asJS($bp, $o);
            $o->write(": ");
        }
        $this->{'vals'}->[$i]->asJS($bp, $o);
        $first = 0;
    }
    $o->writeln("");
    $o->tabOut();
    $o->tabwrite($isHash ? "}" : "]");
}


package S2::NodeAssignExpr;

sub asJS {
    my ($this, $bp, $o) = @_;

    $this->{'lhs'}{'var'}{'varReturnType'} = undef;
    $this->{'lhs'}->asJS($bp, $o);

    my $need_notags = $bp->untrusted() && 
        $this->{'lhs'}->isProperty() &&
        $this->{'lhs'}->getType()->equals($S2::Type::STRING);

    $o->write(" = ");
    $o->write("s2.runtime.notags(") if $need_notags;
    $this->{'rhs'}->asJS($bp, $o);
    $o->write(")") if $need_notags;

}

package S2::NodeClass;

sub asJS {
    my ($this, $bp, $o) = @_;

    # TODO: Add documentation support here too
    
    $o->tabwrite("$bp->{layerid}.registerClass(".$bp->quoteString($this->getName()));

    if ($this->{'parentName'}) {
        $o->write(", ".$bp->quoteString($this->getParentName()));
    }
    $o->writeln(");");
}

package S2::NodeCondExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->write("(");
    $this->{'test_expr'}->asJS_bool($bp, $o);
    $o->write(" ? ");
    $this->{'true_expr'}->asJS($bp, $o);
    $o->write(" : ");
    $this->{'false_expr'}->asJS($bp, $o);
    $o->write(")");
}

package S2::NodeDeleteStmt;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("");
    $this->{'var'}->asJS($bp, $o);
    $o->writeln(" = null;");
}

package S2::NodeEqExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asJS($bp, $o);
    if ($this->{'op'} == $S2::TokenPunct::EQ) {
        $o->write(" == ");
    } else {
        $o->write(" != ");
    }
    $this->{'rhs'}->asJS($bp, $o);
}

package S2::NodeExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    $this->{'expr'}->asJS($bp, $o);
}

package S2::NodeExprStmt;

sub asJS {
    my ($this, $bp, $o) = @_;
   
    $o->tabwrite("");
    $this->{'expr'}->asJS($bp, $o);
    $o->writeln(";");
}

package S2::NodeForeachStmt;

sub asJS {
    my ($this, $bp, $o) = @_;

    my $varname;
    if ($this->{'vardecl'}) {
        $varname = sub {
            $o->write($bp->decorateLocal($this->{'vardecl'}->{'nt'}->getName(), $this->{'stmts'}));
        };
    }
    else {
        $varname = sub {
            $this->{'varref'}->asJS($bp, $o);
        };
    }
    
    my $realexpr = $this->{'listexpr'}->isa('S2::NodeExpr') ?
                   $this->{'listexpr'}->{expr} :
                   $this->{'listexpr'};

    # Optimise the foreach (x .. y) idiom to a JS numeric for
    # FIXME: ...but this doesn't quite work right yet... the loop
    # variable isn't declared.
    if ($realexpr->isa('S2::NodeRange')) {
        my $range = $realexpr;
        $o->tabwrite("for (");
        $varname->();
        $o->write(" = ");
        $range->{'lhs'}->asJS($bp, $o);    
        $o->write("; ");
        $varname->();
        $o->write(" <= ");
        $range->{'rhs'}->asJS($bp, $o);
        $o->write("; ");
        $varname->();
        $o->write("++) ");
    } else {
        $o->tabwrite("for (");

        # FIXME: Implement foreach loops properly for arrays and strings
        if ($this->{'isHash'}) {
            $varname->();
            $o->write(" in ");
            $this->{'listexpr'}->asJS($bp, $o);
        } elsif ($this->{'isString'}) {
            $varname->();
            $o->write("");
            die "Foreach on strings isn't implemented for JS Backend";
        } else {
            # HACK: Use part of Perl's stringification of this object
            # to create a unique identifier to use for the loop variables.
            my $decorate = $this."";
            if ($decorate =~ /HASH\(0x(\w+)\)/) {
                $decorate = $1;
            }
            else {
                die "Unable to generate loop variable thingy ???";
            }
            
            $o->write("___a_${decorate} = ");
            $this->{'listexpr'}->asJS($bp, $o);
            
            $o->write(", ___i_${decorate} = 0, ___a_${decorate}"."[0]; ");
            $o->write("___i_${decorate} < ___a_${decorate}.length, ");
            $varname->();
            $o->write(" = ___a_${decorate}"."[___i_${decorate}]; ___i_${decorate}++");
        }

#        $this->{'listexpr'}->asJS($bp, $o);

        $o->write(") ");
    }

    $this->{'stmts'}->asJS($bp, $o);
    $o->newline();
}

package S2::NodeForStmt;

sub asJS {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("for (");
    $this->{'vardecl'}->asJS($bp, $o, { as_expr => 1 }) if $this->{'vardecl'};
    $this->{'initexpr'}->asJS($bp, $o) if $this->{'initexpr'};

    $o->write("; ");

    $this->{'condexpr'}->asJS($bp, $o);

    $o->write("; ");

    $this->{'iterexpr'}->asJS($bp, $o);
    
    $o->write(") ");

    $this->{'stmts'}->asJS($bp, $o);
    $o->newline();
}

package S2::NodeFunction;

sub asJS {
    my ($this, $bp, $o) = @_;
    unless ($this->{'classname'}) {
        # TODO: Spew out global function documentation if docs are enabled
    }

    return if $this->{'attr'}->{'builtin'};

    $o->tabwrite("$bp->{layerid}.registerFunction([");
#    $o->write($bp->quoteString(
#        S2::Checker::functionID($this->{classname} ? $this->{classname}->getIdent() : undef,
#                                $this->{name}->getIdent(),
#                                $this->{formals})
#    ));

    # declare all the names by which this function would be called:
    # its base name, then all derivative classes which aren't already
    # used.
    my $first = 1;
    foreach my $funcID (@{$this->{'ck'}->getFuncIDs($this)}) {
        $o->write(($first ? "" : ", ").$bp->quoteString($funcID));
        $first = 0;
    }

    $o->writeln("], function () {");
    $o->tabIn();

    # TODO: maybe throw some pre-resolved functions into the closure here,
    #    but must be careful not to cause new class cascade effects.

    # now, return the closure
    $o->tabwrite("return function (");
        
    # setup function argument/ locals
    $o->write("ctx");
    if ($this->{'classname'} && ! $this->{'isCtor'}) {
        $o->write(", obj");
    }

    if ($this->{'formals'}) {
        my $nts = $this->{'formals'}->getFormals();
        foreach my $nt (@$nts) {
            $o->write(", " . $bp->decorateLocal($nt->getName(), $this->{'stmts'}));
        }
    }

    $o->write(") ");
    # end function locals

#    $o->tabIn();
    
    $this->{'stmts'}->asJS($bp, $o, 0);
    $o->writeln("");
    
    # end the outer function
    $o->tabOut();
    $o->tabwriteln("});");

#    $o->tabOut();
#    $o->tabwriteln(");");

}

package S2::NodeIfStmt;

sub asJS {
    my ($this, $bp, $o) = @_;

    # if
    $o->tabwrite("if (");
    $this->{'expr'}->asJS_bool($bp, $o);
    $o->write(") ");
    $this->{'thenblock'}->asJS($bp, $o, 0);
    $o->writeln("");
        
    # else-if
    my $i = 0;
    foreach my $expr (@{$this->{'elseifexprs'}}) {
        my $block = $this->{'elseifblocks'}->[$i++];
        $o->tabwrite("else if (");
        $expr->asJS_bool($bp, $o);
        $o->write(") ");
        $block->asJS($bp, $o, 0);
        $o->writeln("");
    }

    # else
    if ($this->{'elseblock'}) {
        $o->tabwrite("else ");
        $this->{'elseblock'}->asJS($bp, $o, 0);
    }

    $o->writeln("");

}

package S2::NodeIncExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    
    my $plus = $this->{'op'}->getPunct() eq $S2::TokenPunct::INCR->getPunct();
    
    if ($this->{'bPre'}) {
        $o->write($plus ? "++" : "--");
    }

    $this->{'expr'}->asJS($bp, $o);

    if (! $this->{'bPre'}) {
        $o->write($plus ? "++" : "--");
    }
}

package S2::NodeLayerInfo;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->tabwriteln("$bp->{layerid}.setLayerInfo(" .
                   $bp->quoteString($this->{'key'}) . "," .
                   $bp->quoteString($this->{'val'}) . ");");
}

package S2::NodeLogAndExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asJS($bp, $o);
    $o->write(" && ");
    $this->{'rhs'}->asJS($bp, $o);
}

package S2::NodeLogOrExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asJS($bp, $o);
    $o->write(" || ");
    $this->{'rhs'}->asJS($bp, $o);
}

package S2::NodePrintStmt;

sub asJS {
    my ($this, $bp, $o) = @_;
    if ($bp->untrusted() || $this->{'safe'}) {
        $o->tabwrite("ctx.safePrint(");
    } else {
        $o->tabwrite("ctx.print(");
    }
    $this->{'expr'}->asJS($bp, $o);
    $o->write(" + \"\\n\"") if $this->{'doNewline'};
    $o->writeln(");");
}

package S2::NodeProduct;

sub asJS {
    my ($this, $bp, $o) = @_;

    
    $o->write("Math.floor(") if $this->{'op'} == $S2::TokenPunct::DIV;
    $this->{'lhs'}->asJS($bp, $o);

    if ($this->{'op'} == $S2::TokenPunct::MULT) {
        $o->write(" * ");
    } elsif ($this->{'op'} == $S2::TokenPunct::DIV) {
        $o->write(" / ");
    } elsif ($this->{'op'} == $S2::TokenPunct::MOD) {
        $o->write(" % ");
    } else {
        die "Unknown product type in NodeProduct::asJS";
    }

    $this->{'rhs'}->asJS($bp, $o);
    $o->write(")") if $this->{'op'} == $S2::TokenPunct::DIV;     
}

package S2::NodeProperty;

sub asJS {
    my ($this, $bp, $o) = @_;
    
    # Must have enabled property metadata
    return unless $bp->{opts}{propmeta};

    my ($this, $bp, $o) = @_;

    if ($this->{'use'}) {
        $o->tabwriteln("$bp->{layerid}.useProperty(" .
                       $bp->quoteString($bp->decorateIdent($this->{'uhName'})) . ");");
        return;
    }

    if ($this->{'hide'}) {
        $o->tabwriteln("$bp->{layerid}.hideProperty(" .
                       $bp->quoteString($bp->decorateIdent($this->{'uhName'})) . ");");
        return;
    }

    $o->tabwriteln("$bp->{layerid}.registerProperty(" .
                   $bp->quoteString($bp->decorateIdent($this->{'nt'}->getName())) . "," .
                   $bp->quoteString($this->{'nt'}->getType->toString) .
                   ",{");
    $o->tabIn();
    
    my $first = 1;
    foreach my $pp (@{$this->{'pairs'}}) {
        $o->writeln(",") unless $first;
        $o->tabwrite($bp->quoteString($pp->getKey()) . ": " .
                       $bp->quoteString($pp->getVal()));
        $first = 0;
    }    
    $o->writeln("") unless $first;
    $o->tabOut();
    $o->writeln("});");
}

package S2::NodePropGroup;

# TODO: Output property groups if the property option is on
# For now, must see if there are any property assignments inside.

sub asJS {
    my ($this, $bp, $o) = @_;

    if ($this->{'set_name'}) {
        $o->tabwriteln("$bp->{layerid}.namePropGroup(" .
                       "'$this->{groupident}'," .
                       $bp->quoteString($this->{'name'}) . ");");
        return;
    }

    foreach (@{$this->{'list_props'}}, @{$this->{'list_sets'}}) {
        $_->asJS($bp, $o);
    }
    
    $o->tabwriteln("$bp->{layerid}.registerPropGroup(" . 
                   "'$this->{groupident}',[".
                   join(', ', map { $bp->quoteString($bp->decorateIdent($_->getName)) } @{$this->{'list_props'}}) .
                   "]);");


#    my ($this, $bp, $o) = @_;
#
#    foreach (@{$this->{'list_sets'}}) {
#        $_->asJS($bp, $o);
#    }
}

package S2::NodeRange;

# This operator doesn't exist in JavaScript (or in any other language
# than Perl, as far as I know!) so we need another runtime
# library helper.

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->write("s2.runtime.makerange(");
    $this->{'lhs'}->asJS($bp, $o);
    $o->write(", ");
    $this->{'rhs'}->asJS($bp, $o);
    $o->write(")");
}

package S2::NodeRelExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asJS($bp, $o);

    if ($this->{'op'} == $S2::TokenPunct::LT) {
        $o->write(" < ");
    } elsif ($this->{'op'} == $S2::TokenPunct::LTE) {
        $o->write(" <= ");
    } elsif ($this->{'op'} == $S2::TokenPunct::GT) {
        $o->write(" > ");
    } elsif ($this->{'op'} == $S2::TokenPunct::GTE) {
        $o->write(" >= ");
    }
    
    $this->{'rhs'}->asJS($bp, $o);
}

package S2::NodeReturnStmt;

sub asJS {
    my ($this, $bp, $o, $atend) = @_;
    $o->tabwrite("");
    $o->write("return");
    if ($this->{'expr'}) {
        my $need_notags = $bp->untrusted() && $this->{'notags_func'};
        $o->write(" ");
        $o->write("s2.runtime.notags(") if $need_notags;
        $this->{'expr'}->asJS($bp, $o);
        $o->write(")") if $need_notags;
    }
    $o->writeln(";");
}

package S2::NodeSet;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("$bp->{layerid}.setProperty(".
                 $bp->quoteString($bp->decorateIdent($this->{'key'})).",");
    $this->{'value'}->asJS($bp, $o);
    $o->writeln(");");
    return;
}

package S2::NodeStmtBlock;

sub asJS {
    my ($this, $bp, $o) = @_;

    $o->writeln("{");
    $o->tabIn();

    my $stmtc = $#{$this->{'stmtlist'}};
    foreach my $ns (@{$this->{'stmtlist'}}) {
        $ns->asJS($bp, $o);
    }

    $o->tabOut();
    $o->tabwrite("}");
}

package S2::NodeSum;

sub asJS {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asJS($bp, $o);

    if ($this->{'op'} == $S2::TokenPunct::PLUS) {
        $o->write(" + ");
    } elsif ($this->{'op'} == $S2::TokenPunct::MINUS) {
        $o->write(" - ");
    }
     
    $this->{'rhs'}->asJS($bp, $o);
}

package S2::NodeTerm;

# This one's a big 'un, and it'll break if new term
# types are added. Bad historical design, I'm afraid.

sub asJS {
    my ($this, $bp, $o) = @_;
    my $type = $this->{'type'};

    if ($type == $INTEGER) {
        $this->{'tokInt'}->asJS($bp, $o);
        return;
    }

    if ($type == $STRING) {
        if (defined $this->{'nodeString'}) {
            $o->write("(");
            $this->{'nodeString'}->asJS($bp, $o);
            $o->write(")");
            return;
        }
        if ($this->{'ctorclass'}) {
            my $pkg = "s2.builtin";
            $o->write("${pkg}.construct_$this->{'ctorclass'}(");
        }
        $this->{'tokStr'}->asJS($bp, $o);
        $o->write(")") if $this->{'ctorclass'};
        return;
    }

    if ($type == $BOOL) {
        $o->write($this->{'boolValue'} ? "true" : "false");
        return;
    }

    if ($type == $SUBEXPR) {
        $o->write("(");
        $this->{'subExpr'}->asJS($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $ARRAY) {
        $this->{'subExpr'}->asJS($bp, $o);
        return;
    }

    # FIXME: Fix for S2 Constructors
    if ($type == $NEW) {
        $o->write("{\".type\": ".
                  $bp->quoteString($this->{'newClass'}->getIdent()) .
                  "}");
        return;
    }

    if ($type == $NEWNULL) {
        $o->write("{\".type\": ".
                  $bp->quoteString($this->{'newClass'}->getIdent()) .
                  ", \".isnull\":  1}");
        return;
    }

    if ($type == $REVERSEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("s2.runtime.reverseArray(");
            $this->{'subExpr'}->asJS($bp, $o);
            $o->write(")");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("s2.runtime.reverseString(");
            $this->{'subExpr'}->asJS($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $SIZEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("(");
            $this->{'subExpr'}->asJS($bp, $o);
            $o->write(").length");
        } elsif ($this->{'subType'}->isHashOf()) {
            $o->write("s2.runtime.hashSize(");
            $this->{'subExpr'}->asJS($bp, $o);
            $o->write(")");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            # JavaScript strings are unicode-aware, so this is easy
            $o->write("(");
            $this->{'subExpr'}->asJS($bp, $o);
            $o->write(").length");
        }
        return;
    }

    if ($type == $DEFINEDTEST) {
        $o->write("s2.runtime.isDefined(");
        $this->{'subExpr'}->asJS($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $ISNULLFUNC) {
        $o->write("(not s2.runtime.isDefined(");
        $this->{'subExpr'}->asJS($bp, $o);
        $o->write("))");
        return;
    }

    if ($type == $VARREF) {
        $this->{'var'}->asJS($bp, $o);
        return;
    }

    if ($type == $OBJ_INTERPOLATE) {
        $o->write("ctx.toString(");
        $this->{'var'}->asJS($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $FUNCCALL || $type == $METHCALL) {

        # builtin functions can be optimized.
        if ($this->{'funcBuiltin'}) {
            # these built-in functions can be inlined.
            if ($this->{'funcID'} eq "string(int)") {
                $this->{'funcArgs'}->asJS($bp, $o, 0);
                return;
            }
            if ($this->{'funcID'} eq "int(string)") {
                # cast from string to int by adding zero to it
                $o->write("Math.floor(");
                $this->{'funcArgs'}->asJS($bp, $o, 0);
                $o->write(" + 0)");
                return;
            }

            # otherwise, call the builtin function (avoid a layer
            # of indirection), unless it's for a class that has
            # children (won't know until run-time which class to call)
            my $pkg = "ctx.builtin";
            $o->write("${pkg}._");
            if ($this->{'funcClass'}) {
                $o->write("$this->{'funcClass'}__");
            }
            $o->write($this->{'funcIdent'}->getIdent());
        } else {
            if ($type == $METHCALL && $this->{'funcClass'} ne "string") {
                $o->write("ctx.getMethod(");
                $this->{'var'}->asJS($bp, $o);
                $o->write(",");
                $o->write($bp->quoteString($this->{'funcID_noclass'}));
                $o->write(",$bp->{layerid},");          # The layer itself
                $o->write($this->{'derefLine'}+0);
                if ($this->{'var'}->isSuper()) {
                    $o->write(",true");
                }
                $o->write(")");
            } else {
                $o->write("ctx.getFunction(");
                $o->write($bp->quoteString($this->{'funcID'}));
                $o->write(")");
            }
        }

        $o->write("(ctx");
        
        # this pointer
        if ($type == $METHCALL) {
            $o->write(", ");
            $this->{'var'}->asJS($bp, $o);
        }
        
        $this->{'funcArgs'}->asJS($bp, $o, 0, 1);
        
        $o->write(")");
        return;
    }

    die "Unknown term type";
}

package S2::NodeUnaryExpr;

sub asJS {
    my ($this, $bp, $o) = @_;
    if ($this->{'bNot'}) { $o->write("! "); }
    if ($this->{'bNegative'}) { $o->write("-"); }
    $this->{'expr'}->asJS($bp, $o);
}

package S2::NodeUnnecessary;

sub asJS {
    my ($this, $bp, $o) = @_;
    # do nothing when making the JavaScript output
}

package S2::NodeVarDecl;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->write("var " . $bp->decorateLocal($this->{'nt'}->getName(), $this->{owningScope}));
}

package S2::NodeVarDeclStmt;

sub asJS {
    my ($this, $bp, $o, $opts) = @_;
    $o->tabwrite("") unless ($opts && $opts->{as_expr});
    $this->{'nvd'}->asJS($bp, $o);
    if ($this->{'expr'}) {
        $o->write(" = ");
        $this->{'expr'}->asJS($bp, $o);
    } else {
        # Must initialize the variables otherwise they will have
        # type "null" and we'll have exceptions galore.
        my $t = $this->{'nvd'}->getType();
        if (! $t->isSimple()) {
            # FIXME: Arrays must use [] instead of {}
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
    $o->writeln(";") unless ($opts && $opts->{as_expr});
}

package S2::NodeVarRef;

sub asJS {
    my ($this, $bp, $o) = @_;
    my $first = 1;

    if ($this->{varReturnType}) {
        if ($this->{varReturnType} && $this->{varReturnType}->equals($S2::Type::STRING)) {
            # Need to wrap a preparation function around to
            # ensure we never end up with undefined strings.
            $o->write("s2.runtime.prepareString(");
        }
        elsif ($this->{varReturnType}->equals($S2::Type::INT)) {
            $o->write("Number(");
        }
        elsif ($this->{varReturnType}->equals($S2::Type::BOOL)) {
            $o->write("Boolean(Number(");
        }
    }

    if ($this->{'type'} == $OBJECT) {
        $o->write("obj");
    } elsif ($this->{'type'} == $PROPERTY) {
        $o->write("ctx.prop");
        $first = 0;
    }

    foreach my $lev (@{$this->{'levels'}}) {
        if (! $first || $this->{'type'} == $OBJECT) {
            $o->write(".".$bp->decorateIdent($lev->{'var'}));
        } else {
            my $v = $lev->{'var'};
            if ($first && $this->{'type'} == $LOCAL &&
                ($v eq "super" || $v eq "this")) {
                $o->write("obj");
            } elsif ($this->{'type'} == $LOCAL) {
                $o->write($bp->decorateLocal($v, $this->{owningScope}));
            }
            else {
                $o->write($bp->decorateIdent($v));
            }
            $first = 0;
        }

        foreach my $d (@{$lev->{'derefs'}}) {
            $o->write("["); # [ or {
            $d->{'expr'}->asJS($bp, $o);
            $o->write("]");
        }
    } # end levels

    if ($this->{varReturnType}) {
        if ($this->{varReturnType}->equals($S2::Type::STRING)) {
            # Need to wrap a preparation function around to
            # ensure we never end up with undefined strings.
            $o->write(")");
        }
        elsif ($this->{varReturnType}->equals($S2::Type::INT)) {
            $o->write(")");
        }
        elsif ($this->{varReturnType}->equals($S2::Type::BOOL)) {
            $o->write("))");
        }
    }

    if ($this->{'useAsString'}) {
        $o->write("._as_string");
    }
}

package S2::NodeWhileStmt;

sub asJS {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("while (");
    $this->{'expr'}->asJS($bp, $o);
    $o->write(") ");

    $this->{'stmts'}->asJS($bp, $o);
    $o->newline();
}

package S2::TokenStringLiteral;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->write($bp->quoteString($this->{'text'}));
}

package S2::TokenIntegerLiteral;

sub asJS {
    my ($this, $bp, $o) = @_;
    $o->write($this->{'chars'});
}

1;
