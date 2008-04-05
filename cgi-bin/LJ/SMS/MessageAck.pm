#!/usr/bin/perl

package LJ::SMS::MessageAck;

use strict;
use Carp qw(croak);

# LJ::SMS::MessageAck object
#
# internal fields:
#
#    owner_uid     userid to which this ack belongs
#    msgid         msgid to which this ack is a response
#    type          ack type: gateway, smsc, handset, unknown
#    timerecv      unixtime when ack was received
#    status_flag   status flag indicating message success
#    status_code   optional status code given for ack
#    status_text   full status string as received

sub new {
    my ($class, %opts) = @_;
    croak "new is a class method"
        unless $class eq __PACKAGE__;

    my $self = bless {}, $class;

    { # owner argument
        my $owner_arg = delete $opts{owner};
        croak "owner argument must be a valid user object"
            unless LJ::isu($owner_arg);

        $self->{owner_uid} = $owner_arg->id;
    }

    # set msgid if a non-zero one was specified
    $self->{msgid} = delete $opts{msgid};
    croak "invalid msgid: $self->{msgid}"
        if $self->{msgid} && int($self->{msgid}) <= 0;

    # what type of ack is this?  gateway?  handset?
    $self->{type} = delete $opts{type};
    croak "type must be one of 'gateway', 'smsc', 'handset', or 'unknown'"
        unless $self->{type} =~ /^(?:gateway|smsc|handset|unknown)$/;

    # when was this message received?
    $self->{timerecv} = delete $opts{timerecv} || time();
    croak "invalid timerecv: $self->{timerecv}"
        if $self->{timerecv} && int($self->{timerecv}) <= 0;

    # what is the status indicated by this ack?
    $self->{status_flag} = delete $opts{status_flag};
    croak "status_flag must be one of 'success', 'error', or 'unknown'"
        unless $self->{status_flag} =~ /^(?:success|error|unknown)$/;

    # status code is opaque and optional
    $self->{status_code} = delete $opts{status_code};
    croak "invalid status code: $self->{status_code}"
        if $self->{status_code} && length $self->{status_code};

    # what status text was given for this message?
    $self->{status_text} = delete $opts{status_text};
    croak "invalid status text has no length"
        unless length $self->{status_text};

    croak "invalid parameters: " . join(",", keys %opts) 
        if %opts;

    return $self;
}

sub new_from_dsms {
    my ($class, $ack) = @_;
    croak "new_from_dsms is a class method"
        unless $class eq __PACKAGE__;
    croak "invalid ack arg: $ack"
        unless $ack && $ack->isa("DSMS::MessageAck");

    # get msg_uniq from DSMS::MessageAck
    my $msg_uniq = $ack->msg_uniq
        or die "unable to construct LJ::SMS::MessageAck from missing msg_uniq";

    my $msg = LJ::SMS::Message->load_by_uniq($msg_uniq)
        or die "unable to load message by msg_uniq: $msg_uniq";

    return $class->new
        ( owner       => $msg->owner_u,
          msgid       => $msg->msgid,
          type        => $ack->type,
          timerecv    => $ack->timestamp,
          status_flag => $ack->status_flag,
          status_code => $ack->status_code,
          status_text => $ack->status_text, );
}

sub load {
    my $class = shift;
    croak "load is a class method"
        unless $class eq __PACKAGE__;

    my $owner_u = shift;
    croak "invalid owner_u: $owner_u" 
        unless LJ::isu($owner_u);

    my @msgids = @_;
    foreach (@msgids) {
        croak "invalid msgid: $_"
            unless $_ && int($_) > 0;
    }

    my @ret_acks = ();

    my $bind = join(",", map { "?" } @msgids);
    my $sth = $owner_u->prepare
        ("SELECT msgid, type, timerecv, status_flag, status_code, status_text " .
         "FROM sms_msgack WHERE userid=? AND msgid IN ($bind)");
    $sth->execute($owner_u->id, @msgids);

    while (my $row = $sth->fetchrow_hashref) {
        push @ret_acks, LJ::SMS::MessageAck->new
            ( owner => $owner_u,

              map { $_ => $row->{$_} } 
              qw(msgid type timerecv status_flag status_code status_text)
              );              
    }

    return @ret_acks;
}

sub save_to_db {
    my $self = shift;

    # do nothing if already saved to db
    return 1 if $self->{_saved_to_db}++;

    my $owner_u = $self->owner_u;

    my $rv = $owner_u->do
        ("INSERT INTO sms_msgack SET userid=?, msgid=?, type=?, " . 
         "timerecv=?, status_flag=?, status_code=?, status_text=?",
         undef, $owner_u->id, $self->msgid, $self->type,
         $self->timerecv, $self->status_flag, $self->status_code, $self->status_text);
    die $owner_u->errstr if $owner_u->err;

    return $rv;
}

sub apply_to_msg {
    my $self = shift;
    my $msg  = shift;

    # load message automatically unless a specific one
    # is passed in by the caller
    $msg ||= $self->msg;
    die "no msg found for ack application"
        unless $msg && $msg->isa("LJ::SMS::Message");

    # update message status to reflect this ack's receipt
    return $msg->recv_ack($self);
}

sub owner_u {
    my $self = shift;

    # load user obj if valid uid and return
    my $uid = $self->{owner_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub msg {
    my $self = shift;

    return LJ::SMS::Message->load($self->owner_u, $self->msgid);
}

sub _get {
    my $self  = shift;
    my $field = shift;
    croak "unknown field: $field"
        unless exists $self->{$field};

    return $self->{$field};
}

# FIXME: this needs to be done via the message perspective

sub msgid       { _get($_[0], 'msgid'      ) }
sub type        { _get($_[0], 'type'       ) }
sub timerecv    { _get($_[0], 'timerecv'   ) }
sub status_flag { _get($_[0], 'status_flag') }
sub status_code { _get($_[0], 'status_code') }
sub status_text { _get($_[0], 'status_text') }
*id = \&msgid;

1;
