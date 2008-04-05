package LJ::PersistentQueue;

use strict;
use warnings;
use Data::Queue::Persistent;

sub new {
    my ($class, %opts) = @_;

    my $dbh = delete $opts{dbh} || LJ::get_db_writer();

    return Data::Queue::Persistent->new(
                                        table => 'persistent_queue',
                                        cache => 0,
                                        dbh   => $dbh,
                                        %opts,
                                        );
}



package LJ;

sub queue {
    my ($id, $size) = @_;

    return LJ::PersistentQueue->new(id => $id, max_size => $size);
}


1;
