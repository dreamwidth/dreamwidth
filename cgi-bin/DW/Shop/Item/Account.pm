#!/usr/bin/perl
#
# DW::Shop::Item::Account
#
# Represents a paid account that someone is purchasing.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Item::Account;

use base 'DW::Shop::Item';

use strict;
use DW::InviteCodes;
use DW::Pay;

=head1 NAME

DW::Shop::Item::Account - Represents a paid account that someone is purchasing. See
the documentation for DW::Shop::Item for usage examples and description of methods
inherited from that base class.

=head1 API

=head2 C<< $class->new( [ %args ] ) >>

Instantiates an account of some sort to be purchased.

Arguments:
=item ( see DW::Shop::Item ),
=item months => number of months of paid time,
=item class => type of paid account,
=item random => 1 (if gifting paid time to a random user),
=item anonymous_target => 1 (if random user should be anonymous, not identified)

=cut

# override
sub new {
    my ( $class, %args ) = @_;

    if ( $args{anonymous_target} ) {
        return undef unless $args{anonymous_target} == 1;
    }

    if ( $args{random} ) {
        return undef unless $args{random} == 1;
    }

    my $self = $class->SUPER::new(%args);

    if ($self) {
        $self->{months} = $LJ::SHOP{ $self->{type} }->[1];
        $self->{class}  = $LJ::SHOP{ $self->{type} }->[2];
    }

    return $self;
}

# override
sub _apply {
    my $self = $_[0];

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
    unless ( $self->anonymous || $self->from_name || $fu ) {
        warn "Failed to apply: NOT anonymous, no from_name, no from_user!\n";
        return 0;
    }

    # need this user
    my $u = LJ::load_userid( $self->t_userid )
        or return 0;

    # try to add the paid time to the user
    LJ::statushistory_add(
        $u->id,
        $self->from_userid,
        'paidstatus',
        sprintf(
            'Order #%d: applied %d months of %s.',
            $self->cartid, $self->months, $self->class_name
        )
    );
    DW::Pay::add_paid_time( $u, $self->class, $self->months )
        or return 0;

    {
        # By definition, things from anonymous purchasers are gifts.
        my @tags = (
            'gift:' .      ( $fu && $fu->equals($u) ? 'no'  : 'yes' ),
            'anonymous:' . ( $self->anonymous       ? 'yes' : 'no' ),
            'type:' . $self->class,
            'target:account'
        );
        DW::Stats::increment( 'dw.shop.paid_account.applied',
            1, [ @tags, 'months:' . $self->months ] );
        DW::Stats::increment( 'dw.shop.paid_account.applied_months', $self->months, [@tags] );
    }

    # we're applied now, regardless of what happens with the email
    $self->{applied} = 1;

    # now we have to mail this code
    my ( $body, $subj );
    my $accounttype_string =
        $self->permanent
        ? LJ::Lang::ml( 'shop.email.accounttype.permanent', { type => $self->class_name } )
        : LJ::Lang::ml( 'shop.email.accounttype',
        { type => $self->class_name, nummonths => $self->months } );
    $subj = LJ::Lang::ml( "shop.email.acct.subject", { sitename => $LJ::SITENAME } );

    if ( $u->is_community ) {
        my $maintus = LJ::load_userids( $u->maintainer_userids );
        foreach my $maintu ( values %$maintus ) {
            my $emailtype = $fu && $maintu->equals($fu) ? 'self' : 'other';
            $emailtype = 'anon'     if $self->anonymous;
            $emailtype = 'explicit' if $self->from_name;

            $body =
                LJ::Lang::ml( "shop.email.acct.body.start", { touser => $maintu->display_name } );
            $body .= "\n";
            $body .= LJ::Lang::ml(
                "shop.email.comm.$emailtype",
                {
                    fromuser => $fu ? $fu->display_name : '',
                    commname => $u->display_name,
                    sitename => $LJ::SITENAME,
                    fromname => $self->from_name,
                }
            );

            $body .=
                LJ::Lang::ml( "shop.email.acct.body.type", { accounttype => $accounttype_string } );
            $body .= LJ::Lang::ml( "shop.email.acct.body.note", { reason => $self->reason } )
                if $self->reason;

            $body .= LJ::Lang::ml("shop.email.comm.close");
            $body .= LJ::Lang::ml( "shop.email.acct.body.end", { sitename => $LJ::SITENAME } );

            # send the email to the maintainer
            LJ::send_mail(
                {
                    to       => $maintu->email_raw,
                    from     => $LJ::ACCOUNTS_EMAIL,
                    fromname => $LJ::SITENAME,
                    subject  => $subj,
                    body     => $body
                }
            );
        }
    }
    else {
        my $emailtype;
        if ( $self->random ) {
            $emailtype = $self->anonymous ? 'random_anon' : 'random';
        }
        else {
            $emailtype = $fu && $u->equals($fu) ? 'self' : 'other';
            $emailtype = 'anon' if $self->anonymous;
            $emailtype = 'explicit' if $self->from_name;
        }

        $body = LJ::Lang::ml( "shop.email.acct.body.start", { touser => $u->display_name } );
        $body .= "\n";
        $body .= LJ::Lang::ml(
            "shop.email.user.$emailtype",
            {
                fromuser => $fu ? $fu->display_name : '',
                sitename => $LJ::SITENAME,
                fromname => $self->from_name,
            }
        );

        $body .=
            LJ::Lang::ml( "shop.email.acct.body.type", { accounttype => $accounttype_string } );
        $body .= LJ::Lang::ml( "shop.email.acct.body.note", { reason => $self->reason } )
            if $self->reason;

        $body .= LJ::Lang::ml("shop.email.user.close");
        $body .= LJ::Lang::ml( "shop.email.acct.body.end", { sitename => $LJ::SITENAME } );

        # send the email to the user
        LJ::send_mail(
            {
                to       => $u->email_raw,
                from     => $LJ::ACCOUNTS_EMAIL,
                fromname => $LJ::SITENAME,
                subject  => $subj,
                body     => $body
            }
        );
    }

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

    {
        # By definition, things sent to email are gifts.
        my @tags = (
            'gift:yes', 'target:email',
            'anonymous:' . ( $self->anonymous ? 'yes' : 'no' ), 'type:' . $self->class
        );
        DW::Stats::increment( 'dw.shop.paid_account.applied',
            1, [ @tags, 'months:' . $self->months ] );
        DW::Stats::increment( 'dw.shop.paid_account.applied_months', $self->months, [@tags] );
    }

    my $reason = join ':', 'payment', $self->class, $self->months;
    my ($code) = DW::InviteCodes->generate( reason => $reason );
    my ($acid) = DW::InviteCodes->decode($code);

    # store in the db
    my $dbh = LJ::get_db_writer()
        or return 0;
    $dbh->do( 'INSERT INTO shop_codes (acid, cartid, itemid) VALUES (?, ?, ?)',
        undef, $acid, $self->cartid, $self->id );
    return 0
        if $dbh->err;

    # now we have to mail this code
    my ( $body, $subj );
    my $accounttype_string =
        $self->permanent
        ? LJ::Lang::ml( 'shop.email.accounttype.permanent', { type => $self->class_name } )
        : LJ::Lang::ml( 'shop.email.accounttype',
        { type => $self->class_name, nummonths => $self->months } );

    my $emailtype = $self->anonymous ? 'anon' : 'other';

    $subj = LJ::Lang::ml( "shop.email.acct.subject", { sitename => $LJ::SITENAME } );

    $body = LJ::Lang::ml( "shop.email.acct.body.start", { touser => $self->t_email } );
    $body .= "\n";
    $body .= LJ::Lang::ml(
        "shop.email.email.$emailtype",
        {
            fromuser => $fu ? $fu->display_name : '',
            sitename => $LJ::SITENAME,
        }
    );

    $body .= LJ::Lang::ml( "shop.email.acct.body.type", { accounttype => $accounttype_string } );
    $body .= LJ::Lang::ml( "shop.email.acct.body.create",
        { createurl => "$LJ::SITEROOT/create?code=$code" } );
    $body .= LJ::Lang::ml( "shop.email.acct.body.note", { reason => $self->reason } )
        if $self->reason;

    $body .= LJ::Lang::ml("shop.email.email.close");
    $body .= LJ::Lang::ml( "shop.email.acct.body.end", { sitename => $LJ::SITENAME } );

    # send the email to the user
    my $rv = LJ::send_mail(
        {
            to       => $self->t_email,
            from     => $LJ::ACCOUNTS_EMAIL,
            fromname => $LJ::SITENAME,
            subject  => $subj,
            body     => $body
        }
    );

    # if this worked, then we're applied! yay!
    if ($rv) {
        $self->{applied} = 1;
        return 1;
    }

    # else ... something naughty happened :(
    warn "Failed to send email!\n";
    return 0;
}

# override
sub unapply {
    my $self = $_[0];
    return unless $self->applied;

    # do the application process now, and if it succeeds...
    $self->{applied} = 0;
    warn "$self->{class} unapplied $self->{months} months\n";

    return 1;
}

# override
sub can_be_added {
    my ( $self, %opts ) = @_;

    my $errref   = $opts{errref};
    my $target_u = LJ::load_userid( $self->t_userid );

    # the receiving user must be a personal or community account
    if ( LJ::isu($target_u) && !$target_u->is_personal && !$target_u->is_community ) {
        $$errref = LJ::Lang::ml('shop.item.account.canbeadded.invalidjournaltype');
        return 0;
    }

    # check to see if we're over the permanent account limit
    if ( $self->permanent && DW::Pay::num_permanent_accounts_available() < 1 ) {
        $$errref = LJ::Lang::ml('shop.item.account.canbeadded.noperms');
        return 0;
    }

    # check to make sure that the target user is valid: not deleted / suspended, etc
    if ( !$opts{user_confirmed} && LJ::isu($target_u) && $target_u->is_inactive ) {
        $$errref = LJ::Lang::ml( 'shop.item.account.canbeadded.notactive',
            { user => $target_u->ljuser_display } );
        return 0;
    }

    # check to make sure the target user's current account type doesn't conflict with the item
    if ( LJ::isu($target_u) ) {
        my $account_type = DW::Pay::get_account_type($target_u);
        if ( $account_type eq 'seed' ) {

            # no paid time can be purchased for seed accounts
            $$errref = LJ::Lang::ml( 'shop.item.account.canbeadded.alreadyperm',
                { user => $target_u->ljuser_display } );
            return 0;
        }
        elsif ( !DW::Shop::Item::Account->allow_account_conversion( $target_u, $self->class ) ) {

            # premium accounts can't get normal paid time
            $$errref = LJ::Lang::ml(
                'shop.item.account.canbeadded.nopaidforpremium',
                { user => $target_u->ljuser_display }
            );
            return 0;
        }
    }

    return 1;
}

# this checks whether we can downgrade the premium to paid
# FIXME: a better fix for this is to have an autorenewal system, and have the paid time
# applied to their account once their current premium time expires
sub allow_account_conversion {
    my ( $class, $u, $to ) = @_;

    # no existing user; assume no previous conflicting account
    return 1 unless LJ::isu($u);

    # no previous paid status; assume no conflicts
    my $paid_status = DW::Pay::get_paid_status($u);
    return 1 unless $paid_status;

    my $from = DW::Pay::type_shortname( $paid_status->{typeid} );

    # doesn't match premium => paid, so allow it
    return 1 unless $from eq 'premium' && $to eq 'paid';

    # allow if we're within two weeks of expiration
    return 1 if $paid_status->{expiresin} <= 3600 * 24 * 14;

    return 0;
}

# override
sub conflicts {
    my ( $self, $item ) = @_;

    # if either item are set as "does not conflict" then never say yes
    return
        if $self->cannot_conflict || $item->cannot_conflict;

    # we can only conflict with other items of our own type
    return
        if ref $self ne ref $item;

    # first see if we're talking about the same target
    # note that we're not checking email here because they may want to buy
    # multiple paid accounts and send them to all to the same email address
    # (so they can can create multiple new paid accounts)
    return
        if ( $self->t_userid && ( $self->t_userid != $item->t_userid ) )
        || ( $self->t_email );

    # target same, if both are permanent, then fail because
    # THERE CAN BE ONLY ONE
    return LJ::Lang::ml('shop.item.account.conflicts.multipleperms')
        if $self->permanent && $item->permanent;

    # otherwise ensure that the classes are the same
    return LJ::Lang::ml('shop.item.account.conflicts.differentpaid')
        if $self->class ne $item->class;

    # guess we allow it
    return undef;
}

# override
sub t_html {
    my ( $self, %opts ) = @_;

    if ( $self->anonymous_target ) {
        my $random_user_string = LJ::Lang::ml('shop.item.account.randomuser');
        if ( $opts{admin} ) {
            my $u = LJ::load_userid( $self->t_userid );
            return "<strong>invalid userid " . $self->t_userid . "</strong>"
                unless $u;
            return "$random_user_string (" . $u->ljuser_display . ")";
        }
        else {
            return "<strong>$random_user_string</strong>";
        }
    }

    # otherwise, fall back upon default display
    return $self->SUPER::t_html(%opts);
}

# override
sub name_text {
    my $self = $_[0];

    my $name = $self->class_name;

    if ( $self->cost_points > 0 ) {
        return LJ::Lang::ml( 'shop.item.account.name.perm',
            { name => $name, points => $self->cost_points } )
            if $self->permanent;
        return LJ::Lang::ml( 'shop.item.account.name',
            { name => $name, num => $self->months, points => $self->cost_points } );
    }
    else {
        return $name if $self->permanent;
        return LJ::Lang::ml( 'shop.item.account.name.nopoints',
            { name => $name, num => $self->months } );
    }
}

=head2 C<< $self->class_name >>

Return the display name of this account class.

=cut

sub class_name {
    my $self = $_[0];

    foreach my $cap ( keys %LJ::CAP ) {
        return $LJ::CAP{$cap}->{_visible_name}
            if $LJ::CAP{$cap} && $LJ::CAP{$cap}->{_account_type} eq $self->class;
    }

    return 'Invalid Account Class';
}

# simple accessors

=head2 C<< $self->months >>

Number of months of paid time to be applied.

=head2 C<< $self->class >>

Account class identifier; not for display.

=head2 C<< $self->permanent >>

Returns whether this item is for a permanent account, or just a normal paid.

=head2 C<< $self->random >>

Returns whether this item is for a random user.

=head2 C<< $self->anonymous_target >>

Returns whether this item for a random user should go to an anonymous user (true)
or to an identified user (false)

=cut

sub months           { return $_[0]->{months}; }
sub class            { return $_[0]->{class}; }
sub permanent        { return $_[0]->months == 99; }
sub random           { return $_[0]->{random}; }
sub anonymous_target { return $_[0]->{anonymous_target}; }

1;
