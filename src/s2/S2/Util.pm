#!/usr/bin/perl
#

package S2;

sub error {
    my ($where, $msg) = @_;
    if (ref $where && ($where->isa('S2::Token') ||
                       $where->isa('S2::Node'))) {
        $where = $where->getFilePos();
    }
    if (ref $where eq "S2::FilePos") {
        $where = $where->locationString;
    }

    my $i = 0;
    my $errmsg = "$where: $msg\n";
    while (my ($p, $f, $l) = caller($i++)) {
        $errmsg .= "  $p, $f, $l\n";
    }
    undef $S2::CUR_COMPILER;
    die $errmsg;
}


1;
