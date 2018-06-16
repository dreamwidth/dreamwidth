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

package LJ::Sysban;

=head1 Methods

=cut

# <LJFUNC>
# name: LJ::sysban_check
# des: Given a 'what' and 'value', checks to see if a ban exists.
# args: what, value
# des-what: The ban type
# des-value: The value which triggers the ban
# returns: 1 if a ban exists, 0 otherwise
# </LJFUNC>
sub sysban_check {
    my ($what, $value) = @_;

    # cache if noanon_ip ban
    if ($what eq 'noanon_ip') {

        my $now = time();
        my $ip_ban_delay = $LJ::SYSBAN_IP_REFRESH || 120;

        # check memcache first if not loaded
        $LJ::NOANON_IP_BANNED_LOADED = 0 unless defined $LJ::NOANON_IP_BANNED_LOADED;
        unless ($LJ::NOANON_IP_BANNED_LOADED + $ip_ban_delay > $now) {
            my $memval = LJ::MemCache::get("sysban:noanon_ip");
            if ($memval) {
                *LJ::NOANON_IP_BANNED = $memval;
                $LJ::NOANON_IP_BANNED_LOADED = $now;
            } else {
                $LJ::NOANON_IP_BANNED_LOADED = 0;
            }
        }

        # is it already cached in memory?
        if ($LJ::NOANON_IP_BANNED_LOADED) {
            return (defined $LJ::NOANON_IP_BANNED{$value} &&
                    ($LJ::NOANON_IP_BANNED{$value} == 0 ||     # forever
                     $LJ::NOANON_IP_BANNED{$value} > time())); # not-expired
        }

        # set this before the query
        $LJ::NOANON_IP_BANNED_LOADED = time();

        sysban_populate( \%LJ::NOANON_IP_BANNED, "noanon_ip" )
            or return undef $LJ::NOANON_IP_BANNED_LOADED;

        # set in memcache
        LJ::MemCache::set("sysban:noanon_ip", \%LJ::NOANON_IP_BANNED, $ip_ban_delay);

        # return value to user
        return $LJ::NOANON_IP_BANNED{$value};
    }

    # cache if ip ban
    if ($what eq 'ip') {

        my $now = time();
        my $ip_ban_delay = $LJ::SYSBAN_IP_REFRESH || 120;

        # check memcache first if not loaded
        $LJ::IP_BANNED_LOADED = 0 unless defined $LJ::IP_BANNED_LOADED;
        unless ($LJ::IP_BANNED_LOADED + $ip_ban_delay > $now) {
            my $memval = LJ::MemCache::get("sysban:ip");
            if ($memval) {
                *LJ::IP_BANNED = $memval;
                $LJ::IP_BANNED_LOADED = $now;
            } else {
                $LJ::IP_BANNED_LOADED = 0;
            }
        }

        # is it already cached in memory?
        if ($LJ::IP_BANNED_LOADED) {
            return (defined $LJ::IP_BANNED{$value} &&
                    ($LJ::IP_BANNED{$value} == 0 ||     # forever
                     $LJ::IP_BANNED{$value} > time())); # not-expired
        }

        # set this before the query
        $LJ::IP_BANNED_LOADED = time();

        sysban_populate( \%LJ::IP_BANNED, "ip" )
            or return undef $LJ::IP_BANNED_LOADED;

        # set in memcache
        LJ::MemCache::set("sysban:ip", \%LJ::IP_BANNED, $ip_ban_delay);

        # return value to user
        return $LJ::IP_BANNED{$value};
    }

    # cache if uniq ban
    if ($what eq 'uniq') {

        # check memcache first if not loaded
        $LJ::UNIQ_BANNED_LOADED = 0 unless defined $LJ::UNIQ_BANNED_LOADED;
        unless ($LJ::UNIQ_BANNED_LOADED) {
            my $memval = LJ::MemCache::get("sysban:uniq");
            if ($memval) {
                *LJ::UNIQ_BANNED = $memval;
                $LJ::UNIQ_BANNED_LOADED++;
            }
        }

        # is it already cached in memory?
        if ($LJ::UNIQ_BANNED_LOADED) {
            return (defined $LJ::UNIQ_BANNED{$value} &&
                    ($LJ::UNIQ_BANNED{$value} == 0 ||     # forever
                     $LJ::UNIQ_BANNED{$value} > time())); # not-expired
        }

        # set this now before the query
        $LJ::UNIQ_BANNED_LOADED++;

        sysban_populate( \%LJ::UNIQ_BANNED, "uniq" )
            or return undef $LJ::UNIQ_BANNED_LOADED;

        # set in memcache
        my $exp = 60*15; # 15 minutes
        LJ::MemCache::set("sysban:uniq", \%LJ::UNIQ_BANNED, $exp);

        # return value to user
        return $LJ::UNIQ_BANNED{$value};
    }

    # cache if spamreport ban
    if ( $what eq 'spamreport' ) {
        # check memcache first if not loaded
        $LJ::SPAM_BANNED_LOADED = 0
            unless defined $LJ::SPAMREPORT_BANNED_LOADED;
        unless ( $LJ::SPAMREPORT_BANNED_LOADED ) {
            my $memval = LJ::MemCache::get( "sysban:spamreport" );
            if ( $memval ) {
                *LJ::SPAMREPORT_BANNED = $memval;
                $LJ::SPAMREPORT_BANNED_LOADED++;
            }
        }

        # is it already cached in memory?
        if ( $LJ::SPAMREPORT_BANNED_LOADED ) {
            return ( defined $LJ::SPAMREPORT_BANNED{$value} &&
                    ( $LJ::SPAMREPORT_BANNED{$value} == 0 ||        # forever
                      $LJ::SPAMREPORT_BANNED{$value} > time() ) );  # not expired
        }

        # set this now before the query
        $LJ::SPAMREPORT_BANNED_LOADED++;

        sysban_populate( \%LJ::SPAMREPORT_BANNED, "spamreport" )
            or return undef $LJ::SPAMREPORT_BANNED_LOADED;

        # set in memcache
        my $exp = 60 * 30; # 30 minutes
        LJ::MemCache::set( "sysban:spamreport", \%LJ::SPAMREPORT_BANNED, $exp );

        # return value to user
        return $LJ::SPAMREPORT_BANNED{$value};
    }

    # need the db below here
    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    # standard check helper
    my $check = sub {
        my ($wh, $vl) = @_;

        return $dbr->selectrow_array(qq{
                SELECT COUNT(*)
                FROM sysban
                WHERE status = 'active'
                  AND what = ?
                  AND value = ?
                  AND NOW() > bandate
                  AND (NOW() < banuntil
                       OR banuntil = 0
                       OR banuntil IS NULL)
            }, undef, $wh, $vl);
    };

    # helper variation for wildcard match of domain bans
    my $check_subdomains = sub {
        my ( $host ) = @_;
        return 0 unless $host && $host =~ /\./;

        # very similar to above, except in addition to exact match
        # we also check for wildcard matches of larger banned domains
        # e.g. foo.bar.org will match ban for "%.bar.org"

        return $dbr->selectrow_array( qq{
                SELECT COUNT(*) FROM sysban
                WHERE status = 'active'
                  AND what = ?
                  AND (value = ? OR ? LIKE CONCAT("%.", value))
                  AND NOW() > bandate
                  AND (NOW() < banuntil
                       OR banuntil = 0
                       OR banuntil IS NULL)
            }, undef, 'email_domain', $host, $host );
    };

    # check both ban by email and ban by domain if we have an email address
    if ($what eq 'email') {
        # short out if this email really is banned directly, or if we can't parse it
        return 1 if $check->('email', $value);
        return 0 unless $value =~ /@(.+)$/;

        # see if this domain is banned, either directly
        # or else as part of a larger domain ban
        return 1 if $check_subdomains->( $1 );

        # account for GMail troll tricks
        my @domains = split(/\./, $1);
        return 0 unless scalar @domains >= 2;
        my $domain = "$domains[-2].$domains[-1]";

        if ( $domain eq "gmail.com" ) {
        	my ($user) = ($value =~ /^(.+)@/);
        	$user =~ s/\.//g;    # strip periods
        	$user =~ s/\+.*//g;  # strip plus tags
        	return 1 if $check->('email', "$user\@$domain");
        }

        # must not be banned
        return 0;
    }

    # non-ip bans come straight from the db
    return $check->($what, $value);
}
*LJ::sysban_check = \&sysban_check;

# takes a hashref to populate with 'value' => expiration  pairs
# takes a 'what' to populate the hashref with sysbans of that type
# returns undef on failure, hashref on success
sub sysban_populate {
    my ($where, $what) = @_;

    # call normally if no gearman/not wanted
    my $gc = LJ::gearman_client();
    return _db_sysban_populate( $where, $what )
        unless $gc && LJ::conf_test($LJ::LOADSYSBAN_USING_GEARMAN);

    # invoke gearman
    my $args = Storable::nfreeze({what => $what});
    my $task = Gearman::Task->new("sysban_populate", \$args,
                                  {
                                      uniq => $what,
                                      on_complete => sub {
                                          my $res = shift;
                                          return unless $res;

                                          my $rv = Storable::thaw($$res);
                                          return unless $rv;

                                          $where->{$_} = $rv->{$_} foreach keys %$rv;
                                      }
                                  });
    my $ts = $gc->new_task_set();
    $ts->add_task($task);
    $ts->wait(timeout => 30); # 30 sec timeout

    return $where;
}


sub _db_sysban_populate {
    my ($where, $what) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # build cache from db
    my $sth = $dbh->prepare("SELECT value, UNIX_TIMESTAMP(banuntil) " .
                            "FROM sysban " .
                            "WHERE status='active' AND what=? " .
                            "AND NOW() > bandate " .
                            "AND (NOW() < banuntil OR banuntil IS NULL)");
    $sth->execute($what);
    return undef if $sth->err;
    while (my ($val, $exp ) = $sth->fetchrow_array) {
        $where->{$val} = $exp || 0;
    }

    return $where;

}

# <LJFUNC>
# name: LJ::Sysban::populate_full
# des: populates a hashref with sysbans of given type
# args: where, what
# des-where: the hashref to populate with hash of hashes:
#            value => { expire => expiration, note => note,
#                        banid => banid } for each ban
# des-what: the type of sysban to look up
# returns: hashref on success, undef on failure
# </LJFUNC>
sub populate_full {
    return _db_sysban_populate_full( @_ );
}

sub _db_sysban_populate_full {
    my ( $where, $what, $limit, $skip ) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # build cache from db
    my $limitsql = $limit ? " ORDER BY banid DESC LIMIT ? OFFSET ?" : "";
    my $sth = $dbh->prepare( "SELECT banid, value, " .
                             "UNIX_TIMESTAMP(banuntil), note " .
                             "FROM sysban " .
                             "WHERE status='active' AND what=? " .
                             "AND NOW() > bandate " .
                             "AND (NOW() < banuntil OR banuntil IS NULL)" .
                             $limitsql );
    $sth->execute( $what, $limit, $skip );
    return undef if $sth->err;
    while (my ($banid, $val, $exp, $note) = $sth->fetchrow_array) {
        $where->{$val}->{banid}  = $banid || 0;
        $where->{$val}->{expire} = $exp   || 0;
        $where->{$val}->{note}   = $note  || 0;
    }

    return $where;

}


=head2 C<< LJ::Sysban::populate_full_by_value( $value, @types ) >>

List all sysbans for the given value, of the specified types. This can be used, for example, to limit the sysban to only the privs that this user can see.
Returns a hashref of hashes in the format:
    what => { expire => expiration, note => note, banid => banid }

=cut

sub populate_full_by_value {
    my ( $value, @types ) = @_;
    return _db_sysban_populate_full_by_value( $value, @types );
}

sub _db_sysban_populate_full_by_value {
    my ( $value, @types ) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $in_what = "";
    my $has_all = 0;

    $in_what = join ", ", map { $dbh->quote( $_ ) } @types
        unless $has_all;
    $in_what = " AND what IN ( $in_what )"
        if $in_what;

    # build cache from db
    my $sth = $dbh->prepare(
        qq{SELECT banid, what, UNIX_TIMESTAMP(banuntil), note
           FROM sysban
           WHERE status = 'active'
                 AND value = ?
                 $in_what
                 AND NOW() > bandate
                 AND ( NOW() < banuntil OR banuntil IS NULL )
        }
    );
    $sth->execute( $value );
    return undef if $sth->err;

    my $where;
    while ( my ( $banid, $what, $exp, $note ) = $sth->fetchrow_array ) {
        $where->{$what}->{banid} = $banid || 0;
        $where->{$what}->{expire} = $exp || 0;
        $where->{$what}->{note} = $note || 0;
    }

    return $where;
}


# <LJFUNC>
# name: LJ::Sysban::note
# des: Inserts a properly-formatted row into [dbtable[statushistory]] noting that a ban has been triggered.
# args: userid?, notes, vars
# des-userid: The userid which triggered the ban, if available.
# des-notes: A very brief description of what triggered the ban.
# des-vars: A hashref of helpful variables to log, keys being variable name and values being values.
# returns: nothing
# </LJFUNC>
sub note
{
    my ($userid, $notes, $vars) = @_;

    $notes .= ":";
    map { $notes .= " $_=$vars->{$_};" if $vars->{$_} } sort keys %$vars;
    LJ::statushistory_add($userid, 0, 'sysban_trig', $notes);

    return;
}

# <LJFUNC>
# name: LJ::Sysban::block
# des: Notes a sysban in [dbtable[statushistory]] and returns a fake HTTP error message to the user.
# args: userid?, notes, vars
# des-userid: The userid which triggered the ban, if available.
# des-notes: A very brief description of what triggered the ban.
# des-vars: A hashref of helpful variables to log, keys being variable name and values being values.
# returns: nothing
# </LJFUNC>
sub block
{
    my ($userid, $notes, $vars) = @_;

    note( $userid, $notes, $vars );

    my $msg = <<'EOM';
<html>
<head>
<title>503 Service Unavailable</title>
</head>
<body>
<h1>503 Service Unavailable</h1>
The service you have requested is temporarily unavailable.
</body>
</html>
EOM

    # may not run from web context (e.g. mailgated.pl -> supportlib -> ..)
    eval { BML::http_response(200, $msg); };

    return;
}

# <LJFUNC>
# name: LJ::Sysban::create
# des: creates a sysban.
# args: what, value, bandays, note
# des-what: the criteria we're sysbanning on
# des-value: the value we're banning
# des-bandays: length of sysban (0 for forever)
# des-note: note to go with the ban (optional)
# info: Takes args as a hash.
# returns: BanID on success, error object on failure
# </LJFUNC>
sub create {

    my %opts = @_;

    unless ( $opts{what} && $opts{value} && defined $opts{bandays} ) {
        return bless {
            message => "Wrong arguments passed; should be a hash\n",
        }, 'ERROR';
    }

    if ( $opts{note} && length( $opts{note} ) > 255 ) {
        return bless {
            message => "Note too long; must be less than 256 characters\n",
        }, 'ERROR';
    }


    my $dbh = LJ::get_db_writer();

    my $banuntil = "NULL";
    if ($opts{'bandays'}) {
        $banuntil = "NOW() + INTERVAL " . $dbh->quote($opts{'bandays'}) . " DAY";
    }

    # strip out leading/trailing whitespace
    $opts{'value'} = LJ::trim($opts{'value'});

    # do insert
    $dbh->do( "INSERT INTO sysban (what, value, note, bandate, banuntil)
              VALUES (?, ?, ?, NOW(), $banuntil)",
              undef, $opts{what}, $opts{value}, $opts{note} );

    if ( $dbh->err ) {
        return bless {
            message => $dbh->errstr,
        }, 'ERROR';
    }

    my $banid = $dbh->{'mysql_insertid'};

    my $exptime = $opts{bandays} ? time() + 86400*$opts{bandays} : 0;
    # special case: creating ip/uniq/spamreport ban
    ban_do( $opts{what}, $opts{value}, $exptime );

    # log in statushistory
    my $remote = LJ::get_remote();
    $banuntil = $opts{'bandays'} ? LJ::mysql_time($exptime) : "forever";

    LJ::statushistory_add(0, $remote, 'sysban_add',
                              "banid=$banid; status=active; " .
                              "bandate=" . LJ::mysql_time() . "; banuntil=$banuntil; " .
                              "what=$opts{'what'}; value=$opts{'value'}; " .
                              "note=$opts{'note'};");

    return $banid;
}


# <LJFUNC>
# name: LJ::Sysban::validate
# des: determines whether a sysban can be added for a given value.
# args: type, value
# des-type: the sysban type we're checking
# des-value: the value we're checking
# returns: nothing on success, error message on failure
# </LJFUNC>
sub validate {
    my ($what, $value, $opts, $post) = @_;

    # bail early if the ban already exists
    return "This is already banned"
        if !$opts->{skipexisting} && sysban_check( $what, $value );

    my $validate = {
        'ip' => sub {
            my $ip = shift;

            while (my ($ip_re, $reason) = each %LJ::UNBANNABLE_IPS) {
                next unless $ip =~ $ip_re;
                return "Cannot ban IP $ip: " . LJ::ehtml($reason);
            }

            return $ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ ?
                0 : "Format: xxx.xxx.xxx.xxx (ip address)";
        },
        'uniq' => sub {
            my $uniq = shift;
            return $uniq =~ /^[a-zA-Z0-9]{15}$/ ?
                0 : "Invalid uniq: must be 15 digits/chars";
        },
        'email' => sub {
            my $email = shift;

            my @err;
            LJ::check_email($email, \@err, $post);
            return @err ? shift @err : 0;
        },
        'email_domain' => sub {
            my $email_domain = shift;

            if ($email_domain =~ /^[^@]+\.[^@]+$/) {
                return 0;
            } else {
                return "Invalid email domain: $email_domain";
            }
        },
        'user' => sub {
            my $user = shift;

            my $u = LJ::load_user($user);
            return $u ? 0 : "Invalid user: $user";
        },
        'pay_cc' => sub {
            my $cc = shift;

            return $cc =~ /^\d{4}-\d{4}$/ ?
                0 : "Format: xxxx-xxxx (first four-last four)";

        },
    };

    # aliases to handlers above
    my @map = ('pay_user' => 'user',
               'pay_email' => 'email',
               'pay_uniq' => 'uniq',
               'support_user' => 'user',
               'oauth_consumer' => 'user',
               'support_email' => 'email',
               'support_uniq' => 'uniq',
               'lostpassword' => 'user',
               'talk_ip_test' => 'ip',
               'invite_user' => 'user',
               'invite_email' => 'email',
               'noanon_ip' => 'ip',
               'spamreport' => 'user',
               oauth_consumer => 'user',
               );

    while (my ($new, $existing) = splice(@map, 0, 2)) {
        $validate->{$new} = $validate->{$existing};
    }

    my $check = $validate->{$what} or return "Invalid sysban type";
    return $check->($value);
}


# <LJFUNC>
# name: LJ::Sysban::modify
# des: modifies the expiry or note field of an entry
# args: banid, bandays, expiry, expirenow, note (passed in as hash)
# des-banid: the ban ID we're modifying
# des-bandays: the new expiry
# des-expire: the old expiry
# des-note: the new note (optional)
# des-what: the ban type
# des-value: the ban value
# returns: ERROR object on success, error message on failure
# </LJFUNC>
sub modify {
    my %opts = @_;
    unless ( $opts{'banid'} && defined $opts{'expire'} ) {
        return bless {
            message => "Arguments must be passed as a hash; ban ID and
                        old expiry are required\n",
        }, 'ERROR';
    }

    if ( $opts{note} && length( $opts{note} ) > 255 ) {
        return bless {
            message => "Note too long; must be less than 256 characters\n",
        }, 'ERROR';
    }

    my $dbh = LJ::get_db_writer();

    my $banid    = $dbh->quote($opts{'banid'});
    my $expire   = $opts{'expire'};
    my $bandays  = $opts{'bandays'};

    my $banuntil = "NULL";
    if ($bandays) {
        if ($bandays eq "E") {
            $banuntil = "FROM_UNIXTIME(" . $dbh->quote($expire) . ")"
                unless ($expire==0);
        } elsif ($bandays eq "X") {
            $banuntil = "NOW()";
        } else {
            $banuntil = "FROM_UNIXTIME(" . $dbh->quote($expire) .
                        ") + INTERVAL " . $dbh->quote($bandays) . " DAY";
        }
    }

    $dbh->do("UPDATE sysban SET banuntil=$banuntil,note=?
             WHERE banid=$banid",
             undef, $opts{note} );

    if ( $dbh->err ) {
        return bless {
            message => $dbh->errstr,
        }, 'ERROR';
    }

    # log in statushistory
    my $remote = LJ::get_remote();
    $banuntil = $opts{'bandays'} ? LJ::mysql_time($expire) : "forever";

    LJ::statushistory_add(0, $remote, 'sysban_modify',
                              "banid=$banid; status=active; " .
                              "bandate=" . LJ::mysql_time() . "; banuntil=$banuntil; " .
                              "what=$opts{'what'}; value=$opts{'value'}; " .
                              "note=$opts{'note'};");


    return $dbh->{'mysql_insertid'};

}

sub ban_do {
    my ( $what, $value, $until ) = @_;
    my %types = ( ip => 1, uniq => 1, spamreport => 1 );
    return unless $types{$what};

    my $procopts = { $what => $value, exptime => $until };

    LJ::Procnotify::add( "ban_$what", $procopts );
    LJ::MemCache::delete( "sysban:$what" );

    return 1;
}

sub ban_undo {
    my ( $what, $value ) = @_;
    my %types = ( ip => 1, uniq => 1, spamreport => 1 );
    return unless $types{$what};

    my $procopts = { $what => $value };

    LJ::Procnotify::add( "unban_$what", $procopts );
    LJ::MemCache::delete( "sysban:$what" );

    return 1;
}


1;
