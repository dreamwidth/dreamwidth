
# LiveJournal Vertical object.
#

package LJ::Vertical;
use strict;
use vars qw/ $AUTOLOAD /;
use Carp qw/ croak /;
use Class::Autouse qw( LJ::Image );

# how many entries to query and display in $self->recent_entries;
my $RECENT_ENTRY_LIMIT   = 100;
my $MEMCACHE_ENTRY_LIMIT = 1_000;
my $DB_ENTRY_CHUNK       = 1_000; # rows to fetch per quety

# internal fields:
#
#    vertid:                   id of the vertical being represented
#    name:                     text name of the vertical
#    createtime:               time when vertical was created
#    lastfetch:                time of last fetch from vertical data source
#    entries:                  [ [ journalid, jitemid ], [ ... ], ... ] in order of preferred display
#    entries_filtered:         [ LJ::Entry, LJ::Entry, LJ::Entry, ... ] in order of preferred display
#    rules:                    { whitelist => [ [ score1, data1 ], [ score2, data2 ], ... ], blacklist => [ ... ] }
#
#    _iter_idx:                index position of iterator within $self->{entries}
#    _loaded_row:              loaded vertical row
#    _loaded_entries:          length of window which has been queried so far
#    _loaded_entries_filtered: length of window which has been filtered so far
#    _loaded_rules:            loaded 'rules' row?
#
# NOT IMPLEMENTED:
#    * tree-based hierarchy of verticals
#
# NOTES:
# * Storage of [ journalid, jitemid, instime ] using storable vs pack:
#
# lj@whitaker:~$ perl -I Storable -e 'use Storable; print length(pack("(NN)*", map { (3_500_000_000, 3_500_000_000, 3_500_000_000) } 1..1_000 )) . "\n";'
# 12000
# lj@whitaker:~$  perl -I Storable -e 'use Storable; print length(Storable::nfreeze([ map { (3_500_000_000, 3_500_000_000, 3_500_000_000) } 1..1_000 ])) . "\n";'
# 36007
#

my %singletons = (); # vertid => singleton
my @vert_cols = qw( vertid name createtime lastfetch );

sub min_age_of_poster_account {
    my $class = shift;
    my $journal = shift;

    return LJ::conf_test($LJ::VERTICAL::MIN_AGE_OF_POSTER_ACCOUNT, $journal->journaltype_readable) || 60*60*24*7; # 1 week
}

sub min_friendofs_for_journal_account {
    my $class = shift;
    my $journal = shift;

    return LJ::conf_test($LJ::VERTICAL::MIN_FRIENDOFS_FOR_JOURNAL_ACCOUNT, $journal->journaltype_readable) || 5;
}

sub min_entries_for_journal_account {
    my $class = shift;
    my $journal = shift;

    return LJ::conf_test($LJ::VERTICAL::MIN_ENTRIES_FOR_JOURNAL_ACCOUNT, $journal->journaltype_readable) || 5;
}

sub min_received_comments_for_journal_account {
    my $class = shift;
    my $journal = shift;

    return LJ::conf_test($LJ::VERTICAL::MIN_RECEIVED_COMMENTS_FOR_JOURNAL_ACCOUNT, $journal->journaltype_readable) || 5;
}

sub max_number_of_images_for_entry_in_journal {
    my $class = shift;
    my $journal = shift;

    return LJ::conf_test($LJ::VERTICAL::MAX_NUMBER_OF_IMAGES_FOR_ENTRY_IN_JOURNAL, $journal->journaltype_readable) || 3;
}

sub max_dimensions_of_images_for_entry_in_journal {
    my $class = shift;
    my $journal = shift;

    return LJ::conf_test($LJ::VERTICAL::MAX_DIMENSIONS_OF_IMAGES_FOR_ENTRY_IN_JOURNAL, $journal->journaltype_readable) || { width => 500, height => 500 };
}

sub max_dimensions_of_images_for_editorials {
    my $class = shift;

    return LJ::conf_test($LJ::VERTICAL::MAX_DIMENSIONS_OF_IMAGES_FOR_EDITORIALS) || { width => 320, height => 240 };
}

# logic to execute when adding an entry to or when displaying an entry in a vertical
sub check_entry_for_addition_and_display {
    my $class = shift;
    my $entry = shift;

    my $poster = $entry->poster;
    my $journal = $entry->journal;

    # entry must be public
    return 0 unless $entry->security eq "public";

    # poster, journal, and entry must be visible
    return 0 unless $poster->is_visible;
    return 0 unless $journal->is_visible;
    return 0 unless $entry->is_visible;

    my $hook_rv = LJ::run_hook("entry_should_be_in_verticals", $entry);
    return 0 if defined $hook_rv && !$hook_rv;

    # poster and journal cannot be banned by an admin
    return 0 if $poster->prop('exclude_from_verticals');
    return 0 if $journal->prop('exclude_from_verticals');

    # poster can't have chosen to be excluded
    return 0 if $poster->opt_exclude_from_verticals eq "entries";

    # poster and journal can't have opted out of latest feeds
    return 0 if $poster->prop('latest_optout');
    return 0 if $journal->prop('latest_optout');

    # entry must not be backdated
    return 0 if $entry->prop('opt_backdated');

    return 1;
}

# logic to execute only when adding an entry to a vertical (not on display)
# can pass an option to ignore the rate check (rate check is on by default)
sub check_entry_for_addition {
    my $class = shift;
    my $entry = shift;
    my %opts = @_;

    my $poster = $entry->poster;
    my $journal = $entry->journal;

    # journal must not be one of the usernames we want to leave out
    unless ($LJ::_T_VERTICAL_IGNORE_USERNAME) {
        foreach my $username (@LJ::VERTICAL::JOURNALS_TO_EXCLUDE) {
            return 0 if $journal->user =~ /$username/;
        }
    }

    # poster's account must be of a certain age
    unless ($LJ::_T_VERTICAL_IGNORE_TIMECREATE) {
        return 0 unless time() - $poster->timecreate >= $class->min_age_of_poster_account($poster);
    }

    # journal must have a certain number of friend ofs
    unless ($LJ::_T_VERTICAL_IGNORE_NUMFRIENDOFS) {
        my $min_friendofs = $class->min_friendofs_for_journal_account($journal);
        return 0 unless $journal->friendof_uids( limit => $min_friendofs ) >= $min_friendofs;
    }

    # journal must have a certain number of entries
    unless ($LJ::_T_VERTICAL_IGNORE_NUMENTRIES) {
        return 0 unless $journal->number_of_posts >= $class->min_entries_for_journal_account($journal);
    }

    # journal must have a certain number of received comments
    unless ($LJ::_T_VERTICAL_IGNORE_NUMRECEIVEDCOMMENTS) {
        return 0 unless $journal->num_comments_received >= $class->min_received_comments_for_journal_account($journal);
    }

    # journal/poster must not have gone over the rate limit
    unless ($LJ::_T_VERTICAL_IGNORE_RATECHECK || $opts{ignore_rate_check}) {
        if ($journal->is_comm) {
            return 0 unless $journal->rate_log("comm_in_vertical", 1);
            return 0 unless $poster->rate_log("in_vertical", 1);
        } elsif ($journal->is_syndicated) {
            return 0 unless $journal->rate_log("syn_in_vertical", 1);
        } else {
            return 0 unless $journal->rate_log("in_vertical", 1);
        }
    }

    return 1;
}

# logic to execute only when displaying an entry in a vertical (not when adding)
sub check_entry_for_display {
    my $class = shift;
    my $entry = shift;

    my $hook_rv = LJ::run_hook("entry_should_show_in_verticals", $entry);
    return 0 if defined $hook_rv && !$hook_rv;

    my $journal = $entry->journal;

    # check content flags of the entry and the journal the entry is in
    if (LJ::is_enabled("content_flag")) {
        my $adult_content_entry = $entry->adult_content_calculated;
        my $adult_content_journal = $journal->adult_content_calculated;
        my $admin_flag = $entry->admin_content_flag || $journal->admin_content_flag;

        # use the adult content value that is more adult of the two (entry or journal)
        my $adult_content = "none";
        if ($adult_content_entry eq "explicit" || $adult_content_journal eq "explicit") {
            $adult_content = "explicit";
        } elsif ($adult_content_entry eq "concepts" || $adult_content_journal eq "concepts") {
            $adult_content = "concepts";
        }

        my $remote = LJ::get_remote();
        if ($remote) {
            my $safe_search = $remote->safe_search;

            unless ($safe_search == 0) {
                my $adult_content_flag_level = $LJ::CONTENT_FLAGS{$adult_content} ? $LJ::CONTENT_FLAGS{$adult_content}->{safe_search_level} : 0;
                my $admin_flag_level = $LJ::CONTENT_FLAGS{$admin_flag} ? $LJ::CONTENT_FLAGS{$admin_flag}->{safe_search_level} : 0;

                return 0 if $adult_content_flag_level && ($safe_search >= $adult_content_flag_level);
                return 0 if $admin_flag_level && ($safe_search >= $admin_flag_level);
            }
        } else {
            return 0 if $adult_content ne "none" || $admin_flag;
        }
    }

    return 1;
}

# separate this out from ->check_entry_for_addition because we want to make
# sure to call this only after everything else is checked (so we don't make HTTP
# requests when not necessary).
#
# -- only call this when adding an entry to a vertical (not on display)
sub check_entry_for_image_restrictions {
    my $class = shift;
    my $entry = shift;
    my %opts = @_;

    unless ($LJ::_T_VERTICAL_IGNORE_IMAGERESTRICTIONS) {
        my $img_urls = LJ::html_get_img_urls(\$entry->event_html, exclude_site_imgs => 1 );
        my $journal = $entry->journal;

        # first check that there's no more than N images
        return 0 unless @$img_urls <= $class->max_number_of_images_for_entry_in_journal($journal);

        # now check that these images are not over WxH in size
        eval "use Image::Size;";
        foreach my $image_url (@$img_urls) {
            my $imageref = LJ::Image->prefetch_image($image_url, timeout => 1);
            return 0 unless $imageref;

            unless ($opts{ignore_image_sizes}) {
                my ($w, $h) = Image::Size::imgsize($imageref);
                my $max_dimensions = $class->max_dimensions_of_images_for_entry_in_journal($journal);

                return 0 unless $w && $w <= $max_dimensions->{width};
                return 0 unless $h && $h <= $max_dimensions->{height};
            }
        }
    }

    return 1;
}

#
# Constructors
#

sub new
{
    my $class = shift;

    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    my $self = bless {
        # arguments
        vertid     => delete $opts{vertid},

        # initialization
        name       => undef,
        createtime => undef,
        lastfetch  => undef,
        entries    => [],
        entries_filtered => [],
        rules => { whitelist => [], blacklist => [] },

        # internal flags
        _iter_idx       => 0,
        _loaded_row     => 0,
        _loaded_entries => 0,
        _loaded_all_entries => 0,
        _loaded_entries_filtered => 0,
        _loaded_all_entries_filtered => 0,
        _loaded_rules => 0,
    };

    croak("need to supply vertid") unless defined $self->{vertid};

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    # do we have a singleton for this vertical?
    {
        my $vertid = $self->{vertid};
        return $singletons{$vertid} if exists $singletons{$vertid};

        # save the singleton if it doesn't exist
        $singletons{$vertid} = $self;
    }

    return $self;
}
*instance = \&new;

sub create {
    my $class = shift;
    my $self  = bless {};

    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    $self->{name} = delete $opts{name};

    croak("need to supply name") unless defined $self->{name};

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;
    
    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create vertical";

    $dbh->do("INSERT INTO vertical SET name=?, createtime=UNIX_TIMESTAMP()",
             undef, $self->{name});
    die $dbh->errstr if $dbh->err;

    return $class->new( vertid => $dbh->{mysql_insertid} );
}

sub load_by_id {
    my $class = shift;

    my $v = $class->new( vertid => shift );
    $v->preload_rows;

    return $v;
}

# returns a vertical object of the vertical with the given name,
# or undef if a vertical with that name doesn't exist
sub load_by_name {
    my $class = shift;
    my $name = shift;

    return undef unless $name;

    my $reqcache = $LJ::REQ_GLOBAL{vertname}->{$name};
    if ($reqcache) {
        my $v = $class->new( vertid => $reqcache->{vertid} );
        $v->absorb_row($reqcache);

        return $v;
    }

    # check memcache for data
    my $memval = LJ::MemCache::get($class->memkey_vertname($name));
    if ($memval) {
        my $v = $class->new( vertid => $memval->{vertid} );
        $v->absorb_row($memval);
        $LJ::REQ_GLOBAL{vertname}->{$name} = $memval;

        return $v;
    }

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    # not in memcache; load from db
    my $sth = $dbh->prepare("SELECT * FROM vertical WHERE name = ?");
    $sth->execute($name);
    die $dbh->errstr if $dbh->err;

    if (my $row = $sth->fetchrow_hashref) {
        my $v = $class->new( vertid => $row->{vertid} );
        $v->absorb_row($row);
        $v->set_memcache;
        $LJ::REQ_GLOBAL{vertname}->{$name} = $row;

        return $v;
    }

    # name does not exist in db
    return undef;
}

sub load_all {
    my $class = shift;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    my $sth = $dbh->prepare("SELECT * FROM vertical");
    $sth->execute;
    die $dbh->errstr if $dbh->err;

    my @verticals;
    while (my $row = $sth->fetchrow_hashref) {
        my $v = $class->new( vertid => $row->{vertid} );
        $v->absorb_row($row);
        $v->set_memcache;

        push @verticals, $v;
    }

    return @verticals;
}

sub load_top_level {
    my $class = shift;

    my @verticals;
    foreach my $vertname (keys %LJ::VERTICAL_TREE) {
        next unless $LJ::VERTICAL_TREE{$vertname}->{in_nav};

        my $v = $class->load_by_name($vertname);
        push @verticals, $v if $v;
    }

    return sort { lc $a->display_name cmp lc $b->display_name } @verticals;
}

sub load_for_nav {
    my $class = shift;

    my $should_see_nav = LJ::run_hook('remote_should_see_vertical_nav');
    return () unless !defined $should_see_nav || $should_see_nav;

    if ($LJ::CACHED_VERTICALS_FOR_NAV){
        foreach my $v (@$LJ::CACHED_VERTICALS_FOR_NAV){
            $v->{'display_name'} = BML::ml("vertical.nav.explore." . $v->{'name'}) || $v->{'display_name_ori'};
        }

        return @$LJ::CACHED_VERTICALS_FOR_NAV;
    }
    my @verticals;
    foreach my $vertname (keys %LJ::VERTICAL_TREE) {
        next unless $LJ::VERTICAL_TREE{$vertname}->{in_nav};

        my $v = $class->load_by_name($vertname);
        push @verticals, $v if $v;
    }

    foreach my $v (sort { $LJ::VERTICAL_TREE{$a->{name}}->{in_nav} cmp $LJ::VERTICAL_TREE{$b->{name}}->{in_nav} } @verticals) {
        push @$LJ::CACHED_VERTICALS_FOR_NAV, {
            id => $v->vertid,
            name => $v->name,
            display_name => BML::ml("vertical.nav.explore." . $v->name) || $v->display_name,
            display_name_ori => $v->display_name,
            url => $v->url,
        };
    }

    return @$LJ::CACHED_VERTICALS_FOR_NAV;
}

# given a valid URL for a vertical, returns the vertical object associated with it
# valid URLs can be the special URL defined in config or just /explore/verticalname/
sub load_by_url {
    my $class = shift;
    my $url = shift;

    $url =~ /^(?:$LJ::SITEROOT)?(\/.+)$/;
    my $path = $1;
    $path =~ s/\/?(?:\?.*)?$//; # remove trailing slash and any get args

    my $map = $class->uri_map;
    if (my $vertname = $map->{$path}) {
        return $class->load_by_name($vertname);
    } elsif ($path =~ /^\/explore\/(.+)$/) {
        return $class->load_by_name($1);
    }

    return undef;
}

# only load verticals that can have editorials
sub load_for_editorials {
    my $class = shift;

    my @verticals;
    foreach my $vertname (keys %LJ::VERTICAL_TREE) {
        next unless $LJ::VERTICAL_TREE{$vertname}->{has_editorials};

        my $v = $class->load_by_name($vertname);
        push @verticals, $v if $v;
    }

    return sort { lc $a->display_name cmp lc $b->display_name } @verticals;
}

#
# Singleton accessors and helper methods
#

sub reset_singletons {
    %singletons = ();
}

sub all_singletons {
    my $class = shift;

    return values %singletons;
}

sub unloaded_singletons {
    my $class = shift;

    return grep { ! $_->{_loaded_row} } $class->all_singletons;
}

#
# Loaders
#

sub memkey_vertid {
    my $self = shift;
    my $id = shift;

    return [ $id, "vert:$id" ] if $id;
    return [ $self->{vertid}, "vert:$self->{vertid}" ];
}

sub memkey_vertname {
    my $self = shift;
    my $name = shift;

    return "vertname:$name" if $name;
    return "vertname:$self->{name}";
}

sub memkey_rules {
    my $self = shift;
    my $id = shift;

    return [ $id, "vertrules:$id" ] if $id;
    return [ $self->{vertid}, "vertrules:$self->{vertid}" ];
}

sub set_memcache {
    my $self = shift;

    return unless $self->{_loaded_row};

    my $val = { map { $_ => $self->{$_} } @vert_cols };
    LJ::MemCache::set( $self->memkey_vertid => $val );
    LJ::MemCache::set( $self->memkey_vertname => $val );

    return;
}

sub clear_memcache {
    my $self = shift;

    LJ::MemCache::delete($self->memkey_vertid);
    LJ::MemCache::delete($self->memkey_vertname);

    return;
}

sub entries_memkey {
    my $self = shift;
    return [ $self->{vertid}, "vertentries:$self->{vertid}" ];
}

sub clear_entries_memcache {
    my $self = shift;
    return LJ::MemCache::delete($self->entries_memkey);
}


sub absorb_row {
    my ($self, $row) = @_;

    $self->{$_} = $row->{$_} foreach @vert_cols;
    $self->{_loaded_row} = 1;

    return 1;
}

sub absorb_rules {
    my ($self, $rules) = @_;

    $self->{rules} = $rules;
    $self->{_loaded_rules} = 1;

    return 1;
}

sub absorb_entries {
    my ($self, $entries, $window_max) = @_;

    # add given entries to our in-object arrayref
    unshift @{$self->{entries}}, @$entries;

    # update _loaded_entries to reflect new data
    $self->{_loaded_entries} = $window_max;

    # did we query memcache and get less than the max that can be stored there?
    # if so then we've got all entries for this vertical
    if (@$entries < $window_max) {
        #print "we've loaded all entries: entries=" . @$entries . ", window_max=$window_max\n";
        $self->{_loaded_all_entries} = 1;
    }

    return 1;
}

sub purge_entries {
    my ($self, $entries, $window_max) = @_;

    # remove given entries from our in-object arrayref
    my @current_entries = @{$self->{entries}};
    for (my $i = 0; $i < @current_entries; $i++) {
        my $current_entry = $current_entries[$i];
        foreach my $entry_to_remove (@$entries) {
            if ($current_entry->[0] == $entry_to_remove->[0] && $current_entry->[1] == $entry_to_remove->[1]) {
                splice(@current_entries, $i, 1);
                $i--; # we just removed an element from @current_entries
            }
        }
    }
    $self->{entries} = \@current_entries;

    # update _loaded_entries to reflect removed data
    $self->{_loaded_entries} = $window_max;

    return 1; 
}

sub preload_rows {
    my $self = shift;
    return 1 if $self->{_loaded_row};

    my @to_load = $self->unloaded_singletons;
    my %need = map { $_->{vertid} => $_ } @to_load;

    my @mem_keys = map { $_->memkey_vertid } @to_load;
    my $memc = LJ::MemCache::get_multi(@mem_keys);

    # now which of the objects to load did we get a memcache key for?
    foreach my $obj (@to_load) {
        my $row = $memc->{"vert:$obj->{vertid}"};
        next unless $row;

        $obj->absorb_row($row);
        delete $need{$obj->{vertid}};
    }

    # now hit the db for what was left
    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    my @vals = keys %need;
    my $bind = LJ::bindstr(@vals);
    my $sth = $dbh->prepare("SELECT * FROM vertical WHERE vertid IN ($bind)");
    $sth->execute(@vals);

    while (my $row = $sth->fetchrow_hashref) {

        # what singleton does this DB row represent?
        my $obj = $need{$row->{vertid}};

        # and update singleton (request cache)
        $obj->absorb_row($row);

        # set in memcache
        $obj->set_memcache;

        # and delete from %need for error reporting
        delete $need{$obj->{vertid}};

    }

    # weird, vertids that we couldn't find in memcache or db?
    warn "unknown vertical(s): " . join(",", keys %need) if %need;

    # now memcache and request cache are both updated, we're done
    return 1;
}

sub rules {
    my $self = shift;

    unless ($self->{_loaded_rules}) {
        $self->load_rules;
    }

    return $self->{rules};
}

sub rules_whitelist {
    my $self = shift;

    return @{$self->rules->{whitelist}};
}

sub rules_blacklist {
    my $self = shift;

    return @{$self->rules->{blacklist}};
}

# usage: $v->set_rules( whitelist => $text, blacklist => $text );
#        $v->set_rules( $full_hashref );
sub set_rules {
    my $self = shift;

    my $to_set = {};

    # did they pass in named pairs?
    if (@_ > 1) {
        my %opts = @_;
        $to_set->{whitelist} = $self->parse_rules(\$opts{whitelist});
        $to_set->{blacklist} = $self->parse_rules(\$opts{blacklist});
    } else {
        $to_set = shift;
        croak "invalid rules hashref"
            unless ref $to_set->{whitelist} && ref $to_set->{blacklist};
    }

    my $dbh = LJ::get_db_writer()
        or die "Unable to contact global db writer for vertical rules";

    $dbh->do("REPLACE INTO vertical_rules SET vertid=?, rules=?",
             undef, $self->vertid, Storable::nfreeze($to_set));

    LJ::MemCache::delete($self->memkey_rules);

    $self->absorb_rules($to_set);

    return 1;
}

sub parse_rules {
    my $self = shift;
    my $textref = shift;

    # caller can also pass a scalar if they like
    $textref = \$textref unless ref $textref;

    my @array_ret = ();
    foreach my $line (split(/\n+/, $$textref)) {
        $line = LJ::trim($line);
        next unless length $line;

        my ($score, @rule) = split(/\s+/, $line);
        if (@rule) {
            die "invalid score: $score"
                unless $score =~ /^0*\.\d+$/;
        } else {
            @rule = ($score);
            $score = undef;
        }
        my $rule = join(" ", @rule);

        push @array_ret => [ $score, $rule ];
    }

    return \@array_ret;
}

sub load_rules {
    my $self = shift;

    return 1 if $self->{_loaded_rules};

    # memcache contains storable object, but that will be thawed on return from MemCache::get
    my $memkey = $self->memkey_rules;
    my $memval = LJ::MemCache::get($memkey);
    if ($memval) {
        $self->absorb_rules($memval);
        return 1;
    }

    my $dbh = LJ::get_db_writer()
        or die "Unable to contact global db writer for vertical rules";

    # db contains storable object
    my $rules = $dbh->selectrow_array("SELECT rules FROM vertical_rules WHERE vertid=?",
                                      undef, $self->vertid);
    die $dbh->errstr if $dbh->err;

    # if we got something, deserialize it
    $rules = Storable::thaw($rules) if $rules;

    # fill in blank rule set if there's nothing in the db
    $rules ||= { whitelist => [], blacklist => [] };

    # set storable object in memcache
    LJ::MemCache::set($memkey, $rules);

    $self->absorb_rules($rules);

    return 1;
}

# we don't do preloading of entries for all singletons because the assumption that
# calling entries on one vertical means it will be called on many doesn't tend to hold
sub load_entries {
    my $self = shift;
    my %opts = @_;

    # limit is a number of entries that can be returned, so max_idx+1
    my $want_limit = delete $opts{limit};
    croak("must specify limit for loading entries")
        unless $want_limit >= 1;
    croak("limit for loading entries must be reasonable")
        unless $want_limit < 100_000;
    croak("unknown parameters: " . join(",", keys %opts)) if %opts;

    # have we already loaded what we need?
    return 1 if $self->{_loaded_all_entries};
    return 1 if $self->{_loaded_entries} >= $want_limit;

    # can we get all that we need from memcache?
    # -- common case
    my $populate_memcache = 1;
    if ($self->{_loaded_entries} <= $MEMCACHE_ENTRY_LIMIT) {
        my $memval = LJ::MemCache::get($self->entries_memkey);
        if ($memval) {
            my @rows = ();
            my $cur = [];
            foreach my $val (unpack("(NN)*", $memval)) {
                push @$cur, $val;
                next unless @$cur == 2;
                push @rows, $cur;
                $cur = [];
            }

            # got something out of memcache, no need to populate it
            $populate_memcache = 0;

            # this will update $self->{_loaded_entries}
            $self->absorb_entries(\@rows, $MEMCACHE_ENTRY_LIMIT);

            # do we have all we need? can we return now?
            return 1 if $want_limit < $self->{_loaded_entries};
        }
    }

    # two cases get us here:
    # 1: need to go back farther than memcache will go
    # 2: memcache needs to be populated
    my ($db_offset, $db_limit) = $self->calc_db_offset_and_limit($want_limit);

    # now hit the db for what was left
    my $db = $populate_memcache ? LJ::get_db_writer() : LJ::get_db_reader();
    die "unable to contact global db master to load vertical" unless $db;

    my $rows = $db->selectall_arrayref
        ("SELECT journalid, jitemid FROM vertical_entries WHERE vertid=? " . 
         "ORDER BY instime DESC LIMIT $db_offset,$db_limit", undef, $self->{vertid});
    die $db->errstr if $db->err;

    $self->absorb_entries($rows, $db_offset + $db_limit);

    # we loaded first $MEMCACHE_ENTRY_LIMIT rows, need to populate memcache
    if ($populate_memcache) {
        my $pack_data = pack("(NN)*", map { @$_ } @$rows);
        LJ::MemCache::set($self->entries_memkey, $pack_data);
    }

    return 1;
}

sub calc_db_offset_and_limit {
    my ($self, $want_limit) = @_;

    my ($db_offset, $db_limit);

    # case 1: we've loaded up to the memcache limit or more, fetch next $DB_ENTRY_LIMIT rows
    if ($self->{_loaded_entries} > $MEMCACHE_ENTRY_LIMIT) {
        $db_offset = $self->{_loaded_entries};

    # case 2: we've not loaded up to memcache limit, fetch up to $MEMCACHE_ENTRY_LIMIT so
    #         we can populate memcache in the next step
    } else {
        $db_offset = 0;
    }

    # how many rows do we need to fetch in order to meet $want_limit?
    my $need_rows   = $want_limit - $db_offset;

    # now, how many chunks is that?
    my $need_chunks = $need_rows % $DB_ENTRY_CHUNK == 0 ? # does $need_rows align exactly to a chunk?
        $need_rows / $DB_ENTRY_CHUNK :                    # simple division to get number of chunks
        int($need_rows / $DB_ENTRY_CHUNK) + 1;            # divide to get n-1 chunk, then add 1
    
    # db_limit should align to a multiple of $DB_ENTRY_CHUNK
    $db_limit = $DB_ENTRY_CHUNK * $need_chunks;

    return ($db_offset, $db_limit)
}

# don't call this unless you're serious
sub delete_and_purge {
    my $self = shift;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    foreach my $table (qw(vertical vertical_entries)) {
        $dbh->do("DELETE FROM $table WHERE vertid=?", undef, $self->{vertid});
        die $dbh->errstr if $dbh->err;
    }

    $self->clear_memcache;
    $self->clear_entries_memcache;

    delete $singletons{$self->{vertid}};

    return;
}

#
# Accessors
#

sub add_entry {
    my $self = shift;
    my @entries = @_;

    die "parameters must all be LJ::Entry object"
        if grep { ! ref $_ || ! $_->isa("LJ::Entry") } @entries;

    # add new entries to the db listing for this vertical
    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    my $bind = join(",", map { "(?,?,?,UNIX_TIMESTAMP())" } @entries);
    my @vals = map { $self->{vertid}, $_->journalid, $_->jitemid } @entries;

    $dbh->do("REPLACE INTO vertical_entries (vertid, journalid, jitemid, instime) " . 
             "VALUES $bind", undef, @vals);
    die $dbh->errstr if $dbh->err;

    # FIXME: lazily clean over time?

    # clear memcache for entries so changes will be reflected on next read
    $self->clear_entries_memcache;

    # mark these entries as being in this vertical
    foreach my $entry (@entries) {
        $entry->add_to_vertical($self->name);
    }

    # add entries to current LJ::Vertical object in memory
    if ($self->{_loaded_entries}) {
        my @entries_to_absorb;
        foreach my $entry (@entries) {
            push @entries_to_absorb, [ $entry->journalid, $entry->jitemid ];
        }
        $self->absorb_entries(\@entries_to_absorb, $self->{_loaded_entries} + @entries_to_absorb);
    }

    return 1;
}
*add_entries = \&add_entry;

sub remove_entry {
    my $self = shift;
    my @entries = @_;

    die "parameters must all be LJ::Entry object"
        if grep { ! ref $_ || ! $_->isa("LJ::Entry") } @entries;

    # remove entries from the db listing for this vertical
    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    my $bind = join(" OR ", map { "(vertid = ? AND journalid = ? AND jitemid = ?)" } @entries);
    my @vals = map { $self->{vertid}, $_->journalid, $_->jitemid } @entries;

    $dbh->do("DELETE FROM vertical_entries WHERE $bind", undef, @vals);
    die $dbh->errstr if $dbh->err;

    # FIXME: lazily clean over time?

    # clear memcache for entries so changes will be reflected on next read
    $self->clear_entries_memcache;

    # mark these entries as not being in this vertical
    foreach my $entry (@entries) {
        $entry->remove_from_vertical($self->name);
    }

    # remove entries from current LJ::Vertical object in memory
    if ($self->{_loaded_entries}) {
        my @entries_to_purge;
        foreach my $entry (@entries) {
            push @entries_to_purge, [ $entry->journalid, $entry->jitemid ];
        }
        $self->purge_entries(\@entries_to_purge, $self->{_loaded_entries} - @entries);
    }

    return 1;
}
*remove_entries = \&remove_entry;

# entries accessor w/o filter
sub entries_raw {
    my $self = shift;
    my %opts = @_;

    # start is 0-based, limit is a count
    my $start = delete $opts{start} || 0;
    my $limit = delete $opts{limit};
    croak("invalid start value: $start")
        if $start < 0;
    croak("must specify limit for loading entries")
        unless $limit >= 1;
    croak("limit for loading entries must be reasonable")
        unless $limit < 100_000;
    croak("unknown parameters: " . join(",", keys %opts)) if %opts;

    my $need_ct  = $start + $limit;
    my $need_idx = $start + $limit - 1; 

    # ensure that we've retrieved entries through need_ct
    $self->load_entries( limit => $need_ct );

    # not enough entries?
    my $loaded_entry_ct = $self->loaded_entry_ct;
    
    return () unless $loaded_entry_ct;
    return () if $start > $loaded_entry_ct - 1;

    # make sure that we don't try to have an index past the end of the entries array
    my $entry_idx = $need_idx > $loaded_entry_ct - 1 ? $loaded_entry_ct - 1 : $need_idx;

    return $self->entry_singletons(@{$self->{entries}}[$start..$entry_idx]);
}

sub entries {
    my $self = shift;
    my %opts = @_;

    # start is 0-based, limit is a count
    my $start = delete $opts{start} || 0;
    my $limit = delete $opts{limit};

    # how many entries will we have on success?
    my $want_entries = $start + $limit;

    my @entries = ();

    # see what's already in the filter cache
    {
        @entries = @{$self->{entries_filtered}};

        # do we have all we need already?
        if (@entries >= $want_entries || $self->{_loaded_all_entries_filtered}) {
            return splice(@entries, $start, $limit);
        }
    }

    # need to read through more raw entries and filter them
    # -- start at the point where our cache left off (above)

    my $chunk_start = $self->{_loaded_entries_filtered};
    my $chunk_max   = 0;
    while (@entries < $want_entries) {
        my $chunk_size = $want_entries - @entries;
        $chunk_max = $chunk_start + $chunk_size;

        my @chunk = $self->entries_raw( start => $chunk_start, limit => $chunk_size );

        foreach my $entry (@chunk) {
            unless (defined $entry && $entry->valid && $entry->should_show_in_verticals) {
                next;
            }

            push @entries, $entry;

            # did we get all we need?
            last if @entries >= $want_entries;
        }

        # if we didn't get the number of entries we requested, then there are no more
        if (@chunk < $chunk_size) {
            $self->{_loaded_all_entries_filtered} = 1;
            last;
        }

        # need to get the next chunk on our next iteration
        $chunk_start += $chunk_size;
    }

    # now we're gauranteed to have loaded at least through $chunk_start entries.  store them in filter cache.
    $self->set_filtered_cache($chunk_max, @entries);

    # chop off elements we didn't care about
    return splice(@entries, $start, $limit);
}

sub set_filtered_cache {
    my ($self, $loaded_ct, @entries) = @_;
    
    $self->{_loaded_entries_filtered} = $loaded_ct;
    @{$self->{entries_filtered}} = @entries;

    return $loaded_ct;
}

sub loaded_entry_ct {
    my $self = shift;

    return scalar @{$self->{entries}};
}

sub recent_entries {
    my $self = shift;

    # reset iterator to end of list which was just fetched, so ->next_entry will be the next from here
    $self->{_iter_idx} = $RECENT_ENTRY_LIMIT;

    # now return next $RECENT_ENTRY_LIMIT -- but only the entries that we should show
    return $self->entries( start => 0, limit => $RECENT_ENTRY_LIMIT );
}

sub next_entry {
    my $self = shift;

    # return next entry, then advance iterator
    my @entries = $self->entries( start => $self->{_iter_idx}++, limit => 1 );
    return $entries[0];
}

sub first_entry {
    my $self = shift;

    my @entries = $self->entries( start => 0, limit => 1 );
    return $entries[0];
}

sub entry_singletons {
    my $self = shift;

    return map { LJ::Entry->new($_->[0], jitemid => $_->[1]) } @_; 
}

sub children {
    my $self = shift;

    my $children = $LJ::VERTICAL_TREE{$self->name}->{children};
    my @child_verticals = map { LJ::Vertical->load_by_name($_) } @$children;

    return @child_verticals ? @child_verticals : ();
}

# right now a vertical has only one parent, but we don't
# want to assume that it will always be that way
sub parents {
    my $self = shift;

    my $parents = $LJ::VERTICAL_TREE{$self->name}->{parents};
    my @parent_verticals = map { LJ::Vertical->load_by_name($_) } @$parents;

    return @parent_verticals ? @parent_verticals : ();
}

sub siblings {
    my $self = shift;
    my %opts = @_;

    my $include_self = $opts{include_self} ? 1 : 0;

    my @sibling_verticals;
    foreach my $parent ($self->parents) {
        foreach my $child ($parent->children) {
            push @sibling_verticals, $child if $include_self || !$child->equals($self);
        }
    }

    return @sibling_verticals ? @sibling_verticals : ();
}

sub display_name {
    my $self = shift;

    return $LJ::VERTICAL_TREE{$self->name}->{display_name};
}

sub url {
    my $self = shift;

    if ($LJ::VERTICAL_TREE{$self->name}->{url_path}) {
        return "$LJ::SITEROOT" . $LJ::VERTICAL_TREE{$self->name}->{url_path} . "/";
    } else {
        return "$LJ::SITEROOT/explore/" . $self->name . "/";
    }
}

# checks to see if the given URL is the canonical URL so that we can redirect if it's not
sub is_canonical_url {
    my $self = shift;
    my $current_url = shift;

    $current_url = "$LJ::SITEROOT$current_url" unless $current_url =~ /$LJ::SITEROOT/;
    my $canonical_url = $self->url;

    # remove trailing slash and any get args for comparison
    $canonical_url =~ s/\/?(?:\?.*)?$//;
    $current_url =~ s/\/?(?:\?.*)?$//;

    return $canonical_url eq $current_url ? 0 : 1;
}

# returns the time that a given entry was added to this vertical, or 0 if it doesn't exist
sub entry_insert_time {
    my $self = shift;
    my $entry = shift;

    die "Invalid entry." unless $entry && $entry->valid;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to load vertical";

    my $sth = $dbh->prepare("SELECT instime FROM vertical_entries WHERE vertid = ? AND journalid = ? AND jitemid = ?");
    $sth->execute($self->vertid, $entry->journalid, $entry->jitemid);
    die $dbh->errstr if $dbh->err;

    if (my $row = $sth->fetchrow_hashref) {
        return $row->{instime};
    }

    return 0;
}

sub remote_can_remove_entry {
    my $self = shift;
    my $entry = shift;

    my $remote = LJ::get_remote();
    return $self->user_can_remove_entry($remote, $entry);
}

sub user_can_remove_entry {
    my $self = shift;
    my $u = shift;
    my $entry = shift;

    return 1 if $u && $u->equals($entry->poster);
    return 1 if $self->user_is_moderator($u);
    return 0;
}

sub remote_is_moderator {
    my $self = shift;

    my $remote = LJ::get_remote();
    return $self->user_is_moderator($remote);
}

sub user_is_moderator {
    my $self = shift;
    my $u = shift;

    return LJ::check_priv($u, "vertical", $self->name) || $LJ::IS_DEV_SERVER ? 1 : 0;
}

sub equals {
    my $self = shift;
    my $other = shift;

    return $self->vertid == $other->vertid ? 1 : 0;
}

sub uri_map {
    return \%LJ::VERTICAL_URI_MAP;
}

# the name to pass to ads to identify verticals
sub ad_name {
    my $self = shift;

    my $name = $self->name;
    return $LJ::VERTICAL_TREE{$name}->{ad_name} || $name;
}

sub has_editorials {
    my $self = shift;

    return $LJ::VERTICAL_TREE{$self->name}->{has_editorials} ? 1 : 0;
}

sub feed {
    my $self = shift;

    return $LJ::VERTICAL_TREE{$self->name}->{feed};
}

sub is_hidden {
    my $self = shift;

    return $LJ::VERTICAL_TREE{$self->name}->{is_hidden} ? 1 : 0;
}

sub _get_set {
    my $self = shift;
    my $key  = shift;

    if (@_) { # setter case
        my $val = shift;

        my $dbh = LJ::get_db_writer()
            or die "unable to contact global db master to load vertical";

        $dbh->do("UPDATE vertical SET $key=? WHERE vertid=?",
                 undef, $self->{vertid}, $val);
        die $dbh->errstr if $dbh->err;

        $self->clear_memcache;

        return $self->{$key} = $val;
    }

    # getter case
    $self->preload_rows unless $self->{_loaded_row};

    return $self->{$key};
}

sub vertid         { shift->_get_set('vertid')              }
sub name           { shift->_get_set('name')                }
sub set_name       { shift->_get_set('name' => $_[0])       }
sub createtime     { shift->_get_set('createtime')          }
sub set_createtime { shift->_get_set('createtime' => $_[0]) }
sub lastfetch      { shift->_get_set('lastfetch')           }
sub set_lastfetch  { shift->_get_set('lastfetch' => $_[0])  }

1;
