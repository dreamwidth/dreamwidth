package LJ::Poll;
use strict;
use Carp qw (croak);
use LJ::Entry;
use LJ::Poll::Question;
use LJ::Event::PollVote;
use LJ::Typemap;

##
## Memcache routines
##
use base 'LJ::MemCacheable';
    *_memcache_id                   = \&id;
sub _memcache_key_prefix            { "poll" }
sub _memcache_stored_props          {
    # first element of props is a VERSION
    # next - allowed object properties
    return qw/ 1
               ditemid itemid
               pollid journalid posterid whovote whoview name status questions props
               /;
}
    *_memcache_hashref_to_object    = \*absorb_row;
sub _memcache_expires               { 24*3600 }


# loads a poll
sub new {
    my ($class, $pollid) = @_;

    my $self = {
        pollid => $pollid,
    };

    bless $self, $class;
    return $self;
}

# create a new poll
# returns created poll object on success, 0 on failure
# can be called as a class method or an object method
#
# %opts:
#   questions: arrayref of poll questions
#   error: scalarref for errors to be returned in
#   entry: LJ::Entry object that this poll is attached to
#   ditemid, journalid, posterid: required if no entry object passed
#   whovote: who can vote in this poll
#   whoview: who can view this poll
#   name: name of this poll
#   status: set to 'X' when poll is closed
sub create {
    my ($classref, %opts) = @_;

    my $entry = $opts{entry};

    my ($ditemid, $journalid, $posterid);

    if ($entry) {
        $ditemid   = $entry->ditemid;
        $journalid = $entry->journalid;
        $posterid  = $entry->posterid;
    } else {
        $ditemid   = $opts{ditemid} or croak "No ditemid";
        $journalid = $opts{journalid} or croak "No journalid";
        $posterid  = $opts{posterid} or croak "No posterid";
    }

    my $whovote = $opts{whovote} or croak "No whovote";
    my $whoview = $opts{whoview} or croak "No whoview";
    my $name    = $opts{name} || '';

    my $questions = delete $opts{questions}
        or croak "No questions passed to create";

    # get a new pollid
    my $pollid = LJ::alloc_global_counter('L'); # L == poLL
    unless ($pollid) {
        ${$opts{error}} = "Could not get pollid";
        return 0;
    }

    my $u = LJ::load_userid($journalid)
        or die "Invalid journalid $journalid";

    my $dbh = LJ::get_db_writer();

    $u->do( "INSERT INTO poll2 (journalid, pollid, posterid, whovote, whoview, name, ditemid) " .
            "VALUES (?, ?, ?, ?, ?, ?, ?)", undef,
            $journalid, $pollid, $posterid, $whovote, $whoview, $name, $ditemid );
    die $u->errstr if $u->err;

    # made poll, insert global pollid->journalid mapping into global pollowner map
    $dbh->do( "INSERT INTO pollowner (journalid, pollid) VALUES (?, ?)", undef,
              $journalid, $pollid );

    die $dbh->errstr if $dbh->err;

    ## start inserting poll questions
    my $qnum = 0;

    foreach my $q (@$questions) {
        $qnum++;

        $u->do( "INSERT INTO pollquestion2 (journalid, pollid, pollqid, sortorder, type, opts, qtext) " .
                "VALUES (?, ?, ?, ?, ?, ?, ?)", undef,
                $journalid, $pollid, $qnum, $qnum, $q->{'type'}, $q->{'opts'}, $q->{'qtext'} );
        die $u->errstr if $u->err;

        ## start inserting poll items
        my $inum = 0;
        foreach my $it (@{$q->{'items'}}) {
            $inum++;

            $u->do( "INSERT INTO pollitem2 (journalid, pollid, pollqid, pollitid, sortorder, item) " .
                    "VALUES (?, ?, ?, ?, ?, ?)", undef, $journalid, $pollid, $qnum, $inum, $inum, $it->{'item'} );
            die $u->errstr if $u->err;
        }
        ## end inserting poll items

    }
    ## end inserting poll questions

    if (ref $classref eq 'LJ::Poll') {
        $classref->{pollid} = $pollid;
        foreach my $prop (keys %{$opts{props}}) {
            $classref->set_prop($prop, $opts{props}->{$prop});
        }

        return $classref;
    }

    my $pollobj = LJ::Poll->new($pollid);
    foreach my $prop (keys %{$opts{props}}) {
        $pollobj->set_prop($prop, $opts{props}->{$prop});
    }

    return $pollobj;
}

sub clean_poll {
    my ($class, $ref) = @_;
    if ($$ref !~ /[<>]/) {
        LJ::text_out($ref);
        return;
    }

    my $poll_eat    = [qw[head title style layer iframe applet object]];
    my $poll_allow  = [qw[a b i u strong em img]];
    my $poll_remove = [qw[bgsound embed object caption link font]];

    LJ::CleanHTML::clean($ref, {
        'wordlength' => 40,
        'addbreaks'  => 0,
        'eat'        => $poll_eat,
        'mode'       => 'deny',
        'allow'      => $poll_allow,
        'remove'     => $poll_remove,
    });
    LJ::text_out($ref);
}

sub contains_new_poll {
    my ($class, $postref) = @_;
    return ($$postref =~ /<(?:lj-)?poll\b/i);
}

# parses poll tags and returns whatever polls were parsed out
sub new_from_html {
    my ($class, $postref, $error, $iteminfo) = @_;

    $iteminfo->{'posterid'}  += 0;
    $iteminfo->{'journalid'} += 0;

    my $newdata;

    my $popen = 0;
    my %popts;

    my $numq  = 0;
    my $qopen = 0;
    my %qopts;

    my $numi  = 0;
    my $iopen = 0;
    my %iopts;

    my @polls;  # completed parsed polls

    my $p = HTML::TokeParser->new($postref);

    # if we're being called from mailgated, then we're not in web context and therefore
    # do not have any BML::ml functionality.  detect this now and report errors in a
    # plaintext, non-translated form to be bounced via email.

    # FIXME: the above comment is obsolete, we now have LJ::Lang::ml
    # which will do the right thing
    my $have_bml = eval { LJ::Lang::ml() } || ! $@;

    my $err = sub {
        # more than one element, either make a call to LJ::Lang::ml
        # or build up a semi-useful error string from it
        if (@_ > 1) {
            if ($have_bml) {
                $$error = LJ::Lang::ml(@_);
                return 0;
            }

            $$error = shift() . ": ";
            while (my ($k, $v) = each %{$_[0]}) {
                $$error .= "$k=$v,";
            }
            chop $$error;
            return 0;
        }

        # single element, either look up in %BML::ML or return verbatim
        $$error = $have_bml ? LJ::Lang::ml($_[0]) : $_[0];
        return 0;
    };

    while (my $token = $p->get_token) {
        my $type = $token->[0];
        my $append;

        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];
            my $opts = $token->[2];

            ######## Begin poll tag

            if ($tag eq "lj-poll" || $tag eq "poll") {
                return $err->('poll.error.nested', { 'tag' => 'poll' })
                    if $popen;

                $popen = 1;
                %popts = ();
                $popts{'questions'} = [];

                $popts{'name'} = $opts->{'name'};
                $popts{'whovote'} = lc($opts->{'whovote'}) || "all";
                $popts{'whoview'} = lc($opts->{'whoview'}) || "all";

                # "friends" equals "trusted" for backwards compatibility
                $popts{whovote} = "trusted" if $popts{whovote} eq "friends";
                $popts{whoview} = "trusted" if $popts{whoview} eq "friends";

                my $journal = LJ::load_userid($iteminfo->{posterid});
                if (LJ::run_hook("poll_unique_prop_is_enabled", $journal)) {
                    $popts{props}->{unique} = $opts->{unique} ? 1 : 0;
                }
                if (LJ::run_hook("poll_createdate_prop_is_enabled", $journal)) {
                    $popts{props}->{createdate} = $opts->{createdate} || undef;
                }
                LJ::run_hook('get_more_options_from_poll', finalopts => \%popts, givenopts => $opts, journalu => $journal);

                if ($popts{'whovote'} ne "all" &&
                    $popts{'whovote'} ne "trusted")
                {
                    return $err->('poll.error.whovote');
                }
                if ($popts{'whoview'} ne "all" &&
                    $popts{'whoview'} ne "trusted" &&
                    $popts{'whoview'} ne "none")
                {
                    return $err->('poll.error.whoview');
                }
            }

            ######## Begin poll question tag

            elsif ($tag eq "lj-pq" || $tag eq "poll-question")
            {
                return $err->('poll.error.nested', { 'tag' => 'poll-question' })
                    if $qopen;

                return $err->('poll.error.missingljpoll2')
                    unless $popen;

                return $err->("poll.error.toomanyquestions")
                    unless $numq++ < 255;

                $qopen = 1;
                %qopts = ();
                $qopts{'items'} = [];

                $qopts{'type'} = $opts->{'type'};
                if ($qopts{'type'} eq "text") {
                    my $size = 35;
                    my $max = 255;
                    if (defined $opts->{'size'}) {
                        if ($opts->{'size'} > 0 &&
                            $opts->{'size'} <= 100)
                        {
                            $size = $opts->{'size'}+0;
                        } else {
                            return $err->('poll.error.badsize2');
                        }
                    }
                    if (defined $opts->{'maxlength'}) {
                        if ($opts->{'maxlength'} > 0 &&
                            $opts->{'maxlength'} <= 255)
                        {
                            $max = $opts->{'maxlength'}+0;
                        } else {
                            return $err->('poll.error.badmaxlength2');
                        }
                    }

                    $qopts{'opts'} = "$size/$max";
                }
                if ($qopts{'type'} eq "scale")
                {
                    my $from = 1;
                    my $to = 10;
                    my $by = 1;

                    if (defined $opts->{'from'}) {
                        $from = int($opts->{'from'});
                    }
                    if (defined $opts->{'to'}) {
                        $to = int($opts->{'to'});
                    }
                    if (defined $opts->{'by'}) {
                        $by = int($opts->{'by'});
                    }
                    if ($by < 1) {
                        return $err->('poll.error.scaleincrement');
                    }
                    if ($from >= $to) {
                        return $err->('poll.error.scalelessto');
                    }
                    if ((($to-$from)/$by) > 20) {
                        return $err->('poll.error.scaletoobig');
                    }
                    $qopts{'opts'} = "$from/$to/$by";
                }

                $qopts{'type'} = lc($opts->{'type'}) || "text";

                if ($qopts{'type'} ne "radio" &&
                    $qopts{'type'} ne "check" &&
                    $qopts{'type'} ne "drop" &&
                    $qopts{'type'} ne "scale" &&
                    $qopts{'type'} ne "text")
                {
                    return $err->('poll.error.unknownpqtype2');
                }
            }

            ######## Begin poll item tag

            elsif ($tag eq "lj-pi" || $tag eq "poll-item")
            {
                if ($iopen) {
                    return $err->('poll.error.nested', { 'tag' => 'poll-item' });
                }
                if (! $qopen) {
                    return $err->('poll.error.missingljpq2');
                }

                return $err->("poll.error.toomanyopts")
                    unless $numi++ < 255;

                if ($qopts{'type'} eq "text")
                {
                    return $err->('poll.error.noitemstext2');
                }

                $iopen = 1;
                %iopts = ();
            }

            #### not a special tag.  dump it right back out.

            else
            {
                $append .= "<$tag";
                foreach (keys %$opts) {
                    $opts->{$_} = LJ::no_utf8_flag($opts->{$_});
                    $append .= " $_=\"" . LJ::ehtml($opts->{$_}) . "\"";
                }
                $append .= ">";
            }
        }
        elsif ($type eq "E")
        {
            my $tag = $token->[1];

            ##### end POLL

            if ($tag eq "lj-poll" || $tag eq "poll") {
                return $err->('poll.error.tagnotopen', { 'tag' => 'poll' })
                    unless $popen;

                $popen = 0;

                return $err->('poll.error.noquestions')
                    unless @{$popts{'questions'}};

                $popts{'journalid'} = $iteminfo->{'journalid'};
                $popts{'posterid'} = $iteminfo->{'posterid'};

                # create a fake temporary poll object
                my $pollobj = LJ::Poll->new;
                $pollobj->absorb_row(\%popts);
                push @polls, $pollobj;

                $append .= "<poll-placeholder>";
            }

            ##### end QUESTION

            elsif ($tag eq "lj-pq" || $tag eq "poll-question") {
                return $err->('poll.error.tagnotopen', { 'tag' => 'poll-question' })
                    unless $qopen;

                unless ($qopts{'type'} eq "scale" ||
                        $qopts{'type'} eq "text" ||
                        @{$qopts{'items'}})
                {
                    return $err->('poll.error.noitems');
                }

                $qopts{'qtext'} =~ s/^\s+//;
                $qopts{'qtext'} =~ s/\s+$//;
                my $len = length($qopts{'qtext'})
                    or return $err->('poll.error.notext2');

                my $question = LJ::Poll::Question->new_from_row(\%qopts);
                push @{$popts{'questions'}}, $question;
                $qopen = 0;
                $numi = 0; # number of open opts resets
            }

            ##### end ITEM

            elsif ($tag eq "lj-pi" || $tag eq "poll-item") {
                return $err->('poll.error.tagnotopen', { 'tag' => 'poll-item' })
                    unless $iopen;

                $iopts{'item'} =~ s/^\s+//;
                $iopts{'item'} =~ s/\s+$//;

                my $len = length($iopts{'item'});
                return $err->('poll.error.pitoolong2', { 'len' => $len, })
                    if $len > 255 || $len < 1;

                push @{$qopts{'items'}}, { %iopts };
                $iopen = 0;
            }

            ###### not a special tag.

            else
            {
                $append .= "</$tag>";
            }
        }
        elsif ($type eq "T" || $type eq "D")
        {
            $append = $token->[1];
        }
        elsif ($type eq "C") {
            # <!-- comments -->. keep these, let cleanhtml deal with it.
            $newdata .= $token->[1];
        }
        elsif ($type eq "PI") {
            $newdata .= "<?$token->[1]>";
        }
        else {
            $newdata .= "<!-- OTHER: " . $type . "-->\n";
        }

        ##### append stuff to the right place
        if (length($append))
        {
            if ($iopen) {
                $iopts{'item'} .= $append;
            }
            elsif ($qopen) {
                $qopts{'qtext'} .= $append;
            }
            elsif ($popen) {
                0;       # do nothing.
            } else {
                $newdata .= $append;
            }
        }

    }

    if ($popen) { return $err->('poll.error.unlockedtag', { 'tag' => 'poll' }); }
    if ($qopen) { return $err->('poll.error.unlockedtag', { 'tag' => 'poll-question' }); }
    if ($iopen) { return $err->('poll.error.unlockedtag', { 'tag' => 'poll-item' }); }

    $$postref = $newdata;
    return @polls;
}

###### Utility methods

# if we have a complete poll object (sans pollid) we can save it to
# the database and get a pollid
sub save_to_db {

    # OBSOLETE METHOD?

    my $self = shift;
    my %opts = @_;

    my %createopts;

    # name and props are optional fields
    $createopts{name} = $opts{name} || $self->{name};
    $createopts{props} = $opts{props} || $self->{props};

    foreach my $f (qw(ditemid journalid posterid questions whovote whoview)) {
        $createopts{$f} = $opts{$f} || $self->{$f} or croak "Field $f required for save_to_db";
    }

    # create can optionally take an object as the invocant
    return LJ::Poll::create($self, %createopts);
}

# loads poll from db
sub _load {
    my $self = shift;

    return $self if $self->{_loaded};

    croak "_load called on LJ::Poll with no pollid"
        unless $self->pollid;

    # Requests context
    if (my $obj = $LJ::REQ_CACHE_POLL{ $self->id }){
        %{ $self }= %{ $obj }; # change object in memory
        return $self;
    }

    # Try to get poll from MemCache
    return $self if $self->_load_from_memcache;

    # Load object from MySQL database
    my $dbr = LJ::get_db_reader();

    my $journalid = $dbr->selectrow_array("SELECT journalid FROM pollowner WHERE pollid=?", undef, $self->pollid);
    die $dbr->errstr if $dbr->err;

    my $row = '';

    my $u = LJ::load_userid( $journalid )
        or die "Invalid journalid $journalid";

    $row = $u->selectrow_hashref( "SELECT pollid, journalid, ditemid, " .
                                  "posterid, whovote, whoview, name, status " .
                                  "FROM poll2 WHERE pollid=? " .
                                  "AND journalid=?", undef, $self->pollid, $journalid );
    die $u->errstr if $u->err;

    return undef unless $row;

    $self->absorb_row($row);
    $self->{_loaded} = 1; # object loaded

    # store constructed object in caches
    $self->_store_to_memcache;
    $LJ::REQ_CACHE_POLL{ $self->id } = $self;

    return $self;
}

sub absorb_row {
    my ($self, $row) = @_;
    croak "No row" unless $row;

    # questions is an optional field for creating a fake poll object for previewing
    $self->{ditemid} = $row->{ditemid} || $row->{itemid}; # renamed to ditemid in poll2
    $self->{$_} = $row->{$_} foreach qw(pollid journalid posterid whovote whoview name status questions props);
    $self->{_loaded} = 1;
    return $self;
}

# Mark poll as closed
sub close_poll {
    my $self = shift;

    # Nothing to do if poll is already closed
    return if ($self->{status} eq 'X');

    my $u = LJ::load_userid($self->journalid)
        or die "Invalid journalid " . $self->journalid;

    my $dbh = LJ::get_db_writer();

    $u->do( "UPDATE poll2 SET status='X' where pollid=? AND journalid=?",
            undef, $self->pollid, $self->journalid );
    die $u->errstr if $u->err;

    # poll status has changed
    $self->_remove_from_memcache;
    delete $LJ::REQ_CACHE_POLL{ $self->id };

    $self->{status} = 'X';
}

# Mark poll as open
sub open_poll {
    my $self = shift;

    # Nothing to do if poll is already open
    return if ($self->{status} eq '');

    my $u = LJ::load_userid($self->journalid)
        or die "Invalid journalid " . $self->journalid;

    my $dbh = LJ::get_db_writer();

    $u->do( "UPDATE poll2 SET status='' where pollid=? AND journalid=?",
            undef, $self->pollid, $self->journalid );
    die $u->errstr if $u->err;

    # poll status has changed
    $self->_remove_from_memcache;
    delete $LJ::REQ_CACHE_POLL{ $self->id };

    $self->{status} = '';
}
######### Accessors
# ditemid
*ditemid = \&itemid;
sub itemid {
    my $self = shift;
    $self->_load;
    return $self->{ditemid};
}
sub name {
    my $self = shift;
    $self->_load;
    return $self->{name};
}
sub whovote {
    my $self = shift;
    $self->_load;
    return $self->{whovote};
}
sub whoview {
    my $self = shift;
    $self->_load;
    return $self->{whoview};
}
sub journalid {
    my $self = shift;
    $self->_load;
    return $self->{journalid};
}
sub posterid {
    my $self = shift;
    $self->_load;
    return $self->{posterid};
}
sub poster {
    my $self = shift;
    return LJ::load_userid($self->posterid);
}

*id = \&pollid;
sub pollid { $_[0]->{pollid} }

sub url {
    my $self = shift;
    return "$LJ::SITEROOT/poll/?id=" . $self->id;
}

sub entry {
    my $self = shift;
    return LJ::Entry->new($self->journal, ditemid => $self->ditemid);
}

sub journal {
    my $self = shift;
    return LJ::load_userid($self->journalid);
}

# return true if poll is closed
sub is_closed {
    my $self = shift;
    $self->_load;
    return $self->{status} eq 'X' ? 1 : 0;
}

# return true if remote is also the owner
sub is_owner {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    return 1 if $remote && $remote->userid == $self->posterid;
    return 0;
}

# poll requires unique answers (by email address)
sub is_unique {
    my $self = shift;

    return LJ::run_hook("poll_unique_prop_is_enabled", $self->poster) && $self->prop("unique") ? 1 : 0;
}

# poll requires voters to be created on or before a certain date
sub is_createdate_restricted {
    my $self = shift;

    return LJ::run_hook("poll_createdate_prop_is_enabled", $self->poster) && $self->prop("createdate") ? 1 : 0;
}

# do we have a valid poll?
sub valid {
    my $self = shift;
    return 0 unless $self->pollid;
    my $res = eval { $self->_load };
    warn "Error loading poll id: " . $self->pollid . ": $@\n"
        if $@;
    return $res;
}

# get a question by pollqid
sub question {
    my ($self, $pollqid) = @_;
    my @qs = $self->questions;
    my ($q) = grep { $_->pollqid == $pollqid } @qs;
    return $q;
}

##### Poll rendering

# returns the time that the given user answered the given poll
sub get_time_user_submitted {
    my ( $self, $u ) = @_;

    return $self->journal->selectrow_array( 'SELECT datesubmit FROM pollsubmission2 '.
                                            'WHERE pollid=? AND userid=? AND journalid=?',
                                            undef, $self->pollid, $u->userid, $self->journalid );

}

# expects a fake poll object (doesn't have to have pollid) and
# an arrayref of questions in the poll object
sub preview {
    my $self = shift;

    my $ret = '';

    $ret .= "<form action='#'>\n";
    $ret .= "<b>" . LJ::Lang::ml('poll.pollnum', { 'num' => 'xxxx' }) . "</b>";

    my $name = $self->name;
    if ($name) {
        LJ::Poll->clean_poll(\$name);
        $ret .= " <i>$name</i>";
    }

    $ret .= "<br />\n";

    my $whoview = $self->whoview eq "none" ? "none_remote" : $self->whoview;
    $ret .= LJ::Lang::ml('poll.security2', { 'whovote' => LJ::Lang::ml('poll.security.'.$self->whovote), 'whoview' => LJ::Lang::ml('poll.security.'.$whoview), });

    # iterate through all questions
    foreach my $q ($self->questions) {
        $ret .= $q->preview_as_html;
    }

    $ret .= LJ::html_submit('', LJ::Lang::ml('poll.submit'), { 'disabled' => 1 }) . "\n";
    $ret .= "</form>";

    return $ret;
}

sub render_results {
    my $self = shift;
    my %opts = @_;
    return $self->render(mode => 'results', %opts);
}

sub render_enter {
    my $self = shift;
    my %opts = @_;
    return $self->render(mode => 'enter', %opts);
}

sub render_ans {
    my $self = shift;
    my %opts = @_;
    return $self->render(mode => 'ans', %opts);
}

# returns HTML of rendered poll
# opts:
#   mode => enter|results|ans
#   qid  => show a specific question
#   page => page #
sub render {
    my ($self, %opts) = @_;

    my $remote = LJ::get_remote();
    my $ditemid = $self->ditemid;
    my $pollid = $self->pollid;

    my $mode     = delete $opts{mode};
    my $qid      = delete $opts{qid};
    my $page     = delete $opts{page};
    my $pagesize = delete $opts{pagesize};

    # Default pagesize.
    $pagesize = 2000 unless $pagesize;

    return "<b>[ Poll owner has been deleted ]</b>" unless $self->journal->clusterid;
    return "<b>[" . LJ::Lang::ml('poll.error.pollnotfound', { 'num' => $pollid }) . "]</b>" unless $pollid;
    return "<b>[" . LJ::Lang::ml('poll.error.noentry') . "</b>" unless $ditemid;

    my $can_vote = $self->can_vote;

    my $dbr = LJ::get_db_reader();

    # update the mode if we need to
    $mode = 'results' if ((!$remote && !$mode) || $self->is_closed);
    if ($remote && !$mode) {
        my $time = $self->get_time_user_submitted($remote);
        $mode = $time ? 'results' : $can_vote ? 'enter' : 'results';
    }

    my $sth;
    my $ret = '';

    ### load all the questions
    my @qs = $self->questions;

    ### view answers to a particular question in a poll
    if ($mode eq "ans") {
        return "<b>[" . LJ::Lang::ml('poll.error.cantview') . "]</b>"
            unless $self->can_view;
        my $q = $self->question($qid)
            or return "<b>[" . LJ::Lang::ml('poll.error.questionnotfound') . "]</b>";

        my $text = $q->text;
        LJ::Poll->clean_poll(\$text);
        $ret .= $text;
        $ret .= '<div>' . $q->answers_as_html($self->journalid, $page, $pagesize) . '</div>';
        return $ret;
    }

    # Users cannot vote unless they are logged in
    return "<?needlogin?>"
        if $mode eq 'enter' && !$remote;

    my $do_form = $mode eq 'enter' && $can_vote;

    # from here out, if they can't vote, we're going to force
    # them to just see results.
    $mode = 'results' unless $can_vote;

    my %preval;

    if ( $do_form ) {
        $sth = $self->journal->prepare( "SELECT pollqid, value FROM pollresult2 WHERE pollid=? AND userid=? AND journalid=?" );
        $sth->execute( $pollid, $remote->userid, $self->journalid );

        while ( my ( $qid, $value ) = $sth->fetchrow_array ) {
            $preval{$qid} = $value;
        }

        $ret .= "<form action='$LJ::SITEROOT/poll/?id=$pollid' method='post'>";
        $ret .= LJ::form_auth();
        $ret .= LJ::html_hidden('pollid', $pollid);
    }

    $ret .= "<b><a href='$LJ::SITEROOT/poll/?id=$pollid'>" . LJ::Lang::ml('poll.pollnum', { 'num' => $pollid }) . "</a></b> ";
    if ($self->name) {
        my $name = $self->name;
        LJ::Poll->clean_poll(\$name);
        $ret .= "<i>$name</i>";
    }
    $ret .= "<br />\n";
    $ret .= "<span style='font-family: monospace; font-weight: bold; font-size: 1.2em;'>" .
            BML::ml('poll.isclosed') . "</span><br />\n"
        if ($self->is_closed);

    my $whoview = $self->whoview;
    if ($whoview eq "none") {
        $whoview = $remote && $remote->id == $self->posterid ? "none_remote" : "none_others";
    }
    $ret .= LJ::Lang::ml('poll.security2', { 'whovote' => LJ::Lang::ml('poll.security.'.$self->whovote),
                                       'whoview' => LJ::Lang::ml('poll.security.'.$whoview) });

    if ( $mode eq 'enter' && $self->can_view( $remote ) ) {
        $ret .= "<br />\n";
        $ret .= "[ <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=results'>" . BML::ml( 'poll.seeresults' ) . "</a> ]  ";
    } elsif ( $mode eq 'results' ) {
        #include number of participants
        my $sth = $self->journal->prepare( "SELECT count(DISTINCT userid) FROM pollresult2 WHERE pollid=? AND journalid=?" );
        $sth->execute( $pollid, $self->journalid );
        my ( $participants ) = $sth->fetchrow_array;
        $ret .= LJ::Lang::ml('poll.participants', { 'total' => $participants });
        $ret .= "<br />\n";
        # change vote link
        $ret .= "[ <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=enter'>" . BML::ml( 'poll.changevote' ) . "</a> ]" if $self->can_vote( $remote ) && !$self->is_closed;
    } else {
        $ret .= "<br />\n";
    }

    my $results_table = "";
    ## go through all questions, adding to buffer to return
    foreach my $q (@qs) {
        my $qid = $q->pollqid;
        my $text = $q->text;
        LJ::Poll->clean_poll(\$text);
        $results_table .= "<p>$text</p><div style='margin: 10px 0 10px 40px'>";

        ### get statistics, for scale questions
        my ($valcount, $valmean, $valstddev, $valmedian);
        if ($q->type eq "scale") {
            # get stats
            $sth = $self->journal->prepare( "SELECT COUNT(*), AVG(value), STDDEV(value) FROM pollresult2 " .
                                            "WHERE pollid=? AND pollqid=? AND journalid=?" );
            $sth->execute( $pollid, $qid, $self->journalid );

            ( $valcount, $valmean, $valstddev ) = $sth->fetchrow_array;

            # find median:
            $valmedian = 0;
            if ($valcount == 1) {
                $valmedian = $valmean;
            } elsif ($valcount > 1) {
                my ($mid, $fetch);
                # fetch two mids and average if even count, else grab absolute middle
                $fetch = ($valcount % 2) ? 1 : 2;
                $mid = int(($valcount+1)/2);
                my $skip = $mid-1;

                $sth = $self->journal->prepare(
                    "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=? " .
                    "ORDER BY value+0 LIMIT $skip,$fetch" );
                $sth->execute( $pollid, $qid, $self->journalid );

                while (my ($v) = $sth->fetchrow_array) {
                    $valmedian += $v;
                }
                $valmedian /= $fetch;
            }
        }

        my $usersvoted = 0;
        my %itvotes;
        my $maxitvotes = 1;

        if ($mode eq "results") {
            ### to see individual's answers
            my $posterid = $self->posterid;
            $results_table .= qq {
                <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;qid=$qid&amp;mode=ans'
                     class='LJ_PollAnswerLink' lj_pollid='$pollid' lj_qid='$qid' lj_posterid='$posterid' lj_page='0' lj_pagesize="$pagesize"
                     id="LJ_PollAnswerLink_${pollid}_$qid">
                } . LJ::Lang::ml('poll.viewanswers') . "</a><br />" if $self->can_view;

            ### but, if this is a non-text item, and we're showing results, need to load the answers:
            if ($q->type ne "text") {
                $sth = $self->journal->prepare( "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?" );
                $sth->execute( $pollid, $qid, $self->journalid );
                while (my ($val) = $sth->fetchrow_array) {
                    $usersvoted++;
                    if ($q->type eq "check") {
                        foreach (split(/,/,$val)) {
                            $itvotes{$_}++;
                        }
                    } else {
                        $itvotes{$val}++;
                    }
                }

                foreach (values %itvotes) {
                    $maxitvotes = $_ if ($_ > $maxitvotes);
                }
            }
        }

        #### text questions are the easy case
        if ($q->type eq "text" && $do_form) {
            my ($size, $max) = split(m!/!, $q->opts);

            $results_table .= LJ::html_text({ 'size' => $size, 'maxlength' => $max,
                                    'name' => "pollq-$qid", 'value' => $preval{$qid} });
        } elsif ($q->type eq 'drop' && $do_form) {
            #### drop-down list
            my @optlist = ('', '');
            foreach my $it ($self->question($qid)->items) {
                my $itid  = $it->{pollitid};
                my $item  = $it->{item};
                LJ::Poll->clean_poll(\$item);
                push @optlist, ($itid, $item);
            }
            $results_table .= LJ::html_select({ 'name' => "pollq-$qid",
                                      'selected' => $preval{$qid} }, @optlist);
        } elsif ($q->type eq "scale" && $do_form) {
            #### scales (from 1-10) questions
            my ($from, $to, $by) = split(m!/!, $q->opts);
            $by ||= 1;
            my $count = int(($to-$from)/$by) + 1;
            my $do_radios = ($count <= 11);

            # few opts, display radios
            if ($do_radios) {

                $results_table .= "<table><tr valign='top' align='center'>";

                for (my $at=$from; $at<=$to; $at+=$by) {
                    $results_table .= "<td style='text-align: center;'>";
                    $results_table .= LJ::html_check({ 'type' => 'radio', 'name' => "pollq-$qid",
                                             'value' => $at, 'id' => "pollq-$pollid-$qid-$at",
                                             'selected' => (defined $preval{$qid} && $at == $preval{$qid}) });
                    $results_table .= "<br /><label for='pollq-$pollid-$qid-$at'>$at</label></td>";
                }

                $results_table .= "</tr></table>\n";

            # many opts, display select
            # but only if displaying form
            } else {

                my @optlist = ('', '');
                for (my $at=$from; $at<=$to; $at+=$by) {
                    push @optlist, ($at, $at);
                }
                $results_table .= LJ::html_select({ 'name' => "pollq-$qid", 'selected' => $preval{$qid} }, @optlist);
            }

        } else {
            #### now, questions with items
            my $do_table = 0;

            if ($q->type eq "scale") { # implies ! do_form
                my $stddev = sprintf("%.2f", $valstddev);
                my $mean = sprintf("%.2f", $valmean);
                $results_table .= LJ::Lang::ml('poll.scaleanswers', { 'mean' => $mean, 'median' => $valmedian, 'stddev' => $stddev });
                $results_table .= "<br />\n";
                $do_table = 1;
                $results_table .= "<table>";
            }

            my @items = $self->question($qid)->items;
            @items = map { [$_->{pollitid}, $_->{item}] } @items;

            # generate poll items dynamically if this is a scale
            if ($q->type eq 'scale') {
                my ($from, $to, $by) = split(m!/!, $q->opts);
                $by = 1 unless ($by > 0 and int($by) == $by);
                for (my $at=$from; $at<=$to; $at+=$by) {
                    push @items, [$at, $at]; # note: fake itemid, doesn't matter, but needed to be uniqeu
                }
            }

            foreach my $item (@items) {
                # note: itid can be fake
                my ($itid, $item) = @$item;

                LJ::Poll->clean_poll(\$item);

                # displaying a radio or checkbox
                if ($do_form) {
                    $results_table .= LJ::html_check({ 'type' => $q->type, 'name' => "pollq-$qid",
                                              'value' => $itid, 'id' => "pollq-$pollid-$qid-$itid",
                                              'selected' => ($preval{$qid} =~ /\b$itid\b/) });
                    $results_table .= " <label for='pollq-$pollid-$qid-$itid'>$item</label><br />";
                    next;
                }

                # displaying results
                my $count = $itvotes{$itid}+0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);

                if ($do_table) {
                    $results_table .= "<tr valign='middle'><td align='right'>$item</td>";
                    $results_table .= "<td><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' width='7' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='$width' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> ";
                    $results_table .= "<b>$count</b> ($percent%)</td></tr>";
                } else {
                    $results_table .= "<p>$item<br />";
                    $results_table .= "<span style='white-space: nowrap'><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='$width' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> ";
                    $results_table .= "<b>$count</b> ($percent%)</span></p>";
                }
            }

            if ($do_table) {
                $results_table .= "</table>";
            }

        }

        $results_table .= "</div>";
    }

    $ret .= $results_table;

    if ($do_form) {
        $ret .= LJ::html_submit(
                                'poll-submit',
                                LJ::Lang::ml('poll.submit'),
                                {class => 'LJ_PollSubmit'}) . "</form>\n";;
    }

    return $ret;
}


######## Security

sub can_vote {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    # owner can do anything
    return 1 if $remote && $remote->userid == $self->posterid;

    my $is_friend = $remote && $self->journal->trusts_or_has_member( $remote );

    return 0 if $self->whovote eq "trusted" && !$is_friend;

    if (LJ::is_banned($remote, $self->journalid) || LJ::is_banned($remote, $self->posterid)) {
        return 0;
    }

    if ($self->is_createdate_restricted) {
        my $propval = $self->prop("createdate");
        if ($propval =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
            my $propdate = DateTime->new( year => $1, month => $2, day => $3, hour => 23, minute => 59, second => 59, time_zone => 'America/Los_Angeles' );
            my $timecreate = DateTime->from_epoch( epoch => $remote->timecreate, time_zone => 'America/Los_Angeles' );

            # make sure that timecreate is before or equal to propdate
            return 0 if $propdate && $timecreate && DateTime->compare($timecreate, $propdate) == 1;
        }
    }

    my $can_vote_override = LJ::run_hook("can_vote_poll_override", $self);
    return 0 unless !defined $can_vote_override || $can_vote_override;

    return 1;
}

sub can_view {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    # owner can do anything
    return 1 if $remote && $remote->userid == $self->posterid;

    # not the owner, can't view results
    return 0 if $self->whoview eq 'none';

    # okay if everyone can view or if trusted can view and remote is a friend
    my $is_friend = $remote && $self->journal->trusts_or_has_member( $remote );
    return 1 if $self->whoview eq "all" || ($self->whoview eq "trusted" && $is_friend);

    return 0;
}


########## Questions
# returns list of LJ::Poll::Question objects associated with this poll
sub questions {
    my $self = shift;

    return @{$self->{questions}} if $self->{questions};

    croak "questions called on LJ::Poll with no pollid"
        unless $self->pollid;

    my @qs = ();

    my $sth = $self->journal->prepare( 'SELECT * FROM pollquestion2 WHERE pollid=? AND journalid=?' );
    $sth->execute( $self->pollid, $self->journalid );

    die $sth->errstr if $sth->err;

    while (my $row = $sth->fetchrow_hashref) {
        my $q = LJ::Poll::Question->new_from_row($row);
        push @qs, $q if $q;
    }

    @qs = sort { $a->sortorder <=> $b->sortorder } @qs;
    $self->{questions} = \@qs;

    # store poll data with loaded questions
    $self->_store_to_memcache;
    $LJ::REQ_CACHE_POLL{ $self->id } = $self;

    return @qs;
}


########## Props
# get the typemap for pollprop2
sub typemap {
    my $self = shift;

    return LJ::Typemap->new(
        table       => 'pollproplist2',
        classfield  => 'name',
        idfield     => 'propid',
    );
}

sub prop {
    my ($self, $propname) = @_;

    my $tm = $self->typemap;
    my $propid = $tm->class_to_typeid($propname);
    my $u = $self->journal;

    my $sth = $u->prepare("SELECT * FROM pollprop2 WHERE journalid = ? AND pollid = ? AND propid = ?");
    $sth->execute($u->id, $self->pollid, $propid);
    die $sth->errstr if $sth->err;

    if (my $row = $sth->fetchrow_hashref) {
        return $row->{propval};
    }

    return undef;
}

sub set_prop {
    my ($self, $propname, $propval) = @_;

    if (defined $propval) {
        my $tm = $self->typemap;
        my $propid = $tm->class_to_typeid($propname);
        my $u = $self->journal;

        $u->do("INSERT INTO pollprop2 (journalid, pollid, propid, propval) " .
               "VALUES (?,?,?,?)", undef, $u->id, $self->pollid, $propid, $propval);
        die $u->errstr if $u->err;
    }

    return 1;
}

########## Class methods

package LJ::Poll;
use strict;
use Carp qw (croak);

# takes a scalarref to entry text and expands (lj-)poll tags into the polls
sub expand_entry {
    my ($class, $entryref) = @_;

    my $expand = sub {
        my $pollid = (shift) + 0;

        return "[Error: no poll ID]" unless $pollid;

        my $poll = LJ::Poll->new($pollid);
        return "[Error: Invalid poll ID $pollid]" unless $poll && $poll->valid;

        return $poll->render;
    };

    $$entryref =~ s/<(?:lj-)?poll-(\d+)>/$expand->($1)/eg;
}

sub process_submission {
    my $class = shift;
    my $form = shift;
    my $error = shift;
    my $sth;

    my $remote = LJ::get_remote();

    unless ($remote) {
        $$error = LJ::error_noremote();
        return 0;
    }

    my $pollid = int($form->{'pollid'});
    my $poll = LJ::Poll->new($pollid);
    unless ($poll) {
        $$error = LJ::Lang::ml('poll.error.nopollid');
        return 0;
    }

    if ($poll->is_closed) {
        $$error = LJ::Lang::ml('poll.isclosed');
        return 0;
    }

    unless ($poll->can_vote($remote)) {
        $$error = LJ::Lang::ml('poll.error.cantvote');
        return 0;
    }

    # if unique prop is on, make sure that a particular email address can only vote once
    if ($poll->is_unique) {
        # make sure their email address is validated
        unless ($remote->is_validated) {
            $$error = LJ::Lang::ml('poll.error.notvalidated2', { aopts => "href='$LJ::SITEROOT/register'" });
            return 0;
        }

        # if this particular user has already voted, let them change their answer
        my $time = $poll->get_time_user_submitted($remote);
        unless ($time) {
            my $uids = $poll->journal->selectcol_arrayref( "SELECT userid FROM pollsubmission2 " .
                                                           "WHERE journalid = ? AND pollid = ?",
                                                           undef, $poll->journalid, $poll->pollid );

            if (@$uids) {
                my $remote_email = $remote->email_raw;
                my $us = LJ::load_userids(@$uids);

                foreach my $u (values %$us) {
                    next unless $u;

                    my $u_email = $u->email_raw;
                    if (lc $u_email eq lc $remote_email) {
                        $$error = LJ::Lang::ml('poll.error.alreadyvoted', { user => $u->ljuser_display });
                        return 0;
                    }
                }
            }
        }
    }

    ### load all the questions
    my @qs = $poll->questions;

    my $ct = 0; # how many questions did they answer?
    foreach my $q (@qs) {
        my $qid = $q->pollqid;
        my $val = $form->{"pollq-$qid"};
        if ($q->type eq "check") {
            ## multi-selected items are comma separated from htdocs/poll/index.bml
            $val = join(",", sort { $a <=> $b } split(/,/, $val));
        }
        if ($q->type eq "scale") {
            my ($from, $to, $by) = split(m!/!, $q->opts);
            if ($val < $from || $val > $to) {
                # bogus! cheating?
                $val = "";
            }
        }
        if ($val ne "") {
            $ct++;
            $poll->journal->do( "REPLACE INTO pollresult2 (journalid, pollid, pollqid, userid, value) VALUES (?, ?, ?, ?, ?)",
                                undef, $poll->journalid, $pollid, $qid, $remote->userid, $val );
        } else {
            $poll->journal->do( "DELETE FROM pollresult2 WHERE journalid=? AND pollid=? AND pollqid=? AND userid=?",
                                undef, $poll->journalid, $pollid, $qid, $remote->userid );
        }
    }

    ## finally, register the vote happened
    $poll->journal->do( "REPLACE INTO pollsubmission2 (journalid, pollid, userid, datesubmit) VALUES (?, ?, ?, NOW())",
                        undef, $poll->journalid, $pollid, $remote->userid );

    # if vote results are not cached, there is no need to modify cache
    #$poll->_remove_from_memcache;
    #delete $LJ::REQ_CACHE_POLL{ $poll->id };

    # don't notify if they blank-polled
    LJ::Event::PollVote->new($poll->poster, $remote, $poll)->fire
        if $ct;

    return 1;
}

sub dump_poll {
    my $self = shift;
    my $fh = shift || \*STDOUT;

    my @tables = qw(poll2 pollquestion2 pollitem2 pollsubmission2 pollresult2);
    my $db = $self->journal;
    my $id = $self->pollid;

    print $fh "<poll id='$id'>\n";
    foreach my $t (@tables) {
        my $sth = $db->prepare("SELECT * FROM $t WHERE pollid = ?");
        $sth->execute($id);
        while (my $data = $sth->fetchrow_hashref) {
            print $fh "<$t ";
            foreach my $k (sort keys %$data) {
                my $v = LJ::ehtml($data->{$k});
                print $fh "$k='$v' ";
            }
            print $fh "/>\n";
        }
    }
    print $fh "</poll>\n";
}

1;
