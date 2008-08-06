package DW::Worker::Payment;

use strict;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

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

    # failure closer for permanent errors
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
    return $temp_fail->( "Payment status is not 'processing' or 'paid-*'." )
        unless $pmt->{status} eq 'processing' || $pmt->{status} =~ /^paid-/;

    my $pp = DW::Pay::pp_get_order_details( $payid )
        or return $temp_fail->( "Order details not found." );
    return $temp_fail->( "Payerid not in order details." )
        unless $pp->{payerid};

    # processing logic for pulling payment
    if ( $pmt->{status} eq 'processing' ) {
        # we have a payment and it is in the state of processing, so we should now
        # contact PayPal and see how this went; we've also ensured we have the full
        # details from the payment, and the user has gone through the payment flow
        my $res = DW::Pay::pp_do_request( $payid, 'DoExpressCheckoutPayment',
                token => $pmt->{pp_token},
                paymentaction => 'Sale',
                payerid => $pp->{payerid},
                amt => sprintf( '%0.2f', $pmt->{amount} ),
                desc => "$LJ::SITENAME Account",
                currencycode => 'USD',
                notifyurl => "$LJ::SITEROOT/paidaccounts/pp_notify.bml",
            );

        # be sensitive to PayPal being down or slow or annoying
        unless ( $res ) {
            return $temp_fail->( "Temporary failure." )
                if DW::Pay::error_is_temporary();
            return $temp_fail->( "Unexpected response from PayPal." );
        }

        # but if they actually say Failure, consider it dead
        return $fail->( "PayPal error encountered." )
            if $res->{ack} eq 'Failure';

        # FIXME: if the payment is going to be pending, we might want to do
        # something more than just noting it as paid-pending ... theoretically
        # the user could do a chargeback or something and we have given away
        # free paid service?

        if ( $res->{paymentstatus} ne 'Completed' ) {
            DW::Pay::update_payment_status( $payid, 'paid-pending' );
        } else {
            DW::Pay::update_payment_status( $payid, 'paid-completed' );
        }
    }

    # okay happy days let's spawn a job to actually activate this order
    my $sh = LJ::theschwartz()
        or return $temp_fail->( "Failed getting TheSchwartz client." );
    my $new_job = TheSchwartz::Job->new( funcname => 'DW::Worker::PaidStatus',
                                         arg => {
                                             payid => $payid,
                                         } );
    my $h = $sh->insert( $new_job );
    return $temp_fail->( "Failed inserting new job." )
        unless $h;

    $job->completed;
}


sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

1;
