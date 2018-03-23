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

use LJ::Auth;
use LJ::BetaFeatures;

########################################################################
### 6. What the App Shows to Users

=head2 What the App Shows to Users
=cut

# format unixtimestamp according to the user's timezone setting
sub format_time {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my $u = shift;
    my $time = shift;

    return undef unless $time;

    return eval { DateTime->from_epoch(epoch=>$time, time_zone=>$u->prop("timezone"))->ymd('-') } ||
                  DateTime->from_epoch(epoch => $time)->ymd('-');
}


# return whether or not a user is in a given beta key (as defined by %LJ::BETA_FEATURES)
# and enabled on the beta page
sub is_in_beta {
    my ( $u, $key ) = @_;
    return LJ::BetaFeatures->user_in_beta( $u => $key );
}


# sometimes when the app throws errors, we want to display "nice"
# text to end-users, while allowing admins to view the actual error message
sub show_raw_errors {
    my $u = shift;

    return 1 if $LJ::IS_DEV_SERVER;
    return 1 if $LJ::ENABLE_BETA_TOOLS;

    return 0 unless LJ::isu( $u );
    return 1 if $u->has_priv( "supporthelp" );
    return 1 if $u->has_priv( "supportviewscreened" );
    return 1 if $u->has_priv( "siteadmin" );

    return 0;
}


# returns a DateTime object corresponding to a user's "now"
sub time_now {
    my $u = shift;

    my $now = DateTime->now;

    # if user has timezone, use it!
    my $tz = $u->prop("timezone");
    return $now unless $tz;

    $now = eval { DateTime->from_epoch(
                                       epoch => time(),
                                       time_zone => $tz,
                                       );
              };

    return $now;
}


# return the user's timezone based on the prop if it's defined, otherwise best guess
sub timezone {
    my $u = shift;

    my $offset = 0;
    LJ::get_timezone($u, \$offset);
    return $offset;
}


########################################################################
### 7. Formatting Content Shown to Users

=head2 Formatting Content Shown to Users
=cut

sub ajax_auth_token {
    return LJ::Auth->ajax_auth_token( @_ );
}


# gets a user bio, from DB or memcache.
# optional argument: boolean, true to skip memcache and use cluster master.
sub bio {
    my ( $u, $force ) = @_;
    return unless $u && $u->has_bio;

    my $bio;

    $bio = $u->memc_get( 'bio' ) unless $force;
    return $bio if defined $bio;

    # not in memcache, fall back to disk
    my $db = @LJ::MEMCACHE_SERVERS || $force
             ? LJ::get_cluster_def_reader( $u )
             : LJ::get_cluster_reader( $u );
    return unless $db;
    $bio = $db->selectrow_array( "SELECT bio FROM userbio WHERE userid=?",
                                 undef, $u->userid );

    # set in memcache
    LJ::MemCache::add( [$u->id, "bio:" . $u->id], $bio );

    return $bio;
}


sub check_ajax_auth_token {
    return LJ::Auth->check_ajax_auth_token( @_ );
}


sub clusterid {
    return $_[0]->{clusterid};
}


# returns username or identity display name, not escaped
*display_username = \&display_name;
sub display_name {
    my $u = shift;
    return $u->user unless $u->is_identity;

    my $id = $u->identity;
    return "[ERR:unknown_identity]" unless $id;

    my ($url, $name);
    if ($id->typeid eq 'O') {
        $url = $id->value;

        # load the module conditionally
        $LJ::OPTMOD_OPENID_VERIFIED_IDENTITY = eval "use Net::OpenID::VerifiedIdentity; 1;"
            unless defined $LJ::OPTMOD_OPENID_VERIFIED_IDENTITY;
        $name = Net::OpenID::VerifiedIdentity::DisplayOfURL($url, $LJ::IS_DEV_SERVER)
            if $LJ::OPTMOD_OPENID_VERIFIED_IDENTITY;

        $name = LJ::Hooks::run_hook("identity_display_name", $name) || $name;

        ## Unescape %xx sequences
        $name =~ s/%([\dA-Fa-f]{2})/chr(hex($1))/ge;
    }
    return $name;
}


sub equals {
    my ($u1, $u2) = @_;
    return $u1 && $u2 && $u1->userid == $u2->userid;
}


sub has_bio {
    return $_[0]->{has_bio} eq "Y" ? 1 : 0;
}


# userid
*userid = \&id;
sub id {
    return $_[0]->{userid};
}


sub ljuser_display {
    my ( $u, $opts ) = @_;

    return LJ::ljuser( $u, $opts ) unless $u->is_identity;

    my $id = $u->identity;
    return "<b>????</b>" unless $id;

    # Mark accounts as deleted that aren't visible, memorial, locked, or
    # read-only
    $opts->{del} = 1 unless $u->is_visible || $u->is_memorial ||
            $u->is_locked || $u->is_readonly;

    my $andfull = $opts->{full} ? "&amp;mode=full" : "";
    my $img = $opts->{imgroot} || $LJ::IMGPREFIX;
    my $strike = $opts->{del} ? ' text-decoration: line-through;' : '';
    my $profile_url = $opts->{profile_url} || '';
    my $journal_url = $opts->{journal_url} || '';
    my $display_class = $opts->{no_ljuser_class} ? "" : " class='ljuser'";
    my $type = $u->journaltype_readable;

    my ($url, $name);

    if ($id->typeid eq 'O') {
        $url = $journal_url ne '' ? $journal_url : $id->value;
        $name = $u->display_name;

        $url ||= "about:blank";
        $name ||= "[no_name]";

        $url = LJ::ehtml($url);
        $name = LJ::ehtml($name);

        my ($imgurl, $width, $height);
        my $head_size = $opts->{head_size};
        if ($head_size) {
            $imgurl = "$img/silk/${head_size}/openid.png";
            $width = $head_size;
            $height = $head_size;
        } else {
            $imgurl = "$img/silk/identity/openid.png";
            $width = 16;
            $height = 16;
        }

        my $profile = $profile_url ne '' ? $profile_url :
            "$LJ::SITEROOT/profile?userid=" . $u->userid . "&amp;t=I$andfull";

        my $lj_user = $opts->{no_ljuser_class} ? "" : " lj:user='$name'";
        return "<span$lj_user style='white-space: nowrap;$strike'$display_class><a href='$profile'>" .
            "<img src='$imgurl' alt='[$type profile] ' width='$width' height='$height'" .
            " style='vertical-align: text-bottom; border: 0; padding-right: 1px;' /></a>" .
            "<a href='$url' rel='nofollow'><b>$name</b></a></span>";

    } else {
        return "<b>????</b>";
    }
}


# returns the user-specified name of a journal in valid UTF-8
# and with HTML escaped
sub name_html {
    my $u = shift;
    return LJ::ehtml($u->name_raw);
}


# returns the user-specified name of a journal exactly as entered
sub name_orig {
    my $u = shift;
    return $u->{name};
}


# returns the user-specified name of a journal in valid UTF-8
sub name_raw {
    my $u = shift;
    LJ::text_out(\$u->{name});
    return $u->{name};
}


sub new_from_row {
    my ($class, $row) = @_;
    my $u = bless $row, $class;

    # for selfassert method below:
    $u->{_orig_userid} = $u->userid;
    $u->{_orig_user}   = $u->user;

    return $u;
}


sub username_from_url {
    my ( $class, $url ) = @_;

    # this doesn't seem to like URLs with ?...
    $url =~ s/\?.+$//;

    # /users, /community, or /~
    if ($url =~ m!^\Q$LJ::SITEROOT\E/(?:users/|community/|~)([\w-]+)/?!) {
        return LJ::canonical_username( $1 );
    }

    # user subdomains
    if ($LJ::USER_DOMAIN && $url =~ m!^https?://([\w-]+)\.\Q$LJ::USER_DOMAIN\E/?$!) {
        return LJ::canonical_username( $1 );
    }

    # subdomains that hold a bunch of users (eg, users.siteroot.com/username/)
    if ($url =~ m!^https?://\w+\.\Q$LJ::USER_DOMAIN\E/([\w-]+)/?$!) {
        return LJ::canonical_username( $1 );
    }

    return undef;
}


sub new_from_url {
    my ($class, $url) = @_;

    my $username = $class->username_from_url( $url );
    return LJ::load_user( $username )
        if defined $username;
    return undef;
}


# if bio_absent is set to "yes", bio won't be updated
sub set_bio {
    my ( $u, $text, $bio_absent ) = @_;
    $bio_absent = "" unless $bio_absent;

    my $oldbio = $u->bio;
    my $newbio = $bio_absent eq "yes" ? $oldbio : $text;
    my $has_bio = ( $newbio =~ /\S/ ) ? "Y" : "N";

    $u->update_self( { has_bio => $has_bio } );

    # update their bio text
    return if ( $oldbio eq $text ) || ( $bio_absent eq "yes" );

    if ( $has_bio eq "N" ) {
        $u->do( "DELETE FROM userbio WHERE userid=?", undef, $u->id );
        $u->dudata_set( 'B', 0, 0 );
    } else {
        $u->do( "REPLACE INTO userbio (userid, bio) VALUES (?, ?)",
                undef, $u->id, $text );
        $u->dudata_set( 'B', 0, length( $text ) );
    }
    $u->memc_set( 'bio', $text );
}


sub url {
    my $u = shift;

    my $url;

    if ( $u->is_identity && ! $u->prop( 'url' ) ) {
        my $id = $u->identity;
        if ($id && $id->typeid eq 'O') {
            $url = $id->value;
            $u->set_prop("url", $url) if $url;
        }
    }

    # not openid, what does their 'url' prop say?
    $url ||= $u->prop( 'url' );
    return undef unless $url;

    $url = "http://$url" unless $url =~ m!^https?://!;

    return $url;
}


# returns username
*username = \&user;
sub user {
    return $_[0]->{user};
}


########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

########################################################################
###  6. What the App Shows to Users

=head2 What the App Shows to Users (LJ)
=cut

# <LJFUNC>
# name: LJ::get_times_multi
# des: Get the last update time and time create.
# args: opt?, uids
# des-opt: optional hashref, currently can contain 'memcache_only'
#          to only retrieve data from memcache
# des-uids: list of userids to load timeupdate and timecreate for
# returns: hashref; uid => {timeupdate => unix timeupdate, timecreate => unix timecreate}
# </LJFUNC>
sub get_times_multi {
    my ($opt, @uids) = @_;

    # allow optional opt hashref as first argument
    unless (ref $opt eq 'HASH') {
        push @uids, $opt;
        $opt = {};
    }
    return {} unless @uids;

    my @memkeys = map { [$_, "tu:$_"], [$_, "tc:$_"] } @uids;
    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    my @need  = ();
    my %times = ();
    foreach my $uid (@uids) {
        my ($tc, $tu) = ('', '');
        if ($tu = $mem->{"tu:$uid"}) {
            $times{updated}->{$uid} = unpack("N", $tu);
        }
        if ($tc = $mem->{"tc:$_"}){
            $times{created}->{$_} = $tc;
        }

        push @need => $uid
            unless $tc and $tu;
    }

    # if everything was in memcache, return now
    return \%times if $opt->{'memcache_only'} or not @need;

    # fill in holes from the database.  safe to use the reader because we
    # only do an add to memcache, whereas postevent does a set, overwriting
    # any potentially old data
    my $dbr = LJ::get_db_reader();
    my $need_bind = join(",", map { "?" } @need);

    # Fetch timeupdate and timecreate from DB.
    # Timecreate is loaded in pre-emptive goals.
    # This is tiny optimization for 'get_timecreate_multi',
    # which is called right after this method during
    # friends page generation.
    my $sth = $dbr->prepare("
        SELECT userid,
               UNIX_TIMESTAMP(timeupdate),
               UNIX_TIMESTAMP(timecreate)
        FROM   userusage
        WHERE
               userid IN ($need_bind)");
    $sth->execute(@need);
    while (my ($uid, $tu, $tc) = $sth->fetchrow_array){
        $times{updated}->{$uid} = $tu;
        $times{created}->{$uid} = $tc;

        # set memcache for this row
        LJ::MemCache::add([$uid, "tu:$uid"], pack("N", $tu), 30*60);
        # set this for future use
        LJ::MemCache::add([$uid, "tc:$uid"], $tc, 60*60*24); # as in LJ::User->timecreate
    }

    return \%times;
}


# <LJFUNC>
# name: LJ::get_timeupdate_multi
# des: Get the last time a list of users updated.
# args: opt?, uids
# des-opt: optional hashref, currently can contain 'memcache_only'
#          to only retrieve data from memcache
# des-uids: list of userids to load timeupdates for
# returns: hashref; uid => unix timeupdate
# </LJFUNC>
sub get_timeupdate_multi {
    my ($opt, @uids) = @_;

    # allow optional opt hashref as first argument
    if ( $opt && ref $opt ne 'HASH' ) {
        push @uids, $opt;
        $opt = {};
    }
    return {} unless @uids;

    my @memkeys = map { [$_, "tu:$_"] } @uids;
    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    my @need;
    my %timeupdate; # uid => timeupdate
    foreach (@uids) {
        if ($mem->{"tu:$_"}) {
            $timeupdate{$_} = unpack("N", $mem->{"tu:$_"});
        } else {
            push @need, $_;
        }
    }

    # if everything was in memcache, return now
    return \%timeupdate if $opt->{'memcache_only'} || ! @need;

    # fill in holes from the database.  safe to use the reader because we
    # only do an add to memcache, whereas postevent does a set, overwriting
    # any potentially old data
    my $dbr = LJ::get_db_reader();
    my $need_bind = join(",", map { "?" } @need);
    my $sth = $dbr->prepare("SELECT userid, UNIX_TIMESTAMP(timeupdate) " .
                            "FROM userusage WHERE userid IN ($need_bind)");
    $sth->execute(@need);
    while (my ($uid, $tu) = $sth->fetchrow_array) {
        $timeupdate{$uid} = $tu;

        # set memcache for this row
        $tu = 0 unless defined $tu;  # don't try to pack an undefined value
        LJ::MemCache::add([$uid, "tu:$uid"], pack("N", $tu), 30*60);
    }

    return \%timeupdate;
}


# <LJFUNC>
# name: LJ::get_timezone
# des: Gets the timezone offset for the user.
# args: u, offsetref, fakedref
# des-u: user object.
# des-offsetref: reference to scalar to hold timezone offset;
# des-fakedref: reference to scalar to hold whether this timezone was
#               faked.  0 if it is the timezone specified by the user.
# returns: nonzero if successful.
# </LJFUNC>
sub get_timezone {
    my ($u, $offsetref, $fakedref) = @_;

    # See if the user specified their timezone
    if (my $tz = $u->prop('timezone')) {
        # If the eval fails, we'll fall through to guessing instead
        my $dt = eval {
            DateTime->from_epoch(
                                 epoch => time(),
                                 time_zone => $tz,
                                 );
        };

        if ($dt) {
            $$offsetref = $dt->offset() / (60 * 60); # Convert from seconds to hours
            $$fakedref  = 0 if $fakedref;

            return 1;
        }
    }

    # Either the user hasn't set a timezone or we failed at
    # loading it.  We guess their current timezone's offset
    # by comparing the gmtime of their last post with the time
    # they specified on that post.

    # first, check request cache
    my $timezone = $u->{_timezone_guess};
    if ($timezone) {
        $$offsetref = $timezone;
        return 1;
    }

    # next, check memcache
    my $memkey = [$u->userid, 'timezone_guess:' . $u->userid];
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $u->{_timezone_guess} = $memcache_data;
        $$offsetref = $memcache_data;
        return 1;
    }

    # nothing in cache; check db
    my $dbcr = LJ::get_cluster_def_reader($u);
    return 0 unless $dbcr;

    $$fakedref = 1 if $fakedref;

    # grab the times on the last post that wasn't backdated.
    # (backdated is rlogtime == $LJ::EndOfTime)
    if (my $last_row = $dbcr->selectrow_hashref(
        qq{
            SELECT rlogtime, eventtime
            FROM log2
            WHERE journalid = ? AND rlogtime <> ?
            ORDER BY rlogtime LIMIT 1
        }, undef, $u->userid, $LJ::EndOfTime)) {
        my $logtime = $LJ::EndOfTime - $last_row->{'rlogtime'};
        my $eventtime = LJ::mysqldate_to_time($last_row->{'eventtime'}, 1);
        my $hourdiff = ($eventtime - $logtime) / 3600;

        # if they're up to a quarter hour behind, round up.
        $hourdiff = $hourdiff > 0 ? int($hourdiff + 0.25) : int($hourdiff - 0.25);

        # if the offset is more than 24h in either direction, then the last
        # entry is probably unreliable. don't use any offset at all.
        $$offsetref = (-24 < $hourdiff && $hourdiff < 24) ? $hourdiff : 0;

        # set the caches
        $u->{_timezone_guess} = $$offsetref;
        my $expire = 60*60*24; # 24 hours
        LJ::MemCache::set($memkey, $$offsetref, $expire);
    }

    return 1;
}


# <LJFUNC>
# class: component
# name: LJ::ljuser
# des: Make link to profile/journal of user.
# info: Returns the HTML for a profile/journal link pair for a given user
#       name, just like LJUSER does in BML.  This is for files like cleanhtml.pl
#       and ljpoll.pl which need this functionality too, but they aren't run as BML.
# args: user, opts?
# des-user: Username to link to, or user hashref.
# des-opts: Optional hashref to control output.  Key 'full' when true causes
#           a link to the mode=full profile.   Key 'type' when 'C' makes
#           a community link, when 'Y' makes a syndicated account link,
#           when 'I' makes an identity account link (e.g. OpenID),
#           otherwise makes a user account
#           link. If user parameter is a hashref, its 'journaltype' overrides
#           this 'type'.  Key 'del', when true, makes a tag for a deleted user.
#           If user parameter is a hashref, its 'statusvis' overrides 'del'.
#           Key 'no_follow', when true, disables traversal of renamed users.
# returns: HTML with a little head image & bold text link.
# </LJFUNC>
sub ljuser {
    my ( $user, $opts ) = @_;

    my $andfull = $opts->{'full'} ? "?mode=full" : "";
    my $img = $opts->{'imgroot'} || $LJ::IMGPREFIX;
    my $profile_url = $opts->{'profile_url'} || '';
    my $journal_url = $opts->{'journal_url'} || '';
    my $display_class = $opts->{no_ljuser_class} ? "" : " class='ljuser'";
    my $profile;

    my $make_tag = sub {
        my ($fil, $url, $x, $y, $type) = @_;
        $y ||= $x;  # make square if only one dimension given
        my $strike = $opts->{'del'} ? ' text-decoration: line-through;' : '';

        # Backwards check, because we want it to default to on
        my $bold = (exists $opts->{'bold'} and $opts->{'bold'} == 0) ? 0 : 1;
        my $ljusername = $bold ? "<b>$user</b>" : "$user";
        my $lj_user = $opts->{no_ljuser_class} ? "" : " lj:user='$user'";

        my $alttext = $type ? "$type profile" : "profile";

        my $link_color = "";
        # Make sure it's really a color
        if ($opts->{'link_color'} && $opts->{'link_color'} =~ /^#([a-fA-F0-9]{3}|[a-fA-F0-9]{6})$/) {
            $link_color = " style='color: " . $opts->{'link_color'} . ";'";
        }

        $profile = $profile_url ne '' ? $profile_url : $profile . $andfull;
        $url = $journal_url ne '' ? $journal_url : $url;

        return "<span$lj_user style='white-space: nowrap;$strike'$display_class>" .
            "<a href='$profile'><img src='$img/$fil' alt='[$alttext] ' width='$x' height='$y'" .
            " style='vertical-align: text-bottom; border: 0; padding-right: 1px;' /></a>" .
            "<a href='$url'$link_color>$ljusername</a></span>";
    };

    my $u = isu($user) ? $user : LJ::load_user($user);

    # Traverse the renames to the final journal
    if ($u && !$opts->{'no_follow'}) {
        ( $u, $user ) = $u->get_renamed_user;
    }

    # if invalid user, link to dummy userinfo page
    unless ($u && isu($u)) {
        $user = LJ::canonical_username($user);
        $profile = "$LJ::SITEROOT/profile?user=$user";
        return $make_tag->('silk/identity/user.png', "$LJ::SITEROOT/profile?user=$user", 17);
    }

    $profile = $u->profile_url;

    my $type = $u->journaltype;
    my $type_readable = $u->journaltype_readable;

    # Mark accounts as deleted that aren't visible, memorial, locked, or read-only
    $opts->{'del'} = 1 unless $u->is_visible || $u->is_memorial || $u->is_locked || $u->is_readonly;
    $user = $u->user;

    my $url = $u->journal_base . "/";
    my $head_size = $opts->{head_size};

    if (my ($icon, $size) = LJ::Hooks::run_hook("head_icon", $u, head_size => $head_size)) {
        return $make_tag->($icon, $url, $size || 16) if $icon;
    }

    if ( $type eq 'C' ) {
        if ( $u->get_cap( 'staff_headicon' ) ) {
            return $make_tag->( "silk/${head_size}/comm_staff.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'comm_staff.png', $url, 16, '', 'site community' );
        } else {
            return $make_tag->( "silk/${head_size}/community.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/community.png', $url, 16, '', $type_readable );
        }
    } elsif ( $type eq 'Y' ) {
        return $make_tag->( "silk/${head_size}/feed.png", $url, $head_size, '', $type_readable ) if $head_size;
        return $make_tag->( 'silk/identity/feed.png', $url, 16, '', $type_readable );
    } elsif ( $type eq 'I' ) {
        return $u->ljuser_display($opts);
    } else {
        if ( $u->get_cap( 'staff_headicon' ) ) {
            return $make_tag->( "silk/${head_size}/user_staff.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/user_staff.png', $url, 17, '', 'staff' );
        }
        else {
            return $make_tag->( "silk/${head_size}/user.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/user.png', $url, 17, '', $type_readable );
        }
    }
}


1;
