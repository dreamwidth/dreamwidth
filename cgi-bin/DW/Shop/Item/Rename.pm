#!/usr/bin/perl
#
# DW::Shop::Item::Rename
#
# Represents a rename token that someone is purchasing.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Item::Rename;

use base 'DW::Shop::Item';

use strict;
use DW::RenameToken;
use DW::User::Rename;
use DW::Shop::Cart;

=head1 NAME

DW::Shop::Item::Rename - Represents a rename token that someone is purchasing. See
the documentation for DW::Shop::Item for usage examples and description of methods
inherited from that base class.

=head1 API

=cut

=head2 C<< $class->new( [ %args ] ) >>

Instantiates a rename token to be purchased.

=cut

sub new {
    my ( $class, %args ) = @_;

    # must have been sent to a user
    return undef unless $args{target_userid};

    my $self = $class->SUPER::new( %args, type => "rename" );
    return undef unless $self;

    return $self;
}

#override
sub name_text {
    return $_[0]->token && $_[0]->from_userid == $_[0]->t_userid
        ? LJ::Lang::ml( 'shop.item.rename.name.hastoken.text', { token  => $_[0]->token } )
        : LJ::Lang::ml( 'shop.item.rename.name.notoken',       { points => $_[0]->cost_points } );
}

# override
sub name_html {
    return $_[0]->token && $_[0]->from_userid == $_[0]->t_userid
        ? LJ::Lang::ml(
        'shop.item.rename.name.hastoken',
        {
            token => $_[0]->token,
            aopts => "href='$LJ::SITEROOT/rename?giventoken=" . $_[0]->token . "'"
        }
        )
        : LJ::Lang::ml( 'shop.item.rename.name.notoken', { points => $_[0]->cost_points } );
}

# override
sub note {

    # token is for ourselves, but currently unpaid for
    return LJ::Lang::ml( 'shop.item.rename.note', { aopts => "href='$LJ::SITEROOT/rename/'" } )
        if $_[0]->from_userid == $_[0]->t_userid && !$_[0]->token;

    return "";
}

# override
sub apply_automatically { 0 }

# override
sub _apply {
    my ( $self, %opts ) = @_;

    # very simple (the actual logic for applying is in the rename token object)
    $self->{applied} = 1;

    return 1;
}

# override
sub can_be_added {
    my ( $self, %opts ) = @_;

    my $errref   = $opts{errref};
    my $target_u = LJ::load_userid( $self->t_userid );

    # the receiving user must be a personal journal
    if ( LJ::isu($target_u) && !$target_u->is_personal ) {
        $$errref = LJ::Lang::ml('shop.item.rename.canbeadded.invalidjournaltype');
        return 0;
    }

    return 1;
}

# override
sub cart_state_changed {
    my ( $self, $newstate ) = @_;

# create a new rename token once the cart has been paid for
# but only do so if we haven't created one before (just checking in case we manage to set the cart to
#    paid status multiple times -- but that had better not happen!)
    if ( $newstate == $DW::Shop::STATE_PAID && !$self->{token} ) {
        my $token = DW::RenameToken->create( ownerid => $self->t_userid, cartid => $self->cartid );
        return undef unless $token;

        $self->{token} = $token;

        # now let's tell the user about this token
        my $fu = LJ::load_userid( $self->from_userid );
        my $u  = LJ::load_userid( $self->t_userid )
            or return 0;

        my $from;
        my $vars = {
            sitename => $LJ::SITENAME,
            touser   => $u->user,
            tokenurl => "$LJ::SITEROOT/rename?giventoken=$token",
        };

        if ( $u->equals($fu) ) {
            $from = "self";
        }
        elsif ($fu) {
            $from = "explicit";
            $vars->{fromuser} = $fu->user;
        }
        else {
            $from = "anon";
        }

        DW::Stats::increment(
            'dw.shop.rename_tokens.created',
            1,
            [
                'gift:' .      ( $from eq 'self' ? 'no'  : 'yes' ),
                'anonymous:' . ( $from eq 'anon' ? 'yes' : 'no' )
            ]
        );

        LJ::send_mail(
            {
                to       => $u->email_raw,
                from     => $LJ::ACCOUNTS_EMAIL,
                fromname => $LJ::SITENAME,
                subject =>
                    LJ::Lang::ml( 'shop.email.renametoken.subject', { sitename => $LJ::SITENAME } ),
                body => LJ::Lang::ml( "shop.email.renametoken.$from.body", $vars ),
            }
        );
    }
}

=head2 C<< $self->token >>

Returns the usable encoded representation of the rename token.

=cut

sub token { return $_[0]->{token} }

1;
