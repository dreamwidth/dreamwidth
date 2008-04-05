package LJ::EventLogRecord::EditEntry;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $e) = @_;

    croak "Must pass an LJ::Entry"
        unless UNIVERSAL::isa($e, 'LJ::Entry');

    return $class->SUPER::new(
                              journalid => $e->journalid,
                              jitemid   => $e->jitemid,
                              );
}

sub event_type { 'edit_entry' }

1;
