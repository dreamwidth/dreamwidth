#!/usr/bin/perl
#
# DW::Controller::Shop::Account
#
# This is the page where a person can choose to buy a paid account for
# themself, another user, or a new user.
#
# Authors:
#      Cocoa <cocoa@tokyo-tower.org>
#
# Copyright (c) 2010-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop::Account;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;
use DW::FormErrors;

DW::Routing->register_string( '/shop/account', \&shop_account_handler, app => 1 );

sub shop_account_handler {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = DW::Request->get;
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $post   = $r->post_args;
    my $vars;

    my $scope = "/shop/account.tt";

    # let's see what they're trying to do
    my $for = $GET->{for};
    return $r->redirect("$LJ::SHOPROOT")
        unless $for && $for =~ /^(?:self|gift|new|random)$/;

    return error_ml("$scope.error.invalidself")
        if $for eq 'self' && ( !$remote || !$remote->is_personal );

    my $account_type = DW::Pay::get_account_type($remote);
    return error_ml("$scope.error.invalidself.perm")
        if $for eq 'self' && $account_type eq 'seed';

    my $post_fields = {};
    my $email_checkbox;
    my $premium_convert;

    if ( $for eq 'random' ) {
        if ( my $username = LJ::ehtml( $GET->{user} ) ) {
            my $randomu = LJ::load_user($username);
            if ( LJ::isu($randomu) ) {
                $vars->{randomu} = $randomu;
            }
            else {
                return $r->redirect("$LJ::SHOPROOT");
            }
        }
    }

    if ( $for eq 'gift' ) {
        if ( my $username = LJ::ehtml( $GET->{user} ) ) {
            my $randomu = LJ::load_user($username);
            if ( LJ::isu($randomu) ) {
                $vars->{randomu} = $randomu;
            }
            else {
                return $r->redirect("$LJ::SHOPROOT");
            }
        }
    }

    if ( $for eq 'self' ) {
        $vars->{paid_status} = DW::Widget::PaidAccountStatus->render;
    }

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {

        my $item_data = {};

        $item_data->{from_userid} = $remote ? $remote->id : 0;

        if ( $post->{for} eq 'self' ) {
            DW::Pay::for_self( $remote, $item_data );
        }
        elsif ( $post->{for} eq 'gift' ) {
            DW::Pay::for_gift( $remote, $post->{username}, $errors, $item_data );
        }
        elsif ( $post->{for} eq 'random' ) {
            my $target_u;
            if ( $post->{username} eq '(random)' ) {
                $target_u = DW::Pay::get_random_active_free_user();
                return error_ml('widget.shopitemoptions.error.nousers')
                    unless LJ::isu($target_u);
                $item_data->{anonymous_target} = 1;
            }
            else {
                $target_u = LJ::load_user( $post->{username} );
            }

            my $user_check = DW::Pay::validate_target_user( $target_u, $remote );

            if ( defined $user_check->{error} ) {
                $errors->add( 'username', $user_check->{error} );
            }
            else {
                $item_data->{target_userid} = $target_u->id;
                $item_data->{random}        = 1;
            }
        }
        elsif ( $post->{for} eq 'new' ) {
            my @email_errors;
            LJ::check_email( $post->{email}, \@email_errors, $post, $post->{email_checkbox} );
            if (@email_errors) {
                $errors->add_string( 'email', join( ', ', @email_errors ) );
            }
            else {
                $item_data->{target_email} = $post->{email};
            }
        }

        if ( $post->{deliverydate} ) {
            DW::Pay::validate_deliverydate( $post->{deliverydate}, $errors, $item_data );
        }

        unless ( $post->{accttype} ) {
            $errors->add( 'accttype', 'widget.shopitemoptions.error.notype' );
        }

        unless ( $errors->exist ) {
            $item_data->{anonymous} = 1
                if $post->{anonymous} || !$remote;

            $item_data->{reason} = LJ::strip_html( $post->{reason} );    # plain text

            # build a new item and try to toss it in the cart.  this fails if there's a
            # conflict or something

            my $item = DW::Shop::Item::Account->new(
                type           => $post->{accttype},
                user_confirmed => $post->{alreadyposted},
                force_spelling => $post->{force_spelling},
                %$item_data
            );

            # check for renewing premium as paid
            my $u           = LJ::load_userid( $item ? $item->t_userid : undef );
            my $paid_status = $u ? DW::Pay::get_paid_status($u) : undef;

            if ($paid_status) {
                my $paid_curtype = DW::Pay::type_shortname( $paid_status->{typeid} );
                my $has_premium  = $paid_curtype eq 'premium' ? 1 : 0;

                my $ok = DW::Shop::Item::Account->allow_account_conversion( $u, $item->class );

                if ( $ok && $has_premium && $item->class eq 'paid' && !$post->{prem_convert} ) {

                    # check account expiration date
                    my $exptime = DateTime->from_epoch( epoch => $paid_status->{expiretime} );
                    my $newtime = DateTime->now;

                    if ( my $future_ymd = $item->deliverydate ) {
                        my ( $y, $m, $d ) = split /-/, $future_ymd;
                        $newtime = DateTime->new( year => $y + 0, month => $m + 0, day => $d + 0 );
                    }

                    my $to_day = sub { return $_[0]->truncate( to => 'day' ) };

                    if ( DateTime->compare( $to_day->($exptime), $to_day->($newtime) ) ) {
                        my $months = $item->months;
                        my $newexp = $exptime->clone->add( months => $months );
                        my $paid_d = $exptime->delta_days($newexp)->in_units('days');

                        # FIXME: this should be DW::BusinessRules::Pay::DWS::CONVERSION_RATE
                        my $prem_d = int( $paid_d * 0.7 );

                        my $ml_args =
                            { date => $exptime->ymd, premium_num => $prem_d, paid_num => $paid_d };

                        # but only include date if the logged-in user owns the account
                        delete $ml_args->{date} unless $remote && $remote->can_purchase_for($u);

                        $errors->add( undef, '/shop/account.tt.error.premiumconvert', $ml_args );
                        $errors->add( undef, '/shop/account.tt.error.premiumconvert.postdate',
                            $ml_args )
                            if $ml_args->{date};
                        $premium_convert = 1;

                    }
                }
            }

            unless ( $errors->exist ) {

                my ( $rv, $err ) = $rv->{cart}->add_item($item);
                $errors->add_string( '', $err ) unless $rv;

                unless ( $errors->exist ) {
                    return $r->redirect($LJ::SHOPROOT);
                }
            }
        }

    }

    $vars->{errors} = $errors;

    my $get_opts = sub {
        my $given_item = shift;
        my %month_values;
        foreach my $item ( keys %LJ::SHOP ) {
            if ( $item =~ /^$given_item(\d*)$/ ) {
                my $i = $1 || 1;
                $month_values{$i} = {
                    name   => $item,
                    points => $LJ::SHOP{$item}->[3],
                    price  => "\$" . sprintf( "%.2f", $LJ::SHOP{$item}->[0] ) . " USD"
                };
            }
        }
        return \%month_values;
    };

    $vars->{for}            = $for;
    $vars->{remote}         = $remote;
    $vars->{user}           = $GET->{user};
    $vars->{cart_display}   = $rv->{cart_display};
    $vars->{seed_avail}     = DW::Pay::num_permanent_accounts_available() > 0;
    $vars->{num_perms}      = DW::Pay::num_permanent_accounts_available_estimated();
    $vars->{formdata}       = $post || { username => ( $GET->{user} ), anonymous => !$remote };
    $vars->{did_post}       = $r->did_post;
    $vars->{acct_reason}    = DW::Shop::Item::Account->can_have_reason;
    $vars->{prem_convert}   = $premium_convert;
    $vars->{email_checkbox} = $email_checkbox;
    $vars->{get_opts}       = $get_opts;
    $vars->{date}           = DateTime->today;
    $vars->{allow_convert}  = DW::Shop::Item::Account->allow_account_conversion( $remote, 'paid' );

    return DW::Template->render_template( 'shop/account.tt', $vars );
}

1;
