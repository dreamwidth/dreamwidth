package LJ::Widget::ManageVerticalEditorials;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical LJ::VerticalEditorials );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $get = delete $opts{get};

    my $ret = "";

    # default values for year/month
    my $year  = $get->{year}+0;
    my $month = $get->{month}+0;

    # if year and month aren't defined, use the current month
    unless ($year && $month) {
        my @time = localtime();
        $year  = $time[5]+1900;
        $month = $time[4]+1;
    }

    my @verticals = LJ::Vertical->load_for_editorials;
    my $vertname = $get->{vertical_name} || $verticals[0]->name;
    my $vertical = LJ::Vertical->load_by_name($vertname);

    $ret .= "<?p Select a month to view all editorials that are starting and running during that month. p?>";

    # TODO: supported way for widgets to do GET forms?
    #       -- lame that GET/POST is done differently in here
    $ret .= "<form method='GET'>";
    $ret .= "<?p Month: " . LJ::html_select({ name => 'month', selected => $month }, map { $_, LJ::Lang::month_long($_) } 1..12) . " ";
    $ret .= "Year: " . LJ::html_text({ name => 'year', size => '4', maxlength => '4', value => $year }) . " ";
    $ret .= "Vertical: " . LJ::html_select({ name => 'vertical_name', selected => $vertname }, map { $_->name, $_->display_name } @verticals) . " p?>";
    $ret .= "<?p " . LJ::html_submit('View Editorial Content') . " p?>";
    $ret .= "</form>";

    $ret .= "<hr style='clear: both;' />";

    return $ret . "<?p You do not have permission to manage these editorials. p?>" unless $vertical && $vertical->remote_is_moderator;

    my @editorials_running = LJ::VerticalEditorials->get_all_editorials_running_during_month($year, $month, $vertname);
    return $ret . "<?p No editorial content for this vertical could be found during this time period. p?>" unless @editorials_running;

    $ret .= $class->start_form;

    $ret .= "<strong>Editorials Running During Month</strong>";
    $ret .= $class->table_display(@editorials_running);
    $ret .= $class->html_hidden( vertname => $vertname );

    $ret .= $class->end_form;

    return $ret;
}

sub table_display {
    my $class = shift;
    my @editorials = @_;

    my $ret;
    $ret .= "<table border='1' cellpadding='3'>";
    $ret .= "<tr><th>Status</th><th>Edit</th><th>Image</th><th>Submitter</th><th>Title</th><th>Editor</th><th>Header #1</th><th>Body #1</th><th>Header #2</th><th>Body #2</th><th>Header #3</th><th>Body #3</th><th>Header #4</th><th>Body #4</th><th>Start Date</th><th>End Date</th><th>Admin</th><th>Delete</th></tr>";
    foreach my $row (@editorials) {
        my $start_date = DateTime->from_epoch( epoch => $row->{time_start}, time_zone => 'America/Los_Angeles' );
        my $end_date = DateTime->from_epoch( epoch => $row->{time_end}, time_zone => 'America/Los_Angeles' );
        my $time_now = DateTime->now( time_zone => 'America/Los_Angeles' );

        foreach my $item ($row->{title}, $row->{editor}, $row->{submitter}, $row->{block_1_title},
                          $row->{block_2_title}, $row->{block_3_title}, $row->{block_4_title}) {
            LJ::CleanHTML::clean_subject(\$item);
        }
        foreach my $item ($row->{block_1_text}, $row->{block_2_text}, $row->{block_3_text}, $row->{block_4_text}) {
            LJ::CleanHTML::clean_event(\$item);
        }

        $ret .= "<tr>";

        # status
        $ret .= "<td>";
        $ret .= $start_date <= $time_now && $end_date >= $time_now ? "active" : "inactive";
        $ret .= "</td>";

        # edit
        $ret .= "<td>" . $class->html_submit("edit:$row->{edid}", "edit") . "</td>";

        # image or video
        if ($row->{img_url} && $row->{img_url} =~ /[<>]/) { # HTML
            $ret .= "<td>(video)</td>";
        } elsif ($row->{img_url}) { # not HTML
            my $img_link_url = $row->{img_link_url} || $row->{img_url};
            $ret .= "<td><a href='$img_link_url'><img src='$row->{img_url}' width='100' height='100' border='0' /></a></td>";
        } else {
            $ret .= "<td>&nbsp;</td>";
        }

        # submitter
        $ret .= $row->{submitter} ? "<td>$row->{submitter}</td>" : "<td>&nbsp;</td>";

        # title
        $ret .= "<td>$row->{title}</td>";

        # editor
        $ret .= $row->{editor} ? "<td>$row->{editor}</td>" : "<td>&nbsp;</td>";

        # blocks
        foreach my $i (1..4) {
            $ret .= $row->{"block_${i}_title"} ? "<td>" . $row->{"block_${i}_title"} . "</td>" : "<td>&nbsp;</td>";
            $ret .= $row->{"block_${i}_text"} ? "<td>" . $row->{"block_${i}_text"} . "</td>" : "<td>&nbsp;</td>";
        }

        # dates
        $ret .= "<td>" . $start_date->strftime("%F %r %Z")  . "</td>";
        $ret .= "<td>" . $end_date->strftime("%F %r %Z")  . "</td>";

        # admin
        my $admin = LJ::load_userid($row->{adminid});
        $ret .= $admin ? "<td>" . $admin->ljuser_display . "</td>" : "<td>&nbsp;</td>";

        # delete
        $ret .= "<td>" . $class->html_submit(
            "delete:$row->{edid}" => "delete",
            { onclick => "if (confirm('Are you sure you want to delete this editorial group?')) { return true; } else { return false; }" },
        ) . "</td>";

        $ret .= "</tr>";
    }
    $ret .= "</table>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $vertical = LJ::Vertical->load_by_name($post->{vertname});
    die "You do not have permission to manage these editorials." unless $vertical && $vertical->remote_is_moderator;

    # find which to edit/delete
    # do the action
    my ($action, $edid);
    while (my ($k, $v) = each %$post) {
        next unless $k =~ /^(\w+):(\w+)/;
        ($action, $edid) = ($1, $2);
        last;
    }

    die "Invalid action: $action" unless $action eq "edit" || $action eq "delete";

    if ($action eq "edit") {
        return BML::redirect("$LJ::SITEROOT/admin/verticals/editorials/add.bml?edid=$edid");
    } else { # delete
        return LJ::VerticalEditorials->delete_editorials($edid);
    }

    return;
}

1;
