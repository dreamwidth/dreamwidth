package LJ::Widget::VerticalEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical );

sub need_res { qw( stc/widgets/verticalentries.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $vertical = $opts{vertical};
    die "Invalid vertical object passed to widget." unless $vertical;

    my $page = $opts{page} > 0 ? $opts{page} : 1;
    my $num_full_entries_first_page = defined $opts{num_full_entries_first_page} ? $opts{num_full_entries_first_page} : 3;
    my $num_collapsed_entries_first_page = defined $opts{num_collapsed_entries_first_page} ? $opts{num_collapsed_entries_first_page} : 8;
    my $num_entries_older_pages = $opts{num_entries_older_pages} > 0 ? $opts{num_entries_older_pages} : 10;
    my $max_pages = $opts{max_pages} > 0 ? $opts{max_pages} : 10;

    my $num_entries_first_page = $num_full_entries_first_page + $num_collapsed_entries_first_page;
    my $num_entries_this_page = $page > 1 ? $num_entries_older_pages : $num_entries_first_page;
    my $start_index = $page > 1 ? (($page - 2) * $num_entries_this_page) + $num_entries_first_page : 0;

    my $r = BML::get_request();
    my $return_url = "$LJ::SITEROOT" . $r->uri;
    my $args = $r->args;
    $return_url .= "?$args" if $args;

    my $ret;

    $ret .= "<div class='firstpage'>" if $page == 1;

    # get one more than we display so that we can tell if the next page will have entries or not
    my @entries_this_page = $vertical->entries( start => $start_index, limit => $num_entries_this_page + 1 );

    # pop off the last entry if we got more than we need, since we won't display it
    my $last_entry = pop @entries_this_page if @entries_this_page > $num_entries_this_page;

    my $title_displayed = 0;
    my $count = 0;
    my $collapsed_count = 0;
    foreach my $entry (@entries_this_page) {
        if ($page > 1 || $count < $num_full_entries_first_page) {
            $ret .= $class->print_entry( entry => $entry, vertical => $vertical, title_displayed => \$title_displayed, return_url => $return_url );
        } else {
            $ret .= "<table class='entry-collapsed' cellspacing='10'>" if $count == $num_full_entries_first_page;
            $ret .= "<tr>" if $collapsed_count % 2 == 0;
            $ret .= "<td class='entry-collapsed-entry'>" . $class->print_collapsed_entry( entry => $entry, vertical => $vertical, title_displayed => \$title_displayed, return_url => $return_url ) . "</td>";
            $ret .= "</tr>" if $collapsed_count % 2 == 1;
            $ret .= "</table>" if $count == @entries_this_page - 1;
            $collapsed_count++;
        }
        $count++;
    }

    my $page_back = $page + 1;
    my $page_forward = $page - 1;
    my $show_page_back = defined $last_entry ? 1 : 0;
    my $show_page_forward = $page_forward > 0;

    $ret .= "<p class='skiplinks'>" if $show_page_back || $show_page_forward;
    if ($show_page_back) {
        $ret .= "<a href='" . $vertical->url . "?page=$page_back'>&lt; " . $class->ml('widget.verticalentries.skip.previous') . "</a>";
    }
    $ret .= " | " if $show_page_back && $show_page_forward;
    if ($show_page_forward) {
        my $url = $page_forward == 1 ? $vertical->url : $vertical->url . "?page=$page_forward";
        $ret .= "<a href='$url'>" . $class->ml('widget.verticalentries.skip.next') . " &gt;</a>";
    }
    $ret .= "</p>" if $show_page_back || $show_page_forward;

    $ret .= "</div>" if $page == 1;

    return $ret;
}

sub print_entry {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $vertical = $opts{vertical};
    my $title_displayed_ref = $opts{title_displayed};

    my $display_name = $vertical->display_name;
    my $ret;

    # display the title in here so we don't show it if there's no entries to show
    unless ($$title_displayed_ref) {
        $ret .= "<h2>" . $class->ml('widget.verticalentries.title2', { verticalname => $display_name }) . "</h2>";
        $$title_displayed_ref = 1;
    }

    $ret .= "<table class='entry' cellspacing='0' cellpadding='0'><tr>";

    $ret .= "<td class='userpic'>";
    if ($entry->userpic) {
        $ret .= $entry->userpic->imgtag_lite;
    } else {
        $ret .= LJ::run_hook('no_userpic_html');
    }
    $ret .= "<p class='poster'>" . $entry->poster->ljuser_display({ bold => 0, head_size => 11 });
    unless ($entry->posterid == $entry->journalid) {
        $ret .= "<br />" . $entry->journal->ljuser_display({ bold => 0, head_size => 11 });
    }
    $ret .= "</p></td>";

    $ret .= "<td class='content'>";

    # remove from vertical button and categories button
    $ret .= $class->remove_btn( entry => $entry, vertical => $vertical );
    $ret .= $class->cats_btn( entry => $entry, return_url => $opts{return_url} );

    # subject
    $ret .= "<p class='subject'><a href='" . $entry->url . "'><strong>";
    $ret .= $class->entry_subject( entry => $entry, length => 55 );
    $ret .= "</strong></a></p>";

    # entry text
    my $full_entry = $entry->event_html;
    my $trimmed_entry = $class->entry_event( entry => $entry );
    $ret .= "<p class='event'>";
    $ret .= $trimmed_entry eq $full_entry ? $trimmed_entry : "$trimmed_entry&hellip;";
    $ret .= "</p>";

    # tags
    my @tags = $entry->tags;
    if (@tags) {
        my $tag_list = join(", ",
            map  { "<a href='" . LJ::eurl($entry->journal->journal_base . "/tag/$_") . "'>" . LJ::ehtml($_) . "</a>" }
            sort { lc $a cmp lc $b } @tags);
        $ret .= "<p class='tags'>" . $class->ml('widget.verticalentries.tags') . " $tag_list</p>";
    }

    # post time and comments link
    my $secondsago = time() - $entry->logtime_unix;
    my $posttime = LJ::ago_text($secondsago);
    $ret .= "<p class='posttime'>" . $class->ml('widget.verticalentries.posttime', { posttime => $posttime });
    if ($entry->reply_count) {
        $ret .= " | <a href='" . $entry->url . "'>";
        $ret .= $class->ml('widget.verticalentries.replycount', { count => $entry->reply_count });
        $ret .= "</a>";
    }
    $ret .= " | <a href='" . $entry->reply_url . "'>" . $class->ml('widget.verticalentries.postacomment') . "</a>";
    $ret .= "</p>";

    $ret .= "</td>";
    $ret .= "</tr></table>";

    $ret .= "<hr />";

    return $ret;
}

sub print_collapsed_entry {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $vertical = $opts{vertical};
    my $title_displayed_ref = $opts{title_displayed};

    my $display_name = $vertical->display_name;
    my $ret;

    # display the title in here so we don't show it if there's no entries to show
    unless ($$title_displayed_ref) {
        $ret .= "<h2>" . $class->ml('widget.verticalentries.title2', { verticalname => $display_name }) . "</h2>";
        $$title_displayed_ref = 1;
    }

    $ret .= "<table class='entry-collapsed-inner' cellspacing='0' cellpadding='0'><tr>";

    $ret .= "<td class='userpic'>";

    if ($entry->userpic) {
        $ret .= $entry->userpic->imgtag_percentagesize(0.5);
    } else {
        $ret .= LJ::run_hook('no_userpic_html', percentage => 0.5 );
    }

    $ret .= "</td>";
    $ret .= "<td class='content'>";

    # remove from vertical button and categories button
    $ret .= $class->remove_btn( entry => $entry, vertical => $vertical );
    $ret .= $class->cats_btn( entry => $entry, return_url => $opts{return_url} );

    $ret .= "<p class='collapsed-subject'><a href='" . $entry->url . "'><strong>";
    $ret .= $class->entry_subject( entry => $entry, length => 30 );
    $ret .= "</strong></a></p>";
    $ret .= "<p class='collapsed-poster'>" . $entry->poster->ljuser_display({ bold => 0, head_size => 11 });
    unless ($entry->posterid == $entry->journalid) {
        $ret .= " " . $class->ml('widget.verticalentries.injournal', { user => $entry->journal->ljuser_display({ bold => 0, head_size => 11 }) });
    }
    $ret .= "</p>";

    # tags
    my @tags = $entry->tags;
    if (@tags) {
        $ret .= "<p class='collapsed-tags'>" . $class->ml('widget.verticalentries.tags') . " ";
        $ret .= $class->entry_tags( entry => $entry, length => 35 );
        $ret .= "</p>";
    }

    # post time and comments link
    my $secondsago = time() - $entry->logtime_unix;
    my $posttime = LJ::ago_text($secondsago);
    $ret .= "<p class='collapsed-posttime'>" . $class->ml('widget.verticalentries.posttime', { posttime => $posttime });
    if ($entry->reply_count) {
        $ret .= " | <a href='" . $entry->url . "'>";
        $ret .= $class->ml('widget.verticalentries.replycount', { count => $entry->reply_count });
        $ret .= "</a>";
    }
    $ret .= "</p>";

    $ret .= "</td>";
    $ret .= "</tr></table>";

    $ret .= "<hr />";

    return $ret;
}

sub entry_subject {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $length = $opts{length} || 25;

    my $subject = $entry->subject_text || $entry->event_text;
    my $subject_orig = $subject;
    LJ::CleanHTML::clean_and_trim_subject(\$subject, $length);

    if ($subject) {
        $subject = "$subject&hellip;" unless $subject eq $subject_orig;
    } else {
        $subject = $class->ml('widget.verticalentries.nosubject');
    }

    return $subject;
}

sub entry_event {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $length = $opts{length} || 400;

    my $trimmed_entry = $entry->event_html_summary(400, { remove_colors => 1, remove_sizes => 1, remove_fonts => 1 });

    # cut off entry text after the 6th <br>
    my @lines = split(/<br\s*\/?>/, $trimmed_entry);
    my $final_trimmed_entry;
    my $count = 1;
    foreach my $line (@lines) {
        last if $count > 6;

        $final_trimmed_entry .= "$line<br />";
        $count++;
    }
    $final_trimmed_entry =~ s/<br \/>$//; # remove the last <br>

    return $final_trimmed_entry;
}

sub entry_tags {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $length = $opts{length} || 25;

    my @tags = $entry->tags;

    my $tag_list_plaintext = join(", ", sort { lc $a cmp lc $b } @tags);
    my $tag_list_plaintext_trimmed = LJ::text_trim($tag_list_plaintext, 0, $length);

    my @tags_trimmed = split(/, /, $tag_list_plaintext_trimmed);
    @tags = sort { lc $a cmp lc $b } @tags;

    my @final_tags;
    foreach my $i (0..@tags_trimmed-1) {
        push @final_tags, "<a href='" . LJ::eurl($entry->journal->journal_base . "/tag/$tags[$i]") . "'>" . LJ::ehtml($tags_trimmed[$i]) . "</a>";
    }

    my $tag_list = join(", ", @final_tags);
    $tag_list .= "&hellip;" unless $tag_list_plaintext eq $tag_list_plaintext_trimmed;

    return $tag_list;
}

sub remove_btn {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $vertical = $opts{vertical};
    my $display_name = $vertical->display_name;

    my $ret;
    if ($vertical->remote_can_remove_entry($entry)) {
        my $confirm_text = $class->ml('widget.verticalentries.remove.confirm', { verticalname => $display_name });
        my $btn_alt = $class->ml('widget.verticalentries.remove.alt', { verticalname => $display_name });

        $ret .= LJ::Widget::VerticalContentControl->start_form(
            class => "remove-entry",
            onsubmit => "if (confirm('$confirm_text')) { return true; } else { return false; }"
        );
        $ret .= LJ::Widget::VerticalContentControl->html_hidden( remove => 1, entry_url => $entry->url, verticals => $vertical->vertid );
        $ret .= " <input type='image' src='$LJ::IMGPREFIX/explore/removebutton.gif' alt='$btn_alt' title='$btn_alt' />";
        $ret .= LJ::Widget::VerticalContentControl->end_form;
    }

    return $ret;
}

sub cats_btn {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    return "" unless LJ::run_hook("remote_can_get_categories_for_entry", $entry);

    my $btn_alt = $class->ml('widget.verticalentries.cats.alt');

    my $ret;
    $ret .= LJ::Widget::VerticalContentControl->start_form( class => "entry-cats", action => "$LJ::SITEROOT/admin/verticals/?action=cats" );
    $ret .= LJ::Widget::VerticalContentControl->html_hidden( cats => 1, entry_url => $entry->url, return_url => $opts{return_url} );
    $ret .= " <input type='image' src='$LJ::IMGPREFIX/btn_todo.gif' alt='$btn_alt' title='$btn_alt' />";
    $ret .= LJ::Widget::VerticalContentControl->end_form;

    return $ret;
}

1;
