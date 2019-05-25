#!/usr/bin/perl
#
# DW::RenameToken - Token which can be applied to a journal to change the username.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::RenameToken;

=head1 NAME

DW::RenameToken - Token which can be applied to a journal to change the username.

=head1 SYNOPSIS

  use DW::Rename;

  # create:
  # return a DW::RenameToken object
  my $new_token_obj = DW::RenameToken->create_token( ownerid => $u->id, cartid => $cart->id );

  # convenience method which returns the string representation of the token. Same as $token_obj->token
  my $new_token_string = DW::RenameToken->create( ownerid => $u->id, cartid => $cart->id );

  # special token for internal use
  my $internal_token = DW::RenameToken->create_token( systemtoken => 1 );


  # try to use...
  my $token_obj = DW::RenameToken->new( token => $POST{token} );
  if ( $token_obj->applied ) { print "Already used" }
  elsif ( $token_obj->revoked ) { print "Revoked by a site admin" }
  else { $token_obj->apply( userid => $id_of_the_journal_being_renamed, from => $oldname, to => $newname ) }

=cut

use strict;
use warnings;

use DW::Shop::Cart;

use fields qw(renid auth cartid ownerid renuserid fromuser touser rendate status);

use constant { AUTH_LEN => 13, ID_LEN => 7 };
use constant DIGITS => qw(A B C D E F G H J K L M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9);
use constant { TOKEN_LEN => AUTH_LEN + ID_LEN, DIGITS_LEN => scalar(DIGITS) };

=head1 API

=head2 C<< $class->create_token >>

Create a new rename token and return the DW::RenameToken object.

=head2 C<< $class->create >>

Create a new rename token and return the string token representation of the rename token

Args
=item ownerid => id of the user who gets to use the rename token
=item cartid => id of the cart where this rename token was bought
=item systemtoken => whether this token is owned by the system instead of a user. Used for automatically generated tokens -- manual renames, moving aside a user to ex_* etc. When this is on, the ownerid is ignored.
=cut

sub create_token {
    my ( $class, %opts ) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Unable to connect to database.\n";

    my $sth = $dbh->prepare(
        q{INSERT INTO renames (renid, auth, cartid, ownerid, status)
          VALUES (NULL, ?, ?, ?, 'U')}
    ) or die "Unable to allocate statement handle.\n";

    my $uid      = $opts{systemtoken} ? 0 : $opts{ownerid};
    my $cartid   = $opts{cartid};
    my $authcode = LJ::make_auth_code(AUTH_LEN);

    $sth->execute( $authcode, $cartid, $uid );
    die "Unable to create rename token: " . $dbh->errstr . "\n"
        if $dbh->err;

    return bless(
        {
            renid   => $dbh->{mysql_insertid},
            auth    => $authcode,
            cartid  => $cartid,
            ownerid => $uid,
            status  => 'U'
        },
        "DW::RenameToken"
    );
}

sub create {
    my ( $class, %opts ) = @_;
    return $class->create_token(%opts)->token;
}

=head2 C<< $class->valid_format( string => tokentovalidate ) >>

Verifies if this could be a valid format for the rename token. Checks length and characters.

=cut

sub valid_format {
    my ( $class, %opts ) = @_;

    my $string = uc( $opts{string} // '' );
    return 0 unless length $string == TOKEN_LEN;

    my %valid_digits = map { $_ => 1 } DIGITS;
    my @string_array = split( //, $string );
    foreach my $char (@string_array) {
        return 0 unless $valid_digits{$char};
    }

    return 1;
}

=head2 C<< $class->new >>

Returns object for rename token, given the token string, or undef if none exists.

=item userid => userid of the journal being renamed
=item from   => old username
=item to     => new username
=cut

sub new {
    my ( $class, %opts ) = @_;
    my $dbr = LJ::get_db_reader();

    return undef unless $class->valid_format( string => $opts{token} );

    my ( $id, $auth ) = $class->decode( $opts{token} );
    my $renametoken = $dbr->selectrow_hashref(
"SELECT renid, auth, cartid, ownerid, renuserid, fromuser, touser, rendate, status FROM renames "
            . "WHERE renid=? AND auth=?",
        undef, $id, $auth
    );

    return undef unless defined $renametoken;

    my $ret = fields::new($class);
    while ( my ( $k, $v ) = each %$renametoken ) {
        $ret->{$k} = $v;
    }

    return $ret;

}

=head2 C<< $class->by_owner_unused( userid => ownerid ) >>

Return a list of unused tokens for this user.

=cut

sub by_owner_unused {
    my ( $class, %opts ) = @_;

    my $userid = $opts{userid} + 0;
    return unless $userid;

    my $dbr = LJ::get_db_reader();

    my $sth = $dbr->prepare(
"SELECT renid, auth, cartid, ownerid, renuserid, fromuser, touser, rendate, status FROM renames "
            . "WHERE ownerid=? AND status='U'" )
        or die "Unable to retrieve list of unused rename tokens: " . $dbr->errstr;

    $sth->execute($userid)
        or die "Unable to retrieve list of unused rename tokens: " . $sth->errstr;

    my @tokens;

    while ( my $token = $sth->fetchrow_hashref ) {
        my $ret = fields::new($class);
        while ( my ( $k, $v ) = each %$token ) {
            $ret->{$k} = $v;
        }
        push @tokens, $ret;
    }

    return @tokens ? [@tokens] : undef;
}

=head2 C<< $class->by_username( user => username ) >>

Return a list of renames involving this username (either to this username, or from this username)

=cut

sub by_username {
    my ( $class, %opts ) = @_;

    # this assumes that we haven't changed what makes a valid username
    #   so that we would be querying a username that was valid but is now invalid
    # seems safe enough to start with
    my $user = LJ::canonical_username( $opts{user} );
    return unless $user;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare(
"SELECT renid, auth, cartid, ownerid, renuserid, fromuser, touser, rendate, status FROM renames "
            . "WHERE fromuser=? OR touser=?" )
        or die "Unable to retrieve list of rename tokens involving a username";

    $sth->execute( $user, $user )
        or die "Unable to retrieve list of rename tokens involving a username";

    my @tokens;

    while ( my $token = $sth->fetchrow_hashref ) {
        my $ret = fields::new($class);
        while ( my ( $k, $v ) = each %$token ) {
            $ret->{$k} = $v;
        }
        push @tokens, $ret;
    }

    return @tokens ? [@tokens] : undef;
}

=head2 C<< $class->_encode( $id, $auth ) >>

Internal. Given a rename token id and a 13-digit auth code, returns a 20-digit
all-uppercase rename token.

=cut

sub _encode {
    my ( $class, $id, $auth ) = @_;
    return uc($auth) . $class->_id_encode($id);
}

=head2 C<< $class->decode( $invite ) >>

Internal. Given a rename token, break it down into its component parts: a rename token id and a 13-character auth code.

=cut

sub decode {
    my ( $class, $token ) = @_;
    return ( $class->_id_decode( substr( $token, AUTH_LEN, ID_LEN ) ),
        uc( substr( $token, 0, AUTH_LEN ) ) );
}

=head2 C<< $class->_id_encode( $num ) >>

Internal. Converts a 32-bit unsigned integer into a fixed-width string
representation in base DIGITS_LEN, based on an alphabet of letters and numbers
that are not easily mistaken for each other.

=cut

sub _id_encode {
    my ( $class, $num ) = @_;
    my $id = "";
    while ($num) {
        my $dig = $num % DIGITS_LEN;
        $id  = (DIGITS)[$dig] . $id;
        $num = ( $num - $dig ) / DIGITS_LEN;
    }
    return ( (DIGITS)[0] x ( ID_LEN - length($id) ) . $id );
}

my %val;
@val{ (DIGITS) } = 0 .. DIGITS_LEN;

=head2 C<< $class->_id_decode( $id ) >>

Internal. Given an id encoding from C<DW::RenameToken::_id_encode>, returns
the original decimal number.

=cut

sub _id_decode {
    my ( $class, $id ) = @_;
    $id = uc($id);

    my $num   = 0;
    my $place = 0;
    foreach my $d ( split //, $id ) {
        return 0 unless exists $val{$d};
        $num = $num * DIGITS_LEN + $val{$d};
    }
    return $num;
}

=head2 C<< $self->apply( %opts ) >>

Record information about how this rename token was applied.

=cut

sub apply {
    my ( $self, %opts ) = @_;

    # modify self
    my $dbh = LJ::get_db_writer();
    $dbh->do(
"UPDATE renames SET renuserid=?, fromuser=?, touser=?, rendate=?, status = 'A' WHERE renid=?",
        undef, $opts{userid}, $opts{from}, $opts{to}, time, $self->id
    );

    # modify status in the cart
    if ( $self->cartid ) {
        my $cart = DW::Shop::Cart->get_from_cartid( $self->cartid );
        foreach my $item ( @{ $cart->items } ) {
            next unless $item->isa("DW::Shop::Item::Rename") && $item->token eq $self->token;
            $item->apply;
        }

        $cart->save;
    }

    return 1;
}

=head2 C<< $self->revoke >>

Mark as revoked in-DB

=cut

sub revoke {
    my $dbh = LJ::get_db_writer();
    $dbh->do( "UPDATE renames SET status = 'R' WHERE renid=?", undef, $_[0]->id );
    return 1;
}

=head2 C<< $self->details >>

Get the details from the log for admin use. Not cached and pretty inefficient.
Also, does not check for privs (leave that to the caller)

=cut

sub details {
    my $self = $_[0];

    my $u = LJ::load_userid( $self->renuserid );
    return unless LJ::isu($u);
    return if $u->is_expunged;    # can't retrieve the info from userlog

    # get more than we need and filter, just in case the timestamps don't match up perfectly
    my $results = $u->selectall_arrayref(
        "SELECT userid, logtime, action, extra FROM userlog "
            . "WHERE userid=? AND action='rename' AND logtime >= ? ORDER BY logtime LIMIT 3",
        { Slice => {} }, $u->userid, $self->rendate
    );

    foreach my $row ( @{ $results || [] } ) {
        my $extra = {};
        LJ::decode_url_string( $row->{extra}, $extra );

        if ( $extra->{from} eq $self->fromuser && $extra->{to} eq $self->touser ) {
            $row->{from} = $extra->{from};
            $row->{to}   = $extra->{to};

            foreach ( split( ":", $extra->{redir} ) ) {
                $row->{redirect}->{
                    {
                        J => "username",    #journal/username
                        E => "email",
                    }->{$_}
                } = 1;
            }

            foreach ( split( ":", $extra->{del} ) ) {
                $row->{del}->{
                    {
                        TB => "trusted_by",
                        WB => "watched_by",
                        T  => "trusted",
                        W  => "watched",
                        C  => "communities",
                    }->{$_}
                } = 1;
            }

            return $row;
        }
    }

    return {};
}

# accessors

=head2 C<< $self->token >>

The string representation of the token (formed by a combination of the auth code and the id)

=head2 C<< $self->applied >>

Whether this token has been used.

=head2 C<< $self->revoked >>

Whether this token has been revoked.

=head2 C<< $self->auth >>

The auth code, randomly generated characters. Not necesarily unique.

=head2 C<< $self->id >>

Unique id for the rename token.

=head2 C<< $self->cartid( [ $cartid ] ) >>

Gets / sets cart where we can look up payment information. May be 0, if the rename token did not pass through the payment system.

=head2 C<< $self->ownerid >>

Owner of the rename token; the one who actually did the applying.  May be different from the user who owns/bought the rename token in case  of gifts, or of renaming of communities, or a system admin doing the rename

=head2 C<< $self->renuserid >>

User id that the rename token was applied to.

=head2 C<< $self->fromuser >>

Original username.

=head2 C<< $self->touser >>

New username.

=head2 C<< $self->rendate >>

UNIX timestamp the token was used.

=cut

sub token {
    my $self = $_[0];

    # _encode is a class method
    return ( ref $self )->_encode( $self->{renid}, $self->{auth} );
}

sub applied {
    my $self = $_[0];
    return ( $self->{status} eq 'A' ) ? 1 : 0;
}

sub revoked {
    my $self = $_[0];
    return ( $self->{status} eq 'R' ) ? 1 : 0;
}

sub cartid {
    return $_[0]->{cartid} unless defined $_[1];
    return $_[0]->{cartid} = $_[1];
}

sub auth      { return $_[0]->{auth} }
sub id        { return $_[0]->{renid} }
sub ownerid   { return $_[0]->{ownerid} }
sub renuserid { return $_[0]->{renuserid} }
sub fromuser  { return $_[0]->{fromuser} }
sub touser    { return $_[0]->{touser} }
sub rendate   { return $_[0]->{rendate} }

=head1 BUGS

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
