package LJ::Widget::RecentEntry;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;

    my %opts          = @_;
    my $num_to_show   = $opts{num_to_show} || 1;
    my $show_comments = exists $opts{show_comments} ? $opts{show_comments} : 1;
    my $journal       = $opts{journal};
    croak "no journal specified"
        unless $journal;
    my $journalu = LJ::load_user($journal);
    croak "invalid journal: $journal"
        unless LJ::isu($journalu);

    my $ret = "<h2>" . $journalu->name_html . "</h2>";

    my @items = LJ::get_recent_items({
        'userid'        => $journalu->id,
        'clusterid'     => $journalu->clusterid,
        'clustersource' => 'slave',
        'order'         => 'logtime',
        'itemshow'      => $num_to_show,
        'dateformat'    => 'S2',
    });

    my $entry;
    foreach my $item (@items) {
        # silly, there's no journalid in the hashref
        # returned here, so we'll shove it in to
        # construct an LJ::Entry object.  : (
        $item->{journalid} = $journalu->id;

        $entry = LJ::Entry->new_from_item_hash($item);
        next unless $entry->event_text;

        # Display date as YYYY-MM-DD
        my $date = substr($entry->eventtime_mysql, 0, 10);

        $ret .= "<div class='entry'>";

        $ret .= "<div class='date'>$date</div>";
        $ret .= "<div class='subject'>" . $entry->subject_html . "</div>";
        $ret .= "<div class='text'>" . $entry->event_html . "</div>";

        my $link = $entry->url;

        $ret .= "<div class='comments'>";
        if ($show_comments) {
            if (my $reply_ct = $entry->prop('replycount')) {
                $ret .= "<a href='$link'><strong>" . ($reply_ct == 1 ? "1 comment" : "$reply_ct comments") . "</strong></a>";
            } else {
                $ret .= "<a href='$link'><strong>Link</strong></a>";
            }
            unless ($entry->prop('opt_nocomments')) {
                $ret .= " | <a href='$link?mode=reply'><strong>Leave a comment</strong></a>";
            }
        } else {
            $ret .= "<a href='$link'><strong>Link</strong></a>";
        }
        $ret .= "</div>";

        $ret .= "</div>";
    }

    return $ret;
}

1;
