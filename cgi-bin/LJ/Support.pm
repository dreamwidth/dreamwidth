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

package LJ::Support;
use strict;

use Digest::MD5 qw(md5_hex);

use LJ::Sysban;
use LJ::Faq;

# Constants
my $SECONDS_IN_DAY = 3600 * 24;
our @SUPPORT_PRIVS = (
    qw/supportclose
        supporthelp
        supportread
        supportviewinternal
        supportmakeinternal
        supportmovetouch
        supportviewscreened
        supportviewstocks
        supportchangesummary/
);

# <LJFUNC>
# name: LJ::Support::slow_query_dbh
# des: Retrieve a database handle to be used for support-related
#      slow queries... defaults to 'slow' role but can be
#      overriden by [ljconfig[support_slow_roles]].
# args: none
# returns: master database handle.
# </LJFUNC>
sub slow_query_dbh {
    return LJ::get_dbh(@LJ::SUPPORT_SLOW_ROLES);
}

# basic function to add or update a support category.
# args: hashref corresponding to row values of supportcat table
# returns: spcatid on success, undef on failure
sub define_cat {
    my ($opts) = @_;
    if ( $opts->{catkey} ) {

        # see if this category is already defined (catkey is unique)
        my $cat = get_cat_by_key( load_cats(), $opts->{catkey} );
        if ($cat) {

            # use the existing category id
            $opts->{spcatid} = $cat->{spcatid};
            delete $opts->{catkey};
        }
    }

    my @columns = qw/ catkey catname sortorder basepoints is_selectable
        public_read public_help allow_screened hide_helpers
        user_closeable replyaddress no_autoreply scope /;
    my %row;
    foreach (@columns) {
        $row{$_} = $opts->{$_} if exists $opts->{$_};
        delete $opts->{$_};
    }

    my $id = delete $opts->{spcatid};
    return $id unless %row;

    # if we have any $opts remaining here, they're invalid
    my $invalid = join ', ', keys %$opts;
    die "Invalid opts passed to LJ::Support::define_cat: $invalid"
        if $invalid;

    my $dbh = LJ::get_db_writer() or return;

    if ($id) {    # update path
        my ( @cols, @vals );
        while ( my ( $col, $val ) = each %row ) {
            push @cols, "$col=?";
            push @vals, $val;
        }
        my $bind = join ', ', @cols;

        $dbh->do( "UPDATE supportcat SET $bind WHERE spcatid=?", undef, @vals, $id );

    }
    else {        # insert path
        my @cols    = keys %row;
        my @vals    = @row{@cols};
        my $colbind = join ',', map { $_ } @cols;
        my $valbind = join ',', map { '?' } @vals;

        $dbh->do( "INSERT INTO supportcat ($colbind) VALUES ($valbind)", undef, @vals );
        $id = $dbh->{mysql_insertid};
    }

    die $dbh->errstr if $dbh->err;
    return $id;
}

sub delete_cat {
    my ($id) = @_;
    my $dbh = LJ::get_db_writer() or return;
    $dbh->do( "DELETE FROM supportcat WHERE spcatid=?", undef, $id );
    die $dbh->errstr if $dbh->err;
    return 1;    # regardless of whether the id was in the table
}

## pass $id of zero or blank to get all categories
sub load_cats {
    my ($id) = @_;
    my $hashref = {};
    $id += 0;
    my $where = $id ? "WHERE spcatid=$id" : "";
    my $dbr   = LJ::get_db_reader();
    my $sth   = $dbr->prepare("SELECT * FROM supportcat $where");
    $sth->execute;
    $hashref->{ $_->{'spcatid'} } = $_ while ( $_ = $sth->fetchrow_hashref );
    return $hashref;
}

sub load_email_to_cat_map {
    my $map = {};
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT * FROM supportcat ORDER BY sortorder DESC");
    $sth->execute;
    while ( my $sp = $sth->fetchrow_hashref ) {
        next unless ( $sp->{'replyaddress'} );
        $map->{ $sp->{'replyaddress'} } = $sp;
    }
    return $map;
}

sub calc_points {
    my ( $sp, $secs, $spcat ) = @_;
    $spcat ||= $sp->{_cat};
    my $base = $spcat->{basepoints} || 1;
    $secs = int( $secs / ( 3600 * 6 ) );
    my $total = ( $base + $secs );
    $total = 10 if $total > 10;
    return $total;
}

sub init_remote {
    my $remote = shift;
    return unless $remote;
    $remote->load_user_privs(@SUPPORT_PRIVS);
}

sub has_any_support_priv {
    my $u = shift;
    return 0 unless $u;
    foreach my $support_priv (@SUPPORT_PRIVS) {
        return 1 if $u->has_priv($support_priv);
    }
    return 0;
}

# given all the categories, maps a catkey into a cat
sub get_cat_by_key {
    my ( $cats, $cat ) = @_;
    $cat ||= '';
    foreach ( keys %$cats ) {
        if ( $cats->{$_}->{'catkey'} eq $cat ) {
            return $cats->{$_};
        }
    }
    return undef;
}

sub filter_cats {
    my $remote = shift;
    my $cats   = shift;

    return grep { can_read_cat( $_, $remote ); } sorted_cats($cats);
}

sub sorted_cats {
    my $cats = shift;
    return sort { $a->{'catname'} cmp $b->{'catname'} } values %$cats;
}

# takes raw support request record and puts category info in it
# so it can be used in other functions like can_*
sub fill_request_with_cat {
    my ( $sp, $cats ) = @_;
    $sp->{_cat} = $cats->{ $sp->{'spcatid'} };
}

sub open_request_status {
    my ( $timetouched, $timelasthelp ) = @_;
    my $status;
    if ( $timelasthelp > $timetouched + 5 ) {
        $status = "awaiting close";
    }
    elsif ($timelasthelp
        && $timetouched > $timelasthelp + 5 )
    {
        $status = "still needs help";
    }
    else {
        $status = "open";
    }
    return $status;
}

sub is_poster {
    my ( $sp, $remote, $auth ) = @_;

    if ( $sp->{'reqtype'} eq "user" ) {
        return 1 if $remote && $remote->id == $sp->{'requserid'};

    }
    else {
        if ($remote) {
            return 1 if lc( $remote->email_raw ) eq lc( $sp->{'reqemail'} );
        }
        else {
            return 1 if $auth && $auth eq mini_auth($sp);
        }
    }

    return 0;
}

sub can_see_helper {
    my ( $sp, $remote ) = @_;
    if ( $sp->{_cat}->{'hide_helpers'} ) {
        if ( can_help( $sp, $remote ) ) {
            return 1;
        }
        if ( $remote && $remote->has_priv( "supportviewinternal", $sp->{_cat}->{'catkey'} ) ) {
            return 1;
        }
        if ( $remote && $remote->has_priv( "supportviewscreened", $sp->{_cat}->{'catkey'} ) ) {
            return 1;
        }
        return 0;
    }
    return 1;
}

sub can_read {
    my ( $sp, $remote, $auth ) = @_;
    return ( is_poster( $sp, $remote, $auth ) || can_read_cat( $sp->{_cat}, $remote ) );
}

sub can_read_cat {
    my ( $cat, $remote ) = @_;
    return unless ($cat);
    return ( $cat->{'public_read'}
            || ( $remote && $remote->has_priv( "supportread", $cat->{'catkey'} ) ) );
}

*can_bounce = \&can_close_cat;
*can_lock   = \&can_close_cat;

# if they can close in this category
sub can_close_cat {
    my ( $sp, $remote ) = @_;
    return 1 if $sp->{_cat}->{public_read} && $remote && $remote->has_priv( 'supportclose', '' );
    return 1 if $remote && $remote->has_priv( 'supportclose', $sp->{_cat}->{catkey} );
    return 0;
}

# if they can close this particular request
sub can_close {
    my ( $sp, $remote, $auth ) = @_;
    return 1 if $sp->{_cat}->{user_closeable} && is_poster( $sp, $remote, $auth );
    return can_close_cat( $sp, $remote );
}

# if they can reopen a request
sub can_reopen {
    my ( $sp, $remote, $auth ) = @_;
    return 1 if is_poster( $sp, $remote, $auth );
    return can_close_cat( $sp, $remote );
}

sub can_append {
    my ( $sp, $remote, $auth ) = @_;
    if ( is_poster( $sp, $remote, $auth ) ) { return 1; }
    return 0 unless $remote;
    return 0 unless $remote->is_visible;
    if ( $sp->{_cat}->{'allow_screened'} ) { return 1; }
    if ( can_help( $sp, $remote ) ) { return 1; }
    return 0;
}

sub is_locked {
    my $sp   = shift;
    my $spid = ref $sp ? $sp->{spid} : $sp + 0;
    return undef unless $spid;
    my $props = LJ::Support::load_props($spid);
    return $props->{locked} ? 1 : 0;
}

sub lock {
    my $sp   = shift;
    my $spid = ref $sp ? $sp->{spid} : $sp + 0;
    return undef unless $spid;
    my $dbh = LJ::get_db_writer();
    $dbh->do( "REPLACE INTO supportprop (spid, prop, value) VALUES (?, 'locked', 1)", undef,
        $spid );
}

sub unlock {
    my $sp   = shift;
    my $spid = ref $sp ? $sp->{spid} : $sp + 0;
    return undef unless $spid;
    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM supportprop WHERE spid = ? AND prop = 'locked'", undef, $spid );
}

# privilege policy:
#   supporthelp with no argument gives you all abilities in all public_read categories
#   supporthelp with a catkey arg gives you all abilities in that non-public_read category
#   supportread with a catkey arg is required to view requests in a non-public_read category
#   all other privs work like:
#      no argument = global, where category is public_read or user has supportread on that category
#      argument = local, priv applies in that category only if it's public or user has supportread
sub support_check_priv {
    my ( $sp, $remote, $priv ) = @_;
    return 1 if can_help( $sp, $remote );
    return 0 unless can_read_cat( $sp->{_cat}, $remote );
    return 1 if $remote && $remote->has_priv( $priv, '' ) && $sp->{_cat}->{public_read};
    return 1 if $remote && $remote->has_priv( $priv, $sp->{_cat}->{catkey} );
    return 0;
}

# can they read internal comments?  if they're a helper or have
# extended supportread (with a plus sign at the end of the category key)
sub can_read_internal {
    my ( $sp, $remote ) = @_;
    return 1 if LJ::Support::support_check_priv( $sp, $remote, 'supportviewinternal' );
    return 1 if $remote && $remote->has_priv( "supportread", $sp->{_cat}->{catkey} . "+" );
    return 0;
}

sub can_make_internal {
    return LJ::Support::support_check_priv( @_, 'supportmakeinternal' );
}

sub can_read_screened {
    return LJ::Support::support_check_priv( @_, 'supportviewscreened' );
}

sub can_read_response {
    my ( $sp, $u, $rtype, $posterid ) = @_;
    return 1 if $posterid == $u->id;
    return 0
        if $rtype eq 'screened'
        && !LJ::Support::can_read_screened( $sp, $u );
    return 0
        if $rtype eq 'internal'
        && !LJ::Support::can_read_internal( $sp, $u );
    return 1;
}

sub can_perform_actions {
    return LJ::Support::support_check_priv( @_, 'supportmovetouch' );
}

sub can_change_summary {
    return LJ::Support::support_check_priv( @_, 'supportchangesummary' );
}

sub can_see_stocks {
    return LJ::Support::support_check_priv( @_, 'supportviewstocks' );
}

sub can_help {
    my ( $sp, $remote ) = @_;
    if ( $sp->{_cat}->{'public_read'} ) {
        return 1 if $sp->{_cat}->{'public_help'};
        return 1 if $remote && $remote->has_priv( "supporthelp", "" );
    }
    my $catkey = $sp->{_cat}->{'catkey'};
    return 1 if $remote && $remote->has_priv( "supporthelp", $catkey );
    return 0;
}

sub load_props {
    my $spid = shift;
    return unless $spid;

    my %props = ();    # prop => value

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT prop, value FROM supportprop WHERE spid=?");
    $sth->execute($spid);
    while ( my ( $prop, $value ) = $sth->fetchrow_array ) {
        $props{$prop} = $value;
    }

    return \%props;
}

sub prop {
    my ( $spid, $propname ) = @_;

    my $props = LJ::Support::load_props($spid);

    return $props->{$propname} || undef;
}

sub set_prop {
    my ( $spid, $propname, $propval ) = @_;

    # TODO:
    # -- delete on 'undef' propval
    # -- allow setting of multiple

    my $dbh = LJ::get_db_writer()
        or die "couldn't contact global master";

    $dbh->do( "REPLACE INTO supportprop (spid, prop, value) VALUES (?,?,?)",
        undef, $spid, $propname, $propval );
    die $dbh->errstr if $dbh->err;

    return 1;
}

# $loadreq is used by /abuse/report.bml and
# to signify that the full request
# should not be loaded.  To simplify code going live,
# Whitaker and I decided to not try and merge it
# into the new $opts hash.

# $opts->{'db_force'} loads the request from a
# global master.  Needed to prevent a race condition
# where the request may not have replicated to slaves
# in the time needed to load an auth code.

sub load_request {
    my ( $spid, $loadreq, $opts ) = @_;
    my $sth;

    $spid += 0;

    # load the support request
    my $db = $opts->{'db_force'} ? LJ::get_db_writer() : LJ::get_db_reader();

    $sth = $db->prepare("SELECT * FROM support WHERE spid=$spid");
    $sth->execute;
    my $sp = $sth->fetchrow_hashref;

    return undef unless $sp;

    # load the category the support requst is in
    $sth = $db->prepare("SELECT * FROM supportcat WHERE spcatid=$sp->{'spcatid'}");
    $sth->execute;
    $sp->{_cat} = $sth->fetchrow_hashref;

    # now load the user's request text, if necessary
    if ($loadreq) {
        $sp->{body} =
            $db->selectrow_array( "SELECT message FROM supportlog WHERE spid = ? AND type = 'req'",
            undef, $sp->{spid} );
    }

    return $sp;
}

# load_requests:
# Given an arrayref, fetches information about the requests
# with these spid's; unlike load_request(), it doesn't fetch information
# about supportcats.

sub load_requests {
    my ($spids) = @_;
    my $dbr = LJ::get_db_reader() or return;

    my $list     = join( ',', map { '?' } @$spids );
    my $requests = $dbr->selectall_arrayref(
        "SELECT spid, reqtype, requserid, reqname, reqemail, state,"
            . " authcode, spcatid, subject, timecreate, timetouched, timeclosed,"
            . " timelasthelp, timemodified FROM support WHERE spid IN ($list)",
        { Slice => {} },
        map { $_ + 0 } @$spids
    );
    die $dbr->errstr if $dbr->err;

    return $requests;
}

sub load_response {
    my $splid = shift;
    my $sth;

    $splid += 0;

    # load the support request. we hit the master because we generally
    # only invoke this when we want the freshest version of the row.
    # (ie, approving a response changes its type from screened to
    # answer ... then we fetch the row again and make decisions on its type.
    # so we want the authoritative version)
    my $dbh = LJ::get_db_writer();
    $sth = $dbh->prepare("SELECT * FROM supportlog WHERE splid=$splid");
    $sth->execute;
    my $res = $sth->fetchrow_hashref;

    return $res;
}

sub get_answer_types {
    my ( $sp, $remote, $auth ) = @_;
    my @ans_type;

    if ( is_poster( $sp, $remote, $auth ) ) {
        push @ans_type, ( "comment", LJ::Lang::ml("support.answertype.moreinfo") );
        return @ans_type;
    }

    if ( can_help( $sp, $remote ) ) {
        push @ans_type,
            (
            "screened" => LJ::Lang::ml("support.answertype.screened"),
            "answer"   => LJ::Lang::ml("support.answertype.answer"),
            "comment"  => LJ::Lang::ml("support.answertype.comment")
            );
    }
    elsif ( $sp->{_cat}->{'allow_screened'} ) {
        push @ans_type, ( "screened" => LJ::Lang::ml("support.answertype.screened") );
    }

    if ( can_make_internal( $sp, $remote )
        && !$sp->{_cat}->{'public_help'} )
    {
        push @ans_type, ( "internal" => LJ::Lang::ml("support.answertype.internal") );
    }

    if ( can_bounce( $sp, $remote ) ) {
        push @ans_type, ( "bounce" => LJ::Lang::ml("support.answertype.bounce") );
    }

    return @ans_type;
}

sub file_request {
    my $errors = shift;
    my $o      = shift;

    my $email = $o->{'reqtype'} eq "email" ? $o->{'reqemail'} : "";
    unless ( LJ::is_enabled('loggedout_support_requests') || !$email ) {
        push @$errors, LJ::Lang::ml("error.support.mustbeloggedin");
    }
    my $log = {
        'uniq'  => $o->{'uniq'},
        'email' => $email
    };
    my $userid = 0;

    unless ($email) {
        if ( $o->{'reqtype'} eq "user" ) {
            my $u = LJ::load_userid( $o->{'requserid'} );
            $userid = $u->{'userid'};

            $log->{'user'}  = $u->user;
            $log->{'email'} = $u->email_raw;

            unless ( $u->is_person || $u->is_identity ) {
                push @$errors, LJ::Lang::ml("error.support.nonuser");
            }

            if ( LJ::sysban_check( 'support_user', $u->{'user'} ) ) {
                return LJ::Sysban::block( $userid, "Support request blocked based on user", $log );
            }

            $email = $u->email_raw || $o->{'reqemail'};
        }
    }

    if ( LJ::sysban_check( 'support_email', $email ) ) {
        return LJ::Sysban::block( $userid, "Support request blocked based on email", $log );
    }
    if ( LJ::sysban_check( 'support_uniq', $o->{'uniq'} ) ) {
        return LJ::Sysban::block( $userid, "Support request blocked based on uniq", $log );
    }

    my $reqsubject = LJ::trim( $o->{'subject'} );
    my $reqbody    = LJ::trim( $o->{'body'} );

    # remove the auth portion of any see_request links
    $reqbody = LJ::strip_request_auth($reqbody);

    unless ($reqsubject) {
        push @$errors, LJ::Lang::ml("error.support.nosummary");
    }
    unless ($reqbody) {
        push @$errors, LJ::Lang::ml("error.support.norequest");
    }

    my $cats = LJ::Support::load_cats();
    push @$errors, LJ::Lang::ml { "error.support.invalid_category" }
    unless $cats->{ $o->{'spcatid'} + 0 };

    if (@$errors) { return 0; }

    if ( LJ::is_enabled("support_request_language") ) {
        $o->{'language'} = undef unless grep { $o->{'language'} eq $_ } ( @LJ::LANGS, "xx" );
        $reqsubject = "[$o->{'language'}] $reqsubject"
            if $o->{'language'} && $o->{'language'} !~ /^en_/;
    }

    my $dbh = LJ::get_db_writer();

    my $dup_id     = 0;
    my $qsubject   = $dbh->quote($reqsubject);
    my $qbody      = $dbh->quote($reqbody);
    my $qreqtype   = $dbh->quote( $o->{'reqtype'} );
    my $qrequserid = $o->{'requserid'} + 0;
    my $qreqname   = $dbh->quote( $o->{'reqname'} );
    my $qreqemail  = $dbh->quote( $o->{'reqemail'} );
    my $qspcatid   = $o->{'spcatid'} + 0;

    my $scat = $cats->{$qspcatid};

    # make the authcode
    my $authcode  = LJ::make_auth_code(15);
    my $qauthcode = $dbh->quote($authcode);

    my $md5 = md5_hex("$qreqname$qreqemail$qsubject$qbody");
    my $sth;

    $dbh->do("LOCK TABLES support WRITE, duplock WRITE");

    unless ( $o->{ignore_dup_check} ) {
        $sth = $dbh->prepare(
"SELECT dupid FROM duplock WHERE realm='support' AND reid=0 AND userid=$qrequserid AND digest='$md5'"
        );
        $sth->execute;
        ($dup_id) = $sth->fetchrow_array;
        if ($dup_id) {
            $dbh->do("UNLOCK TABLES");
            return $dup_id;
        }
    }

    my ( $urlauth, $url, $spid );    # used at the bottom

    my $sql =
"INSERT INTO support (spid, reqtype, requserid, reqname, reqemail, state, authcode, spcatid, subject, timecreate, timetouched, timeclosed, timelasthelp) VALUES (NULL, $qreqtype, $qrequserid, $qreqname, $qreqemail, 'open', $qauthcode, $qspcatid, $qsubject, UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), 0, 0)";
    $sth = $dbh->prepare($sql);
    $sth->execute;

    if ( $dbh->err ) {
        my $error = $dbh->errstr;
        $dbh->do("UNLOCK TABLES");
        push @$errors, "<b>Database error:</b> (report this)<br>$error";
        return 0;
    }
    $spid = $dbh->{'mysql_insertid'};

    $dbh->do(
"INSERT INTO duplock (realm, reid, userid, digest, dupid, instime) VALUES ('support', 0, $qrequserid, '$md5', $spid, NOW())"
    ) unless $o->{ignore_dup_check};
    $dbh->do("UNLOCK TABLES");

    unless ($spid) {
        push @$errors, "<b>Database error:</b> (report this)<br>Didn't get a spid.";
        return 0;
    }

    # save meta-data for this request
    my @data;
    my $add_data = sub {
        my $q = $dbh->quote( $_[1] );
        return unless $q && $q ne 'NULL';
        push @data, "($spid, '$_[0]', $q)";
    };
    if ( LJ::is_enabled("support_request_language") && $o->{language} ne "xx" ) {
        $add_data->( $_, $o->{$_} ) foreach qw(uniq useragent language);
    }
    else {
        $add_data->( $_, $o->{$_} ) foreach qw(uniq useragent);
    }
    $dbh->do( "INSERT INTO supportprop (spid, prop, value) VALUES " . join( ',', @data ) );

    $dbh->do( "INSERT INTO supportlog (splid, spid, timelogged, type, faqid, userid, message) "
            . "VALUES (NULL, $spid, UNIX_TIMESTAMP(), 'req', 0, $qrequserid, $qbody)" );

    my $body;
    my $miniauth = mini_auth( { 'authcode' => $authcode } );
    $url     = "$LJ::SITEROOT/support/see_request?id=$spid";
    $urlauth = "$url&auth=$miniauth";

    $body = LJ::Lang::ml(
        "support.email.confirmation.body",
        {
            sitename => $LJ::SITENAME,
            subject  => $o->{'subject'},
            number   => $spid,
            url      => $urlauth
        }
    );

    if ( $scat->{user_closeable} ) {
        $body .= "\n\n" . LJ::Lang::ml("support.email.confirmation.close") . "\n\n";
        $body .= "$LJ::SITEROOT/support/act?close;$spid;$authcode";
    }

    # disable auto-replies for the entire category, or per request
    unless ( $scat->{'no_autoreply'} || $o->{'no_autoreply'} ) {
        LJ::send_mail(
            {
                'to'   => $email,
                'from' => $LJ::BOGUS_EMAIL,
                'fromname' =>
                    LJ::Lang::ml( "support.email.fromname", { sitename => $LJ::SITENAME } ),
                'charset' => 'utf-8',
                'subject' => LJ::Lang::ml( "support.email.subject", { number => $spid } ),
                'body'    => $body
            }
        );
    }

    support_notify( { spid => $spid, type => 'new' } );

    # and we're done
    return $spid;
}

sub append_request {
    my $sp = shift;    # support request to be appended to.
    my $re = shift;    # hashref of attributes of response to be appended
    my $sth;

    # $re->{'body'}
    # $re->{'type'}    (req, answer, comment, internal, screened)
    # $re->{'faqid'}
    # $re->{'remote'}  (remote if known)
    # $re->{'uniq'}    (uniq of remote)
    # $re->{'tier'}    (tier of response if type is answer or internal)

    my $remote   = $re->{'remote'};
    my $posterid = $remote ? $remote->{'userid'} : 0;

    # check for a sysban
    my $log = { 'uniq' => $re->{'uniq'} };
    if ($remote) {

        $log->{'user'}  = $remote->user;
        $log->{'email'} = $remote->email_raw;

        if ( LJ::sysban_check( 'support_user', $remote->{'user'} ) ) {
            return LJ::Sysban::block( $remote->{userid}, "Support request blocked based on user",
                $log );
        }
        if ( LJ::sysban_check( 'support_email', $remote->email_raw ) ) {
            return LJ::Sysban::block( $remote->{userid}, "Support request blocked based on email",
                $log );
        }
    }

    if ( LJ::sysban_check( 'support_uniq', $re->{'uniq'} ) ) {
        my $userid = $remote ? $remote->{'userid'} : 0;
        return LJ::Sysban::block( $userid, "Support request blocked based on uniq", $log );
    }

    my $message = $re->{'body'};
    $message =~ s/^\s+//;
    $message =~ s/\s+$//;

    my $dbh = LJ::get_db_writer();

    my $qmessage = $dbh->quote($message);
    my $qtype    = $dbh->quote( $re->{'type'} );

    my $qfaqid  = $re->{'faqid'} + 0;
    my $quserid = $posterid + 0;
    my $spid    = $sp->{'spid'} + 0;
    my $qtier   = $re->{'tier'} ? ( $re->{'tier'} + 0 ) . "0" : "NULL";

    my $sql;
    if ( LJ::is_enabled("support_response_tier") ) {
        $sql =
"INSERT INTO supportlog (splid, spid, timelogged, type, faqid, userid, message, tier) VALUES (NULL, $spid, UNIX_TIMESTAMP(), $qtype, $qfaqid, $quserid, $qmessage, $qtier)";
    }
    else {
        $sql =
"INSERT INTO supportlog (splid, spid, timelogged, type, faqid, userid, message) VALUES (NULL, $spid, UNIX_TIMESTAMP(), $qtype, $qfaqid, $quserid, $qmessage)";
    }
    $dbh->do($sql);
    my $splid = $dbh->{'mysql_insertid'};

    # mark this as an interesting update
    $dbh->do( 'UPDATE support SET timemodified=UNIX_TIMESTAMP() WHERE spid=?', undef, $spid );

    if ($posterid) {

        # add to our index of recently replied to support requests per-user.
        $dbh->do( "INSERT IGNORE INTO support_youreplied (userid, spid) VALUES (?, ?)",
            undef, $posterid, $spid );
        die $dbh->errstr if $dbh->err;

        # and also lazily clean out old stuff:
        $sth =
            $dbh->prepare( "SELECT s.spid FROM support s, support_youreplied yr "
                . "WHERE yr.userid=? AND yr.spid=s.spid AND s.state='closed' "
                . "AND s.timeclosed < UNIX_TIMESTAMP() - 3600*72" );
        $sth->execute($posterid);
        my @to_del;
        push @to_del, $_ while ($_) = $sth->fetchrow_array;
        if (@to_del) {
            my $in = join( ", ", map { $_ + 0 } @to_del );
            $dbh->do( "DELETE FROM support_youreplied WHERE userid=? AND spid IN ($in)",
                undef, $posterid );
        }
    }

    support_notify( { spid => $spid, splid => $splid, type => 'update' } );

    return $splid;
}

# userid may be undef/0 in the setting to zero case
sub set_points {
    my ( $spid, $userid, $points ) = @_;

    my $dbh = LJ::get_db_writer();
    if ($points) {
        $dbh->do( "REPLACE INTO supportpoints (spid, userid, points) " . "VALUES (?,?,?)",
            undef, $spid, $userid, $points );
    }
    else {
        $userid ||=
            $dbh->selectrow_array( "SELECT userid FROM supportpoints WHERE spid=?", undef, $spid );
        $dbh->do( "DELETE FROM supportpoints WHERE spid=?", undef, $spid );
    }

    $dbh->do(
        "REPLACE INTO supportpointsum (userid, totpoints, lastupdate) "
            . "SELECT userid, SUM(points), UNIX_TIMESTAMP() FROM supportpoints "
            . "WHERE userid=? GROUP BY 1",
        undef, $userid
    ) if $userid;

    # clear caches
    if ($userid) {
        my $u = LJ::load_userid($userid);
        delete $u->{_supportpointsum} if $u;

        my $memkey = [ $userid, "supportpointsum:$userid" ];
        LJ::MemCache::delete($memkey);
    }
}

# closes request, assigning points for the last response left to the request

sub close_request_with_points {
    my ( $sp, $spcat, $remote ) = @_;

    my $spid = $sp->{spid} + 0;
    my $dbh  = LJ::get_db_writer() or return;

    # close the request
    $dbh->do(
        'UPDATE support SET state="closed", '
            . 'timeclosed=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() WHERE spid=?',
        undef, $spid
    );
    die $dbh->errstr if $dbh->err;

    # check to see who should get the points
    my $response = $dbh->selectrow_hashref(
        'SELECT splid, timelogged, userid FROM supportlog '
            . 'WHERE spid=? AND type="answer" '
            . 'ORDER BY timelogged DESC LIMIT 1',
        undef, $spid
    );
    die $dbh->errstr if $dbh->err;

    # deliberately not using LJ::Support::append_request
    # to avoid sysban checks etc.; this sub is supposed to be fast.

    my $sth =
        $dbh->prepare( 'INSERT INTO supportlog '
            . '(spid, timelogged, type, userid, message) VALUES '
            . '(?, UNIX_TIMESTAMP(), "internal", ?, ?)' );

    unless ( defined $response ) {

        # no points awarded
        $sth->execute(
            $spid,
            LJ::want_userid($remote),
            "(Request has been closed as part of mass closure)"
        );
        die $sth->errstr if $sth->err;
        return 1;
    }

    # award the points
    my $userid = $response->{userid};
    my $points =
        LJ::Support::calc_points( $sp, $response->{timelogged} - $sp->{timecreate}, $spcat );

    LJ::Support::set_points( $spid, $userid, $points );

    my $username = LJ::want_user($userid)->display_name;

    $sth->execute( $spid, LJ::want_userid($remote),
              "(Request has been closed as part of mass closure, "
            . "granting $points points to $username for response #"
            . $response->{splid}
            . ")" );
    die $sth->errstr if $sth->err;
    return 1;
}

sub touch_request {
    my ($spid) = @_;

    # no touching if the request is locked
    return 0 if LJ::Support::is_locked($spid);

    my $dbh = LJ::get_db_writer();

    $dbh->do(
        "UPDATE support"
            . "   SET state='open', timeclosed=0, timetouched=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP()"
            . " WHERE spid=?",
        undef, $spid
    ) or return 0;

    set_points( $spid, undef, 0 );

    return 1;
}

# Extra email addresses are stored as support properties
# - nb_extra_addresses: number of extra addresses (if not present, 0)
# - extra_address_$n: extra address $n (0<=$n<nb_extra_addresses)

sub add_email_address {
    my ( $sp, $address ) = @_;

    # Already present?
    return if grep { $_ eq $address } all_email_addresses($sp);

    # Add
    my $props              = load_props( $sp->{spid} + 0 );
    my $nb_extra_addresses = $props->{nb_extra_addresses} || 0;
    set_prop( $sp->{spid}, 'nb_extra_addresses', $nb_extra_addresses + 1 );
    set_prop( $sp->{spid}, "extra_address_$nb_extra_addresses", $address );
}

sub all_email_addresses {
    my ($sp) = @_;

    my $props = load_props( $sp->{spid} + 0 );
    my @emails =
        map { $props->{"extra_address_$_"} } 0 .. ( ( $props->{nb_extra_addresses} || 0 ) - 1 );

    if ( $sp->{reqtype} eq 'email' ) {
        push @emails, $sp->{reqemail};
    }
    else {
        my $u = LJ::load_userid( $sp->{requserid} );
        push @emails, ( $u->email_raw || $sp->{reqemail} );
    }

    return @emails;
}

sub mail_response_to_user {
    my $sp    = shift;
    my $splid = shift;

    $splid += 0;

    my $res = load_response($splid);
    my $u;
    $u = LJ::load_userid( $sp->{requserid} ) if $sp->{reqtype} ne 'email';

    my $spid  = $sp->{'spid'} + 0;
    my $faqid = $res->{'faqid'} + 0;

    my $type = $res->{'type'};

    # don't mail internal comments (user shouldn't see) or
    # screened responses (have to wait for somebody to approve it first)
    return if ( $type eq "internal" || $type eq "screened" );

    # the only way it can be zero is if it's a reply to an email, so it's
    # problem the person replying to their own request, so we don't want
    # to mail them:
    return unless ( $res->{'userid'} );

    # also, don't send them their own replies:
    return if ( $sp->{'requserid'} == $res->{'userid'} );

    my $lang;
    $lang = LJ::Support::prop( $spid, 'language' )
        if LJ::is_enabled('support_request_language');
    $lang ||= $LJ::DEFAULT_LANG;

    my $body = "";
    my $dbh  = LJ::get_db_writer();
    $body .=
        $type eq "answer"
        ? LJ::Lang::ml( "support.email.update.body_a", { subject => $sp->{'subject'} } )
        : LJ::Lang::ml( "support.email.update.body_c", { subject => $sp->{'subject'} } );
    $body .= "\n";

    my $miniauth = mini_auth($sp);
    $body .= "($LJ::SITEROOT/support/see_request?id=$spid&auth=$miniauth).\n\n";

    $body .= "=" x 70 . "\n\n";
    if ($faqid) {

        # Get requesting username and journal URL, or example user's username
        # and journal URL
        my ( $user, $user_url );
        $u ||= LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
        $user =
            $u ? $u->user : "<b>" . LJ::Lang::ml("support.email.update.unknown_username") . "</b>";
        $user_url =
              $u
            ? $u->journal_base
            : "<b>" . LJ::Lang::ml("support.email.update.unknown_username") . "</b>";

        my $faq = LJ::Faq->load( $faqid, lang => $lang );
        if ($faq) {
            $faq->render_in_place;
            $body .= LJ::Lang::ml("support.email.update.faqref") . " " . $faq->question_raw . "\n";
            $body .= $faq->url_full;
            $body .= "\n\n";
        }
    }

    $body .= "$res->{'message'}\n\n";

    if ( $sp->{_cat}->{user_closeable} ) {
        my $closeurl = "$LJ::SITEROOT/support/act?close;$spid;$sp->{'authcode'}"
            . ( $type eq "answer" ? ";$splid" : "" );
        $body .= LJ::Lang::ml(
            "support.email.update.close",
            {
                close => $closeurl,
                reply => "$LJ::SITEROOT/support/see_request?id=$spid&auth=$miniauth"
            }
        );
        $body .= "\n\n";
    }

    $body .= LJ::Lang::ml("support.email.update.linkserror");

    my $fromemail;
    if ( $sp->{_cat}->{'replyaddress'} ) {
        my $miniauth = mini_auth($sp);
        $fromemail = $sp->{_cat}->{'replyaddress'};

        # insert mini-auth stuff:
        my $rep = "+${spid}z$miniauth\@";
        $fromemail =~ s/\@/$rep/;
    }
    else {
        $fromemail = $LJ::BOGUS_EMAIL;
        $body .= "\n\n" . LJ::Lang::ml("support.email.update.noreply");
    }

    foreach my $email ( all_email_addresses($sp) ) {
        LJ::send_mail(
            {
                to       => $email,
                from     => $fromemail,
                fromname => LJ::Lang::ml( 'support.email.fromname', { sitename => $LJ::SITENAME } ),
                charset  => 'utf-8',
                subject =>
                    LJ::Lang::ml( 'support.email.update.subject', { subject => $sp->{subject} } ),
                body => $body
            }
        );
    }

    if ( $type eq "answer" ) {
        $dbh->do(
"UPDATE support SET timelasthelp=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() WHERE spid=$spid"
        );
    }
}

sub mini_auth {
    my $sp = shift;
    return substr( $sp->{'authcode'}, 0, 4 );
}

sub support_notify {
    my $params  = shift;
    my $sclient = LJ::theschwartz()
        or return 0;

    my $h = $sclient->insert( "LJ::Worker::SupportNotify", $params );
    return $h ? 1 : 0;
}

package LJ::Worker::SupportNotify;
use base 'TheSchwartz::Worker';

sub work {
    my ( $class, $job ) = @_;
    my $a = $job->arg;

    # load basic stuff common to both paths
    my $type      = $a->{type};
    my $spid      = $a->{spid} + 0;
    my $load_body = $type eq 'new' ? 1 : 0;
    my $sp = LJ::Support::load_request( $spid, $load_body, { force => 1 } );    # force from master

    # we're only going to be reading anyway, but these jobs
    # sometimes get processed faster than replication allows,
    # causing the message not to load from the reader
    my $dbr = LJ::get_db_writer();

    # now branch a bit to select the right user information
    my $level = $type eq 'new' ? "'new', 'all'" : "'all'";
    my $data  = $dbr->selectcol_arrayref(
        "SELECT userid FROM supportnotify " . "WHERE spcatid=? AND level IN ($level)",
        undef, $sp->{_cat}{spcatid} );
    my $userids = LJ::load_userids(@$data);

    # prepare the email
    my $body;
    my @emails;

    if ( $type eq 'new' ) {
        my $show_name = $sp->{reqname};
        if ( $sp->{reqtype} eq 'user' ) {
            my $u = LJ::load_userid( $sp->{requserid} );
            $show_name = $u->display_name if $u;
        }

        $body = LJ::Lang::ml(
            "support.email.notif.new.body2",
            {
                sitename => $LJ::SITENAMESHORT,
                category => $sp->{_cat}{catname},
                subject  => $sp->{subject},
                username => LJ::trim($show_name),
                url      => "$LJ::SITEROOT/support/see_request?id=$spid",
                text     => $sp->{body}
            }
        );
        $body .= "\n\n" . "=" x 4 . "\n\n";
        $body .= LJ::Lang::ml(
            "support.email.notif.new.footer",
            {
                url     => "$LJ::SITEROOT/support/see_request?id=$spid",
                setting => "$LJ::SITEROOT/support/changenotify"
            }
        );

        foreach my $u ( values %$userids ) {
            next unless $u->is_visible;
            next unless $u->{status} eq "A";
            push @emails, $u->email_raw;
        }

    }
    elsif ( $type eq 'update' ) {

        # load the response we want to stuff in the email
        my ( $resp, $rtype, $posterid, $faqid ) =
            $dbr->selectrow_array(
            "SELECT message, type, userid, faqid FROM supportlog WHERE spid = ? AND splid = ?",
            undef, $sp->{spid}, $a->{splid} + 0 );

        # set up $show_name for this environment
        my $show_name;
        if ($posterid) {
            my $u = LJ::load_userid($posterid);
            $show_name = $u->display_name if $u;
        }

        $show_name ||= $sp->{reqname};

        # set up $response_type for this environment
        my $response_type = {
            req      => "New Request",        # not applicable here
            answer   => "Answer",
            comment  => "Comment",
            internal => "Internal Comment",
            screened => "Screened Answer",
        }->{$rtype};

        # build body
        $body = LJ::Lang::ml(
            "support.email.notif.update.body4",
            {
                sitename => $LJ::SITENAMESHORT,
                category => $sp->{_cat}{catname},
                subject  => $sp->{subject},
                username => LJ::trim($show_name),
                url      => "$LJ::SITEROOT/support/see_request?id=$spid",
                type     => $response_type
            }
        );
        if ($faqid) {

            # need to set up $lang
            my ( $lang, $u );
            $u    = LJ::load_userid($posterid) if $posterid;
            $lang = LJ::Support::prop( $spid, 'language' )
                if LJ::is_enabled('support_request_language');
            $lang ||= $LJ::DEFAULT_LANG;

            # now actually get the FAQ
            my $faq = LJ::Faq->load( $faqid, lang => $lang );
            if ($faq) {
                $faq->render_in_place;
                my $faqref = $faq->question_raw . " " . $faq->url_full;

                # now add it to the e-mail!
                $body .= "\n"
                    . LJ::Lang::ml(
                    "support.email.notif.update.body.faqref",
                    {
                        faqref => $faqref
                    }
                    );
                $body .= "\n";
            }
        }
        $body .= LJ::Lang::ml(
            "support.email.notif.update.body.text",
            {
                text => $resp
            }
        );
        $body .= "\n\n" . "=" x 4 . "\n\n";
        $body .= LJ::Lang::ml(
            "support.email.notif.update.footer",
            {
                url     => "$LJ::SITEROOT/support/see_request?id=$spid",
                setting => "$LJ::SITEROOT/support/changenotify"
            }
        );

        # now see who this should be sent to
        foreach my $u ( values %$userids ) {
            next unless $u->is_visible;
            next unless $u->{status} eq "A";
            next unless LJ::Support::can_read_response( $sp, $u, $rtype, $posterid );
            next
                if $posterid == $u->id
                && !$u->prop('opt_getselfsupport');
            push @emails, $u->email_raw;
        }
    }

    # send the email
    LJ::send_mail(
        {
            bcc      => join( ', ', @emails ),
            from     => $LJ::BOGUS_EMAIL,
            fromname => LJ::Lang::ml( "support.email.fromname", { sitename => $LJ::SITENAME } ),
            charset  => 'utf-8',
            subject  => (
                $type eq 'update'
                ? LJ::Lang::ml( "support.email.notif.update.subject", { number => $spid } )
                : LJ::Lang::ml( "support.email.subject",              { number => $spid } )
            ),
            body => $body,
            wrap => 1,
        }
    ) if @emails;

    $job->completed;
    return 1;
}

sub keep_exit_status_for { 0 }
sub grab_for             { 30 }
sub max_retries          { 5 }

sub retry_delay {
    my ( $class, $fails ) = @_;
    return 30;
}

1;
