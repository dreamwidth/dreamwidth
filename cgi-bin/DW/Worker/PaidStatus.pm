package DW::Worker::PaidStatus;

use strict;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';

use base 'TheSchwartz::Worker';

sub work {
    my ( $class, $job ) = @_;

    # failure closer for permanent errors
    my $fail = sub {
        my $msg = sprintf( shift(), @_ );

        $msg .= sprintf( ' (Internal: %s)', DW::Pay::error_text() )
            if DW::Pay::was_error();

        $job->permanent_failure( $msg );
        return;
    };

    # failure closer for temporary errors
    my $temp_fail = sub {
        my $msg = sprintf( shift(), @_ );

        $msg .= sprintf( ' (Internal: %s)', DW::Pay::error_text() )
            if DW::Pay::was_error();

        $job->failed( $msg );
        return;
    };

    my $a = $job->arg;
    my $payid = $a->{payid}+0
        or return $fail->( "Payid not among arguments?" );

    my $pmt = DW::Pay::load_payment( $payid )
        or return $temp_fail->( "Failed loading payment from database." );
    return $temp_fail->( "Payment status is not 'paid-*'." )
        unless $pmt->{status} =~ /^paid-/;

    my $pp = DW::Pay::pp_get_order_details( $payid )
        or return $temp_fail->( "Failed loading order details." );

    # calculate target we're applying this payment to
    my $tgt_u;
    if ( $pmt->{target_userid} && $pmt->{target_userid} > 0 ) {
        $tgt_u = LJ::load_userid( $pmt->{target_userid} )
            or return $temp_fail->( "Unable to load target userid $pmt->{target_userid}." );
    } elsif ( $pmt->{target_username} ) {
        my $test_u = LJ::load_user( $pmt->{target_username} );
        if ( $test_u ) {
            LJ::send_mail( {
                    to => $LJ::PAYPAL_CONFIG{email},
                    from => $LJ::BOGUS_EMAIL,
                    subject => "$LJ::SITENAME Account Creation Error",
                    body => <<EOF,
A collision has occurred during account creation.  Someone has chosen to pay
for a new account, and that new account was created before they could finish
the payment process.

We have already taken the user's money, however, and so this situation needs
to be corrected manually.  Here are the payment details:

    Customer email: $pp->{email}

    Amount paid:    $pmt->{amount}
    Failed to make: $pmt->{target_username}

Please contact this customer and either refund their money or create a new
account for them.  You will manually need to upgrade the account when it is
created, if you take that option.

We're very sorry for the inconvenience.


Regards,
The $LJ::SITENAME Team
EOF
                } );
            return $fail->( "Account $pmt->{target_username} already exists." );
        }

        # create a blank user
        my $pw = LJ::make_auth_code(8);
        $tgt_u = LJ::User->create_personal(
                user => $pmt->{target_username},
                email => $pp->{email},
                password => $pw,
                get_ljnews => 1,
                inviter => $pmt->{from_userid} ? LJ::load_userid( $pmt->{from_userid} ) : undef,
                underage => 0,
                ofage => 1,
            );

        LJ::send_mail( {
                to => $pp->{email},
                from => $LJ::BOGUS_EMAIL,
                subject => "Your New $LJ::SITENAME Account",
                body => <<EOF,
Dear $pp->{firstname},

Your payment for a new $LJ::SITENAME account has been processed.  The account
has been created.  Here is your username and password:

    Username: $pmt->{target_username}
    Password: $pw

You should receive another email shortly confirming that this account has been
credited with the appropriate amount of paid time.


Regards,
The $LJ::SITENAME Team
EOF
            } );
    }

    # must have a target user by now
    return $fail->( "No target user found!" )
        unless $tgt_u;

    my $ps = DW::Pay::get_paid_status( $tgt_u );

    # don't allow downgrading from permanent
    if ( $ps->{permanent} && $pmt->{duration} < 99 ) {
        LJ::send_mail( {
                to => $LJ::PAYPAL_CONFIG{email},
                from => $LJ::BOGUS_EMAIL,
                subject => "$LJ::SITENAME Payment Error",
                body => <<EOF,
A user has managed to give us money for an account that is already in a
permanent state.  This really should never happen.

    Customer email: $pp->{email}

    Amount paid:    $pmt->{amount}
    Failed account: $tgt_u->{user}

Please contact this customer and work something out.  Again, this really
should never happen, so you may want to take a look at the code or try
to figure out how this happened.

We're very sorry for the inconvenience.


Regards,
The $LJ::SITENAME Team
EOF
            } );
        return $fail->( "Account already permanent!" );
    }

    my $dbh = DW::Pay::get_db_writer()
        or return $temp_fail->( "Unable to get database handle." );

    # FIXME: identify the proper error handling here, what if we fail to update
    # the paidstatus row?   or sync caps?  we should probably do something
    # intelligent about that...

    # note payment application
    my $note = sub {
        LJ::statushistory_add( $tgt_u, undef, 'paidstatus', sprintf('Updated paidstatus: ' . shift, @_) );
    };

    # insert dummy row so we can do updates later, it makes the logic easier
    $dbh->do( q{
            INSERT IGNORE INTO dw_paidstatus (userid, typeid, expiretime, permanent)
            VALUES (?, ?, 0, 0)
        }, undef, $tgt_u->{userid}, $pmt->{typeid} ); 

    if ( $pmt->{duration} == 99 ) {
        $dbh->do( q{
                UPDATE dw_paidstatus
                SET typeid = ?, expiretime = 0, permanent = 1
                WHERE userid = ?
            }, undef, $pmt->{typeid}, $tgt_u->{userid} );
        $note->( 'added permanent %s', DW::Pay::type_name( $pmt->{typeid} ) );
    } else {
        # if expired or not this type, set it absolute from now
        if ( $ps->{expiresin} < 0 || $ps->{typeid} != $pmt->{typeid} ) {
            $dbh->do( q{
                    UPDATE dw_paidstatus
                    SET typeid = ?, expiretime = UNIX_TIMESTAMP(DATE_ADD(NOW(), INTERVAL ? MONTH)), permanent = 0
                    WHERE userid = ?
                }, undef, $pmt->{typeid}, $pmt->{duration}, $tgt_u->{userid} );
            $note->( 'set to %d months of %s', $pmt->{duration}, DW::Pay::type_name( $pmt->{typeid} ) );
        } else {
            $dbh->do( q{
                    UPDATE dw_paidstatus
                    SET typeid = ?, expiretime = UNIX_TIMESTAMP(DATE_ADD(FROM_UNIXTIME(expiretime), INTERVAL ? MONTH)), permanent = 0
                    WHERE userid = ?
                }, undef, $pmt->{typeid}, $pmt->{duration}, $tgt_u->{userid} );
            $note->( 'extended by %d months of %s', $pmt->{duration}, DW::Pay::type_name( $pmt->{typeid} ) );
        }
    }

    DW::Pay::sync_caps( $tgt_u );

    my $type = DW::Pay::type_name( $pmt->{typeid} );
    my $duration = $pmt->{duration} == 99 ? "Permanent" : "$pmt->{duration} months";

    if ( $pp->{email} ne $tgt_u->email_raw ) {
        LJ::send_mail( {
                to => $pp->{email},
                from => $LJ::BOGUS_EMAIL,
                subject => "Paid Time Credited to $LJ::SITENAME Account",
                body => <<EOF,
Dear $pp->{firstname},

This email is to confirm that we have successfully credited the following
paid time.  A separate email will be sent to the account owner advising
them that this time has been credited.

    Account: $tgt_u->{user}

    Type:    $type
    Period:  $duration

We appreciate your business!


Regards,
The $LJ::SITENAME Team
EOF
            } );
    }

    LJ::send_mail( {
            to => $tgt_u->email_raw,
            from => $LJ::BOGUS_EMAIL,
            subject => "Update to Your $LJ::SITENAME Account",
            body => <<EOF,
Dear $tgt_u->{user},

Your account on $LJ::SITENAME has been credited with some paid time.
The details of this transaction are:

    Type:   $type
    Period: $duration

We appreciate your patronage!


Regards,
The $LJ::SITENAME Team
EOF
        } );

    $job->completed;
}


sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ( $class, $fails ) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

1;
