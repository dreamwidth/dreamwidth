# t/formerrors.t
#
# Tests error message handling for form validation ( DW::FormErrors ).
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


use strict;
use Test::More tests => 8;

use lib "$ENV{LJHOME}/extlib/lib/perl5";
use lib "$ENV{LJHOME}/cgi-bin";

use DW::FormErrors;

note( "Get all errors" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo" );
    $errors->add( "bar", ".error.bar" );
    $errors->add( "baz", ".error.baz" );

    is_deeply( $errors->get_all, [
                { key => "foo", message => ".error.foo" },
                { key => "bar", message => ".error.bar" },
                { key => "baz", message => ".error.baz" },
            ], "all errors in the order that they were added" );
};

note( "Get error by key" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo" );
    $errors->add( "bar", ".error.bar" );

    is( $errors->get( "foo" )->{message}, ".error.foo", "error foo by key" );
    is( $errors->get( "bar" )->{message}, ".error.bar", "error bar by key" );
}

note( "Multiple errors for the same key" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo1" );
    $errors->add( "foo", ".error.foo2" );

    my ( $foo1, $foo2 ) = $errors->get( "foo" );
    is( $foo1->{message}, ".error.foo1", "multiple errors for foo (1)" );
    is( $foo2->{message}, ".error.foo2", "multiple errors for foo (2)" );

    is_deeply( $errors->get_all, [
                { key => "foo", message => ".error.foo1" },
                { key => "foo", message => ".error.foo2" }
            ], "all errors in the order that they were added (multiple errors for the key)" );
}

note( "Error ml code with argument" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo", { foo_arg => "foofoofoo" } );

    is_deeply( $errors->get( "foo" ), { message => ".error.foo", args => { foo_arg => "foofoofoo" } },
                "error foo with argument (get)" );
    is_deeply(
        $errors->get_all,
        [ { key => "foo", message => ".error.foo", args => { foo_arg => "foofoofoo" } } ],
        "error foo with argument (get_all)" );
}
1;
