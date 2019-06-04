#!/usr/bin/perl
#
# DW::InviteCodes - Invite code management backend for Dreamwidth
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::InviteCodes;

=head1 NAME

DW::InviteCodes - Invite code management backend for Dreamwidth

=head1 SYNOPSIS

  use DW::InviteCodes;

  # Reward the module authors
  my @ic = DW::InviteCodes->generate( owner => LJ::load_user("system"),
                                      count => 2,
                                      reason => "For DW::InviteCodes authors" );

  # Check whether a code is valid
  my $valid = DW::InviteCodes->check_code( code => $code [, userid => $recipient] );

  # Retrieve DW::InviteCodes object(s) by code, owner (all or just unused), or recipient
  # (note: these return objects, not strings)
  my $object = DW::InviteCodes->new( code => $invite );
  my @owned = DW::InviteCodes->by_owner( userid => $userid );
  my @unused = DW::InviteCodes->by_owner_unused( userid => $userid);
  my @used = DW::InviteCodes->by_recipient( userid => $userid );

  # Retrieve a count of all invite codes
  my $count = DW::InviteCodes->unused_count( userid => $userid );

  # Access object data
  my $invite = $object->code;
  my $owner = $object->owner; # userid, not LJ::User object
  my $recipient = $object->recipient; # userid or 0
  my $reason = $object->reason;
  my $email = $object->email;
  my $timegenerate = $object->timegenerate; # unix timestamp
  my $timesent = $object->timesent; #unix timestamp
  my $is_used = $object->is_used; # true if used to create an account

  # Mark the invite code as sent
  $code->send_code( email => $email );

  # Mark the invite code as used
  $code->use_code( user => LJ::load_user('new') );

=cut

use strict;
use warnings;

use fields qw(acid userid rcptid auth reason timegenerate timesent email);

use constant { AUTH_LEN => 13, ACID_LEN => 7 };
use constant DIGITS => qw(A B C D E F G H J K L M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9);
use constant { CODE_LEN => AUTH_LEN + ACID_LEN, DIGITS_LEN => scalar(DIGITS) };

use DW::InviteCodes::Promo;

=head1 API

=head2 C<< $class->generate( [ count => $howmany, ] owner => $forwho, reason => $why >>

Generates $howmany invite codes (default 1) and sets their reason to $why and
owner to $forwho.

If owner is undef, the codes will be 'system codes' and have no source.

=cut

sub generate {
    my ( $class, %opts ) = @_;
    $opts{count} ||= 1;

    my $dbh = LJ::get_db_writer()
        or die "Unable to connect to database.\n";

    my $sth = $dbh->prepare(
        q{INSERT INTO acctcode (acid, userid, rcptid, auth, reason, timegenerate)
          VALUES (NULL, ?, 0, ?, ?, UNIX_TIMESTAMP())}
    ) or die "Unable to allocate statement handle.\n";

    my @invitecodes;
    my @authcodes = map { LJ::make_auth_code(AUTH_LEN) } 1 .. $opts{count};
    my $uid       = $opts{owner} ? $opts{owner}->id : 0;

    foreach my $auth (@authcodes) {
        $sth->execute( $uid, $auth, $opts{reason} );
        die "Unable to generate invite codes: " . $dbh->errstr . "\n"
            if $dbh->err;

        my $acid = $dbh->{mysql_insertid};
        push @invitecodes, $class->encode( $acid, $auth );
    }

    return @invitecodes;
}

=head2 C<< $class->could_be_code( string => $string ) >>

Checks whether $string could possibly be a code. It makes sure that it only
contains DIGITS and is CODE_LEN long.

=cut

sub could_be_code {
    my ( $class, %opts ) = @_;

    my $string = uc( $opts{string} // '' );
    return 0 unless length $string == CODE_LEN;

    my %valid_digits = map { $_ => 1 } DIGITS;
    my @string_array = split( //, $string );
    foreach my $char (@string_array) {
        return 0 unless $valid_digits{$char};
    }

    return 1;
}

=head2 C<< $class->check_code( code => $invite [, userid => $recipient] ) >>

Checks whether code $invite is valid before trying to create an account. Takes
an optional $recipient userid, to protect the code from accidentally being used
if the form is double-submitted.

=cut

sub check_code {
    my ( $class, %opts ) = @_;
    my $dbh  = LJ::get_db_writer();
    my $code = $opts{code};

    # check if this code is a promo code first
    # if it is, make sure it's active and we're not over the creation limit for the code
    my $promo_code_info = DW::InviteCodes::Promo->load( code => $code );
    if ( ref $promo_code_info ) {
        return $promo_code_info->usable;
    }

    return 0 unless $class->could_be_code( string => $code );

    my ( $acid, $auth ) = $class->decode($code);
    my $ac = $dbh->selectrow_hashref( "SELECT userid, rcptid, auth " . "FROM acctcode WHERE acid=?",
        undef, $acid );

    # invalid account code
    return 0 unless ( $ac && uc( $ac->{auth} ) eq $auth );

    # code has already been used
    my $userid = $opts{userid} || 0;
    return 0 if ( $ac->{rcptid} && $ac->{rcptid} != $userid );

    # is the inviter suspended?
    my $u = LJ::load_userid( $ac->{userid} );
    return 0 if ( $u && $u->is_suspended );

    return 1;
}

=head2 C<< $class->check_rate >>

Rate limit code input; only allow one code every five seconds.

Return 1 if rate is okay, return 0 if too fast.

=cut

sub check_rate {
    my $ip = LJ::get_remote_ip();
    if ( LJ::MemCache::get("invite_code_try_ip:$ip") ) {
        LJ::MemCache::set( "invite_code_try_ip:$ip", 1, 5 );
        return 0;
    }
    LJ::MemCache::set( "invite_code_try_ip:$ip", 1, 5 );
    return 1;
}

=head2 C<< $class->paid_status( code => $code ) >>

Checks whether this code comes loaded with a paid account. Returns a DW::Shop::Item::Account 
if yes; undef if not

=cut

sub paid_status {
    my ( $class, %opts ) = @_;
    my $code = $opts{code};

    return undef unless DW::InviteCodes->check_code( code => $code );

    my $itemidref;
    if ( my $cart = DW::Shop::Cart->get_from_invite( $code, itemidref => \$itemidref ) ) {
        my $item = $cart->get_item($itemidref);
        return $item if $item && $item->isa('DW::Shop::Item::Account');
    }

    return undef;
}

=head2 C<< $object->use_code( user => $recipient ) >>

Marks an invite code as having been used to create the $recipient account.

=cut

sub use_code {
    my ( $self, %opts ) = @_;
    my $dbh = LJ::get_db_writer();

    $self->{rcptid} = $opts{user}->{userid};

    $dbh->do(
        "UPDATE acctcode SET email=NULL, rcptid=? WHERE acid=?",
        undef, $opts{user}->{userid},
        $self->{acid}
    );

    return 1;    # 1 means success? Needs error return in that case.
}

=head2 C<< $object->send_code ( [ email => $email ] ) >>

Marks an invite code as having been sent. The code may or may not have been used to create a new account.
Make sure if passing email to validate first!

=cut

sub send_code {
    my ( $self, %opts ) = @_;
    my $dbh = LJ::get_db_writer();

    $dbh->do( "UPDATE acctcode SET timesent=UNIX_TIMESTAMP(), email=? WHERE acid=?",
        undef, $opts{email}, $self->{acid} );

    return 1;    # 1 means success? Needs error return in that case.
}

=head2 C<< $class->new( code => $invite ) >>

Returns object for invite, or undef if none exists.

=cut

sub new {
    my ( $class, %opts ) = @_;
    my $dbr = LJ::get_db_reader();

    return undef unless length( $opts{code} ) == CODE_LEN;

    my ( $acid, $auth ) = $class->decode( $opts{code} );
    my $ac = $dbr->selectrow_hashref(
        "SELECT acid, userid, rcptid, auth, reason, timegenerate, timesent, email FROM acctcode "
            . "WHERE acid=? AND auth=?",
        undef, $acid, $auth
    );

    return undef unless defined $ac;

    my $ret = fields::new($class);
    while ( my ( $k, $v ) = each %$ac ) {
        $ret->{$k} = $v;
    }

    return $ret;
}

=head2 C<< $class->by_owner( userid => $userid ) >>

Returns (as objects) the list of all invite codes generated by (or on behalf
of) $userid.

=head2 C<< $class->by_owner_unused( userid => $userid ) >>

Returns (as objects) the list of all unused invite codes generated by
(or on behalf of) $userid.

=head2 C<< $class->by_recipient( userid => $userid ) >>

Returns (as objects) the list of all invite codes used by $userid. (This will
normally be a singleton, but the table declaration doesn't make that key
unique, so going for safety.)

=cut

sub by_owner {
    my ( $class, %opts ) = @_;
    return $class->load_by( 'userid', $opts{userid} );
}

sub by_owner_unused {
    my ( $class, %opts ) = @_;
    return $class->load_by( 'userid', $opts{userid}, 1 );
}

sub by_recipient {
    my ( $class, %opts ) = @_;
    return $class->load_by( 'rcptid', $opts{userid} );
}

=head2 C<< $class->unused_count( user => $userid ) >>

Returns a count of unused invite codes owned by $userid.

=cut

sub unused_count {
    my ( $class, %opts ) = @_;
    my $userid = $opts{userid};

    my $dbr = LJ::get_db_reader();
    my $count =
        $dbr->selectrow_array( "SELECT COUNT(*) FROM acctcode WHERE userid = ? AND rcptid = 0",
        undef, $userid );

    return $count;
}

=head2 C<< $class->load_by( $field, $userid ) >>

Internal. Loads all invite codes with $field (that should be one of the userid
fields) set to $userid. Note: this has protection against most SQL injection
attempts, but is not guaranteed to be 100% safe. Caller should take care not
to pass externally generated values in $field.

=cut

sub load_by {
    my ( $class, $field, $userid, $only_load_unused ) = @_;

    die "SQL injection attempt? '$field'" unless $field =~ /^\w+$/;

    my $dbr = LJ::get_db_reader();

    my $unused_sql = $only_load_unused ? "AND rcptid=0" : "";
    my $sth        = $dbr->prepare(
"SELECT acid, userid, rcptid, auth, reason, timegenerate, timesent, email FROM acctcode WHERE $field = ? $unused_sql"
    ) or die "Unable to retrieve invite codes by $field: " . $dbr->errstr;

    $sth->execute( $userid + 0 )
        or die "Unable to retrieve invite codes by $field: " . $sth->errstr;

    my @ics;

    while ( my $ac = $sth->fetchrow_hashref ) {
        my $ret = fields::new($class);
        while ( my ( $k, $v ) = each %$ac ) {
            $ret->{$k} = $v;
        }
        push @ics, $ret;
    }

    return @ics;
}

=head2 C<< $object->code >>

Returns the object's invite code.

=cut

sub code {
    my ($self) = @_;

    return ( ref $self )->encode( $self->{acid}, $self->{auth} );
}

=head2 C<< $object->owner >>

Returns the object's owner (userid, not LJ::User object).

=cut

sub owner {
    my ($self) = @_;

    return $self->{userid};
}

=head2 C<< $object->recipient >>

Returns the object's recipient (userid or 0).

=cut

sub recipient {
    my ($self) = @_;

    return $self->{rcptid};
}

=head2 C<< $object->reason >>

Returns the object's reason for creation.

=cut

sub reason {
    my ($self) = @_;

    return $self->{reason};
}

=head2 C<< $object->timegenerate >>

Returns the object's  generated date and time as a unix timestamp.

=cut

sub timegenerate {
    my ($self) = @_;

    return $self->{timegenerate};
}

=head2 C<< $object->timesent >>

Returns the date and time the invite code was sent through the interface, as a unix timestamp. The code may or may not have been used since.

=cut

sub timesent {
    my ($self) = @_;

    return $self->{timesent};
}

=head2 C<< $object->email >>

Returns the email address the invite code was sent to through the interface. The code may or may not have been used since.

=cut

sub email {
    my ($self) = @_;

    return $self->{email};
}

=head2 C<< $object->is_used >>

Returns true if the object was used to create an account, false otherwise.

=cut

sub is_used {
    my ($self) = @_;

    return $self->{rcptid} + 0 != 0;
}

=head2 C<< $class->encode( $acid, $auth ) >>

Internal. Given an invite code id and a 13-digit auth code, returns a 20-digit
all-uppercase invite code.

=cut

sub encode {
    my ( $class, $acid, $auth ) = @_;
    return uc($auth) . $class->acid_encode($acid);
}

=head2 C<< $class->decode( $invite ) >>

Internal. Given an invite code, break it down into its component parts: an
invite code id and a 13-character auth code.

=cut

sub decode {
    my ( $class, $code ) = @_;
    return ( $class->acid_decode( substr( $code, AUTH_LEN, ACID_LEN ) ),
        uc( substr( $code, 0, AUTH_LEN ) ) );
}

=head2 C<< $class->acid_encode( $num ) >>

Internal. Converts a 32-bit unsigned integer into a fixed-width string
representation in base DIGITS_LEN, based on an alphabet of letters and numbers
that are not easily mistaken for each other.

=cut

sub acid_encode {
    my ( $class, $num ) = @_;
    my $acid = "";
    while ($num) {
        my $dig = $num % DIGITS_LEN;
        $acid = (DIGITS)[$dig] . $acid;
        $num  = ( $num - $dig ) / DIGITS_LEN;
    }
    return ( (DIGITS)[0] x ( ACID_LEN - length($acid) ) . $acid );
}

my %val;
@val{ (DIGITS) } = 0 .. DIGITS_LEN;

=head2 C<< $class->acid_decode( $acid ) >>

Internal. Given an acid encoding from C<DW::InviteCodes::acid_encode>, returns
the original decimal number.

=cut

sub acid_decode {
    my ( $class, $acid ) = @_;
    $acid = uc($acid);

    my $num   = 0;
    my $place = 0;
    foreach my $d ( split //, $acid ) {
        return 0 unless exists $val{$d};
        $num = $num * DIGITS_LEN + $val{$d};
    }
    return $num;
}

=head1 BUGS

Bound to be some.

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

Pau Amma <pauamma@dreamwidth.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
