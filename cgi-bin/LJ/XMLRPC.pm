package LJ::XMLRPC;
use strict;

use vars qw/ $AUTOLOAD /;

sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://;
    LJ::Protocol::xmlrpc_method($method, @_);
}


1;
