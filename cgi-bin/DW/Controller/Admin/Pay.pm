#!/usr/bin/perl
#
# DW::Controller::Admin::Pay
#
# Manage payment history and status. Requires 'payments' privs.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::Pay;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use DW::Pay;
use DW::Shop;
use DW::Shop::Cart;
use DW::Shop::Engine;
use DW::InviteCodes;

use DateTime;
use Storable qw/ thaw /;

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'pay',
    ml_scope => '/admin/pay/index.tt',
    privs    => ['payments']
);

DW::Routing->register_string( "/admin/pay/index", \&main_controller, app => 1 );
DW::Routing->register_string( "/admin/pay/view",  \&view_controller, app => 1 );

DW::Routing->register_string( "/admin/pay/striptime", \&striptime_controller, app => 1 );

sub main_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['payments'] );
    return $rv unless $ok;

    my $r     = DW::Request->get;
    my $scope = '/admin/pay/viewuser.tt';
    my $vars  = {};

    return DW::Template->render_template( 'admin/pay/index.tt', $vars )
        unless $r->did_post
        or $r->get_args->{view};

    if ( $r->did_post ) {
        my $remote = $rv->{remote};
        my $post   = $r->post_args;

        return error_ml("$scope.error.formcheck") unless $post->{givetime};

        my $who = $post->{user};
        my $u   = LJ::load_user($who);
        return error_ml( "$scope.error.invalidaccount", { user => LJ::ehtml($who) } )
            unless $u;

        if ( $post->{submit} eq 'Edit' ) {
            my $datetime = $post->{datetime};
            return error_ml("$scope.error.invalidtime")
                unless $datetime =~ /^\d{4}\-\d\d\-\d\d *( \d\d(:\d\d){1,2})?$/;

            my $done = DW::Pay::edit_expiration_datetime( $u, $datetime );
            return error_ml( "$scope.error.sys", { err => DW::Pay::error_text() } )
                unless $done;

            LJ::statushistory_add( $u, $remote, 'paidstatus',
                "Admin override: edit expiration date/time: $datetime" );

            return $r->redirect("$LJ::SITEROOT/admin/pay/index?view=$u->{user}");
        }

        my $type = $post->{type};
        return error_ml("$scope.error.invalidstatus")
            unless $type =~ /^(?:seed|premium|paid|expire)$/;

        my $months = $post->{months} || 0;
        my $days   = $post->{days}   || 0;

        $months = 99 if $type eq 'seed';

        if ( $type eq 'expire' ) {
            my $done = DW::Pay::expire_user( $u, force => 1 );
            return error_ml( "$scope.error.sys", { err => DW::Pay::error_text() } )
                unless $done;

            LJ::statushistory_add( $u, $remote, 'paidstatus', "Admin override: expired account." );
        }
        else {
            my $done = DW::Pay::add_paid_time( $u, $type, $months, $days );
            return error_ml( "$scope.error.sys", { err => DW::Pay::error_text() } )
                unless $done;

            LJ::statushistory_add( $u, $remote, 'paidstatus',
                "Admin override: gave paid time to user: months=$months days=$days type=$type" );

            if ( $post->{sendemail} ) {
                LJ::send_mail(
                    {
                        to       => $u->email_raw,
                        from     => $LJ::ACCOUNTS_EMAIL,
                        fromname => $LJ::SITENAME,
                        subject  => LJ::Lang::ml(
                            'shop.email.admin.subject',
                            {
                                sitename => $LJ::SITENAME
                            }
                        ),
                        body => LJ::Lang::ml(
                            'shop.email.admin.body',
                            {
                                touser    => $u->display_name,
                                type      => $type,
                                nummonths => $months,
                                numdays   => $days,
                                sitename  => $LJ::SITENAME,
                            }
                        ),
                    }
                );
            }
        }

        return $r->redirect("$LJ::SITEROOT/admin/pay/index?view=$u->{user}");

    }    # end if did_post

    my $username = $r->get_args->{view};
    return error_ml( "$scope.error.invalidaccount", { user => LJ::ehtml($username) } )
        unless $vars->{u} = LJ::load_user($username);

    $vars->{ps}    = DW::Pay::get_paid_status( $vars->{u} );
    $vars->{carts} = [ DW::Shop::Cart->get_all( $vars->{u} ) ];

    $vars->{type_name}  = sub { DW::Pay::type_name( $_[0]->{typeid} ) };
    $vars->{from_epoch} = sub { DateTime->from_epoch( epoch => $_[0] ) };
    $vars->{mysql_time} = sub { $_[0] ? LJ::mysql_time( $_[0] ) : "" };
    $vars->{ago_text}   = sub {
        my $exp = LJ::ago_text( $_[0] );
        $exp =~ s/ ago//;
        return $exp;
    };

    $vars->{is_pending} = sub { $_[0] == $DW::Shop::STATE_PEND_PAID ? 1 : 0 };

    return DW::Template->render_template( 'admin/pay/viewuser.tt', $vars );
}

sub striptime_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['payments'] );
    return $rv unless $ok;

    my $r     = DW::Request->get;
    my $scope = '/admin/pay/striptime.tt';
    my $vars  = {};

    return $r->redirect("$LJ::SITEROOT/admin/pay/")
        unless my $acid = $r->get_args->{from};

    if ( $r->did_post ) {
        my $dbh = LJ::get_db_writer();
        my $ct  = $dbh->do( 'DELETE FROM shop_codes WHERE acid = ?', undef, $acid );

        return error_ml( "$scope.error.db", { err => $dbh->errstr } )
            if $dbh->err;

        return error_ml("$scope.error.stripfail") unless $ct > 0;
        return success_ml("$scope.success");
    }

    $vars->{acid} = $acid;

    return DW::Template->render_template( 'admin/pay/striptime.tt', $vars );
}

# very sad generic table dumper (generates HTML)
my $dump = sub {
    my ( $sql, @bind ) = @_;
    my $body = '';

    # make an educated guess at durl-ing something
    my $durl = sub {
        my $val = $_[0];

        my $hr;
        my $out = sub {
            foreach (qw/ SIGNATURE USER PWD ccnumber password username /) {
                $hr->{$_} = '<em>redacted</em>'
                    if exists $hr->{$_};
            }
            return join( '<br />', map { "<strong>$_:</strong> $hr->{$_}" } sort keys %$hr );
        };

        # first see if it's Storable encoded ...
        eval {
            my $x = thaw($val);
            $hr = $x if $x && ref $x eq 'HASH';
        };
        return $out->() if $hr;

        # but see if it seems to be a unix time we can convert to a readable one
        return LJ::mysql_time( $val, 1 ) if $val =~ /^1\d{9}$/;

        # and now fall back to urlencoded ...
        return $val unless $val =~ /&/ && $val =~ /=/;
        LJ::decode_url_string( $val, $hr = {} );
        return $out->();
    };

    my $dbh = LJ::get_db_writer();
    my $sth = $dbh->prepare($sql) or return "<p>Unable to prepare SQL.</p>";
    $sth->execute(@bind);
    return "<p>Error executing SQL.</p>" if $sth->err;

    my $rows = [];
    push @$rows, $_ while $_ = $sth->fetchrow_hashref;
    return "<p>No records found.</p>" unless $rows && @$rows;

    my @cols = sort { $a cmp $b } keys %{ $rows->[0] };

    $body .= q{<table border=1 cellpadding=5><tr><th>};
    $body .= join( '</th><th>', @cols );
    $body .= q{</th></tr>};

    foreach my $row (@$rows) {
        $body .= q{<tr><td>};
        $body .= join( '</td><td>', map { $durl->( $row->{$_} ) } @cols );
        $body .= q{</td></tr>};
    }

    $body .= q{</table>};

    return $body;
};

sub view_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['payments'] );
    return $rv unless $ok;

    my $r     = DW::Request->get;
    my $scope = '/admin/pay/vieworder.tt';
    my $vars  = {};

    my $dbh = LJ::get_db_writer();

    # see if we need to look up the cart associated with a paid invite code

    if ( my $code = $r->get_args->{code} ) {

        my ($acid) = DW::InviteCodes->decode($code);
        return error_ml("$scope.error.invalidcode") unless $acid;

        my $cartid =
            $dbh->selectrow_array( 'SELECT cartid FROM shop_codes WHERE acid = ?', undef, $acid );

        return error_ml( "$scope.error.db", { err => $dbh->errstr } )
            if $dbh->err;

        return error_ml("$scope.error.unpaidcode") unless $cartid;

        return $r->redirect("$LJ::SITEROOT/admin/pay/view?cartid=$cartid");
    }

    my $cartid = $r->get_args->{cartid};
    return error_ml("$scope.error.nocartid") unless $cartid;

    if ( $cartid !~ /^\d+$/ ) {

        # see if we were given a PayPal transaction id instead
        $cartid = $dbh->selectrow_array( 'SELECT cartid FROM pp_trans WHERE transactionid = ?',
            undef, $cartid );
        return error_ml("$scope.error.notfound") unless $cartid && $cartid > 0;
    }

    my $cart = DW::Shop::Cart->get_from_cartid($cartid);
    return error_ml("$scope.error.notfound") unless $cart;
    $cartid = $cart->id;

    # see if we are being asked to process a check/money order

    if ( $r->did_post && $r->post_args->{record_cmo} ) {

        my $received_method = $r->post_args->{paymentmethod};
        my $received_notes  = LJ::ehtml( $r->post_args->{notes} );

        my %valid_method = map { $_ => 1 } qw( cash check moneyorder other );
        return error_ml("$scope.error.invalidpay")
            unless $valid_method{$received_method};

        my %notes_method = map { $_ => 1 } qw( check other );
        return error_ml("$scope.error.nonotes")
            if $notes_method{$received_method} && !$received_notes;

        # record the payment

        $dbh->do( "INSERT INTO shop_cmo (cartid, paymentmethod, notes) VALUES (?, ?, ?)",
            undef, $cartid, $received_method, $received_notes );

        return error_ml( "$scope.error.db", { err => $dbh->errstr } )
            if $dbh->err;

        $cart->state($DW::Shop::STATE_PAID);    # mark cart as paid

        return $r->redirect("$LJ::SITEROOT/admin/pay/view?cartid=$cartid");
    }

    $vars->{cart} = $cart;
    $vars->{u}    = LJ::load_userid( $cart->userid );

    my $classname = $DW::Shop::PAYMENTMETHODS{ $cart->paymentmethod }->{class};
    $vars->{classname} = $classname;

    # attempt to create an engine so we can get more info about the cart
    if ( defined $classname ) {
        $vars->{engine} = eval "DW::Shop::Engine::${classname}->new_from_cart( \$cart )";
    }

    $vars->{dump}   = sub { $dump->(@_) };
    $vars->{widget} = sub { LJ::Widget::ShopCart->render( admin => 1, cart => $_[0] ) };

    $vars->{from_epoch} = sub { DateTime->from_epoch( epoch => $_[0] ) };
    $vars->{is_pending} = sub { $_[0] == $DW::Shop::STATE_PEND_PAID ? 1 : 0 };

    $vars->{cmo_info} =
        $dbh->selectrow_hashref( "SELECT paymentmethod, notes FROM shop_cmo WHERE cartid = ?",
        undef, $cartid );

    return DW::Template->render_template( 'admin/pay/vieworder.tt', $vars );
}

1;
