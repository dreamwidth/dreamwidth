package LJ::Portal::Box::CProd; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "CProd";
our $_box_description = 'Frank the Goat thinks you might enjoy these features';
our $_box_name = "What else has LJ been hiding?";

sub generate_content {
    my $self = shift;

    my $u = $self->{u};
    my $box = LJ::CProd->full_box_for($u, style => 'plain');
    return $box;
}

# mark this cprod as having been viewed
sub box_updated {
    my $self = shift;

    my $u = $self->{u};
    my $prod = LJ::CProd->prod_to_show($u);
    LJ::CProd->mark_acked($u, $prod) if $prod;
    return 'CProd.attachNextClickListener();';
}

#######################################

sub box_description { $_box_description; }
sub box_name { $_box_name; }
sub box_class { $_box_class; }
sub can_refresh { 1 }

1;
