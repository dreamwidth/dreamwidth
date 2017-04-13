#!/usr/bin/perl
#
# DW::InviteCodeRequests - Invite code request backend for Dreamwidth
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

package DW::InviteCodeRequests;

=head1 NAME

DW::InviteCodeRequests - Invite code request backend for Dreamwidth

=head1 SYNOPSIS

  use DW::InviteCodeRequests;

  ## aggregate information
  # list all outstanding requests, by all users
  my @all_outstanding = DW::InviteCodeRequests->outstanding;


  ## per-user information, and request creation
  # list all of the invite code requests a user has made
  my @user_requests = DW::InviteCodeRequests->by_user( userid => $userid );

  # find out how many invite code requests a user has outstanding
  my $outstanding_count = DW::InviteCodeRequests->outstanding_count( userid => $userid );

  # create a new request for this user if they don't have outstanding requests
  my $new_request = DW::InviteCodeRequests->create( userid => $userid, reason => $reason )
    if ! $outstanding_count;

  ## request processing
  # load a request object
  my $request = DW::InviteCodeRequests->new( reqid => $reqid )

  # accept or reject the request
  $request->accept( num_invites => $num_invites );
  $request->reject;

  ## request data
  my $id = $request->id;
  my $userid = $request->userid;
  my $status = $request->status;    # accepted, rejected, outstanding
  my $reason = $request->reason;
  my $timegenerate = $request->timegenerate;   # unix timestamp
  my $timeprocessed = $request->timeprocessed; # unix timestamp

=cut

use strict;
use warnings;

use fields qw( reqid userid status reason timegenerate timeprocessed );

=head1 API

=head2 C<< $class->new( reqid => $reqid ) >>

Returns object for invite code request, or undef if none exists

=cut

sub new {
    my ($class, %opts) = @_;
    my $reqid = $opts{reqid};

    my $dbr = LJ::get_db_reader();
    my $req = $dbr->selectrow_hashref( "SELECT reqid, userid, status, reason, timegenerate, timeprocessed " .
                                        "FROM acctcode_request WHERE reqid=?", undef, $reqid );

    return undef unless defined $req;

    my $ret = fields::new($class);
    while (my ($k, $v) = each %$req) {
        $ret->{$k} = $v;
    }

    return $ret;
}

=head2 C<< $class->by_user( userid => $userid ) >>

Returns an array of all the requests the user has made.

=cut

sub by_user {
    my ($class, %opts) = @_;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare( "SELECT reqid, userid, status, reason, timegenerate, timeprocessed " .
                            "FROM acctcode_request WHERE userid = ?" )
        or die "Unable to retrieve user's requests: " . $dbr->errstr;
    $sth->execute( $opts{userid} )
        or die "Unable to retrieve user's requests: " . $sth->errstr;

    my @requests;

    while (my $req = $sth->fetchrow_hashref) {
        my $ret = fields::new($class);
        while (my ($k, $v) = each %$req) {
            $ret->{$k} = $v;
        }
        push @requests, $ret;
    }

    return @requests;
}

=head2 C<< $class->create( userid => $userid, reason => $reason ) >>

Create and return a request for additional invite codes, which will be put into
a queue for admin review. Returns undef on failure.

=cut

sub create {
    my ($class, %opts) = @_;
    my $userid = $opts{userid};
    my $reason = $opts{reason};

    return undef unless DW::BusinessRules::InviteCodeRequests::can_request( user => LJ::load_userid( $userid ) );

    my $dbh = LJ::get_db_writer();

    $dbh->do( "INSERT INTO acctcode_request (userid, status, reason, timegenerate, timeprocessed) VALUES (?, 'outstanding', ?, UNIX_TIMESTAMP(), NULL)", undef, $userid, $reason );
    die "Unable to request a new invite code: " . $dbh->errstr if $dbh->err;

    my $reqid = $dbh->{'mysql_insertid'};
    return undef unless $reqid;

    return $class->new( reqid => $reqid );
}

=head2 C<< $class->outstanding_count( userid => $userid ) >>

Returns how many outstanding invite code requests a user has.

=cut

sub outstanding_count {
    my ($class, %opts) = @_;
    my $userid = $opts{userid};

    my $dbr = LJ::get_db_reader();
    my $count = $dbr->selectrow_array( "SELECT COUNT(*) FROM acctcode_request ".
                                       "WHERE userid = ? AND status='outstanding'",
                                       undef, $userid );
    return $count;
}

=head2 C<< $class->outstanding >>

Return a list of all outstanding invite code requests.

=cut

sub outstanding {
    my ($class) = @_;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare( "SELECT reqid, userid, status, reason, timegenerate, timeprocessed " .
                             "FROM acctcode_request WHERE status = 'outstanding'" )
        or die "Unable to retrieve outstanding invite requests: " . $dbr->errstr;

    $sth->execute
        or die "Unable to retrieve outstanding invite requests: " . $sth->errstr;

    my @outstanding;

    while (my $req = $sth->fetchrow_hashref) {
        my $ret = fields::new($class);
        while (my ($k, $v) = each %$req) {
            $ret->{$k} = $v;
        }
        push @outstanding, $ret;
    }

    return @outstanding;
}

=head2 C<< $class->invite_sysbanned( user => $u ) >>

Return whether this user is sysbanned from the invite codes system.
Accepts a user object.

=cut

sub invite_sysbanned {
    my ( $class, %opts ) = @_;
    my $u = $opts{user};

    return 1 if LJ::sysban_check( "invite_user", $u->user );
    return 1 if LJ::sysban_check( "invite_email", $u->email_raw );

    return 0;
}

=head2 C<< $object->accept( [num_invites => $num_invites ] ) >>

Accept this request.

=cut

sub accept {
    my ($self, %opts) = @_;

    my $u = LJ::load_userid( $self->userid );
    my @invitecodes = DW::InviteCodes->generate(
        count => $opts{num_invites},
        owner => $u ,
        reason => "Accepted: " . $self->reason );

    die "Unable to generate invite codes " unless @invitecodes;

    $self->change_status( status => "accepted", count => $opts{num_invites} );

    LJ::send_mail( {
        to => $u->email_raw,
        from => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITENAME,
        subject => LJ::Lang::ml( 'email.invitecoderequest.accept.subject' ),
        body => LJ::Lang::ml( 'email.invitecoderequest.accept.body2', {
            siteroot => $LJ::SITEROOT,
            invitesurl => $LJ::SITEROOT . '/invite',
            sitename => $LJ::SITENAMESHORT,
            number => $opts{num_invites},
            codes => join( "\n", @invitecodes ),
            } ),
    });
}

=head2 C<< $object->reject >>

 Reject this request.

=cut

sub reject {
    my ($self, %opts) = @_;
    $self->change_status( status => "rejected" );

    my $u = LJ::load_userid( $self->userid );
    LJ::send_mail({
        to => $u->email_raw,
        from => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITENAME,
        subject => LJ::Lang::ml( 'email.invitecoderequest.reject.subject' ),
        body => LJ::Lang::ml( 'email.invitecoderequest.reject.body' ),
    });

}

=head2 C<< $object->change_status( status => $status ) >>

Internal. Accepts or rejects a request.

=cut

sub change_status {
    my $dbh = LJ::get_db_writer();
    my ($self, %opts) = @_;

    $dbh->do( "UPDATE acctcode_request SET status = ?, timeprocessed = UNIX_TIMESTAMP() WHERE reqid = ?",
            undef, $opts{status}, $self->id );
    die "Unable to change status to $opts{status}: " . $dbh->errstr if $dbh->err;
}

=head2 C<< $object->id >>

Returns the id of this object.

=cut

sub id {
    my ($self) = @_;

    return $self->{reqid};
}

=head2 C<< $object->userid >>

Returns the userid of the user who made the request.

=cut

sub userid {
    my ($self) = @_;

    return $self->{userid};
}

=head2 C<< $object->status >>

Returns the status of the request. Values can be one of "accepted", "rejected", "outstanding".

=cut

sub status {
    my ($self) = @_;

    return $self->{status};
}

=head2 C<< $object->reason >>

Returns the user-provided reason for requesting more invite codes.

=cut

sub reason {
    my ($self) = @_;

    return $self->{reason};
}

=head2 C<< $object->timegenerate >>

Returns the time the request was made as a unix timestamp.

=cut

sub timegenerate {
    my ($self) = @_;

    return $self->{timegenerate};
}

=head2 C<< $object->timeprocessed >>

Returns the time the request was accepted or rejected as a unix timestamp.

=cut

sub timeprocessed {
    my ($self) = @_;

    return $self->{timeprocessed};
}

=head1 BUGS

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
