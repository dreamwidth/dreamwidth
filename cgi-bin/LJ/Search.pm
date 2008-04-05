package LJ::Search;
use strict;
use Carp qw (croak);

our $searcher;

# returns a search client
sub client {
    my ($class) = @_;

    unless ($searcher) {
        $searcher = LJ::run_hook("content_search_client");
    }

    return $searcher;
}

# returns a new document with the data in %opts
sub document {
    my ($class, %opts) = @_;

    return LJ::run_hook("content_search_document", %opts);
}

1;


