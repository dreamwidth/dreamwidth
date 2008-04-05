# session_expired
#         userid
#         sessionid

package LJ::EventLogRecord::SessionExpired;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $sess) = @_;

    croak "Must pass an LJ::Session"
        unless UNIVERSAL::isa($sess, 'LJ::Session');

    return $class->SUPER::new(
                              userid => $sess->owner->userid,
                              id     => $sess->id,
                              );
}

sub event_type { 'session_expired' }

1;
