package LJ::EventLogRecord::PropChanged;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, %info) = @_;

    return $class->SUPER::new(
                              userid => $info{userid},
                              prop   => $info{prop},
                              value  => $info{value},
                              );
}

sub event_type { 'prop_changed' }

1;
