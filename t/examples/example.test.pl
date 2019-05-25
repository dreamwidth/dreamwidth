#!/usr/bin/perl -w
###########################################################################

=head1 Example test script

This is a minimal test suite to demo LJ::Test::Unit.

=head1 CVS

  $Id: example.test.pl 4627 2004-10-30 01:10:21Z deveiant $

=cut

###########################################################################
package moveuclusterd_tests;
use strict;

use lib qw{lib};

use LJ::Test::Unit qw{+autorun};
use LJ::Test::Assertions qw{:all};

sub test_00_packages {
    assert(1);
    assert_undef(undef);
    assert_defined(1);
    assert_no_exception { my $foo = 1; };
}

sub test_01_fail {
    fail("Intentional failure.");
}

sub test_02_fail2 {
    assert_no_exception { blargllglg() } "Demo of failing assertion.";
}

sub test_05_error {
    plop();
}
