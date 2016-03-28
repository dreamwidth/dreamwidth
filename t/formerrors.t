# t/formerrors.t
#
# Tests error message handling for form validation ( DW::FormErrors ).
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


use strict;
use Test::More tests => 8;


BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::FormErrors;

note( "Get all errors" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo" );
    $errors->add( "bar", ".error.bar" );
    $errors->add( "baz", ".error.baz" );

    is_deeply( $errors->get_all, [
                { key => "foo", ml_key => ".error.foo", message => '[missing string .error.foo]' },
                { key => "bar", ml_key => ".error.bar", message => '[missing string .error.bar]' },
                { key => "baz", ml_key => ".error.baz", message => '[missing string .error.baz]' },
            ], "all errors in the order that they were added" );
};

note( "Get error by key" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo" );
    $errors->add( "bar", ".error.bar" );

    is( $errors->get( "foo" )->{ml_key}, ".error.foo", "error foo by key" );
    is( $errors->get( "bar" )->{ml_key}, ".error.bar", "error bar by key" );
}

note( "Multiple errors for the same key" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo1" );
    $errors->add( "foo", ".error.foo2" );

    my ( $foo1, $foo2 ) = $errors->get( "foo" );
    is( $foo1->{ml_key}, ".error.foo1", "multiple errors for foo (1)" );
    is( $foo2->{ml_key}, ".error.foo2", "multiple errors for foo (2)" );

    is_deeply( $errors->get_all, [
                { key => "foo", ml_key => ".error.foo1", message => '[missing string .error.foo1]' },
                { key => "foo", ml_key => ".error.foo2", message => '[missing string .error.foo2]' }
            ], "all errors in the order that they were added (multiple errors for the key)" );
}

note( "Error ml code with argument" );
{
    my $errors = DW::FormErrors->new;
    $errors->add( "foo", ".error.foo", { foo_arg => "foofoofoo" } );

    is_deeply( $errors->get( "foo" ), { ml_key => ".error.foo", message => '[missing string .error.foo]', ml_args => { foo_arg => "foofoofoo" } },
                "error foo with argument (get)" );
    is_deeply(
        $errors->get_all,
        [ { key => "foo", ml_key => ".error.foo", message => '[missing string .error.foo]', ml_args => { foo_arg => "foofoofoo" } } ],
        "error foo with argument (get_all)" );
}
1;
