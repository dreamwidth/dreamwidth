package LJ::Widget::AddVerticalEditorials;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical LJ::VerticalEditorials );

sub need_res { qw( js/widgets/addverticaleditorials.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $get = delete $opts{get};
    my $post = delete $opts{post};

    my $edid = $get->{edid};
    my ($vertid, $title, $editor, $img_url, $img_link_url, $submitter);
    my ($block_1_title, $block_2_title, $block_3_title, $block_4_title);
    my ($block_1_text, $block_2_text, $block_3_text, $block_4_text);
    my ($start_month, $start_day, $start_year);
    my ($end_month, $end_day, $end_year);

    if ($edid || ($post && keys %$post)) {
        my $editorial;
        if ($post && keys %$post) {
            $editorial = $post;
        } else {
            $editorial = LJ::VerticalEditorials->get_single_editorial_group($edid)
                or die "Invalid editorial: $edid";

            my $vertical = LJ::Vertical->load_by_id($editorial->{vertid});
            die "You do not have permission to edit this editorial." unless $vertical && $vertical->remote_is_moderator;
        }

        $vertid = $editorial->{vertid};
        $title = $editorial->{title};
        $editor = $editorial->{editor};
        $img_url = $editorial->{img_url};
        $img_link_url = $editorial->{img_link_url};
        $submitter = $editorial->{submitter};
        $block_1_title = $editorial->{block_1_title};
        $block_2_title = $editorial->{block_2_title};
        $block_3_title = $editorial->{block_3_title};
        $block_4_title = $editorial->{block_4_title};
        $block_1_text = $editorial->{block_1_text};
        $block_2_text = $editorial->{block_2_text};
        $block_3_text = $editorial->{block_3_text};
        $block_4_text = $editorial->{block_4_text};

        if ($post && keys %$post) {
            $start_month = $editorial->{start_month};
            $start_day = $editorial->{start_day};
            $start_year = $editorial->{start_year};
            $end_month = $editorial->{end_month};
            $end_day = $editorial->{end_day};
            $end_year = $editorial->{end_year};
        } else {
            my $start_date = DateTime->from_epoch( epoch => $editorial->{time_start}, time_zone => 'America/Los_Angeles' );
            my $end_date = DateTime->from_epoch( epoch => $editorial->{time_end}, time_zone => 'America/Los_Angeles' );
            $start_month = $start_date->month;
            $start_day = $start_date->day;
            $start_year = $start_date->year;
            $end_month = $end_date->month;
            $end_day = $end_date->day;
            $end_year = $end_date->year;
        }
    }

    # default values for year/month/day = today's date
    # unless we're editing, in which case use the given question's dates
    my $time_now = DateTime->now( time_zone => 'America/Los_Angeles' );
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
    my $ret = "<?p Add new editorial content: p?>";

    $ret .= $class->start_form( id => "editorial_form" );

    $ret .= "<table cellspacing='5'><tr><td valign='top'>Select Vertical:</td><td>";
    $ret .= $class->html_select(
        name => 'vertid',
        id => 'vertid',
        selected => $vertid || 0,
        list => [ "0", "(Choose one)", map { $_->vertid, $_->display_name } LJ::Vertical->load_for_editorials ],
    ) . "</td></tr>";

    $ret .= "<tr><td>Start Date:</td><td>";
    $ret .= $class->html_select(
        name => 'start_month',
        selected => $start_month,
        list => [ map { $_, LJ::Lang::month_long($_) } 1..12 ],
    ) . " ";

    $ret .= $class->html_text(
        name => 'start_day',
        size => 2,
        maxlength => 2,
        value => $start_day,
    ) . " ";

    $ret .= $class->html_text(
        name => 'start_year',
        size => 4,
        maxlength => 4,
        value => $start_year,
    ) . " @ 12:00 AM</td></tr>";

    $ret .= "<tr><td>End Date:</td><td>";
    $ret .= $class->html_select(
        name => 'end_month',
        selected => $end_month,
        list => [ map { $_, LJ::Lang::month_long($_) } 1..12 ],
    ) . " ";

    $ret .= $class->html_text(
        name => 'end_day',
        size => 2,
        maxlength => 2,
        value => $end_day,
    ) . " ";

    $ret .= $class->html_text(
        name => 'end_year',
        size => 4,
        maxlength => 4,
        value => $end_year,
    ) . " @ 11:59 PM</td></tr>";

    $ret .= "<tr><td valign='top'>Title:</td><td>";
    $ret .= $class->html_text(
        name => 'title',
        size => 30,
        value => $title ) . "<br /><small>limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td valign='top'>Editor (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'editor',
        size => 30,
        value => $editor ) . "<br /><small>limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td valign='top'>Image or Video (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'img_url',
        size => 30,
        value => $img_url ) . "<br /><small>input either the URL to an image or the embed code for a video<small></td></tr>";

    $ret .= "<tr><td valign='top'>Link URL for Image (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'img_link_url',
        size => 30,
        value => $img_link_url ) . "<br /><small>use only to link an image to a specific entry (will not work for videos)<small></td></tr>";

    $ret .= "<tr><td valign='top'>Submitted by (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'submitter',
        size => 30,
        value => $submitter ) . "<br /><small>limited HTML allowed; only displays if image or video is entered<small></td></tr>";

    $ret .= "<tr><td valign='top' rowspan='2'>Block #1 (header optional):</td><td>";
    $ret .= $class->html_text(
        name => 'block_1_title',
        size => 30,
        value => $block_1_title ) . "<br /><small>limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td>";
    $ret .= $class->html_textarea(
        name => 'block_1_text',
        rows => 10,
        cols => 60,
        wrap => 'soft',
        value => $block_1_text,
    ) . "<br /><small>HTML allowed</small></td></tr>";

    $ret .= "<tr><td valign='top' rowspan='2'>Block #2 (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'block_2_title',
        size => 30,
        value => $block_2_title ) . "<br /><small>limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td>";
    $ret .= $class->html_textarea(
        name => 'block_2_text',
        rows => 10,
        cols => 60,
        wrap => 'soft',
        value => $block_2_text,
    ) . "<br /><small>HTML allowed</small></td></tr>";

    $ret .= "<tr><td valign='top' rowspan='2'>Block #3 (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'block_3_title',
        size => 30,
        value => $block_3_title ) . "<br /><small>limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td>";
    $ret .= $class->html_textarea(
        name => 'block_3_text',
        rows => 10,
        cols => 60,
        wrap => 'soft',
        value => $block_3_text,
    ) . "<br /><small>HTML allowed</small></td></tr>";

    $ret .= "<tr><td valign='top' rowspan='2'>Block #4 (optional):</td><td>";
    $ret .= $class->html_text(
        name => 'block_4_title',
        size => 30,
        value => $block_4_title ) . "<br /><small>limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td>";
    $ret .= $class->html_textarea(
        name => 'block_4_text',
        rows => 10,
        cols => 60,
        wrap => 'soft',
        value => $block_4_text,
    ) . "<br /><small>HTML allowed</small></td></tr>";

    $ret .= $class->html_hidden
        ( edid => $edid );

    $ret .= "<tr><td colspan='2' align='center'>";
    $ret .= "<input type='button' id='preview_btn' value='Preview' /> ";
    $ret .= $class->html_submit('Save') . "</td></tr>";
    $ret .= "</table>";
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();

    my $vertical = LJ::Vertical->load_by_id($post->{vertid});

    # make sure the vertical chosen is valid
    die "Selected vertical is invalid." unless $vertical && $vertical->has_editorials;

    # make sure remote can add to this vertical's editorials
    die "You do not have permission to add this editorial." unless $vertical->remote_is_moderator;

    my $time_start = DateTime->new(
        year => $post->{start_year}+0,
        month => $post->{start_month}+0,
        day => $post->{start_day}+0,
        time_zone => 'America/Los_Angeles',
    );

    my $time_end = DateTime->new(
        year      => $post->{end_year}+0,
        month     => $post->{end_month}+0,
        day       => $post->{end_day}+0,
        hour      => 23,
        minute    => 59,
        second    => 59,
        time_zone => 'America/Los_Angeles',
    );

    # make sure the start time is before the end time
    if (DateTime->compare($time_start, $time_end) != -1) {
        die "Start time must be before end time";
    }

    # make sure there's a title and block 1 is filled out
    die "No title specified." unless $post->{title};
    die "No block #1 text specified." unless $post->{block_1_text};

    # make sure that all links to entries in the block text areas are entries that can be added to verticals by admins
    foreach my $i (1..4) {
        my $html = $post->{"block_${i}_text"};
        if ($html) {
            my $link_urls = LJ::html_get_link_urls(\$html);
            foreach my $url (@$link_urls) {
                my $entry = LJ::Entry->new_from_url($url);
                if ($entry) {
                    die "This entry URL should not be shown in explore areas: " . $entry->url
                        unless $entry->can_be_added_to_verticals_by_admin( ignore_image_restrictions => 1 );
                }
            }
        }
    }

    LJ::VerticalEditorials->store_editorials(
         edid => $post->{edid},
         vertid => $post->{vertid},
         adminid => $remote->id,
         time_start => $time_start->epoch,
         time_end => $time_end->epoch,
         title => $post->{title},
         editor => $post->{editor},
         img_url => $post->{img_url},
         img_link_url => LJ::CleanHTML::canonical_url($post->{img_link_url}),
         submitter => $post->{submitter},
         block_1_title => $post->{block_1_title},
         block_1_text => $post->{block_1_text},
         block_2_title => $post->{block_2_title},
         block_2_text => $post->{block_2_text},
         block_3_title => $post->{block_3_title},
         block_3_text => $post->{block_3_text},
         block_4_title => $post->{block_4_title},
         block_4_text => $post->{block_4_text},
    );

    return;
}

1;
