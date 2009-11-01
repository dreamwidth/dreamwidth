package LJ::S2Theme::blanket;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column" ) }
sub layout_prop { "layout_type" }

sub designer { "renoir" }

sub header_props {
    my $self = shift;
    my @props = qw( color_header_footer_border );
    return $self->_append_props( "header_props", @props );
}

package LJ::S2Theme::blanket::nnwm2009;
use base qw( LJ::S2Theme::blanket );
sub cats { qw( ) }
sub designer { "zvi" }

package LJ::S2Theme::blanket::peach;
use base qw( LJ::S2Theme::blanket );
sub cats { qw( base ) }

package LJ::S2Theme::blanket::sprung;
use base qw( LJ::S2Theme::blanket );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::blanket::thetealandthegrey;
use base qw( LJ::S2Theme::blanket );
sub cats { qw( ) }
sub designer { "twtd" }

1;

