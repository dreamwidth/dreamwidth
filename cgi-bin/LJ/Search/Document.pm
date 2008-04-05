package LJ::Search::Document;
use strict;
use Carp qw ( croak );

# This represents a search document. Search document subclasses should
# be returned by the content_search_document hook.

sub new {
    croak "Tried to instantiate LJ::Search::Client base class";
}

# id of document
sub id {}

# body of document
sub body {}

# date of document
sub date {}

# subject of document
sub subject {}

# list of fields in the document
sub fields {}

# returns if a field is a date field
sub is_date {}

# boost $field, $value
sub boost {}

1;
