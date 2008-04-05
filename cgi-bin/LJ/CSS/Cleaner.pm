package LJ::CSS::Cleaner;

use strict;
use warnings;
no warnings 'redefine';

use base 'CSS::Cleaner';

sub new {
    my $class = shift;
    return $class->SUPER::new( @_,
        pre_hook => sub {
            my $rref = shift;

            $$rref =~ s/comment-bake-cookie/CLEANED/g;
            return;
        },
    );
}

1;
