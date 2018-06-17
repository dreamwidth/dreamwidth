#!/usr/bin/perl
#
# LJ::Widget::ShopItemOptions
#
# Returns the options for purchasing a particular shop item.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::ShopItemOptions;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

sub need_res { qw( stc/shop.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote();
    my $ret;

    my $option_name = $opts{option_name};
    my $given_item = $opts{item};

    return "" unless $option_name && $given_item;

    # get all of the possible month values for the item
    # note that it's okay if there's no month values for an item;
    # we'll just print the item itself in that case
    my @month_values;
    foreach my $item ( keys %LJ::SHOP ) {
        if ( $item =~ /^$given_item(\d*)$/ ) {
            push @month_values, $1;
        }
    }

    $ret .= "<strong>" . $class->ml( "widget.shopitemoptions.header.$given_item" ) . "</strong>";

    my $num_perms = DW::Pay::num_permanent_accounts_available_estimated();
    if ( $num_perms > 0 ) {
        my $highlight_string = $class->ml( "widget.shopitemoptions.highlight.$given_item", { num => $num_perms } );
        $ret .= " <span class='shop-item-highlight'>$highlight_string</span>"
            unless $highlight_string eq 'ShopItemOptions';
    }

    $ret .= "<br />";

    $ret .= $class->ml( "widget.shopitemoptions.error.notforsale" )
        unless @month_values;  # no matching keys in SHOP hash

    foreach my $month_value ( sort { $b <=> $a } @month_values ) {
        my $full_item = $given_item . $month_value;
        if ( ref $LJ::SHOP{$full_item} eq 'ARRAY' ) {
            my $price_string = $class->ml( "widget.shopitemoptions.price.$full_item", { price => "\$".sprintf( "%.2f" , $LJ::SHOP{$full_item}->[0] )." USD", points => $LJ::SHOP{$full_item}->[3] } );
            $price_string = $class->ml( 'widget.shopitemoptions.price', { num => $month_value, price => "\$".sprintf( "%.2f" , $LJ::SHOP{$full_item}->[0] )." USD", points => $LJ::SHOP{$full_item}->[3] } )
                if $price_string eq 'ShopItemOptions';

            $ret .= $class->html_check(
                type => 'radio',
                name => $option_name,
                id => $full_item,
                value => $full_item,
                selected => ($opts{post}->{$option_name} || "") eq $full_item,
            ) . " <label for='$full_item'>$price_string</label><br />";
        }
    }

    return $ret;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    # now try to add this item to their list
    my $cart = DW::Shop->get->cart
        or return ( error => $class->ml( 'widget.shopitemoptions.error.nocart' ) );

    my %item_data;

    my $remote = LJ::get_remote();
    $item_data{from_userid} = $remote ? $remote->id : 0;

    if ( $post->{for} eq 'self' ) {
        if ( $remote && $remote->is_personal ) {
            $item_data{target_userid} = $remote->id;
        } else {
            return ( error => $class->ml( 'widget.shopitemoptions.error.notloggedin' ) );
        }
    } elsif ( $post->{for} eq 'gift' ) {
        my $target_u = LJ::load_user( $post->{username} );

        return ( error => $class->ml( 'widget.shopitemoptions.error.invalidusername' ) )
            unless LJ::isu( $target_u );

        return ( error => $class->ml( 'widget.shopitemoptions.error.expungedusername' ) )
            if $target_u->is_expunged;

        return ( error => $class->ml( 'widget.shopitemoptions.error.banned' ) )
            if $remote && $target_u->has_banned( $remote );

        $item_data{target_userid} = $target_u->id;

    } elsif ( $post->{for} eq 'random' ) {
        my $target_u;
        if ( $post->{username} eq '(random)' ) {
            $target_u = DW::Pay::get_random_active_free_user();
            return ( error => $class->ml( 'widget.shopitemoptions.error.nousers' ) )
                unless LJ::isu( $target_u );
            $item_data{anonymous_target} = 1;
        } else {
            $target_u = LJ::load_user( $post->{username} );
            return ( error => $class->ml( 'widget.shopitemoptions.error.invalidusername' ) )
                unless LJ::isu( $target_u );
        }

        return ( error => $class->ml( 'widget.shopitemoptions.error.banned' ) )
            if $remote && $target_u->has_banned( $remote );

        $item_data{target_userid} = $target_u->id;
        $item_data{random} = 1;

    } elsif ( $post->{for} eq 'new' ) {
        my @email_errors;
        LJ::check_email( $post->{email}, \@email_errors, $post, $opts{email_checkbox} );
        if ( @email_errors ) {
            return ( error => join( ', ', @email_errors ) );
        } else {
            $item_data{target_email} = $post->{email};
        }
    }

    if ( $post->{deliverydate_mm} && $post->{deliverydate_dd} && $post->{deliverydate_yyyy} ) {
        my $given_date = DateTime->new(
            year => $post->{deliverydate_yyyy}+0,
            month => $post->{deliverydate_mm}+0,
            day => $post->{deliverydate_dd}+0,
        );

        $item_data{deliverydate} = $given_date->date
            unless $given_date->date eq DateTime->today->date;
    }

    $item_data{anonymous} = 1
        if $post->{anonymous} || !$remote;

    $item_data{reason} = LJ::strip_html( $post->{reason} );  # plain text

    # build a new item and try to toss it in the cart.  this fails if there's a
    # conflict or something
    if ( $post->{accttype} ) {
        my ( $rv, $err ) = $cart->add_item(
            DW::Shop::Item::Account->new( type => $post->{accttype}, user_confirmed => $post->{alreadyposted}, force_spelling => $post->{force_spelling}, %item_data )
        );
        return ( error => $err ) unless $rv;
    } elsif ( $post->{item} eq "rename" ) {
        my ( $rv, $err ) = $cart->add_item(
            DW::Shop::Item::Rename->new( cannot_conflict => 1, %item_data )
        );

        return ( error => $err ) unless $rv;
    }

    return;
}

1;
