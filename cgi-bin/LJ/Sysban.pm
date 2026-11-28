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

package LJ::Sysban;

use strict;
use v5.10;
use Log::Log4perl;
use Socket qw( AF_INET AF_INET6 inet_ntop inet_pton );
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::MemCache;
use LJ::TextUtil;

my @ip_types = qw( ip noanon_ip talk_ip_test );
my %ip_type  = map { $_ => 1 } @ip_types;

sub _canonical_ipv6 {
    my ($value) = @_;
    return unless defined $value && index( $value, ':' ) >= 0 && $value =~ /\A[0-9a-f:.]+\z/i;
    my $address = inet_pton( AF_INET6, $value ) or return;

    return inet_ntop( AF_INET, substr( $address, 12 ) )
        if substr( $address, 0, 12 ) eq ( "\0" x 10 . "\xff\xff" );

    return lc inet_ntop( AF_INET6, $address );
}

sub _canonical_ip {
    my ($value) = @_;
    return unless defined $value;
    if ( index( $value, '.' ) >= 0 ) {
        my ( $prefix, $dotted ) = $value =~ /\A(.*:)?((?:[0-9]{1,3}\.){3}[0-9]{1,3})\z/;
        return unless defined $dotted;
        my @octets = split /\./, $dotted;
        return if grep { $_ > 255 } @octets;
        $value = ( $prefix // '' ) . join '.', map { 0 + $_ } @octets;
        return $value unless defined $prefix;
    }
    return _canonical_ipv6($value);
}

sub normalize_value {
    my ( $what, $value ) = @_;
    return $value unless $what && $ip_type{$what} && defined $value;
    $value = LJ::trim($value);
    return _canonical_ip($value) // $value;
}

sub value_match_sql {
    my ($value) = @_;
    return ( 'value = ?', $value ) unless defined $value;

    my $trimmed   = LJ::trim($value);
    my $canonical = _canonical_ip($trimmed);
    return ( 'value = ?', $value ) if !defined $canonical && $trimmed eq $value;

    my $ip_match = 'value = ?';
    my @values   = ($trimmed);
    if ( defined $canonical ) {
        @values =
            index( $canonical, ':' ) >= 0 ? ($canonical) : ( $canonical, "::ffff:$canonical" );
        my $addresses = join ', ', map { 'INET6_ATON(?)' } @values;
        $ip_match = "INET6_ATON(value) IN ($addresses)";
    }
    my $ip_types = join ', ', map { "'$_'" } @ip_types;
    return ( "(value = ? OR (what IN ($ip_types) AND $ip_match))", $value, @values );
}

sub _ip_ban_active {
    my ( $bans, $value, $now ) = @_;
    return 0 unless defined $value;

    my $canonical = _canonical_ip($value);
    for my $ip ( $value, defined $canonical && $canonical ne $value ? ($canonical) : () ) {
        my $expires = $bans->{$ip};
        return 1 if defined $expires && ( !$expires || $expires > $now );
    }
    return 0;
}

=head1 Methods

=cut

# Temporary ban; just throws it in memcache as a one-off which can
# be used to more scalably determine whether or not a particular
# thing is banned.
sub tempban_create {
    my ( $what, $value, $exptime ) = @_;

    $exptime += time()
        if $exptime < 86400 * 90;

    $log->debug( 'Tempban for ', $what, ' of ', $value, ' until: ', $exptime );

    if ( $what eq 'ip' ) {
        $value = normalize_value( $what, $value );
        LJ::MemCache::set( "tempban:ip:$value", 1, $exptime );
    }
    elsif ( $what eq 'uniq' ) {
        LJ::MemCache::set( "tempban:uniq:$value", 1, $exptime );
    }
}

# Check if something is temporarily banned. Supports checking if there
# are multiple things to look for and returns 1 if any are banned.
sub tempban_check {
    my ( $what, $values ) = @_;

    die "Invalid $what in tempban" unless $what eq 'ip' || $what eq 'uniq';

    $values = [$values] unless ref $values eq 'ARRAY';

    my @keys = map { "tempban:$what:$_" } @$values;
    if ( $what eq 'ip' ) {
        for my $value (@$values) {
            my $canonical = _canonical_ip($value);
            push @keys, "tempban:ip:$canonical" if defined $canonical && $canonical ne $value;
        }
    }
    my $mem = LJ::MemCache::get_multi(@keys);

    return 1 if grep { $_ } values %$mem;
    return 0;
}

# <LJFUNC>
# name: LJ::sysban_check
# des: Given a 'what' and 'value', checks to see if a ban exists.
# args: what, value
# des-what: The ban type
# des-value: The value which triggers the ban
# returns: 1 if a ban exists, 0 otherwise
# </LJFUNC>
sub sysban_check {
    my ( $what, $value ) = @_;

    # cache if noanon_ip ban
    if ( $what eq 'noanon_ip' ) {

        my $now          = time();
        my $ip_ban_delay = $LJ::SYSBAN_IP_REFRESH || 120;

        # check memcache first if not loaded
        $LJ::NOANON_IP_BANNED_LOADED = 0 unless defined $LJ::NOANON_IP_BANNED_LOADED;
        unless ( $LJ::NOANON_IP_BANNED_LOADED + $ip_ban_delay > $now ) {
            my $memval = LJ::MemCache::get("sysban:noanon_ip");
            if ($memval) {
                *LJ::NOANON_IP_BANNED        = $memval;
                $LJ::NOANON_IP_BANNED_LOADED = $now;
            }
            else {
                $LJ::NOANON_IP_BANNED_LOADED = 0;
            }
        }

        # is it already cached in memory?
        if ($LJ::NOANON_IP_BANNED_LOADED) {
            return _ip_ban_active( \%LJ::NOANON_IP_BANNED, $value, $now );
        }

        # set this before the query
        $LJ::NOANON_IP_BANNED_LOADED = time();

        my $bans = sysban_populate( {}, 'noanon_ip' )
            or return undef $LJ::NOANON_IP_BANNED_LOADED;
        %LJ::NOANON_IP_BANNED = %$bans;

        # set in memcache
        LJ::MemCache::set( "sysban:noanon_ip", \%LJ::NOANON_IP_BANNED, $ip_ban_delay );

        # return value to user
        return _ip_ban_active( $bans, $value, $now );
    }

    # cache if ip ban
    if ( $what eq 'ip' ) {

        my $now          = time();
        my $ip_ban_delay = $LJ::SYSBAN_IP_REFRESH || 120;

        # check memcache first if not loaded
        $LJ::IP_BANNED_LOADED = 0 unless defined $LJ::IP_BANNED_LOADED;
        unless ( $LJ::IP_BANNED_LOADED + $ip_ban_delay > $now ) {
            my $memval = LJ::MemCache::get("sysban:ip");
            if ($memval) {
                *LJ::IP_BANNED        = $memval;
                $LJ::IP_BANNED_LOADED = $now;
            }
            else {
                $LJ::IP_BANNED_LOADED = 0;
            }
        }

        # is it already cached in memory?
        if ($LJ::IP_BANNED_LOADED) {
            return _ip_ban_active( \%LJ::IP_BANNED, $value, $now );
        }

        # set this before the query
        $LJ::IP_BANNED_LOADED = time();

        my $bans = sysban_populate( {}, 'ip' )
            or return undef $LJ::IP_BANNED_LOADED;
        %LJ::IP_BANNED = %$bans;

        # set in memcache
        LJ::MemCache::set( "sysban:ip", \%LJ::IP_BANNED, $ip_ban_delay );

        # return value to user
        return _ip_ban_active( $bans, $value, $now );
    }

    # cache if uniq ban
    if ( $what eq 'uniq' ) {

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
            return (
                defined $LJ::UNIQ_BANNED{$value}
                    && (
                    $LJ::UNIQ_BANNED{$value} == 0 ||    # forever
                    $LJ::UNIQ_BANNED{$value} > time()
                    )
            );                                          # not-expired
        }

        # set this now before the query
        $LJ::UNIQ_BANNED_LOADED++;

        sysban_populate( \%LJ::UNIQ_BANNED, "uniq" )
            or return undef $LJ::UNIQ_BANNED_LOADED;

        # set in memcache
        my $exp = 60 * 15;                              # 15 minutes
        LJ::MemCache::set( "sysban:uniq", \%LJ::UNIQ_BANNED, $exp );

        # return value to user
        return $LJ::UNIQ_BANNED{$value};
    }

    # cache if spamreport ban
    if ( $what eq 'spamreport' ) {

        # check memcache first if not loaded
        $LJ::SPAM_BANNED_LOADED = 0
            unless defined $LJ::SPAMREPORT_BANNED_LOADED;
        unless ($LJ::SPAMREPORT_BANNED_LOADED) {
            my $memval = LJ::MemCache::get("sysban:spamreport");
            if ($memval) {
                *LJ::SPAMREPORT_BANNED = $memval;
                $LJ::SPAMREPORT_BANNED_LOADED++;
            }
        }

        # is it already cached in memory?
        if ($LJ::SPAMREPORT_BANNED_LOADED) {
            return (
                defined $LJ::SPAMREPORT_BANNED{$value}
                    && (
                    $LJ::SPAMREPORT_BANNED{$value} == 0 ||    # forever
                    $LJ::SPAMREPORT_BANNED{$value} > time()
                    )
            );                                                # not expired
        }

        # set this now before the query
        $LJ::SPAMREPORT_BANNED_LOADED++;

        sysban_populate( \%LJ::SPAMREPORT_BANNED, "spamreport" )
            or return undef $LJ::SPAMREPORT_BANNED_LOADED;

        # set in memcache
        my $exp = 60 * 30;                                    # 30 minutes
        LJ::MemCache::set( "sysban:spamreport", \%LJ::SPAMREPORT_BANNED, $exp );

        # return value to user
        return $LJ::SPAMREPORT_BANNED{$value};
    }

    # need the db below here
    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    # standard check helper
    my $check = sub {
        my ( $wh, $vl ) = @_;
        my ( $value_match, @values ) = $ip_type{$wh} ? value_match_sql($vl) : ( 'value = ?', $vl );

        return $dbr->selectrow_array(
            qq{
                SELECT COUNT(*)
                FROM sysban
                WHERE status = 'active'
                  AND what = ?
                  AND $value_match
                  AND NOW() > bandate
                  AND (NOW() < banuntil
                       OR banuntil = 0
                       OR banuntil IS NULL)
            }, undef, $wh, @values
        );
    };

    # helper variation for wildcard match of domain bans
    my $check_subdomains = sub {
        my ($host) = @_;
        return 0 unless $host && $host =~ /\./;

        # very similar to above, except in addition to exact match
        # we also check for wildcard matches of larger banned domains
        # e.g. foo.bar.org will match ban for "%.bar.org"

        return $dbr->selectrow_array(
            qq{
                SELECT COUNT(*) FROM sysban
                WHERE status = 'active'
                  AND what = ?
                  AND (value = ? OR ? LIKE CONCAT("%.", value))
                  AND NOW() > bandate
                  AND (NOW() < banuntil
                       OR banuntil = 0
                       OR banuntil IS NULL)
            }, undef, 'email_domain', $host, $host
        );
    };

    # check both ban by email and ban by domain if we have an email address
    if ( $what eq 'email' ) {

        # short out if this email really is banned directly, or if we can't parse it
        return 1 if $check->( 'email', $value );
        return 0 unless $value =~ /@(.+)$/;

        # see if this domain is banned, either directly
        # or else as part of a larger domain ban
        return 1 if $check_subdomains->($1);

        # account for GMail troll tricks
        my @domains = split( /\./, $1 );
        return 0 unless scalar @domains >= 2;
        my $domain = "$domains[-2].$domains[-1]";

        if ( $domain eq "gmail.com" ) {
            my ($user) = ( $value =~ /^(.+)@/ );
            $user =~ s/\.//g;      # strip periods
            $user =~ s/\+.*//g;    # strip plus tags
            return 1 if $check->( 'email', "$user\@$domain" );
        }

        # must not be banned
        return 0;
    }

    # Other bans come straight from the db
    return $check->( $what, $value );
}
*LJ::sysban_check = \&sysban_check;

# takes a hashref to populate with 'value' => expiration  pairs
# takes a 'what' to populate the hashref with sysbans of that type
# returns undef on failure, hashref on success
sub sysban_populate {
    my ( $where, $what ) = @_;

    return _db_sysban_populate( $where, $what );
}

sub _db_sysban_populate {
    my ( $where, $what ) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # build cache from db
    my $sth =
        $dbh->prepare( "SELECT value, UNIX_TIMESTAMP(banuntil) "
            . "FROM sysban "
            . "WHERE status='active' AND what=? "
            . "AND NOW() > bandate "
            . "AND (NOW() < banuntil OR banuntil IS NULL)" );
    $sth->execute($what);
    return undef if $sth->err;
    while ( my ( $val, $exp ) = $sth->fetchrow_array ) {
        if ( $ip_type{$what} ) {
            $val = _canonical_ip($val) // $val;
            my $previous = $where->{$val};
            next if defined $previous && ( !$previous || ( $exp && $previous > $exp ) );
        }
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
    return _db_sysban_populate_full(@_);
}

sub _db_sysban_populate_full {
    my ( $where, $what, $limit, $skip ) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # build cache from db
    my $limitsql = $limit ? " ORDER BY banid DESC LIMIT ? OFFSET ?" : "";
    my $sth =
        $dbh->prepare( "SELECT banid, value, "
            . "UNIX_TIMESTAMP(banuntil), note "
            . "FROM sysban "
            . "WHERE status='active' AND what=? "
            . "AND NOW() > bandate "
            . "AND (NOW() < banuntil OR banuntil IS NULL)"
            . $limitsql );
    $sth->execute( $what, $limit, $skip );
    return undef if $sth->err;
    while ( my ( $banid, $val, $exp, $note ) = $sth->fetchrow_array ) {
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
    return _db_sysban_populate_full_by_value( $value, 1, @types );
}

=head2 C<< LJ::Sysban::populate_full_by_value_with_expired( $value, @types ) >>

List all sysbans for the given value, of the specified types, including expired bans.
Returns a hashref of hashes in the format:
    what => { expire => expiration, note => note, banid => banid }

=cut

sub populate_full_by_value_with_expired {
    my ( $value, @types ) = @_;
    return _db_sysban_populate_full_by_value( $value, 0, @types );
}

sub _db_sysban_populate_full_by_value {
    my ( $value, $no_expired, @types ) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $in_what = "";
    my $has_all = 0;

    $in_what = join ", ", map { $dbh->quote($_) } @types
        unless $has_all;
    $in_what = " AND what IN ( $in_what )"
        if $in_what;

    my $banuntil = $no_expired ? "AND ( NOW() < banuntil OR banuntil IS NULL )" : "";
    my ( $value_match, @values ) = value_match_sql($value);

    # build cache from db
    my $sth = $dbh->prepare(
        qq{SELECT banid, what, UNIX_TIMESTAMP(banuntil), note
           FROM sysban
           WHERE status = 'active'
                 AND $value_match
                 $in_what
                 AND NOW() > bandate
                 $banuntil
        }
    );
    $sth->execute(@values);
    return undef if $sth->err;

    my $where;
    while ( my ( $banid, $what, $exp, $note ) = $sth->fetchrow_array ) {
        my $data = {
            banid  => $banid || 0,
            expire => $exp   || 0,
            note   => $note  || 0,
        };
        $where->{$what} //= [];
        push @{ $where->{$what} }, $data;
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
sub note {
    my ( $userid, $notes, $vars ) = @_;

    $notes .= ":";
    map { $notes .= " $_=$vars->{$_};" if $vars->{$_} } sort keys %$vars;
    LJ::statushistory_add( $userid, 0, 'sysban_trig', $notes );

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
sub block {
    my ( $userid, $notes, $vars ) = @_;

    note( $userid, $notes, $vars );

    # Response construction is the caller's responsibility (see
    # DW::Controller::Community, DW::Controller::Create, which build their
    # own response after calling this).
    return;
}

# <LJFUNC>
# name: LJ::Sysban::create
# des: creates a sysban.
# args: what, value, bandays, note
# des-what: the criteria we're sysbanning on
# des-value: the value we're banning
# des-bandays: length of sysban (0 for forever)
# des-exptime: when to expire (unix epoch time)
# des-note: note to go with the ban (optional)
# des-noremote: do not attribute ban to remote
# info: Takes args as a hash.
# returns: BanID on success, error object on failure
# </LJFUNC>
sub create {

    my %opts = @_;

    unless ( $opts{what} && $opts{value} && ( defined $opts{bandays} || defined $opts{exptime} ) ) {
        return bless { message => "Wrong arguments passed; should be a hash\n", }, 'ERROR';
    }

    if ( $opts{note} && length( $opts{note} ) > 255 ) {
        return bless { message => "Note too long; must be less than 256 characters\n", }, 'ERROR';
    }

    my $dbh = LJ::get_db_writer();

    my $banuntil = "NULL";
    if ( $opts{'bandays'} ) {
        $banuntil = "NOW() + INTERVAL " . $dbh->quote( $opts{'bandays'} ) . " DAY";
    }
    elsif ( $opts{exptime} ) {
        $banuntil = "FROM_UNIXTIME(" . ( $opts{exptime} + 0 ) . ")";
    }

    # strip out leading/trailing whitespace
    $opts{'value'} = normalize_value( $opts{'what'}, LJ::trim( $opts{'value'} ) );

    # do insert
    $dbh->do(
        "INSERT INTO sysban (what, value, note, bandate, banuntil)
              VALUES (?, ?, ?, NOW(), $banuntil)",
        undef, $opts{what}, $opts{value}, $opts{note}
    );

    if ( $dbh->err ) {
        return bless { message => $dbh->errstr, }, 'ERROR';
    }

    my $banid = $dbh->{'mysql_insertid'};

    my $exptime = $opts{bandays} ? time() + 86400 * $opts{bandays} : 0;
    $exptime = $opts{exptime} if $opts{exptime};

    # Invalidate the cache for ban types that use it.
    ban_do( $opts{what}, $opts{value}, $exptime );

    # log in statushistory
    my $remote = $opts{noremote} ? undef : LJ::get_remote();
    $banuntil = $exptime ? LJ::mysql_time($exptime) : "forever";

    LJ::statushistory_add( 0, $remote, 'sysban_add',
              "banid=$banid; status=active; "
            . "bandate="
            . LJ::mysql_time()
            . "; banuntil=$banuntil; "
            . "what=$opts{'what'}; value=$opts{'value'}; "
            . "note=$opts{'note'};" );

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
    my ( $what, $value, $opts, $post ) = @_;
    $value = LJ::trim($value) if $ip_type{$what};
    my $canonical = $ip_type{$what} ? _canonical_ip($value) : undef;

    # bail early if the ban already exists
    unless ( $opts->{skipexisting} ) {
        if ( defined $canonical ) {
            my $dbh = LJ::get_db_writer();
            my ( $value_match, @values ) = value_match_sql($value);
            return "This is already banned"
                if $dbh && $dbh->selectrow_array(
                "SELECT 1 FROM sysban WHERE what = ? AND status = 'active' AND $value_match "
                    . "AND bandate <= NOW() AND (banuntil > NOW() OR banuntil = 0 OR banuntil IS NULL) LIMIT 1",
                undef, $what, @values
                );
        }
        else {
            return "This is already banned" if sysban_check( $what, $value );
        }
    }

    my $validate = {
        'ip' => sub {
            my $ip = shift;

            for my $ip_re ( keys %LJ::UNBANNABLE_IPS ) {
                next unless $ip =~ $ip_re || ( defined $canonical && $canonical =~ $ip_re );
                return "Cannot ban IP $ip: " . LJ::ehtml( $LJ::UNBANNABLE_IPS{$ip_re} );
            }

            return 0 if defined $canonical;
            return 'Invalid IPv6 address' if index( $ip, ':' ) >= 0;

            return $ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
                ? 0
                : "Format: xxx.xxx.xxx.xxx (ip address)";
        },
        'uniq' => sub {
            my $uniq = shift;
            return $uniq =~ /^[a-zA-Z0-9]{15}$/ ? 0 : "Invalid uniq: must be 15 digits/chars";
        },
        'email' => sub {
            my $email = shift;

            my @err;
            LJ::check_email( $email, \@err, $post );
            return @err ? shift @err : 0;
        },
        'email_domain' => sub {
            my $email_domain = shift;

            if ( $email_domain =~ /^[^@]+\.[^@]+$/ ) {
                return 0;
            }
            else {
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

            return $cc =~ /^\d{4}-\d{4}$/ ? 0 : "Format: xxxx-xxxx (first four-last four)";

        },
    };

    # aliases to handlers above
    my @map = (
        'pay_user'       => 'user',
        'pay_email'      => 'email',
        'pay_uniq'       => 'uniq',
        'support_user'   => 'user',
        'oauth_consumer' => 'user',
        'support_email'  => 'email',
        'support_uniq'   => 'uniq',
        'lostpassword'   => 'user',
        'invite_user'    => 'user',
        'invite_email'   => 'email',
        'spamreport'     => 'user',
        oauth_consumer   => 'user',
    );

    while ( my ( $new, $existing ) = splice( @map, 0, 2 ) ) {
        $validate->{$new} = $validate->{$existing};
    }
    $validate->{$_} = $validate->{ip} for @ip_types;

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
# returns: ERROR object on success, error message on failure
# </LJFUNC>
sub modify {
    my %opts = @_;
    unless ( $opts{'banid'} && defined $opts{'expire'} ) {
        return bless {
            message => "Arguments must be passed as a hash; ban ID and
                        old expiry are required\n",
            },
            'ERROR';
    }

    if ( $opts{note} && length( $opts{note} ) > 255 ) {
        return bless { message => "Note too long; must be less than 256 characters\n", }, 'ERROR';
    }

    my $dbh = LJ::get_db_writer();

    my $banid   = $opts{'banid'};
    my $expire  = $opts{'expire'};
    my $bandays = $opts{'bandays'};
    my $ban =
        $dbh->selectrow_hashref( 'SELECT what, value FROM sysban WHERE banid = ?', undef, $banid );
    return bless { message => $dbh->errstr // "No sysban with ID $banid", }, 'ERROR' unless $ban;

    my $banuntil = "NULL";
    if ($bandays) {
        if ( $bandays eq "E" ) {
            $banuntil = "FROM_UNIXTIME(" . $dbh->quote($expire) . ")"
                unless ( $expire == 0 );
        }
        elsif ( $bandays eq "X" ) {
            $banuntil = "NOW()";
        }
        else {
            $banuntil =
                  "FROM_UNIXTIME("
                . $dbh->quote($expire)
                . ") + INTERVAL "
                . $dbh->quote($bandays) . " DAY";
        }
    }

    my $updated = $dbh->do(
        "UPDATE sysban SET banuntil=$banuntil,note=?
             WHERE banid=?",
        undef, $opts{note}, $banid
    );

    return bless { message => $dbh->errstr, }, 'ERROR' unless defined $updated;

    ban_do( $ban->{what} );

    # log in statushistory
    my $remote = LJ::get_remote();
    $banuntil = $opts{'bandays'} ? LJ::mysql_time($expire) : "forever";

    LJ::statushistory_add( 0, $remote, 'sysban_modify',
              "banid=$banid; status=active; "
            . "bandate="
            . LJ::mysql_time()
            . "; banuntil=$banuntil; "
            . "what=$ban->{what}; value=$ban->{value}; "
            . "note=$opts{'note'};" );

    return $dbh->{'mysql_insertid'};

}

sub ban_do {
    my ( $what, $value, $until ) = @_;
    my %types = ( ip => 1, noanon_ip => 1, uniq => 1, spamreport => 1 );
    return unless $types{$what};

    $LJ::IP_BANNED_LOADED        = 0 if $what eq 'ip';
    $LJ::NOANON_IP_BANNED_LOADED = 0 if $what eq 'noanon_ip';
    LJ::MemCache::delete("sysban:$what");

    return 1;
}

sub ban_undo {
    return ban_do(@_);
}

1;
