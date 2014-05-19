#!/usr/bin/perl
#

package S2::NodeTerm;

use strict;
use S2::Node;
use S2::NodeExpr;
use S2::NodeArrayLiteral;
use S2::NodeArguments;

use vars qw($VERSION @ISA
            $INTEGER $STRING $BOOL $VARREF $SUBEXPR $POPFUNC
            $DEFINEDTEST $SIZEFUNC $REVERSEFUNC $ISNULLFUNC
            $NEW $NEWNULL $FUNCCALL $METHCALL $ARRAY $OBJ_INTERPOLATE);

$VERSION = '1.0';
@ISA = qw(S2::NodeExpr);

$INTEGER = 1;
$STRING = 2;
$BOOL = 3;
$VARREF = 4;
$SUBEXPR = 5;
$DEFINEDTEST = 6;
$SIZEFUNC = 7;
$REVERSEFUNC = 8;
$ISNULLFUNC = 12;
$NEW = 9;
$NEWNULL = 13;
$FUNCCALL = 10;
$METHCALL = 11;
$ARRAY = 14;
$OBJ_INTERPOLATE = 15;
$POPFUNC = 16;

sub new {
    my ($class, $n) = @_;
    my $node = new S2::NodeExpr;
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    my $t = $toker->peek();

    return $t->isa('S2::TokenIntegerLiteral') ||
        $t->isa('S2::TokenStringLiteral') ||
        $t->isa('S2::TokenIdent') ||
        $t == $S2::TokenPunct::DOLLAR ||
        $t == $S2::TokenPunct::LPAREN ||
        $t == $S2::TokenPunct::LBRACK ||
        $t == $S2::TokenPunct::LBRACE ||
        $t == $S2::TokenKeyword::DEFINED ||
        $t == $S2::TokenKeyword::TRUE ||
        $t == $S2::TokenKeyword::FALSE ||
        $t == $S2::TokenKeyword::NEW ||
        $t == $S2::TokenKeyword::SIZE ||
        $t == $S2::TokenKeyword::REVERSE ||
        $t == $S2::TokenKeyword::ISNULL ||
        $t == $S2::TokenKeyword::NULL ||
        $t == $S2::TokenKeyword::POP;
}

sub getType {
    my ($this, $ck, $wanted) = @_;
    return $this->{'_cache_type'} if exists $this->{'_cache_type'};
    $this->{'_cache_type'} = _getType($this, $ck, $wanted);
}

sub _getType {
    my ($this, $ck, $wanted) = @_;
    my $type = $this->{'type'};

    if ($type == $INTEGER) { return $S2::Type::INT; }

    if ($type == $STRING) {
        return $this->{'nodeString'}->getType($ck, $S2::Type::STRING)
            if $this->{'nodeString'};
        if ($ck->isStringCtor($wanted)) {
            $this->{'ctorclass'} = $wanted->baseType();
            return $wanted;
        }
        return $S2::Type::STRING;
    }
    
    if ($type == $SUBEXPR) { return $this->{'subExpr'}->getType($ck, $wanted); }

    if ($type == $BOOL) { return $S2::Type::BOOL; }

    if ($type == $SIZEFUNC) {
        $this->{'subType'} = $this->{'subExpr'}->getType($ck);
        return $S2::Type::INT if
            $this->{'subType'}->isArrayOf() ||
            $this->{'subType'}->isHashOf() ||
            $this->{'subType'}->equals($S2::Type::STRING);
        S2::error($this, "Can't use size on expression that's not a string, hash or array.");
    }

    if ($type == $REVERSEFUNC) {
        $this->{'subType'} = $this->{'subExpr'}->getType($ck);

        # reverse a string
        return $S2::Type::STRING if 
            $this->{'subType'}->equals($S2::Type::STRING);

        # reverse an array
        return $this->{'subType'} if
            $this->{'subType'}->isArrayOf();

        S2::error($this, "Can't reverse on expression that's not a string or array.");
    }

    if ($type == $POPFUNC) {
        $this->{'subType'} = $this->{'subExpr'}->getType($ck);

        # pop from an array
        return new S2::Type $this->{'subType'}->baseType() if
            $this->{'subType'}->isArrayOf();

        S2::error($this, "Can't pop from something that isn't an array.");
    }

    if ($type == $ISNULLFUNC || $type == $DEFINEDTEST) {
        my $op = ($type == $ISNULLFUNC) ? "isnull" : "defined";
        $this->{'subType'} = $this->{'subExpr'}->getType($ck);

        if ($this->{'subExpr'}->isa('S2::NodeTerm')) {
            my $nt = $this->{'subExpr'};
            if ($nt->{'type'} != $VARREF && $nt->{'type'} != $FUNCCALL &&
                $nt->{'type'} != $METHCALL) {
                S2::error($this, "$op must only be used on an object variable, ".
                          "function call or method call.");
            }
        } else {
            S2::error($this, "$op must only be used on an object variable, ".
                      "function call or method call.");
        }

        # can't be used on arrays and hashes
        unless ($this->{'subType'}->isSimple()) {
            S2::error($this, "Can't use $op on an array or hash.");
        }
        
        # not primitive types either
        if ($this->{'subType'}->isPrimitive()) {
            S2::error($this, "Can't use $op on primitive types.");
        }
        
        # nor void
        if ($this->{'subType'}->equals($S2::Type::VOID)) {
            S2::error($this, "Can't use $op on a void value.");
        }
        
        return $S2::Type::BOOL;
    }

    if ($type == $NEW || $type == $NEWNULL) {
        # A classname is optional for 'null', but not for 'new'.
        # The parsing code enforces the presence of the type for 'new'.
        if ($this->{'newClass'}) {
            my $clas = $this->{'newClass'}->getIdent();
            if ($clas eq "int" || $clas eq "string") {
                S2::error($this, "Can't use 'new' with primitive type '$clas'");
            }
            my $nc = $ck->getClass($clas);
            unless ($nc) {
                S2::error($this, "Can't instantiate unknown class.");
            }
            $this->{funcID} = S2::Checker::functionID( $clas, $clas,
                ( $this->{funcArgs} ? $this->{funcArgs}->typeList($ck) : undef ) );
            $this->{funcBuiltin} = $ck->isFuncBuiltin( $this->{funcID} );

            my $t = $ck->functionType($this->{funcID});
            my $clasType = S2::Type->new( $clas );

            S2::error($this, "Unknown constructor '$this->{funcID}'")
                if $this->{funcArgs} && ! $t;
            S2::error($this, "Constructor '$this->{funcID}' returns '" . $t->toString() . "', expected '$clas'")
                if $t && ! $t->equals( $clasType );
            $this->{funcID} = undef unless $t;

            return $clasType;
        }
        else {
            if (defined($wanted) && !$wanted->isPrimitive()) {
                return $wanted;
            }
            else {
                return $S2::Type::NULL;
            }
        }
    }

    if ($type == $VARREF) {
        unless ($ck->getInFunction()) {
            S2::error($this, "Can't reference a variable outside of a function.");
        }
        return $this->{'var'}->getType($ck, $wanted);
    }

    if ($type == $METHCALL || $type == $FUNCCALL) {
        S2::error($this, "Can't call a function or method outside of a function")
            unless $ck->getInFunction();

        if ($type == $METHCALL) {
            my $vartype = $this->{'var'}->getType($ck, $wanted);
            S2::error($this, "Cannot call a method on an array or hash")
                unless $vartype->isSimple();

            $this->{'funcClass'} = $vartype->toString;
            
            my $methClass = $ck->getClass($this->{'funcClass'});
            S2::error($this, "Can't call a method on an instance of an undefined class")
                unless $methClass;
        }

          $this->{'funcID'} = 
              S2::Checker::functionID($this->{'funcClass'},
                                      $this->{'funcIdent'}->getIdent(),
                                      $this->{'funcArgs'}->typeList($ck));
          $this->{'funcBuiltin'} = $ck->isFuncBuiltin($this->{'funcID'});

          $this->{'funcID_noclass'} = 
              S2::Checker::functionID(undef,
                                      $this->{'funcIdent'}->getIdent(),
                                      $this->{'funcArgs'}->typeList($ck));
          
          my $t = $ck->functionType($this->{'funcID'});
          $this->{'funcNum'} = $ck->functionNum($this->{'funcID'})
              unless $this->{'funcBuiltin'};
          
          S2::error($this, "Unknown function $this->{'funcID'}")
              unless $t;
          
          return $t;
    }

    if ($type == $ARRAY) {
        return $this->{'subExpr'}->getType($ck, $wanted);
    }

    S2::error($this, "Unknown NodeTerm type");
}

sub isLValue {
    my $this = shift;
    return 1 if $this->{'type'} == $VARREF;
    return $this->{'subExpr'}->isLValue()
        if $this->{'type'} == $SUBEXPR;
    return 0;
}

# make the object interpolate in a string
sub makeAsString {
    my ($this, $ck) = @_;

    if ($this->{'type'} == $STRING) {
        return $this->{'nodeString'}->makeAsString($ck);
    }
    return 0 unless $this->{'type'} == $VARREF;

    my $t = $this->{'var'}->getType($ck);
    return 0 unless $t->isSimple();
    
    my $bt = $t->baseType;
    
    # class has .toString() or .as_string() method?
    if (my $methname = $ck->classHasToString($bt)) {
        # let's change this VARREF into a METHCALL!
        # warning: ugly hacks ahead...
        my $funcID = "${bt}::$methname()";
        if ($ck->isFuncBuiltin($funcID)) {
            # builtins map to a normal function call.
            # the builtin function is responsible for checking if the
            # object is S2::check_defined() and then returning nothing.
            $this->{'type'} = $METHCALL;
            $this->{'funcIdent'} = new S2::TokenIdent $methname;
            $this->{'funcClass'} = $bt;
            $this->{'funcArgs'} = new S2::NodeArguments; # empty
            $this->{'funcID_noclass'} = "$methname()";
            $this->{'funcID'} = $funcID;
            $this->{'funcBuiltin'} = 1;
        } else {
            # if it's S2-level as_string(), then we call
            # S2::interpolate_object($ctx, "ClassName", $obj, $methname)
            $this->{'type'} = $OBJ_INTERPOLATE;
            $this->{'funcClass'} = $bt;
            $this->{'objint_method'} = $methname;

        }
        return 1;
    }

    # class has $.as_string string member?
    if ($ck->classHasAsString($bt)) {
        $this->{'var'}->useAsString();
        return 1;
    }
    
    return 0;    
}

sub parse {
    my ($class, $toker) = @_;
    my $nt = new S2::NodeTerm;
    my $t = $toker->peek();

    # integer literal
    if ($t->isa('S2::TokenIntegerLiteral')) {
        $nt->{'type'} = $INTEGER;
        $nt->{'tokInt'} = $nt->eatToken($toker);
        return $nt;
    }

    # boolean literal
    if ($t == $S2::TokenKeyword::TRUE ||
        $t == $S2::TokenKeyword::FALSE) {
        $nt->{'type'} = $BOOL;
        $nt->{'boolValue'} = $t == $S2::TokenKeyword::TRUE;
        $nt->eatToken($toker);
        return $nt;
    }

    # string literal
    if ($t->isa('S2::TokenStringLiteral')) {
        my $ts = $t;
        my $ql = $ts->getQuotesLeft();
        my $qr = $ts->getQuotesRight();

        if ($qr) {
            # whole string literal
            $nt->{'type'} = $STRING;
            $nt->{'tokStr'} = $nt->eatToken($toker);
            $nt->setStart($nt->{'tokStr'});
            return $nt;
        }

        # interpolated string literal (turn into a subexpr)
        my $toklist = [];
        $toker->pushInString($ql);
        
        $nt->{'type'} = $STRING;
        $nt->{'tokStr'} = $nt->eatToken($toker);
        push @$toklist, $nt->{'tokStr'}->clone();
        $nt->{'tokStr'}->setQuotesRight($ql);
        
        my $lhs = $nt;
        my $filepos = $nt->{'tokStr'}->getFilePos();
        
        my $loop = 1;
        while ($loop) {
            my $rhs = undef;
            my $tok = $toker->peek();
            unless ($tok) {
                S2::error($tok, "Unexpected end of file.  Unclosed string literal?");
            }
            if ($tok->isa('S2::TokenStringLiteral')) {
                $rhs = new S2::NodeTerm;
                $ts = $tok;
                $rhs->{'type'} = $STRING;
                $rhs->{'tokStr'} = $rhs->eatToken($toker);
                push @$toklist, $rhs->{'tokStr'}->clone();

                $loop = 0 if $ts->getQuotesRight() == $ql;
                $ts->setQuotesRight($ql);
                $ts->setQuotesLeft($ql);
            } elsif ($tok == $S2::TokenPunct::DOLLAR) {
                $rhs = parse S2::NodeTerm $toker;
                push @$toklist, @{$rhs->getTokenList()};
            } else {
                S2::error($tok, "Error parsing interpolated string: " . $tok->toString);
            }
            
            # don't make a sum out of a blank string on either side
            my $join = 1;
            if ($lhs->isa('S2::NodeTerm') &&
                $lhs->{'type'} == $STRING &&
                length($lhs->{'tokStr'}->getString()) == 0) 
            {
                $lhs = $rhs;
                $join = 0;
            }
            if ($rhs->isa('S2::NodeTerm') &&
                $rhs->{'type'} == $STRING &&
                length($rhs->{'tokStr'}->getString()) == 0)
            {
                $join = 0;
            }

            if ($join) {
                $lhs = S2::NodeSum->new($lhs, $S2::TokenPunct::PLUS, $rhs);
            }
        }
        
        $toker->popInString();

        $lhs->setTokenList($toklist);
        $lhs->setStart($filepos);
        
        my $rnt = new S2::NodeTerm;
        $rnt->{'type'} = $STRING;
        $rnt->{'nodeString'} = $lhs;
        $rnt->addNode($lhs);

        return $rnt;
    }
    
    # Sub-expression (in parenthesis)
    if ($t == $S2::TokenPunct::LPAREN) {
        $nt->{'type'} = $SUBEXPR;
        $nt->setStart($nt->eatToken($toker));

        $nt->{'subExpr'} = parse S2::NodeExpr $toker;
        $nt->addNode($nt->{'subExpr'});

        $nt->requireToken($toker, $S2::TokenPunct::RPAREN);
        return $nt;
    }

    # defined test
    if ($t == $S2::TokenKeyword::DEFINED) {
        $nt->{'type'} = $DEFINEDTEST;
        $nt->setStart($nt->eatToken($toker));
        $nt->{'subExpr'} = parse S2::NodeTerm $toker;
        $nt->addNode($nt->{'subExpr'});
        return $nt;
    }

    # pop function
    if ($t == $S2::TokenKeyword::POP) {
        $nt->{'type'} = $POPFUNC;
        $nt->eatToken($toker);
        $nt->{'subExpr'} = parse S2::NodeTerm $toker;
        $nt->addNode($nt->{'subExpr'});
        return $nt;
    }

    # reverse function
    if ($t == $S2::TokenKeyword::REVERSE) {
        $nt->{'type'} = $REVERSEFUNC;
        $nt->eatToken($toker);
        $nt->{'subExpr'} = parse S2::NodeTerm $toker;
        $nt->addNode($nt->{'subExpr'});
        return $nt;
    }

    # size function
    if ($t == $S2::TokenKeyword::SIZE) {
        $nt->{'type'} = $SIZEFUNC;
        $nt->eatToken($toker);
        $nt->{'subExpr'} = parse S2::NodeTerm $toker;
        $nt->addNode($nt->{'subExpr'});
        return $nt;
    }

    # isnull function
    if ($t == $S2::TokenKeyword::ISNULL) {
        $nt->{'type'} = $ISNULLFUNC;
        $nt->eatToken($toker);
        $nt->{'subExpr'} = parse S2::NodeTerm $toker;
        $nt->addNode($nt->{'subExpr'});
        return $nt;
    }

    # new andnull
    if ($t == $S2::TokenKeyword::NEW ||
        $t == $S2::TokenKeyword::NULL) {
        $nt->{'type'} = $t == $S2::TokenKeyword::NEW ? $NEW : $NEWNULL;
        $nt->eatToken($toker);
        # For backward compatibility, we still allow a type to follow
        # the 'null' keyword, but it is no longer required and it is ignored.
        my $nextToken = $toker->peek;
        if (UNIVERSAL::isa($nextToken, 'S2::TokenIdent')) {
            $nt->{newClass} = $nt->getIdent($toker);
            $nextToken = $toker->peek;
            if ( $nextToken == $S2::TokenPunct::LPAREN ) {
                $nt->{funcArgs} = parse S2::NodeArguments $toker;
                $nt->addNode($nt->{funcArgs});
            }
        }
        elsif ($t == $S2::TokenKeyword::NEW) {
            # A type is *required* for new, but not for null
            S2::error($toker->peek, "new operator requires a type");
        }
        return $nt;
    }

    # VarRef
    if ($t == $S2::TokenPunct::DOLLAR) {
        $nt->{'type'} = $VARREF;
        $nt->{'var'} = parse S2::NodeVarRef $toker;
        $nt->addNode($nt->{'var'});

        # check for -> after, like: $object->method(arg1, arg2, ...)
        if ($toker->peek() == $S2::TokenPunct::DEREF) {
            $nt->{'derefLine'} = $toker->peek()->getFilePos()->line;
            $nt->eatToken($toker);
            $nt->{'type'} = $METHCALL;
            # don't return... parsing continues below.
        } else {
            return $nt;
        }
    }

    # function/method call
    my $isa_methcall = defined $nt->{type} ?
                       $nt->{type} == $METHCALL :
                       ! defined $METHCALL;
    if ( $isa_methcall || $t->isa('S2::TokenIdent') ) {
        $nt->{'type'} = $FUNCCALL unless $isa_methcall;
        $nt->{'funcIdent'} = $nt->getIdent($toker);
        $nt->{'funcArgs'} = parse S2::NodeArguments $toker;
        $nt->addNode($nt->{'funcArgs'});
        return $nt;
    }

    # array/hash literal
    if (S2::NodeArrayLiteral->canStart($toker)) {
        $nt->{'type'} = $ARRAY;
        $nt->{'subExpr'} = parse S2::NodeArrayLiteral $toker;
        $nt->addNode($nt->{'subExpr'});
        return $nt;
    }
    
    S2::error($toker->peek(), "Can't finish parsing NodeTerm");
}


sub asS2 {
    my ($this, $o) = @_;
    die "NodeTerm::asS2(): not implemented";
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    my $type = $this->{'type'};

    if ($type == $INTEGER) {
        $this->{'tokInt'}->asPerl($bp, $o);
        return;
    }

    if ($type == $STRING) {
        if (defined $this->{'nodeString'}) {
            $o->write("(");
            $this->{'nodeString'}->asPerl($bp, $o);
            $o->write(")");
            return;
        }
        if ($this->{'ctorclass'}) {
            my $pkg = $bp->getBuiltinPackage() || "S2::Builtin";
            $o->write("${pkg}::$this->{'ctorclass'}__$this->{'ctorclass'}(");
        }
        $this->{'tokStr'}->asPerl($bp, $o);
        $o->write(")") if $this->{'ctorclass'};
        return;
    }

    if ($type == $BOOL) {
        $o->write($this->{'boolValue'} ? "1" : "0");
        return;
    }

    if ($type == $SUBEXPR) {
        $o->write("(");
        $this->{'subExpr'}->asPerl($bp, $o);
        $o->write(")");
        return;
    }

    if ($type == $ARRAY) {
        $this->{'subExpr'}->asPerl($bp, $o);
        return;
    }

    if ($type == $NEW) {
        if ( $this->{funcID} && $this->{funcBuiltin} ) {
            my $pkg = $bp->getBuiltinPackage() || "S2::Builtin";
            my $clas = $this->{newClass}->getIdent();
            $o->write($pkg . '::' . $clas . '__' . $clas);

            # FIXME: I think S2 builtin constructors should at least get $ctx.
            $o->write("(");
            $this->{funcArgs}->asPerl($bp, $o, 0) if $this->{funcArgs};
            $o->write(")");
        } elsif ( $this->{funcID} ) {
            S2::error($this, "Can't use non-builtin constructor '$this->{funcID}'");
        } else {
            $o->write("S2::Object->new(" .
                  $bp->quoteString($this->{'newClass'}->getIdent()) .
                  ")");
        }
        return;
    }

    if ($type == $NEWNULL) {
        $o->write("undef");
        return;
    }

    if ($type == $POPFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("pop(\@{");
            $this->{'subExpr'}->asPerl($bp, $o);
            $o->write("})");
        }
        return;
    }

    if ($type == $REVERSEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("[reverse(\@{");
            $this->{'subExpr'}->asPerl($bp, $o);
            $o->write("})]");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("reverse(");
            $this->{'subExpr'}->asPerl($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $SIZEFUNC) {
        if ($this->{'subType'}->isArrayOf()) {
            $o->write("scalar(\@{");
            $this->{'subExpr'}->asPerl($bp, $o);
            $o->write("})");
        } elsif ($this->{'subType'}->isHashOf()) {
            $o->write("scalar(keys \%{");
            $this->{'subExpr'}->asPerl($bp, $o);
            $o->write("})");
        } elsif ($this->{'subType'}->equals($S2::Type::STRING)) {
            $o->write("length(");
            $this->{'subExpr'}->asPerl($bp, $o);
            $o->write(")");
        }
        return;
    }

    if ($type == $DEFINEDTEST || $type == $ISNULLFUNC) {
        if ($type == $ISNULLFUNC) {
            $o->write("(!");
        }
        if ($bp->oo) {
            $o->write("\$_ctx->_is_defined(");
        }
        else {
            $o->write("S2::check_defined(");
        }
        $this->{'subExpr'}->asPerl($bp, $o);
        $o->write(")");
        if ($type == $ISNULLFUNC) {
            $o->write(")");
        }
        return;
    }

    if ($type == $VARREF) {
        $this->{'var'}->asPerl($bp, $o);
        return;
    }

    if ($type == $OBJ_INTERPOLATE) {
        if ($bp->oo) {
            $o->write("\$_ctx->_interpolate_object(");
            $this->{'var'}->asPerl($bp, $o);
            $o->write(", '$this->{'objint_method'}()'");
            $o->write(", '$this->{'funcClass'}'");
            $o->write(", \$lay");
            $o->write(", ".($this->{'derefLine'}+0));
            $o->write(")");
        }
        else {
            $o->write("S2::interpolate_object(\$_ctx, '$this->{'funcClass'}', ");
            $this->{'var'}->asPerl($bp, $o);
            $o->write(", '$this->{'objint_method'}()')");
        }
        return;
    }

    if ($type == $FUNCCALL || $type == $METHCALL) {

        # builtin functions can be optimized.
        if ($this->{'funcBuiltin'}) {
            # these built-in functions can be inlined.
            if ($this->{'funcID'} eq "string(int)") {
                $this->{'funcArgs'}->asPerl($bp, $o, 0);
                return;
            }
            if ($this->{'funcID'} eq "int(string)") {
                # cast from string to int by adding zero to it
                $o->write("int(");
                $this->{'funcArgs'}->asPerl($bp, $o, 0);
                $o->write(")");
                return;
            }

            # otherwise, call the builtin function (avoid a layer
            # of indirection), unless it's for a class that has
            # children (won't know until run-time which class to call)
            my $pkg = $bp->getBuiltinPackage() || "S2::Builtin";
            $o->write("${pkg}::");
            if ($this->{'funcClass'}) {
                $o->write("$this->{'funcClass'}__");
            }
            $o->write($this->{'funcIdent'}->getIdent());
        } else {

            # Function calls in OO mode work differently
            if ($bp->oo) {
                if ($type == $METHCALL && ! { map { $_=>1 } qw(string int bool) }->{$this->{'funcClass'}}) {
                    $o->write("\$_ctx->_call_method(");
                    $this->{var}->asPerl($bp, $o);
                    $o->write(",");
                    $o->write($bp->quoteString($this->{'funcID_noclass'}));
                    $o->write(",");
                    $o->write($bp->quoteString($this->{'funcClass'}));
                    $o->write($this->{'var'}->isSuper() ? ",1" : ",0");
                    $o->write(",");
                }
                else {
                    $o->write("\$_ctx->_call_function(");
                    $o->write($bp->quoteString($this->{'funcID'}));
                    $o->write(",");
                }

                $o->write("[");
                $this->{'funcArgs'}->asPerl($bp, $o, 0);
                $o->write("]");

                $o->write(",");
                $o->write("\$lay");
                $o->write(",");
                $o->write($this->{'derefLine'}+0);
                $o->write(",");

                $o->write(")");

                return;
            }

            if ($type == $METHCALL && $this->{'funcClass'} ne "string") {
                $o->write("\$_ctx->[VTABLE]->{get_object_func_num(");
                $o->write($bp->quoteString($this->{'funcClass'}));
                $o->write(",");
                $this->{'var'}->asPerl($bp, $o);
                $o->write(",");
                $o->write($bp->quoteString($this->{'funcID_noclass'}));
                $o->write(",");
                $o->write($bp->getLayerID());
                $o->write(",");
                $o->write($this->{'derefLine'}+0);
                $o->write($this->{'var'}->isSuper() ? ",1" : ",0");
                $o->write(",\$_ctx");
                $o->write(")}->");
            } elsif ($type == $METHCALL) {
                $o->write("\$_ctx->[VTABLE]->{get_func_num(");
                $o->write($bp->quoteString($this->{'funcID'}));
                $o->write(")}->");
            } else {
                $o->write("\$_ctx->[VTABLE]->{\$_l2g_func[$this->{'funcNum'}]}->");
            }
        }

        $o->write("(\$_ctx, ");
        
        # this pointer
        if ($type == $METHCALL) {
            $this->{'var'}->asPerl($bp, $o);
            $o->write(", ");
        }
        
        $this->{'funcArgs'}->asPerl($bp, $o, 0);
        
        $o->write(")");
        return;
    }

    die "Unknown term type: $type";
}

sub isProperty {
    my $this = shift;
    return 0 unless $this->{'type'} == $VARREF;
    return $this->{'var'}->isProperty();
}

sub isBuiltinProperty {
    my ($this, $ck) = @_;
    return 0 unless $this->{'type'} == $VARREF;
    return 0 unless $this->{'var'}->isProperty();
    my $name = $this->{'var'}->propName();
    return $ck->propertyBuiltin($name);
}
