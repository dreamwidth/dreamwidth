package LJ::Widget::VerticalEditorialSnippets;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical LJ::VerticalEditorials );

sub need_res { qw( stc/widgets/verticaleditorialsnippets.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $verticals = LJ::VerticalEditorials->get_random_editorial_snippet_group;
    my $ret;

    my $count = 0;

    $ret .= "<table cellspacing='0' cellpadding='5'>";
    foreach my $vertname (@$verticals) {
        my $vertical = LJ::Vertical->load_by_name($vertname);
        my $editorial = LJ::VerticalEditorials->get_editorial_for_vertical( vertical => $vertical );

        foreach my $item ($editorial->{title}, $editorial->{block_1_title}, $editorial->{block_2_title}, $editorial->{block_3_title},
                          $editorial->{block_4_title}) {
            LJ::CleanHTML::clean_subject(\$item);
        }
        foreach my $item ($editorial->{block_1_text}, $editorial->{block_2_text}, $editorial->{block_3_text}, $editorial->{block_4_text}) {
            LJ::CleanHTML::clean_event(\$item);
        }

        my $main_title = $editorial->{title};
        next unless $main_title;

        my @blocks;
        foreach my $item ($editorial->{block_1_title}, $editorial->{block_1_text}, $editorial->{block_2_title}, $editorial->{block_2_text},
                          $editorial->{block_3_title}, $editorial->{block_3_text}, $editorial->{block_4_title}, $editorial->{block_4_text}) {
            push @blocks, LJ::strip_html($item) if $item;
        }

        my $block_text = join(". ", @blocks);
        my $trimmed_block_text = LJ::text_trim($block_text, 150);
        next unless $trimmed_block_text;

        $ret .= "<tr valign='top'>" if $count % 2 == 0;
        $ret .= "<td class='snippet'><fieldset>";
        $ret .= "<legend class='heading'>" . $class->ml('widget.verticaleditorialsnippets.heading', { vertname => $vertical->display_name }) . "</legend>";
        $ret .= "<p class='title'><a href='" . $vertical->url . "'>$main_title</a></p>";
        $ret .= "<p class='text'>";
        $ret .= $trimmed_block_text eq $block_text ? $trimmed_block_text : "$trimmed_block_text&hellip;";
        $ret .= "</fieldset></td>";
        $ret .= "</tr>" if $count % 2 == 1;

        $count++;
    }
    $ret .= "</table>";

    my %shown_verticals = map { $_ => 1 } @$verticals;
    my @other_verticals;
    foreach my $vertical (LJ::Vertical->load_top_level) {
        unless ($shown_verticals{$vertical->name}) {
            push @other_verticals, "<a href='" . $vertical->url . "'>" . $vertical->display_name . "</a>";
        }
    }

    my $vertical_list = join(" | ", @other_verticals);
    if ($vertical_list) {
        $ret .= "<p class='moreverts'>" . $class->ml('widget.verticaleditorialsnippets.moreverts', { verticallist => $vertical_list }) . "</p>";
    }

    return $ret;
}

1;
