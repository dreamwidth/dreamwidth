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
# Copyright (c) 2009-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Routing;
use strict;

use LJ::ModuleLoader;
use DW::Template;
use LJ::JSON;
use DW::Request;
use DW::Routing::CallInfo;
use Carp qw/croak/;

# IMPORTANT!
#
# If we change the internal representation here, the code in
# bin/dev/lookup-routing must also be updated.
#
# Thank you.
#
our %string_choices;
our %regex_choices = (
    app  => [],
    user => []
);

our $T_TESTING_ERRORS;

my $default_content_types = {
    'html' => "text/html; charset=utf-8",
    'json' => "application/json; charset=utf-8",
    'js' => "application/javascript; charset=utf-8",
    'plain' => "text/plain; charset=utf-8",
    'png' => "image/png",
    'atom' => "application/atom+xml; charset=utf-8",
};

LJ::ModuleLoader->require_subclasses( "DW::Controller" )
    unless $DW::Routing::DONT_LOAD;  # for testing

=head1 NAME

DW::Routing - Module to allow calling non-BML controller/views.

=head1 Page Call API

=head2 C<< $class->call( $r, %opts ) >>

Valid options:

=over

=item uri - explicitly override the uri
=item role - explicitly define the role
=item username - define the username, implies username role
=item ssl - this is a SSL call

=back

This method should be directly returned by the caller if defined.

=cut

sub call {
    my $class = shift;
    my $call_opts = $class->get_call_opts(@_);

    return $class->call_hash( $call_opts ) if defined $call_opts;
    return undef;
}

=head2 C<< $class->get_call_opts( $r, %opts ) >>

Valid options:

=over

=item uri - explicitly override the uri
=item role - explicitly define the role
=item username - define the username, implies username role
=item ssl - this is a SSL call

=back

Returns a call_opts hash, or undefined.

=cut

sub get_call_opts {
    my ( $class, %opts ) = @_;
    my $r = DW::Request->get;

    my $uri = $opts{uri} ||  $r->uri;
    my $format = undef;
    ( $uri, $format ) = ( $1, $2 )
        if $uri =~ m/^(.+?)\.([a-z]+)$/;

    # add more data to the options hash, we'll need it
    $opts{role} ||= $opts{username} ? 'user' : 'app';
    $opts{uri}    = $uri;
    $opts{format} = $format;

    # we construct this object as an easy way to get options later, it gives
    # us accessors.
    my $call_opts = DW::Routing::CallInfo->new( \%opts );

    my $hash;
    my $role = $call_opts->role;

    # try the string options first as they're fast
    $hash = $string_choices{$role . $uri};
    if ( defined $hash ) {
        $call_opts->init_call_opts( $hash );
        return $call_opts;
    }

    # try the regex choices next
    # FIXME: this should be a dynamically sorting array so the most used items float to the top
    # for now it doesn't matter so much but eventually when everything is in the routing table
    # that will have to be done
    my @args;
    foreach $hash ( @{ $regex_choices{$call_opts->role} } ) {
        if ( ( @args = $uri =~ $hash->{regex} ) ) {
            $call_opts->init_call_opts( $hash, \@args );
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

    my $hash = $opts->call_opts;
    return undef unless $hash && $hash->{sub};

    $r->pnote(routing_opts => $opts);
    return $r->call_response_handler( \&_call_hash );
}

# INTERNAL METHOD: no POD
# Perl Response Handler for call_hash
sub _call_hash {
    my $r = DW::Request->get;
    my $opts = $r->pnote('routing_opts');

    $opts->prepare_for_call;

    # check method
    my $method = uc( $r->method );
    return $r->HTTP_METHOD_NOT_ALLOWED unless $opts->method_valid( $method );

    my $format = $opts->format;
    # check for format validity
    return $r->NOT_FOUND unless $opts->format_valid;

    # prefer SSL if wanted and possible
    #  cannot do SSL on userspace, cannot do SSL if it's not set up
    #  cannot do the redirect safely for non-GET/HEAD requests.
    return $r->redirect( LJ::create_url($r->uri, keep_args => 1, ssl => 1) )
        if $opts->prefer_ssl && $LJ::USE_SSL && $opts->role eq 'app' &&
            ! $opts->ssl && ( $r->method eq 'GET' || $r->method eq 'HEAD' );

    # apply default content type if it exists
    $r->content_type( $default_content_types->{$format} )
        if $default_content_types->{$format};

    # try to call the handler that actually does the content creation; it will
    # return either a number (HTTP code), or undef
    # means there was an error of some sort
    my $ret = eval { $opts->call };
    return $ret unless $@;

    # here down is simply error handling for whatever the handler sub above
    # might have died with
    my $msg = $@;

    my $err = LJ::errobj( $msg )
        or die "LJ::errobj didn't return anything.";
    unless ( $T_TESTING_ERRORS ) {
        $err->log;
        warn $msg;
    }

    # JSON error rendering
    if ( $format eq 'json' ) {
        $msg = $err->as_string;
        chomp $msg;

        my $text = $LJ::MSG_ERROR || "Sorry, there was a problem.";
        my $remote = LJ::get_remote();

        $text = "$msg" if ( $remote && $remote->show_raw_errors ) || $LJ::IS_DEV_SERVER;

        $r->status( 500 );
        $r->print(to_json( { error => $text } ));
        return $r->OK;
    # default error rendering
    } elsif ( $format eq "html" ) {
        $msg = $err->as_html;
        chomp $msg;

        $msg .= " \@ $LJ::SERVER_NAME" if $LJ::SERVER_NAME;

        $r->status( 500 );
        $r->content_type( $default_content_types->{html} );

        my $text = $LJ::MSG_ERROR || "Sorry, there was a problem.";
        my $remote = LJ::get_remote();
        $text = "<b>[Error: $msg]</b>" if ( $remote && $remote->show_raw_errors ) || $LJ::IS_DEV_SERVER;
        $opts->{no_sitescheme} = 1 if $T_TESTING_ERRORS;

        $ret = eval { return DW::Template->render_string( $text, $opts ); };
        return $ret unless $@;

        my $msg2 = $@;
        my $err2 = LJ::errobj( $msg2 )
            or die "LJ::errobj didn't return anything.";
        unless ( $T_TESTING_ERRORS ) {
            $err2->log;
            warn $msg2;
        }

        if ( ( $remote && $remote->show_raw_errors ) || $LJ::IS_DEV_SERVER ) {
            $msg2 = $err2->as_html;
            $msg2 .= " \@ $LJ::SERVER_NAME" if $LJ::SERVER_NAME;

            $text .= "\n<br/><br/>Additionally, while trying to render this error page:";
            $text .= "\n<b>[Error 2: $msg2]</b>";
        }

        $r->status( 500 );
        $r->content_type( 'text/html' );
        $r->print( $text );
        return $r->OK;
    } else {
        $msg = $err->as_string;
        chomp $msg;

        $msg .= " \@ $LJ::SERVER_NAME" if $LJ::SERVER_NAME;

        my $text = $LJ::MSG_ERROR || "Sorry, there was a problem.";
        my $remote = LJ::get_remote();
        $text = "Error: $msg" if ( $remote && $remote->show_raw_errors ) || $LJ::IS_DEV_SERVER;

        $r->status( 500 );
        $r->content_type( 'text/plain' );
        $r->print( $text );

        return $r->OK;
    }
}

# INTERNAL METHOD: no POD
# controller sub for register_static
sub _static_helper {
    my $r = DW::Request->get;
    return DW::Template->render_template( $_[0]->args );
}

# INTERNAL METHOD: no POD
# controller sub for register_redirect
sub _redirect_helper {
    my $r = DW::Request->get;
    my $data = $_[0]->args;

    if ( $data->{full_uri} ) {
        return $r->redirect( $data->{dest} );
    } else {
        return $r->redirect( LJ::create_url( $data->{dest}, keep_args => $data->{keep_args} ) );
    }
}

=head1 Registration API

=head2 C<< $class->register_static( $string, $filename, %opts ) >>

Static page helper.

=over

=item string - path

=item filename - template filename

=item Opts ( see register_string )

=back

=cut

sub register_static {
    my ( $class, $string, $fn, %opts ) = @_;

    $opts{args} = $fn;
    $class->register_string( $string, \&_static_helper, %opts );
}

=head2 C<< $class->register_string( $string, $sub, %opts ) >>

=over

=item string - path

=item sub - sub

=item Opts:

=over

=item args - passed verbatim to sub.

=item app - Serve this in app-space.

=item user - Serve this in journalspace.

=item format - What format should be used, defaults to HTML

=item formats - An array of possible formats, or 1 to allow everything.

=item prefer_ssl - Auto-redirect to SSL version if possible.

=back

=back

=cut

sub register_string {
    my ( $class, $string, $sub, %opts ) = @_;

    my $hash = _apply_defaults( \%opts, {
        sub    => $sub,
    });

    $string_choices{'app'  . $string} = $hash if $hash->{app};
    $string_choices{'user' . $string} = $hash if $hash->{user};

    if ( $string =~ m!(^(.*)/)index$! && ! exists $opts{no_redirects} ) {
        my %opts = (
            app => $hash->{app},
            user => $hash->{user},
            formats => $hash->{formats},
            format => $hash->{format},
            no_redirects => 1,
            keep_args => 1,
        );
        $class->register_redirect( $2, $1, %opts ) if $2;
        $string_choices{'app'  . $1} = $hash if $hash->{app};
        $string_choices{'user' . $1} = $hash if $hash->{user};
    }
}

=head2 C<< $class->register_redirect( $string, $dest, %opts ) >>

Redirect helper.

=over

=item string - path

=item dest - destination

=item Opts ( see register_string )

=over

=item keep_args - Persist GET arguments over redirect ( same as the keep_args argument to create_url ).

=item full_uri - A full URI ( http://...../foo v.s. /foo )

=back

=back

=cut

sub register_redirect {
    my ( $class, $string, $dest, %opts ) = @_;

    my $args = { dest => $dest };
    $args->{keep_args} = delete $opts{keep_args} || 0;
    $args->{full_uri} = delete $opts{full_uri} || 0;

    $opts{args} = $args;
    $class->register_string( $string, \&_redirect_helper, %opts );
}

=head2 C<< $class->register_regex( $regex, $sub, %opts ) >>

=over

=item regex

=item sub - sub

=item Opts ( see register_string )

=back

=cut

sub register_regex {
    my ( $class, $regex, $sub, %opts ) = @_;

    my $hash = _apply_defaults( \%opts, {
        regex  => $regex,
        sub    => $sub,
    });
    push @{$regex_choices{app}}, $hash if $hash->{app};
    push @{$regex_choices{user}}, $hash if $hash->{user};
}

=head2 C<< $class->register_rpc( $name, $sub, %opts ) >>

Register a RPC call

=over

=item name - RPC call name

=item sub - sub

=item Opts ( see register_string )

=back

=cut

sub register_rpc {
    my ( $class, $string, $sub, %opts ) = @_;

    delete $opts{app};
    delete $opts{user};
    $class->register_string( "/__rpc_$string", $sub, app => 1, user => 1, %opts );

    # FIXME: per Bug 4900, this line is temporary and can go away as soon as
    #  all the javascript is updated
    $class->register_regex( qr!^/[^/]+/\Q__rpc_$string\E$!, $sub, user => 1, %opts );
}


# internal method, intentionally no POD
# applies default for opts and hash
sub _apply_defaults {
    my ( $opts, $hash ) = @_;

    $hash ||= {};
    $opts->{app} = 1 if ! defined $opts->{app} && !$opts->{user};
    $hash->{args} = $opts->{args};
    $hash->{app} = $opts->{app} || 0;
    $hash->{user} = $opts->{user} || 0;
    $hash->{format} = $opts->{format} || 'html';
    $hash->{prefer_ssl} = $opts->{prefer_ssl} || 0;


    my $formats = $opts->{formats} || [ $hash->{format} ];
    $formats = { map { ( $_, 1 ) } @$formats } if ( ref($formats) eq 'ARRAY' );

    $hash->{formats} = $formats;
    $hash->{methods} = $opts->{methods} || { GET => 1, POST => 1, HEAD => 1 };

    croak "Cannot register with prefer_ssl without app role" if ( $hash->{prefer_ssl} && ! $hash->{app} );

    return $hash;
}

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
