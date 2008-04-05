package LJ::S2Theme::digitalmultiplex;
use base qw(LJ::S2Theme);

sub layouts { ( "2r" => 1 ) }
sub cats { qw( clean modern ) }
sub desginer { "Jesse Proulx" }
sub linklist_support_tab { "Sidebar" }

sub display_option_props {
    my $self = shift;
    my @props = qw( leading_full_entries );
    return $self->_append_props("display_option_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( main_fgcolor main_link_color );
    return $self->_append_props("text_props", @props);
}

sub header_bar_props {
    my $self = shift;
    my @props = qw( heading_bgcolor heading_fgcolor heading_link_color );
    return $self->_append_props("header_bar_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw( sidebar_bgcolor sidebar_box_bgcolor sidebar_box_fgcolor sidebar_title_bgcolor sidebar_title_fgcolor );
    return $self->_append_props("sidebar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( text_meta_music text_meta_mood text_meta_location text_meta_groups );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw( comment_bar_one_bgcolor comment_bar_one_fgcolor comment_bar_screened_bgcolor comment_bar_screened_fgcolor );
    return $self->_append_props("comment_props", @props);
}

sub setup_props {
    my $self = shift;
    my @props = qw( sidebar_width sidebar_profile_text sidebar_blurb sidebar_disable_recent_summary );
    return $self->_append_props("setup_props", @props);
}

sub ordering_props {
    my $self = shift;
    my @props = qw( sidebar_position_one sidebar_position_two sidebar_position_three sidebar_position_four sidebar_position_five );
    return $self->_append_props("ordering_props", @props);
}

1;
