#!/usr/bin/perl
#

package S2::NodeStmt;

use strict;
use S2::Node;
use S2::NodePrintStmt;
use S2::NodeIfStmt;
use S2::NodeReturnStmt;
use S2::NodeBranchStmt;
use S2::NodeDeleteStmt;
use S2::NodeForeachStmt;
use S2::NodeWhileStmt;
use S2::NodeForStmt;
use S2::NodeVarDeclStmt;
use S2::NodePushStmt;
use S2::NodeExprStmt;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub canStart {
    my ($class, $toker) = @_;
    return
        S2::NodePrintStmt->canStart($toker) ||
        S2::NodeIfStmt->canStart($toker) ||
        S2::NodeReturnStmt->canStart($toker) ||
        S2::NodeDeleteStmt->canStart($toker) ||
        S2::NodeForeachStmt->canStart($toker) ||
        S2::NodeVarDeclStmt->canStart($toker) ||
        S2::NodePushStmt->canStart($toker) ||
        S2::NodeExprStmt->canStart($toker);
}

sub parse {
    my ($class, $toker, $isDecl) = @_;

    return S2::NodePrintStmt->parse($toker)
        if S2::NodePrintStmt->canStart($toker);

    return S2::NodeIfStmt->parse($toker)
        if S2::NodeIfStmt->canStart($toker);

    return S2::NodeReturnStmt->parse($toker)
        if S2::NodeReturnStmt->canStart($toker);

    return S2::NodeBranchStmt->parse($toker)
        if S2::NodeBranchStmt->canStart($toker);

    return S2::NodeDeleteStmt->parse($toker)
        if S2::NodeDeleteStmt->canStart($toker);

    return S2::NodeForeachStmt->parse($toker)
        if S2::NodeForeachStmt->canStart($toker);

    return S2::NodeWhileStmt->parse($toker)
        if S2::NodeWhileStmt->canStart($toker);

    return S2::NodeForStmt->parse($toker)
        if S2::NodeForStmt->canStart($toker);

    return S2::NodeVarDeclStmt->parse($toker)
        if S2::NodeVarDeclStmt->canStart($toker);

    return S2::NodePushStmt->parse($toker)
        if S2::NodePushStmt->canStart($toker);
    
    # important that this is last:
    # (otherwise idents would be seen as function calls)
    return S2::NodeExprStmt->parse($toker)
        if S2::NodeExprStmt->canStart($toker);

    S2::error($toker->peek(), "Don't know how to parse this type of statement");
}

