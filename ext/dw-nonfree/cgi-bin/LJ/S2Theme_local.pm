package LJ::S2Theme;
use strict;
use Carp qw(croak);

sub local_default_themes {
    return (
        colorside      => 'colorside/nadeshiko',
        modish         => 'modish/scarlet',
        sundaymorning  => 'sundaymorning/greensquiggle',
        transmogrified => 'transmogrified/basic',
    );
}

1;
