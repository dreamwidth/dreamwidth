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
    my ($select_box, $search_btn);

    my @search_opts = (
        'int' => $class->ml('.widget.search.interest'),
        'region' => $class->ml('.widget.search.region'),
        'user' => $class->ml('.widget.search.username'),
        'email' => $class->ml('.widget.search.email'),
        'aolim' => $class->ml('.widget.search.aim'),
        'icq' => $class->ml('.widget.search.icq'),
        'jabber' => $class->ml('.widget.search.jabber'),
        'msn' => $class->ml('.widget.search.msn'),
        'yahoo' => $class->ml('.widget.search.yahoo'),
    );

    if ($single_search eq "interest") {
        $ret .= "<p class='search-interestonly'>" . $class->ml('widget.search.interestonly') . "</p>";
        $select_box = LJ::html_hidden( type => "int" );
        $search_btn = LJ::html_submit($class->ml('widget.search.interestonly.btn'));
    } else {
        $ret .= "<h2>" . $class->ml('.widget.search.title') . "</h2>\n";
        $select_box = LJ::html_select({name => 'type', selected => 'int', class => 'select'}, @search_opts) . " ";
        $search_btn = LJ::html_submit($class->ml('.widget.search.submit'));
    }

    $ret .= "<form action='$LJ::SITEROOT/multisearch.bml' method='post'>\n";
    $ret .= $select_box;
    $ret .= LJ::html_text({name => 'q', 'class' => 'text', 'size' => 30}) . " ";
    $ret .= $search_btn;
    $ret .= "</form>";

    return $ret;
}

1;
