package LJ::EventLogRecord::UpdateUser;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, %info) = @_;

    return $class->SUPER::new(
                              userid => $info{userid},
                              field  => $info{field},
                              value  => $info{value},
                              );
}

sub event_type { 'update_user' }

1;
