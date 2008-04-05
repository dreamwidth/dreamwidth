use strict;
package LJ::Intercast::Handler::GetCommenterOptions;
use base 'LJ::Intercast::Handler';

sub handle {
    my ($class, $reqopts) = @_;

    my $retopts = [
                   ['commenter_id',
                    'commenter_name'],

                   [0, 'Allow comments'],
                   [1, 'Disallow comments'],
                   ];

    my %ret = (
               status      => "OK",
               code        => 0,
               total_items => 2,
               results     => $retopts,
               );

    return JSON::objToJson(\%ret);
}

sub owns { $_[1] eq 'Member::getCommenterOptions' }

1;
