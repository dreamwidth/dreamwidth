#!/usr/bin/perl
#
# DW::Routing::CallInfo
#
# Module to provide accessors for routing call info hashes.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Routing::CallInfo;
use strict;

=head1 NAME

DW::Routing::CallInfo - Module to provide accessors for routing call info hashes.

=head1 SYNOPSIS

=head2 C<< $class->new( $hash ) >>

=cut

sub new {
    my ( $class, $hash ) = @_;

    return bless $hash, $class;
}

=head2 C<< $self->call_opts( $hash ) >>

Retrieve the call opts hash.

=cut

sub call_opts {
    return $_[0]->{__hash};
}

=head2 C<< $self->init_call_opts( $hash, $subpatterns ) >>

Initalizes the call opts.

=cut

sub init_call_opts {
    my ($self, $hash, $args) = @_;

    $self->{__hash} = $hash;
    $self->{subpatterns} = $args;
}

=head2 C<< $self->prepare_for_call >>

Prepares this CallInfo for being called.

=cut

sub prepare_for_call {
    my $hash = $_[0]->{__hash};

    $_[0]->{format} ||= $hash->{format};
}

=head2 C<< $self->call >>

Calls the sub.

=cut

sub call {
    my ( $opts ) = @_;

    my @args;
    @args = @{$opts->subpatterns} if ( $opts->subpatterns );
    $opts->{__hash}->{sub}->( $opts, @args );
}

=head1 Controller API

API to be used from the controllers.

=head2 C<< $self->args >>

Return the arguments passed to the register call.

=cut

sub args { return $_[0]->{__hash}->{args}; }

=head2 C<< $self->format >>

Return the format.

=cut

sub format { return $_[0]->{format}; }

=head2 C<< $self->format_valid >>

Returns if the format is valid for this CallInfo

=cut

sub format_valid {
    my $formats = $_[0]->{__hash}->{formats};
    return 1 if $formats == 1;
    return $formats->{$_[0]->format} || 0;
}

=head2 C<< $self->method_valid( $method ) >>

Returns if the method is valid for the callinfo

=cut

sub method_valid {
    my $methods = $_[0]->{__hash}->{methods};
    return 1 if $methods == 1;
    return $methods->{$_[1]} || 0;
}

=head2 C<< $self->apiver >>

Returns the API version requested.

=cut

sub apiver { return $_[0]->{apiver}; }

=head2 C<< $self->role >>

Current mode: 'app' or 'user' or 'ssl' or 'api'

=cut

sub role { return $_[0]->{role}; }

=head2 C<< $self->ssl >>

Is SSL request?

=cut

sub ssl { return $_[0]->{ssl} ? 1 : 0; }

=head2 C<< $self->prefer_ssl >>

Should prefer SSL if possible.

=cut

sub prefer_ssl { return $_[0]->{__hash}->{prefer_ssl} // $LJ::USE_HTTPS_EVERYWHERE; }

=head2 C<< $self->no_cache >>

Return whether we should prevent caching or not.

=cut
sub no_cache { return $_[0]->{__hash}->{no_cache} || 0; }

=head2 C<< $self->subpatterns >>

Return the regex matches.

=cut

sub subpatterns {
    return $_[0]->{subpatterns};
}

=head2 C<< $self->username >>

Username

=cut

sub username { return $_[0]->{username}; }

=head1 AUTHOR

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
