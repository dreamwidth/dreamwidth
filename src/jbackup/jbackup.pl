#!/usr/bin/perl

# jbackup.pl
# Journal Backup Utility
# This tool downloads a copy of your journal (all entries and all comments) in a nice-to-the-server
# fashion and lets you export them in an easy to access XML format or an easy to read HTML format.

### DATABASE DOCUMENTATION ########################################################################
# There are a bunch of keys in the database.  They're (hopefully) named in an easy to follow and
# understand manner, but I'm documenting them here for quick reference.
#
# event:lastsync
#       The most recent item returned by the syncitems mode.  This is just passed back to the
#       server to instruct it when to pick up again and start sending us more data.
#
# event:ids
#       Comma separated list of all valid jitemids.  This is maintained so we don't have to
#       iterate through every key in the database to find event jitemids.
#
# event:lastgrab
#       The real date of the most recently downloaded event.  This is set when we actually
#       get an event from the getevents mode.  This date will match up with one of the dates
#       returned by syncitems.
#
# event:realtime:<jitemid>      Time the server got this post (YYYY-MM-DD HH:MM:SS format).
# event:subject:<jitemid>       Subject of the event, may not be present.
# event:anum:<jitemid>          Arbitrary number for this event.
# event:event:<jitemid>         Text of the event.
# event:eventtime:<jitemid>     Time the user specified (YYYY-MM-DD HH:MM:SS format).
# event:security:<jitemid>      Present if not public.  Values are 'private', 'usemask'.
# event:allowmask:<jitemid>     Present for security == usemask.  Allowmask == 1 means Friends Only.
# event:poster:<jitemid>        If present, may be any username.  Else, it's the user's journal.
#       These all contain various bits of data about the event.
#
# event:proplist:<jitemid>
#       List of all properties that are defined for this event.  Comma separated.
#
# event:prop:<jitemid>:<property>
#       Stores the values of the properties.  <property> is taken from the proplist.
#
# usermap:<userid>
#       For <userid>, contains the username.
#
# usermap:userids
#       All the valid userids.  Same logic as event:ids.
#
# comment:ids
#       Should be familiar.  All the valid jtalkids.  Comma separated.
#
# comment:lastid
#       The most recently downloaded jtalkid as retrieved by the comment_body mode.
#
# comment:state:<jtalkid>
#       Formatted string: <state>:<posterid>:<jitemid>:<parentid>
#       This contains state information about a comment.  Most of this information is subject to
#       change, and hence it's separate.
#
# comment:subject:<jtalkid>     Subject of the comment.  May not be present.
# comment:body:<jtalkid>        Text of the comment.  May not be present for deleted comments.
# comment:date:<jtalkid>        Date of the comment.  In W3C date format.
#       As with events.  Contains various bits of information about the comments.
###################################################################################################

## the program ##
use strict;
use Getopt::Long;
use GDBM_File;
use Data::Dumper;
use XMLRPC::Lite;
use XML::Parser;
use Digest::MD5 qw(md5_hex);
use Term::ReadKey;

# get options
my %opts;
exit 1 unless
    GetOptions("dump=s" => \$opts{dumptype},
               "sync" => \$opts{sync},
               "user=s" => \$opts{user},
               "help" => \$opts{help},
               "protocol=s" => \$opts{protocol},
               "server=s" => \$opts{server},
               "port=i" => \$opts{port},
               "quiet" => \$opts{quiet},
               "publiconly" => \$opts{public},
               "journal=s" => \$opts{usejournal},
               "clean" => \$opts{clean},
               "file=s" => \$opts{file},
               "password=s" => \$opts{password},
               "md5pass=s" => \$opts{md5password},
               "alter-security=s" => \$opts{alter_security},
               "confirm-alter" => \$opts{confirm_alter},
               "no-comments" => \$opts{no_comments},
               "backfill" => \$opts{backfill},);

# hit up .jbackup for other options
if (-e "$ENV{HOME}/.jbackup") {
    # read in the options
    open FILE, "<$ENV{HOME}/.jbackup";
    foreach (<FILE>) {
        $opts{$1} = $2
            if /^(.+)=(.+)[\r\n]*$/;
    }
    close FILE;
}

# setup some nice, sane defaults
$opts{protocol} ||= 'https';
$opts{server} ||= 'www.dreamwidth.org';
$opts{baseurl} = $opts{protocol} . '://' . $opts{server};
$opts{port} += 0;
$opts{baseurl} .= ":$opts{port}"
    unless ( $opts{port} == 0 ||
             $opts{protocol} eq 'http' && $opts{port} == 80 ||
             $opts{protocol} eq 'https' && $opts{port} == 443 );
$opts{verbose} = $opts{quiet} ? 0 : 1;

# set some constants that should never need to change.
my $COMMENTS_FETCH_META = 10000;   # up to 10000 comments, the maximum for comment_meta
# comment_body batch size: the server max is 1000, but heavy windows (big threads) can blow
# past DW's gateway timeout and 504. Lower this (e.g. comment_body_fetch=250 in ~/.jbackup)
# to make each request lighter and far less likely to time out, at the cost of more requests.
my $COMMENTS_FETCH_BODY = defined $opts{comment_body_fetch} ? $opts{comment_body_fetch}+0 : 1000;
$COMMENTS_FETCH_BODY = 1000 if $COMMENTS_FETCH_BODY > 1000;   # server ceiling
$COMMENTS_FETCH_BODY = 1    if $COMMENTS_FETCH_BODY < 1;

# --- resilience knobs (override in ~/.jbackup, e.g. a line "xmlrpc_delay=3") ---
my $XMLRPC_DELAY      = defined $opts{xmlrpc_delay} ? $opts{xmlrpc_delay}+0 : 2;   # sec before each XML-RPC call
my $FETCH_DELAY       = defined $opts{fetch_delay}  ? $opts{fetch_delay}+0  : 1;   # sec before each comment HTTP fetch
my $HTTP_TIMEOUT      = defined $opts{http_timeout} ? $opts{http_timeout}+0 : 120; # sec per request before it's an error (not a hang)
my $MAX_BACKOFF_TRIES = defined $opts{max_tries}    ? $opts{max_tries}+0    : 6;   # retries w/ exponential backoff before giving up/skipping
my $META_MAX_TRIES    = defined $opts{meta_max_tries} ? $opts{meta_max_tries}+0 : 9; # meta windows get more patience (a meta skip is high-stakes)
my $MAX_BACKOFF_WAIT  = defined $opts{max_backoff}   ? $opts{max_backoff}+0   : 300; # cap on a single backoff sleep (sec)

# adaptive pacing: extra delay carried across comment windows, ramps up on errors, decays
# only after a clean streak -- so a struggling server gets sustained relief, not fresh poking.
my $ADAPT_STEP        = defined $opts{adapt_step}  ? $opts{adapt_step}+0  : 5;   # first bump (sec) on the first error
my $ADAPT_MAX         = defined $opts{adapt_max}   ? $opts{adapt_max}+0   : 60;  # ceiling for the carried-over delay
my $ADAPT_DECAY_AFTER = defined $opts{adapt_decay} ? $opts{adapt_decay}+0 : 10;  # clean windows needed before easing off
my $ADAPT_DELAY       = 0;   # current carried-over delay (state)
my $ADAPT_OK          = 0;   # consecutive clean windows (state)

# now figure out what we're doing
if ($opts{help} || !($opts{sync} || $opts{dumptype} || $opts{alter_security})) {
    print <<HELP;
jbackup.pl -- journal database generator and formatter

  Informative/behavior options:
    --help          Prints this help you see.
    --quiet         Suppress progress printing to standard error.

  Authentication options:
    --user=X        Specify the user to use for authentication.
    --password=X    Specify the password to use for the user.
                    NOTE: For Dreamwidth, this must be an API key.
    --md5pass=X     Alternately, provide the MD5 digest of the password.
    --journal=X     Specify an alternate journal to use.
                    NOTE: You must be maintainer of the journal.
    --protocol=X    Use a different protocol. (Default: https)
    --server=X      Use a different server.   (Default: www.dreamwidth.org)
    --port=X        Use a non-default port.   (Default: 80 or 443)

  Data update options:
    --sync          Update or create the database.
    --no-comments   Do not update comment information.  (Much faster.)

  Journal modification options:
    --alter-security=X  Change the security setting of your public entries.
    --confirm-alter     Confirm that you wish to actually edit your entries.

  Data output options:
    --dump=X        Dump data in the specified format: html, xml, raw.
    --publiconly    When dumping, only spit out public entries.
    --file=X        Dump to specified file instead of the screen.

Usage examples:

   ./jbackup.pl --sync
Create or update the local copy of your journal.  You can put this command
in a cron or just run it whenever you want.

   ./jbackup.pl --alter-security=friends
If you wish to alter all of your public entries to be friends only, you can
use this command to see exactly what will be done.  If you are sure that
the program is going to take the actions you want, add the 'confirm-alter'
command line flag.  You can also specify private or the name of some friend
group that you have defined.

The script also checks for the presence of a ~/.jbackup file, and you can
put options into it like this:

user=test
password=test
publiconly=1
HELP
    exit 1;
}

# prompt for user/pass if we don't have them
unless ($opts{user}) {
    print "Username: ";
    my $user = <>;
    chomp $user;
    $opts{user} = $user;
    die "Need a username" unless $opts{user};
}
if (!$opts{password} && !$opts{md5password} && $opts{sync}) {
    print "Password: ";
    ReadMode('noecho');
    my $pass = ReadLine(0);
    ReadMode('normal');
    chomp $pass;
    $opts{password} = $pass;
    print "\n";
    die "Need a password" unless $opts{password};
}
$opts{linkuser} = $opts{usejournal} || $opts{user};

# setup some global variables
my %bak;
my $filename = "$ENV{HOME}/$opts{user}." . ($opts{usejournal} ? "$opts{usejournal}." : '') . "jbak";

# setup database
my $tied = do_tie();

# do something
do_alter_security($opts{alter_security}, $opts{confirm_alter}) if $opts{alter_security};
do_sync() if $opts{sync} || $opts{backfill};
do_dump($opts{dumptype}) if $opts{dumptype};

# clean up before we exit
do_untie();

#### helper functions below here ############################################

sub d {
    # just dump a message to stderr if we're in verbose mode
    return unless $opts{verbose};
    print STDERR shift(@_) . "\n";
}

# --- skipped-window accounting -------------------------------------------------
# Skips are recorded durably in the database under a single key, "skipped:windows",
# as a comma list of "mode:startid:numitems" so a gap survives the run ending, is
# reported at the end, and can be recovered with --backfill. numitems gives the exact
# id range and an upper bound on how many comments the window could hold.
sub parse_skips {
    my %w;
    foreach my $e (split /,/, ($bak{"skipped:windows"} || '')) {
        my ($mode, $startid, $numitems) = split /:/, $e;
        next unless defined $numitems;
        $w{"$mode:$startid"} = $numitems;
    }
    return %w;
}

sub record_skip {
    my ($mode, $startid, $numitems) = @_;
    my %w = parse_skips();
    $w{"$mode:$startid"} = $numitems;
    $bak{"skipped:windows"} = join(',', map { "$_:$w{$_}" } sort keys %w);
}

sub remove_skip {
    my ($mode, $startid) = @_;
    my %w = parse_skips();
    delete $w{"$mode:$startid"};
    $bak{"skipped:windows"} = join(',', map { "$_:$w{$_}" } sort keys %w);
}

sub report_skipped {
    my %w = parse_skips();
    return unless %w;
    my $total = 0; $total += $_ for values %w;
    print STDERR "\n*** WARNING: " . (scalar keys %w) . " window(s) skipped; up to $total comment(s) missing:\n";
    foreach my $k (sort keys %w) {
        my ($mode, $startid) = split /:/, $k;
        print STDERR "      $mode startid=$startid numitems=$w{$k}\n";
    }
    print STDERR "    Re-run with --backfill (set a lower comment_body_fetch first) to recover them.\n\n";
}

sub do_sync {
### ENTRY DOWNLOADING ###
  unless ($opts{backfill}) {   # --backfill skips the entry sweep; it only re-pulls comment gaps
    # see if we have any sync data saved
    my %sync;
    my $lastsync = $bak{"event:lastsync"};
    my $synccount = 0;

    # get sync data
    my @usejournal = $opts{usejournal} ? ('usejournal', $opts{usejournal}) : ();
    while (1) {
        # contact server for list of items
        d("do_sync: calling syncitems with lastsync = " . ($lastsync || 'none yet'));
        my $hash = call_xmlrpc('syncitems', { lastsync => $lastsync, @usejournal });

        # push this info, set lastsync
        foreach my $item (@{$hash->{syncitems} || []}) {
            $lastsync = $item->{'time'}
                if $item->{'time'} gt $lastsync;
            next unless $item->{item} =~ /L-(\d+)/;
            $synccount++;
            $sync{$1} = [ $item->{action}, $item->{'time'} ];
            $bak{"event:realtime:$1"} = $item->{'time'};
        }
        $bak{'event:lastsync'} = $lastsync;
        do_flush();

        # last if necessary
        d("do_sync: got $hash->{count} of $hash->{total} syncitems.");
        last if $hash->{count} == $hash->{total};
    }
    print "$synccount total new and/or updated entries.\n";
    $bak{'event:lastsync'} = $lastsync;

    # helper sub
    my $realtime = sub {
        my $id = shift;
        return $sync{$id}->[1] if @{$sync{$id} || []};
        return $bak{"event:realtime:$id"};
    };

    # get list of ids so far
    my %eventids = ( map { $_, 1 } split(',', $bak{"event:ids"}) );

    # setup our download hash
    my $lastgrab = $bak{"event:lastgrab"};
    my %data;

    while (1) {
        # shortcut to maybe not have to hit getvents
        last if $lastgrab eq $lastsync;

        # get newest item we have cached
        my $count = 0;
        d("do_sync: calling getevents with lastgrab = " . ($lastgrab || 'none yet'));
        my $hash = call_xmlrpc('getevents', { selecttype => 'syncitems',
                                              lastsync => $lastgrab,
                                              ver => 1,
                                              lineendings => 'unix',
                                              @usejournal, });

        # parse incoming data one event at a time
        foreach my $evt (@{$hash->{events} || []}) {
            # got an event
            $count++;
            $eventids{$evt->{itemid}} = 1;
            $evt->{realtime} = $realtime->($evt->{itemid});
            $lastgrab = $evt->{realtime}
                if $evt->{realtime} gt $lastgrab;
            save_event($evt);
        }
        $bak{"event:lastgrab"} = $lastgrab;
        $bak{"event:ids"} = join ',', keys %eventids;
        do_flush();

        # do we all be done here?
        d("do_sync: got $count items.");
        last unless $count && $lastgrab;
    }

  }  # end entry sweep (skipped in --backfill mode)

### COMMENT DOWNLOADING ###
    # see if we shouldn't be doing this
    return if $opts{no_comments};

    # first we hit up the server to get a session
    my $hash = call_xmlrpc('sessiongenerate', { expiration => 'short' });
    my $ljsession = $hash->{ljsession};

    # downloaded meta data information
    my %meta;
    my @userids;

    # setup our parsing function
    my $maxid = 0;
    my $server_max_id = 0;
    my $server_next_id = 1;
    my $lasttag = '';
    my $meta_handler = sub {
        # this sub actually processes incoming meta information
        $lasttag = $_[1];
        shift; shift;      # remove the Expat object and tag name
        my %temp = ( @_ ); # take the rest into our humble hash
        if ($lasttag eq 'comment') {
            # get some data on a comment
            $meta{$temp{id}} = {
                id => $temp{id},
                posterid => $temp{posterid}+0,
                state => $temp{state} || 'A',
            };
            update_comment($meta{$temp{id}});
        } elsif ($lasttag eq 'usermap') {
            # put this data in our usermap
            $bak{"usermap:$temp{id}"} = $temp{user};
            push @userids, $temp{id};
        }
    };
    my $meta_closer = sub {
        # we hit a closing tag so we're not in a tag anymore
        $lasttag = '';
    };
    my $meta_content = sub {
        # if we're in a maxid tag, we want to save that value so we know how much further
        # we have to go in downloading meta info
        return unless ($lasttag eq 'maxid') || ($lasttag eq 'nextid');
        $server_max_id = $_[1] + 0 if ($lasttag eq 'maxid');
        $server_next_id = $_[1] + 0 if ($lasttag eq 'nextid');
    };

    # hit up the server for metadata. A skipped meta window is NOT safe to continue past: it
    # would leave %meta incomplete and a wrong $server_max_id, corrupting/truncating the body
    # sweep. So we stop the comment phase cleanly and let a re-run rebuild the (in-memory,
    # uncheckpointed, cheap) meta pass from scratch.
    while (defined $server_next_id  && $server_next_id =~ /^\d+$/) {
        my $content = do_authed_fetch('comment_meta', $server_next_id, $COMMENTS_FETCH_META, $ljsession);
        die "Some sort of error fetching metadata from server" unless $content;

        if ($content eq '__SKIP__') {
            print STDERR "\n*** A comment-metadata window failed after $META_MAX_TRIES retries.\n";
            print STDERR "    Stopping the comment phase WITHOUT running the body sweep, because an\n";
            print STDERR "    incomplete metadata pass would corrupt and truncate saved comments.\n";
            print STDERR "    Your entries and any previously-saved comments are intact. Wait for the\n";
            print STDERR "    server to recover, then re-run --sync -- the metadata pass rebuilds from\n";
            print STDERR "    scratch (it is not checkpointed), so nothing here needs --backfill.\n\n";
            report_skipped();
            return;
        }

        $server_next_id = undef;

        # now we want to XML parse this
        my $parser = new XML::Parser(Handlers => { Start => $meta_handler, Char => $meta_content, End => $meta_closer });
        $parser->parse($content);
    }
    # the metadata pass completed in full, so any comment_meta skip marker from a prior aborted
    # run is now stale -- clear it.
    {
        my %w = parse_skips();
        foreach my $k (grep { /^comment_meta:/ } keys %w) {
            my (undef, $sid) = split /:/, $k;
            remove_skip('comment_meta', $sid);
        }
    }
    $bak{"comment:ids"} = join ',', keys %meta;
    $bak{"usermap:userids"} = join ',', @userids;

    # setup our handlers for body XML info
    my $lastid = $bak{"comment:lastid"}+0;
    my $curid = 0;
    my @tags;
    my @window_ids;   # ids whose bodies arrived in the current window (for incremental save)
    my $body_handler = sub {
        # this sub actually processes incoming body information
        $lasttag = $_[1];
        push @tags, $lasttag;
        shift; shift;      # remove the Expat object and tag name
        my %temp = ( @_ ); # take the rest into our humble hash
        if ($lasttag eq 'comment') {
            # get some data on a comment
            $curid = $temp{id};
            $meta{$curid}{parentid} = $temp{parentid}+0;
            $meta{$curid}{jitemid} = $temp{jitemid}+0;
            push @window_ids, $curid;   # for incremental per-window save
            # line below commented out because we shouldn't be trying to be clever like this ;p
            # $lastid = $curid if $curid > $lastid;
        }
    };
    my $body_closer = sub {
        # we hit a closing tag so we're not in a tag anymore
        my $tag = pop @tags;
        $lasttag = $tags[0];
    };
    my $body_content = sub {
        # this grabs data inside of comments: body, subject, date
        return unless $curid;
        return unless $lasttag =~ /(?:body|subject|date)/;
        $meta{$curid}{$lasttag} .= $_[1];
        # have to .= it, because the parser will split on punctuation such as an apostrophe
        # that may or may not be in the data stream, and we won't know until we've already
        # gotten some data
    };

    # at this point we have a fully regenerated metadata cache and we want to grab comment bodies
    if ($opts{backfill}) {
        # --backfill: re-pull only the windows recorded as skipped (reusing the meta rebuilt
        # above), splitting each into sub-windows of the current comment_body_fetch size -- so a
        # window that 504'd at 1000 can come through at e.g. 250. Recovered comments are saved;
        # any sub-window that still fails re-records a finer skip marker for a later attempt.
        my %w = parse_skips();
        my @windows = sort grep { /^comment_body:/ } keys %w;
        unless (@windows) {
            print "No skipped comment_body windows to backfill.\n";
            report_skipped();
            return;
        }
        print scalar(@windows) . " skipped window(s) to backfill (sub-batch = $COMMENTS_FETCH_BODY).\n";
        my $recovered = 0;
        foreach my $k (@windows) {
            my (undef, $startid) = split /:/, $k;
            my $numitems = $w{$k};
            remove_skip('comment_body', $startid);   # drop the wide marker; sub-failures re-mark finer
            $tied->sync();
            for (my $s = $startid; $s < $startid + $numitems; $s += $COMMENTS_FETCH_BODY) {
                my $n = ($s + $COMMENTS_FETCH_BODY > $startid + $numitems) ? ($startid + $numitems - $s) : $COMMENTS_FETCH_BODY;
                @window_ids = ();
                my $content = do_authed_fetch('comment_body', $s, $n, $ljsession);
                next if !$content || $content eq '__SKIP__';   # finer marker auto-recorded on re-skip
                my $parser = new XML::Parser(Handlers => { Start => $body_handler, Char => $body_content, End => $body_closer });
                $parser->parse($content);
                foreach my $id (@window_ids) {
                    next unless $meta{$id}{jitemid};
                    $recovered++;
                    save_comment($meta{$id});
                }
                $tied->sync();
            }
            print "backfill: processed window startid=$startid numitems=$numitems.\n";
        }
        print "Backfill done: recovered $recovered comment bodies.\n";
        report_skipped();   # report any finer gaps that still remain
        return;
    }

    my $count = 0;
    while (1) {
        @window_ids = ();
        my $content = do_authed_fetch('comment_body', $lastid+1, $COMMENTS_FETCH_BODY, $ljsession);
        die "Some sort of error fetching body data from server" unless $content;

        # now we want to XML parse this
        unless ($content eq '__SKIP__') {
            my $parser = new XML::Parser(Handlers => { Start => $body_handler, Char => $body_content, End => $body_closer });
            $parser->parse($content);
        }

        # INCREMENTAL SAVE: persist this window's comments, advance the checkpoint, and flush
        # to disk immediately. This turns the comment phase from all-or-nothing into resumable:
        # if the server blocks us mid-run, everything pulled so far is already saved, and the
        # next --sync picks up from comment:lastid instead of restarting bodies from scratch.
        foreach my $id (@window_ids) {
            next unless $meta{$id}{jitemid}; # jitemid == 0 means we didn't get body info
            $count++;
            save_comment($meta{$id});
        }
        $lastid += $COMMENTS_FETCH_BODY;
        $bak{"comment:lastid"} = $lastid;   # checkpoint advances EVERY window (even empty ones)
        $tied->sync();                       # flush so progress survives an interruption

        last unless $lastid < $server_max_id;
    }
    print "$count new comments downloaded.\n";
    report_skipped();   # surface any windows skipped during this sweep
}

# save an event that we get
sub save_event {
    my $data = shift;
    my $id = $data->{itemid}; # convenience
    # DO NOT SET REALTIME HERE.  It is set by syncitems.
    foreach (qw(subject anum event eventtime security allowmask poster)) {
        next unless $data->{$_};
        use bytes;
        my $tmp = substr($data->{$_}, 0);
        $bak{"event:$_:$id"} = $tmp;
    }
    my @props;
    while (my ($p, $v) = each %{$data->{props} || {}}) {
        $bak{"event:prop:$id:$p"} = $v;
        push @props, $p;
    }
    $bak{"event:proplist:$id"} = join ',', @props; # so we don't have to sort through the whole database
}

# load up an event given an id
sub load_event {
    my $id = shift;
    my %hash = ( props => {} );
    foreach (qw(subject anum event eventtime security allowmask poster realtime)) {
        $hash{$_} = $bak{"event:$_:$id"};
    }
    my $proplist = $bak{"event:proplist:$id"};
    my @props = split ',', $proplist;
    foreach (@props) {
        $hash{props}->{$_} = $bak{"event:prop:$id:$_"};
    }
    $hash{itemid} = $id;
    return \%hash;
}

# updates a comment (state and posterid)
sub update_comment {
    my $new = shift;
    my $old = load_comment($new->{id});
    return unless $old && $old->{id};
    $old->{$_} = $new->{$_} foreach qw(state posterid);
    save_comment($old);
}

# takes in a comment hashref and saves it to the database
sub save_comment {
    my $data = shift;
    $bak{"comment:state:$data->{id}"} = "$data->{state}:$data->{posterid}:$data->{jitemid}:$data->{parentid}";
    foreach (qw(subject body date)) {
        next unless $data->{$_};
        # GDBM doesn't deal with UTF-8, it only wants a string of bytes, so let's do that
        # by clearing the UTF-8 flag on our input scalars.
        use bytes;
        my $tmp = substr($data->{$_}, 0);
        $bak{"comment:$_:$data->{id}"} = $tmp;
    }
}

# load a comment up into a hash and return the hash
sub load_comment {
    my $id = shift;
    my $state = $bak{"comment:state:$id"};
    return {} unless $state;
    my @data;
    @data = ($1, $2, $3, $4)
        if $state =~ /^(\w):(\d+):(\d+):(\d+)$/;
    my %hash = (
        id => $id,
        subject => $bak{"comment:subject:$id"},
        body => $bak{"comment:body:$id"},
        date => $bak{"comment:date:$id"},
        state => $data[0] || 'D',
        posterid => $data[1]+0,
        jitemid => $data[2]+0,
        parentid => $data[3]+0,
    );
    return \%hash;
}

sub do_authed_fetch {
    my ($mode, $startid, $numitems, $sess, $tries) = @_;
    $tries ||= 0;
    # adaptive pacing: $ADAPT_DELAY is extra delay carried ACROSS windows. It ramps up when
    # the server is unhappy (504s/etc) and decays only after a run of clean successes, so we
    # stay slowed for a while instead of slamming a struggling server fresh on every window.
    sleep($FETCH_DELAY + $ADAPT_DELAY) if ($FETCH_DELAY + $ADAPT_DELAY) > 0;
    d("do_authed_fetch: mode = $mode, startid = $startid, numitems = $numitems, sess = $sess");

    # hit up the server with the specified information and return the raw content.
    # use a cookie jar so the ljsession cookie survives any redirects
    # (e.g. dreamwidth.org -> www.dreamwidth.org)
    my $ua = LWP::UserAgent->new;
    $ua->agent('JBackup/1.0');
    $ua->timeout($HTTP_TIMEOUT);   # a stalled connection becomes an error instead of a forever-hang
    $ua->cookie_jar({});
    $ua->cookie_jar->set_cookie(0, 'ljsession', $sess, '/', $opts{server}, undef, 0, 0, 86400, 0);
    my $authas = $opts{usejournal} ? "&authas=$opts{usejournal}" : '';
    my $request = HTTP::Request->new(GET => "$opts{baseurl}/export_comments.bml?get=$mode&startid=$startid&numitems=$numitems$authas");
    my $response = $ua->request($request);

    if ($response->is_error()) {
        my $code = $response->code;
        # an error means the server is struggling: bump the carried-over delay (capped) and
        # reset the clean-streak counter so it doesn't decay back immediately.
        $ADAPT_DELAY = $ADAPT_DELAY < $ADAPT_MAX ? ($ADAPT_DELAY ? $ADAPT_DELAY * 2 : $ADAPT_STEP) : $ADAPT_MAX;
        $ADAPT_DELAY = $ADAPT_MAX if $ADAPT_DELAY > $ADAPT_MAX;
        $ADAPT_OK = 0;
        # metadata windows get more retry patience than body windows: a skipped meta window is
        # high-stakes (it truncates the meta pass), whereas a skipped body window is a clean,
        # backfillable gap.
        my $cap = ($mode eq 'comment_meta') ? $META_MAX_TRIES : $MAX_BACKOFF_TRIES;
        if ($tries < $cap) {
            my $wait = 15 * (2 ** $tries);
            $wait = $MAX_BACKOFF_WAIT if $wait > $MAX_BACKOFF_WAIT;   # don't let a single backoff run away
            d("do_authed_fetch: HTTP $code; backing off ${wait}s (try " . ($tries+1) . "/$cap); pace now ${ADAPT_DELAY}s");
            sleep $wait;
            return do_authed_fetch($mode, $startid, $numitems, $sess, $tries + 1);
        }
        warn "do_authed_fetch: giving up on $mode startid=$startid after repeated HTTP $code; skipping this window\n";
        record_skip($mode, $startid, $numitems);   # persist the gap for end-of-run report + --backfill
        $tied->sync();
        return '__SKIP__';
    }

    # success: only decay the carried-over delay after several clean windows in a row.
    if ($ADAPT_DELAY > 0) {
        if (++$ADAPT_OK >= $ADAPT_DECAY_AFTER) {
            $ADAPT_OK = 0;
            $ADAPT_DELAY = int($ADAPT_DELAY / 2);
            d("do_authed_fetch: clean streak; easing pace to ${ADAPT_DELAY}s");
        }
    }

    my $xml = $response->content();
    return $xml if $xml;

    # 200 but empty body: transient, retry (no try increment, matches original intent)
    d("do_authed_fetch: empty response; retrying");
    return do_authed_fetch($mode, $startid, $numitems, $sess, $tries);
}

sub do_dump {
    # raw handler preemption
    my $dt = shift;
    return raw_dump() if $dt eq 'raw';

    # put our data into a format usable by the dumpers
    d("do_dump: loading comments");
    my %data;
    my @ids = split ',', $bak{"comment:ids"};
    foreach my $id (@ids) {
        $data{$id} = load_comment($id);
    }

    # get the usermap loaded
    d("do_dump: loading users");
    my %usermap;
    my @userids = split ',', $bak{"usermap:userids"};
    foreach my $id (@userids) {
        $usermap{$id} = $bak{"usermap:$id"};
    }

    # now let's hit up the events
    d("do_dump: loading events");
    my %events;
    @ids = split ',', $bak{"event:ids"};
    foreach my $id (@ids) {
        $events{$id} = load_event($id);
        delete $events{$id} if $opts{publiconly} &&
                               $events{$id}->{security} && $events{$id}->{security} ne 'public';
    }

    # and now, the wild and crazy 'dump this' handler ... in case you can't tell, it just
    # dispatches to the appropriate dumper, and if an invalid dump type is specified, it
    # tells the user they can't do that
    my $content = ({html => \&dump_html, xml => \&dump_xml}->{$dt} || \&dump_invalid)->(\%data, \%usermap, \%events);
    if ($opts{file}) {
        # open file and print
        open FILE, ">$opts{file}"
            or die "do_dump: unable to open file: $!\n";
        print FILE $content;
        close FILE;
    } else {
        # just throw it out, oh well
        print $content;
    }
}

sub do_alter_security {
    # raw handler preemption
    my ($newsec, $confirmed) = @_;

    # verify new security
    my ($security, $allowmask);
    if ($newsec eq 'friends') {
        ($security, $allowmask) = ('usemask', 1);
    } elsif ($newsec eq 'private') {
        ($security, $allowmask) = ('private', 0);
    } else {
        # probably a group? load their groups
        my $groups = call_xmlrpc('getfriendgroups', { ver => 1 });
        foreach my $group (@{$groups->{friendgroups} || []}) {
            if ($group->{name} eq $newsec) {
                # it's this group, set it up
                ($security, $allowmask) = ('usemask', 1 << $group->{id});
            }
        }
    }
    die "New security must be one of: friends, private, or the name of a group you have.\n"
        unless defined $security && defined $allowmask;
    d("do_alter_security: new security = $security ($allowmask)");

    # load up the user's events
    d("do_alter_security: loading events");
    my %events;
    my @ids = split ',', $bak{"event:ids"};
    foreach my $id (@ids) {
        $events{$id} = load_event($id);

        # delete events that are not public
        delete $events{$id} if $events{$id}->{security} &&
                               $events{$id}->{security} ne 'public';
    }

    # now spit out to the user what we're going to change
    unless ($confirmed) {
        foreach my $evt (sort { $a->{eventtime} cmp $b->{eventtime} } values %events) {
            my ($subj, $time) = ($evt->{subject} || '(no subject)', $evt->{eventtime});
            my $ditemid = $evt->{itemid} * 256 + $evt->{anum};
            $subj = substr($subj, 0, 40);
            printf "\%-45s\%s\n", $subj, "$opts{baseurl}/users/$opts{linkuser}/$ditemid.html";
        }
        return;
    }

    # if we're confirmed we get here and we should handle uploading the changed entries
    foreach my $evt (sort { $a->{eventtime} cmp $b->{eventtime} } values %events) {
        # make SURE we have event text (otherwise we delete their entry)
        die "FATAL: no event text for event itemid $evt->{itemid}!\n"
            unless $evt->{event};

        # break up the event time
        my ($year, $mon, $day, $hour, $min);
        if ($evt->{eventtime} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):\d\d$/) {
            ($year, $mon, $day, $hour, $min) = ($1, $2, $3, $4, $5);
        } else {
            # if we have no time, this is also fatal
            die "FATAL: $evt->{eventtime} does not match expected eventtime format.\n";
        }

        # now call for the update
        my $hash = call_xmlrpc('editevent', {
            ver => 1,
            itemid => $evt->{itemid},
            event => $evt->{event},
            subject => $evt->{subject},
            security => $security,
            allowmask => $allowmask,
            props => $evt->{props}, # hashref
            usejournal => $evt->{linkuser},
            year => $year,
            mon => $mon,
            day => $day,
            hour => $hour,
            min => $min,
        });

        # see what we got back and make sure it's kosher
        die "FATAL: Server sent back ($hash->{itemid}, $hash->{anum}) but expected ($evt->{itemid}, $evt->{anum}).\n"
            if $hash->{itemid} != $evt->{itemid} || $hash->{anum} != $evt->{anum};

        # print success
        my $ditemid = $hash->{itemid} * 256 + $hash->{anum};
        printf "\%s\n%-35s\%s\n\n", ($evt->{subject} || "(no subject)"), "public -> $security ($allowmask)",
            "$opts{baseurl}/users/$opts{linkuser}/$ditemid.html";
    }

    # tell user to run --sync
    print "WARNING: you should now run jbackup.pl again with the --sync\n" .
          "option, AFTER making a backup copy of your current jbak GDBM\n" .
          "file. That way, if anything got messed up, you still have your journal.\n";
}

sub dump_invalid {
    d("dump_invalid: invalid dump type");
    return "Invalid dump type specified.  Valid values are xml, html, and raw.\n";
}

# makes an array of trees of comments so they can easily be parsed in dumpers
sub make_tree {
    d("make_tree: calculating");
    my $comments = shift;

    my %jitems;
    my %children;
    while (my ($id, $data) = each %$comments) {
        if ($data->{parentid}) {
            # not a top level comment
            push @{$children{$data->{parentid}}}, $id;
        } else {
            # top level comment, so add it to the list
            push @{$jitems{$data->{jitemid}}}, $id;
        }
    }

    # now we want to sort all the comments by date
    while (my ($id, $list) = each %children) {
        $children{$id} = [ sort { $comments->{$a}{date} cmp $comments->{$b}{date} } @$list ];
    }
    while (my ($id, $list) = each %jitems) {
        $jitems{$id} = [ sort { $comments->{$a}{date} cmp $comments->{$b}{date} } @$list ];
    }

    # now we have all the location information necessary to construct our array
    my $creator;
    $creator = sub {
        my ($jitemid, $jtalkid) = @_;

        # two modes: first creates hashref for an entry, second an arrayref of comments
        if ($jitemid) {
            my @temp;
            foreach my $id (@{$jitems{$jitemid}}) {
                # we get comment ids here
                push @temp, $creator->(0, $id);
            }
            return \@temp;
        } elsif ($jtalkid) {
            my $hash = $comments->{$jtalkid};
            push @{$hash->{children}}, $creator->(0, $_)
                foreach @{$children{$jtalkid} || []};
            return $hash;
        }
    };

    # create the result array to send back
    my %res;
    $res{$_} = $creator->($_, 0) foreach keys %jitems;

    # all done
    return \%res;
}

sub prune_nonvisible {
    # prunes out nonvisible trunks of the passed comment tree.  a nonvisible trunk is defined
    # as a part of the comment tree that has no visible children.  this could mean they're all
    # deleted, or perhaps they're all screened and we're hiding private data.  however, note
    # that we show normally hidden things if a visible comment is further down the trunk, but
    # we want to show as little as possible, so we prune out most things.
    my $stem = shift;
    my $anyvis = 0; # any visible?

    # hit up each child
    my @list;
    foreach my $data (@{$stem->{children} || []}) {
        $data = prune_nonvisible($data);
        if ($data && %$data) {
            $anyvis = 1;
            push @list, $data;
        }
    }
    $stem->{children} = \@list;

    # now hop back and undefine this stem if necessary.  we undefine if we have no visible
    # children and we are also not visible.
    $stem = undef if !$anyvis && $stem->{state} ne 'A';
    return $stem;
}

sub dump_html {
    my ($comments, $users, $events) = @_;
    d("dump_html: dumping.");

    # dumper
    my $ret = "<html><body>";
    my $cdumper;
    $cdumper = sub {
        my ($ary, $link, $anum, $level) = @_;
        foreach my $data (@{$ary || []}) {
            # prune out paths that we shouldn't see
            $data = prune_nonvisible($data);
            next unless $data;

            # we have something to dump, so let's get to it
            $ret .= "<br /><div style='margin-left: 15px;'>\n";
            my $col = ($level % 2) ? '#bbb' : '#ddd';
            $ret .= "<div style='background-color: $col; border: black 1px solid;'>\n";
            if ($data->{state} eq 'D') {
                $ret .= "(deleted comment)";
            } elsif ($data->{state} eq 'S' && $opts{publiconly}) {
                $ret .= "(screened comment)";
            } else {
                my $ditemid = $data->{id} * 256 + $anum;
                my $commentlink = "$link?thread=$ditemid#t$ditemid";
                $ret .= $data->{posterid} ?
                        "<a href='$commentlink'>Comment</a> by <a href='$opts{baseurl}/profile.bml?user=$users->{$data->{posterid}}'>$users->{$data->{posterid}}</a> " :
                        "<a href='$commentlink'>Anonymous comment</a> ";
                $ret .= "on $data->{date}<br />\n";
                $data->{subject} = $opts{clean} ? clean_subject($data->{subject}) : ehtml($data->{subject});
                $ret .= "<b>Subject:</b> $data->{subject}<br />\n" if $data->{subject};
                $data->{body} = $opts{clean} ? clean_comment($data->{body}) : ehtml($data->{body});
                $ret .= $data->{body} . "\n<br />";
                my $replylink = "$link?replyto=$ditemid";
                $ret .= "(<a href='$replylink'>reply</a>)\n";
            }
            $ret .= "</div>\n";

            # now hit up their children
            $cdumper->($data->{children}, $link, $anum, $level+1);

            $ret .= "</div>\n";
        }
    };

    # iterate through all entries, sorted by date
    my $tree = make_tree($comments);
    my $maxcount = scalar keys %$events;
    my $count = 0;
    foreach my $evt (sort { $a->{eventtime} cmp $b->{eventtime} } values %{$events || {}}) {
        $ret .= "<br /><div style='background-color: #eee; border: blue 1px solid;'>\n";
        my $itemid = $evt->{itemid} * 256 + $evt->{anum};
        my $link = "$opts{baseurl}/users/$opts{linkuser}/$itemid.html";
        $evt->{subject} = $opts{clean} ? clean_subject($evt->{subject}) : ehtml($evt->{subject});
        $ret .= "<b>$evt->{subject}</b>" if $evt->{subject};
        my $altposter = $evt->{poster} ? " (posted by $evt->{poster})" : "";
        $ret .= "$altposter<br />\n";
        $ret .= "<a href='$link'>$evt->{eventtime}</a><br /><br />\n";
        $evt->{event} = $opts{clean} ? clean_event($evt->{event}) : ehtml($evt->{event});
        $ret .= "$evt->{event}<br />";
        $ret .= "(<a href='$link?mode=reply'>reply</a>)<br />\n";
        $cdumper->($tree->{$evt->{itemid}}, $link, $evt->{anum}); # dump comments
        $ret .= "</div>\n";

        $count++;
        unless ($count % 100) {
            my $str = sprintf "%.2f%% ...", ($count / $maxcount * 100);
            d($str);
        }
    }
    $ret .= "</body></html>";
    d("100.00% ..."); # just to make it look polished
    d("dump_html: done.");
    return $ret;
}

sub dump_xml {
    my ($comments, $users, $events) = @_;
    d("dump_xml: dumping.");

    # comment dumper
    my $ret;
    my $cdumper;
    $cdumper = sub {
        my ($ary, $level) = @_;
        my $res;
        foreach my $data (@{$ary || []}) {
            # prune out paths that we shouldn't see
            $data = prune_nonvisible($data);
            next unless $data;

            # we have something to dump, so let's get to it
            $res .= "\t\t\t\t<comment jtalkid='$data->{id}'";
            $res .= " poster='$users->{$data->{posterid}}' posterid='$data->{posterid}'" if $data->{posterid};
            $res .= " parentid='$data->{parentid}'" if $data->{parentid};
            $res .= " state='$data->{state}'" if $data->{state} ne 'A';
            $res .= ">\n";
            $res .= "\t\t\t\t\t<date>$data->{date}</date>\n";

            unless ($data->{state} eq 'D' ||
                    $data->{state} eq 'S' && $opts{publiconly}) {
                # spit out subject/body info
                foreach (qw(subject body)) {
                    $data->{$_} = exml($data->{$_});
                    $res .= "\t\t\t\t\t<$_>$data->{$_}</$_>\n" if $data->{$_};
                }
            }

            # now hit up their children
            my $sc = $cdumper->($data->{children}, $level+1);
            $res .= "\t\t\t\t\t<comments>\n$sc\t\t\t\t\t</comments>\n" if $sc;
            $res .= "\t\t\t\t</comment>\n";
        }
        return $res;
    };

    # dump xml formatted comments
    $ret .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
    $ret .= "<dreamwidth>\n\t<events>\n";

    # now start iterating
    my $tree = make_tree($comments);
    my $maxcount = scalar keys %$events;
    my $count = 0;
    foreach my $evt (sort { $a->{eventtime} cmp $b->{eventtime} } values %{$events || {}}) {
        my $ditemid = $evt->{itemid} * 256 + $evt->{anum};
        $ret .= "\t\t<event jitemid='$evt->{itemid}' anum='$evt->{anum}' ditemid='$ditemid'";
        $ret .= " security='$evt->{security}'" if $evt->{security} && $evt->{security} ne 'public';
        $ret .= " allowmask='$evt->{allowmask}'" if $evt->{allowmask};
        $ret .= " poster='$evt->{poster}'" if $evt->{poster};
        $ret .= ">\n";
        foreach (qw(subject event)) {
            $evt->{$_} = exml($evt->{$_});
            $ret .= "\t\t\t<$_>$evt->{$_}</$_>\n" if $evt->{$_};
        }
        $ret .= "\t\t\t<date>$evt->{eventtime}</date>\n";
        $ret .= "\t\t\t<systemdate>$evt->{realtime}</systemdate>\n";
        my $p;
        while (my ($k, $v) = each %{$evt->{props} || {}}) {
            $k = exml($k);
            $v = exml($v);
            $p .= "\t\t\t\t<prop name='$k' value='$v' />\n";
        }
        $ret .= "\t\t\t<props>\n$p\t\t\t</props>\n" if $p;
        my $c = $cdumper->($tree->{$evt->{itemid}}); # dump comments
        $ret .= "\t\t\t<comments>\n$c\t\t\t</comments>\n" if $c;
        $ret .= "\t\t</event>\n";

        $count++;
        unless ($count % 100) {
            my $str = sprintf "%.2f%% ...", ($count / $maxcount * 100);
            d($str);
        }
    }
    d("100.00% ..."); # spit and polish

    # close out, we're done
    $ret .= "\t</events>\n</dreamwidth>\n";
    d("dump_xml: done.");
    return $ret;
}

sub xmlrpc_call_helper {
    # helper function that makes life easier on folks that call xmlrpc stuff.  this handles
    # running the actual request and checking for errors, as well as handling the cases where
    # we hit a problem and need to do something about it.  (back off, retry, skip or abort.)
    my ($xmlrpc, $method, $req, $mode, $hash, $tries) = @_;
    $tries ||= 0;
    sleep $XMLRPC_DELAY if $XMLRPC_DELAY;
    d("\t\txmlrpc_call_helper: $method");
    my $res;
    eval { $res = $xmlrpc->call($method, $req); };
    if ($res && $res->fault) {
        # a server-side fault (e.g. throttle/abuse "Denied access to method"). Back off and
        # retry a few times in case it's transient; only abort if it persists.
        if ($tries < $MAX_BACKOFF_TRIES) {
            my $wait = 30 * (2 ** $tries);   # 30,60,120,240,480,960s
            print STDERR "xmlrpc_call_helper: fault '" . $res->faultstring . "'; backing off ${wait}s (try " . ($tries+1) . "/$MAX_BACKOFF_TRIES)\n";
            sleep $wait;
            return call_xmlrpc($mode, $hash, $tries + 1);
        }
        # fatal error, so don't use d() as we want to print even in case of non-verbosity
        print STDERR "xmlrpc_call_helper error:\n\tString: " . $res->faultstring . "\n\tCode: " . $res->faultcode . "\n";
        print STDERR "\t(persisted after $MAX_BACKOFF_TRIES backoffs -- you are likely rate/abuse blocked; wait and re-run --sync)\n";
        do_abort();
        exit 1;
    }
    unless ($res) {
        # no response: server timeout / transport error. back off and retry (bounded).
        if ($tries < $MAX_BACKOFF_TRIES) {
            my $wait = 15 * (2 ** $tries);
            d("\t\txmlrpc_call_helper: no response; backing off ${wait}s (try " . ($tries+1) . "/$MAX_BACKOFF_TRIES)");
            sleep $wait;
            return call_xmlrpc($mode, $hash, $tries + 1);
        }
        print STDERR "xmlrpc_call_helper: giving up after repeated timeouts on $method\n";
        do_abort();
        exit 1;
    }
    return $res->result;
}

sub call_xmlrpc {
    # also a way to help people do xmlrpc stuff easily.  this method actually does the
    # challenge response stuff so we never send the user's password or md5 digest over
    # the intarweb.  of course, we say nothing about the user's password security anyway...
    my ($mode, $hash, $tries) = @_;
    $hash ||= {};
    $tries ||= 0;

    my $xmlrpc = new XMLRPC::Lite;
    $xmlrpc->proxy("$opts{baseurl}/interface/xmlrpc");
    eval { $xmlrpc->transport->timeout($HTTP_TIMEOUT); };   # don't hang forever on a dead socket
    my $chal;
    while (!$chal) {
        my $get_chal = xmlrpc_call_helper($xmlrpc, 'LJ.XMLRPC.getchallenge', undef, $mode, $hash, $tries);
        $chal = $get_chal->{'challenge'};
    }
    #d("\tcall_xmlrpc: challenge obtained: $chal");

    my $response = md5_hex($chal . ($opts{md5password} ? $opts{md5password} : md5_hex($opts{password})));
    #d("\tcall_xmlrpc: calling LJ.XMLRPC.$mode");
    my $res = xmlrpc_call_helper($xmlrpc, "LJ.XMLRPC.$mode", {
        'username' => $opts{user},
        'auth_method' => 'challenge',
        'auth_challenge' => $chal,
        'auth_response' => $response,
        %$hash, # interpolate $hash into our hash here...isn't Perl great?
    }, $mode, $hash, $tries);
    return $res;
}

sub do_flush {
    # simply flush ourselves
    d('do_flush: flushing database');
    $tied->sync();
}

sub do_tie {
    # try to open the database for access
    d("do_tie: tying database");
    my $x = tie %bak, 'GDBM_File', $filename, &GDBM_WRCREAT, 0600
        or die "Could not open/tie $filename: $!\n";
    return $x;
};

sub do_untie {
    # close our database.
    d("do_untie: untying database");
    return untie %bak;
};

sub do_abort {
    # hard abort.  save our database and just exit right back to the OS.
    print STDERR "Aborted.\n";
    do_untie();
    exit 1;
};

sub raw_dump {
    # dump out the raw GDBM data
    while (my ($k, $v) = each %bak) {
        print "$k = $v\n";
    }
}

sub exml {
    # stolen from ljlib.pl, LJ::exml

    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[&\"\'<>\x00-\x08\x0B\x0C\x0E-\x1F]/;
    # what are those character ranges? XML 1.0 allows:
    # #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]

    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    $a =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    return $a;
}

sub ehtml {
    # also stolen from ljlib.pl, LJ::ehtml

    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[&\"\'<>]/;

    # this is faster than doing one substitution with a map:
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

# yeah, the cleaners are pretty sad right now.  the idea is that perhaps the LJ HTML cleaner can
# be invoked if the user typed the --clean option, it just hasn't been coded in yet.  for now, if
# they specify --clean, we will just replace poll tags with links to the poll, and not do much else.
sub clean_event {
    my $input = shift;
    $input =~ s!<(?:lj-)?poll-(\d+)>!<a href="$opts{baseurl}/poll/?id=$1">View poll.</a>!g;
    return $input;
}

sub clean_comment {
    my $input = shift;
    return $input;
}

sub clean_subject {
    my $input = shift;
    return $input;
}
