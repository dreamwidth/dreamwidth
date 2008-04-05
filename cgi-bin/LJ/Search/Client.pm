package LJ::Search::Client;
use strict;
use Carp qw ( croak );

# This is a placeholder class; the real search client class will be
# loaded by the content_search_client hook.

sub new {
    croak "Tried to instantiate LJ::Search::Client base class";
}

1;
