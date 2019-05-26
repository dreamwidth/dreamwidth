#!/usr/bin/perl
#
# DW::InviteCodes::Promo - Represents a promotional invite code
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::InviteCodes::Promo;

=head1 NAME

DW::InviteCodes::Promo - Represents a promotional invite code

=cut

use strict;

sub _from_row {
    my ( $class, $row ) = @_;
    return bless $row, $class;
}

=head1 CLASS METHODS

=head2 C<< DW::InviteCodes::Promo->load( code => $code ); >>

Gets a DW::InviteCode::Promo objct

=cut

# FIXME: Consider process caching and/or memcache, if this is a busy enough path
sub load {
    my ( $class, %opts ) = @_;
    my $dbh  = LJ::get_db_writer();
    my $code = $opts{code};

    return undef unless $code && $code =~ /^[a-z0-9]+$/i;    # make sure the code is valid first
    my $data =
        $dbh->selectrow_hashref( "SELECT * FROM acctcode_promo WHERE code = ?", undef, $code );
    return undef unless $data;

    return $class->_from_row($data);
}

=head2 C<< DW::InviteCodes::Promo->load_bulk( state => $state ); >>

Return the list of promo codes, optionally filtering by state.
State can be:
  * active ( active promo codes )
  * inactive ( inactive promo codes )
  * unused ( unused promo codes )
  * noneleft ( no uses left )
  * all ( all promo codes )

=cut

sub load_bulk {
    my ( $class, %opts ) = @_;
    my $dbh   = LJ::get_db_writer();
    my $state = $opts{state} || 'active';

    my $sql = "SELECT * FROM acctcode_promo";
    if ( $state eq 'all' ) {

        # do nothing
    }
    elsif ( $state eq 'active' ) {
        $sql .= " WHERE active = '1' AND current_count < max_count";
    }
    elsif ( $state eq 'inactive' ) {
        $sql .= " WHERE active = '0' OR current_count >= max_count";
    }
    elsif ( $state eq 'unused' ) {
        $sql .= " WHERE current_count = 0";
    }
    elsif ( $state eq 'noneleft' ) {
        $sql .= " WHERE current_count >= max_count";
    }

    my $sth = $dbh->prepare($sql) or die $dbh->errstr;
    $sth->execute() or die $dbh->errstr;

    my @out;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @out, $class->_from_row($row);
    }
    return \@out;
}

=head2 C<< $class->is_promo_code( code => $code ) >>

Returns if the given code is a promo code or not.

=cut

sub is_promo_code {
    my ( $class, %opts ) = @_;

    my $promo_code_info = $class->load(%opts);

    return ref $promo_code_info ? 1 : 0;
}

=head1 INSTANCE METHODS

=head2 C<< $self->usable >>

Checks code is available, not already used up, and not expired.

=cut

sub usable {
    my ($self) = @_;

    return 0 unless $self->{active};
    return 0 unless $self->{current_count} < $self->{max_count};

    # 0 for expiry_date means never expire;
    return 0 if $self->{expiry_date} && time() >= $self->{expiry_date};
    return 1;
}

=head2 C<< $self->apply_for_user( $u ) >>

Handle any post-create operations for this user.

=cut

sub apply_for_user {
    my ( $self, $u ) = @_;

    my $code        = $self->code;
    my $paid_type   = $self->paid_class;
    my $paid_months = $self->paid_months;

    LJ::statushistory_add( $u, undef, 'create_from_promo',
        "Created new account from promo code '$code'." );

    if ( defined $paid_type ) {
        if ( DW::Pay::add_paid_time( $u, $paid_type, $paid_months ) ) {
            LJ::statushistory_add( $u, undef, 'paid_from_promo',
                "Created new '$paid_type' account from promo code '$code'." );
        }
    }
}

=head2 C<< $self->code >>

=cut

sub code {
    return $_[0]->{code};
}

=head2 C<< $self->paid_class_name >>

Return the display name of this account class.

=cut

sub paid_class_name {
    my $self = $_[0];

    foreach my $cap ( keys %LJ::CAP ) {
        return $LJ::CAP{$cap}->{_visible_name}
            if $LJ::CAP{$cap} && $LJ::CAP{$cap}->{_account_type} eq $self->paid_class;
    }

    return 'Invalid Account Class';
}

=head2 C<< $self->paid_months >>

=cut

sub paid_months {
    return $_[0]->{paid_class} ? $_[0]->{paid_months} : 0;
}

=head2 C<< $self->paid_class >>

=cut

sub paid_class {
    return $_[0]->{paid_class};
}

=head2 C<< $self->suggest_journal

Return the LJ::User to suggest

=cut

sub suggest_journal {
    my $id = $_[0]->{suggest_journalid};
    return $id ? LJ::load_userid($id) : undef;
}

=head2 C<< $self->use_code >>

Increments the current_count on the given promo code.

=cut

sub use_code {
    my ($self) = @_;
    my $dbh = LJ::get_db_writer();

    my $code = $self->code;

    $dbh->do( "UPDATE acctcode_promo SET current_count = current_count + 1 WHERE code = ?",
        undef, $code );

    return 1;
}

1;
