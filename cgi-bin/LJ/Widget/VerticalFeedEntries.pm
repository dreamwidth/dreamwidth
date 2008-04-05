package LJ::Widget::VerticalFeedEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/verticalfeedentries.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $vertical = $opts{vertical};
    die "Invalid vertical object passed to widget." unless $vertical;

    my $u = LJ::load_user($vertical->feed);
    return "" unless $u && $u->is_syndicated;

    my @entries;
    my $memkey = "verticalfeedentries:" . $vertical->vertid;
    if (my $memcache_data = LJ::MemCache::get($memkey)) {
        @entries = @{$memcache_data};
    } else {
        my $num = $opts{num} || 4;
        @entries = $u->recent_entries( count => $num, order => "logtime" );
        @entries = sort { $b->jitemid <=> $a->jitemid } @entries;
        LJ::MemCache::set($memkey, \@entries, 60); # 1 minute
    }

    my $feed_display = LJ::run_hook("verticalfeedentries_display", class => $class, vertical => $vertical, entries => \@entries);
    return $feed_display if $feed_display;

    my $ret;
    foreach my $entry (@entries) {
        next unless $entry;
        my $link = $entry->syn_link;
        next unless $link;

        $ret .= "<a href='$link'>";
        $ret .= $entry->subject_text || "<em>" . $class->ml('widget.verticalfeedentries.nosubject') . "</em>";
        $ret .= "</a><br />";
    }

    return $ret;
}

1;
