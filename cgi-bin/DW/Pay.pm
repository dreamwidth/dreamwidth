package DW::Pay;

use strict;

use HTTP::Request;
use LWP::UserAgent;

our $error_code = undef;
our $error_text = undef;

use constant ERR_FATAL => 1;
use constant ERR_TEMP => 2;

################################################################################
# DW::Pay::pp_get_checkout_url
#
# ARGUMENTS: target_userid, target_username, from_userid, type, duration, amount
#
#   target_user     optional    the user that we are giving this item to
#   target_username optional    if no target_userid, use this to indicate that a
#                               new account is being created
#   from_user       optional    who is giving this, may be undef if anonymous
#   type            required    the account type being given
#   duration        required    months the account type is good for (99 for permanent)
#   amount          required    how much this order costs, in dollars
#
# RETURN: URL that you should redirect the user to, or undef on error.
#
sub pp_get_checkout_url {
    my ( $tgt_uid, $tgt_uname, $frm_uid, $type, $dur, $amt ) = @_;

    DW::Pay::clear_error();

    $tgt_uid = LJ::want_userid( $tgt_uid ) if defined $tgt_uid;
    $frm_uid = LJ::want_userid( $frm_uid ) if defined $frm_uid;
    $tgt_uname = LJ::canonical_username( $tgt_uname ) if defined $tgt_uname;
    my $tgt_u = LJ::load_userid( $tgt_uname ) if defined $tgt_uname;
    $type += 0;
    $dur += 0;
    $amt += 0;

    return error( ERR_FATAL, "Invalid duration, must be > 0." )
        if $dur <= 0;
    return error( ERR_FATAL, "Invalid duration, must be <= 12 or 99." )
        if $dur > 12 && $dur != 99;
    return error( ERR_FATAL, "Invalid type, not known." )
        unless DW::Pay::type_is_valid( $type );
    return error( ERR_FATAL, "Amount cannot be negative." )
        if $amt < 0;
    return error( ERR_FATAL, "Amount cannot be zero." )
        if $amt == 0;
    return error( ERR_FATAL, "Amount seems fishy, it's too much?" )
        if $amt > 100;
    return error( ERR_FATAL, "Amount must be a whole dollar amount, no cents." )
        if $amt != int( $amt );
    return error( ERR_FATAL, "Must have either a target username or target userid." )
        unless ( defined $tgt_uid && $tgt_uid > 0 ) ||
               ( defined $tgt_uname && $tgt_uname );
    return error( ERR_FATAL, "Target username must not exist." )
        if defined $tgt_uname && $tgt_u;

    my $res = DW::Pay::pp_do_request( 'SetExpressCheckout',
            returnurl => "$LJ::SITEROOT/paidaccounts/confirm.bml",
            cancelurl => "$LJ::SITEROOT/paidaccounts/",
            paymentaction => 'Sale',
            amt => sprintf( '%0.2f', $amt ),
            desc => "$LJ::SITENAME Account",
            custom => join( '-', map { $_ ? $_ : "" } ( $tgt_uid, $tgt_uname, $frm_uid, $type, $dur, $amt ) ),
            noshipping => 1,
        );
    return error( ERR_FATAL, "Error talking to PayPal!" )
        unless defined $res && exists $res->{token};

    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Failed acquiring database writer handle." );
    $dbh->do( q{
            INSERT INTO dw_payments (paymentid, paydate, pp_token, from_userid, target_userid, target_username,
                                     typeid, duration, amount, status)
            VALUES (NULL, UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?, ?, 'pending')
        }, undef, $res->{token}, $frm_uid, $tgt_uid, $tgt_uname, $type, $dur, $amt );
    return error( ERR_FATAL, "Database error: " . $dbh->errstr )
        if $dbh->err;

    return $LJ::PAYPAL_CONFIG{url} . $res->{token};
}

################################################################################
# DW::Pay::pp_get_paymentid_from_token
#
# ARGUMENTS: token
#
#   token       required    the token, passed to us by PayPal
#
# RETURN: paymentid if found, else undef
#
# NOTE: tokens are only valid for three hours, and should be unique within that
# three hour period.  if they're not, then you will end up only getting the
# first result.
#
sub pp_get_paymentid_from_token {
    DW::Pay::clear_error();

    my $token = shift
        or return error( ERR_FATAL, "Invalid token, must be defined." );

    my $dbr = DW::Pay::get_db_reader()
        or return error( ERR_TEMP, "Failed acquiring database reader handle." );

    my $payid = $dbr->selectrow_array( q{
            SELECT paymentid FROM dw_payments
            WHERE paydate > UNIX_TIMESTAMP() - 3600 * 3
              AND pp_token = ?
        }, undef, $token );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;

    # force undef if not found
    return $payid || error( ERR_FATAL, "Token not found or has expired." );
}

################################################################################
# DW::Pay::get_payment_details
#
# ARGUMENTS: paymentid
#
#   paymentid   required    the paymentid
#
# RETURN: Hashref (one row from 'dw_payments' table):
#
#   {
#       paymentid           => id of this payment,
#       pp_token            => paypal token (may be invalid),
#       paydate             => date this payment was made,
#       target_userid       => the userid being credited (undef if none),
#       target_username     => the username being created (undef if none),
#       from_userid         => the purchaser (undef if none),
#       type                => a valid type id,
#       duration            => how long (1-12, 99),
#       amount              => cost of this order,
#       status              => enum('success','pending','failed','refunded','reversed','fraud'),
#   }
#
sub get_payment_details {
    DW::Pay::clear_error();

    my $payid = shift()+0
        or return error( ERR_FATAL, "Invalid payment ID, must be non-zero." );

    my $pmt = DW::Pay::load_payment( $payid );
    return error( ERR_FATAL, "Invalid payment ID, not found in database." )
        unless defined $pmt;

    return $pmt;
}

################################################################################
# DW::Pay::pp_get_order_details
#
# ARGUMENTS: paymentid
#
#   paymentid   required    the paymentid that this order is with
#
# RETURN: Hashref:
#
#   {
#       paymentid => ...
#       token => ...
#       email => user's PayPal email address (may be undef)
#       firstname => user's first name (may be undef)
#       lastname => user's last name (may be undef)
#       payerid => user's PayPal payerid (may be undef)
#   }
#
# NOTE: the keys noted as possibly being undef are only filled in after the
# user has gone to PayPal and completed the order process.  so if the user
# tries to get order status before they've done that, we don't know any of
# this information, they have to complete the PayPal flow first.
#
sub pp_get_order_details {
    DW::Pay::clear_error();

    my $payid = shift()+0
        or return error( ERR_FATAL, "Invalid payment ID, must be defined and non-zero." );

    my $pmt = DW::Pay::load_payment( $payid );
    return error( ERR_FATAL, "Invalid payment ID, not found in database." )
        unless defined $pmt;

    my $dbr = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to acquire database reader handle." );
    my $pp = $dbr->selectrow_hashref( q{
            SELECT email, firstname, lastname, payerid
            FROM dw_pp_details
            WHERE paymentid = ?
        }, undef, $payid );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;

    if ( $pp ) {
        $pp->{paymentid} = $payid;
        $pp->{token} = $pmt->{pp_token};
        return $pp;
    }

    # nope, not in database, so we need to get it from PayPal and insert it
    my $res = DW::Pay::pp_do_request( $payid, 'GetExpressCheckoutDetails',
            token => $pmt->{pp_token},
        );
    return error( ERR_FATAL, "Invalid PayPal response; user not done with PayPal flow?" )
        unless $res && $res->{payerid};

    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to acquire database writer handle." );
    $dbh->do( q{
            REPLACE INTO dw_pp_details (paymentid, email, firstname, lastname, payerid)
            VALUES (?, ?, ?, ?, ?)
        }, undef, $payid, $res->{email}, $res->{firstname}, $res->{lastname}, $res->{payerid} );
    return error( ERR_FATAL, "Database error: " . $dbh->errstr )
        if $dbh->err;

    return {
            paymentid => $payid,
            token => $pmt->{pp_token},

            map { $_ => $res->{$_} }
                qw/ email firstname lastname payerid /,
        };
}

################################################################################
# DW::Pay::pp_confirm_order
#
# ARGUMENTS: paymentid
#
#   paymentid   required    the id of the payment, returned in the URL from PP
#
# RETURN: 1 on success, undef on error
#
# NOTE: calling this method will schedule the order to be processed.  we will
# go and actually do the order once this has been called.  processing is all
# done by worker threads in the schwartz.
#
sub pp_confirm_order {
    DW::Pay::clear_error();

    my $payid = shift()+0
        or return error( ERR_FATAL, "Invalid payment ID, must be non-zero." );

    my $pmt = DW::Pay::load_payment( $payid );
    return error( ERR_FATAL, "Invalid payment ID, not found in database." )
        unless defined $pmt;

    # MUST be 'pending' for us to touch it, if not, then we've already touched
    # it or someone else is touching it, ow ow ow!
    return error( ERR_FATAL, "Payment status is not 'pending'!" )
        if $pmt->{status} ne 'pending';

    my $sh = LJ::theschwartz()
        or return error( ERR_FATAL, "Unable to get TheSchwartz client." );

    my $pp = DW::Pay::pp_get_order_details( $payid )
        or return error( ERR_FATAL, "Unable to get PayPal order details." );
    return error( ERR_FATAL, "User has not completed PayPal flow." )
        unless $pp->{payerid};

    DW::Pay::update_payment_status( $payid, 'processing' );

    my $job = TheSchwartz::Job->new( funcname => 'DW::Worker::Payment',
                                     arg => {
                                         payid => $payid,
                                     } );

    my $h = $sh->insert( $job );
    return error( ERR_TEMP, "Error inserting TheSchwartz job." )
        unless $h;

    return 1;
}

################################################################################
# DW::Pay::type_is_valid
#
# ARGUMENTS: type
#
#   type        required    the id of the type we're checking
#
# RETURN: 1/0 if the type is a valid type
#
sub type_is_valid {
    my $type = shift()+0;
    return 1 if $type >= 1 && $type <= 2;
    return 0;
}

################################################################################
# DW::Pay::type_name
#
# ARGUMENTS: type
#
#   type        required    the id of the type we're checking
#
# RETURN: strin name of type, else undef
#
sub type_name {
    return {
        1 => 'Basic Paid Account',
        2 => 'Premium Paid Account',
    }->{ $_[0] } || 'UNKNOWN/ERROR';
}

################################################################################
# DW::Pay::get_paid_status
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: Hashref if paid (or has ever been), undef if free:
#
#   {
#       typeid => ...
#       expiretime => db time epoch seconds they expire at
#       expiresin => seconds until they expire
#       permanent => 1/0 if they're permanent
#   }
#
sub get_paid_status {
    DW::Pay::clear_error();

    my $uuid = shift;

    my $uid = LJ::want_userid($uuid) if defined $uuid;
    return error( ERR_FATAL, "Invalid user object/userid passed in." )
        unless defined $uid && $uid > 0;

    my $dbr = DW::Pay::get_db_reader()
        or return error( ERR_TEMP, "Failed acquiring database reader handle." );
    my $row = $dbr->selectrow_hashref( q{
            SELECT IFNULL(expiretime, 0) - UNIX_TIMESTAMP() AS 'expiresin', typeid, expiretime, permanent
            FROM dw_paidstatus
            WHERE userid = ?
        }, undef, $uid );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;

    return $row;
}

################################################################################
# DW::Pay::get_current_account_status
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: undef for free, else a typeid of the account type.
#
sub get_current_account_status {
    DW::Pay::clear_error();

    my $stat = DW::Pay::get_paid_status( @_ );

    # free accounts: no row, or expired
    return undef unless defined $stat;
    return undef unless $stat->{permanent} || $stat->{expiresin} > 0;
    return $stat->{typeid};
}

################################################################################
# DW::Pay::get_current_paid_userids
#
# ARGUMENTS: limit => #rows, typeid => paid account type, permanent => 0|1
#
#   limit       optional    how many userids to return (default: no limit)
#   typeid      optional    1 to restrict to basic paid, 2 for premium paid
#                           (default: both)
#   permanent   optional    false to restrict to expiring accounts, true to
#                           permanent (default: both)
#
# RETURN: arrayref of userids for currently paid accounts matching the above
#         restrictions
#
sub get_current_paid_userids {
    DW::Pay::clear_error();

    my %opts = @_;

    my $sql = 'SELECT userid FROM dw_paidstatus WHERE ';
    my ( @where, @values );

    if ( exists $opts{permanent} ) {
        push @where, 'permanent = ?';
        push @values, ($opts{permanent} ? 1 : 0);
        push @where, 'expiretime > UNIX_TIMESTAMP(NOW())'
            unless $opts{permanent};
    } else {
        push @where, '(permanent = 1 OR expiretime > UNIX_TIMESTAMP(NOW()))';
    }

    if ( exists $opts{typeid} ) {
        push @where, 'typeid = ?';
        push @values, $opts{typeid};
    }

    $sql .= join ' AND ', @where;

    if ( exists $opts{limit} ) {
        $sql .= ' LIMIT ?';
        push @values, $opts{limit};
    }

    my $dbr = DW::Pay::get_db_reader()
        or return error( ERR_TEMP, "Unable to get db reader." );
    my $uids = $dbr->selectcol_arrayref( $sql, {}, @values );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;
    return $uids;
}

################################################################################
# DW::Pay::update_paid_status
#
# ARGUMENTS: uuserid, key => value pairs
#
#   uuserid     required    user object or userid to set paid status for
#   key         required    column being set
#   value       required    new value to set column to
#
# RETURN: undef on error, else 1 on success.
#
# NOTE: this function is a low level function intended to be use for admin
# pages and similar functionality.  don't use this willy-nilly in anything
# else as it is probably not what you want!
#
# NOTE: you can set special keys if you want to extend time by months, use
# _set_months to set expiretime to now + N months, and _add_months to append
# that many months.  This is more than likely only useful for such things as
# TODO complete that sentence.
#
sub update_paid_status {
    DW::Pay::clear_error();

    my $u = LJ::want_user( shift() )
        or return error( ERR_FATAL, "Invalid/not a user object." );
    my %cols = ( @_ )
        or return error( ERR_FATAL, "Nothing to change!" );

    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to get db writer." );

    if ( $cols{_set_months} ) {
        $cols{expiretime} = $dbh->selectrow_array( "SELECT UNIX_TIMESTAMP(DATE_ADD(NOW(), INTERVAL $cols{_set_months} MONTH))" );
        delete $cols{_set_months};
    }

    if ( $cols{_add_months} ) {
        my $row = DW::Pay::get_paid_status( $u );
        my $time = $dbh->selectrow_array( "SELECT UNIX_TIMESTAMP(DATE_ADD(FROM_UNIXTIME($row->{expiretime}), " .
                                          "INTERVAL $cols{_add_months} MONTH))" );
        $cols{expiretime} = $time;
        delete $cols{_add_months};
    }

    return error( ERR_FATAL, "Can't change the userid!" )
        if exists $cols{userid};
    return error( ERR_FATAL, "Permanent must be 0/1." )
        if exists $cols{permanent} && $cols{permanent} !~ /^(?:0|1)$/;
    return error( ERR_FATAL, "Typeid must be some number." )
        if exists $cols{typeid} && $cols{typeid} !~ /^(?:\d+)$/;
    return error( ERR_FATAL, "Expiretime must be some number." )
        if exists $cols{expiretime} && $cols{expiretime} !~ /^(?:\d+)$/;
    return error( ERR_FATAL, "Lastemail must be 0, 3, or 14." )
        if exists $cols{lastemail} && defined $cols{lastemail} && $cols{lastemail} !~ /^(?:0|3|14)$/;

    my $cols = join( ', ', map { "$_ = ?" } sort keys %cols );
    my @bind = map { $cols{$_} } sort keys %cols;

    $dbh->do( qq{
            UPDATE dw_paidstatus SET $cols WHERE userid = ?
        }, undef, @bind, $u->{userid} );
    return error( ERR_FATAL, "Database error: " . $dbh->errstr )
        if $dbh->err;

    return 1;
}


################################################################################
################################################################################
################################################################################

sub load_payment {
    my $payid = shift()+0;
    return undef unless $payid >= 0;

    my $dbr = DW::Pay::get_db_reader()
        or return error( ERR_TEMP, "Temporary failure connecting to database." );

    my $row = $dbr->selectrow_hashref( q{
            SELECT paymentid, paydate, pp_token, from_userid, target_userid, target_username,
                   typeid, duration, amount, status
            FROM dw_payments
            WHERE paymentid = ?
        }, undef, $payid );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;

    return error( ERR_FATAL, "Payment ID invalid, not found in database." )
        unless defined $row;
    return $row;
}

sub pp_log_notify {
    my $vars = shift
        or return error( ERR_FATAL, "Invalid input." );

    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to get database handle." );
    $dbh->do( q{
            INSERT INTO dw_pp_notify_log (transdate, pp_log) VALUES (UNIX_TIMESTAMP(), ?)
        }, undef, join( '&', map { uc( LJ::eurl( $_ ) ) . '=' . LJ::eurl( $vars->{$_} ) } keys %$vars ) );
    return error( ERR_FATAL, "Database error: " . $dbh->errstr )
        if $dbh->err;

    return 1;
}

sub pp_do_request {
    # optional first argument paymentid if used then this request will be logged
    # to the table ...
    my $payid;
    if ( $_[0] && $_[0] > 0 ) {
        $payid = shift()+0;
    }

    # standard arguments
    my ( $method, %args ) = @_;

    $args{method} = $method;
    $args{version} = '3.2';

    $args{user} = $LJ::PAYPAL_CONFIG{user};
    $args{pwd} = $LJ::PAYPAL_CONFIG{password};
    $args{signature} = $LJ::PAYPAL_CONFIG{signature};

    my $req = HTTP::Request->new( 'POST', $LJ::PAYPAL_CONFIG{api_url} );
    $req->content_type( 'application/x-www-form-urlencoded' );
    $req->content( join( '&', map { uc( LJ::eurl( $_ ) ) . '=' . LJ::eurl( $args{$_} ) } keys %args ) );

    my $ua = LJ::get_useragent( role => 'paypal', timeout => 10 );
    $ua->agent( 'DW-PayPal/1.0' );

    my $res = $ua->request( $req );
    if ( $res->is_success ) {
        # this funging is just to get the keys lowercase
        my $tmp = {
            map { LJ::durl( $_ ) }
                map { split( /=/, $_ ) }
                    split( /&/, $res->content )
        };
        my $resh = {};
        $resh->{lc $_} = $tmp->{$_} foreach keys %$tmp;

        # best case logging, don't fail if we had an error logging, because we've
        # already done the PayPal logic and failing on logging could lead to us
        # taking money but not crediting accounts, etc ...
        if ( $payid && $payid > 0 ) {
            my $dbh = DW::Pay::get_db_writer();
            if ( $dbh ) {
                $dbh->do( q{
                        INSERT INTO dw_pp_log (paymentid, transdate, pp_log)
                        VALUES (?, UNIX_TIMESTAMP(), ?)
                    }, undef, $payid, $res->content );
            }
        }

        return $resh;
    } else {
        return error( ERR_TEMP, "Error with PayPal connection." );
    }
}

sub sync_caps {
    my $u = LJ::want_user( shift )
        or return error( ERR_FATAL, "Must provide a user to sync caps for." );
    my $ps = DW::Pay::get_paid_status( $u );

    # either they're free, or they expired (not permanent)
    if ( ! $ps || ( ! $ps->{permanent} && $ps->{expiresin} < 0 ) ) {
        LJ::modify_caps( $u, [], [ 3, 4, 6, 7 ] );
        DW::Pay::update_paid_status( $u, lastemail => 0 );

    } else {
        return error( ERR_FATAL, "Unknown typeid." )
            unless $ps->{typeid} == 1 || $ps->{typeid} == 2;

        DW::Pay::update_paid_status( $u, lastemail => undef );

        if ( $ps->{permanent} ) {
            if ( $ps->{typeid} == 1 ) {
                LJ::modify_caps( $u, [ 6 ], [ 3, 4, 7 ] );
            } elsif ( $ps->{typeid} == 2 ) {
                LJ::modify_caps( $u, [ 7 ], [ 3, 4, 6 ] );
            }
        } else {
            if ( $ps->{typeid} == 1 ) {
                LJ::modify_caps( $u, [ 3 ], [ 4, 6, 7 ] );
            } elsif ( $ps->{typeid} == 2 ) {
                LJ::modify_caps( $u, [ 4 ], [ 3, 6, 7 ] );
            }
        }
    }

    return 1;
}

sub update_payment_status {
    my ( $pmtid, $status ) = @_;
    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to acquire database writer." );
    my $ct = $dbh->do( q{
            UPDATE dw_payments SET status = ? WHERE paymentid = ?
        }, undef, $status, $pmtid )+0;
    return error( ERR_FATAL, "Database error: " . $dbh->errstr )
        if $dbh->err;
    return $ct;
}

sub error {
    $DW::Pay::error_code = $_[0]+0;
    $DW::Pay::error_text = $_[1] || "Unknown error.";
    return undef;
}

sub error_code {
    return $DW::Pay::error_code;
}

sub error_text {
    return $DW::Pay::error_text;
}

sub was_error {
    return defined $DW::Pay::error_code;
}

sub clear_error {
    $DW::Pay::error_code = $DW::Pay::error_text = undef;
}

sub get_db_reader {
    # we always use the master, but perhaps we want to use a specific role for
    # payments later?  so we abstracted this...
    return LJ::get_db_writer();
}

sub get_db_writer {
    return LJ::get_db_writer();
}

1;
