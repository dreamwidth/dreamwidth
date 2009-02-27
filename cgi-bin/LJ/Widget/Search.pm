package LJ::Widget::Search;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/search.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $single_search = $opts{single_search};
    my ( $select_box, $search_btn );

    my @search_opts = (
        int => $class->ml( 'widget.search.interest' ),
        region => $class->ml( 'widget.search.region' ),
        nav_and_user => $class->ml( 'widget.search.siteuser' ),
        faq => $class->ml( 'widget.search.faq' ),
        email => $class->ml( 'widget.search.email' ),
        im => $class->ml( 'widget.search.iminfo' ),
    );

    if ( $single_search eq "interest" ) {
        $ret .= "<p class='search-interestonly'>" . $class->ml( 'widget.search.interestonly' ) . "</p>";
        $select_box = LJ::html_hidden( type => "int" );
        $search_btn = LJ::html_submit( $class->ml( 'widget.search.interestonly.btn' ) );
    } else {
        $select_box = LJ::html_select( { name => 'type', selected => 'int', class => 'select' }, @search_opts ) . " ";
        $search_btn = LJ::html_submit( $class->ml( 'widget.search.btn.go' ) );
    }

    $ret .= "<form action='$LJ::SITEROOT/multisearch.bml' method='post'>\n";
    $ret .= LJ::html_text( { name => 'q', id => 'search', class => 'text', title => $class->ml( 'widget.search.title' ), size => 20 } ) . " ";
    $ret .= $select_box;
    $ret .= $search_btn;
    $ret .= "</form>";

    return $ret;
}

1;
