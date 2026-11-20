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
use DateTime;
use Digest::SHA qw(hmac_sha256_hex);

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;
use LJ::UniqCookie;
use DW::FormErrors;

DW::Routing->register_string( '/shop/account', \&shop_account_handler, app => 1 );

sub _order_token {
    my ( $cart, $remote, $token, @fields ) = @_;
    return unless $cart;

    my ( $stime, $secret );
    if ( defined $token ) {
        ($stime) = $token =~ /\A([1-9][0-9]{0,9}):[0-9a-f]{64}\z/;
        return unless $stime;
        $secret = LJ::get_secret($stime);
    }
    else {
        ( $stime, $secret ) = LJ::get_secret();
    }
    return unless $secret;

    my $buyer = $remote ? $remote->id : ( LJ::UniqCookie->current_uniq // '' );
    my $payload = join "\0", 'shop/account', $cart->id, $remote ? 'user' : 'guest', $buyer, @fields;
    my $signed  = "$stime:" . hmac_sha256_hex( $payload, $secret );
    return defined $token ? $token eq $signed : $signed;
}

sub shop_account_handler {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = DW::Request->get;
    my $remote = $rv->{remote};
    my $cart   = $rv->{cart};
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

    my $errors           = DW::FormErrors->new;
    my $editing_delivery = $r->did_post && $post->{edit_deliverydate};
    if (
           $editing_delivery
        && $post->{prem_convert}
        && _order_token(
            $cart, $remote,
            $post->{delivery_review_token} // '', 'delivery',
            $post->{deliverydate}          // '', $post->{prem_convert}
        )
        )
    {
        $premium_convert = $post->{prem_convert};
    }

    if ( $r->did_post && !$editing_delivery ) {

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

        my $delivery_days =
            $post->{deliverydate}
            ? DW::Pay::validate_deliverydate( $post->{deliverydate}, $errors, $item_data )
            : undef;

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

                if ( $ok && $has_premium && $item->class eq 'paid' ) {

                    # check account expiration date
                    my $exptime = DateTime->from_epoch( epoch => $paid_status->{expiretime} );
                    my $newtime = DateTime->now;

                    if ( my $future_ymd = $item->deliverydate ) {
                        my ( $y, $m, $d ) = split /-/, $future_ymd;
                        $newtime = DateTime->new( year => $y + 0, month => $m + 0, day => $d + 0 );
                    }

                    my $to_day = sub { return $_[0]->truncate( to => 'day' ) };

                    if ( DateTime->compare( $to_day->($exptime), $to_day->($newtime) ) ) {
                        my @conversion = (
                            'conversion', $u->id, $post->{accttype},
                            $item->deliverydate // '',
                            $paid_status->{expiretime}
                        );

                        if (
                            _order_token(
                                $cart, $remote, $post->{prem_convert} // '', @conversion
                            )
                            )
                        {
                            $premium_convert = $post->{prem_convert};
                        }
                        else {
                            $premium_convert = _order_token( $cart, $remote, undef, @conversion );
                            my $months = $item->months;
                            my $newexp = $exptime->clone->add( months => $months );
                            my $paid_d = $exptime->delta_days($newexp)->in_units('days');

                            # FIXME: this should be DW::BusinessRules::Pay::DWS::CONVERSION_RATE
                            my $prem_d = int( $paid_d * 0.7 );

                            my $ml_args = {
                                date        => $exptime->ymd,
                                premium_num => $prem_d,
                                paid_num    => $paid_d
                            };

                            # but only include date if the logged-in user owns the account
                            delete $ml_args->{date} unless $remote && $remote->can_purchase_for($u);

                            $errors->add( undef, '/shop/account.tt.error.premiumconvert',
                                $ml_args );
                            $errors->add( undef, '/shop/account.tt.error.premiumconvert.postdate',
                                $ml_args )
                                if $ml_args->{date};
                        }
                    }
                }
            }

            unless ( $errors->exist ) {
                if ( $item && $delivery_days ) {
                    my $date   = $item->deliverydate;
                    my @review = ( 'delivery', $date, $premium_convert // '' );
                    unless (
                        ( $post->{confirm_deliverydate} // '' ) eq $date
                        && _order_token(
                            $cart, $remote, $post->{delivery_review_token} // '', @review
                        )
                        )
                    {
                        return DW::Template->render_template(
                            'shop/account-delivery-confirm.tt',
                            {
                                cart_display => $rv->{cart_display},
                                deliverydate => $date,
                                days         => $delivery_days,
                                formdata     => $post,
                                prem_convert => $premium_convert,
                                delivery_review_token =>
                                    _order_token( $cart, $remote, undef, @review ),
                            }
                        );
                    }
                }

                my ( $rv, $err ) = $cart->add_item($item);
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
    $vars->{did_post}       = $r->did_post && ( !$editing_delivery || $post->{alreadyposted} );
    $vars->{acct_reason}    = DW::Shop::Item::Account->can_have_reason;
    $vars->{prem_convert}   = $premium_convert;
    $vars->{email_checkbox} = $email_checkbox;
    $vars->{get_opts}       = $get_opts;
    $vars->{date}           = DateTime->today;
    $vars->{allow_convert}  = DW::Shop::Item::Account->allow_account_conversion( $remote, 'paid' );

    return DW::Template->render_template( 'shop/account.tt', $vars );
}

1;
