package LJ::Widget::AddSiteMessages;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::SiteMessages );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $mid = $opts{mid};
    my $text;
    my ($start_month, $start_day, $start_year);
    my ($end_month, $end_day, $end_year);
    if ($mid) {
        my $message = LJ::SiteMessages->get_single_message($opts{mid})
            or die "Invalid question: $mid";

        $text = $message->{text};

        my $start_date = DateTime->from_epoch( epoch => $message->{time_start}, time_zone => 'America/Los_Angeles' );
        my $end_date = DateTime->from_epoch( epoch => $message->{time_end}, time_zone => 'America/Los_Angeles' );
        $start_month = $start_date->month;
        $start_day = $start_date->day;
        $start_year = $start_date->year;
        $end_month = $end_date->month;
        $end_day = $end_date->day;
        $end_year = $end_date->year;
    }

    # default values for year/month/day = today's date
    # unless we're editing, in which case use the given message's dates
    my $time_now = DateTime->now(time_zone => 'America/Los_Angeles');
    unless ($start_month && $start_day && $start_year) {
        $start_month = $time_now->month;
        $start_day = $time_now->day;
        $start_year = $time_now->year;
    }
    unless ($end_month && $end_day && $end_year) {
        $end_month = $time_now->month;
        $end_day = $time_now->day;
        $end_year = $time_now->year;
    }

    # form entry
    my $ret =
        "<?p (<a href='$LJ::SITEROOT/admin/sitemessages/manage.bml'>" . 
        "Manage site messages</a>) p?>" . 
        "<?p Enter a new site message. p?>";

    $ret .= $class->start_form;

    $ret .= "<table><tr><td>Start Date:</td><td>";
    $ret .= $class->html_select
        ( name => 'month_start',
          selected => $start_month,
          list => [ map { $_, LJ::Lang::month_long($_) } 1..12 ] ) . " ";

    $ret .= $class->html_text
        ( name => 'day_start',
          size => 2,
          maxlength => 2,
          value => $start_day ) . " ";

    $ret .= $class->html_text
        ( name => 'year_start',
          size => 4,
          maxlength => 4,
          value => $start_year ) . " @ 12:00 AM</td></tr>";

    $ret .= "<tr><td>End Date:</td><td>";
    $ret .= $class->html_select
        ( name => 'month_end',
          selected => $end_month,
          list => [ map { $_, LJ::Lang::month_long($_) } 1..12 ] ) . " ";

    $ret .= $class->html_text
        ( name => 'day_end',
          size => 2,
          maxlength => 2,
          value => $end_day ) . " ";

    $ret .= $class->html_text
        ( name => 'year_end',
          size => 4,
          maxlength => 4,
          value => $end_year ) . " @ 11:59 PM</td></tr>";

    $ret .= "<tr><td valign='top'>Message:</td><td>";
    $ret .= $class->html_textarea
        ( name => 'text',
          raw => 5,
          cols => 30,
          wrap => 'soft',
          value => $text ) . "</td></tr>";

    $ret .= $class->html_hidden
        ( mid => $mid );

    $ret .= "<tr><td colspan='2' align='center'>";
    $ret .= $class->html_submit('Submit') . "</td></tr>";
    $ret .= "</table>";
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $time_start = DateTime->new
        ( year      => $post->{year_start}+0, 
          month     => $post->{month_start}+0, 
          day       => $post->{day_start}+0, 

          # Yes, this specific timezone
          time_zone => 'America/Los_Angeles' );

    my $time_end = DateTime->new
        ( year      => $post->{year_end}+0, 
          month     => $post->{month_end}+0, 
          day       => $post->{day_end}+0, 
          hour      => 23, 
          minute    => 59, 
          second    => 59, 

          # Yes, this specific timezone
          time_zone => 'America/Los_Angeles' );

    # Make sure the start time is before the end time
    if (DateTime->compare($time_start, $time_end) != -1) {
        die "Start time must be before end time";
    }

    LJ::SiteMessages->store_message (
         mid        => $post->{mid},
         time_start => $time_start->epoch,
         time_end   => $time_end->epoch,
         active     => 'Y',
         text       => $post->{text},
    );

    return;
}

1;
