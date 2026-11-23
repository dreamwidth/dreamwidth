#!/usr/bin/perl
#
# LJ::Event::ImportStatus
#
# Fired whenever the importer wants to give the user some status to advise them
# of something.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Event::ImportStatus;

use strict;
use Carp qw/ croak /;
use Storable qw/ nfreeze thaw /;
use base 'LJ::Event';

use DW::Importer::Registry;

sub new {
    my ( $class, $u, $type, $optref ) = @_;

    $u = LJ::want_user($u)
        or croak 'Not an LJ::User';

    croak 'second argument not a hashref'
        unless $optref && ref $optref eq 'HASH';

    # the typeid is what we store in the notification; it comes from the registry
    my $item = DW::Importer::Registry->item($type)
        or croak 'Invalid importer item type [' . $type . ']';
    my $typeid = $item->{typeid};

    # now store this item
    my $sid = LJ::alloc_user_counter( $u, 'Z' );
    if ($sid) {
        $u->do( 'INSERT INTO import_status (userid, import_status_id, status) VALUES (?, ?, ?)',
            undef, $u->id, $sid, nfreeze($optref) );
        return $class->SUPER::new( $u, $typeid, $sid );
    }

    # failure :(
    return undef;
}

sub arg_list {
    return ( "Type id", "Import status id" );
}

# always subscribed, you can't unsubscribe, send to everybody, and don't
# give the user any options.  (we assume that if they're importing things,
# they want to know how it went.)
sub is_common      { 1 }
sub is_visible     { 0 }
sub is_significant { 1 }
sub always_checked { 1 }

# this is the header line that shows up on the event
sub as_html {
    my $self   = $_[0];
    my $opts   = $self->_optsref;
    my $status = $opts->{type};

    # status items are special
    return "A status update about your import."
        if $status eq 'status';

    # FIXME: strip these strings into status strings
    my $item     = DW::Importer::Registry->item_for_typeid( $self->arg1 );
    my $item_has = ( $item && $item->{event_noun} ) || 'ERROR, INVALID TYPE';

    # now success message
    my $succeeded = {
        ok        => 'been imported successfully',
        temp_fail => 'failed to import',
        fail      => 'failed to import and will not be retried',
    }->{$status}
        || 'ERROR, UNKNOWN STATUS';

    # put the string together
    return "Your $item_has $succeeded.";
}

# content is the main body of the event
sub content {
    my $self   = $_[0];
    my $opts   = $self->_optsref;
    my $status = $opts->{type};

    if ( $status eq 'status' ) {
        return LJ::html_newlines( $opts->{text} )
            if $opts->{text};

        my $item = DW::Importer::Registry->item_for_typeid( $self->arg1 );
        if ( $item && $item->{reports_posts} ) {
            my $msg = qq(Original post: <a href="$opts->{remote_url}">$opts->{remote_url}</a>\n);
            $msg .=
                qq(Local post: <a href="$opts->{post_res}->{url}">$opts->{post_res}->{url}</a>\n)
                if $opts->{post_res} && $opts->{post_res}->{url};
            $msg .= "\n" . join( "\n", map { " * $_" } @{ $opts->{errors} || [] } ) . "\n";
            return LJ::html_newlines($msg);
        }

        return 'Unknown status update.';

    }
    elsif ( $status eq 'fail' || $status eq 'temp_fail' ) {
        my $msg = $opts->{msg} || 'Unknown error or error not recorded.';
        if ( $status eq 'temp_fail' ) {
            $msg .= "\n\nThis was failure #" . ( $opts->{failures} + 1 ) . ".";
        }
        return LJ::html_newlines($msg);

    }

    return '';
}

# short enough that we can just use this the normal content as the summary
sub content_summary {
    return $_[0]->content(@_);
}

# load our options hashref
sub _optsref {
    my $self = $_[0];
    return $self->{_optsref} if $self->{_optsref};

    my $u    = $self->u;
    my $item = $u->selectrow_array(
        'SELECT status FROM import_status WHERE userid = ? AND import_status_id = ?',
        undef, $u->id, $self->arg2 );
    return undef
        if $u->err || !$item;

    return $self->{_optsref} = thaw($item);
}

# override parent class subscriptions method to always return
# a subscription object for the user
sub raw_subscriptions {
    my ( $class, $self, %args ) = @_;

    $args{ntypeid} = LJ::NotificationMethod::Inbox->ntypeid;    # Inbox

    return $class->_raw_always_subscribed( $self, %args );
}

sub get_subscriptions {
    my ( $self, $u, $subid ) = @_;

    unless ($subid) {
        my $row = {
            userid  => $u->{userid},
            ntypeid => LJ::NotificationMethod::Inbox->ntypeid,    # Inbox
        };

        return LJ::Subscription->new_from_row($row);
    }

    return $self->SUPER::get_subscriptions( $u, $subid );
}

1;
