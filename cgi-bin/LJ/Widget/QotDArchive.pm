package LJ::Widget::QotDArchive;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::QotD;

sub need_res {
    return qw( stc/widgets/qotdarchive.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $page = $opts{page} > 0 ? $opts{page} : 1;
    my $num_questions_per_page = $opts{questions_per_page} > 0 ? $opts{questions_per_page} : 5;
    my @questions = LJ::QotD->get_questions( all => 1 );

    my $start_index = $num_questions_per_page * ($page - 1);
    my $end_index = ($num_questions_per_page * $page) - 1;

    my $ret;
    foreach my $q (@questions[$start_index..$end_index]) {
        last unless ref $q;
        $ret .= LJ::Widget::QotD->render( question => $q, archive => 1, nocontrols => 1 );
    }

    my $page_back = $page + 1;
    my $page_forward = $page - 1;
    my $show_page_back = ref $questions[$end_index + 1] ? 1 : 0;
    my $show_page_forward = $page_forward > 0 ? 1 : 0;

    $ret .= "<p class='skiplinks'>" if $show_page_back || $show_page_forward;
    if ($show_page_back) {
        $ret .= "<a href='$LJ::SITEROOT/misc/qotdarchive?page=$page_back'>&lt; " . $class->ml('widget.qotdarchive.skip.previous') . "</a>";
    }
    $ret .= " | " if $show_page_back && $show_page_forward;
    if ($show_page_forward) {
        my $url = $page_forward == 1 ? "$LJ::SITEROOT/misc/qotdarchive" : "$LJ::SITEROOT/misc/qotdarchive?page=$page_forward";
        $ret .= "<a href='$url'>" . $class->ml('widget.qotdarchive.skip.next') . " &gt;</a>";
    }
    $ret .= "</p>" if $show_page_back || $show_page_forward;

    return $ret;
}

1;
