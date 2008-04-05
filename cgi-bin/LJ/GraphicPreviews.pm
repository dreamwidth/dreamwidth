package LJ::GraphicPreviews;
use strict;
use Carp qw(croak);

# loads a graphic preview object
sub new {
    my ($class) = @_;

    my $self = {};

    bless $self, $class;
    return $self;
}

# returns the code for rendering a graphic preview
sub render {
    my $self = shift;
    my $journalu = shift;

    return "";
}

# returns whether the feature is enabled at all
sub is_enabled {
    my $self = shift;
    my $journalu = shift;

    return 0;
}

# returns whether the graphic preview should be rendered
sub should_render {
    my $self = shift;
    my $journalu = shift;

    return 0;
}

# need res stuff that needs to be included on journal pages
sub need_res {
    my $self = shift;
    my $journalu = shift;

    return undef;
}

1;
