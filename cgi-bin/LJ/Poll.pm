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

package LJ::Poll;
use strict;
use Carp qw (croak);
use LJ::Entry;
use LJ::Poll::Question;
use LJ::Event::PollVote;

##
## Memcache routines
##
use base 'LJ::MemCacheable';
    *_memcache_id                   = \&id;
sub _memcache_key_prefix            { "poll" }
sub _memcache_stored_props          {
    # first element of props is a VERSION
    # next - allowed object properties
    return qw/ 2
               ditemid itemid
               pollid journalid posterid isanon whovote whoview name status questions
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

    my $isanon = $opts{isanon} or croak "No isanon";
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

    $u->do( "INSERT INTO poll2 (journalid, pollid, posterid, isanon, whovote, whoview, name, ditemid) " .
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", undef,
            $journalid, $pollid, $posterid, $isanon, $whovote, $whoview, $name, $ditemid );
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

        return $classref;
    }

    my $pollobj = LJ::Poll->new($pollid);

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

    my $err = sub {
        $$error = LJ::Lang::ml( @_ );
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
                $popts{'isanon'} = $opts->{'isanon'} || "no";
                $popts{'whovote'} = lc($opts->{'whovote'}) || "all";
                $popts{'whoview'} = lc($opts->{'whoview'}) || "all";

                # "friends" equals "trusted" for backwards compatibility
                $popts{whovote} = "trusted" if $popts{whovote} eq "friends";
                $popts{whoview} = "trusted" if $popts{whoview} eq "friends";

                my $journal = LJ::load_userid($iteminfo->{posterid});

                $popts{'isanon'} = "no" unless ($popts{'isanon'} eq "yes");

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

                return $err->('poll.error.missingljpoll')
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
                            return $err->('poll.error.badmaxlength');
                        }
                    }

                    $qopts{'opts'} = "$size/$max";
                }
                if ($qopts{'type'} eq "check") {
                    my $checkmin = 0;
                    my $checkmax = 255;

                    if (defined $opts->{'checkmin'}) {
                        $checkmin = int($opts->{'checkmin'});
                    }
                    if (defined $opts->{'checkmax'}) {
                        $checkmax = int($opts->{'checkmax'});
                    }
                    if ($checkmin < 0) {
                        return $err->('poll.error.checkmintoolow');
                    }
                    if ($checkmax < $checkmin) {
                        return $err->('poll.error.checkmaxtoolow');
                    }

                    $qopts{'opts'} = "$checkmin/$checkmax";

                }
                if ($qopts{'type'} eq "scale")
                {
                    my $from = 1;
                    my $to = 10;
                    my $by = 1;
                    my $lowlabel = "";
                    my $highlabel = "";

                    if (defined $opts->{'from'}) {
                        $from = int($opts->{'from'});
                    }
                    if (defined $opts->{'to'}) {
                        $to = int($opts->{'to'});
                    }
                    if (defined $opts->{'by'}) {
                        $by = int($opts->{'by'});
                    }
                    if ( defined $opts->{'lowlabel'} ) {
                        $lowlabel = LJ::strip_html( $opts->{'lowlabel'} );
                    }
                    if ( defined $opts->{'highlabel'} ) {
                        $highlabel = LJ::strip_html( $opts->{'highlabel'} );
                    }
                    if ($by < 1) {
                        return $err->('poll.error.scaleincrement');
                    }
                    if ($from >= $to) {
                        return $err->('poll.error.scalelessto');
                    }
                    my $scaleoptions = ( ( $to - $from ) / $by ) + 1;
                    if ( $scaleoptions > 21 ) {
                        return $err->( 'poll.error.scaletoobig1', { 'maxselections' => 21, 'selections' => $scaleoptions - 21 } );
                    }
                    $qopts{'opts'} = "$from/$to/$by/$lowlabel/$highlabel";
                }

                $qopts{'type'} = lc($opts->{'type'}) || "text";

                if ($qopts{'type'} ne "radio" &&
                    $qopts{'type'} ne "check" &&
                    $qopts{'type'} ne "drop" &&
                    $qopts{'type'} ne "scale" &&
                    $qopts{'type'} ne "text")
                {
                    return $err->('poll.error.unknownpqtype');
                }
            }

            ######## Begin poll item tag

            elsif ($tag eq "lj-pi" || $tag eq "poll-item")
            {
                if ($iopen) {
                    return $err->('poll.error.nested', { 'tag' => 'poll-item' });
                }
                if (! $qopen) {
                    return $err->('poll.error.missingljpq');
                }

                return $err->( "poll.error.toomanyopts2" )
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
                return $err->( 'poll.error.pitoolong2', { 'len' => $len, } )
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
        if ( defined $append && length $append )
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

    my ( $self, %opts ) = @_;

    my %createopts;

    # name is optional field
    $createopts{name} = $opts{name} || $self->{name};

    foreach my $f (qw(ditemid journalid posterid questions isanon whovote whoview)) {
        $createopts{$f} = $opts{$f} || $self->{$f} or croak "Field $f required for save_to_db";
    }

    # create can optionally take an object as the invocant
    return LJ::Poll::create($self, %createopts);
}

# loads poll from db
sub _load {
    my $self = $_[0];

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

    return undef unless $journalid;

    my $row = '';

    my $u = LJ::load_userid( $journalid )
        or die "Invalid journalid $journalid";

    $row = $u->selectrow_hashref( "SELECT pollid, journalid, ditemid, " .
                                  "posterid, isanon, whovote, whoview, name, status " .
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
    $self->{$_} = $row->{$_} foreach qw(pollid journalid posterid isanon whovote whoview name status questions);
    $self->{_loaded} = 1;
    return $self;
}

# Mark poll as closed
sub close_poll {
    my $self = $_[0];

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

# get the answer a user gave in a poll
sub get_pollanswers {
    my ( $self, $u ) = @_;

    my $pollid = $self->pollid;

    # try getting first from memcache
    my $memkey = [$u->userid, "pollresults:" . $u->userid . ":$pollid"];
    my $result = LJ::MemCache::get( $memkey );
    return %$result if $result;

    my $sth;
    my %answers;
    $sth = $self->journal->prepare( "SELECT pollqid, value FROM pollresult2 WHERE pollid=? AND userid=?" );
    $sth->execute( $pollid, $u->userid );

    while ( my ( $qid, $value ) = $sth->fetchrow_array ) {
        $answers{$qid} = $value;
    }

    LJ::MemCache::set( $memkey, \%answers );
    return %answers;
}

# Mark poll as open
sub open_poll {
    my $self = $_[0];

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
    my $self = $_[0];
    $self->_load;
    return $self->{ditemid};
}
sub name {
    my $self = $_[0];
    $self->_load;
    return $self->{name};
}
# returns "yes" if the poll is anonymous
sub isanon {
    my $self = $_[0];
    $self->_load;
    return $self->{isanon};
}
sub whovote {
    my $self = $_[0];
    $self->_load;
    return $self->{whovote};
}
sub whoview {
    my $self = $_[0];
    $self->_load;
    return $self->{whoview};
}
sub journalid {
    my $self = $_[0];
    $self->_load;
    return $self->{journalid};
}
sub posterid {
    my $self = $_[0];
    $self->_load;
    return $self->{posterid};
}
sub poster {
    my $self = $_[0];
    return LJ::load_userid($self->posterid);
}

*id = \&pollid;
sub pollid { $_[0]->{pollid} }

sub url {
    my $self = $_[0];
    return "$LJ::SITEROOT/poll/?id=" . $self->id;
}

sub entry {
    my $self = $_[0];
    return LJ::Entry->new($self->journal, ditemid => $self->ditemid);
}

sub journal {
    my $self = $_[0];
    return LJ::load_userid($self->journalid);
}

# return true if poll is closed
sub is_closed {
    my $self = $_[0];
    $self->_load;
    my $status = $self->{status} || '';
    return $status eq 'X' ? 1 : 0;
}

# return true if remote is also the owner
sub is_owner {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    return 1 if $remote && $remote->userid == $self->posterid;
    return 0;
}

# do we have a valid poll?
sub valid {
    my $self = $_[0];
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
    my $self = $_[0];

    my $ret = '';

    $ret .= "<form action='#'>\n";
    $ret .= "<b>" . LJ::Lang::ml('poll.pollnum', { 'num' => 'xxxx' }) . "</b>";

    my $name = $self->name;
    if ($name) {
        LJ::Poll->clean_poll(\$name);
        $ret .= " <i>$name</i>";
    }

    $ret .= "<br />\n";

    $ret .= LJ::Lang::ml( 'poll.isanonymous2' ) . "<br />\n"
        if ($self->isanon eq "yes");

    my $whoview = $self->whoview eq "none" ? "none_remote" : $self->whoview;
    $ret .= LJ::Lang::ml('poll.security2', { 'whovote' => LJ::Lang::ml('poll.security.whovote.'.$self->whovote), 'whoview' => LJ::Lang::ml('poll.security.whoview.'.$whoview), });

    # iterate through all questions
    foreach my $q ($self->questions) {
        $ret .= $q->preview_as_html;
    }

    $ret .= LJ::html_submit('', LJ::Lang::ml('poll.submit'), { 'disabled' => 1 }) . "\n";
    $ret .= "</form>";

    return $ret;
}

sub render_results {
    my ( $self, %opts ) = @_;
    return $self->render(mode => 'results', %opts);
}

sub render_enter {
    my ( $self, %opts ) = @_;
    return $self->render(mode => 'enter', %opts);
}

sub render_ans {
    my ( $self, %opts ) = @_;
    return $self->render(mode => 'ans', %opts);
}

# returns HTML of rendered poll
# opts:
#   mode => enter|results|ans
#   qid  => show a specific question
#   page => page
sub render {
    my ($self, %opts) = @_;

    my $remote = LJ::get_remote();
    my $ditemid = $self->ditemid;
    my $pollid = $self->pollid;

    my $mode     = delete $opts{mode};
    my $qid      = delete $opts{qid};
    my $page     = delete $opts{page};
    my $pagesize = delete $opts{pagesize};

    # clearing the answers renders just like 'enter' mode, we just need to clear all selections
    my $clearanswers;
    if ( $mode && $mode eq "clear" ) {
        $clearanswers = 1;
        $mode = "enter";
    }

    # Default pagesize.
    $pagesize = 2000 unless $pagesize;

    return "<b>[" . LJ::Lang::ml( 'poll.error.deletedowner' ) . "]</b>" unless $self->journal->clusterid;
    return "<b>[" . LJ::Lang::ml( 'poll.error.pollnotfound', { 'num' => $pollid } ) . "]</b>" unless $pollid;
    return "<b>[" . LJ::Lang::ml( 'poll.error.noentry' ) . "]</b>" unless $ditemid;

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
    if ( $mode eq "ans" ) {
        return "<b>[" . LJ::Lang::ml('poll.error.cantview') . "]</b>"
            unless $self->can_view;
        my $q = $self->question($qid)
            or return "<b>[" . LJ::Lang::ml('poll.error.questionnotfound') . "]</b>";

        my $text = $q->text;
        LJ::Poll->clean_poll(\$text);
        $ret .= $text;
        $ret .= '<div>' . $q->answers_as_html($self->journalid, $self->isanon, $page, $pagesize) . '</div>';

        my $pages    = $q->answers_pages($self->journalid, $pagesize);
        $ret .= '<div>' . $q->paging_bar_as_html($page, $pages, $pagesize, $self->journalid, $pollid, $qid, no_class => 1) . '</div>';
        return $ret;
    } elsif ( $mode eq "ans_extended" ) {
        # view detailed answers for every user
        return "<b>[" . LJ::Lang::ml( 'poll.error.cantview' ) . "]</b>"
            unless $self->can_view;

        my @userids;

        my $respondents = $self->journal->selectall_arrayref(
            "SELECT DISTINCT(userid) FROM pollresult2 WHERE pollid=? AND journalid=? ",
            undef, $pollid, $self->journalid );

        foreach my $userid ( @$respondents ) {
            $ret .= "<div class='useranswer'>" . $self->user_answers_as_html( $userid ) . "</div><br />";
        }

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

    $ret .= qq{<div id='poll-$pollid-container' class='poll-container'>};
    if ( $remote ) {
        %preval = $self->get_pollanswers( $remote );
    }

    if ( $do_form ) {
        my $url = LJ::create_url( "/poll/", host => $LJ::DOMAIN_WEB, viewing_style => 1, args => { id => $pollid } );
        $ret .= "<form class='LJ_PollForm' action='$url' method='post'>";
        $ret .= LJ::form_auth();
        $ret .= LJ::html_hidden('pollid', $pollid);
        $ret .= LJ::html_hidden('id', $pollid);    #for the ajax request
    }

    $ret .= "<div class='poll-title'><b><a href='$LJ::SITEROOT/poll/?id=$pollid'>" . LJ::Lang::ml('poll.pollnum', { 'num' => $pollid }) . "</a></b>";
    if ($self->name) {
        my $name = $self->name;
        LJ::Poll->clean_poll(\$name);
        $ret .= " <i>$name</i>\n";
    }
    $ret .= "</div><div class='poll-status'>";
    $ret .= "<span style='font-family: monospace; font-weight: bold; font-size: 1.2em;'>" .
            LJ::Lang::ml( 'poll.isclosed' ) . "</span><br />\n"
        if ($self->is_closed);

    $ret .= LJ::Lang::ml( 'poll.isanonymous2' ) . "<br />\n"
        if ($self->isanon eq "yes");

    my $whoview = $self->whoview;
    if ($whoview eq "none") {
        $whoview = $remote && $remote->id == $self->posterid ? "none_remote" : "none_others2";
    }
    $ret .= LJ::Lang::ml('poll.security2', { 'whovote' => LJ::Lang::ml('poll.security.whovote.'.$self->whovote),
                                       'whoview' => LJ::Lang::ml('poll.security.whoview.'.$whoview) });

    $ret .= LJ::Lang::ml('poll.participants', { 'total' => $self->num_participants });
    $ret .= "</div>";
    if ( $mode eq 'enter' && $self->can_view( $remote ) ) {
        $ret .= "<div class='poll-control'>[ <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=results' class='LJ_PollDisplayLink'
            id='LJ_PollDisplayLink_${pollid}' lj_pollid='$pollid' >" . LJ::Lang::ml( 'poll.seeresults' ) . "</a> ]  ";
        $ret .= "&nbsp&nbsp;[ <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=clear'
            class='LJ_PollClearLink' id='LJ_PollClearLink_${pollid}' lj_pollid='$pollid'>  " . BML::ml('poll.clear') ."</a> ]</div>";
    } elsif ( $mode eq 'results' ) {
        # change vote link
        my $pollvotetext = %preval ? "poll.changevote" : "poll.vote";
        $ret .= "<div class='poll-control'>[ <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=enter' class='LJ_PollChangeLink' id='LJ_PollChangeLink_${pollid}' lj_pollid='$pollid' >" 
            . LJ::Lang::ml( $pollvotetext ) . "</a> ]</div>" if $self->can_vote( $remote ) && !$self->is_closed;
        if ( $self->can_view && $self->isanon ne "yes" ) {
            $ret .= "<br /><div class='respondents'><a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=ans_extended' class='LJ_PollRespondentsLink' " .
            "id='LJ_PollRespondentsLink_${pollid}' " .
            "lj_pollid='$pollid' >" . LJ::Lang::ml( 'poll.viewrespondents' ) . "</a></div><br />"
        }
    }

    my $results_table = "";
    ## go through all questions, adding to buffer to return
    foreach my $q (@qs) {
        my $qid = $q->pollqid;
        my $text = $q->text;
        LJ::Poll->clean_poll(\$text);
        $results_table .= "<div class='poll-inquiry'><p>$text</p>";

        # shows how many options a user must/can choose if that restriction applies
        if ($q->type eq 'check' && $do_form) {
            my ($mincheck, $maxcheck) = split(m!/!, $q->opts);
            $mincheck ||= 0;
            $maxcheck ||= 255;

            if ($mincheck > 0 && $mincheck eq $maxcheck ) {
                $results_table .= "<i>". LJ::Lang::ml( "poll.checkexact2", { options => $mincheck } ). "</i><br />\n";
            }
            else {
                if ($mincheck > 0) {
                    $results_table .= "<i>". LJ::Lang::ml( "poll.checkmin2", { options => $mincheck } ). "</i><br />\n";
                }

                if ($maxcheck < 255) {
                    $results_table .= "<i>". LJ::Lang::ml( "poll.checkmax2", { options => $maxcheck } ). "</i><br />\n";
                }
            }
        }
        
        $results_table .= "<div style='margin: 10px 0 10px 40px' class='poll-response'>";

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

            ### if this is a text question and the viewing user answered it, show that answer
            if ( $q->type eq "text" && $preval{$qid} ) {
                LJ::Poll->clean_poll( \$preval{$qid} );
                $results_table .= "<br />" . BML::ml('poll.useranswer', { "answer" => $preval{$qid} } );
            } elsif ( $q->type ne "text" ) {
                ### but, if this is a non-text item, and we're showing results, need to load the answers:
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

        my $prevanswer;

        #### text questions are the easy case
        if ($q->type eq "text" && $do_form) {
            my ($size, $max) = split(m!/!, $q->opts);
            $prevanswer = $clearanswers ? "" : $preval{$qid};

            $results_table .= LJ::html_text({ 'size' => $size, 'maxlength' => $max, 'class'=>"poll-$pollid",
                                    'name' => "pollq-$qid", 'value' => $prevanswer });
        } elsif ($q->type eq 'drop' && $do_form) {
            #### drop-down list
            my @optlist = ('', '');
            foreach my $it ($self->question($qid)->items) {
                my $itid  = $it->{pollitid};
                my $item  = $it->{item};
                LJ::Poll->clean_poll(\$item);
                push @optlist, ($itid, $item);
            }
            $prevanswer = $clearanswers ? 0 : $preval{$qid};
            $results_table .= LJ::html_select({ 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                      'selected' => $prevanswer }, @optlist);
        } elsif ($q->type eq "scale" && $do_form) {
            #### scales (from 1-10) questions
            my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $q->opts );
            $by ||= 1;
            my $count = int(($to-$from)/$by) + 1;
            my $do_radios = ($count <= 11);

            # few opts, display radios
            if ($do_radios) {

                $results_table .= "<table summary=''><tr valign='top' align='center'>";

                # appends the lower end
                $results_table .= "<td style='padding-right: 5px;'><b>$lowlabel</b></td>" if defined $lowlabel;

                for (my $at=$from; $at<=$to; $at+=$by) {

                    my $selectedanswer = !$clearanswers && ( defined $preval{$qid} && $at == $preval{$qid});
                    $results_table .= "<td style='text-align: center;'>";
                    $results_table .= LJ::html_check( { 'type' => 'radio', 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                             'value' => $at, 'id' => "pollq-$pollid-$qid-$at",
                                             'selected' => $selectedanswer } );
                    $results_table .= "<br /><label for='pollq-$pollid-$qid-$at'>$at</label></td>";
                }

                # appends the higher end
                $results_table .= "<td style='padding-left: 5px;'><b>$highlabel</b></td>" if defined $highlabel;

                $results_table .= "</tr></table>\n";

            # many opts, display select
            # but only if displaying form
            } else {
                $prevanswer = $clearanswers ? "" : $preval{$qid};

                my @optlist = ('', '');
                push @optlist, ( $from, $from . " " . $lowlabel );

                my $at = 0;
                for ( $at=$from+$by; $at<=$to-$by; $at+=$by ) {
                    push @optlist, ($at, $at);
                }

                push @optlist, ( $at, $at . " " . $highlabel );

                $results_table .= LJ::html_select({ 'name' => "pollq-$qid", 'class'=>"poll-$pollid", 'selected' => $prevanswer }, @optlist);
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
                $results_table .= "<table summary=''>";
            }

            my @items = $self->question($qid)->items;
            @items = map { [$_->{pollitid}, $_->{item}] } @items;

            # generate poll items dynamically if this is a scale
            if ($q->type eq 'scale') {
                my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $q->opts );
                $by = 1 unless ($by > 0 and int($by) == $by);
                $highlabel //= "";
                $lowlabel //= "";

                push @items, [ $from, "$lowlabel $from" ];
                for (my $at=$from+$by; $at<=$to-$by; $at+=$by) {
                    push @items, [$at, $at]; # note: fake itemid, doesn't matter, but needed to be unique
                }
                push @items, [ $to, "$highlabel $to" ];
            }

            foreach my $item (@items) {
                # note: itid can be fake
                my ($itid, $item) = @$item;

                LJ::Poll->clean_poll(\$item);

                # displaying a radio or checkbox
                if ($do_form) {
                    my $qvalue = $preval{$qid} || '';
                    $prevanswer = $clearanswers ? 0 : $qvalue =~ /\b$itid\b/;
                    $results_table .= LJ::html_check({ 'type' => $q->type, 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                              'value' => $itid, 'id' => "pollq-$pollid-$qid-$itid",
                                              'selected' => $prevanswer });
                    $results_table .= " <label for='pollq-$pollid-$qid-$itid'>$item</label><br />";
                    next;
                }

                # displaying results
                my $count = ( defined $itid ) ? $itvotes{$itid} || 0 : 0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);

                # did the user viewing this poll choose this option? If so, mark it
                my $qvalue = $preval{$qid} || '';
                my $answered = ( $qvalue =~ /\b$itid\b/ ) ? "*" : "";

                if ($do_table) {
                    $results_table .= "<tr valign='middle'><td align='right'>$item</td><td>";
                    $results_table .= LJ::img( 'poll_left', '', { style => 'vertical-align:middle' } );
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle; height: 14px;' height='14' width='$width' alt='' />";
                    $results_table .= LJ::img( 'poll_right', '', { style => 'vertical-align:middle' } );
                    $results_table .= "<b>$count</b> ($percent%) $answered</td></tr>";
                } else {
                    $results_table .= "<p>$item<br /><span style='white-space: nowrap'>";
                    $results_table .= LJ::img( 'poll_left', '', { style => 'vertical-align:middle' } );
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle; height: 14px;' height='14' width='$width' alt='' />";
                    $results_table .= LJ::img( 'poll_right', '', { style => 'vertical-align:middle' } );
                    $results_table .= "<b>$count</b> ($percent%) $answered</span></p>";
                }
            }

            if ($do_table) {
                $results_table .= "</table>";
            }

        }

        $results_table .= "</div></div>";
    }

    $ret .= $results_table;

    if ($do_form) {
        $ret .= LJ::html_submit(
                                'poll-submit',
                                LJ::Lang::ml('poll.submit'),
                                {class => 'LJ_PollSubmit'}) . "</form>";
    }
    $ret .= "</div>";

    return $ret;
}


######## Security

sub can_vote {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    # owner can do anything
    return 1 if $remote && $remote->userid == $self->posterid;

    my $trusted = $remote && $self->journal->trusts_or_has_member( $remote );

    return 0 if $self->whovote eq "trusted" && !$trusted;

    return 0 if $self->journal->has_banned( $remote );

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
    my $has_access = $remote && $self->journal->trusts_or_has_member( $remote );
    return 1 if $self->whoview eq "all" || ( $self->whoview eq "trusted" && $has_access );

    return 0;
}

sub num_participants {
    my ( $self ) = @_;

    my $sth = $self->journal->prepare( "SELECT count(DISTINCT userid) FROM pollresult2 WHERE pollid=? AND journalid=?" );
    $sth->execute( $self->pollid, $self->journalid );
    my ( $participants ) = $sth->fetchrow_array;

    return $participants;
}

########## Questions
# returns list of LJ::Poll::Question objects associated with this poll
sub questions {
    my $self = $_[0];

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

# returns a string with the html of how a user answered all questions of this poll
sub user_answers_as_html {
    my ( $self, $userid ) = @_;

    my $ret;
    my $u = LJ::load_userid( $userid );

    $ret = "<span class='useranswer' id='useranswer_" . $u->userid . "'>"  . LJ::Lang::ml( 'poll.respondents.user', { user => $u->ljuser_display } ) . "\n";

    my @qs = $self->questions;

    foreach my $q ( @qs ) {
        $ret .= $q->user_answer_as_html( $userid );
    }
    $ret .= "</span>";

    return $ret;
 }

# returns a string with the html of the people who responded to this poll
sub respondents_as_html {
    my ( $self ) = @_;
    my $pollid = $self->pollid;

    my @res = @{ $self->journal->selectall_arrayref(
        "SELECT userid FROM pollsubmission2 WHERE " .
        "pollid=? AND journalid=? ORDER BY datesubmit ",
        undef, $pollid, $self->journalid ) };
    my @respondents = map { $_->[0] } @res;

    my $users = LJ::load_userids( @respondents );

    my $ret;
    foreach my $userid ( @respondents ) {
        my $u = $users->{$userid};
        next unless $u;

        $ret .= "<div> <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;mode=ans_extended'" .
            "class='LJ_PollUserAnswerLink'" .
            "lj_pollid='$pollid' lj_userid='$userid'" .
            "id='LJ_PollUserAnswerLink_${pollid}_$userid'>[+]</a>" .
            "<span class='polluser' id='LJ_PollUserAnswerRes_${pollid}_$userid'>" . $u->ljuser_display . "</span></div>\n";
    }
    return $ret;
}

########## Class methods

package LJ::Poll;
use strict;
use Carp qw (croak);

# takes a scalarref to entry text and expands (lj-)poll tags into the polls
sub expand_entry {
    my ( $class, $entryref, %opts ) = @_;

    my $expand = sub {
        my $pollid = $_[0] + 0;

        return "[Error: no poll ID]" unless $pollid;

        my $poll = LJ::Poll->new($pollid);
        return "[Error: Invalid poll ID $pollid]" unless $poll && $poll->valid;

        if ( $opts{sandbox} ) {
            # hacky. Basically, when we render an entry with a poll in a form element
            # the nested form from the poll wreaks havoc, breaking the first poll form and (maybe) the outer form
            # This deliberately adds a new form element, to make sure that our poll form always works.
            return "<form style='display: none'></form>" . $poll->render;
        } else {
            return $poll->render;
        }
    };

    $$entryref =~ s/<(?:lj-)?poll-(\d+)>/$expand->($1)/eg if $$entryref;
}

sub process_submission {
    my ( $class, $form, $error ) = @_;
    my $sth;

    my $error_code = 1;

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

    # delete user answer MemCache entry
    my $memkey = [$remote->userid, "pollresults:" . $remote->userid . ":$pollid"];
    LJ::MemCache::delete( $memkey );

    ### load any previous answers
    my $qvals = $poll->journal->selectall_arrayref(
                "SELECT pollqid, value FROM pollresult2 " .
                "WHERE journalid=? AND pollid=? AND userid=?",
                undef, $poll->journalid, $pollid, $remote->userid );
    die $poll->journal->errstr if $poll->journal->err;
    my %qvals = $qvals ? map { $_->[0], $_->[1] } @$qvals : ();

    ### load all the questions
    my @qs = $poll->questions;

    my $ct = 0; # how many questions did they answer?
    my ( %vote_delete, %vote_replace );

    foreach my $q (@qs) {
        my $qid = $q->pollqid;
        my $val = $form->{"pollq-$qid"};
        if ($q->type eq "check") {
            ## multi-selected items are comma separated from htdocs/poll/index.bml
            $val = join(",", sort { $a <=> $b } split(/,/, $val));
            if (length($val) > 0) { # if the user answered to this question
                my @num_opts = split( /,/, $val );
                my $num_opts = scalar @num_opts;  # returns the number of options they answered

                my ($checkmin, $checkmax) = split(m!/!, $q->opts);
                $checkmin ||= 0;
                $checkmax ||= 255;

                if($num_opts < $checkmin) {
                    $$error = LJ::Lang::ml( 'poll.error.checkfewoptions3', {'question' => $qid, 'options' => $checkmin} );
                    $error_code = 2;
                    $val = "";
                }
                if($num_opts > $checkmax) {
                    $$error = LJ::Lang::ml( 'poll.error.checktoomuchoptions3', {'question' => $qid, 'options' => $checkmax} );
                    $error_code = 2;
                    $val = "";
                }
            }
        }
        if ($q->type eq "scale") {
            my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $q->opts );
            if ($val < $from || $val > $to) {
                # bogus! cheating?
                $val = "";
            }
        }

        # if $val is still undef here, set it to empty string
        $val = "" unless defined $val;

        # see if the vote changed values
        my $changed = 1;

        if ( $val ne "" ) {
            my $oldval = $qvals{$qid};
            if ( defined $oldval && $oldval eq $val ) {
                $changed = 0;
            }
        }

        if ( $val eq "" ) {
            $vote_delete{$qid} = 1;
        } elsif ( $changed ) {
            $ct++;
            $vote_replace{$qid} = $val;
        }
    }
    ## do one transaction for all deletions
    my $delete_qs = join ',', map { '?' } keys %vote_delete;
    $poll->journal->do( "DELETE FROM pollresult2 WHERE journalid=? AND pollid=? " .
                        "AND userid=? AND pollqid IN ($delete_qs)",
                        undef, $poll->journalid, $pollid, $remote->userid,
                               keys %vote_delete );

    ## do one transaction for all replacements
    my ( @replace_qs, @replace_args );
    foreach my $qid ( keys %vote_replace ) {
        push @replace_qs, '(?, ?, ?, ?, ?)';
        push @replace_args, $poll->journalid, $pollid, $qid, $remote->userid, $vote_replace{$qid};
    }
    my $replace_qs = join ', ', @replace_qs;
    $poll->journal->do( "REPLACE INTO pollresult2 " .
                        "(journalid, pollid, pollqid, userid, value) " .
                        "VALUES $replace_qs", undef, @replace_args );

    ## finally, register the vote happened
    $poll->journal->do( "REPLACE INTO pollsubmission2 (journalid, pollid, userid, datesubmit) VALUES (?, ?, ?, NOW())",
                        undef, $poll->journalid, $pollid, $remote->userid );

    # if vote results are not cached, there is no need to modify cache
    #$poll->_remove_from_memcache;
    #delete $LJ::REQ_CACHE_POLL{ $poll->id };

    # don't notify if they blank-polled
    LJ::Event::PollVote->new($poll->poster, $remote, $poll)->fire
        if $ct;

    return $error_code;
}

sub dump_poll {
    my ( $self, $fh ) = @_;
    $fh ||= \*STDOUT;

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
