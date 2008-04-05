# new_comment
#         jtalkid
#         ditemid
#         journal.userid
#         journal.user
#         poster.caps
#         security {public, protected, private}  (of ditemid)

package LJ::EventLogRecord::NewComment;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $c) = @_;

    croak "Must pass an LJ::Comment"
        unless UNIVERSAL::isa($c, 'LJ::Comment');

    return $class->SUPER::new(
                              'jtalkid'        => $c->jtalkid,
                              'ditemid'        => $c->entry->ditemid,
                              'journal.userid' => $c->journal->userid,
                              'journal.user'   => $c->journal->user,
                              'poster.caps'    => $c->poster ? $c->poster->caps : 0,
                              'poster.userid'  => $c->poster ? $c->poster->userid : 0,
                              'security'       => $c->entry->security,
                              );
}

sub event_type { 'new_comment' }

1;
