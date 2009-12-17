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

package LJ::QotD;
use strict;
use Carp qw(croak);
use List::Util qw(shuffle);

sub get_domains {
    my $class = shift;

    return ( homepage => "Homepage" );
}

sub is_valid_domain {
    my $class = shift;
    my $domain = shift;

    return scalar(grep { $_ eq $domain } $class->get_domains) ? 1 : 0;
}

# returns 'current' or 'old' depending on given start and end times
sub get_type {
    my $class = shift;
    my %times = @_;

    return $class->is_current(%times) ? 'current' : 'old';
}

# given a start and end time, returns if now is between those two times
sub is_current {
    my $class = shift;
    my %times = @_;

    return 0 unless $times{start} && $times{end};

    my $now = time();
    return $times{start} <= $now && $times{end} >= $now;
}

sub memcache_key {
    my $class = shift;
    my $type = shift;

    return "qotd:$type";
}

sub cache_get {
    my $class = shift;
    my $type = shift;

    # first, is it in our per-request cache?
    my $questions = $LJ::QotD::REQ_CACHE_QOTD{$type};
    return $questions if $questions;

    my $memkey = $class->memcache_key($type);
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $class->request_cache_set($type, $memcache_data);
    }
    return $memcache_data;
}

sub request_cache_set {
    my $class = shift;
    my $type = shift;
    my $val = shift;

    $LJ::QotD::REQ_CACHE_QOTD{$type} = $val;
}

sub cache_set {
    my $class = shift;
    my $type = shift;
    my $val = shift;

    # first set in request cache
    $class->request_cache_set($type, $val);

    # now set in memcache
    my $memkey = $class->memcache_key($type);
    my $expire = 60*5; # 5 minutes
    return LJ::MemCache::set($memkey, $val, $expire);
}

sub cache_clear {
    my $class = shift;
    my $type = shift;

    # clear request cache
    delete $LJ::QotD::REQ_CACHE_QOTD{$type};

    # clear memcache
    my $memkey = $class->memcache_key($type);
    return LJ::MemCache::delete($memkey);
}

# returns the current active questions
sub load_current_questions {
    my $class = shift;
    my %opts = @_;

    my $questions = $class->cache_get('current');
    return @$questions if $questions;

    my $dbh = LJ::get_db_writer()
        or die "no global database writer for QotD";

    my $sth = $dbh->prepare(
        "SELECT * FROM qotd WHERE time_start <= UNIX_TIMESTAMP() AND time_end >= UNIX_TIMESTAMP() AND active='Y'"
    );
    $sth->execute;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set('current', \@rows);

    return @rows;
}

# returns the non-current active questions that
# have an end time more recent than a month ago
sub load_old_questions {
    my $class = shift;
    my %opts = @_;

    my $questions = $class->cache_get('old');
    return @$questions if $questions;

    my $dbh = LJ::get_db_writer()
        or die "no global database writer for QotD";

    my $sth = $dbh->prepare(
        "SELECT * FROM qotd WHERE time_end >= UNIX_TIMESTAMP()-86400*30 AND time_end < UNIX_TIMESTAMP() AND active='Y'"
    );
    $sth->execute;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set('old', \@rows);

    return @rows;
}

sub filter_by_domain {
    my $class = shift;
    my $u = shift;
    my $domain = shift;
    my @questions = @_;

    my @questions_ret;
    foreach my $q (@questions) {
        push @questions_ret, $q if $q->{domain} eq $domain;
    }

    return @questions_ret;
}

sub filter_by_eff_class {
    my $class = shift;
    my $u = shift;
    my @questions = @_;

    my $eff_class = LJ::run_hook("qotd_get_eff_class", $u);
    return @questions unless $eff_class;

    my @questions_ret;
    if ($eff_class eq "logged_out") {
        foreach my $q (@questions) {
            push @questions_ret, $q if $q->{show_logged_out} eq "Y";
        }
    } else {
        my @classes = ( $eff_class );
        my $class_mask = LJ::mask_from_classes(@classes);

        foreach my $q (@questions) {
            push @questions_ret, $q if ($q->{cap_mask} & $class_mask) > 0;
        }
    }

    return @questions_ret;
}

sub filter_by_country {
    my $class = shift;
    my $u = shift;
    my $skip = shift;
    my $all = shift;
    my @questions = @_;

    # split the list into a list of questions with countries and a list of questions without countries
    my @questions_with_countries;
    my @questions_without_countries;
    foreach my $question (@questions) {
        if ($question->{countries}) {
            push @questions_with_countries, $question;
        } else {
            push @questions_without_countries, $question;
        }
    }

    # get the user's country if defined, otherwise the country of the remote IP
    my $country;
    $country = lc $u->country if $u;
    $country = lc LJ::country_of_remote_ip() unless $country;

    my @questions_ret;

    # get the questions that are targeted at the user's country
    if ($country) {
        foreach my $question (@questions_with_countries) {
            next unless grep { $_ eq $country } split(",", $question->{countries});
            push @questions_ret, $question;
        }
    }

    # if there are questions that are targeted at the user's country
    # and we're getting the current view, return only those questions
    #
    # if the user has an unknown country or there are no questions
    # targeted at their country, or if we're looking at the history,
    # return all questions
    if (@questions_ret && $skip == 0 && !$all) {
        return @questions_ret;
    } else {
        return (@questions_ret, @questions_without_countries);
    }
}

sub get_questions {
    my $class = shift;
    my %opts = @_;

    my $skip = defined $opts{skip} ? $opts{skip} : 0;
    my $domain = defined $opts{domain} ? lc $opts{domain} : "homepage";

    # if true, get all questions for this user from the last month
    # overrides value of $skip
    my $all = defined $opts{all} ? $opts{all} : 0;

    # direct the questions at the given $u, or remote if no $u given
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    my @questions;
    if ($all) {
        @questions = ( $class->load_current_questions, $class->load_old_questions );
    } else {
        if ($skip == 0) {
            @questions = $class->load_current_questions;
        } else {
            @questions = $class->load_old_questions;
        }
    }

    @questions = $class->filter_by_domain($u, $domain, @questions) unless $all;
    @questions = $class->filter_by_eff_class($u, @questions);
    @questions = $class->filter_by_country($u, $skip, $all, @questions);

    # sort questions in descending order by start time (newest first)
    @questions = 
        sort { $b->{time_start} <=> $a->{time_start} } 
        grep { ref $_ } @questions;

    if ($all) {
        return grep { ref $_ } @questions;
    } else {
        # if we're getting the current question, return a random one from the list
        if ($skip == 0) {
            @questions = List::Util::shuffle(@questions);

            return $questions[0] if ref $questions[0];
            return ();

        # if we're getting old questions, we need to only return the one for this view
        } else {
            my $index = $skip - 1;

            # only return the array elements that exist
            my @ret = grep { ref $_ } $questions[$index];
            return @ret;
        }
    }
}

sub store_question {
    my $class = shift;
    my %vals = @_;

    my $dbh = LJ::get_db_writer()
        or die "Unable to store question: no global dbh";

    my @classes = split(/\s*,\s*/, $vals{classes});
    $vals{cap_mask} = LJ::mask_from_classes(@classes);
    $vals{show_logged_out} = $vals{show_logged_out} ? 'Y' : 'N';

    # update existing question
    if ($vals{qid}) {
        $dbh->do("UPDATE qotd SET time_start=?, time_end=?, active=?, subject=?, text=?, tags=?, " .
                 "from_user=?, img_url=?, extra_text=?, cap_mask=?, show_logged_out=?, countries=?, link_url=?, domain=?, impression_url=?, is_special=? WHERE qid=?",
                 undef, (map { $vals{$_} } qw(time_start time_end active subject text tags from_user img_url extra_text cap_mask show_logged_out countries link_url domain impression_url is_special qid)))
            or die "Error updating qotd: " . $dbh->errstr;
    }
    # insert new question
    else {
        $dbh->do("INSERT INTO qotd VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                 undef, "null", (map { $vals{$_} } qw(time_start time_end active subject text tags from_user img_url extra_text cap_mask show_logged_out countries link_url domain impression_url is_special)))
            or die "Error adding qotd: " . $dbh->errstr;
    }

    # insert/update question subject and text in translation system
    my $qid = $vals{qid} || $dbh->{mysql_insertid};
    my $ml_key = LJ::Widget::QotD->ml_key("$qid.text");
    LJ::Widget->ml_set_text($ml_key => $vals{text});
    $ml_key = LJ::Widget::QotD->ml_key("$qid.subject");
    LJ::Widget->ml_set_text($ml_key => $vals{subject});

    # insert/update extra text in translation system
    $ml_key = LJ::Widget::QotD->ml_key("$qid.extra_text");
    if ($vals{extra_text}) {
        LJ::Widget->ml_set_text($ml_key => $vals{extra_text});
    } else {
        my $string = LJ::no_ml_cache(sub { LJ::Widget->ml($ml_key) });
        LJ::Widget->ml_remove_text($ml_key) unless LJ::Widget->ml_is_missing_string($string);
    }

    # clear cache
    my $type = $class->get_type( start => $vals{time_start}, end => $vals{time_end} );
    $class->cache_clear($type);
    return 1;
}

# returns all questions that started during the given month
sub get_all_questions_starting_during_month {
    my $class = shift;
    my ($year, $month) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $time_start = DateTime->new( year => $year, month => $month, time_zone => 'America/Los_Angeles' );
    my $time_end = $time_start->clone;
    $time_end = $time_end->add( months => 1 );
    $time_end = $time_end->subtract( seconds => 1 ); # we want time_end to be the end of the last day of the month

    my $sth = $dbh->prepare("SELECT * FROM qotd WHERE time_start >= ? AND time_start <= ?");
    $sth->execute($time_start->epoch, $time_end->epoch)
        or die "Error getting this month's questions: " . $dbh->errstr;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    # sort questions in descending order by start time (newest first)
    @rows =
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @rows;

    return @rows;
}

# returns all questions that are running during the given month
sub get_all_questions_running_during_month {
    my $class = shift;
    my ($year, $month) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $time_start = DateTime->new( year => $year, month => $month, time_zone => 'America/Los_Angeles' );
    my $time_end = $time_start->clone;
    $time_end = $time_end->add( months => 1 );
    $time_end = $time_end->subtract( seconds => 1 ); # we want time_end to be the end of the last day of the month

    my $time_start_epoch = $time_start->epoch;
    my $time_end_epoch = $time_end->epoch;

    my $sth = $dbh->prepare(
        "SELECT * FROM qotd WHERE " .
        # starts before the start of the month and ends after the start of the month
        "(time_start <= ? AND time_end >= ?) OR " .
        # starts before the end of the month and ends after the end of the month
        "(time_start <= ? AND time_end >= ?) OR " .
        # starts after the start of the month and ends before the end of the month
        "(time_start >= ? AND time_end <= ?) OR " .
        # starts before the start of the month and ends after the end of the month
        "(time_start <= ? AND time_end >= ?)"
    );
    $sth->execute(
        $time_start_epoch, $time_start_epoch, $time_end_epoch, $time_end_epoch, $time_start_epoch, $time_end_epoch, $time_start_epoch, $time_end_epoch
    )
        or die "Error getting this month's questions: " . $dbh->errstr;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    # sort questions in descending order by start time (newest first)
    @rows =
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @rows;

    return @rows;
}

# given an id for a question, returns the info for it
sub get_single_question {
    my $class = shift;
    my $qid = shift;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

   my $sth = $dbh->prepare("SELECT * FROM qotd WHERE qid = ?");
    $sth->execute($qid)
        or die "Error getting single question: " . $dbh->errstr;

    return $sth->fetchrow_hashref;
}

# change the active status of the given question
sub change_active_status {
    my $class = shift;
    my $qid = shift;

    my %opts = @_;
    my $to = delete $opts{to};
    croak "invalid 'to' field" unless $to =~ /^(active|inactive)$/; 

    my $question = $class->get_single_question($qid)
        or die "Invalid question: $qid";

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $active_val = $to eq 'active' ? 'Y' : 'N';
    my $rv = $dbh->do("UPDATE qotd SET active = ? WHERE qid = ?", undef, $active_val, $qid)
        or die "Error updating active status of question: " . $dbh->errstr;

    my $type = $class->get_type( start => $question->{time_start}, end => $question->{time_end} );
    $class->cache_clear($type);

    return $rv;
}

# given a comma-separated list of tags, remove the default tag(s) from the list
sub remove_default_tags {
    my $class = shift;
    my $tag_list = shift;

    my $tag = $class->entry_tag;
    $tag_list =~ s/\s*${tag},?\s*//g;

    return $tag_list;
}

# given a comma-separated list of tags, add the default tag(s) to the list
sub add_default_tags {
    my $class = shift;
    my $tag_list = shift;

    my $tag = $class->entry_tag;

    if ($tag_list) {
        return "$tag, " . $tag_list;
    } else {
        return $tag;
    }
}

# tag given to QotD entries
sub entry_tag { "writer's block" }

# parse the given URL
# * replace '[[uniq]]' with a unique identifier
sub parse_url {
    my $class = shift;
    my %opts = @_;

    my $qid = $opts{qid};
    my $url = $opts{url};

    my $uniq = LJ::pageview_unique_string() . $qid;
    $uniq = Digest::SHA1::sha1_hex($uniq);

    $url =~ s/\[\[uniq\]\]/$uniq/g;

    return $url;
}

1;
