package LJ::VerticalEditorials;
use strict;
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical LJ::Image );

sub memcache_key {
    my $class = shift;
    my $verticalname = shift;

    return "verticaleditorials:$verticalname";
}

sub cache_get {
    my $class = shift;
    my $verticalname = shift;

    # first, is it in our per-request cache?
    my $editorials = $LJ::REQ_GLOBAL{vertical_editorials};
    if ($editorials && $editorials->{$verticalname}) {
        return $editorials->{$verticalname};
    }

    my $memkey = $class->memcache_key($verticalname);
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $class->request_cache_set($verticalname, $memcache_data);
    }
    return $memcache_data;
}

sub request_cache_set {
    my $class = shift;
    my $verticalname = shift;
    my $val = shift;

    $LJ::REQ_GLOBAL{vertical_editorials}->{$verticalname} = $val;
}

sub cache_set {
    my $class = shift;
    my $verticalname = shift;
    my $val = shift;

    # first set in request cache
    $class->request_cache_set($verticalname, $val);

    # now set in memcache
    my $memkey = $class->memcache_key($verticalname);
    my $expire = 60*5; # 5 minutes
    return LJ::MemCache::set($memkey, $val, $expire);
}

sub cache_clear {
    my $class = shift;
    my $verticalname = shift;

    # clear request cache
    delete $LJ::REQ_GLOBAL{vertical_editorials}->{$verticalname};

    # clear memcache
    my $memkey = $class->memcache_key($verticalname);
    return LJ::MemCache::delete($memkey);
}

# returns the current editorials for the given vertical
sub load_current_editorials_for_vertical {
    my $class = shift;
    my $vertical = shift;

    my $verticalname = $vertical->name;

    my $editorials = $class->cache_get($verticalname);
    return @$editorials if $editorials;

    my $dbh = LJ::get_db_writer()
        or die "no global database writer for vertical editorials";

    my $sth = $dbh->prepare(
        "SELECT * FROM vertical_editorials WHERE time_start <= UNIX_TIMESTAMP() AND time_end >= UNIX_TIMESTAMP() AND vertid = ?"
    );
    $sth->execute($vertical->vertid);

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set($verticalname, \@rows);

    return @rows;
}

sub get_editorial_for_vertical {
    my $class = shift;
    my %opts = @_;

    my @editorials = $class->load_current_editorials_for_vertical($opts{vertical});

    # sort editorials in descending order by start time (newest first)
    @editorials = 
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @editorials;

    # return the first one in the list
    return $editorials[0];
}

sub get_image_dimensions {
    my $class = shift;
    my $img_url = shift;

    return undef if !$img_url || $img_url =~ /[<>]/;

    my $imageref = LJ::Image->prefetch_image($img_url);
    die "Image cannot be prefetched." unless $imageref;

    my $max_dimensions = LJ::Vertical->max_dimensions_of_images_for_editorials;

    return LJ::Image->get_dimensions_of_resized_image($imageref, %$max_dimensions);
}

sub store_editorials {
    my $class = shift;
    my %vals = @_;

    # get dimensions for image
    my %dimensions = $class->get_image_dimensions($vals{img_url});
    $vals{img_width} = $dimensions{width} if $dimensions{width};
    $vals{img_height} = $dimensions{height} if $dimensions{height};

    my $dbh = LJ::get_db_writer()
        or die "Unable to store editorials: no global dbh";

    # update existing editorials
    if ($vals{edid}) {
        $dbh->do("UPDATE vertical_editorials SET vertid=?, adminid=?, time_start=?, time_end=?, title=?, editor=?, img_url=?, img_width=?, " .
                 "img_height=?, img_link_url=?, submitter=?, block_1_title=?, block_1_text=?, block_2_title=?, block_2_text=?, block_3_title=?, " .
                 "block_3_text=?, block_4_title=?, block_4_text=? WHERE edid=?",
                 undef, (map { $vals{$_} } qw( vertid adminid time_start time_end title editor img_url img_width img_height img_link_url
                                               submitter block_1_title block_1_text block_2_title block_2_text block_3_title block_3_text
                                               block_4_title block_4_text edid )))
            or die "Error updating vertical_editorials: " . $dbh->errstr;
    }
    # insert new editorials
    else {
        $dbh->do("INSERT INTO vertical_editorials VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                 undef, "null", (map { $vals{$_} } qw( vertid adminid time_start time_end title editor img_url img_width img_height
                                                       img_link_url submitter block_1_title block_1_text block_2_title block_2_text
                                                       block_3_title block_3_text block_4_title block_4_text )))
            or die "Error adding vertical_editorials: " . $dbh->errstr;
    }

    # clear cache
    my $vertical = LJ::Vertical->load_by_id($vals{vertid});
    $class->cache_clear($vertical->name);
    return 1;
}

sub delete_editorials {
    my $class = shift;
    my $edid = shift;

    my $editorial = $class->get_single_editorial_group($edid)
        or die "Unable to delete editorials: group $edid does not exist";

    my $dbh = LJ::get_db_writer()
        or die "Unable to delete editorials: no global dbh";

    # delete editorials
    $dbh->do("DELETE FROM vertical_editorials WHERE edid=?", undef, $edid)
        or die "Error deleting editorials: " . $dbh->errstr;

    # clear cache
    my $vertical = LJ::Vertical->load_by_id($editorial->{vertid});
    $class->cache_clear($vertical->name);

    return 1;
}

# returns all editorials that are running during the given month
sub get_all_editorials_running_during_month {
    my $class = shift;
    my ($year, $month, $verticalname) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $time_start = DateTime->new( year => $year, month => $month, time_zone => 'America/Los_Angeles' );
    my $time_end = $time_start->clone;
    $time_end = $time_end->add( months => 1 );
    $time_end = $time_end->subtract( seconds => 1 ); # we want time_end to be the end of the last day of the month

    my $time_start_epoch = $time_start->epoch;
    my $time_end_epoch = $time_end->epoch;

    my $vertical = LJ::Vertical->load_by_name($verticalname);

    my $sth = $dbh->prepare(
        "SELECT * FROM vertical_editorials WHERE vertid = ? AND " .
        # starts before the start of the month and ends after the start of the month
        "((time_start <= ? AND time_end >= ?) OR " .
        # starts before the end of the month and ends after the end of the month
        "(time_start <= ? AND time_end >= ?) OR " .
        # starts after the start of the month and ends before the end of the month
        "(time_start >= ? AND time_end <= ?) OR " .
        # starts before the start of the month and ends after the end of the month
        "(time_start <= ? AND time_end >= ?))"
    );
    $sth->execute(
        $vertical->vertid, $time_start_epoch, $time_start_epoch, $time_end_epoch, $time_end_epoch,
        $time_start_epoch, $time_end_epoch, $time_start_epoch, $time_end_epoch
    )
        or die "Error getting this month's editorials: " . $dbh->errstr;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    # sort editorials in descending order by start time (newest first)
    @rows =
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @rows;

    return @rows;
}

# given an id for an editorial group, returns the info for it
sub get_single_editorial_group {
    my $class = shift;
    my $edid = shift;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

   my $sth = $dbh->prepare("SELECT * FROM vertical_editorials WHERE edid = ?");
    $sth->execute($edid)
        or die "Error getting single editorial group: " . $dbh->errstr;

    return $sth->fetchrow_hashref;
}

# returns a random set of verticals from a defined list where both verticals have current editorials
sub get_random_editorial_snippet_group {
    my $class = shift;

    my @all_valid_groups = @LJ::VERTICAL::EDITORIAL_SNIPPET_GROUPS;

    GROUP:
    for (my $i = 0; $i < @all_valid_groups; $i++) {
        foreach my $vertname (@{$all_valid_groups[$i]}) {
            next if $class->get_editorial_for_vertical( vertical => LJ::Vertical->load_by_name($vertname) );

            splice(@all_valid_groups, $i, 1);
            $i--;
            next GROUP;
        }
    }

    my $rand_index = int(rand(scalar @all_valid_groups));

    return $all_valid_groups[$rand_index] || [];
}

1;
