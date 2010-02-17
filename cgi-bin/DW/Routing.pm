#!/usr/bin/perl
#
# DW::Routing
#
# Module to allow calling non-BML controller/views.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Routing;
use strict;

use LJ::ModuleLoader;
use DW::Template;
use JSON;
use DW::Request;

our %string_choices;
our %regex_choices = (
    app  => [],
    ssl  => [],
    user => []
);

my $default_content_types = {
    'html' => "text/html; charset=utf-8",
    'json' => "application/json; charset=utf-8",
};

LJ::ModuleLoader->require_subclasses( "DW::Controller" );

=head1 NAME

DW::Routing - Module to allow calling non-BML controller/views.

=head1 SYNOPSIS

=head1 Page Call API

=head2 C<< $class->call( $r, %opts ) >>

=cut

sub call {
    my $class = shift;
    my $call_opts = $class->get_call_opts(@_);

    return $class->call_hash( $call_opts ) if defined $call_opts;
    return undef;
}

=head2 C<< $class->get_call_opts( $r, %opts ) >>

=cut

sub get_call_opts {
    my ( $class, %opts ) = @_;
    my $r = DW::Request->get;

    my ( $uri, $format ) = ( $r->uri, undef );
    ( $uri, $format ) = ( $1, $2 )
        if $uri =~ m/^(.+?)\.([a-z]+)$/;

    # add more data to the options hash, we'll need it
    $opts{role} ||= $opts{ssl} ? 'ssl' : ( $opts{username} ? 'user' : 'app' );
    $opts{uri}    = $uri;
    $opts{format} = $format;

    # we construct this object as an easy way to get options later, it gives
    # us accessors.  FIXME: this should be a separate class, not DW::Routing.
    my $call_opts = bless( \%opts, $class );

    # try the string options first as they're fast
    my $hash = $opts{__hash} = $string_choices{$opts{role} . $uri};
    return $call_opts if defined $hash;

    # try the regex choices next
    # FIXME: this should be a dynamically sorting array so the most used items float to the top
    # for now it doesn't matter so much but eventually when everything is in the routing table
    # that will have to be done
    my @args;
    foreach $hash ( @{ $regex_choices{$opts{role}} } ) {
        if ( ( @args = $uri =~ $hash->{regex} ) ) {
            $opts{__hash} = $hash;
            $opts{subpatterns} = \@args;
            return $call_opts;
        }
    }

    # failed to find anything so fall through
    return undef;
}

=head2 C<< $class->call_hash( $class, $call_opts ) >>

Calls the raw hash.

=cut

sub call_hash {
    my ( $class, $opts ) = @_;
    my $r = DW::Request->get;

    my $hash = $opts->{__hash};
    return undef unless $hash && $hash->{sub};

    $r->pnote(routing_opts => $opts);
    return $r->call_response_handler( \&_call_hash );
}

=head2 C<< $class->_call_hash() >>

Perl Response Handler for call_hash

=cut

sub _call_hash {
    my $r = DW::Request->get;
    my $opts = $r->pnote('routing_opts');
    my $hash = $opts->{__hash};

    $opts->{format} ||= $hash->{format};

    my $format = $opts->{format};
    $r->content_type( $default_content_types->{$format} )
        if $default_content_types->{$format};

    # try to call the handler that actually does the content creation; it will
    # return either a string (valid result), or a number (HTTP code), or undef
    # means there was an error of some sort
    my $ret = eval { return $hash->{sub}->( $opts ) };
    return $ret unless $@;

    # here down is simply error handling for whatever the handler sub above
    # might have died with
    my $msg = $@;

    my $err = LJ::errobj( $msg )
        or die "LJ::errobj didn't return anything.";
    $err->log;

    # JSON error rendering
    if ( $format eq 'json' ) {
        my $text = $LJ::MSG_ERROR || "Sorry, there was a problem.";
        my $remote = LJ::get_remote();
        $text = "$msg" if ( $remote && $remote->show_raw_errors ) || $LJ::IS_DEV_SERVER;

        $r->status( 500 );
        $r->print(objToJson( { error => $text } ));
        return $r->OK;

    # default error rendering
    } else {
        $msg = $err->as_html;

        chomp $msg;
        $msg .= " \@ $LJ::SERVER_NAME" if $LJ::SERVER_NAME;
        warn "$msg\n";

        $r->status( 500 );
        my $text = $LJ::MSG_ERROR || "Sorry, there was a problem.";
        my $remote = LJ::get_remote();
        $text = "<b>[Error: $msg]</b>" if ( $remote && $remote->show_raw_errors ) || $LJ::IS_DEV_SERVER;
        return DW::Template->render_string( $text, { status=>500, content_type=>'text/html' } );
    }
}

sub _static_helper {
    my $r = DW::Request->get;
    return $r->NOT_FOUND unless $_[0]->format eq 'html';
    return  DW::Template->render_template( $_[0]->args );
}

=head1 Registration API

=head2 C<< $class->register_static($string, $filename, $opts) >>

Static page helper.

=over

=item string - path

=item filename - template filename

=item Opts:

=over

=item ssl - If this sub should run for ssl.

=item app - 1 if app

=item user - 1 if user

=back

=back

=cut

sub register_static {
    my ( $class, $string, $fn, %opts ) = @_;

    $opts{args} = $fn;
    $class->register_string( $string, \&_static_helper, %opts );
}

=head2 C<< $class->register_string($string, $sub, $opts) >>

=over

=item string - path

=item sub - sub

=item Opts:

=over

=item ssl - If this sub should run for ssl.

=item args - passed verbatim to sub.

=item app - 1 if app

=item user - 1 if user

=back

=back

=cut

sub register_string {
    my ( $class, $string, $sub, %opts ) = @_;

    $opts{app} = 1 if ! defined $opts{app} && ! $opts{user};
    my $hash = {
        args   => $opts{args},
        sub    => $sub,
        ssl    => $opts{ssl} || 0,
        app    => $opts{app} || 0,
        user   => $opts{user} || 0,
        format => $opts{format} || 'html',
    };
    $string_choices{'app'  . $string} = $hash if $hash->{app};
    $string_choices{'ssl'  . $string} = $hash if $hash->{ssl};
    $string_choices{'user' . $string} = $hash if $hash->{user};
}

=head2 C<< $class->register_regex($regex, $sub, $opts) >>

=over

=item regex

=item sub - sub

=over

=item Opts:

=over

=item ssl - If this sub should run for ssl.

=item args - passed verbatim to sub.

=item app - 1 if app

=item user - 1 if user

=back

=back

=cut
sub register_regex {
    my ( $class, $regex, $sub, %opts ) = @_;

    $opts{app} = 1 if ! defined $opts{app} && !$opts{user};
    my $hash = {
        regex  => $regex,
        args   => $opts{args},
        sub    => $sub,
        ssl    => $opts{ssl} || 0,
        app    => $opts{app} || 0,
        user   => $opts{user} || 0,
        format => $opts{format} || 'html',
    };
    push @{$regex_choices{app}}, $hash if $hash->{app};
    push @{$regex_choices{ssl}}, $hash if $hash->{ssl};
    push @{$regex_choices{user}}, $hash if $hash->{user};
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

=head2 C<< $self->role >>

Current mode: 'app' or 'user' or 'ssl'

=cut

sub role { return $_[0]->{role}; }

=head2 C<< $self->ssl >>

Is SSL request?

=cut

sub ssl { return $_[0]->{role} eq 'ssl' ? 1 : 0; }

=head2 C<< $self->subpatterns >>

Return the regex matches.

=cut

sub subpatterns { return $_[0]->{subpatterns}; }

=head2 C<< $self->username >>

Username

=cut

sub username { return $_[0]->{username}; }

=head1 AUTHOR

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
