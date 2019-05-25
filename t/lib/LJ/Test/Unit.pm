#!/usr/bin/perl
##############################################################################

=head1 NAME

LJ::Test::Unit - unit-testing framework for LiveJournal

=head1 SYNOPSIS

  use LJ::Test::Unit qw{+autorun};
  use My::FooModule ();

  sub test_foo { assert My::FooModule::foo() }

=head1 EXAMPLE

  use LJ::Test::Unit qw{+autorun};
  use LJ::Test::Assertions qw{:all};

  # Require the module
  sub test_require {

      # Make sure we can load the module to be tested.
      assert_no_exception { require MyClass };

      # Try to import some functions, generating a custom error message if it
      # fails.
      assert_no_exception { MyClass->import(':myfuncs') } "Failed to import :myfuncs";

      # Make sure calling 'import()' actually imported the functions
      assert_ref 'CODE', *::myfunc{CODE};
      assert_ref 'CODE', *::myotherfunc{CODE};
  }

=head1 DESCRIPTION

This is a simplified Perl unit-testing framework for creating unit tests to be
run either standalone or under Test::Harness.

=head2 Testing

Testing in LJ::Test::Unit is done by running a test suite, either via 'make
test', which uses the L<Test::Harness|Test::Harness> 'test' target written by
L<ExtUtils::MakeMaker|ExtUtils::MakeMaker>, or as a standalone script.

If errors occur while running tests via the 'make test' method, you can get more
verbose output about the test run by adding C<TEST_VERBOSE=1> to the end of the
C<make> invocation:

  $ make test TEST_VERBOSE=1

If you want to display only the messages caused by failing assertions, you can
add a C<VERBOSE=1> to the end of the C<make> invocation instead:

  $ make test VERBOSE=1

=head2 Test Suites

A test suite is one or more test cases, each of which tests a specific unit of
functionality.

=head2 Test Cases

A test case is a unit of testing which consists of one or more tests, combined
with setup and teardown functions that make the necessary preparations for
testing.

You may wish to split test cases up into separate files under a C<t/> directory
so they will run under a L<Test::Harness|Test::Harness>-style C<make test>.

=head2 Tests

You can run tests in one of two ways: either by calling L<runTests> with a list
of function names or CODErefs to test, or by using this module with the
':autorun' tag, in which case any subs whose name begins with C<'test_'> will
automatically run at the end of the script.

=head1 REQUIRES

C<Carp>, C<Data::Dumper>, C<LJ::Test::Assertions>, C<LJ::Test::Result>,
C<Time::HiRes>, C<constant>

=head1 LICENSE

This module borrows liberally from the Test::SimpleUnit CPAN module, the license
of which is as follows:

  Michael Granger E<lt>ged@danga.comE<gt>

  Copyright (c) 1999-2003 The FaerieMUD Consortium. All rights reserved.

  This module is free software. You may use, modify, and/or redistribute this
  software under the terms of the Perl Artistic License. (See
  http://language.perl.com/misc/Artistic.html)

LiveJournal-specific code is also licensed under the the same terms as Perl
itself:

  Copyright (c) 2004 Danga Interactive. All rights reserved.

=cut

##############################################################################
package LJ::Test::Unit;
use strict;
use warnings qw{all};

###############################################################################
###  I N I T I A L I Z A T I O N
###############################################################################
BEGIN {

    # Versioning
    use vars qw{$VERSION $RCSID};
    $VERSION = 1.21;
    $RCSID   = q$Id: Unit.pm 4628 2004-10-30 02:07:22Z deveiant $;

    # More readable constants
    use constant TRUE  => 1;
    use constant FALSE => 0;

    # Main unit-testing modules
    use LJ::Test::Assertions qw{:all};
    use LJ::Test::Result qw{};

    # Load other modules
    use Carp qw{croak confess};
    use Time::HiRes qw{gettimeofday tv_interval};
    use Data::Dumper qw{};

    # Export the 'runTests' function
    use vars qw{@EXPORT @EXPORT_OK %EXPORT_TAGS};
    @EXPORT_OK = qw{&runTests};

    use base qw{Exporter};
}

our @AutorunPackages = ();

### Exporter callback -- support :autorun tag
sub import {
    my $package  = shift;
    my @args     = @_;
    my @pureargs = grep { !/\+autorun/ } @args;

    if ( @args != @pureargs ) {
        push @AutorunPackages, scalar caller;
    }

    __PACKAGE__->export_to_level( 1, $package, @pureargs );
}

### FUNCTION: extractTestFunctions( @packages )
### Iterate over the specified I<packages>' symbol tables and return a list of
### coderefs that point to functions contained in those packages that are named
### 'test_*'.
sub extractTestFunctions {
    my @packages = @_ or croak "No package given.";

    my (
        $glob,       # Iterated glob for symbol table traversal
        $coderef,    # Extracted coderef from symtable glob
        @tests,      # Collected coderefs for test functions
    );

    @tests = ();

    # Iterate over the package's symbol table, extracting coderefs to functions
    # that are named 'test_*'.
PACKAGE: foreach my $package (@packages) {
        no strict 'refs';

    SYMBOL: foreach my $sym ( sort keys %{"${package}::"} ) {
            next SYMBOL unless $sym =~ m{test_};
            $coderef = extractFunction( $package, $sym );

            push @tests, $coderef;
        }
    }

    return @tests;
}

### FUNCTION: extractFunction( $package, $funcname )
### Given a I<package> and a function name I<funcname>, extract its coderef from
### the symbol table and return it.
sub extractFunction {
    my $package = shift or croak "No package name given.";
    my $sym     = shift or croak "No function name given";

    no strict 'refs';
    my $glob = ${"${package}::"}{$sym} or return undef;
    return *$glob{CODE};
}

### FUNCTION: prepTests( $package[, @rawTests] )
### Normalize the given I<rawTests> (which can be coderefs or function names)
### and return them as coderefs. If I<rawTests> is empty, extract functions from
### the given I<package> and return those.
sub prepTests {
    my $package  = shift or croak "No calling package specified.";
    my @rawtests = @_;
    my @tests    = ();

    @rawtests = extractTestFunctions($package) if !@rawtests;

    my $coderef;

    foreach my $test (@rawtests) {
        push( @tests, $test ), next if ref $test eq 'CODE';
        $coderef = extractFunction( $package, $test )
            or croak "No such test '$test' in $package";
        push @tests, $coderef;
    }

    return @tests;
}

### FUNCTION: runTests( [@tests] )
### Run the specified I<tests> and report the result. The I<tests> can be
### coderefs or names of functions in the current package. If no I<tests> are
### specified, functions that are named 'test_*' in the current package are
### assumed to be the test functions.
sub runTests {
    my @tests  = prepTests( scalar caller, @_ );
    my $result = new LJ::Test::Result;

    print "Started.\n";
    my $starttime = [gettimeofday];
    $|++;

    foreach my $test (@tests) {
        print $result->run($test);
    }

    printf "\nFinished in %0.5fs\n", tv_interval($starttime);
    print $result->stringify, "\n\n";

    return;
}

### Extract tests from packages that were registered for 'autorun' and run them.
END {
    return unless @AutorunPackages;

    # Extract coderefs from autorun packages.
    my @tests = extractTestFunctions(@AutorunPackages);
    runTests(@tests);
}

1;

###	AUTOGENERATED DOCUMENTATION FOLLOWS

=head1 FUNCTIONS

=over 4

=item I<extractFunction( $package, $funcname )>

Given a I<package> and a function name I<funcname>, extract its coderef from
the symbol table and return it.

=item I<extractTestFunctions( @packages )>

Iterate over the specified I<packages>' symbol tables and return a list of
coderefs that point to functions contained in those packages that are named
'test_*'.

=item I<prepTests( $package[, @rawTests] )>

Normalize the given I<rawTests> (which can be coderefs or function names)
and return them as coderefs. If I<rawTests> is empty, extract functions from
the given I<package> and return those.

=item I<runTests( [@tests] )>

Run the specified I<tests> and report the result. The I<tests> can be
coderefs or names of functions in the current package. If no I<tests> are
specified, functions that are named 'test_*' in the current package are
assumed to be the test functions.

=back

=cut

