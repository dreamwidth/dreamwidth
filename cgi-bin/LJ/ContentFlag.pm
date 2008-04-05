use strict;
package LJ::ContentFlag;
use Carp qw (croak);
use Digest::MD5;

use constant {
    # status
    NEW             => 'N',
    CLOSED          => 'C',

    FLAG_EXPLICIT_ADULT => 'E',
    FLAG_HATRED         => 'H',
    FLAG_ILLEGAL        => 'I',
    FLAG_CHILD_PORN     => 'P',
    FLAG_SELF_HARM      => 'X',
    FLAG_SEXUAL         => 'L',
    FLAG_OTHER          => 'R',

    # these are not used
    ABUSE_WARN      => 'W',
    ABUSE_DELETE    => 'D',
    ABUSE_SUSPEND   => 'S',
    ABUSE_TERMINATE => 'T',
    ABUSE_FLAG_ADULT=> 'E',
    REPORTER_BANNED => 'B',
    PERM_OK         => 'O',

    # category
    CHILD_PORN       => 1,
    ILLEGAL_ACTIVITY => 2,
    ILLEGAL_CONTENT  => 3, # not used
    EXPLICIT_ADULT_CONTENT => 4,
    OFFENSIVE_CONTENT => 5,
    HATRED_SITE => 6,
    SPAM => 7,

    # type
    ENTRY   => 1,
    COMMENT => 2,
    JOURNAL => 3,
    PROFILE => 4,
};

# constants to English
our %CAT_NAMES = (
    LJ::ContentFlag::CHILD_PORN             => "Nude Images of Minors",
    LJ::ContentFlag::ILLEGAL_ACTIVITY       => "Illegal Activity",
    LJ::ContentFlag::EXPLICIT_ADULT_CONTENT => "Explicit Adult Content",
    LJ::ContentFlag::OFFENSIVE_CONTENT      => "Offensive Content",
    LJ::ContentFlag::HATRED_SITE            => "Hate Speech",
    LJ::ContentFlag::SPAM                   => "Spam",
);

our @CAT_ORDER = (
    LJ::ContentFlag::SPAM,
    LJ::ContentFlag::EXPLICIT_ADULT_CONTENT,
    LJ::ContentFlag::OFFENSIVE_CONTENT,
    LJ::ContentFlag::HATRED_SITE,
    LJ::ContentFlag::ILLEGAL_ACTIVITY,
    LJ::ContentFlag::CHILD_PORN,
);

# categories that, when selected by the user, will bring them to an Abuse report form
# value is the key name of the section of the abuse form that the user should start at
our %CATS_TO_ABUSE = (
    LJ::ContentFlag::HATRED_SITE => "hatespeech",
    LJ::ContentFlag::ILLEGAL_ACTIVITY => "illegal",
    LJ::ContentFlag::CHILD_PORN => "childporn",
);

# categories that, when selected by the user, should handle the reported content as spam
our @CATS_TO_SPAMREPORTS = (
    LJ::ContentFlag::SPAM,
);

our %STATUS_NAMES = (
    LJ::ContentFlag::NEW                 => 'New',
    LJ::ContentFlag::CLOSED              => 'Marked as Bogus Report (No Action)',
    LJ::ContentFlag::FLAG_EXPLICIT_ADULT => 'Flagged as Explicit Adult Content',
    LJ::ContentFlag::FLAG_HATRED         => 'Flagged as Hate Speech',
    LJ::ContentFlag::FLAG_ILLEGAL        => 'Flagged as Illegal Activity',
    LJ::ContentFlag::FLAG_CHILD_PORN     => 'Flagged as Nude Images of Minors',
    LJ::ContentFlag::FLAG_SELF_HARM      => 'Flagged as Self Harm',
    LJ::ContentFlag::FLAG_SEXUAL         => 'Flagged as Sexual Content',
    LJ::ContentFlag::FLAG_OTHER          => 'Flagged as Other',
);

sub category_names { \%CAT_NAMES }
sub category_order { \@CAT_ORDER }
sub categories_to_abuse { \%CATS_TO_ABUSE }
sub categories_to_spamreports { \@CATS_TO_SPAMREPORTS }
sub status_names   { \%STATUS_NAMES }

our @fields;

# there has got to be a better way to use fields with a list
BEGIN {
    @fields = qw (flagid journalid typeid itemid catid reporterid reporteruniq instime modtime status);
    eval "use fields qw(" . join (' ', @fields) . " _count); 1;" or die $@;
};


####### Class methods


# create a flag for an item
#  opts:
#   $item or $type + $itemid - need to pass $item (entry, comment, etc...) or $type constant with $itemid
#   $journal - journal the $item is in (not needed if $item passed)
#   $reporter - person flagging this item
#   $cat - category constant (why is the reporter flagging this?)
sub create {
    my ($class, %opts) = @_;

    my $journal = delete $opts{journal} || LJ::load_userid(delete $opts{journalid});
    my $type = delete $opts{type} || delete $opts{typeid};
    my $item = delete $opts{item};
    my $itemid = delete $opts{itemid};
    my $reporter = (delete $opts{reporter} || LJ::get_remote()) or croak 'no reporter';
    my $cat = delete $opts{cat} || delete $opts{catid} or croak 'no category';

    croak "need item or type" unless $item || $type;
    croak "need journal" unless $journal;

    croak "unknown options: " . join(', ', keys %opts) if %opts;

    # if $item passed, get itemid and type from it
    if ($item) {
        if ($item->isa("LJ::Entry")) {
            $itemid = $item->ditemid;
            $type = ENTRY;
        } else {
            croak "unknown item type: $item";
        }
    }

    my $uniq = LJ::UniqCookie->current_uniq;

    my %flag = (
                journalid    => $journal->id,
                itemid       => $itemid,
                typeid       => $type,
                catid        => $cat,
                reporterid   => $reporter->id,
                status       => LJ::ContentFlag::NEW,
                instime      => time(),
                reporteruniq => $uniq,
                );

    my $dbh = LJ::get_db_writer() or die "could not get db writer";
    my @params = keys %flag;
    my $bind = LJ::bindstr(@params);
    $dbh->do("INSERT INTO content_flag (" . join(',', @params) . ") VALUES ($bind)",
             undef, map { $flag{$_} } @params);
    die $dbh->errstr if $dbh->err;

    my $flagid = $dbh->{mysql_insertid};
    die "did not get an insertid" unless defined $flagid;

    # log this rating
    LJ::rate_log($reporter, 'ctflag', 1);

    $flag{flagid} = $flagid;
    my ($dbflag) = $class->absorb_row(\%flag);
    return $dbflag;
}
# alias flag() to create()
*flag = \&create;

*load_by_flagid = \&load_by_id;
sub load_by_id {
    my ($class, $flagid, %opts) = @_;
    return undef unless $flagid;
    return $class->load(flagid => $flagid+0, %opts);
}

sub load_by_flagids {
    my ($class, $flagidsref, %opts) = @_;
    croak "not passed a flagids arrayref" unless ref $flagidsref && ref $flagidsref eq 'ARRAY';
    return () unless @$flagidsref;
    return $class->load(flagids => $flagidsref, %opts);
}

sub load_by_journal {
    my ($class, $journal, %opts) = @_;
    return $class->load(journalid => LJ::want_userid($journal), %opts);
}

sub load_by_status {
    my ($class, $status, %opts) = @_;
    return $class->load(status => $status, %opts);
}

# load flags marked NEW
sub load_outstanding {
    my ($class, %opts) = @_;
    return $class->load(status => LJ::ContentFlag::NEW, %opts);
}

# given a flag, find other flags that have the same journalid, typeid, itemid, catid
sub find_similar_flags {
    my ($self, %opts) = @_;
    return $self->load(
                       journalid => $self->journalid,
                       itemid => $self->itemid,
                       typeid => $self->typeid,
                       catid => $self->catid,
                       %opts,
                       );
}

sub find_similar_flagids {
    my ($self, %opts) = @_;
    my $dbr = LJ::get_db_reader();
    my $flagids = $dbr->selectcol_arrayref("SELECT flagid FROM content_flag WHERE " .
                                           "journalid=? AND typeid=? AND itemid=? AND catid=? AND flagid != ? LIMIT 1000",
                                           undef, $self->journalid, $self->typeid, $self->itemid, $self->catid, $self->flagid);
    die $dbr->errstr if $dbr->err;
    return @$flagids;
}

# load rows from DB
# if $opts{lock}, this will lock the result set for a while so that
# other people won't get the same set of flags to work on
#
# other opts:
#  limit, catid, status, flagid, flagids (arrayref), sort
sub load {
    my ($class, %opts) = @_;

    my $instime = $opts{from};

    # default to showing everything in the past month
    $instime = time() - 86400*30 unless defined $instime;
    $opts{instime} ||= $instime;

    my $limit = $opts{limit}+0 || 1000;

    my $catid = $opts{catid};
    my $status = $opts{status};
    my $flagid = $opts{flagid};
    my $flagidsref = $opts{flagids};

    croak "cannot pass flagid and flagids" if $flagid && $flagidsref;

    my $sort = $opts{sort};

    my $fields = join(',', @fields);

    my $dbr = LJ::get_db_reader() or die "Could not get db reader";

    my @vals = ();
    my $constraints = "";

    # add other constraints
    foreach my $c (qw( journalid typeid itemid catid status flagid modtime instime reporterid )) {
        my $val = delete $opts{$c} or next;

        my $cmp = '=';

        # use > for selecting by time, = for everything else
        if ($c eq 'modtime' || $c eq 'instime') {
            $cmp = '>';
        }

        # build sql
        $constraints .= ($constraints ? " AND " : " ") . "$c $cmp ?";
        push @vals, $val;
    }

    if ($flagidsref) {
        my @flagids = @$flagidsref;
        my $bind = LJ::bindstr(@flagids);
        $constraints .= ($constraints ? " AND " : " ") . "flagid IN ($bind)";
        push @vals, @flagids;
    }

    croak "no constraints specified" unless $constraints;

    my @locked;

    if ($opts{lock}) {
        if (my @locked = $class->locked_flags) {
            my $lockedbind = LJ::bindstr(@locked);
            $constraints .= " AND flagid NOT IN ($lockedbind)";
            push @vals, @locked;
        }
    }

    my $groupby = '';

    $sort =~ s/\W//g if $sort;

    if ($opts{group}) {
        $groupby = ' GROUP BY journalid,typeid,itemid';
        $fields .= ',COUNT(flagid) as count';
        $sort ||= 'count';
    }

    $sort ||= 'instime';

    my $sql = "SELECT $fields FROM content_flag WHERE $constraints $groupby ORDER BY $sort DESC LIMIT $limit";
    print STDERR $sql if $opts{debug};

    my $rows = $dbr->selectall_arrayref($sql, undef, @vals);
    die $dbr->errstr if $dbr->err;

    if ($opts{lock}) {
        # lock flagids for a few minutes
        my @flagids = map { $_->[0] } @$rows;

        # lock flags on the same items as well
        my @items = $class->load_by_flagids(\@flagids);
        my @related_flagids = map { $_->find_similar_flagids } @items;

        push @flagids, (@related_flagids, @locked);

        $class->lock(@flagids);
    }

    return map { $class->absorb_row($_) } @$rows;
}

sub locked_flags {
    my $class = shift;
    my %locked = $class->_locked_values;
    return keys %locked;
}

sub _locked_values {
    my $class = shift;
    my %locked = %{ LJ::MemCache::get($class->memcache_key) || {} };

    # delete out flags that were locked >5 minutes ago
    foreach (keys %locked) {
        delete $locked{$_} if $locked{$_} < time() - 5*60;
    }

    return %locked;
}


# append these flagids to the locked set
sub lock {
    my ($class, @flagids) = @_;
    my %locked = $class->_locked_values;

    # add in the new flags
    $locked{$_} = time() foreach @flagids;

    LJ::MemCache::set($class->memcache_key, \%locked, 5 * 60);
}

# remove these flagids from the locked set
sub unlock {
    my ($class, @flagids) = @_;

    # if there's nothing memcached, there's nothing to unlock!
    my %locked = $class->_locked_values
        or return;

    delete $locked{$_} foreach @flagids;

    LJ::MemCache::set($class->memcache_key, \%locked, 5 * 60);
}

sub memcache_key { 'ct_flag_locked' }

sub absorb_row {
    my ($class, $row) = @_;

    my $self = fields::new($class);

    if (ref $row eq 'ARRAY') {
        $self->{$_} = (shift @$row) foreach @fields;
        $self->{_count} = (shift @$row) if @$row;
    } elsif (ref $row eq 'HASH') {
        $self->{$_} = $row->{$_} foreach @fields;

        if ($row->{'count'}) {
            $self->{_count} = $row->{'count'};
        }
    } else {
        croak "unknown row type";
    }

    return $self;
}

# given journalid, typeid, and itemid returns user objects of all the reporters of this item, along with the support requests they opened
sub get_reporters {
    my ($class, %opts) = @_;

    croak "invalid params" unless $opts{journalid} && $opts{typeid};
    $opts{itemid} += 0;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare('SELECT reporterid, supportid FROM content_flag WHERE ' .
                             'journalid=? AND typeid=? AND itemid=? ORDER BY instime DESC LIMIT 1000');
    $sth->execute($opts{journalid}, $opts{typeid}, $opts{itemid});
    die $dbr->errstr if $dbr->err;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    return @rows;
}

sub requests_exist_for_flag {
    my ($class, $flag) = @_;

    my @reporters = $class->get_reporters( journalid => $flag->journalid, typeid => $flag->typeid, itemid => $flag->itemid );
    foreach my $reporter (@reporters) {
        return 1 if $reporter->{supportid};
    }

    return 0;
}

# returns a hash of catid => count
sub flag_count_by_category {
    my ($class, %opts) = @_;

    # this query is unpleasant, so memcache it
    my $countref = LJ::MemCache::get('ct_flag_cat_count');
    return %$countref if $countref;

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectall_hashref("SELECT catid, COUNT(*) as cat_count FROM content_flag " .
                                       "WHERE status = 'N' GROUP BY catid", 'catid');
    die $dbr->errstr if $dbr->err;

    my %count = map { $_, $rows->{$_}->{cat_count} } keys %$rows;

    LJ::MemCache::set('ct_flag_cat_count', \%count, 5);

    return %count;
}

sub get_most_common_cat_for_flag {
    my ($class, %opts) = @_;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT catid, COUNT(catid) as cat_count FROM content_flag " .
                            "WHERE journalid = ? AND typeid = ? AND itemid = ? GROUP BY catid");
    $sth->execute($opts{journalid}, $opts{typeid}, $opts{itemid});
    die $dbr->errstr if $dbr->err;

    my $cat_max = 0;
    my $catid_with_max;
    while (my $row = $sth->fetchrow_hashref) {
        if ($row->{cat_count} > $cat_max) {
            $cat_max = $row->{cat_count};
            $catid_with_max = $row->{catid};
        }
    }

    return $catid_with_max;
}

# returns a url for flagging this item
# pass in LJ::User, LJ::Entry or LJ::Comment
sub flag_url {
    my ($class, $item, %opts) = @_;

    return unless $item && ref $item;

    my $type = $opts{type} || '';
    my $base_url = "$LJ::SITEROOT/tools/content_flag.bml";

    if ($item->isa('LJ::User')) {
        return "$base_url?user=" . $item->user;
    } elsif ($item->isa('LJ::Entry')) {
        my $ditemid = $item->valid ? $item->ditemid : 0;
        return "$base_url?user=" . $item->journal->user . "&itemid=$ditemid";
    }

    croak "Unknown item $item passed to flag_url";
}

sub adult_flag_url {
    my ($class, $item) = @_;

    return $class->flag_url($item, type => 'adult');
}

# changes an adult post into a fake LJ-cut if this journal/entry is marked as adult content
# and the viewer doesn't want to see such entries
sub transform_post {
    my ($class, %opts) = @_;

    my $post = delete $opts{post} or return '';
    return $post if LJ::conf_test($LJ::DISABLED{content_flag});

    my $entry = $opts{entry} or return $post;
    my $journal = $opts{journal} or return $post;
    my $remote = delete $opts{remote} || LJ::get_remote();

    # we should show the entry expanded if:
    # the remote user owns the journal that the entry is posted in OR
    # the remote user posted the entry
    my $poster = $entry->poster;
    return $post if LJ::isu($remote) && ($remote->can_manage($journal) || $remote->equals($poster));

    my $adult_content = $entry->adult_content_calculated || $journal->adult_content_calculated;
    return $post if $adult_content eq 'none';

    my $view_adult = LJ::isu($remote) ? $remote->hide_adult_content : 'concepts';
    if (!$view_adult || $view_adult eq 'none' || ($view_adult eq 'explicit' && $adult_content eq 'concepts')) {
        return $post;
    }

    # return a fake LJ-cut going to an adult content warning interstitial page
    my $adult_interstitial = sub {
        return $class->adult_interstitial_link(type => shift(), %opts) || $post;
    };

    if ($adult_content eq 'concepts') {
        return $adult_interstitial->('concepts');
    } elsif ($adult_content eq 'explicit') {
        return $adult_interstitial->('explicit');
    }

    return $post;
}

# returns url for adult content warning page
sub adult_interstitial_url {
    my ($class, %opts) = @_;

    my $type = $opts{type};
    my $entry = $opts{entry};
    return '' unless $type;

    my $ret = $opts{ret};
    $ret ||= $entry->url if $entry;

    my $url = "$LJ::SITEROOT/misc/adult_${type}.bml";
    $url .= "?ret=$ret" if $ret;

    return $url;
}

# returns path for adult content warning page
sub adult_interstitial_path {
    my ($class, %opts) = @_;

    my $type = $opts{type};
    return '' unless $type;

    my $path = "$LJ::HOME/htdocs/misc/adult_${type}.bml";
    return $path;
}

# returns an link to an adult content warning page
sub adult_interstitial_link {
    my ($class, %opts) = @_;

    my $entry = $opts{entry};
    my $type = $opts{type};
    return '' unless $entry && $type;

    my $url = $entry->url;
    my $msg;

    if ($type eq 'explicit') {
        $msg = LJ::Lang::ml('contentflag.viewingexplicit');
    } else {
        $msg = LJ::Lang::ml('contentflag.viewingconcepts');
    }

    return '' unless $msg;

    my $fake_cut = qq {<b>( <a href="$url">$msg</a> )</b>};
    return $fake_cut;
}

sub check_adult_cookie {
    my ($class, $returl, $postref, $type) = @_;

    my $cookiename = __PACKAGE__->cookie_name($type);
    return undef unless $cookiename;

    my $has_seen = $BML::COOKIE{$cookiename};
    my $adult_check = $postref->{adult_check};

    BML::set_cookie($cookiename => '1', 0) if $adult_check;
    return ($has_seen || $adult_check) ? $returl : undef;
}

sub cookie_name {
    my ($class, $type) = @_;

    return "" unless $type eq "concepts" || $type eq "explicit";
    return "adult_$type";
}


######## instance methods

sub u { LJ::load_userid($_[0]->journalid) }
sub flagid { $_[0]->{flagid} }
sub status { $_[0]->{status} }
sub catid { $_[0]->{catid} }
sub modtime { $_[0]->{modtime} }
sub typeid { $_[0]->{typeid} }
sub itemid { $_[0]->{itemid} }
sub count { $_[0]->{_count} }
sub journalid { $_[0]->{journalid} }
sub reporter { LJ::load_userid($_[0]->{reporterid}) }

sub set_field {
    my ($self, $field, $val) = @_;
    my $dbh = LJ::get_db_writer() or die;

    my $modtime = time();

    $dbh->do("UPDATE content_flag SET $field = ?, modtime = UNIX_TIMESTAMP() WHERE flagid = ?", undef,
             $val, $self->flagid);
    die $dbh->errstr if $dbh->err;

    $self->{$field} = $val;
    $self->{modtime} = $modtime;

    return 1;
}

sub set_status {
    my ($self, $status) = @_;
    return $self->set_field('status', $status);
}

# returns flagged item (entry, comment, etc...)
sub item {
    my ($self, $status) = @_;

    my $typeid = $self->typeid;
    if ($typeid == LJ::ContentFlag::ENTRY) {
        return LJ::Entry->new($self->u, ditemid => $self->itemid);
    } elsif ($typeid == LJ::ContentFlag::COMMENT) {
        return LJ::Comment->new($self->u, dtalkid => $self->itemid);
    }

    return undef;
}

sub url {
    my $self = shift;

    if ($self->item) {
        return $self->item->url;
    } elsif ($self->typeid == LJ::ContentFlag::JOURNAL) {
        return $self->u->journal_base;
    } elsif ($self->typeid == LJ::ContentFlag::PROFILE) {
        return $self->u->profile_url('full' => 1);
    } else {
        return undef;
    }

}

sub summary {

}

sub close { $_[0]->set_status(LJ::ContentFlag::CLOSED) }

sub delete {
    my ($self) = @_;
    my $dbh = LJ::get_db_writer() or die;

    $dbh->do("DELETE FROM content_flag WHERE flagid = ?", undef, $self->flagid);
    die $dbh->errstr if $dbh->err;

    return 1;
}


sub move_to_abuse {
    my ($class, $action, @flags) = @_;

    return unless $action;
    return unless @flags;

    my %req;
    $req{reqtype}      = "email";
    $req{reqemail}     = $LJ::CONTENTFLAG_EMAIL;
    $req{no_autoreply} = 1;

    if ($action eq LJ::ContentFlag::FLAG_CHILD_PORN) {
        $req{spcatid} = $LJ::CONTENTFLAG_PRIORITY;
    } else {
        $req{spcatid} = $LJ::CONTENTFLAG_ABUSE;
    }

    return unless $req{spcatid};

    # take one flag, should be representative of all
    my $flag = $flags[0];
    $req{subject} = "$action: " . $flag->u->user;

    $req{body}  = "Username: " . $flag->u->user . "\n";
    $req{body} .= "URL: " . $flag->url . "\n";
    $req{body} .= "\n" . "=" x 25 . "\n\n";

    foreach (@flags) {
        $req{body} .= "Reporter: " . $_->reporter->user;
        $req{body} .= " (" . $CAT_NAMES{$_->catid} . ")\n";
    }

    $req{flagid} = $flag->flagid;

    my @errors;
    # returns support request id
    return LJ::Support::file_request(\@errors, \%req);
}

sub set_supportid {
    my ($class, $flagid, $supportid) = @_;

    return 0 unless $flagid && $supportid;

    my $dbh = LJ::get_db_writer();
    $dbh->do("UPDATE content_flag SET supportid = ? WHERE flagid = ?", undef, $supportid, $flagid);
    die $dbh->errstr if $dbh->err;

    return 1;
}

sub get_admin_flag_from_status {
    my ($class, $status) = @_;

    my %flags = (
        E => 'explicit_adult',
        H => 'hate_speech',
        I => 'illegal_activity',
        P => 'child_porn',
        X => 'self_harm',
        L => 'sexual_content',
        R => 'other',
    );

    return $flags{$status} || undef;
}

1;
