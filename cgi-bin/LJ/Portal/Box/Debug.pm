package LJ::Portal::Box::Debug; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'Debug';
our $_box_name = "Debug";
our $_box_class = "Debug";

sub generate_content {
    my $self = shift;

    if ($LJ::PORTAL_DEBUG_CONTENT) {
        return qq {
            <pre>$LJ::PORTAL_DEBUG_CONTENT
            </pre>
        };
    }

    return "No debug data.";
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

# hide this box in the add module menu
sub box_hidden { 1; };

1;
