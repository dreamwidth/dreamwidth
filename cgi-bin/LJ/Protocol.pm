#!/usr/bin/perl
#
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


use strict;
no warnings 'uninitialized';

use LJ::Global::Constants;
use LJ::Console;
use LJ::Event::JournalNewEntry;
use LJ::Event::AddedToCircle;
use LJ::Entry;
use LJ::Poll;
use LJ::Config;
use LJ::Comment;

LJ::Config->load;

use LJ::Tags;
use LJ::Feed;
use LJ::EmbedModule;

#### New interface (meta handler) ... other handlers should call into this.
package LJ::Protocol;

# global declaration of this text since we use it in two places
our $CannotBeShown = '(cannot be shown)';

# error classes
use constant E_TEMP => 0;
use constant E_PERM => 1;
# maximum items for get_friends_page function
use constant FRIEND_ITEMS_LIMIT => 50;

my %e = (
     # User Errors
     "100" => [ E_PERM, "Invalid username" ],
     "101" => [ E_PERM, "Invalid password" ],
     "102" => [ E_PERM, "Can't use custom security on community journals." ],
     "103" => [ E_PERM, "Poll error" ],
     "104" => [ E_TEMP, "Error adding one or more friends" ],
     "105" => [ E_PERM, "Challenge expired" ],
     "106" => [ E_PERM, "Can only use administrator-locked security on community journals you manage." ],
     "150" => [ E_PERM, "Can't post as non-user" ],
     "151" => [ E_TEMP, "Banned from journal" ],
     "152" => [ E_PERM, "Can't make back-dated entries in non-personal journal." ],
     "153" => [ E_PERM, "Incorrect time value" ],
     "154" => [ E_PERM, "Can't add a redirected account as a friend" ],
     "155" => [ E_TEMP, "Non-authenticated email address" ],
     "157" => [ E_TEMP, "Tags error" ],
     "158" => [ E_PERM, "Comment error" ],

     # Client Errors
     "200" => [ E_PERM, "Missing required argument(s)" ],
     "201" => [ E_PERM, "Unknown method" ],
     "202" => [ E_PERM, "Too many arguments" ],
     "203" => [ E_PERM, "Invalid argument(s)" ],
     "204" => [ E_PERM, "Invalid metadata datatype" ],
     "205" => [ E_PERM, "Unknown metadata" ],
     "206" => [ E_PERM, "Invalid destination journal username." ],
     "207" => [ E_PERM, "Protocol version mismatch" ],
     "208" => [ E_PERM, "Invalid text encoding" ],
     "209" => [ E_PERM, "Parameter out of range" ],
     "210" => [ E_PERM, "Client tried to edit with corrupt data.  Preventing." ],
     "211" => [ E_PERM, "Invalid or malformed tag list" ],
     "212" => [ E_PERM, "Message body is too long" ],
     "213" => [ E_PERM, "Message body is empty" ],
     "214" => [ E_PERM, "Message looks like spam" ],


     # Access Errors
     "300" => [ E_TEMP, "Don't have access to requested journal" ],
     "301" => [ E_TEMP, "Access of restricted feature" ],
     "302" => [ E_TEMP, "Can't edit post from requested journal" ],
     "303" => [ E_TEMP, "Can't edit post in community journal" ],
     "304" => [ E_TEMP, "Can't delete post in this community journal" ],
     "305" => [ E_TEMP, "Action forbidden; account is suspended." ],
     "306" => [ E_TEMP, "This journal is temporarily in read-only mode.  Try again in a couple minutes." ],
     "307" => [ E_PERM, "Selected journal no longer exists." ],
     "308" => [ E_TEMP, "Account is locked and cannot be used." ],
     "309" => [ E_PERM, "Account is marked as a memorial." ],
     "310" => [ E_TEMP, "Account needs to be age verified before use." ],
     "311" => [ E_TEMP, "Access temporarily disabled." ],
     "312" => [ E_TEMP, "Not allowed to add tags to entries in this journal" ],
     "313" => [ E_TEMP, "Must use existing tags for entries in this journal (can't create new ones)" ],
     "314" => [ E_PERM, "Only paid users allowed to use this request" ],
     "315" => [ E_PERM, "User messaging is currently disabled" ],
     "316" => [ E_TEMP, "Poster is read-only and cannot post entries." ],
     "317" => [ E_TEMP, "Journal is read-only and entries cannot be posted to it." ],
     "318" => [ E_TEMP, "Poster is read-only and cannot edit entries." ],
     "319" => [ E_TEMP, "Journal is read-only and its entries cannot be edited." ],

     # Limit errors
     "402" => [ E_TEMP, "Your IP address is temporarily banned for exceeding the login failure rate." ],
     "404" => [ E_TEMP, "Cannot post" ],
     "405" => [ E_TEMP, "Post frequency limit." ],
     "406" => [ E_TEMP, "Client is making repeated requests.  Perhaps it's broken?" ],
     "407" => [ E_TEMP, "Moderation queue full" ],
     "408" => [ E_TEMP, "Maximum queued posts for this community+poster combination reached." ],
     "409" => [ E_PERM, "Post too large." ],
     "410" => [ E_PERM, "Your trial account has expired.  Posting now disabled." ],
     "411" => [ E_PERM, "Subject too long." ],
     "412" => [ E_PERM, "Maximum number of comments reached" ],

     # Server Errors
     "500" => [ E_TEMP, "Internal server error" ],
     "501" => [ E_TEMP, "Database error" ],
     "502" => [ E_TEMP, "Database temporarily unavailable" ],
     "503" => [ E_TEMP, "Error obtaining necessary database lock" ],
     "504" => [ E_PERM, "Protocol mode no longer supported." ],
     "505" => [ E_TEMP, "Account data format on server is old and needs to be upgraded." ], # cluster0
     "506" => [ E_TEMP, "Journal sync temporarily unavailable." ],
     "507" => [ E_TEMP, "Method temporarily disabled; try again later." ],
);

sub translate
{
    my ($u, $msg, $vars) = @_;
    # we no longer support preferred language selection
    return LJ::Lang::get_default_text( "protocol.$msg", $vars );
}

sub error_class
{
    my $code = shift;
    $code = $1 if $code =~ /^(\d\d\d):(.+)/;
    return $e{$code} && ref $e{$code} ? $e{$code}->[0] : undef;
}

sub error_message
{
    my $code = shift;
    my $des;
    ($code, $des) = ($1, $2) if $code =~ /^(\d\d\d):(.+)/;

    my $prefix = "";
    my $error =
      $e{$code} && ref $e{$code}
      ? ( ref $e{$code}->[1] eq 'CODE' ? $e{$code}->[1]->() : $e{$code}->[1] )
      : "BUG: Unknown error code!";
    $prefix = "Client error: " if $code >= 200;
    $prefix = "Server error: " if $code >= 500;
    my $totalerror = "$prefix$error";
    $totalerror .= ": $des" if $des;
    return $totalerror;
}

sub do_request
{
    # get the request and response hash refs
    my ($method, $req, $err, $flags) = @_;

    # if version isn't specified explicitly, it's version 0
    if (ref $req eq "HASH") {
        $req->{'ver'} ||= $req->{'version'};
        $req->{'ver'} = 0 unless defined $req->{'ver'};
    }

    $flags ||= {};
    my @args = ($req, $err, $flags);

    my $apache_r = eval { BML::get_request() };
    $apache_r->notes->{codepath} = "protocol.$method"
        if $apache_r && ! $apache_r->notes->{codepath};

    DW::Stats::increment( 'dw.protocol_request', 1, [ "method:$method" ] );

    if ($method eq "login")            { return login(@args);            }
    if ($method eq "getfriendgroups")  { return getfriendgroups(@args);  }
    if ($method eq "gettrustgroups")   { return gettrustgroups(@args);   }
    if ($method eq "getfriends")       { return getfriends(@args);       }
    if ($method eq "getcircle")        { return getcircle(@args);        }
    if ($method eq "editcircle")       { return editcircle(@args);       }
    if ($method eq "friendof")         { return friendof(@args);         }
    if ($method eq "checkfriends")     { return checkfriends(@args);     }
    if ($method eq "checkforupdates")  { return checkforupdates(@args);  }
    if ($method eq "getdaycounts")     { return getdaycounts(@args);     }
    if ($method eq "postevent")        { return postevent(@args);        }
    if ($method eq "editevent")        { return editevent(@args);        }
    if ($method eq "syncitems")        { return syncitems(@args);        }
    if ($method eq "getevents")        { return getevents(@args);        }
    if ($method eq "editfriends")      { return editfriends(@args);      }
    if ($method eq "editfriendgroups") { return editfriendgroups(@args); }
    if ($method eq "consolecommand")   { return consolecommand(@args);   }
    if ($method eq "getchallenge")     { return getchallenge(@args);     }
    if ($method eq "sessiongenerate")  { return sessiongenerate(@args);  }
    if ($method eq "sessionexpire")    { return sessionexpire(@args);    }
    if ($method eq "getusertags")      { return getusertags(@args);      }
    if ($method eq "getfriendspage")   { return getfriendspage(@args);   }
    if ($method eq "getreadpage")      { return getreadpage(@args);   }
    if ($method eq "getinbox")         { return getinbox(@args);         }
    if ($method eq "sendmessage")      { return sendmessage(@args);      }
    if ($method eq "setmessageread")   { return setmessageread(@args);   }
    if ($method eq "addcomment")       { return addcomment(@args);   }

    $apache_r->notes->{codepath} = ""
        if $apache_r;

    return fail($err,201);
}


sub addcomment
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    my $u = $flags->{'u'};

    # some additional checks
    return fail($err,314) unless $u->is_paid || $flags->{nocheckcap};
    return fail($err,214) if LJ::Comment->is_text_spam( \ $req->{body} );

    my $journal;
    if ( $req->{journal} ){
        $journal = LJ::load_user( $req->{journal} ) or return fail( $err, 100 );
        return fail( $err, 214 )
            if LJ::Talk::Post::require_captcha_test( $u, $journal, $req->{body}, $req->{ditemid} );
    } else {
        $journal = $u;
    }

    # create
    my $comment_err;
    my $comment = LJ::Comment->create(
                        journal      => $journal,
                        ditemid      => $req->{ditemid},
                        parenttalkid => ($req->{parenttalkid} || ($req->{parent} >> 8)),

                        poster       => $u,

                        body         => $req->{body},
                        subject      => $req->{subject},

                        props        => { picture_keyword => $req->{prop_picture_keyword} },

                        err_ref      => \$comment_err,
                        );

    my $err_code_mapping = {
        bad_journal     => 206,     # authenticate() takes care of this
        bad_poster      => 100,     # authenticate() takes care of this
        bad_args        => 202,

        too_many_comments => 412,

        init_comment    => 158,
        frozen          => 158,
        post_comment    => 158,
    }->{$comment_err->{code}} if $comment_err;

    return fail( $err, $err_code_mapping, $comment_err->{msg} ) if $comment_err;

    my %props = ();
    $props{useragent} = $req->{useragent} if $req->{useragent};
    $props{editor} = $req->{editor} if $req->{editor};
    $comment->set_props( %props );

    # OK
    return {
             status      => "OK",
             commentlink => $comment->url,
             dtalkid     => $comment->dtalkid,
             };
}


sub getfriendspage
{
    return fail( $_[1], 504, "Use 'getreadpage' instead." );
}

sub getreadpage
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    my $u = $flags->{'u'};

    my $itemshow = (defined $req->{itemshow}) ? $req->{itemshow} : 100;
    return fail($err, 209, "Bad itemshow value") if $itemshow ne int($itemshow ) or $itemshow  <= 0 or $itemshow  > 100;
    my $skip = (defined $req->{skip}) ? $req->{skip} : 0;
    return fail($err, 209, "Bad skip value") if $skip ne int($skip ) or $skip  < 0 or $skip  > 100;

    my @entries = $u->watch_items(
        remote      => $u,

        itemshow    => $itemshow,
        skip        => $skip,

        dateformat  => 'S2',
    );

    my @attrs = qw/subject_raw event_raw journalid posterid ditemid security/;

    my @uids;

    my @res = ();
    my $lastsync = int $req->{lastsync};
    foreach my $ei (@entries) {

        next unless $ei;

        # exit cycle if maximum friend items limit reached
        last
            if scalar @res >= FRIEND_ITEMS_LIMIT;

        # if passed lastsync argument - skip items with logtime less than lastsync
        if($lastsync) {
            next
                if $LJ::EndOfTime - $ei->{rlogtime} <= $lastsync;
        }

        my $entry = LJ::Entry->new_from_item_hash($ei);
        next unless $entry;

        # event result data structure
        my %h = ();

        # Add more data for public posts
        foreach my $method (@attrs) {
            $h{$method} = $entry->$method;
        }

        # log time value
        $h{logtime} = $LJ::EndOfTime - $ei->{rlogtime};

        push @res, \%h;

        push @uids, $h{posterid}, $h{journalid};
    }

    my $users = LJ::load_userids(@uids);

    foreach (@res) {
        $_->{journalname} = $users->{ $_->{journalid} }->{'user'};
        $_->{journaltype} = $users->{ $_->{journalid} }->{'journaltype'};
        delete $_->{journalid};
        $_->{postername} = $users->{ $_->{posterid} }->{'user'};
        $_->{postertype} = $users->{ $_->{posterid} }->{'journaltype'};
        delete $_->{posterid};
    }

    LJ::Hooks::run_hooks("getfriendspage", { 'userid' => $u->userid, });

    return { 'entries' => [ @res ] };
}

sub getinbox
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    my $u = $flags->{'u'};

    my $itemshow = (defined $req->{itemshow}) ? $req->{itemshow} : 100;
    return fail($err, 209, "Bad itemshow value") if $itemshow ne int($itemshow ) or $itemshow  <= 0 or $itemshow  > 100;
    my $skip = (defined $req->{skip}) ? $req->{skip} : 0;
    return fail($err, 209, "Bad skip value") if $skip ne int($skip ) or $skip  < 0 or $skip  > 100;

    # get the user's inbox
    my $inbox = $u->notification_inbox or return fail($err, 500, "Cannot get user inbox");

    my %type_number = (
        AddedToCircle        => 1,
        Birthday             => 2,
        CommunityInvite      => 3,
        CommunityJoinApprove => 4,
        CommunityJoinReject  => 5,
        CommunityJoinRequest => 6,
        RemovedFromCircle    => 7,
        InvitedFriendJoins   => 8,
        JournalNewComment    => 9,
        JournalNewEntry      => 10,
        NewUserpic           => 11,
        NewVGift             => 12,
        OfficialPost         => 13,
        PermSale             => 14,
        PollVote             => 15,
        SupOfficialPost      => 16,
        UserExpunged         => 17,
        UserMessageRecvd     => 18,
        UserMessageSent      => 19,
    );
    my %number_type = reverse %type_number;

    my @notifications;

    my $sync_date;
    # check lastsync for valid date
    if ($req->{'lastsync'}) {
        $sync_date = int $req->{'lastsync'};
        if($sync_date <= 0) {
            return fail($err,203,"Invalid syncitems date format (must be unixtime)");
        }
    }

    if ($req->{gettype}) {
        @notifications = grep { $_->event->class eq "LJ::Event::" . $number_type{$req->{gettype}} } $inbox->items;
    } else {
        @notifications = $inbox->all_items;
    }

    # By default, notifications are sorted as "oldest are the first"
    # Reverse it by "newest are the first"
    @notifications = reverse @notifications;

    $itemshow = scalar @notifications - $skip if scalar @notifications < $skip + $itemshow;

    my @res;
    foreach my $item (@notifications[$skip .. $itemshow + $skip - 1]) {
        next if $sync_date && $item->when_unixtime < $sync_date;

        my $raw = $item->event->raw_info($u, {extended => $req->{extended}});

        my $type_index = $type_number{$raw->{type}};
        if (defined $type_index) {
            $raw->{type} = $type_index;
        } else {
            $raw->{typename} = $raw->{type};
            $raw->{type} = 0;
        }

        $raw->{state} = $item->{state};

        push @res, { %$raw,
                     when   => $item->when_unixtime,
                     qid    => $item->qid,
                   };
    }

    return { 'items' => \@res,
             'login' => $u->user,
             'journaltype' => $u->journaltype };
}

sub setmessageread {
    my ($req, $err, $flags) = @_;

    return undef unless authenticate($req, $err, $flags);

    my $u = $flags->{'u'};

    # get the user's inbox
    my $inbox = $u->notification_inbox or return fail($err, 500, "Cannot get user inbox");
    my @result;

    # passing requested ids for loading
    my @notifications = $inbox->all_items;

    # Try to select messages by qid if specified
    my @qids = @{$req->{qid}};
    if (scalar @qids) {
        foreach my $qid (@qids) {
            my $item = eval {LJ::NotificationItem->new($u, $qid)};
            $item->mark_read if $item;
            push @result, { qid => $qid, result => 'set read'  };
        }
    } else { # Else select it by msgid for back compatibility
        # make hash of requested message ids
        my %requested_items = map { $_ => 1 } @{$req->{messageid}};

        # proccessing only requested ids
        foreach my $item (@notifications) {
            my $msgid = $item->event->raw_info($u)->{msgid};
            next unless $requested_items{$msgid};
            # if message already read -
            if ($item->{state} eq 'R') {
                push @result, { msgid => $msgid, result => 'already red' };
                next;
            }
            # in state no 'R' - marking as red
            $item->mark_read;
            push @result, { msgid => $msgid, result => 'set read'  };
        }
    }

    return {
        result => \@result
    };

}

# Sends a private message from one account to another
sub sendmessage
{
    my ($req, $err, $flags) = @_;

    return fail($err, 315) unless LJ::is_enabled('user_messaging');

    return undef unless authenticate($req, $err, $flags);
    my $u = $flags->{'u'};

    return fail($err, 305) if $u->is_suspended; # suspended cannot send private messages

    my $msg_limit = $u->count_usermessage_length;

    my @errors;

    # test encoding and length
    my $subject_text = $req->{'subject'};
    return fail($err, 208, 'subject')
        unless LJ::text_in($subject_text);

    # test encoding and length
    my $body_text = $req->{'body'};
    return fail($err, 208, 'body')
        unless LJ::text_in($body_text);

    my ($msg_len_b, $msg_len_c) = LJ::text_length($body_text);
    return fail($err, 212, 'found: ' . LJ::commafy($msg_len_c) . ' characters, it should not exceed ' . LJ::commafy($msg_limit))
        unless ($msg_len_c <= $msg_limit);


    return fail($err, 213, 'found: ' . LJ::commafy($msg_len_c) . ' characters, it should exceed zero')
        if ($msg_len_c <= 0);

    #test if to argument is present
    return fail($err, 200, "to") unless exists $req->{'to'};

    my @to = (ref $req->{'to'}) ? @{$req->{'to'}} : ($req->{'to'});
    return fail($err, 200) unless scalar @to;

    # remove duplicates
    my %to = map { lc($_), 1 } @to;
    @to = keys %to;

    my @msg;
    BML::set_language('en'); # FIXME

    foreach my $to (@to) {
        my $tou = LJ::load_user($to);
        return fail($err, 100, $to)
            unless $tou;

        my $msguserpic;
        $msguserpic = $req->{'userpic'} if defined $req->{'userpic'};

        my $msg = LJ::Message->new({
                    journalid => $u->userid,
                    otherid => $tou->userid,
                    subject => $subject_text,
                    body => $body_text,
                    parent_msgid => defined $req->{'parent'} ? $req->{'parent'} + 0 : undef,
                    userpic => $msguserpic,
                  });

        push @msg, $msg
            if $msg->can_send(\@errors);
    }
    return fail($err, 203, join('; ', @errors))
        if scalar @errors;

    foreach my $msg (@msg) {
        $msg->send(\@errors);
    }

    return { 'sent_count' => scalar @msg, 'msgid' => [ grep { $_ } map { $_->msgid } @msg ],
             (@errors ? ('last_errors' => \@errors) : () ),
           };
}

sub login
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);

    my $u = $flags->{'u'};
    my $res = {};
    my $ver = $req->{'ver'};

    # do not let locked people log in
    return fail($err, 308) if $u->is_locked;

    ## return a message to the client to be displayed (optional)
    login_message($req, $res, $flags);
    LJ::text_out(\$res->{'message'}) if $ver>=1 and defined $res->{'message'};

    ## report what shared journals this user may post in
    $res->{'usejournals'} = list_usejournals($u);

    ## return their friend groups
    $res->{'friendgroups'} = list_friendgroups($u);
    return fail($err, 502, "Error loading friend groups") unless $res->{'friendgroups'};
    if ($ver >= 1) {
        foreach (@{$res->{'friendgroups'}}) {
            LJ::text_out(\$_->{'name'});
        }
    }

    ## if they gave us a number of moods to get higher than, then return them
    if (defined $req->{'getmoods'}) {
        $res->{'moods'} = list_moods($req->{'getmoods'});
        if ($ver >= 1) {
            # currently all moods are in English, but this might change
            foreach (@{$res->{'moods'}}) { LJ::text_out(\$_->{'name'}) }
        }
    }

    ### picture keywords, if they asked for them.
    if ($req->{'getpickws'}) {
        my $pickws = list_pickws($u);
        @$pickws = sort { lc($a->[0]) cmp lc($b->[0]) } @$pickws;
        $res->{'pickws'} = [ map { $_->[0] } @$pickws ];
        if ($req->{'getpickwurls'}) {
            if ($u->{'defaultpicid'}) {
                 $res->{'defaultpicurl'} = "$LJ::USERPIC_ROOT/$u->{'defaultpicid'}/$u->{'userid'}";
            }
            $res->{'pickwurls'} = [ map {
                "$LJ::USERPIC_ROOT/$_->[1]/$u->{'userid'}"
            } @$pickws ];
        }
        if ($ver >= 1) {
            # validate all text
            foreach(@{$res->{'pickws'}}) { LJ::text_out(\$_); }
            foreach(@{$res->{'pickwurls'}}) { LJ::text_out(\$_); }
            LJ::text_out(\$res->{'defaultpicurl'});
        }
    }
    ## return caps, if they asked for them
    if ($req->{'getcaps'}) {
        $res->{'caps'} = $u->caps;
    }

    ## return client menu tree, if requested
    if ($req->{'getmenus'}) {
        $res->{'menus'} = hash_menus($u);
        if ($ver >= 1) {
            # validate all text, just in case, even though currently
            # it's all English
            foreach (@{$res->{'menus'}}) {
                LJ::text_out(\$_->{'text'});
                LJ::text_out(\$_->{'url'}); # should be redundant
            }
        }
    }

    ## tell some users they can hit the fast servers later.
    $res->{'fastserver'} = 1 if $u->can_use_fastlane;

    ## user info
    $res->{'userid'} = $u->{'userid'};
    $res->{'fullname'} = $u->{'name'};
    LJ::text_out(\$res->{'fullname'}) if $ver >= 1;

    if ($req->{'clientversion'} =~ /^\S+\/\S+$/) {
        eval {
            my $apache_r = BML::get_request();
            $apache_r->notes->{clientver} = $req->{'clientversion'};
        };
    }

    ## update or add to clientusage table
    if ($req->{'clientversion'} =~ /^\S+\/\S+$/ &&
        LJ::is_enabled('clientversionlog'))
    {
        my $client = $req->{'clientversion'};

        return fail($err, 208, "Bad clientversion string")
            if $ver >= 1 and not LJ::text_in($client);

        my $dbh = LJ::get_db_writer();
        my $qclient = $dbh->quote($client);
        my $cu_sql = "REPLACE INTO clientusage (userid, clientid, lastlogin) " .
            "SELECT $u->{'userid'}, clientid, NOW() FROM clients WHERE client=$qclient";
        my $sth = $dbh->prepare($cu_sql);
        $sth->execute;
        unless ($sth->rows) {
            # only way this can be 0 is if client doesn't exist in clients table, so
            # we need to add a new row there, to get a new clientid for this new client:
            $dbh->do("INSERT INTO clients (client) VALUES ($qclient)");
            # and now we can do the query from before and it should work:
            $sth = $dbh->prepare($cu_sql);
            $sth->execute;
        }
    }

    return $res;
}

#deprecated
sub getfriendgroups
{
    return fail( $_[1], 504 );
}

sub gettrustgroups
{
    my ( $req, $err, $flags ) = @_;
    return undef unless authenticate( $req, $err, $flags );
    my $u = $flags->{u};
    my $res = {};
    $res->{trustgroups} = list_trustgroups( $u );
    return fail( $err, 502, "Error loading trust groups" ) unless $res->{trustgroups};
    if ( $req->{ver} >= 1 ) {
        foreach ( @{$res->{trustgroups} || []} ) {
            LJ::text_out( \$_->{name} );
        }
    }
    return $res;
}

sub getusertags
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    return undef unless check_altusage($req, $err, $flags);

    my $u = $flags->{'u'};
    my $uowner = $flags->{'u_owner'} || $u;
    return fail($req, 502) unless $u && $uowner;

    my $tags = LJ::Tags::get_usertags($uowner, { remote => $u });
    return { tags => [ values %$tags ] };
}

sub getfriends
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    return fail($req,502) unless LJ::get_db_reader();
    my $u = $flags->{'u'};
    my $res = {};
    if ($req->{'includegroups'}) {
        $res->{'friendgroups'} = list_friendgroups($u);
        return fail($err, 502, "Error loading friend groups") unless $res->{'friendgroups'};
        if ($req->{'ver'} >= 1) {
            foreach (@{$res->{'friendgroups'} || []}) {
                LJ::text_out(\$_->{'name'});
            }
        }
    }
    # TAG:FR:protocol:getfriends_of
    if ($req->{'includefriendof'}) {
        $res->{'friendofs'} = list_friends($u, {
            'limit' => $req->{'friendoflimit'},
            'friendof' => 1,
        });
        if ($req->{'ver'} >= 1) {
            foreach(@{$res->{'friendofs'}}) { LJ::text_out(\$_->{'fullname'}) };
        }
    }
    # TAG:FR:protocol:getfriends
    $res->{'friends'} = list_friends($u, {
        'limit' => $req->{'friendlimit'},
        'includebdays' => $req->{'includebdays'},
    });
    if ($req->{'ver'} >= 1) {
        foreach(@{$res->{'friends'}}) { LJ::text_out(\$_->{'fullname'}) };
    }
    return $res;
}

sub getcircle
{
    my ( $req,  $err,  $flags ) = @_;
    return undef unless authenticate( $req,  $err,  $flags );
    my $u = $flags->{u};
    my $res = {};
    my $limit = $LJ::MAX_WT_EDGES_LOAD;
    $limit = $req->{limit}
      if defined $req->{limit} && $req->{limit} < $limit;

    if ( $req->{includetrustgroups} ) {
      $res->{trustgroups} = list_trustgroups( $u );
      return fail( $err,  502,  "Error loading trust groups" ) unless $res->{trustgroups};
      if ( $req->{ver} >= 1 ) {
        LJ::text_out( \$_->{name} )
            foreach ( @{$res->{trustgroups} || []} );
      }
    }
    if ( $req->{includecontentfilters} ) {
      $res->{contentfilters} = list_contentfilters( $u );
      return fail( $err, 502, "Error loading content filters" ) unless $res->{contentfilters};
      if ( $req->{ver} >= 1 ) {
        LJ::text_out( \$_->{name} )
            foreach ( @{$res->{contentfilters} || []} );
      }
    }
    if ( $req->{includewatchedusers} ) {
      $res->{watchedusers} = list_users( $u,
                                         limit => $limit,
                                         watched => 1,
                                         includebdays => $req->{includebdays},
                                       );
      if ( $req->{ver} >= 1 ) {
        LJ::text_out( \$_->{fullname} )
            foreach ( @{$res->{watchedusers} || []} );
      }
    }
    if ( $req->{includewatchedby} ) {
      $res->{watchedbys} = list_users( $u,
                                       limit => $limit,
                                       watchedby => 1,
                                     );
      if ( $req->{ver} >= 1 ) {
        LJ::text_out( \$_->{fullname} )
            foreach ( @{$res->{watchedbys} || []} );
      }
    }
    if ( $req->{includetrustedusers} ) {
      $res->{trustedusers} = list_users( $u,
                                         limit => $limit,
                                         trusted => 1,
                                         includebdays => $req->{includebdays},
                                       );
      if ($req->{ver} >= 1) {
        LJ::text_out(\$_->{fullname})
            foreach (@{$res->{trustedusers} || []});
      }
    }
    if ( $req->{includetrustedby} ) {
      $res->{trustedbys} = list_users( $u,
                                       limit => $limit,
                                       trustedby => 1,
                                     );
      if ( $req->{ver} >= 1 ) {
        LJ::text_out( \$_->{fullname} )
            foreach ( @{$res->{trustedbys} || []} );
      }
    }
    return $res;
}

sub friendof
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    return fail($req,502) unless LJ::get_db_reader();
    my $u = $flags->{'u'};
    my $res = {};

    # TAG:FR:protocol:getfriends_of2 (same as TAG:FR:protocol:getfriends_of)
    $res->{'friendofs'} = list_friends($u, {
        'friendof' => 1,
        'limit' => $req->{'friendoflimit'},
    });
    if ($req->{'ver'} >= 1) {
        foreach(@{$res->{'friendofs'}}) { LJ::text_out(\$_->{'fullname'}) };
    }
    return $res;
}

sub checkfriends {
    return fail( $_[1], 504, "Use 'checkforupdates' instead." );
}
sub checkforupdates
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    my $u = $flags->{'u'};
    my $res = {};

    # return immediately if they can't use this mode
    unless ( $u->can_use_checkforupdates ) {
        $res->{'new'} = 0;
        $res->{'interval'} = 36000;
        return $res;
    }

    ## have a valid date?
    my $lastupdate = $req->{'lastupdate'};
    if ($lastupdate) {
        return fail($err,203) unless
            ($lastupdate =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
    } else {
        $lastupdate = "0000-00-00 00:00:00";
    }

    my $interval = LJ::Capabilities::get_cap_min( $u, "checkfriends_interval" );
    $res->{'interval'} = $interval;

    my $filter;
    if ( $req->{filter} ) {
        $filter = $u->content_filters( name => $req->{filter} );
        return fail( $err, 203, "Invalid filter name. Trying to check updates for a filter that does not exist." )
            unless $filter;
    }

    my $memkey = [ $u->id, "checkforupdates:$u->{userid}:" . ( $filter ? $filter->id : "" ) ];
    my $update = LJ::MemCache::get($memkey);
    unless ($update) {
        my @fr = $u->watched_userids;

        # FIXME: see whether we can just get the list of users who are in the filter
        if ( $filter ) {
            my @filter_users;

            foreach my $fid ( @fr ) {
                push @filter_users, $fid
                    if $filter->contains_userid( $fid );
            }
            @fr = @filter_users;
        }

        unless ( @fr ) {
            $res->{'new'} = 0;
            $res->{'lastupdate'} = $lastupdate;
            return $res;
        }
        if (@LJ::MEMCACHE_SERVERS) {
            my $tu = LJ::get_timeupdate_multi({ memcache_only => 1 }, @fr);
            my $max = 0;
            foreach ( values %$tu ) {
                $max = $_ if $_ > $max;
            }
            $update = LJ::mysql_time($max) if $max;
        }
        unless ( $update ) {
            my $dbr = LJ::get_db_reader();
            unless ($dbr) {
                # rather than return a 502 no-db error, just say no updates,
                # because problem'll be fixed soon enough by db admins
                $res->{'new'} = 0;
                $res->{'lastupdate'} = $lastupdate;
                return $res;
            }
            my $list = join(", ", map { int($_) } @fr );
            if ($list) {
              my $sql = "SELECT MAX(timeupdate) FROM userusage ".
                  "WHERE userid IN ($list)";
              $update = $dbr->selectrow_array($sql);
            }
        }
        LJ::MemCache::set($memkey,$update,time()+$interval) if $update;
    }
    $update ||= "0000-00-00 00:00:00";

    if ($req->{'lastupdate'} && $update gt $lastupdate) {
        $res->{'new'} = 1;
    } else {
        $res->{'new'} = 0;
    }

    $res->{'lastupdate'} = $update;
    return $res;
}

sub getdaycounts
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    return undef unless check_altusage($req, $err, $flags);

    my $u = $flags->{'u'};
    my $uowner = $flags->{'u_owner'} || $u;
    my $ownerid = $flags->{'ownerid'};
    return fail($err,502) unless LJ::isu( $uowner );

    my $res = {};
    my $daycts = $uowner->get_daycounts( $u );
    return fail($err,502) unless $daycts;

    foreach my $day (@$daycts) {
        my $date = sprintf("%04d-%02d-%02d", $day->[0], $day->[1], $day->[2]);
        push @{$res->{'daycounts'}}, { 'date' => $date, 'count' => $day->[3] };
    }
    return $res;
}

sub common_event_validation
{
    my ($req, $err, $flags) = @_;

    # clean up event whitespace
    # remove surrounding whitespace
    $req->{event} =~ s/^\s+//;
    $req->{event} =~ s/\s+$//;

    # convert line endings to unix format
    if ($req->{'lineendings'} eq "mac") {
        $req->{event} =~ s/\r/\n/g;
    } else {
        $req->{event} =~ s/\r//g;
    }

    # date validation
    if ($req->{'year'} !~ /^\d\d\d\d$/ ||
        $req->{'year'} < 1970 ||    # before unix time started = bad
        $req->{'year'} > 2037)      # after unix time ends = worse!  :)
    {
        return fail($err,203,"Invalid year value (must be in the range 1970-2037).");
    }
    if ($req->{'mon'} !~ /^\d{1,2}$/ ||
        $req->{'mon'} < 1 ||
        $req->{'mon'} > 12)
    {
        return fail($err,203,"Invalid month value.");
    }
    if ($req->{'day'} !~ /^\d{1,2}$/ || $req->{'day'} < 1 ||
        $req->{'day'} > LJ::days_in_month($req->{'mon'},
                                          $req->{'year'}))
    {
        return fail($err,203,"Invalid day of month value.");
    }
    if ($req->{'hour'} !~ /^\d{1,2}$/ ||
        $req->{'hour'} < 0 || $req->{'hour'} > 23)
    {
        return fail($err,203,"Invalid hour value.");
    }
    if ($req->{'min'} !~ /^\d{1,2}$/ ||
        $req->{'min'} < 0 || $req->{'min'} > 59)
    {
        return fail($err,203,"Invalid minute value.");
    }

    # setup non-user meta-data.  it's important we define this here to
    # 0.  if it's not defined at all, then an editevent where a user
    # removes random 8bit data won't remove the metadata.  not that
    # that matters much.  but having this here won't hurt.  false
    # meta-data isn't saved anyway.  so the only point of this next
    # line is making the metadata be deleted on edit.
    $req->{'props'}->{'unknown8bit'} = 0;

    # we don't want attackers sending something that looks like gzipped data
    # in protocol version 0 (unknown8bit allowed), otherwise they might
    # inject a 100MB string of single letters in a few bytes.
    return fail($err,208,"Cannot send gzipped data")
        if substr($req->{'event'},0,2) eq "\037\213";

    # non-ASCII?
    unless ( $flags->{'use_old_content'} || (
        LJ::is_ascii($req->{'event'}) &&
        LJ::is_ascii($req->{'subject'}) &&
        LJ::is_ascii(join(' ', values %{$req->{'props'}})) ))
    {

        if ($req->{ver} < 1) { # client doesn't support Unicode
            # only people should have unknown8bit entries.
            my $uowner = $flags->{u_owner} || $flags->{u};
            return fail($err,207,'Posting in a community with international or special characters require a Unicode-capable LiveJournal client.  Download one at http://www.livejournal.com/download/.')
                if ! $uowner->is_person;
        }

        # validate that the text is valid UTF-8
        if (!LJ::text_in($req->{subject}) ||
            !LJ::text_in($req->{event}) ||
            grep { !LJ::text_in($_) } values %{$req->{props}}) {
                return fail($err, 208, "The text entered is not a valid UTF-8 stream");
        }
    }


    # trim to column width

    # we did a quick check for number of bytes earlier
    # this one also handles the case of too many characters,
    # even if we'd be within the byte limit
    my $did_trim = 0;
    $req->{'event'} = LJ::text_trim( $req->{'event'}, LJ::BMAX_EVENT, LJ::CMAX_EVENT, \$did_trim );
    return fail( $err, 409 ) if $did_trim;


    $did_trim = 0;
    $req->{'subject'} = LJ::text_trim( $req->{'subject'}, LJ::BMAX_SUBJECT, LJ::CMAX_SUBJECT, \$did_trim );
    return fail( $err, 411 ) if $did_trim && ! $flags->{allow_truncated_subject};

    foreach (keys %{$req->{'props'}}) {
        # do not trim this property, as it's magical and handled later
        next if $_ eq 'taglist';

        # Allow syn_links and syn_ids the full width of the prop, to avoid truncating long URLS
        if ($_ eq 'syn_link' || $_ eq 'syn_id') {
            $req->{'props'}->{$_} = LJ::text_trim($req->{'props'}->{$_}, LJ::BMAX_PROP);
        } else {
            $req->{'props'}->{$_} = LJ::text_trim($req->{'props'}->{$_}, LJ::BMAX_PROP, LJ::CMAX_PROP);
        }

    }


    ## handle meta-data (properties)
    LJ::load_props("log");

    my $allow_system = $flags->{allow_system} || {};
    foreach my $pname (keys %{$req->{'props'}})
    {
        my $p = LJ::get_prop("log", $pname);

        # does the property even exist?
        unless ($p) {
            $pname =~ s/[^\w]//g;
            return fail($err,205,$pname);
        }

        # This is a system logprop
        # fail with unknown metadata here?
        if ( $p->{ownership} eq 'system' && !( $allow_system == 1 || $allow_system->{$pname} ) ) {
            $pname =~ s/[^\w]//g;
            return fail($err,205,$pname);
        }

        # don't validate its type if it's 0 or undef (deleting)
        next unless ($req->{'props'}->{$pname});

        my $ptype = $p->{'datatype'};
        my $val = $req->{'props'}->{$pname};

        if ($ptype eq "bool" && $val !~ /^[01]$/) {
            return fail($err,204,"Property \"$pname\" should be 0 or 1");
        }
        if ($ptype eq "num" && $val =~ /[^\d]/) {
            return fail($err,204,"Property \"$pname\" should be numeric");
        }
        if ($pname eq "current_coords" && ! eval { LJ::Location->new(coords => $val) }) {
            return fail($err,204,"Property \"current_coords\" has invalid value");
        }
    }

    # check props for inactive userpic
    if ( ( my $pickwd = $req->{'props'}->{'picture_keyword'} ) and !$flags->{allow_inactive}) {
        my $pic = LJ::Userpic->new_from_keyword( $flags->{u}, $pickwd );

        # need to make sure they aren't trying to post with an inactive keyword,
        # but also we don't want to allow them to post with a keyword that has
        # no pic at all to prevent them from deleting the keyword, posting, then
        # adding it back with the editicons page
        delete $req->{props}->{picture_keyword}
            unless $pic && $pic->state ne 'I';
    }

    # validate incoming list of tags
    return fail($err, 211)
        if $req->{props}->{taglist} &&
           ! LJ::Tags::is_valid_tagstring($req->{props}->{taglist});

    return 1;
}

sub schedule_xposts {
    my ( $u, $ditemid, $deletep, $fn ) = @_;
    return unless LJ::isu( $u ) && $ditemid > 0;
    return unless $fn && ref $fn eq 'CODE';

    my ( @successes, @failures );
    my $sclient = LJ::theschwartz() or return;
    my @accounts = DW::External::Account->get_external_accounts( $u );

    foreach my $acct ( @accounts ) {
        my ( $xpostp, $info ) = $fn->( $acct );
        next unless $xpostp;

        my $jobargs = {
            uid       => $u->userid,
            accountid => $acct->acctid,
            ditemid   => $ditemid + 0,
            delete    => $deletep ? 1 : 0,
            %{$info}
        };

        my $job = TheSchwartz::Job->new_from_array( 'DW::Worker::XPostWorker', $jobargs );
        if ( $job && $sclient->insert($job) ) {
            push @successes, $acct;
        } else {
            push @failures, $acct;
        }
    }

    return ( \@successes, \@failures );
}

sub postevent
{
    my ($req, $err, $flags) = @_;
    un_utf8_request($req);

    # if the importer is calling us, we want to allow it to post in all but the most extreme
    # of cases.  and even then, we try our hardest to allow content to be posted.  setting this
    # flag will bypass a lot of the safety restrictions about who can post where and when, so
    # we trust the importer to be intelligent about this.  (And if you aren't the importer, don't
    # use this option!!!)
    my $importer_bypass = $flags->{importer_bypass} ? 1 : 0;
    if ( $importer_bypass ) {
        $flags->{nomod} = 1;
        $flags->{ignore_tags_max} = 1;
        $flags->{nonotify} = 1;
        $flags->{noauth} = 1;
        $flags->{usejournal_okay} = 1;
        $flags->{no_xpost} = 1;
        $flags->{create_unknown_picture_mapid} = 1;
        $flags->{allow_inactive} = 1;
    }

    return undef unless LJ::Hooks::run_hook('post_noauth', $req) || authenticate($req, $err, $flags);

    # if going through mod queue, then we know they're permitted to post at least this entry
    return undef unless check_altusage($req, $err, $flags) || $flags->{nomod};

    my $u = $flags->{'u'};
    my $ownerid = $flags->{'ownerid'}+0;
    my $uowner = $flags->{'u_owner'} || $u;

    # Make sure we have a real user object here
    $uowner = LJ::want_user($uowner) unless LJ::isu($uowner);
    my $clusterid = $uowner->{'clusterid'};

    my $dbh = LJ::get_db_writer();
    my $dbcm = LJ::get_cluster_master($uowner);

    return fail($err,306) unless $dbh && $dbcm && $uowner->writer;
    return fail($err,200) unless $req->{'event'} =~ /\S/;

    ### make sure community journals don't post
    return fail($err,150) if $u->is_community;

    # suspended users can't post
    return fail($err,305) if ! $importer_bypass && $u->is_suspended;

    # memorials can't post
    return fail($err,309) if ! $importer_bypass && $u->is_memorial;

    # locked accounts can't post
    return fail($err,308) if ! $importer_bypass && $u->is_locked;

    # check the journal's read-only bit
    return fail($err,306) if $uowner->is_readonly;

    # is the user allowed to post?
    return fail($err,404,$LJ::MSG_NO_POST) unless $importer_bypass || $u->can_post;

    # is the user allowed to post?
    return fail($err,410) if $u->can_post_disabled;

    # read-only accounts can't post
    return fail($err,316) if $u->is_readonly;

    # read-only accounts can't be posted to
    return fail($err,317) if $uowner->is_readonly;

    # can't post to deleted/suspended community
    return fail($err,307) unless $importer_bypass || $uowner->is_visible;

    # must have a validated email address to post to a community
    # unless this is approved from the mod queue (we'll error out initially, but in case they change later)
    return fail($err, 155, "You must have an authenticated email address in order to post to another account")
        unless $u->equals( $uowner ) || $u->{'status'} eq 'A' || $flags->{'nomod'};

    # post content too large
    # NOTE: requires $req->{event} be binary data, but we've already
    # removed the utf-8 flag in the XML-RPC path, and it never gets
    # set in the "flat" protocol path.
    return fail($err,409) if length($req->{'event'}) >= LJ::BMAX_EVENT;

    my $time_was_faked = 0;
    my $offset = 0;  # assume gmt at first.

    if (defined $req->{'tz'}) {
        if ($req->{tz} eq 'guess') {
            LJ::get_timezone($u, \$offset, \$time_was_faked);
        } elsif ($req->{'tz'} =~ /^[+\-]\d\d\d\d$/) {
            # FIXME we ought to store this timezone and make use of it somehow.
            $offset = $req->{'tz'} / 100.0;
        } else {
            return fail($err, 203, "Invalid tz");
        }
    }

    if (defined $req->{'tz'} and not grep { defined $req->{$_} } qw(year mon day hour min)) {
        my @ltime = gmtime(time() + ($offset*3600));
        $req->{'year'} = $ltime[5]+1900;
        $req->{'mon'}  = $ltime[4]+1;
        $req->{'day'}  = $ltime[3];
        $req->{'hour'} = $ltime[2];
        $req->{'min'}  = $ltime[1];
        $time_was_faked = 1;
    }

    return undef
        unless common_event_validation($req, $err, $flags);

    # now we can move over to picture_mapid instead of picture_keyword if appropriate
    if ( $req->{props} && defined $req->{props}->{picture_keyword}  && $u->userpic_have_mapid ) {
        $req->{props}->{picture_mapid} = $u->get_mapid_from_keyword( $req->{props}->{picture_keyword}, create => $flags->{create_unknown_picture_mapid} || 0 );
        delete $req->{props}->{picture_keyword};
    }

    # confirm we can add tags, at least
    return fail($err, 312)
        if $req->{props} && $req->{props}->{taglist} &&
           ! ( $importer_bypass || LJ::Tags::can_add_tags( $uowner, $u ) );

    my $event = $req->{'event'};

    ### allow for posting to journals that aren't yours (if you have permission)
    my $posterid = $u->{'userid'}+0;

    # make the proper date format
    my $eventtime = sprintf("%04d-%02d-%02d %02d:%02d",
                                $req->{'year'}, $req->{'mon'},
                                $req->{'day'}, $req->{'hour'},
                                $req->{'min'});
    my $qeventtime = $dbh->quote($eventtime);

    # load userprops all at once
    my @poster_props = qw(newesteventtime dupsig_post);
    my @owner_props = qw(newpost_minsecurity moderated);

    $u->preload_props( @poster_props, @owner_props );
    if ( $u->equals( $uowner ) ) {
        $uowner->{$_} = $u->{$_} foreach @owner_props;
    } else {
        $uowner->preload_props( @owner_props );
    }

    my $qallowmask = $req->{'allowmask'}+0;
    my $security = "public";
    my $uselogsec = 0;
    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }
    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    # can't specify both a custom security and 'friends-only'
    return fail($err, 203, "Invalid friends group security set")
        if $qallowmask > 1 && $qallowmask % 2;

    ## if newpost_minsecurity is set, new entries have to be
    ## a minimum security level
    $security = "private"
        if $uowner->{'newpost_minsecurity'} eq "private";
    ($security, $qallowmask) = ("usemask", 1)
        if $uowner->{'newpost_minsecurity'} eq "friends"
        and $security eq "public";

    my $qsecurity = $dbh->quote($security);

    ### make sure user can't post with "custom security" on communities
    return fail($err,102)
        if $ownerid != $posterid && # community post
           $req->{'security'} eq "usemask" && $qallowmask != 1;

    ## make sure user can't post with "private security" on communities they don't manage
    return fail( $err, 106 )
        if $ownerid != $posterid && # community post
           $req->{'security'} eq "private" &&
           ! $u->can_manage( $uowner );

    # make sure this user isn't banned from posting here (if
    # this is a community journal)
    return fail($err,151) if $uowner->has_banned( $u );

    # don't allow backdated posts in communities
    return fail($err,152) if
        ( $req->{props}->{opt_backdated} &&
         ! $importer_bypass && $uowner->is_community );

    # do processing of embedded polls (doesn't add to database, just
    # does validity checking)
    my @polls = ();
    if (LJ::Poll->contains_new_poll(\$event))
    {
        return fail($err,301,"Your account type doesn't permit creating polls.")
            unless ( $u->can_create_polls
                    || ( $uowner->is_community && $uowner->can_create_polls ) );

        my $error = "";
        @polls = LJ::Poll->new_from_html(\$event, \$error, {
            'journalid' => $ownerid,
            'posterid' => $posterid,
        });
        return fail($err,103,$error) if $error;
    }

    # convert RTE lj-embeds to normal lj-embeds
    $event = LJ::EmbedModule->transform_rte_post($event);

    # process module embedding
    LJ::EmbedModule->parse_module_embed($uowner, \$event);

    my $now = $dbcm->selectrow_array("SELECT UNIX_TIMESTAMP()");
    my $anum  = int(rand(256));

    # by default we record the true reverse time that the item was entered.
    # however, if backdate is on, we put the reverse time at the end of time
    # (which makes it equivalent to 1969, but get_recent_items will never load
    # it... where clause there is: < $LJ::EndOfTime).  but this way we can
    # have entries that don't show up on friends view, now that we don't have
    # the hints table to not insert into.
    my $rlogtime = $LJ::EndOfTime;
    unless ($req->{'props'}->{"opt_backdated"}) {
        $rlogtime -= $now;
    }
    my $logtime = "FROM_UNIXTIME($now)";

    # this is when the entry was posted. for most cases this is accurate but in case
    # we're using the importer in the community case, it will mess life up.
    if ( $importer_bypass && $posterid != $ownerid ) {
        $logtime = $qeventtime;
        $rlogtime = "$LJ::EndOfTime - UNIX_TIMESTAMP($qeventtime)";
    }

    my $dupsig = Digest::MD5::md5_hex(join('', map { $req->{$_} }
                                           qw(subject event usejournal security allowmask)));
    my $lock_key = "post-$ownerid";

    # release our duplicate lock
    my $release = sub {  $dbcm->do("SELECT RELEASE_LOCK(?)", undef, $lock_key); };

    # our own local version of fail that releases our lock first
    my $fail = sub { $release->(); return fail(@_); };

    my $res = {};
    my $res_done = 0;  # set true by getlock when post was duplicate, or error getting lock

    my $getlock = sub {
        my $r = $dbcm->selectrow_array("SELECT GET_LOCK(?, 2)", undef, $lock_key);
        unless ($r) {
            $res = undef;    # a failure case has an undef result
            fail($err,503);  # set error flag to "can't get lock";
            $res_done = 1;   # tell caller to bail out
            return;
        }

        # If we're the importer, don't do duplicate detection here; the importer already
        # has tooling to do that to compare remote vs local
        return if $importer_bypass;

        my @parts = split(/:/, $u->{'dupsig_post'});
        if ($parts[0] eq $dupsig) {
            # duplicate!  let's make the client think this was just the
            # normal first response.
            $res->{'itemid'} = $parts[1];
            $res->{'anum'} = $parts[2];

            my $dup_entry = LJ::Entry->new($uowner, jitemid => $res->{'itemid'}, anum => $res->{'anum'});
            $res->{'url'} = $dup_entry->url;

            $res_done = 1;
            $release->();
        }
    };

    # if posting to a moderated community, store and bail out here
    if ($uowner->is_community && $uowner->{'moderated'} && !$flags->{'nomod'}) {
        # Don't moderate pre-approved users
        my $dbh = LJ::get_db_writer();
        my $relcount = $dbh->selectrow_array("SELECT COUNT(*) FROM reluser ".
                                             "WHERE userid=$ownerid AND targetid=$posterid ".
                                             "AND type IN ('N')");
        unless ($relcount) {
            # moderation queue full?
            my $modcount = $dbcm->selectrow_array("SELECT COUNT(*) FROM modlog WHERE journalid=$ownerid");
            return fail($err, 407) if $modcount >= $uowner->count_max_mod_queue;

            $modcount = $dbcm->selectrow_array("SELECT COUNT(*) FROM modlog ".
                                               "WHERE journalid=$ownerid AND posterid=$posterid");
            return fail($err, 408) if $modcount >= $uowner->count_max_mod_queue_per_poster;

            $req->{'_moderate'}->{'authcode'} = LJ::make_auth_code(15);

            # create tag <lj-embed> from HTML-tag <embed>
            LJ::EmbedModule->parse_module_embed($uowner, \$req->{event});

            my $fr = $dbcm->quote(Storable::freeze($req));
            return fail($err, 409) if length($fr) > 600_000;

            # store
            my $modid = LJ::alloc_user_counter($uowner, "M");
            return fail($err, 501) unless $modid;

            $uowner->do("INSERT INTO modlog (journalid, modid, posterid, subject, logtime) ".
                        "VALUES ($ownerid, $modid, $posterid, ?, NOW())", undef,
                        LJ::text_trim($req->{'subject'}, 30, 0));
            return fail($err, 501) if $uowner->err;

            $uowner->do("INSERT INTO modblob (journalid, modid, request_stor) ".
                        "VALUES ($ownerid, $modid, $fr)");
            if ($uowner->err) {
                $uowner->do("DELETE FROM modlog WHERE journalid=$ownerid AND modid=$modid");
                return fail($err, 501);
            }

            # expire mod_queue_count memcache
            $uowner->memc_delete( 'mqcount' );

            # alert moderator(s)
            my $mods = LJ::load_rel_user($dbh, $ownerid, 'M') || [];

            if (@$mods) {
                my $modlist = LJ::load_userids(@$mods);

                my @emails;
                my $ct;
                foreach my $mod (values %$modlist) {
                    last if $ct > 20;  # don't send more than 20 emails.

                    next unless $mod->is_visible;

                    LJ::Event::CommunityModeratedEntryNew->new( $mod, $uowner, $modid )->fire;
                }
            }

            my $msg = translate($u, "modpost", undef);
            return { 'message' => $msg };
        }
    } # /moderated comms

    # posting:

    $getlock->(); return $res if $res_done;

    # do rate-checking
    if ( ! $u->is_syndicated && ! $u->rate_log( "post", 1 ) && ! $importer_bypass ) {
        return $fail->($err,405);
    }

    my $jitemid = LJ::alloc_user_counter($uowner, "L");
    return $fail->($err,501,"No itemid could be generated.") unless $jitemid;

    LJ::Entry->can("dostuff");
    LJ::replycount_do($uowner, $jitemid, "init");

    my $dberr;
    $uowner->log2_do(\$dberr, "INSERT INTO log2 (journalid, jitemid, posterid, eventtime, logtime, security, ".
                     "allowmask, replycount, year, month, day, revttime, rlogtime, anum) ".
                     "VALUES ($ownerid, $jitemid, $posterid, $qeventtime, $logtime, $qsecurity, $qallowmask, ".
                     "0, $req->{'year'}, $req->{'mon'}, $req->{'day'}, $LJ::EndOfTime-".
                     "UNIX_TIMESTAMP($qeventtime), $rlogtime, $anum)");
    return $fail->($err,501,$dberr) if $dberr;

    LJ::MemCache::incr([$ownerid, "log2ct:$ownerid"]);
    $uowner->clear_daycounts( $qallowmask || $security );

    # set userprops.
    {
        my %set_userprop;

        # keep track of itemid/anum for later potential duplicates
        $set_userprop{"dupsig_post"} = "$dupsig:$jitemid:$anum";

        # record the eventtime of the last update (for own journals only)
        $set_userprop{"newesteventtime"} = $eventtime
            if $posterid == $ownerid and not $req->{'props'}->{'opt_backdated'} and not $time_was_faked;

        $u->set_prop( \%set_userprop );
    }

    # end duplicate locking section
    $release->();

    my $ditemid = $jitemid * 256 + $anum;

    ### finish embedding stuff now that we have the itemid
    {
        ### this should NOT return an error, and we're mildly fucked by now
        ### if it does (would have to delete the log row up there), so we're
        ### not going to check it for now.

        my $error = "";
        foreach my $poll (@polls) {
            $poll->save_to_db(
                              journalid => $ownerid,
                              posterid  => $posterid,
                              ditemid   => $ditemid,
                              error     => \$error,
                              );

            my $pollid = $poll->pollid;

            $event =~ s/<poll-placeholder>/<poll-$pollid>/;
        }
    }
    #### /embedding

    # record journal's disk usage
    my $bytes = length($event) + length($req->{'subject'});
    $uowner->dudata_set('L', $jitemid, $bytes);

    $uowner->do("INSERT INTO logtext2 (journalid, jitemid, subject, event) ".
                "VALUES ($ownerid, $jitemid, ?, ?)", undef, $req->{'subject'},
                LJ::text_compress($event));
    if ($uowner->err) {
        my $msg = $uowner->errstr;
        LJ::delete_entry($uowner, $jitemid);   # roll-back
        return fail($err,501,"logtext:$msg");
    }
    LJ::MemCache::set([$ownerid,"logtext:$clusterid:$ownerid:$jitemid"],
                      [ $req->{'subject'}, $event ]);

    # warn the user of any bad markup errors
    my $clean_event = $event;
    my $errref;
    LJ::CleanHTML::clean_event( \$clean_event, { errref => \$errref } );
    $res->{message} = translate( $u, $errref, { aopts => "href='$LJ::SITEROOT/editjournal?journal=" . $uowner->user . "&itemid=$ditemid'" } ) if $errref;

    # keep track of custom security stuff in other table.
    if ($uselogsec) {
        $uowner->do("INSERT INTO logsec2 (journalid, jitemid, allowmask) ".
                    "VALUES ($ownerid, $jitemid, $qallowmask)");
        if ($uowner->err) {
            my $msg = $uowner->errstr;
            LJ::delete_entry($uowner, $jitemid);   # roll-back
            return fail($err,501,"logsec2:$msg");
        }
    }

    # Entry tags
    if ( $req->{props} && defined $req->{props}->{taglist} && $req->{props}->{taglist} ne '' ) {
        # slightly misnamed, the taglist is/was normally a string, but now can also be an arrayref.
        my $taginput = $req->{props}->{taglist};

        my $tagerr = "";
        my $logtag_opts = {
            remote => $u,
            ignore_max => $flags->{ignore_tags_max} ? 1 : 0,
            force => $importer_bypass,
            err_ref => \$tagerr,
        };

        if (ref $taginput eq 'ARRAY') {
            $logtag_opts->{set} = [@$taginput];
            $req->{props}->{taglist} = join(", ", @$taginput);
        } else {
            $logtag_opts->{set_string} = $taginput;
        }

        # Do not fail here; worst case we lose tags, but if we fail here we don't perform
        # half of the processing below
        LJ::Tags::update_logtags($uowner, $jitemid, $logtag_opts);

        # Propagate any "skippable" errors
        $res->{message} = $tagerr if $tagerr;
    }

    # meta-data
    if (%{$req->{'props'}}) {
        my $propset = {};
        foreach my $pname (keys %{$req->{'props'}}) {
            next unless $req->{'props'}->{$pname};
            next if $pname eq "revnum" || $pname eq "revtime";
            my $p = LJ::get_prop("log", $pname);
            next unless $p;
            next unless $req->{'props'}->{$pname};
            $propset->{$pname} = $req->{'props'}->{$pname};
        }
        my %logprops;
        LJ::set_logprop($uowner, $jitemid, $propset, \%logprops) if %$propset;

        # if set_logprop modified props above, we can set the memcache key
        # to be the hashref of modified props, since this is a new post
        LJ::MemCache::set([$uowner->{'userid'}, "logprop:$uowner->{'userid'}:$jitemid"],
                          \%logprops) if %logprops;
    }

    $dbh->do("UPDATE userusage SET timeupdate=NOW(), lastitemid=$jitemid ".
             "WHERE userid=$ownerid") unless $flags->{'notimeupdate'};
    LJ::MemCache::set([$ownerid, "tu:$ownerid"], pack("N", time()), 30*60);

    # argh, this is all too ugly.  need to unify more postpost stuff into async
    $u->invalidate_directory_record;

    # Insert the slug (try to, this will fail if this slug is already used)
    my $slug = LJ::canonicalize_slug( $req->{slug} );
    if ( defined $slug && length $slug > 0 ) {
        $u->do( 'INSERT INTO logslugs (journalid, jitemid, slug) VALUES (?, ?, ?)',
                undef, $ownerid, $jitemid, $slug );
        if ( $u->err ) {
            $res->{message} ||= 'Sorry, it looks like that slug has already been used. ' .
                'Your entry has been posted without a slug, but you can still edit it to add a unique slug.';
        }
    }

    # if the post was public, and the user has not opted out, try to insert into the random table;
    # We're doing a REPLACE INTO because chances are the user will already
    # be in there (having posted less than 7 days ago).
    if ($security eq 'public' && ! $u->prop('latest_optout')) {
        $u->do("REPLACE INTO random_user_set (posttime, userid, journaltype) VALUES (UNIX_TIMESTAMP(), ?, ?)",
               undef, $uowner->{userid}, $uowner->{journaltype});
    }

    my @jobs;  # jobs to add into TheSchwartz

    my $entry = LJ::Entry->new($uowner, jitemid => $jitemid, anum => $anum);

    if ( $u->equals( $uowner ) && $req->{xpost} ne '0' && ! $flags->{no_xpost} ) {
        schedule_xposts( $u, $ditemid, 0, sub { ((shift)->xpostbydefault, {}) } );
    }

    # run local site-specific actions
    LJ::Hooks::run_hooks("postpost", {
        'itemid'    => $jitemid,
        'anum'      => $anum,
        'journal'   => $uowner,
        'poster'    => $u,
        'event'     => $event,
        'eventtime' => $eventtime,
        'subject'   => $req->{'subject'},
        'security'  => $security,
        'allowmask' => $qallowmask,
        'props'     => $req->{'props'},
        'entry'     => $entry,
        'jobs'      => \@jobs,  # for hooks to push jobs onto
    });

    # cluster tracking
    LJ::mark_user_active($u, 'post');
    LJ::mark_user_active($uowner, 'post') unless $u->equals( $uowner );

    DW::Stats::increment( 'dw.action.entry.post', 1,
            [ 'journal_type:' . $uowner->journaltype_readable ] );

    $res->{'itemid'} = $jitemid;  # by request of mart
    $res->{'anum'} = $anum;
    $res->{'url'} = $entry->url;

    # if the caller told us not to fire events (importer?) then skip the user events,
    # but still fire the logging events
    unless ( $flags->{nonotify} ) {
        push @jobs, LJ::Event::JournalNewEntry->new($entry)->fire_job;
        push @jobs, LJ::Event::OfficialPost->new($entry)->fire_job if $uowner->is_official;

        # latest posts feed update
        DW::LatestFeed->new_item( $entry );
    }

    # update the sphinx search engine
    if ( @LJ::SPHINX_SEARCHD && !$importer_bypass ) {
        push @jobs, TheSchwartz::Job->new_from_array(
                'DW::Worker::Sphinx::Copier',
                { userid => $uowner->id, jitemid => $jitemid, source => "entrynew" }
            );
    }

    my $sclient = LJ::theschwartz();
    if ($sclient && @jobs) {
        my @handles = $sclient->insert_jobs(@jobs);
        # TODO: error on failure?  depends on the job I suppose?  property of the job?
    }

    # To minimize impact on legacy code, let's make sure the entry object in
    # memory has been populated with data. Easiest way to do that is to call
    # one of the methods that loads the relevant row from the database.
    $entry->valid;

    return $res;
}

sub editevent
{
    my ($req, $err, $flags) = @_;
    my $res = {};
    my $deleted = 0;
    un_utf8_request($req);

    my $add_message = sub {
        my $new_message = shift;
        if ( $res->{message} ) {
            $res->{message} .= "\n\n" . $new_message;
        } else {
            $res->{message} = $new_message;
        }
    };

    return undef unless authenticate($req, $err, $flags);

    # we check later that user owns entry they're modifying, so all
    # we care about for check_altusage is that the target journal
    # exists, and we want it to setup some data in $flags.
    $flags->{'ignorecanuse'} = 1;
    return undef unless check_altusage($req, $err, $flags);

    my $u = $flags->{'u'};
    my $ownerid = $flags->{'ownerid'};
    my $uowner = $flags->{'u_owner'} || $u;
    # Make sure we have a user object here
    $uowner = LJ::want_user($uowner) unless LJ::isu($uowner);
    my $clusterid = $uowner->{'clusterid'};
    my $posterid = $u->{'userid'};
    my $qallowmask = $req->{'allowmask'}+0;
    my $sth;

    my $itemid = $req->{'itemid'}+0;

    # check the journal's read-only bit
    return fail($err,306) if $uowner->is_readonly;

    # can't edit in deleted/suspended community
    return fail($err,307) unless $uowner->is_visible || $uowner->is_readonly;

    my $dbcm = LJ::get_cluster_master($uowner);
    return fail($err,306) unless $dbcm;

    # can't specify both a custom security and 'friends-only'
    return fail($err, 203, "Invalid friends group security set.")
        if $qallowmask > 1 && $qallowmask % 2;

    ### make sure user can't post with "custom security" on communities
    return fail($err,102)
        if $ownerid != $posterid && # community post
           $req->{'security'} eq "usemask" && $qallowmask != 1;

    ## make sure user can't post with "private security" on communities they don't manage
    return fail( $err, 106 )
        if $ownerid != $posterid && # community post
           $req->{'security'} eq "private" &&
           ! $u->can_manage( $uowner );

    # make sure the new entry's under the char limit
    # NOTE: as in postevent, this requires $req->{event} to be binary data
    # but we've already removed the utf-8 flag in the XML-RPC path, and it
    # never gets set in the "flat" protocol path
    return fail($err,409) if length($req->{event}) >= LJ::BMAX_EVENT;

    # fetch the old entry from master database so we know what we
    # really have to update later.  usually people just edit one part,
    # not every field in every table.  reads are quicker than writes,
    # so this is worth it.
    my $oldevent = $dbcm->selectrow_hashref
        ("SELECT journalid AS 'ownerid', posterid, eventtime, logtime, ".
         "compressed, security, allowmask, year, month, day, ".
         "rlogtime, anum FROM log2 WHERE journalid=$ownerid AND jitemid=$itemid");

    my $ditemid = $itemid * 256 + $oldevent->{anum};

    ($oldevent->{subject}, $oldevent->{event}) = $dbcm->selectrow_array
        ("SELECT subject, event FROM logtext2 ".
         "WHERE journalid=$ownerid AND jitemid=$itemid");

    LJ::text_uncompress(\$oldevent->{'event'});

    # use_old_content indicates the subject and entry are not changing
    if ($flags->{'use_old_content'}) {
        $req->{'event'} = $oldevent->{event};
        $req->{'subject'} = $oldevent->{subject};
    }

    # kill seconds in eventtime, since we don't use it, then we can use 'eq' and such
    $oldevent->{'eventtime'} =~ s/:00$//;

    ### make sure this user is allowed to edit this entry
    return fail($err,302)
        unless ($ownerid == $oldevent->{'ownerid'});

    ### load existing meta-data
    my %curprops;
    LJ::load_log_props2($dbcm, $ownerid, [ $itemid ], \%curprops);

    # xpost helper for later
    my $schedule_xposts = sub {
        my $xpost_string = $curprops{$itemid}->{xpost};
        if ( $xpost_string && $u->equals( $uowner ) && $req->{xpost} ne '0' ) {
            my $xpost_info = DW::External::Account->xpost_string_to_hash( $xpost_string );
            schedule_xposts( $u, $ditemid, $deleted,
                             sub { ($xpost_info->{(shift)->acctid}, {}) } );
        }
    };

    ### what can they do to somebody elses entry?  (in shared journal)
    ### can edit it if they own or maintain the journal, but not if the journal is read-only
    if ($posterid != $oldevent->{'posterid'} || $u->is_readonly || $uowner->is_readonly)
    {
        ## deleting.
        return fail($err,304)
            if $req->{'event'} !~ /\S/ && ! $u->can_manage( $uowner );

        ## editing:
        if ($req->{'event'} =~ /\S/) {
            return fail($err,303) if $posterid != $oldevent->{'posterid'};
            return fail($err,318) if $u->is_readonly;
            return fail($err,319) if $uowner->is_readonly;
        }
    }

    # simple logic for deleting an entry
    if (!$flags->{'use_old_content'} && $req->{'event'} !~ /\S/)
    {
        $deleted = 1;

        # if their newesteventtime prop equals the time of the one they're deleting
        # then delete their newesteventtime.
        if ( $u->equals( $uowner ) ) {
            $u->preload_props( { use_master => 1 }, "newesteventtime" );
            if ($u->{'newesteventtime'} eq $oldevent->{'eventtime'}) {
                $u->set_prop( "newesteventtime", undef );
            }
        }

        # log this event, unless noauth is on, which means it is being done internally and we should
        # rely on them to log why they're deleting the entry if they need to.  that way we don't have
        # double entries, and we have as much information available as possible at the location the
        # delete is initiated.
        $uowner->log_event('delete_entry', {
                remote => $u,
                actiontarget => $ditemid,
                method => 'protocol',
            })
            unless $flags->{noauth};

        LJ::delete_entry($uowner, $req->{'itemid'}, 'quick', $oldevent->{'anum'});

        # clear their duplicate protection, so they can later repost
        # what they just deleted.  (or something... probably rare.)
        $u->set_prop( "dupsig_post", undef );
        $uowner->clear_daycounts( $qallowmask || $req->{security} );

        # pass the delete
        $schedule_xposts->();

        $res = { itemid => $itemid, anum => $oldevent->{anum} };
        return $res;
    }

    # now make sure the new entry text isn't $CannotBeShown
    return fail($err, 210)
        if $req->{event} eq $CannotBeShown;

    # don't allow backdated posts in communities... unless this is an import
    if ( $req->{props}->{opt_backdated} && $uowner->is_community ) {
        return fail($err, 152)
            unless $curprops{$itemid}->{import_source};
    }

    # make year/mon/day/hour/min optional in an edit event,
    # and just inherit their old values
    {
        $oldevent->{'eventtime'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)/;
        $req->{'year'} = $1 unless defined $req->{'year'};
        $req->{'mon'} = $2+0 unless defined $req->{'mon'};
        $req->{'day'} = $3+0 unless defined $req->{'day'};
        $req->{'hour'} = $4+0 unless defined $req->{'hour'};
        $req->{'min'} = $5+0 unless defined $req->{'min'};
    }

    # updating an entry:
    return undef
        unless common_event_validation($req, $err, $flags);

    # now we can move over to picture_mapid instead of picture_keyword if appropriate
    if ( $req->{props} && defined $req->{props}->{picture_keyword} && $u->userpic_have_mapid ) {
        $req->{props}->{picture_mapid} = '';
        $req->{props}->{picture_mapid} = $u->get_mapid_from_keyword( $req->{props}->{picture_keyword}, create => $flags->{create_unknown_picture_mapid} || 0 )
            if defined $req->{props}->{picture_keyword};
        delete $req->{props}->{picture_keyword};
    }

    ## handle meta-data (properties)
    my %props_byname = ();
    foreach my $key (keys %{$req->{'props'}}) {
        ## changing to something else?
        if ($curprops{$itemid}->{$key} ne $req->{'props'}->{$key}) {
            $props_byname{$key} = $req->{'props'}->{$key};
        }
    }

    # additionally, if the 'opt_nocomments_maintainer' prop was set before and the poster now sets
    # 'opt_nocomments' to 0 again, 'opt_nocomments_maintainer' should be set to 0 again, as well
    # so comments are enabled again
    $req->{props}->{opt_nocomments_maintainer} = 0
        if defined $req->{props}->{opt_nocomments} && !$req->{props}->{opt_nocomments};

    my $event = $req->{'event'};
    my $owneru = LJ::load_userid($ownerid);
    $event = LJ::EmbedModule->transform_rte_post($event);
    LJ::EmbedModule->parse_module_embed($owneru, \$event);

    my $bytes = length($event) + length($req->{'subject'});

    my $eventtime = sprintf("%04d-%02d-%02d %02d:%02d",
                            map { $req->{$_} } qw(year mon day hour min));
    my $qeventtime = $dbcm->quote($eventtime);

    # preserve old security by default, use user supplied if it's understood
    my $security = $oldevent->{security};
    $security = $req->{security}
        if $req->{security} &&
           $req->{security} =~ /^(?:public|private|usemask)$/;

    my $do_tags = $req->{props} && defined $req->{props}->{taglist};
    my $do_tags_security;
    my $entry_tags;

    if ($oldevent->{security} ne $security || $qallowmask != $oldevent->{allowmask}) {
        # FIXME: this is a hopefully temporary hack which deletes tags from the entry
        # when the security has changed.  the real fix is to make update_logtags aware
        # of security changes so it can update logkwsum appropriately.

        # we need to fix security on this entry's tags; if the user didn't give us a
        # tag list to work with, we use the existing tags on this entry
        unless ( $do_tags ) {
            $entry_tags  = LJ::Tags::get_logtags($uowner, $itemid);
            $entry_tags = $entry_tags->{$itemid};
            $entry_tags = join(',', sort values %{$entry_tags || {}});
            $req->{props}->{taglist} = $entry_tags;
        }

        # FIXME: temporary hack until we can make update_logtags recognize entry security edits
        if ( LJ::Tags::can_control_tags( $uowner, $u ) || LJ::Tags::can_add_tags( $uowner, $u ) ) {
            my $delete = LJ::Tags::delete_logtags( $uowner, $itemid );
            $do_tags_security = 1;
        }
    }

    my $qyear = $req->{'year'}+0;
    my $qmonth = $req->{'mon'}+0;
    my $qday = $req->{'day'}+0;

    if ($eventtime ne $oldevent->{'eventtime'} ||
        $security ne $oldevent->{'security'} ||
        (!$curprops{$itemid}->{opt_backdated} && $req->{props}{opt_backdated}) ||
        $qallowmask != $oldevent->{'allowmask'})
    {
        # are they changing their most recent post?
        if ( $u->equals( $uowner ) &&
            $u->prop( "newesteventtime" ) eq $oldevent->{eventtime} ) {

            if ( ! $curprops{$itemid}->{opt_backdated} && $req->{props}{opt_backdated} ) {
                # if they set the backdated flag, then we no longer know
                # the newesteventtime.
                $u->set_prop( "newesteventtime", undef );
            } elsif ( $eventtime ne $oldevent->{eventtime} ) {
                # otherwise, if they changed time on this event,
                # the newesteventtime is this event's new time.
                $u->set_prop( "newesteventtime", $eventtime );
            }
        }

        my $qsecurity = $uowner->quote($security);
        my $dberr;
        $uowner->log2_do(\$dberr, "UPDATE log2 SET eventtime=$qeventtime, revttime=$LJ::EndOfTime-".
                         "UNIX_TIMESTAMP($qeventtime), year=$qyear, month=$qmonth, day=$qday, ".
                         "security=$qsecurity, allowmask=$qallowmask WHERE journalid=$ownerid ".
                         "AND jitemid=$itemid");
        return fail($err,501,$dberr) if $dberr;

        # update memcached
        my $sec = $qallowmask;
        $sec = 0 if $security eq 'private';
        $sec = $LJ::PUBLICBIT if $security eq 'public';

        my $row = pack($LJ::LOGMEMCFMT, $oldevent->{'posterid'},
                       LJ::mysqldate_to_time($eventtime, 1),
                       LJ::mysqldate_to_time($oldevent->{'logtime'}, 1),
                       $sec,
                       $ditemid);

        LJ::MemCache::set([$ownerid, "log2:$ownerid:$itemid"], $row);

    }

    if ($security ne $oldevent->{'security'} ||
        $qallowmask != $oldevent->{'allowmask'})
    {
        if ($security eq "public" || $security eq "private") {
            $uowner->do("DELETE FROM logsec2 WHERE journalid=$ownerid AND jitemid=$itemid");
        } else {
            $uowner->do("REPLACE INTO logsec2 (journalid, jitemid, allowmask) ".
                        "VALUES ($ownerid, $itemid, $qallowmask)");
        }
        return fail($err,501,$dbcm->errstr) if $uowner->err;
    }

    LJ::MemCache::set([$ownerid,"logtext:$clusterid:$ownerid:$itemid"],
                      [ $req->{'subject'}, $event ]);

    if (!$flags->{'use_old_content'} && (
        $event ne $oldevent->{'event'} ||
        $req->{'subject'} ne $oldevent->{'subject'}))
    {
        $uowner->do("UPDATE logtext2 SET subject=?, event=? ".
                    "WHERE journalid=$ownerid AND jitemid=$itemid", undef,
                    $req->{'subject'}, LJ::text_compress($event));
        return fail($err,501,$uowner->errstr) if $uowner->err;

        # update disk usage
        $uowner->dudata_set('L', $itemid, $bytes);
    }

    my $clean_event = $event;
    my $errref;
    LJ::CleanHTML::clean_event( \$clean_event, { errref => \$errref } );
    $add_message->( translate( $u, $errref, { aopts => "href='$LJ::SITEROOT/editjournal?journal=" . $uowner->user . "&itemid=$ditemid'" } ) ) if $errref;

    # up the revision number
    $req->{'props'}->{'revnum'} = ($curprops{$itemid}->{'revnum'} || 0) + 1;
    $req->{'props'}->{'revtime'} = time();

    if ( $do_tags ) {
        # we only want to update the tags if they've been modified
        # so load the original entry tags
        unless ( $entry_tags ) {
            $entry_tags  = LJ::Tags::get_logtags($uowner, $itemid);
            $entry_tags = $entry_tags->{$itemid};
            $entry_tags = join(',', sort values %{$entry_tags || {}});
        }

        my $request_tags = [];
        LJ::Tags::is_valid_tagstring( $req->{props}->{taglist}, $request_tags );
        $request_tags = join( ",", sort @{ $request_tags || [] } );
        $do_tags = ( $request_tags ne $entry_tags );
    }

    # handle tags if they're defined
    if ( $do_tags || $do_tags_security ) {
        my $tagerr = "";
        my $rv = LJ::Tags::update_logtags($uowner, $itemid, {
                set_string => $req->{props}->{taglist},
                remote => $u,
                err_ref => \$tagerr,
            });

        # we only want to warn if we tried to edit the tags, not if we just tried to edit the security
        $add_message->( $tagerr ) if $tagerr && $do_tags;
    }

    # handle the props
    {
        my $propset = {};
        foreach my $pname (keys %{$req->{'props'}}) {
            my $p = LJ::get_prop("log", $pname);
            next unless $p;
            $propset->{$pname} = $req->{'props'}->{$pname};
        }
        LJ::set_logprop($uowner, $itemid, $propset);
    }

    # deal with backdated changes.  if the entry's rlogtime is
    # $EndOfTime, then it's backdated.  if they want that off, need to
    # reset rlogtime to real reverse log time.  also need to set
    # rlogtime to $EndOfTime if they're turning backdate on.
    if ($req->{'props'}->{'opt_backdated'} eq "1" &&
        $oldevent->{'rlogtime'} != $LJ::EndOfTime) {
        my $dberr;
        $uowner->log2_do(undef, "UPDATE log2 SET rlogtime=$LJ::EndOfTime WHERE ".
                         "journalid=$ownerid AND jitemid=$itemid");
        return fail($err,501,$dberr) if $dberr;
    }
    if ($req->{'props'}->{'opt_backdated'} eq "0" &&
        $oldevent->{'rlogtime'} == $LJ::EndOfTime) {
        my $dberr;
        $uowner->log2_do(\$dberr, "UPDATE log2 SET rlogtime=$LJ::EndOfTime-UNIX_TIMESTAMP(logtime) ".
                         "WHERE journalid=$ownerid AND jitemid=$itemid");
        return fail($err,501,$dberr) if $dberr;
    }
    return fail($err,501,$dbcm->errstr) if $dbcm->err;

    $uowner->clear_daycounts( $oldevent->{allowmask} + 0 || $oldevent->{security}, $qallowmask || $security );

    # Update the slug (try to, this will fail if this slug is already used). To
    # delete or change the slug, you must pass this parameter in. If it is not
    # present, we leave the slug alone.
    if ( exists $req->{slug} ) {
        LJ::MemCache::delete( [ $ownerid, "logslug:$ownerid:$itemid" ] );
        $u->do( 'DELETE FROM logslugs WHERE journalid = ? AND jitemid = ?',
                     undef, $ownerid, $itemid );

        my $slug = LJ::canonicalize_slug( $req->{slug} );
        if ( defined $slug && length $slug > 0 ) {
            $u->do( 'INSERT INTO logslugs (journalid, jitemid, slug) VALUES (?, ?, ?)',
                    undef, $ownerid, $itemid, $slug );
            if ( $u->err ) {
                $add_message->( 'Sorry, it looks like that slug has already been used. ' .
                    'Your entry has been updated, but you can still edit it again to add a unique slug.' );
            }
        }
    }

    my $entry = LJ::Entry->new($ownerid, jitemid => $itemid);

    $res->{itemid} = $itemid;
    if (defined $oldevent->{'anum'}) {
        $res->{'anum'} = $oldevent->{'anum'};
        $res->{'url'} = $entry->url;
    }

    DW::Stats::increment( 'dw.action.entry.edit', 1,
            [ 'journal_type:' . $uowner->journaltype_readable ] );

    # fired to copy the post over to the Sphinx search database
    if ( @LJ::SPHINX_SEARCHD && ( my $sclient = LJ::theschwartz() ) ) {
        $sclient->insert_jobs( TheSchwartz::Job->new_from_array(
                'DW::Worker::Sphinx::Copier',
                { userid => $ownerid, jitemid => $itemid, source => "entryedt" }
            )
        );
    }

    my @jobs;
    LJ::Hooks::run_hooks( "editpost", $entry, \@jobs );

    my $sclient = LJ::theschwartz();
    if ( $sclient && @jobs ) {
        my @handles = $sclient->insert_jobs(@jobs);
        # TODO: error on failure?  depends on the job I suppose?  property of the job?
    }

    # ensure our xposted edit fires
    $schedule_xposts->();

    return $res;
}

sub getevents
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    return undef unless check_altusage($req, $err, $flags);

    my $u = $flags->{'u'};
    my $uowner = $flags->{'u_owner'} || $u;

    ### shared-journal support
    my $posterid = $u->{'userid'};
    my $ownerid = $flags->{'ownerid'};

    my $dbr = LJ::get_db_reader();
    my $sth;

    my $dbcr =  LJ::get_cluster_reader($uowner);
    return fail($err,502) unless $dbcr && $dbr;

    # can't pull events from deleted/suspended journal
    return fail($err,307) unless $uowner->is_visible || $uowner->is_readonly;

    my $reject_code = $LJ::DISABLE_PROTOCOL{getevents};
    if (ref $reject_code eq "CODE") {
        my $apache_r = eval { BML::get_request() };
        my $errmsg = $reject_code->($req, $flags, $apache_r);
        if ($errmsg) { return fail($err, "311", $errmsg); }
    }

    # if this is on, we sort things different (logtime vs. posttime)
    # to avoid timezone issues
    my $is_community = $uowner->is_community;

    # in some cases we'll use the master, to ensure there's no
    # replication delay.  useful cases: getting one item, use master
    # since user might have just made a typo and realizes it as they
    # post, or wants to append something they forgot, etc, etc.  in
    # other cases, slave is pretty sure to have it.
    my $use_master = 0;

    # the benefit of this mode over actually doing 'lastn/1' is
    # the $use_master usage.
    if ($req->{'selecttype'} eq "one" && $req->{'itemid'} eq "-1") {
        $req->{'selecttype'} = "lastn";
        $req->{'howmany'} = 1;
        undef $req->{'itemid'};
        $use_master = 1;  # see note above.
    }

    # build the query to get log rows.  each selecttype branch is
    # responsible for either populating the following 3 variables
    # OR just populating $sql
    my ($orderby, $where, $limit);
    my $sql;
    if ($req->{'selecttype'} eq "day")
    {
        return fail($err,203)
            unless ($req->{'year'} =~ /^\d\d\d\d$/ &&
                    $req->{'month'} =~ /^\d\d?$/ &&
                    $req->{'day'} =~ /^\d\d?$/ &&
                    $req->{'month'} >= 1 && $req->{'month'} <= 12 &&
                    $req->{'day'} >= 1 && $req->{'day'} <= 31);

        my $qyear = $dbr->quote($req->{'year'});
        my $qmonth = $dbr->quote($req->{'month'});
        my $qday = $dbr->quote($req->{'day'});
        $where = "AND year=$qyear AND month=$qmonth AND day=$qday";
        $limit = "LIMIT 200";  # FIXME: unhardcode this constant (also in ljviews.pl)

        # see note above about why the sort order is different
        $orderby = $is_community ? "ORDER BY logtime" : "ORDER BY eventtime";
    }
    elsif ($req->{'selecttype'} eq "lastn")
    {
        my $howmany = $req->{'howmany'} || 20;
        if ($howmany > 50) { $howmany = 50; }
        $howmany = $howmany + 0;
        $limit = "LIMIT $howmany";

        # okay, follow me here... see how we add the revttime predicate
        # even if no beforedate key is present?  you're probably saying,
        # what, huh? -- you're saying: "revttime > 0", that's like
        # saying, "if entry occurred at all."  yes yes, but that hints
        # mysql's optimizer to use the right index.
        my $rtime_after = 0;
        my $rtime_what = $is_community ? "rlogtime" : "revttime";
        if ($req->{'beforedate'}) {
            return fail($err,203,"Invalid beforedate format.")
                unless ($req->{'beforedate'} =~
                        /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$/);
            my $qd = $dbr->quote($req->{'beforedate'});
            $rtime_after = "$LJ::EndOfTime-UNIX_TIMESTAMP($qd)";
        }
        $where .= "AND $rtime_what > $rtime_after ";
        $orderby = "ORDER BY $rtime_what";
    }
    elsif ($req->{'selecttype'} eq "one")
    {
        my $id = $req->{'itemid'} + 0;
        $where = "AND jitemid=$id";
    }
    elsif ($req->{'selecttype'} eq "syncitems")
    {
        return fail($err,506) unless LJ::is_enabled('syncitems');
        my $date = $req->{'lastsync'} || "0000-00-00 00:00:00";
        return fail($err,203,"Invalid syncitems date format")
            unless ($date =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);

        my $now = time();
        # broken client loop prevention
        if ($req->{'lastsync'}) {
            my $pname = "rl_syncitems_getevents_loop";
            # format is:  time/date/time/date/time/date/... so split
            # it into a hash, then delete pairs that are older than an hour
            my %reqs = split( m!/!, $u->prop( $pname ) );
            foreach (grep { $_ < $now - 60*60 } keys %reqs) { delete $reqs{$_}; }
            my $count = grep { $_ eq $date } values %reqs;
            $reqs{$now} = $date;
            if ($count >= 2) {
                # 2 prior, plus this one = 3 repeated requests for same synctime.
                # their client is busted.  (doesn't understand syncitems semantics)
                return fail($err,406);
            }
            $u->set_prop( $pname,
                          join( '/', map { $_, $reqs{$_} }
                                     sort { $b <=> $a } keys %reqs ) );
        }

        my %item;
        $sth = $dbcr->prepare("SELECT jitemid, logtime FROM log2 WHERE ".
                              "journalid=? and logtime > ?");
        $sth->execute($ownerid, $date);
        while (my ($id, $dt) = $sth->fetchrow_array) {
            $item{$id} = $dt;
        }

        my $p_revtime = LJ::get_prop("log", "revtime");
        $sth = $dbcr->prepare("SELECT jitemid, FROM_UNIXTIME(value) ".
                              "FROM logprop2 WHERE journalid=? ".
                              "AND propid=$p_revtime->{'id'} ".
                              "AND value+0 > UNIX_TIMESTAMP(?)");
        $sth->execute($ownerid, $date);
        while (my ($id, $dt) = $sth->fetchrow_array) {
            $item{$id} = $dt;
        }

        my $limit = 100;
        my @ids = sort { $item{$a} cmp $item{$b} } keys %item;
        if (@ids > $limit) { @ids = @ids[0..$limit-1]; }

        my $in = join(',', @ids) || "0";
        $where = "AND jitemid IN ($in)";
    }
    elsif ($req->{'selecttype'} eq "multiple")
    {
        my @ids;
        foreach my $num (split(/\s*,\s*/, $req->{'itemids'})) {
            return fail($err,203,"Non-numeric itemid") unless $num =~ /^\d+$/;
            push @ids, $num;
        }
        my $limit = 100;
        return fail($err,209,"Can't retrieve more than $limit entries at once") if @ids > $limit;
        my $in = join(',', @ids);
        $where = "AND jitemid IN ($in)";
    }
    else
    {
        return fail($err,200,"Invalid selecttype.");
    }

    my $mask = 0;
    if ( $u && ( $u->is_person || $u->is_identity ) && $posterid != $ownerid ) {
        # if this is a community we're viewing, fake the mask to select on, as communities
        # no longer have masks to users
        if ( $uowner->is_community ) {
            $mask = $u->member_of( $uowner ) ? 1 : 0;
        } else {
            $mask = $uowner->trustmask( $u );
        }
    }

    # check security!
    my $secwhere;
    if ( $u && $u->can_manage( $uowner ) ) {
        # journal owners and community admins can see everything
        $secwhere = "";
    } elsif ( $mask ) {
        # can see public or things with them in the mask
        $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $mask != 0))";
    } else {
        # not on access list or a member; only see public.
        $secwhere = "AND security='public'";
    }

    # common SQL template:
    unless ($sql) {
        $sql = "SELECT jitemid, eventtime, logtime, security, allowmask, anum, posterid ".
            "FROM log2 WHERE journalid=$ownerid $where $secwhere $orderby $limit";
    }

    # whatever selecttype might have wanted us to use the master db.
    $dbcr = LJ::get_cluster_def_reader($uowner) if $use_master;

    return fail($err,502) unless $dbcr;

    ## load the log rows
    ($sth = $dbcr->prepare($sql))->execute;
    return fail($err,501,$dbcr->errstr) if $dbcr->err;

    my $count = 0;
    my @itemids = ();
    my $res = {};
    my $events = $res->{events} = [];
    my %evt_from_itemid;

    while (my ($itemid, $eventtime, $logtime, $sec, $mask, $anum, $jposterid) = $sth->fetchrow_array)
    {
        $count++;
        my $evt = {};
        $evt->{itemid} = $itemid;
        push @itemids, $itemid;

        $evt_from_itemid{$itemid} = $evt;

        $evt->{eventtime} = $eventtime;
        $evt->{logtime} = $logtime;
        if ($sec ne "public") {
            $evt->{security} = $sec;
            $evt->{allowmask} = $mask if $sec eq "usemask";
        }
        $evt->{anum} = $anum;
        $evt->{poster} = LJ::get_username( $jposterid )
            if $jposterid != $ownerid;
        $evt->{url} = LJ::item_link( $uowner, $itemid, $anum );
        push @$events, $evt;
    }

    # load properties. Even if the caller doesn't want them, we need
    # them in Unicode installations to recognize older 8bit non-UTF-8
    # entries.
    {
        ### do the properties now
        $count = 0;
        my %props = ();
        LJ::load_log_props2($dbcr, $ownerid, \@itemids, \%props);

        # load the tags for these entries, unless told not to
        unless ($req->{notags}) {
            # construct %idsbycluster for the multi call to get these tags
            my $tags = LJ::Tags::get_logtags($uowner, \@itemids);

            # add to props
            foreach my $itemid (@itemids) {
                next unless $tags->{$itemid};
                $props{$itemid}->{taglist} = join(', ', values %{$tags->{$itemid}});
            }
        }

        foreach my $itemid (keys %props) {
            # 'replycount' is a pseudo-prop, don't send it.
            # FIXME: this goes away after we restructure APIs and
            # replycounts cease being transferred in props
            delete $props{$itemid}->{'replycount'};

            # the xpost property is not something we should be distributing
            # as it's a serialized string and confuses clients
            delete $props{$itemid}->{xpost};

            my $evt = $evt_from_itemid{$itemid};
            $evt->{'props'} = {};
            foreach my $name (keys %{$props{$itemid}}) {
                my $value = $props{$itemid}->{$name};
                $value =~ s/\n/ /g;
                $evt->{'props'}->{$name} = $value;
            }
        }
    }

    ## load the text
    my $text = LJ::DB::cond_no_cache( $use_master, sub {
        return LJ::get_logtext2( $uowner, @itemids );
    } );

    foreach my $i (@itemids)
    {
        my $t = $text->{$i};
        my $evt = $evt_from_itemid{$i};

        # if they want subjects to be events, replace event
        # with subject when requested.
        if ($req->{prefersubject} && length($t->[0])) {
            $t->[1] = $t->[0];  # event = subject
            $t->[0] = undef;    # subject = undef
        }

        # re-generate the picture_keyword prop for the returned data, as a mapid will mean nothing
        my $pu = $uowner;
        $pu = LJ::load_user( $evt->{poster} ) if $evt->{poster};
        $evt->{props}->{picture_keyword} = $pu->get_keyword_from_mapid( $evt->{props}->{picture_mapid} ) if $pu->userpic_have_mapid;

        # now that we have the subject, the event and the props,
        # auto-translate them to UTF-8 if they're not in UTF-8.
        if ( $req->{ver} >= 1 && $evt->{props}->{unknown8bit} ) {
            LJ::item_toutf8($uowner, \$t->[0], \$t->[1], $evt->{props});
            $evt->{converted_with_loss} = 1;
        }

        if ( $req->{'ver'} < 1 && !$evt->{'props'}->{'unknown8bit'} ) {
            unless ( LJ::is_ascii($t->[0]) &&
                     LJ::is_ascii($t->[1]) &&
                     LJ::is_ascii(join(' ', values %{$evt->{'props'}}) )) {
                # we want to fail the client that wants to get this entry
                # but we make an exception for selecttype=day, in order to allow at least
                # viewing the daily summary

                if ($req->{'selecttype'} eq 'day') {
                    $t->[0] = $t->[1] = $CannotBeShown;
                } else {
                    return fail($err,207,"Cannot display/edit a Unicode post with a non-Unicode client. Please see $LJ::SITEROOT/support/encodings for more information.");
                }
            }
        }

        if ($t->[0]) {
            $t->[0] =~ s/[\r\n]/ /g;
            $evt->{'subject'} = $t->[0];
        }

        # truncate
        if ($req->{'truncate'} >= 4) {
            my $original = $t->[1];
            if ($req->{'ver'} > 1) {
                $t->[1] = LJ::text_trim($t->[1], $req->{'truncate'} - 3, 0);
            } else {
                $t->[1] = LJ::text_trim($t->[1], 0, $req->{'truncate'} - 3);
            }
            # only append the elipsis if the text was actually truncated
            $t->[1] .= "..." if $t->[1] ne $original;
        }

        # line endings
        $t->[1] =~ s/\r//g;
        if ($req->{'lineendings'} eq "unix") {
            # do nothing.  native format.
        } elsif ($req->{'lineendings'} eq "mac") {
            $t->[1] =~ s/\n/\r/g;
        } elsif ($req->{'lineendings'} eq "space") {
            $t->[1] =~ s/\n/ /g;
        } elsif ($req->{'lineendings'} eq "dots") {
            $t->[1] =~ s/\n/ ... /g;
        } else { # "pc" -- default
            $t->[1] =~ s/\n/\r\n/g;
        }
        $evt->{'event'} = $t->[1];
    }

    # maybe we don't need the props after all
    if ($req->{'noprops'}) {
        foreach(@$events) { delete $_->{'props'}; }
    }

    return $res;
}

# deprecated
sub editfriends {
    return fail( $_[1], 504 );
}

# deprecated
sub editfriendgroups {
    return fail( $_[1], 504 );
}

sub editcircle
{
    my ( $req, $err, $flags ) = @_;
    return undef unless authenticate( $req, $err, $flags );

    my $u = $flags->{u};
    my $res = {};

    if ( ref $req->{settrustgroups} eq 'HASH' ) {
      while ( my ( $bit, $group ) = each %{$req->{settrustgroups}} ) {
        my $name = $group->{name};
        my $sortorder = $group->{sort};
        my $public = $group->{public};
        my %params = ( id => $bit,
                       groupname => $name,
                       _force_create => 1
                     );

        $params{sortorder} = $sortorder if defined $sortorder;
        $params{is_public} = $public if defined $public;
        $u->edit_trust_group( %params );
      }
    }

    if ( ref $req->{deletetrustgroups} eq 'ARRAY' ) {
      foreach my $bit ( @{$req->{deletetrustgroups}} ) {
        $u->delete_trust_group( id => $bit );
      }
    }

    if ( ref $req->{setcontentfilters} eq 'HASH' ) {
      while ( my ( $bit, $group ) = each %{$req->{setcontentfilters} } ) {
        my $name = $group->{name};
        my $public = $group->{public};
        my $sortorder = $group->{sort};
        my $cf = $u->content_filters( id => $bit );
        if ( $cf ) {
          $cf->name( $name )
            if $name && $name ne $cf->name;
          $cf->public( $public )
            if ( defined $public ) && $public ne $cf->public;
          $cf->sortorder( $sortorder )
            if ( defined $sortorder ) && $sortorder ne $cf->sortorder;
        } else {
          my $fid = $u->create_content_filter( name => $name, public => $public, sortorder => $sortorder );
          my $added = {
                       id => $fid,
                       name => $name,
                      };
          push @{$res->{addedcontentfilters}}, $added;
        }
      }
    }

    if ( ref $req->{deletecontentfilters} eq 'ARRAY' ) {
      foreach my $bit ( @{$req->{deletecontentfilters}} ) {
        $u->delete_content_filter( id => $bit );
      }
    }

    if ( ref $req->{add} eq 'ARRAY' ) {
      foreach my $row ( @{$req->{add}} ) {
        my $other_user = LJ::load_user( $row->{username} );
        return fail( $err, 203 ) unless $other_user;
        my $other_userid = $other_user->{userid};

        if ( defined ( $row->{groupmask} ) ) {
          $u->add_edge( $other_userid, trust => {
                                                 mask => $row->{groupmask},
                                                 nonotify => 1,
                                                } );
        } else {
          if ( $row->{edge} & 1 ) {
            $u->add_edge ( $other_userid, trust => {
                                                    nonotify => $u->trusts ( $other_userid ) ? 1 : 0,
                                                   } );
          } else {
            $u->remove_edge ( $other_userid, trust => {
                                                       nonotify => $u->trusts ( $other_userid ) ? 0 : 1,
                                                      } );
          }
          if ( $row->{edge} & 2 ) {
            my $fg = $row->{fgcolor} || "#000000";
            my $bg = $row->{bgcolor} || "#FFFFFF";
            $u->add_edge ( $other_userid, watch => {
                                                    fgcolor => LJ::color_todb( $fg ),
                                                    bgcolor => LJ::color_todb( $bg ),
                                                    nonotify => $u->watches ( $other_userid ) ? 1 : 0,
                                                   } );
          } else {
            $u->remove_edge ( $other_userid, watch => {
                                                       nonotify => $u->watches ( $other_userid ) ? 0 : 1,
                                                      } );
          }
          if ( $row->{edge} ) {
            my $myid = $u->userid;
            my $added = {
                         username => $other_user->{user},
                         fullname => $other_user->{name},
                         trusted => $u->trusts ( $other_userid ),
                         trustedby => $other_user->trusts ( $myid ),
                         watched => $u->watches ( $other_userid ),
                         watchedby => $other_user->watches ( $myid )
                        };
            push @{$res->{added}}, $added;
          }
        }
      }
    }

    # if ( ref $req->{delete} eq 'ARRAY' ) {
    #   foreach my $row ( @{$req->{delete}} ) {
    #     not implemented yet - maybe unnecessary
    #   }
    # }

    if ( ref $req->{addtocontentfilters} eq 'ARRAY' ) {
      foreach my $row ( @{$req->{addtocontentfilters}} ) {
        my $other_user = LJ::load_user( $row->{username} );
        return fail( $err, 203 ) unless $other_user;
        my $other_userid = $other_user->{userid};
        my $cf = $u->content_filters( id => $row->{id} );
        $cf->add_row( userid => $other_userid ) if $cf;
      }
    }

    if ( ref $req->{deletefromcontentfilters} eq 'ARRAY' ) {
      foreach my $row ( @{$req->{deletefromcontentfilters}} ) {
        my $other_user = LJ::load_user( $row->{username} );
        return fail( $err, 203 ) unless $other_user;
        my $other_userid = $other_user->{userid};
        my $cf = $u->content_filters( id => $row->{id} );
        $cf->delete_row( $other_userid ) if $cf;
      }
    }
    return $res;
}

sub sessionexpire {
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    my $u = $flags->{u};

    # expunge one? or all?
    if ($req->{expireall}) {
        $u->kill_all_sessions;
        return {};
    }

    # just expire a list
    my $list = $req->{expire} || [];
    return {} unless @$list;
    return fail($err,502) unless $u->writer;
    $u->kill_sessions(@$list);
    return {};
}

sub sessiongenerate {
    # generate a session
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);

    # sanitize input
    $req->{expiration} = 'short' unless $req->{expiration} eq 'long';
    my $boundip;
    $boundip = LJ::get_remote_ip() if $req->{bindtoip};

    my $u = $flags->{u};
    my $sess_opts = {
        exptype => $req->{expiration},
        ipfixed => $boundip,
    };

    # do not let locked people do this
    return fail($err, 308) if $u->is_locked;

    my $sess = LJ::Session->create($u, %$sess_opts);

    # return our hash
    return {
        ljsession => $sess->master_cookie_string,
    };
}

sub list_friends
{
    my ($u, $opts) = @_;

    # do not show people in here
    my %hide;  # userid -> 1

    # TAG:FR:protocol:list_friends
    my $sql;
    unless ($opts->{'friendof'}) {
        $sql = "SELECT friendid, fgcolor, bgcolor, groupmask FROM friends WHERE userid=?";
    } else {
        $sql = "SELECT userid FROM friends WHERE friendid=?";

        if (my $list = LJ::load_rel_user($u, 'B')) {
            $hide{$_} = 1 foreach @$list;
        }
    }

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare($sql);
    $sth->execute($u->{'userid'});

    my @frow;
    while (my @row = $sth->fetchrow_array) {
        next if $hide{$row[0]};
        push @frow, [ @row ];
    }

    my $us = LJ::load_userids(map { $_->[0] } @frow);
    my $limitnum = $opts->{'limit'}+0;

    my $res = [];
    foreach my $f (sort { $us->{$a->[0]}{'user'} cmp $us->{$b->[0]}{'user'} }
                   grep { $us->{$_->[0]} } @frow)
    {
        my $u = $us->{$f->[0]};
        next if $opts->{'friendof'} && ! $u->is_visible;

        my $r = {
            'username' => $u->{'user'},
            'fullname' => $u->{'name'},
        };


        if ($u->identity) {
            my $i = $u->identity;
            $r->{'identity_type'} = $i->pretty_type;
            $r->{'identity_value'} = $i->value;
            $r->{'identity_display'} = $u->display_name;
        }

        if ($opts->{'includebdays'} &&
            $u->{'bdate'} &&
            $u->{'bdate'} ne "0000-00-00" &&
            $u->can_show_full_bday)
        {
            $r->{'birthday'} = $u->{'bdate'};
        }

        unless ($opts->{'friendof'}) {
            $r->{'fgcolor'} = LJ::color_fromdb($f->[1]);
            $r->{'bgcolor'} = LJ::color_fromdb($f->[2]);
            $r->{"groupmask"} = $f->[3] if $f->[3] != 1;
        } else {
            $r->{'fgcolor'} = "#000000";
            $r->{'bgcolor'} = "#ffffff";
        }

        $r->{"type"} = {
            'C' => 'community',
            'Y' => 'syndicated',
            'I' => 'identity',
        }->{$u->journaltype} unless $u->is_person;

        $r->{"status"} = {
            'D' => "deleted",
            'S' => "suspended",
            'X' => "purged",
        }->{$u->statusvis} unless $u->is_visible;

        push @$res, $r;
        # won't happen for zero limit (which means no limit)
        last if @$res == $limitnum;
    }
    return $res;
}

sub list_users
{
    my ($u, %opts) = @_;

    my %hide;
    my $list = LJ::load_rel_user( $u, 'B' );
    $hide{$_} = 1 foreach @{$list||[]};


    my $friendof = $opts{trustedby} || $opts{watchedby};
    my ( $filter,  @userids );
    if ( $friendof ) {
      @userids = $opts{trustedby} ? $u->trusted_by_userids : $u->watched_by_userids;
    } else {
      $filter = $opts{trusted} ? $u->trust_list : $u->watch_list;
      @userids = keys %{$filter};
    }

    my $limitnum = $opts{limit} + 0;
    my @res;

    my $us = LJ::load_userids( @userids );
    while ( my( $userid, $u ) = each %$us ) {
      next unless LJ::isu( $u );
      next if $friendof && ! $u->is_visible;
      next if $hide{$userid};

      my $r = {
               username => $u->user,
               fullname => $u->display_name
              };

      if ( $u->identity ) {
        my $i = $u->identity;
        $r->{identity_type} = $i->pretty_type;
        $r->{identity_value} = $i->value;
        $r->{identity_display} = $u->display_name;
      }

      if ( $opts{includebdays} ) {
        $r->{birthday} = $u->bday_string;
      }

      unless ( $friendof ) {
        $r->{fgcolor} = LJ::color_fromdb( $filter->{$userid}->{fgcolor} );
        $r->{bgcolor} = LJ::color_fromdb( $filter->{$userid}->{bgcolor} );
        $r->{groupmask} = $filter->{$userid}->{groupmask};
      }

      $r->{type} = {
                    C => 'community',
                    Y => 'syndicated',
                    I => 'identity',
                   }->{$u->journaltype} unless $u->is_person;

      $r->{status} = {
                      D => 'deleted',
                      S => 'suspended',
                      X => 'purged',
                     }->{$u->statusvis} unless $u->is_visible;

      push @res, $r;
      # won't happen for zero limit (which means no limit)
      last if scalar @res == $limitnum;
    }
    return \@res;
}

sub syncitems
{
    my ($req, $err, $flags) = @_;
    return undef unless authenticate($req, $err, $flags);
    return undef unless check_altusage($req, $err, $flags);
    return fail($err,506) unless LJ::is_enabled('syncitems');

    my $ownerid = $flags->{'ownerid'};
    my $uowner = $flags->{'u_owner'} || $flags->{'u'};
    my $sth;

    my $db = LJ::get_cluster_reader($uowner);
    return fail($err,502) unless $db;

    ## have a valid date?
    my $date = $req->{'lastsync'};
    if ($date) {
        return fail($err,203,"Invalid date format")
            unless ($date =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
    } else {
        $date = "0000-00-00 00:00:00";
    }

    my $LIMIT = 500;

    my %item;
    $sth = $db->prepare("SELECT jitemid, logtime FROM log2 WHERE ".
                        "journalid=? and logtime > ?");
    $sth->execute($ownerid, $date);
    while (my ($id, $dt) = $sth->fetchrow_array) {
        $item{$id} = [ 'L', $id, $dt, "create" ];
    }

    my %cmt;
    my $p_calter = LJ::get_prop("log", "commentalter");
    my $p_revtime = LJ::get_prop("log", "revtime");
    $sth = $db->prepare("SELECT jitemid, propid, FROM_UNIXTIME(value) ".
                        "FROM logprop2 WHERE journalid=? ".
                        "AND propid IN ($p_calter->{'id'}, $p_revtime->{'id'}) ".
                        "AND value+0 > UNIX_TIMESTAMP(?)");
    $sth->execute($ownerid, $date);
    while (my ($id, $prop, $dt) = $sth->fetchrow_array) {
        if ($prop == $p_calter->{'id'}) {
            $cmt{$id} = [ 'C', $id, $dt, "update" ];
        } elsif ($prop == $p_revtime->{'id'}) {
            $item{$id} = [ 'L', $id, $dt, "update" ];
        }
    }

    my @ev = sort { $a->[2] cmp $b->[2] } (values %item, values %cmt);

    my $res = {};
    my $list = $res->{'syncitems'} = [];
    $res->{'total'} = scalar @ev;
    my $ct = 0;
    while (my $ev = shift @ev) {
        $ct++;
        push @$list, { 'item' => "$ev->[0]-$ev->[1]",
                       'time' => $ev->[2],
                       'action' => $ev->[3],  };
        last if $ct >= $LIMIT;
    }
    $res->{'count'} = $ct;
    return $res;
}

sub consolecommand
{
    my ($req, $err, $flags) = @_;

    # logging in isn't necessary, but most console commands do require it
    LJ::set_remote($flags->{'u'}) if authenticate($req, $err, $flags);

    my $res = {};
    my $cmdout = $res->{'results'} = [];

    foreach my $cmd (@{$req->{'commands'}}) {
        # callee can pre-parse the args, or we can do it bash-style
        my @args = ref $cmd eq "ARRAY" ? @$cmd
                                       : LJ::Console->parse_line($cmd);
        my $c = LJ::Console->parse_array(@args);
        my $rv = $c->execute_safely;

        my @output;
        push @output, [$_->status, $_->text] foreach $c->responses;

        push @{$cmdout}, {
            'success' => $rv,
            'output' => \@output,
        };
    }

    return $res;
}

sub getchallenge
{
    my ($req, $err, $flags) = @_;
    my $res = {};
    my $now = time();
    my $etime = 60;
    $res->{'challenge'} = LJ::challenge_generate($etime);
    $res->{'server_time'} = $now;
    $res->{'expire_time'} = $now + $etime;
    $res->{'auth_scheme'} = "c0";  # fixed for now, might support others later
    return $res;
}

sub login_message
{
    my ($req, $res, $flags) = @_;
    my $u = $flags->{'u'};

    my $msg = sub {
        my $code = shift;
        my $args = shift || {};
        $args->{'sitename'} = $LJ::SITENAME;
        $args->{'siteroot'} = $LJ::SITEROOT;
        my $pre = delete $args->{'pre'};
        $res->{'message'} = $pre . translate($u, $code, $args);
    };

    return $msg->("readonly")          if $u->is_readonly;
    return $msg->("not_validated")     if ($u->{'status'} eq "N" and not $LJ::EVERYONE_VALID);
    return $msg->("must_revalidate")   if ($u->{'status'} eq "T" and not $LJ::EVERYONE_VALID);

    my $checkpass = LJ::CreatePage->verify_password( u => $u );
    return $msg->("bad_password", { 'pre' => "$checkpass " }) if $checkpass;

    return $msg->("old_win32_client")  if $req->{'clientversion'} =~ /^Win32-MFC\/(1.2.[0123456])$/;
    return $msg->("old_win32_client")  if $req->{'clientversion'} =~ /^Win32-MFC\/(1.3.[01234])\b/;
    return $msg->("hello_test")        if grep { $u->{user} eq $_ } @LJ::TESTACCTS;
}

sub list_friendgroups
{
    my $u = shift;

#    warn "LJ::Protocol: list_friendgroups called.\n";
    return [];
}

sub list_trustgroups
{
    my $u = shift;

    my $groups = $u->trust_groups;
    return undef unless $groups;

    # we got all of the groups, so put them into an arrayref sorted by the
    # group sortorder; also note that the map is used to construct a new hashref
    # out of the old group hashref so that we have all of the field names converted
    # to a format our callers can recognize
    my @res = map { { id => $_->{groupnum},      name => $_->{groupname},
                      public => $_->{is_public}, sortorder => $_->{sortorder}, } }
              sort { $a->{sortorder} <=> $b->{sortorder} }
              values %$groups;

    return \@res;
}

sub list_contentfilters
{
    my $u = shift;
    my @filters = $u->content_filters;
    return [] unless @filters;

    my @res = map { { id => $_->{id},         name => $_->{name},
                      public => $_->{public}, sortorder => $_->{sortorder},
                      data => join ( ' ',
                                    map { my $uid = $_;
                                          LJ::load_userid( $uid )->user }
                                    ( keys %{$u->content_filters (id => $_->id )->data} ) ) } }
       @filters;

    return \@res;
}

sub list_usejournals {
    my $u = shift;

    my @us = $u->posting_access_list;
    my @unames = map { $_->{user} } @us;

    return \@unames;
}

sub hash_menus
{
    my $u = shift;
    my $user = $u->{'user'};

    my $menu = [
                { 'text' => "Recent Entries",
                  'url' => "$LJ::SITEROOT/users/$user/", },
                { 'text' => "Calendar View",
                  'url' => "$LJ::SITEROOT/users/$user/archive", },
                { 'text' => "Friends View",
                  'url' => "$LJ::SITEROOT/users/$user/read", },
                { 'text' => "-", },
                { 'text' => "Your Profile",
                  'url' => "$LJ::SITEROOT/profile?user=$user", },
                { 'text' => "-", },
                { 'text' => "Change Settings",
                  'sub' => [ { 'text' => "Personal Info",
                               'url' => "$LJ::SITEROOT/manage/profile/", },
                             { 'text' => "Customize Journal",
                               'url' =>"$LJ::SITEROOT/customize/", }, ] },
                { 'text' => "-", },
                { 'text' => "Support",
                  'url' => "$LJ::SITEROOT/support/", }
                ];

    LJ::Hooks::run_hooks("modify_login_menu", {
        'menu' => $menu,
        'u' => $u,
        'user' => $user,
    });

    return $menu;
}

sub list_pickws
{
    my ( $u ) = @_;
    return [] unless LJ::isu( $u );

    my $pi = $u->get_userpic_info;
    my @res;

    my %seen;  # mashifiedptr -> 1

    # FIXME: should be a utf-8 sort
    foreach my $kw ( sort keys %{$pi->{kw}} ) {
        my $pic = $pi->{kw}{$kw};
        $seen{$pic} = 1;
        next if $pic->{state} eq "I";
        push @res, [ $kw, $pic->{picid} ];
    }

    # now add all the pictures that don't have a keyword
    foreach my $picid ( keys %{$pi->{pic}} ) {
        my $pic = $pi->{pic}{$picid};
        next if $seen{$pic};
        next if $pic->{state} eq "I";
        push @res, [ "pic#$picid", $picid ];
    }

    return \@res;
}

sub list_moods
{
    my $mood_max = int(shift);
    DW::Mood->load_moods;

    my $res = [];
    return $res if $mood_max >= $LJ::CACHED_MOOD_MAX;

    for (my $id = $mood_max+1; $id <= $LJ::CACHED_MOOD_MAX; $id++) {
        next unless defined $LJ::CACHE_MOODS{$id};
        my $mood = $LJ::CACHE_MOODS{$id};
        next unless $mood->{'name'};
        push @$res, { 'id' => $id,
                      'name' => $mood->{'name'},
                      'parent' => $mood->{'parent'} };
    }

    return $res;
}

sub check_altusage
{
    my ($req, $err, $flags) = @_;

    my $alt = $req->{'usejournal'};
    my $u = $flags->{'u'};
    unless ($u) {
        my $username = $req->{'username'};
        return fail($err,200) unless $username;
        return fail($err,100) unless LJ::canonical_username($username);

        my $dbr = LJ::get_db_reader();
        return fail($err,502) unless $dbr;
        $u = $flags->{'u'} = LJ::load_user($username);
    }

    $flags->{'ownerid'} = $u->{'userid'};

    # all good if not using an alt journal
    return 1 unless $alt;

    # complain if the username is invalid
    return fail($err,206) unless LJ::canonical_username($alt);

    # we are going to load the alt user
    $flags->{u_owner} = LJ::load_user( $alt );
    $flags->{ownerid} = $flags->{u_owner} ? $flags->{u_owner}->id : undef;
    my $apache_r = eval { BML::get_request() };
    $apache_r->notes->{journalid} = $flags->{ownerid}
        if $apache_r && !$apache_r->notes->{journalid};

    # allow usage if we're told explicitly that it's okay
    if ( $flags->{usejournal_okay} ) {
        return 1 if $flags->{ownerid};
        return fail( $err, 206 );
    }

    # or, if they have explicitly said to ignore canuse
    return 1 if $flags->{ignorecanuse};

    # otherwise, check for access
    return 1 if $u->can_post_to( $flags->{u_owner} );

    # not allowed to access it, bad user, no post
    return fail( $err, 300 );
}

sub authenticate
{
    my ( $req, $err, $flags ) = @_;

    my $username = $req->{username};
    return fail( $err, 200 ) unless $username;
    return fail( $err, 100 ) unless LJ::canonical_username($username);

    my $u = $flags->{u};
    unless ( $u ) {
        my $dbr = LJ::get_db_reader()
            or return fail( $err, 502 );
        $u = LJ::load_user( $username );
    }

    return fail( $err, 100 ) unless $u;
    return fail( $err, 100 ) if $u->is_expunged;
    return fail( $err, 309 ) if $u->is_memorial;    # memorial users can't do anything
    return fail( $err, 505 ) unless $u->{clusterid};

    my $r = DW::Request->get;
    my $ip = LJ::get_remote_ip();

    if ( $r ) {
        $r->note( ljuser => $u->user )
            unless $r->note( 'ljuser' );
        $r->note( journalid => $u->id )
            unless $r->note( 'journalid' );
    }

    my $ip_banned = 0;
    my $chal_expired = 0;
    my $auth_check = sub {

        my $auth_meth = $req->{auth_method} || 'clear';
        if ( $auth_meth eq 'clear' ) {
            return LJ::auth_okay(
                $u, $req->{password}, $req->{hpassword}, $u->password, \$ip_banned
            );
        }
        if ( $auth_meth eq 'challenge' ) {
            my $chal_opts = {};
            my $chall_ok = LJ::challenge_check_login(
                $u, $req->{auth_challenge}, $req->{auth_response}, \$ip_banned, $chal_opts
            );
            $chal_expired = 1 if $chal_opts->{expired};
            return $chall_ok;
        }
        if ( $auth_meth eq 'cookie' ) {
            return unless $r && $r->header_in( 'X-LJ-Auth' ) eq 'cookie';

            my $remote = LJ::get_remote();
            return $remote && $remote->user eq $username ? 1 : 0;
        }
    };

    unless ( $flags->{nopassword} ||
             $flags->{noauth} ||
             $auth_check->() )
    {
        return fail( $err, 402 ) if $ip_banned;
        return fail( $err, 105 ) if $chal_expired;
        return fail( $err, 101 );
    }

    # remember the user record for later.
    $flags->{u} = $u;
    return 1;
}

sub fail
{
    my $err = shift;
    my $code = shift;
    my $des = shift;
    $code .= ":$des" if $des;
    $$err = $code if (ref $err eq "SCALAR");
    return undef;
}

sub un_utf8_request {
    my $req = shift;
    $req->{$_} = LJ::no_utf8_flag($req->{$_}) foreach qw(subject event);
    my $props = $req->{props} || {};
    foreach my $k (keys %$props) {
        next if ref $props->{$k};  # if this is multiple levels deep?  don't think so.
        $props->{$k} = LJ::no_utf8_flag($props->{$k});
    }
}

#### Old interface (flat key/values) -- wrapper aruond LJ::Protocol
package LJ;

sub do_request
{
    # get the request and response hash refs
    my ($req, $res, $flags) = @_;

    # initialize some stuff
    %{$res} = ();                      # clear the given response hash
    $flags = {} unless (ref $flags eq "HASH");

    # did they send a mode?
    unless ($req->{'mode'}) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No mode specified.";
        return;
    }

    # this method doesn't require auth
    if ($req->{'mode'} eq "getchallenge") {
        return getchallenge($req, $res, $flags);
    }

    # mode from here on out require a username
    my $user = LJ::canonical_username($req->{'user'});
    unless ($user) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No username sent.";
        return;
    }

    ### see if the server's under maintenance now
    if ($LJ::SERVER_DOWN) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = $LJ::SERVER_DOWN_MESSAGE;
        return;
    }

    ## dispatch wrappers
    if ($req->{'mode'} eq "login") {
        return login($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriendgroups") {
        return getfriendgroups($req, $res, $flags);
    }
    if ($req->{'mode'} eq "gettrustgroups") {
        return gettrustgroups($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriends") {
        return getfriends($req, $res, $flags);
    }
    if ($req->{'mode'} eq "friendof") {
        return friendof($req, $res, $flags);
    }
    if ($req->{'mode'} eq "checkfriends") {
        return checkfriends($req, $res, $flags);
    }
    if ($req->{'mode'} eq "checkforupdates") {
        return checkforupdates($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getdaycounts") {
        return getdaycounts($req, $res, $flags);
    }
    if ($req->{'mode'} eq "postevent") {
        return postevent($req, $res, $flags);
    }
    if ($req->{'mode'} eq "editevent") {
        return editevent($req, $res, $flags);
    }
    if ($req->{'mode'} eq "syncitems") {
        return syncitems($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getevents") {
        return getevents($req, $res, $flags);
    }
    if ($req->{'mode'} eq "editfriends") {
        return editfriends($req, $res, $flags);
    }
    if ($req->{'mode'} eq "editfriendgroups") {
        return editfriendgroups($req, $res, $flags);
    }
    if ($req->{'mode'} eq "consolecommand") {
        return consolecommand($req, $res, $flags);
    }
    if ($req->{'mode'} eq "sessiongenerate") {
        return sessiongenerate($req, $res, $flags);
    }
    if ($req->{'mode'} eq "sessionexpire") {
        return sessionexpire($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getusertags") {
        return getusertags($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriendspage") {
        return getfriendspage($req, $res, $flags);
    }
    if ($req->{'mode'} eq "getreadpage") {
        return getreadpage( $req, $res, $flags );
    }

    ### unknown mode!
    $res->{'success'} = "FAIL";
    $res->{'errmsg'} = "Client error: Unknown mode ($req->{'mode'})";
    return;
}

## flat wrapper
sub getfriendspage
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getfriendspage", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    return 1;
}

sub getreadpage
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getreadpage", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    my $ect = 0;
    foreach my $evt (@{$rs->{'entries'}}) {
        $ect++;
        foreach my $f (qw(subject_raw journalname journaltype postername postertype ditemid security)) {
            if (defined $evt->{$f}) {
                $res->{"entries_${ect}_$f"} = $evt->{$f};
            }
        }
        $res->{"entries_${ect}_event"} = LJ::eurl($evt->{'event_raw'});
    }

    $res->{'entries_count'} = $ect;
    $res->{'success'} = "OK";

    return 1;
}

## flat wrapper
sub login
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("login", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'name'} = $rs->{'fullname'};
    $res->{'message'} = $rs->{'message'} if $rs->{'message'};
    $res->{'fastserver'} = 1 if $rs->{'fastserver'};
    $res->{'caps'} = $rs->{'caps'} if $rs->{'caps'};

    # shared journals
    my $access_count = 0;
    foreach my $user (@{$rs->{'usejournals'}}) {
        $access_count++;
        $res->{"access_${access_count}"} = $user;
    }
    if ($access_count) {
        $res->{"access_count"} = $access_count;
    }

    # friend groups
    populate_friend_groups($res, $rs->{'friendgroups'});

    my $flatten = sub {
        my ($prefix, $listref) = @_;
        my $ct = 0;
        foreach (@$listref) {
            $ct++;
            $res->{"${prefix}_$ct"} = $_;
        }
        $res->{"${prefix}_count"} = $ct;
    };

    ### picture keywords
    $flatten->("pickw", $rs->{'pickws'})
        if defined $req->{"getpickws"};
    $flatten->("pickwurl", $rs->{'pickwurls'})
        if defined $req->{"getpickwurls"};
    $res->{'defaultpicurl'} = $rs->{'defaultpicurl'} if $rs->{'defaultpicurl'};

    ### report new moods that this client hasn't heard of, if they care
    if (defined $req->{"getmoods"}) {
        my $mood_count = 0;
        foreach my $m (@{$rs->{'moods'}}) {
            $mood_count++;
            $res->{"mood_${mood_count}_id"} = $m->{'id'};
            $res->{"mood_${mood_count}_name"} = $m->{'name'};
            $res->{"mood_${mood_count}_parent"} = $m->{'parent'};
        }
        if ($mood_count) {
            $res->{"mood_count"} = $mood_count;
        }
    }

    #### send web menus
    if ($req->{"getmenus"} == 1) {
        my $menu = $rs->{'menus'};
        my $menu_num = 0;
        populate_web_menu($res, $menu, \$menu_num);
    }

    return 1;
}

## flat wrapper
sub getfriendgroups
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getfriendgroups", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }
    $res->{'success'} = "OK";
    populate_friend_groups($res, $rs->{'friendgroups'});

    return 1;
}

## flat wrapper
sub gettrustgroups
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request('gettrustgroups', $rq, \$err, $flags);
    unless ($rs) {
        $res->{success} = "FAIL";
        $res->{errmsg} = LJ::Protocol::error_message($err);
        return 0;
    }
    $res->{success} = "OK";
    populate_groups($res, 'tr', $rs->{trustgroups});

    return 1;
}

## flat wrapper
sub getusertags
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getusertags", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";

    my $ct = 0;
    foreach my $tag (@{$rs->{tags}}) {
        $ct++;
        $res->{"tag_${ct}_security"} = $tag->{security_level};
        $res->{"tag_${ct}_uses"} = $tag->{uses} if $tag->{uses};
        $res->{"tag_${ct}_display"} = $tag->{display} if $tag->{display};
        $res->{"tag_${ct}_name"} = $tag->{name};
        foreach my $lev (qw(friends private public)) {
            $res->{"tag_${ct}_sb_$_"} = $tag->{security}->{$_}
                if $tag->{security}->{$_};
        }
        my $gm = 0;
        foreach my $grpid (keys %{$tag->{security}->{groups}}) {
            next unless $tag->{security}->{groups}->{$grpid};
            $gm++;
            $res->{"tag_${ct}_sb_group_${gm}_id"} = $grpid;
            $res->{"tag_${ct}_sb_group_${gm}_count"} = $tag->{security}->{groups}->{$grpid};
        }
        $res->{"tag_${ct}_sb_group_count"} = $gm if $gm;
    }
    $res->{'tag_count'} = $ct;

    return 1;
}

## flat wrapper
sub getfriends
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getfriends", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    if ($req->{'includegroups'}) {
        populate_friend_groups($res, $rs->{'friendgroups'});
    }
    if ($req->{'includefriendof'}) {
        populate_friends($res, "friendof", $rs->{'friendofs'});
    }
    populate_friends($res, "friend", $rs->{'friends'});

    return 1;
}

## flat wrapper
sub friendof
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("friendof", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    populate_friends($res, "friendof", $rs->{'friendofs'});
    return 1;
}

## flat wrapper
sub checkfriends
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("checkfriends", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'new'} = $rs->{'new'};
    $res->{'lastupdate'} = $rs->{'lastupdate'};
    $res->{'interval'} = $rs->{'interval'};
    return 1;
}

## flat wrapper
sub checkforupdates
{
    my ( $req, $res, $flags ) = @_;

    my $err = 0;
    my $rq = upgrade_request( $req );

    my $rs = LJ::Protocol::do_request( "checkforupdates", $rq, \$err, $flags );
    unless ( $rs ) {
        $res->{success} = "FAIL";
        $res->{errmsg} = LJ::Protocol::error_message( $err );
        return 0;
    }

    $res->{success} = "OK";
    $res->{new} = $rs->{new};
    $res->{lastupdate} = $rs->{lastupdate};
    $res->{interval} = $rs->{interval};
    return 1;
}

## flat wrapper
sub getdaycounts
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getdaycounts", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    foreach my $d (@{ $rs->{'daycounts'} }) {
        $res->{$d->{'date'}} = $d->{'count'};
    }
    return 1;
}

## flat wrapper
sub syncitems
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("syncitems", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'sync_total'} = $rs->{'total'};
    $res->{'sync_count'} = $rs->{'count'};

    my $ct = 0;
    foreach my $s (@{ $rs->{'syncitems'} }) {
        $ct++;
        foreach my $a (qw(item action time)) {
            $res->{"sync_${ct}_$a"} = $s->{$a};
        }
    }
    return 1;
}

## flat wrapper: limited functionality.  (1 command only, server-parsed only)
sub consolecommand
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    delete $rq->{'command'};

    $rq->{'commands'} = [ $req->{'command'} ];

    my $rs = LJ::Protocol::do_request("consolecommand", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'cmd_success'} = $rs->{'results'}->[0]->{'success'};
    $res->{'cmd_line_count'} = 0;
    foreach my $l (@{$rs->{'results'}->[0]->{'output'}}) {
        $res->{'cmd_line_count'}++;
        my $line = $res->{'cmd_line_count'};
        $res->{"cmd_line_${line}_type"} = $l->[0]
            if $l->[0];
        $res->{"cmd_line_${line}"} = $l->[1];
    }

    $res->{'success'} = "OK";

}

## flat wrapper
sub getchallenge
{
    my ($req, $res, $flags) = @_;
    my $err = 0;
    my $rs = LJ::Protocol::do_request("getchallenge", $req, \$err, $flags);

    # stupid copy (could just return $rs), but it might change in the future
    # so this protects us from future accidental harm.
    foreach my $k (qw(challenge server_time expire_time auth_scheme)) {
        $res->{$k} = $rs->{$k};
    }

    $res->{'success'} = "OK";
    return $res;
}

## flat wrapper
sub editfriends
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    $rq->{'add'} = [];
    $rq->{'delete'} = [];

    foreach (keys %$req) {
        if (/^editfriend_add_(\d+)_user$/) {
            my $n = $1;
            next unless ($req->{"editfriend_add_${n}_user"} =~ /\S/);
            my $fa = { 'username' => $req->{"editfriend_add_${n}_user"},
                       'fgcolor' => $req->{"editfriend_add_${n}_fg"},
                       'bgcolor' => $req->{"editfriend_add_${n}_bg"},
                       'groupmask' => $req->{"editfriend_add_${n}_groupmask"},
                   };
            push @{$rq->{'add'}}, $fa;
        } elsif (/^editfriend_delete_(\w+)$/) {
            push @{$rq->{'delete'}}, $1;
        }
    }

    my $rs = LJ::Protocol::do_request("editfriends", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";

    my $ct = 0;
    foreach my $fa (@{ $rs->{'added'} }) {
        $ct++;
        $res->{"friend_${ct}_user"} = $fa->{'username'};
        $res->{"friend_${ct}_name"} = $fa->{'fullname'};
    }

    $res->{'friends_added'} = $ct;

    return 1;
}

## flat wrapper
sub editfriendgroups
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    $rq->{'groupmasks'} = {};
    $rq->{'set'} = {};
    $rq->{'delete'} = [];

    foreach (keys %$req) {
        if (/^efg_set_(\d+)_name$/) {
            next unless ($req->{$_} ne "");
            my $n = $1;
            my $fs = {
                'name' => $req->{"efg_set_${n}_name"},
                'sort' => $req->{"efg_set_${n}_sort"},
            };
            if (defined $req->{"efg_set_${n}_public"}) {
                $fs->{'public'} = $req->{"efg_set_${n}_public"};
            }
            $rq->{'set'}->{$n} = $fs;
        }
        elsif (/^efg_delete_(\d+)$/) {
            if ($req->{$_}) {
                # delete group if value is true
                push @{$rq->{'delete'}}, $1;
            }
        }
        elsif (/^editfriend_groupmask_(\w+)$/) {
            $rq->{'groupmasks'}->{$1} = $req->{$_};
        }
    }

    my $rs = LJ::Protocol::do_request("editfriendgroups", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    return 1;
}

sub flatten_props
{
    my ($req, $rq) = @_;

    ## changes prop_* to props hashref
    foreach my $k (keys %$req) {
        next unless ($k =~ /^prop_(.+)/);
        $rq->{'props'}->{$1} = $req->{$k};
    }
}

## flat wrapper
sub postevent
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    flatten_props($req, $rq);

    $rq->{'props'}->{'interface'} = "flat";

    my $rs = LJ::Protocol::do_request("postevent", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'message'} = $rs->{'message'} if $rs->{'message'};
    $res->{'success'} = "OK";
    $res->{'itemid'} = $rs->{'itemid'};
    $res->{'anum'} = $rs->{'anum'} if defined $rs->{'anum'};
    $res->{'url'} = $rs->{'url'} if defined $rs->{'url'};
    return 1;
}

## flat wrapper
sub editevent
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    flatten_props($req, $rq);

    my $rs = LJ::Protocol::do_request("editevent", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{message} = $rs->{message} if $rs->{message};
    $res->{'success'} = "OK";
    $res->{'itemid'} = $rs->{'itemid'};
    $res->{'anum'} = $rs->{'anum'} if defined $rs->{'anum'};
    $res->{'url'} = $rs->{'url'} if defined $rs->{'url'};

    return 1;
}

## flat wrapper
sub sessiongenerate {
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request('sessiongenerate', $rq, \$err, $flags);
    unless ($rs) {
        $res->{success} = 'FAIL';
        $res->{errmsg} = LJ::Protocol::error_message($err);
    }

    $res->{success} = 'OK';
    $res->{ljsession} = $rs->{ljsession};
    return 1;
}

## flat wrappre
sub sessionexpire {
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    $rq->{expire} = [];
    foreach my $k (keys %$rq) {
        push @{$rq->{expire}}, $1
            if $k =~ /^expire_id_(\d+)$/;
    }

    my $rs = LJ::Protocol::do_request('sessionexpire', $rq, \$err, $flags);
    unless ($rs) {
        $res->{success} = 'FAIL';
        $res->{errmsg} = LJ::Protocol::error_message($err);
    }

    $res->{success} = 'OK';
    return 1;
}

## flat wrapper
sub getevents
{
    my ($req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request("getevents", $rq, \$err, $flags);
    unless ($rs) {
        $res->{success} = "FAIL";
        $res->{errmsg} = LJ::Protocol::error_message($err);
        return 0;
    }

    my $ect = 0;
    my $pct = 0;
    foreach my $evt (@{$rs->{events}}) {
        $ect++;
        foreach my $f (qw(itemid eventtime logtime security allowmask subject anum url poster converted_with_loss)) {
            if (defined $evt->{$f}) {
                $res->{"events_${ect}_$f"} = $evt->{$f};
            }
        }
        $res->{"events_${ect}_event"} = LJ::eurl($evt->{event});

        if ($evt->{props}) {
            foreach my $k (sort keys %{$evt->{props}}) {
                $pct++;
                $res->{"prop_${pct}_itemid"} = $evt->{itemid};
                $res->{"prop_${pct}_name"} = $k;
                $res->{"prop_${pct}_value"} = $evt->{props}->{$k};
            }
        }
    }

    unless ($req->{noprops}) {
        $res->{prop_count} = $pct;
    }
    $res->{events_count} = $ect;
    $res->{success} = "OK";

    return 1;
}


sub populate_friends
{
    my ($res, $pfx, $list) = @_;
    my $count = 0;
    foreach my $f (@$list)
    {
        $count++;
        $res->{"${pfx}_${count}_name"} = $f->{'fullname'};
        $res->{"${pfx}_${count}_user"} = $f->{'username'};
        $res->{"${pfx}_${count}_birthday"} = $f->{'birthday'} if $f->{'birthday'};
        $res->{"${pfx}_${count}_bg"} = $f->{'bgcolor'};
        $res->{"${pfx}_${count}_fg"} = $f->{'fgcolor'};
        if (defined $f->{'groupmask'}) {
            $res->{"${pfx}_${count}_groupmask"} = $f->{'groupmask'};
        }
        if (defined $f->{'type'}) {
            $res->{"${pfx}_${count}_type"} = $f->{'type'};
            if ($f->{'type'} eq 'identity') {
                $res->{"${pfx}_${count}_identity_type"}    = $f->{'identity_type'};
                $res->{"${pfx}_${count}_identity_value"}   = $f->{'identity_value'};
                $res->{"${pfx}_${count}_identity_display"} = $f->{'identity_display'};
            }
        }
        if (defined $f->{'status'}) {
            $res->{"${pfx}_${count}_status"} = $f->{'status'};
        }
    }
    $res->{"${pfx}_count"} = $count;
}


sub upgrade_request
{
    my $r = shift;
    my $new = { %{ $r } };
    $new->{'username'} = $r->{'user'};

    # but don't delete $r->{'user'}, as it might be, say, %FORM,
    # that'll get reused in a later request in, say, update.bml after
    # the login before postevent.  whoops.

    return $new;
}

## given a $res hashref and friend group subtree (arrayref), flattens it
sub populate_friend_groups
{
    my ($res, $fr) = @_;

    my $maxnum = 0;
    foreach my $fg (@$fr)
    {
        my $num = $fg->{'id'};
        $res->{"frgrp_${num}_name"} = $fg->{'name'};
        $res->{"frgrp_${num}_sortorder"} = $fg->{'sortorder'};
        if ($fg->{'public'}) {
            $res->{"frgrp_${num}_public"} = 1;
        }
        if ($num > $maxnum) { $maxnum = $num; }
    }
    $res->{'frgrp_maxnum'} = $maxnum;
}

## given a $res hashref and trust group (arrayref), flattens it
sub populate_groups
{
    my ($res, $pfx, $fr) = @_;

    my $maxnum = 0;
    foreach my $fg ( @$fr ) {
        my $num = $fg->{id};
        $res->{"${pfx}_${num}_name"} = $fg->{name};
        $res->{"${pfx}_${num}_sortorder"} = $fg->{sortorder};
        $res->{"${pfx}_${num}_public"} = 1 if $fg->{public};
        $maxnum = $num if ($num > $maxnum);
    }
    $res->{"${pfx}_maxnum"} = $maxnum;
}

## given a menu tree, flattens it into $res hashref
sub populate_web_menu
{
    my ($res, $menu, $numref) = @_;
    my $mn = $$numref;  # menu number
    my $mi = 0;         # menu item
    foreach my $it (@$menu) {
        $mi++;
        $res->{"menu_${mn}_${mi}_text"} = $it->{'text'};
        if ($it->{'text'} eq "-") { next; }
        if ($it->{'sub'}) {
            $$numref++;
            $res->{"menu_${mn}_${mi}_sub"} = $$numref;
            &populate_web_menu($res, $it->{'sub'}, $numref);
            next;

        }
        $res->{"menu_${mn}_${mi}_url"} = $it->{'url'};
    }
    $res->{"menu_${mn}_count"} = $mi;
}

1;
