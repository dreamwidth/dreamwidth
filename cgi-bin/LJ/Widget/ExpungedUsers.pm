# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by 
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License. 
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Widget::ExpungedUsers;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::ExpungedUsers;

# increments with each rendering of the sorter bar
my $sorter_bar_idx = 0;

sub need_res {
    return qw( stc/widgets/expungedusers.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $post = delete $opts{post};

    croak "invalid arguments: " . join(",", keys %opts)
        if %opts;

    # reset the sorter bar index, which is used for keeping track
    # of which sorter bar button was clicked, if multiple
    $sorter_bar_idx = 0;

    my $ret;

    # are they just searching by one user?
    if ($class->get_effective_search_user($post)) {
        $ret .= $class->search_by_user($post);
    } else {
        $ret .= $class->random_by_letter($post);
    }

    $ret .= $class->purchase_button;

    return $ret;
}

sub purchase_button {
    my $class = shift;

    my $ret = "<form method='GET' action='$LJ::SITEROOT/shop/view.bml' class='purchase-rename-form'>";
    $ret .= LJ::html_hidden('item', 'rename');
    $ret .= $class->html_submit('Purchase a Rename Token');
    $ret .= "</form>";

    return $ret;
}

sub search_by_user {
    my $class = shift;
    my $post  = shift;

    my $user = $class->get_effective_search_user($post);
    $user = LJ::canonical_username($user);

    my ($u, @fuzzy_us);
    if ($user) {
        $u = LJ::ExpungedUsers->load_single_user($user);
    }
    unless ($u) {
        @fuzzy_us = LJ::ExpungedUsers->fuzzy_load_user($user);
    }

    my $ret = $class->start_form;
    $ret .= $class->sorter_bar( post => $post );

    $ret .= "<div id='appwidget-expungedusers-search-wrapper'>";
    if ($u) {
        $ret .= "<ul id='appwidget-expungedusers-search'><li>" . $u->display_username . "</li></ul>";
    } else {
        $ret .= "<p>Sorry, '$user' is not currently available";

        if (@fuzzy_us) {
            $ret .= ", but we have found some similar usernames you might be interested in:";

            $ret .= "<div id='appwidget-expungedusers-fuzzylist-wrapper'>";
            $ret .= "<ul>";
            foreach (@fuzzy_us) {
                $ret .= "<li>" . $_->[0]->display_username . "</li>";
            }
            $ret .= "</ul>";
            $ret .= "</div>";
        } else {
            $ret .= "."; # yay punctuation
        }
        $ret .= "</p>";
    }
    $ret .= "</div>";

    $ret .= $class->end_form;

    return $ret;
}

sub get_effective_letter {
    my $class = shift;
    my $post  = shift;

    foreach my $key (keys %$post) {
        next unless $key =~ /^(?:filter|more)_(\d+)/;
        return $post->{"letter_$1"};
    }
    return 'a';
}

sub get_effective_search_user {
    my $class = shift;
    my $post  = shift;

    foreach my $key (keys %$post) {
        next unless $key =~ /^(?:search_user)_(\d+)/;
        return $post->{"search_user_$1"};
        next unless $post->{"search_user_$1"};
    }
    return '';
}

sub random_by_letter {
    my $class = shift;
    my $post  = shift;

    # display random usernames
    my @rows = LJ::ExpungedUsers->random_by_letter
        ( letter   => $class->get_effective_letter($post),
          prev_max => $post->{prev_max},
          limit    => 500,
          );

    my $prev_max = (map { $_->[1] } @rows)[-1];

    my $ret = $class->start_form;

    $ret .= $class->sorter_bar( prev_max => $prev_max,
                                post     => $post);

    $ret .= "<div id='appwidget-expungedusers-random-wrapper'>";
    if (@rows) {
        $ret .= "<ul id='appwidget-expungedusers-random'>";
        foreach (@rows) {
            my ($u, $exp_time) = @$_;
            $ret .= "<li>" . $u->display_username . "</li>\n";
        }
        $ret .= "</ul>";
    } else {
        $ret .= "<p>Sorry, there are no matches beginning with '" . $class->get_effective_letter($post) . "'</p>";
    }
    $ret .= "</div>";

    # hide sorter bar if we didn't get rows above
    if (@rows) {
        $ret .= $class->sorter_bar( prev_max => $prev_max,
                                    post     => $post );
    }

    $ret .= $class->end_form;

    return $ret;
}

sub sorter_bar {
    my $class = shift;
    my %opts  = @_;

    my $post     = delete $opts{post};
    my $prev_max = delete $opts{prev_max} || $post->{prev_max};

    my $ret;

    # Show random usernames by letter
    $ret .= "<div class='appwidget-expungeusers-formbar-wrapper pkg'>";
    $ret .= "<div class='appwidget-expungeusers-formbar'>";
    $ret .= "<label>Show random usernames beginning with: </label>";

    my $selected = $class->get_effective_letter($post);

    $ret .= $class->html_select
        ( name => "letter_$sorter_bar_idx", selected => $selected,
          list => [ (map { chr($_), chr($_-32) } 97..122), (map { $_ => $_ } 0..9) ] );

    $ret .= $class->html_hidden(prev_max => $prev_max) if $sorter_bar_idx == 0;
    $ret .= $class->html_submit("filter_$sorter_bar_idx" => "Filter");
    $ret .= $class->html_submit("more_$sorter_bar_idx" => "See more random results");
    
    $ret .= "</div>"; # /formbar

    # Seach by a specific username
    $ret .= "<div class='appwidget-expungeusers-searchuser'>";
    $ret .= $class->html_text( name => "search_user_$sorter_bar_idx", size => 15, maxlength => 25 );
    $ret .= $class->html_submit( "search_$sorter_bar_idx" => "Search by username");
    $ret .= "</div>";

    $ret .= "</div>"; # /wrapper

    # increment sorter bar idx for the next call info this function
    $sorter_bar_idx++;

    return $ret;
}

1;
