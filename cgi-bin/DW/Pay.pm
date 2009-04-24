#!/usr/bin/perl
#
# DW::Pay
#
# Core of the payment system.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2008-2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Pay;

use strict;

use Carp qw/ confess /;
use HTTP::Request;
use LWP::UserAgent;

our $error_code = undef;
our $error_text = undef;

use constant ERR_FATAL => 1;
use constant ERR_TEMP => 2;

################################################################################
# DW::Pay::type_is_valid
#
# ARGUMENTS: typeid
#
#   typeid      required    the id of the type we're checking
#
# RETURN: 1/0 if the type is a valid type
#
sub type_is_valid {
    my $type = shift()+0;
    return 1 if $LJ::CAP{$_[0]} && $LJ::CAP{$_[0]}->{_account_type};
    return 0;
}

################################################################################
# DW::Pay::type_name
#
# ARGUMENTS: typeid
#
#   typeid      required    the id of the type we're checking
#
# RETURN: string name of type, else undef
#
sub type_name {
    confess 'invalid typeid'
        unless DW::Pay::type_is_valid( $_[0] );
    return $LJ::CAP{$_[0]}->{_visible_name};
}

################################################################################
# DW::Pay::get_paid_status
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: Hashref if paid (or has ever been), undef if free:
#
#   {
#       typeid => ...
#       expiretime => db time epoch seconds they expire at
#       expiresin => seconds until they expire
#       permanent => 1/0 if they're permanent
#   }
#
sub get_paid_status {
    DW::Pay::clear_error();

    my $uuid = shift;

    my $uid = LJ::want_userid($uuid) if defined $uuid;
    return error( ERR_FATAL, "Invalid user object/userid passed in." )
        unless defined $uid && $uid > 0;

    my $dbr = DW::Pay::get_db_reader()
        or return error( ERR_TEMP, "Failed acquiring database reader handle." );
    my $row = $dbr->selectrow_hashref( q{
            SELECT IFNULL(expiretime, 0) - UNIX_TIMESTAMP() AS 'expiresin', typeid, expiretime, permanent
            FROM dw_paidstatus
            WHERE userid = ?
        }, undef, $uid );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;

    return $row;
}

################################################################################
# DW::Pay::default_typeid
#
# RETURN: typeid of the default account type.
#
sub default_typeid {
    # try to get the default cap class.  note that we confess here because
    # these errors are bad enough to warrant bailing whoever is calling us.
    my @defaults = grep { $LJ::CAP{$_}->{_account_default} } keys %LJ::CAP;
    confess 'must have one %LJ::CAP class set _account_default to use the payment system'
        if scalar( @defaults ) < 1;
    confess 'only one %LJ::CAP class can be set as _account_default'
        if scalar( @defaults ) > 1;

    # There Can Be Only One
    return $defaults[0];
}

################################################################################
# DW::Pay::get_current_account_status
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: undef for free, else a typeid of the account type.
#
sub get_current_account_status {
    # try to get current paid status
    my $stat = DW::Pay::get_paid_status( @_ );

    # free accounts: no row, or expired
    return DW::Pay::default_typeid() unless defined $stat;
    return DW::Pay::default_typeid() unless $stat->{permanent} || $stat->{expiresin} > 0;

    # valid row, return whatever type it is
    return $stat->{typeid};
}

################################################################################
# DW::Pay::get_account_expiration_time
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: -1 for free, 0 for expired paid, else the unix timestamp this
#         account expires on...
#
# yes, this function has a very weird return value.  :(
#
sub get_account_expiration_time {
    # try to get current paid status
    my $stat = DW::Pay::get_paid_status( @_ );

    # free accounts: no row, or expired
    return -1 unless defined $stat;
    return  0 unless $stat->{permanent} || $stat->{expiresin} > 0;

    # valid row, return whatever the expiration time is
    return time() + $stat->{expiresin};
}

################################################################################
# DW::Pay::get_account_type
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: value defined as _account_type in %LJ::CAP.
#
sub get_account_type {
    my $typeid = DW::Pay::get_current_account_status( @_ );
    confess 'account has no valid typeid'
        unless $typeid && $typeid > 0;
    confess "typeid $typeid not a valid account level"
        unless $LJ::CAP{$typeid} && $LJ::CAP{$typeid}->{_account_type};
    return $LJ::CAP{$typeid}->{_account_type};
}

################################################################################
# DW::Pay::get_account_type_name
#
# ARGUMENTS: uuserid
#
#   uuserid     required    user object or userid to get paid status of
#
# RETURN: value defined as _visible_name in %LJ::CAP.
#
sub get_account_type_name {
    my $typeid = DW::Pay::get_current_account_status( @_ );
    confess 'account has no valid typeid'
        unless $typeid && $typeid > 0;
    confess "typeid $typeid not a valid account level"
        unless $LJ::CAP{$typeid} && $LJ::CAP{$typeid}->{_visible_name};
    return $LJ::CAP{$typeid}->{_visible_name};
}

################################################################################
# DW::Pay::get_current_paid_userids
#
# ARGUMENTS: limit => #rows, typeid => paid account type, permanent => 0|1
#
#   limit       optional    how many userids to return (default: no limit)
#   typeid      optional    1 to restrict to basic paid, 2 for premium paid
#                           (default: both)
#   permanent   optional    false to restrict to expiring accounts, true to
#                           permanent (default: both)
#
# RETURN: arrayref of userids for currently paid accounts matching the above
#         restrictions
#
sub get_current_paid_userids {
    DW::Pay::clear_error();

    my %opts = @_;

    my $sql = 'SELECT userid FROM dw_paidstatus WHERE ';
    my ( @where, @values );

    if ( exists $opts{permanent} ) {
        push @where, 'permanent = ?';
        push @values, ($opts{permanent} ? 1 : 0);
        push @where, 'expiretime > UNIX_TIMESTAMP(NOW())'
            unless $opts{permanent};
    } else {
        push @where, '(permanent = 1 OR expiretime > UNIX_TIMESTAMP(NOW()))';
    }

    if ( exists $opts{typeid} ) {
        push @where, 'typeid = ?';
        push @values, $opts{typeid};
    }

    $sql .= join ' AND ', @where;

    if ( exists $opts{limit} ) {
        $sql .= ' LIMIT ?';
        push @values, $opts{limit};
    }

    my $dbr = DW::Pay::get_db_reader()
        or return error( ERR_TEMP, "Unable to get db reader." );
    my $uids = $dbr->selectcol_arrayref( $sql, {}, @values );
    return error( ERR_FATAL, "Database error: " . $dbr->errstr )
        if $dbr->err;
    return $uids;
}

################################################################################
# DW::Pay::update_paid_status
#
# ARGUMENTS: uuserid, key => value pairs
#
#   uuserid     required    user object or userid to set paid status for
#   key         required    column being set
#   value       required    new value to set column to
#
# RETURN: undef on error, else 1 on success.
#
# NOTE: this function is a low level function intended to be use for admin
# pages and similar functionality.  don't use this willy-nilly in anything
# else as it is probably not what you want!
#
# NOTE: you can set special keys if you want to extend time by months, use
# _set_months to set expiretime to now + N months, and _add_months to append
# that many months.  This is more than likely only useful for such things as
# TODO complete that sentence.
#
sub update_paid_status {
    DW::Pay::clear_error();

    my $u = LJ::want_user( shift() )
        or return error( ERR_FATAL, "Invalid/not a user object." );
    my %cols = ( @_ )
        or return error( ERR_FATAL, "Nothing to change!" );

    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to get db writer." );

    if ( $cols{_set_months} ) {
        $cols{expiretime} = $dbh->selectrow_array( "SELECT UNIX_TIMESTAMP(DATE_ADD(NOW(), INTERVAL $cols{_set_months} MONTH))" );
        delete $cols{_set_months};
    }

    if ( $cols{_add_months} ) {
        my $row = DW::Pay::get_paid_status( $u );
        my $time = $dbh->selectrow_array( "SELECT UNIX_TIMESTAMP(DATE_ADD(FROM_UNIXTIME($row->{expiretime}), " .
                                          "INTERVAL $cols{_add_months} MONTH))" );
        $cols{expiretime} = $time;
        delete $cols{_add_months};
    }

    return error( ERR_FATAL, "Can't change the userid!" )
        if exists $cols{userid};
    return error( ERR_FATAL, "Permanent must be 0/1." )
        if exists $cols{permanent} && $cols{permanent} !~ /^(?:0|1)$/;
    return error( ERR_FATAL, "Typeid must be some number and valid." )
        if exists $cols{typeid} && !( $cols{typeid} =~ /^(?:\d+)$/ && DW::Pay::type_is_valid( $cols{typeid} ) );
    return error( ERR_FATAL, "Expiretime must be some number." )
        if exists $cols{expiretime} && $cols{expiretime} !~ /^(?:\d+)$/;
    return error( ERR_FATAL, "Lastemail must be 0, 3, or 14." )
        if exists $cols{lastemail} && defined $cols{lastemail} && $cols{lastemail} !~ /^(?:0|3|14)$/;

    my $cols = join( ', ', map { "$_ = ?" } sort keys %cols );
    my @bind = map { $cols{$_} } sort keys %cols;

    $dbh->do( qq{
            UPDATE dw_paidstatus SET $cols WHERE userid = ?
        }, undef, @bind, $u->{userid} );
    return error( ERR_FATAL, "Database error: " . $dbh->errstr )
        if $dbh->err;

    return 1;
}

################################################################################
# DW::Pay::num_permanent_accounts_available
#
# ARGUMENTS: none
#
# RETURN: number of permanent accounts that are still available for purchase
#         -1 if there is no limit on how many permanent accounts can be
#         purchased
#
sub num_permanent_accounts_available {
    DW::Pay::clear_error();

    return 0 unless $LJ::PERMANENT_ACCOUNT_LIMIT;
    return -1 if $LJ::PERMANENT_ACCOUNT_LIMIT < 0;

    # try memcache first
    my $ct = LJ::MemCache::get( 'numpermaccts' );
    return $ct if defined $ct;

    # not in memcache, so let's hit the database
    # FIXME: add ddlockd so we don't hit the db in waves every 60 seconds
    my $dbh = DW::Pay::get_db_writer()
        or return error( ERR_TEMP, "Unable to get db writer." );
    my $ct = $dbh->selectrow_array( 'SELECT COUNT(*) FROM dw_paidstatus WHERE permanent = 1' )+0;
    LJ::MemCache::set( 'numpermaccts', $ct, 60 );

    return $ct;
}

################################################################################
# DW::Pay::num_permanent_accounts_available_estimated
#
# ARGUMENTS: none
#
# RETURN: estimated number of permanent accounts that are still available for
#         purchase
#         -1 if there is no limit on how many permanent accounts can be
#         purchased
#
sub num_permanent_accounts_available_estimated {
    my $num_available = DW::Pay::num_permanent_accounts_available();
    return $num_available if $num_available < 1;

    return 10  if $num_available <= 10;
    return 25  if $num_available <= 25;
    return 50  if $num_available <= 50;
    return 100 if $num_available <= 100;
    return 150 if $num_available <= 150;
    return 200 if $num_available <= 200;
    return 300 if $num_available <= 300;
    return 400 if $num_available <= 400;
    return 500;
}

################################################################################
################################################################################
################################################################################

# this internal method takes a user's paid status (which is the accurate record
# of what caps and things a user should have) and then updates their caps.  i.e.,
# this method is used to make the user's actual caps reflect reality.
sub sync_caps {
    my $u = LJ::want_user( shift )
        or return error( ERR_FATAL, "Must provide a user to sync caps for." );
    my $ps = DW::Pay::get_paid_status( $u );

    # calculate list of caps that we care about
    my @bits = grep { $LJ::CAP{$_}->{_account_type} } keys %LJ::CAP;
    my $default = DW::Pay::default_typeid();

    # either they're free, or they expired (not permanent)
    if ( ! $ps || ( ! $ps->{permanent} && $ps->{expiresin} < 0 ) ) {
        # reset back to the default, and turn off all other bits; then set the
        # email count to defined-but-0
        LJ::modify_caps( $u, [ $default ], [ grep { $_ != $default } @bits ] );
        DW::Pay::update_paid_status( $u, lastemail => 0 );

    } else {
        # this is a really bad error we should never have... we can't
        # handle this user
        # FIXME: candidate for email-site-admins
        return error( ERR_FATAL, "Unknown typeid." )
            unless DW::Pay::type_is_valid( $ps->{typeid} );

        # simply modify it to use the typeid specified, as typeids are bits... but
        # turn off any other bits
        LJ::modify_caps( $u, [ $ps->{typeid} ], [ grep { $_ != $ps->{typeid} } @bits ] );
        DW::Pay::update_paid_status( $u, lastemail => undef );
    }

    return 1;
}

sub error {
    $DW::Pay::error_code = $_[0]+0;
    $DW::Pay::error_text = $_[1] || "Unknown error.";
    return undef;
}

sub error_code {
    return $DW::Pay::error_code;
}

sub error_text {
    return $DW::Pay::error_text;
}

sub was_error {
    return defined $DW::Pay::error_code;
}

sub clear_error {
    $DW::Pay::error_code = $DW::Pay::error_text = undef;
}

sub get_db_reader {
    # we always use the master, but perhaps we want to use a specific role for
    # payments later?  so we abstracted this...
    return LJ::get_db_writer();
}

sub get_db_writer {
    return LJ::get_db_writer();
}

1;
