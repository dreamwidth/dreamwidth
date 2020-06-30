package LJ::Mock;

use v5.10;
use strict;
no warnings 'uninitialized';

use Test::MockObject;

sub temp_user {
    my $u = Test::MockObject->new();
    $u->mock( 'user',           sub { return 'temp'; } );
    $u->mock( 'ljuser_display', sub { return LJ::ljuser('temp'); } );
    return $u;
}

1;
