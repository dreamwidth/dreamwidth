#!/usr/bin/perl
#
# DW::Shop::Item::Account
#
# Represents a paid account that someone is purchasing.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Costanzo <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Item::Account;

use strict;
use DW::InviteCodes;
use DW::Pay;


# instantiates an account to be purchased of some sort
sub new {
    my ( $class, %args ) = @_;

    my $type = delete $args{type};
    return undef unless exists $LJ::SHOP{$type};

    # from_userid will be 0 if the sender isn't logged in
    return undef unless $args{from_userid} == 0 || LJ::load_userid( $args{from_userid} );

    # now do validation.  since new is only called when the item is being added
    # to the shopping cart, then we are comfortable doing all of these checks
    # on things at the time this item is put together
    if ( my $uid = $args{target_userid} ) {
        # userid needs to exist
        return undef unless LJ::load_userid( $uid );
    } elsif ( my $email = $args{target_email} ) {
        # email address must be valid
        my @email_errors;
        LJ::check_email( $email, \@email_errors );
        return undef if @email_errors;
    } else {
        return undef;
    }

    if ( $args{deliverydate} ) {
        return undef unless $args{deliverydate} =~ /^\d\d\d\d-\d\d-\d\d$/;
    }

    if ( $args{anonymous} ) {
        return undef unless $args{anonymous} == 1;
    }

    # looks good
    return bless {
        # user supplied arguments (close enough)
        cost    => $LJ::SHOP{$type}->[0] + 0.00,
        months  => $LJ::SHOP{$type}->[1],
        class   => $LJ::SHOP{$type}->[2],
        %args,

        # internal things we use to track the state of this item
        type    => 'account',
        applied => 0,
        cartid  => 0,
    }, $class;
}


# called when we are told we need to apply this item, i.e., turn it on.  note that we
# update ourselves, but it's up to the cart to make sure that it saves.
sub apply {
    my $self = $_[0];
    return 1 if $self->applied;

    # 1) deliverydate must be present/past
    if ( my $ddate = $self->deliverydate ) {
        my $cur = LJ::mysql_time();
        $cur =~ s/^(\d\d\d\d-\d\d-\d\d).+$/$1/;

        return 0
            unless $ddate le $cur;
    }

    # application variability
    return $self->_apply_email  if $self->t_email;
    return $self->_apply_userid if $self->t_userid;

    # something weird, just kill this item!
    $self->{applied} = 1;
    return 1;
}


# internal application sub, do not call
sub _apply_userid {
    my $self = $_[0];
    return 1 if $self->applied;

    # will need this later
    my $fu = LJ::load_userid( $self->from_userid );
    unless ( $self->anonymous || $fu ) {
        warn "Failed to apply: NOT anonymous and no from_user!\n";
        return 0;
    }

    # need this user
    my $u = LJ::load_userid( $self->t_userid )
        or return 0;

    # try to add the paid time to the user
    DW::Pay::add_paid_time( $u, $self->class, $self->months )
        or return 0;

    # we're applied now, regardless of what happens with the email
    $self->{applied} = 1;

    # now we have to mail this code
    my ( $body, $subj );
    if ( $self->anonymous ) {
        $subj = LJ::Lang::ml( 'shop.email.user.anon.subject', { sitename => $LJ::SITENAME } );
        $body = LJ::Lang::ml( 'shop.email.user.anon.body',
            {
                touser    => $u->user,
                email     => $self->t_email,
                sitename  => $LJ::SITENAME,
            }
        );
    } else {
        $subj = LJ::Lang::ml( 'shop.email.user.subject', { sitename => $LJ::SITENAME } );
        $body = LJ::Lang::ml( 'shop.email.user.body',
            {
                touser    => $u->user,
                email     => $self->t_email,
                sitename  => $LJ::SITENAME,
                fromuser  => $fu->user,
            }
        );
    }

    # send the email to the user
    LJ::send_mail( {
        to => $u->email_raw,
        from => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITENAME,
        subject => $subj,
        body => $body
    } );

    # tell the caller we're happy
    return 1;
}


# internal application sub, do not call
sub _apply_email {
    my $self = $_[0];
    return 1 if $self->applied;

    # will need this later
    my $fu = LJ::load_userid( $self->from_userid );
    unless ( $self->anonymous || $fu ) {
        warn "Failed to apply: NOT anonymous and no from_user!\n";
        return 0;
    }

    my $reason = join ':', 'payment', $self->class, $self->months;
    my ($code) = DW::InviteCodes->generate( reason => $reason );
    my ($acid) = DW::InviteCodes->decode( $code );

    # store in the db
    my $dbh = LJ::get_db_writer()
        or return 0;
    $dbh->do( 'INSERT INTO shop_codes (acid, cartid, itemid) VALUES (?, ?, ?)',
              undef, $acid, $self->cartid, $self->id );
    return 0
        if $dbh->err;

    # now we have to mail this code
    my ( $body, $subj );
    if ( $self->anonymous ) {
        $subj = LJ::Lang::ml( 'shop.email.email.anon.subject', { sitename => $LJ::SITENAME } );
        $body = LJ::Lang::ml( 'shop.email.email.anon.body',
            {
                email     => $self->t_email,
                sitename  => $LJ::SITENAME,
                createurl => "$LJ::SITEROOT/create?code=$code",
            }
        );
    } else {
        $subj = LJ::Lang::ml( 'shop.email.email.subject', { sitename => $LJ::SITENAME } );
        $body = LJ::Lang::ml( 'shop.email.email.body',
            {
                email     => $self->t_email,
                sitename  => $LJ::SITENAME,
                createurl => "$LJ::SITEROOT/create?code=$code&from=" . $fu->user,
                fromuser  => $fu->user,
            }
        );
    }

    # send the email to the user
    my $rv = LJ::send_mail( {
        to => $self->t_email,
        from => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITENAME,
        subject => $subj,
        body => $body
    } );

    # if this worked, then we're applied! yay!
    if ( $rv ) {
        $self->{applied} = 1;
        return 1;
    }

    # else ... something naughty happened :(
    warn "Failed to send email!\n";
    return 0;
}


# called when we need to turn this item off
sub unapply {
    my $self = $_[0];
    return unless $self->applied;

    # do the application process now, and if it succeeds...
    $self->{applied} = 0;
    warn "$self->{class} unapplied $self->{months} months\n";

    return 1;
}


# returns 1 if this item is allowed to be added to the shopping cart
sub can_be_added {
    my ( $self, %opts ) = @_;

    my $errref = $opts{errref};

    # check to see if we're over the permanent account limit
    if ( $self->permanent && DW::Pay::num_permanent_accounts_available() < 1 ) {
        $$errref = LJ::Lang::ml( 'shop.item.account.canbeadded.noperms' );
        return 0;
    }

    return 1;
}


# given another item, see if that item conflicts with this item (i.e.,
# if you can't have both in your shopping cart at the same time).
#
# returns undef on "no conflict" else an error message.
sub conflicts {
    my ( $self, $item ) = @_;

    # first see if we're talking about the same target
    # note that we're not checking email here because they may want to buy
    # multiple paid accounts and send them to all to the same email address
    # (so they can can create multiple new paid accounts)
    return if
        ( $self->t_userid && ( $self->t_userid != $item->t_userid ) ) ||
        ( $self->t_email                                            );

    # target same, if both are permanent, then fail because
    # THERE CAN BE ONLY ONE
    return LJ::Lang::ml( 'shop.item.account.conflicts.multipleperms' )
        if $self->permanent && $item->permanent;

    # otherwise ensure that the classes are the same
    return LJ::Lang::ml( 'shop.item.account.conflicts.differentpaid' )
        if $self->class ne $item->class;

    # guess we allow it
    return undef;
}


# render our target as a string
sub t_html {
    my $self = $_[0];

    if ( my $uid = $self->t_userid ) {
        my $u = LJ::load_userid( $uid );
        return $u->ljuser_display
            if $u;
        return "<strong>invalid userid $uid</strong>";

    } elsif ( my $email = $self->t_email ) {
        return "<strong>$email</strong>";

    }

    return "<strong>invalid/unknown target</strong>";
}


# render the item name as a string
sub name_html {
    my $self = $_[0];

    my $name = $self->class_name;
    return $name if $self->permanent;
    return LJ::Lang::ml( 'shop.item.account.name', { name => $name, num => $self->months } );
}


sub class_name {
    my $self = $_[0];

    foreach my $cap ( keys %LJ::CAP ) {
        return $LJ::CAP{$cap}->{_visible_name}
            if $LJ::CAP{$cap} && $LJ::CAP{$cap}->{_account_type} eq $self->class;
    }

    return 'Invalid Account Class';
}


# returns a short string talking about what this is
sub short_desc {
    my $self = $_[0];

    # does not contain HTML, I hope
    my $desc = $self->name_html;

    my $for = $self->t_email;
    unless ( $for ) {
        my $u = LJ::load_userid( $self->t_userid );
        $for = $u->user
            if $u;
    }

    # FIXME: english strip
    return "$desc for $for";
}


# this is a getter/setter so it is pulled out
sub id {
    return $_[0]->{id} unless defined $_[1];
    return $_[0]->{id} = $_[1];
}


# gets/sets
sub cartid {
    return $_[0]->{cartid} unless defined $_[1];
    return $_[0]->{cartid} = $_[1];
}


# simple accessors
sub applied      { return $_[0]->{applied};         }
sub cost         { return $_[0]->{cost};            }
sub months       { return $_[0]->{months};          }
sub class        { return $_[0]->{class};           }
sub t_userid     { return $_[0]->{target_userid};   }
sub t_email      { return $_[0]->{target_email};    }
sub permanent    { return $_[0]->months == 99;      }
sub from_userid  { return $_[0]->{from_userid};     }
sub deliverydate { return $_[0]->{deliverydate};    }
sub anonymous    { return $_[0]->{anonymous};       }


1;
