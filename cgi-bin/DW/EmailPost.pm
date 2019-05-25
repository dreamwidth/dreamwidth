#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::EmailPost;

use strict;

use DW::EmailPost::Base;
use DW::EmailPost::Entry;
use DW::EmailPost::Comment;

=head1 NAME

DW::EmailPost - Handles dispatching to the correct subclasses when email posting

=head1 SYNOPSIS

    # may be either an entry or a comment reply
    # returns something to handle if we wish to handle it
    # undef if not
    my $email_post = DW::EmailPost->get_handler( $mime_object );
    if ( $email_post ) {
        my ( $ok, $status_msg ) = $email_post->process;
        if ( $email_post->dequeue ) { ... }
    }
=cut

=head2 C<< $class->get_handler( $mime_object ) >>

Returns an instance of DW::EmailPost::* that can handle the given email

=cut

sub get_handler {
    my ( $class, $mime_object ) = @_;

    my $handler;
    my $destination;
    if ( DW::EmailPost::Entry->should_handle($mime_object) ) {
        $handler = DW::EmailPost::Entry->new($mime_object);
    }
    elsif ( DW::EmailPost::Comment->should_handle($mime_object) ) {
        $handler = DW::EmailPost::Comment->new($mime_object);
    }

    return $handler;
}

*get_entity = \&DW::EmailPost::Base::get_entity;

1;
