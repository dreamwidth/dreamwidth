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

package LJ::User;
use strict;
no warnings 'uninitialized';

use Carp;

########################################################################
### 11. Birthdays and Age-Related Functions
###   FIXME: Some of these may be outdated when we remove under-13 accounts.

=head2 Birthdays and Age-Related Functions
=cut

# Users age based off their profile birthdate
sub age {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $bdate = $u->{bdate};
    return unless length $bdate;

    my ($year, $mon, $day) = $bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::calc_age($year, $mon, $day);
    return $age if defined $age && $age > 0;
    return;
}


# This will format the birthdate based on the user prop
sub bday_string {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    my $bdate = $u->{'bdate'};
    my ($year,$mon,$day) = split(/-/, $bdate);
    my $bday_string = '';

    if ($u->can_show_full_bday && $day > 0 && $mon > 0 && $year > 0) {
        $bday_string = $bdate;
    } elsif ($u->can_show_bday && $day > 0 && $mon > 0) {
        $bday_string = "$mon-$day";
    } elsif ($u->can_show_bday_year && $year > 0) {
        $bday_string = $year;
    }
    $bday_string =~ s/^0000-//;
    return $bday_string;
}


# Returns the best guess age of the user, which is init_age if it exists, otherwise age
sub best_guess_age {
    my $u = shift;
    return 0 unless $u->is_person || $u->is_identity;
    return $u->init_age || $u->age;
}


# returns if this user can join an adult community or not
# adultref will hold the value of the community's adult content flag
sub can_join_adult_comm {
    my ($u, %opts) = @_;

    return 1 unless LJ::is_enabled( 'adult_content' );

    my $adultref = $opts{adultref};
    my $comm = $opts{comm} or croak "No community passed";

    my $adult_content = $comm->adult_content_calculated;
    $$adultref = $adult_content;

    return 0 if $adult_content eq "explicit" && ( $u->is_minor || !$u->best_guess_age );

    return 1;
}


# Birthday logic -- should a notification be sent?
# Currently the same logic as can_show_bday with an exception for
# journals that have memorial or deleted status.
sub can_notify_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu( $u );

    return 0 if $u->is_memorial;
    return 0 if $u->is_deleted;

    return $u->can_show_bday( %opts );
}


# Birthday logic -- can any of the birthday info be shown
# This will return true if any birthday info can be shown
sub can_share_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $with_u = $opts{with} || LJ::get_remote();

    return 0 if $u->opt_sharebday eq 'N';
    return 0 if $u->opt_sharebday eq 'R' && !$with_u;
    return 0 if $u->opt_sharebday eq 'F' && !$u->trusts( $with_u );
    return 1;
}


# Birthday logic -- show appropriate string based on opt_showbday
# This will return true if the actual birthday can be shown
sub can_show_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'D' || $u->opt_showbday eq 'F';
    return 1;
}


# This will return true if the actual birth year can be shown
sub can_show_bday_year {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'Y' || $u->opt_showbday eq 'F';
    return 1;
}


# This will return true if month, day, and year can be shown
sub can_show_full_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'F';
    return 1;
}


sub include_in_age_search {
    my $u = shift;

    # if they don't display the year
    return 0 if $u->opt_showbday =~ /^[DN]$/;

    # if it's not visible to registered users
    return 0 if $u->opt_sharebday =~ /^[NF]$/;

    return 1;
}


# This returns the users age based on the init_bdate (users coppa validation birthdate)
sub init_age {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $init_bdate = $u->prop('init_bdate');
    return unless $init_bdate;

    my ($year, $mon, $day) = $init_bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::calc_age($year, $mon, $day);
    return $age if $age > 0;
    return;
}


# return true if we know user is a minor (< 18)
sub is_minor {
    my $self = shift;
    my $age = $self->best_guess_age;
    return 0 unless $age;
    return 1 if ($age < 18);
    return 0;
}


sub next_birthday {
    my $u = shift;
    return if $u->is_expunged;

    return $u->selectrow_array("SELECT nextbirthday FROM birthdays " .
                               "WHERE userid = ?", undef, $u->id)+0;
}


# class method, loads next birthdays for a bunch of users
sub next_birthdays {
    my $class = shift;

    # load the users we need, so we can get their clusters
    my $clusters = LJ::User->split_by_cluster(@_);

    my %bdays = ();
    foreach my $cid (keys %$clusters) {
        next unless $cid;

        my @users = @{$clusters->{$cid} || []};
        my $dbcr = LJ::get_cluster_def_reader($cid)
            or die "Unable to load reader for cluster: $cid";

        my $bind = join(",", map { "?" } @users);
        my $sth = $dbcr->prepare("SELECT * FROM birthdays WHERE userid IN ($bind)");
        $sth->execute(@users);
        while (my $row = $sth->fetchrow_hashref) {
            $bdays{$row->{userid}} = $row->{nextbirthday};
        }
    }

    return \%bdays;
}


# opt_showbday options
# F - Full Display of Birthday
# D - Only Show Month/Day       DEFAULT
# Y - Only Show Year
# N - Do not display
sub opt_showbday {
    my $u = shift;
    # option not set = "yes", set to N = "no"
    $u->_lazy_migrate_infoshow;

    # migrate above did nothing
    # -- if user was already migrated in the past, we'll
    #    fall through and show their prop value
    # -- if user not migrated yet, we'll synthesize a prop
    #    value from infoshow without writing it
    unless ( LJ::is_enabled('infoshow_migrate') || $u->{allow_infoshow} eq ' ' ) {
        return $u->{allow_infoshow} eq 'Y' ? undef : 'N';
    }
    if ($u->raw_prop('opt_showbday') =~ /^(D|F|N|Y)$/) {
        return $u->raw_prop('opt_showbday');
    } else {
        return 'D';
    }
}


# opt_sharebday options
# A - All people
# R - Registered Users
# F - Trusted Only
# N - Nobody
sub opt_sharebday {
    my $u = shift;

    if ($u->raw_prop('opt_sharebday') =~ /^(A|F|N|R)$/) {
        return $u->raw_prop('opt_sharebday');
    } else {
        return 'F' if $u->is_minor;
        return 'A';
    }
}


# this sets the unix time of their next birthday for notifications
sub set_next_birthday {
    my $u = shift;
    return if $u->is_expunged;

    my ($year, $mon, $day) = split(/-/, $u->{bdate});
    unless ($mon > 0 && $day > 0) {
        $u->do("DELETE FROM birthdays WHERE userid = ?", undef, $u->id);
        return;
    }

    my $as_unix = sub {
        return LJ::mysqldate_to_time(sprintf("%04d-%02d-%02d", @_));
    };

    my $curyear = (gmtime(time))[5]+1900;

    # Calculate the time of their next birthday.

    # Assumption is that birthday-notify jobs won't be backed up.
    # therefore, if a user's birthday is 1 day from now, but
    # we process notifications for 2 days in advance, their next
    # birthday is really a year from tomorrow.

    # We need to do calculate three possible "next birthdays":
    # Current Year + 0: For the case where we it for the first
    #   time, which could happen later this year.
    # Current Year + 1: For the case where we're setting their next
    #   birthday on (approximately) their birthday. Gotta set it for
    #   next year. This works in all cases but...
    # Current Year + 2: For the case where we're processing notifs
    #   for next year already (eg, 2 days in advance, and we do
    #   1/1 birthdays on 12/30). Year + 1 gives us the date two days
    #   from now! So, add another year on top of that.

    # We take whichever one is earliest, yet still later than the
    # window of dates where we're processing notifications.

    my $bday;
    for my $inc (0..2) {
        $bday = $as_unix->($curyear + $inc, $mon, $day);
        last if $bday > time() + $LJ::BIRTHDAY_NOTIFS_ADVANCE;
    }

    # up to twelve hours drift so we don't get waves
    $bday += int(rand(12*3600));

    $u->do("REPLACE INTO birthdays VALUES (?, ?)", undef, $u->id, $bday);
    die $u->errstr if $u->err;

    return $bday;
}


sub should_fire_birthday_notif {
    my $u = shift;

    return 0 unless $u->is_person;
    return 0 unless $u->is_visible;

    # if the month/day can't be shown
    return 0 if $u->opt_showbday =~ /^[YN]$/;

    # if the birthday isn't shown to anyone
    return 0 if $u->opt_sharebday eq "N";

    # note: this isn't intended to capture all cases where birthday
    # info is restricted. we want to pare out as much as possible;
    # individual "can user X see this birthday" is handled in
    # LJ::Event::Birthday->matches_filter

    return 1;
}


# data for generating packed directory records
sub usersearch_age_with_expire {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    # don't include their age in directory searches
    # if it's not publicly visible in their profile
    my $age = $u->include_in_age_search ? $u->age : 0;
    $age += 0;

    # no need to expire due to age if we don't have a birthday
    my $expire = $u->next_birthday || undef;

    return ($age, $expire);
}


########################################################################
### 12. Adult Content Functions

=head2 Adult Content Functions
=cut

# defined by the user
# returns 'none', 'concepts' or 'explicit'
sub adult_content {
    my $u = shift;

    my $prop_value = $u->prop('adult_content');

    return $prop_value ? $prop_value : "none";
}


# uses user-defined prop to figure out the adult content level
sub adult_content_calculated {
    my $u = shift;

    return $u->adult_content;
}


# returns who marked the entry as the 'adult_content_calculated' adult content level
sub adult_content_marker {
    my $u = shift;

    return "journal";
}


# defuned by the user
sub adult_content_reason {
    my $u = shift;

    return $u->prop('adult_content_reason');
}


sub hide_adult_content {
    my $u = shift;

    my $prop_value = $u->prop('hide_adult_content');

    if (!$u->best_guess_age) {
        return "concepts";
    }

    if ($u->is_minor && $prop_value ne "concepts") {
        return "explicit";
    }

    return $prop_value ? $prop_value : "none";
}


# returns a number that represents the user's chosen search filtering level
# 0 = no filtering
# 1-10 = moderate filtering
# >10 = strict filtering
sub safe_search {
    my $u = shift;

    my $prop_value = $u->prop('safe_search');

    # current user 18+ default is 0
    # current user <18 default is 10
    # new user default (prop value is "nu_default") is 10
    return 0 if $prop_value eq "none";
    return $prop_value if $prop_value && $prop_value =~ /^\d+$/;
    return 0 if $prop_value ne "nu_default" && $u->best_guess_age && !$u->is_minor;
    return 10;
}


# determine if the user in "for_u" should see $u in a search result
sub should_show_in_search_results {
    my ( $u, %opts ) = @_;

    # check basic user attributes first
    return 0 unless $u->is_visible;
    return 0 if $u->is_person && $u->age && $u->age < 14;

    # now check adult content / safe search
    return 1 unless LJ::is_enabled( 'adult_content' ) && LJ::is_enabled( 'safe_search' );

    my $adult_content = $u->adult_content_calculated;
    my $for_u = $opts{for};

    # only show accounts with no adult content to logged out users
    return $adult_content eq "none" ? 1 : 0
        unless LJ::isu( $for_u );

    my $safe_search = $for_u->safe_search;
    return 1 if $safe_search == 0;  # user wants to see everyone

    # calculate the safe_search level for this account
    my $adult_content_flag = $LJ::CONTENT_FLAGS{$adult_content};
    my $adult_content_flag_level = $adult_content_flag
                                 ? $adult_content_flag->{safe_search_level}
                                 : 0;

    # if the level is set, see if it exceeds the desired safe_search level
    return 1 unless $adult_content_flag_level;
    return ( $safe_search < $adult_content_flag_level ) ? 1 : 0;
}


1;
