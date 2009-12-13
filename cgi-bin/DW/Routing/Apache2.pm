#!/usr/bin/perl
#
# DW::Routing::Apache2
#
# Module to allow calling non-BML controller/views.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Routing::Apache2;
use strict;

use LJ::ModuleLoader;
use DW::Template::Apache2;
use JSON;

# FIXME: This shouldn't depend on Apache, but I'm using it here as I need to do a few calls
#        that aren't supported by DW::Request, as well as it's needed in DW::Template.
use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED
                       HTTP_MOVED_PERMANENTLY HTTP_MOVED_TEMPORARILY
                       M_TRACE M_OPTIONS /;

my %string_choices;
my %regex_choices = (
    app  => [],
    ssl  => [],
    user => []
);

my $default_content_types = {
    'html' => "text/html; charset=utf-8",
    'json' => "application/json; charset=utf-8",
};

LJ::ModuleLoader->autouse_subclasses( "DW::Controller" );

=head1 NAME

DW::Routing::Apache2 - Module to allow calling non-BML controller/views.

=head1 SYNOPSIS

=head1 Page Call API

=head2 C<< $class->call( $r, %opts ) >>

=cut

sub call {
    my ( $class, $r, %opts ) = @_;

    my ( $uri, $format ) = ( $r->uri, undef );
    ( $uri, $format ) = ( $1, $2 )
        if $uri =~ m/^(.+?)\.([a-z]+)$/;

    # add more data to the options hash, we'll need it
    $opts{mode}   = $opts{ssl} ? 'ssl' : ( $opts{username} ? 'user' : 'app' );
    $opts{uri}    = $uri;
    $opts{format} = $format;
    $opts{__r}    = $r;

    # we construct this object as an easy way to get options later, it gives
    # us accessors.  FIXME: this should be a separate class, not DW::Routing.
    my $call_opts = bless( \%opts, $class );

    # try the string options first as they're fast
    my $hash = $opts{__hash} = $string_choices{$opts{mode} . $uri};
    return $class->call_hash( $call_opts ) if defined $hash;

    # try the regex choices next
    # FIXME: this should be a dynamically sorting array so the most used items float to the top
    # for now it doesn't matter so much but eventually when everything is in the routing table
    # that will have to be done
    my @args;
    foreach $hash ( @{ $regex_choices{$opts{mode}} } ) {
        if ( ( @args = $uri =~ $hash->{regex} ) ) {
            $opts{__hash} = $hash;
            $opts{subpatterns} = \@args;
            return $class->call_hash( $call_opts );
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

    my $hash = $opts->{__hash};
    return undef unless $hash && $hash->{sub} && $opts->{__r};

    $opts->{__r}->handler( 'perl-script' );
    $opts->{__r}->pnotes->{routing_opts} = $opts;
    $opts->{__r}->push_handlers( PerlResponseHandler => \&_call_hash );

    return OK;
}

=head2 C<< $class->_call_hash( $r ) >>

Perl Response Handler for call_hash

=cut

sub _call_hash {
    my ( $r ) = @_;
    my $opts = $r->pnotes->{routing_opts};
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
        return OK;

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
        return DW::Template::Apache2->render_string( $r, $text, { status=>500, content_type=>'text/html' } );
    }
}

sub _static_helper {
    return NOT_FOUND unless $_[0]->format eq 'html';
    return $_[0]->render_template( $_[0]->args );
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

=head2 C<< $self->render_template( $template, $data, $extra ) >>

Wrap stuff in the sitescheme.

Helper so the controller doesn't need to dig out the Apache request.

=cut

sub render_template {
    my $self = shift;
    return DW::Template::Apache2->render_template( $self->{__r}, @_ );
}

=head2 C<< $self->render_cached_template( $key, $template, $subref, $extra ) >>

Wrap stuff in the sitescheme.

Helper so the controller doesn't need to dig out the Apache request.

=cut

sub render_cached_template {
    my $self = shift;
    return DW::Template::Apache2->render_cached_template( $self->{__r}, @_ );
}

=head2 C<< $self->args >>

Return the arguments passed to the register call.

=cut

sub args { return $_[0]->{__hash}->{args}; }

=head2 C<< $self->format >>

Return the format.

=cut

sub format { return $_[0]->{format}; }

=head2 C<< $self->mode >>

Current mode: 'app' or 'user' or 'ssl'

=cut

sub mode { return $_[0]->{mode}; }

=head2 C<< $self->ssl >>

Is SSL request?

=cut

sub ssl { return $_[0]->{mode} eq 'ssl' ? 1 : 0; }

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

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
