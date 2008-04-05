# new_entry
#         URL
#         journal.userid
#         journal.user
#         poster.caps
#         journal.caps
#         journal.type
#         ditemid
#         security {public, protected, private}


package LJ::EventLogRecord::NewEntry;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $e) = @_;

    croak "Must pass an LJ::Entry"
        unless UNIVERSAL::isa($e, 'LJ::Entry');

    my %args = (
                'ditemid'        => $e->ditemid,
                'journal.userid' => $e->journal->userid,
                'journal.user'   => $e->journal->user,
                'poster.caps'    => $e->poster->caps,
                'poster.userid'  => $e->poster->userid,
                'journal.caps'   => $e->journal->caps,
                'journal.type'   => $e->journal->journaltype,
                'security'       => $e->security,
                );

    # qotdid if one is associated with this entry
    if (my $qotdid = $e->prop('qotdid')) {
        $args{'prop.qotdid'} = $e->prop('qotdid');
    }

    return $class->SUPER::new(%args);
}

sub event_type { 'new_entry' }

1;
