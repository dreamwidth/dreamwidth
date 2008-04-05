package LJ::Widget::AddQotD;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::QotD );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $qid = $opts{qid};
    my (@classes, $show_logged_out);
    my ($subject, $text, $tags, $from_user, $img_url, $extra_text, $countries, $link_url);
    my ($start_month, $start_day, $start_year);
    my ($end_month, $end_day, $end_year);
    if ($qid) {
        my $question = LJ::QotD->get_single_question($opts{qid})
            or die "Invalid question: $qid";

        @classes = LJ::classes_from_mask($question->{cap_mask});
        $show_logged_out = $question->{show_logged_out} eq 'Y' ? 1 : 0;

        $subject = $question->{subject};
        $text = $question->{text};
        $tags = LJ::QotD->remove_default_tags($question->{tags});
        $from_user = $question->{from_user};
        $img_url = $question->{img_url};
        $extra_text = $question->{extra_text};
        $countries = $question->{countries};
        $link_url = $question->{link_url};

        my $start_date = DateTime->from_epoch( epoch => $question->{time_start}, time_zone => 'America/Los_Angeles' );
        my $end_date = DateTime->from_epoch( epoch => $question->{time_end}, time_zone => 'America/Los_Angeles' );
        $start_month = $start_date->month;
        $start_day = $start_date->day;
        $start_year = $start_date->year;
        $end_month = $end_date->month;
        $end_day = $end_date->day;
        $end_year = $end_date->year;
    }

    # default values for year/month/day = today's date
    # unless we're editing, in which case use the given question's dates
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
        "<?p (<a href='$LJ::SITEROOT/admin/qotd/manage.bml'>" . 
        "Manage questions</a>) p?>" . 
        "<?p Enter a new Question of the Day. p?>";

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

    $ret .= "<tr><td valign='top'>Subject:</td><td>";
    $ret .= $class->html_text
        ( name => 'subject',
          size => 30,
          value => $subject ) . "<br /><small>\"Writer's Block\" will be prepended to the given subject; limited HTML allowed<small></td></tr>";

    $ret .= "<tr><td valign='top'>Question:</td><td>";
    $ret .= $class->html_textarea
        ( name => 'text',
          raw => 5,
          cols => 30,
          wrap => 'soft',
          value => $text ) . "<br /><small>HTML allowed</small></td></tr>";

    $ret .= "<tr><td valign='top'>Entry Tags (optional):</td><td>";
    $ret .= $class->html_text
        ( name => 'tags',
          size => 30,
          value => $tags ) . "<br /><small>\"writer's block\" will always be included as a tag automatically</small></td></tr>";

    $ret .= "<tr><td valign='top'>Submitted By (optional):</td><td>";
    $ret .= $class->html_text
        ( name => 'from_user',
          size => 15,
          maxlength => 15,
          value => $from_user ) . "<br /><small>Enter a $LJ::SITENAMESHORT username<small></td></tr>";

    $ret .= "<tr><td>Image URL (optional):</td><td>";
    $ret .= $class->html_text
        ( name => 'img_url',
          size => 30,
          value => $img_url ) . "</td></tr>";

    $ret .= "<tr><td>Link URL for Image (optional):</td><td>";
    $ret .= $class->html_text
        ( name => 'link_url',
          size => 30,
          value => $link_url ) . "</td></tr>";

    $ret .= "<tr><td valign='top'>" . $class->ml('widget.addqotd.extratext') . "</td><td>";
    $ret .= $class->html_textarea
        ( name => 'extra_text',
          raw => 5,
          cols => 30,
          wrap => 'soft',
          value => $extra_text ) . "<br /><small>" . $class->ml('widget.addqotd.extratext.note') . "</small></td></tr>";

    my $hook_rv = LJ::run_hook("qotd_class_checkboxes", class => $class, classes => \@classes, show_logged_out => $show_logged_out);

    if ($hook_rv) {
        $ret .= "<tr><td valign='top'>$hook_rv";

        $ret .= "who are in the following countries (comma-separated list of country codes, e.g. us,uk,fr,es):<br />";
        $ret .= $class->html_text
            ( name => 'countries',
              size => 30,
              value => $countries ) . "<br /><small>(if left blank, a user's country will be ignored)</small></td></tr>";
    } else {
        my $classes_string = join(',', @classes);

        $ret .= "<tr><td valign='top'>Show this question to users in these classes:</td><td>";
        $ret .= $class->html_text
            ( name => 'classes',
              size => 30,
              value => $classes_string ) . "<br /><small>(comma-separated list)</small><br />";

        $ret .= $class->html_check
            ( name => 'show_logged_out',
              id => 'show_logged_out',
              selected => $show_logged_out ) . " <label for='show_logged_out'>Show to Logged Out Users?</label></td></tr>";

        $ret .= "<tr><td valign='top'>Show this question to users in the following countries:</td><td>";
        $ret .= $class->html_text
            ( name => 'countries',
              size => 30,
              value => $countries ) . "<br /><small>(comma-separated list of country codes, e.g. us,uk,fr,es)<br />(if left blank, a user's country will be ignored)</small></td></tr>";
    }

    $ret .= $class->html_hidden
        ( qid => $qid );

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

    # Make sure there's a subject and text
    die "No question subject specified." unless $post->{subject};
    die "No question text specified." unless $post->{text};

    # Make sure the from_user is valid (if given)
    my $from_user = $post->{from_user};
    if ($from_user) {
        my $from_u = LJ::load_user($from_user);
        die "Invalid user: $from_user" unless LJ::isu($from_u);
    }

    LJ::run_hook("qotd_class_checkboxes_post", $post);

    # Make sure at least one class was given
    die "At least one class of users must be given."
        unless $post->{classes} || $post->{show_logged_out};

    # Make sure the country list is valid
    my $countries = $post->{countries};
    my %country_codes;
    LJ::load_codes({ country => \%country_codes });
    my @given_countries = split(/\s*,\s*/, $countries);
    foreach my $cc (@given_countries) {
        $cc = uc $cc;
        next if $country_codes{$cc};
        die "Invalid country code: $cc";
    }

    # Pass the countries to the db as a comma-separated list with no spaces, all lowercase
    $countries = join(',', @given_countries);
    $countries = lc $countries;

    LJ::QotD->store_question (
         qid        => $post->{qid},
         time_start => $time_start->epoch,
         time_end   => $time_end->epoch,
         active     => 'Y',
         subject    => $post->{subject},
         text       => $post->{text},
         from_user  => $post->{from_user},
         tags       => LJ::QotD->add_default_tags($post->{tags}),
         img_url    => LJ::CleanHTML::canonical_url($post->{img_url}),
         extra_text => $post->{extra_text},
         classes => $post->{classes},
         show_logged_out => $post->{show_logged_out},
         countries  => $countries,
         link_url   => LJ::CleanHTML::canonical_url($post->{link_url}),
    );

    return;
}

1;
