#!/usr/bin/perl
#
# DW::Captcha
#
# This module handles CAPTCHA throughout the site
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

=head1 NAME

DW::Captcha - This module handles CAPTCHA throughout the site

=head1 SYNOPSIS

Here's the simplest method:

    # print out the captcha form fields on a particular page
    my $captcha = DW::Captcha->new( $page );
    if ( $captcha->enabled ) {
        $captcha->print;
    }

    # elsewhere, process the post
    if ( $r->did_post ) {
        my $captcha = DW::Captcha->new( $page, %{$r->post_args} );

        my $captcha_error;
        push @errors, $captcha_error unless $captcha->validate( err_ref => \$captcha_error );
    }


When using in conjunction with LJ::Widget subclasses, you can just specify the form field names and let the widget handle it:

    LJ::Widget->use_specific_form_fields( post => \%POST, widget => "...", fields => [ DW::Captcha->form_fields ] )
        if DW::Captcha->enabled( 'create' );


In a controller+template pair, do this to generate the captcha HTML:

    $vars->{print_captcha} = sub { return DW::Captcha->new( $_[0] )->print; }
    # ... other vars go here ...
    return DW::Template->render_template( 'path/to/template.tt', $vars );

then, in template path/to/template.tt:

    [% print_captcha( 'page name' ) %]

or

    [% print_captcha() %]

=cut

package DW::Captcha;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::MemCache;
use LJ::ModuleLoader;
use LJ::UniqCookie;

my @CLASSES = LJ::ModuleLoader->module_subclasses("DW::Captcha");

my %impl2class;
foreach my $class (@CLASSES) {
    eval "use $class";
    die "Error loading class '$class': $@" if $@;
    $impl2class{ lc $class->name } = $class;
}

# class methods

=head1 API

=head2 C<< DW::Captcha->new( $page, %opts ) >>

Arguments:

=over

=item page - the page we're going to display this CAPTCHA on

=item a hash of additional options, including the request/response from a form post

=back

=cut

sub new {
    my ( $class, $page, %opts ) = @_;

    # yes, I really do want to do this rather than $impl{...||$LJ::DEFAULT_CAPTCHA...}
    # we want to make certain that someone can't force all captchas off
    # by asking for an invalid captcha type
    my $impl     = $LJ::CAPTCHA_TYPES{ delete $opts{want} || "" } || "";
    my $subclass = $impl2class{$impl};
    $subclass = $impl2class{ $LJ::CAPTCHA_TYPES{$LJ::DEFAULT_CAPTCHA_TYPE} }
        unless $subclass && $subclass->site_enabled;

    my $self = bless { page => $page, }, $subclass;

    $self->_init_opts(%opts);

    return $self;
}

# must be implemented by subclasses

=head2 C<< $class->name >>

The name used to refer to this CAPTCHA implementation.

=cut

sub name { return ""; }

# object methods

=head2 C<< $captcha->form_fields >>

Returns a list of the form fields expected by the CAPTCHA implementation.

=head2 C<< $captcha->site_enabled >>

Whether CAPTCHA is enabled site-wide. (Specific pages may have CAPTCHA disabled)

=head2 C<< $captcha->print >>

Print the CAPTCHA form fields.

=head2 C<< $captcha->validate( %opts ) >>

Return whether the response for this CAPTCHA was valid.

Arguments:

=over

=item opts - a hash of additional options, including the request/response from a form post
and an error reference (err_ref) which may contain additional information in case
the validation failed

=back

=head2 C<< $captcha->enabled( $page ) >>

Whether this CAPTCHA implementation is enabled on this particular page
(or sitewide if this captcha instance isn't tied to a specific page)

Arguments:

=over

=item page - Optional. A specific page to check

=back

=head2 C<< $captcha->page >>

Return the page that this CAPTCHA instance is going to be used with

=head2 C<< $captcha->challenge >>

Challenge text, provided by the CAPTCHA implementation

=head2 C<< $captcha->response >>

User-provided response text

=head2 C<< $captcha->has_response >>

Tests for existence of user-provided response text, returns true/false

=cut

# must be implemented by subclasses
sub form_fields { qw() }

sub site_enabled { return LJ::is_enabled('captcha') && $_[0]->_implementation_enabled ? 1 : 0 }

# must be implemented by subclasses
sub _implementation_enabled { return 1; }

sub print {
    my $self = $_[0];
    return "" unless $self->enabled;

    my $ret = "<div class='captcha'>";
    $ret .= $self->_print;
    $ret .= "<p style='clear:both'>"
        . LJ::Lang::ml( 'captcha.accessibility.contact', { email => $LJ::SUPPORT_EMAIL } ) . "</p>";
    $ret .= "</div>";

    return $ret;
}

# must be implemented by subclasses
sub _print { return ""; }

sub validate {
    my ( $self, %opts ) = @_;

    # if disabled, then it's always valid to allow the post to go through
    return 1 unless $self->enabled;

    $self->_init_opts(%opts);

    my $err_ref = $opts{err_ref};

    # error catching for undefined page
    my $pageref = $self->page // '';

    # captcha type, page captcha appeared on
    my $stat_tags = [ ( ref $self )->name, "page:$pageref" ];
    if ( $self->challenge && $self->_validate ) {
        DW::Stats::increment( "dw.captcha.success", 1, $stat_tags );
        return 1;
    }

    DW::Stats::increment( "dw.captcha.failure", 1, $stat_tags );
    $$err_ref = LJ::Lang::ml('captcha.invalid');

    return 0;
}

# must be implemented by subclasses
sub _validate { return 0; }

sub enabled {
    my $page;
    $page = $_[0]->page if ref $_[0];
    $page ||= $_[1];

    return $page
        ? $_[0]->site_enabled() && $LJ::CAPTCHA_FOR{$page}
        : $_[0]->site_enabled();
}

# Integrated with our controller system to determine whether a user should
# or shouldn't receive a captcha in this place.
#
# Returns whether or not we believe the user should receive a captcha at
# this point based on request counting. Note, you should probably not use
# this on things where you _definitely_ want a captcha, like creating
# an account or something.
sub should_captcha_view {
    my ( $class, $remote ) = @_;
    my $r = DW::Request->get;

    # Return unless we're enabled
    return 0 unless $LJ::CAPTCHA_HCAPTCHA_SITEKEY;

    # If we're completing a captcha, no captcha
    return 0 if $r->uri =~ m!^/captcha!;

    # If the user is logged in, no captcha
    return 0 if $remote;

    # If the path matches the bypass regex, no captcha
    if ($LJ::CAPTCHA_BYPASS_REGEX) {
        return 0 if $r->uri =~ $LJ::CAPTCHA_BYPASS_REGEX;
    }

    # If the user is on a trusted IP range, no captcha
    my ( $mckey, $ip ) = _captcha_mckey();
    if ( my $matcher = $LJ::SHOULD_CAPTCHA_IP ) {
        return 0 unless $matcher->($ip);
    }

    # Get our captcha information -- no information means that the user has not
    # passed a captcha. If we have information, then they *have* at some point.
    my $info_raw = LJ::MemCache::get($mckey);
    unless ($info_raw) {

        # Let's see if this is a repeat offender who is spamming requests at us
        # and hitting a bunch of 302s -- in which case, temp ban
        my $ip    = $r->get_remote_ip;
        my $mckey = "cct:$ip";
        my ( $last_seen_ts, $count ) = split( /:/, LJ::MemCache::get($mckey) // "0:0" );
        if ( $last_seen_ts > 0 ) {

            # Subtract out
            my $intervals = int( ( time() - $last_seen_ts ) / $LJ::CAPTCHA_FRAUD_INTERVAL_SECS );
            if ( $intervals > 1 ) {
                $count -= $LJ::CAPTCHA_FRAUD_FORGIVENESS_AMOUNT * $intervals;
                $count = 0
                    if $count < 0;
            }
        }

        # Set the counter
        $log->debug( $ip, ' has seen ', $count + 1, ' captcha requests.' );
        LJ::MemCache::set(
            $mckey,
            join( ':', time(), $count + 1 ),
            $LJ::CAPTCHA_FRAUD_INTERVAL_SECS * $LJ::CAPTCHA_FRAUD_LIMIT
        );

        # Now the trigger interval, if it's over, sysban this IP but just carry
        # on with rendering this page (simpler)
        if ( $count >= $LJ::CAPTCHA_FRAUD_LIMIT ) {
            $log->info( 'Banning ', $ip, ' for exceeding captcha fraud threshold.' );
            LJ::Sysban::tempban_create( ip => $ip, $LJ::CAPTCHA_FRAUD_SYSBAN_SECS );
        }

        return 1;
    }

    # This is a poor rate limit system but it might be good enough
    # for us, it's also poorly documented sorry
    my ( $first_req_ts, $last_req_ts, $remaining ) = map { $_ + 0 } split( /:/, $info_raw );

    # If the first request is too long ago, then re-captcha
    if ( ( time() - $first_req_ts ) > $LJ::CAPTCHA_RETEST_INTERVAL_SECS ) {
        $log->info( $mckey, ' has exceeded the retest interval, issuing captcha.' );
        return 1;
    }

    # First, refresh remaining according to time since last request
    my $delta_intervals = ( time() - $last_req_ts ) / $LJ::CAPTCHA_REFILL_INTERVAL_SECS;
    if ( $delta_intervals > 1 ) {

        # Only add more if we've waited at least an interval
        $remaining += int( $delta_intervals * $LJ::CAPTCHA_REFILL_AMOUNT );
        $remaining = $LJ::CAPTCHA_MAX_REMAINING
            if $remaining > $LJ::CAPTCHA_MAX_REMAINING;
        $last_req_ts = time();
    }

    # If we are out of requests, retest
    if ( $remaining <= 0 ) {
        $log->info( $mckey, ' is out of requests by usage, retesting.' );
        return 1;
    }

    # Things look good, so let's allow this to continue but update remaining
    LJ::MemCache::set( $mckey, join( ':', $first_req_ts, $last_req_ts, $remaining - 1 ) );
    return 0;
}

# Called when the captcha page has a successful captcha.
sub record_success {

    # Return unless we're enabled
    return 0 unless $LJ::CAPTCHA_HCAPTCHA_SITEKEY;

    my $mckey = _captcha_mckey();
    $log->debug( 'Captcha success for: ', $mckey );
    LJ::MemCache::set( $mckey, join( ':', time(), time(), $LJ::CAPTCHA_INITIAL_REMAINING ) );
}

# Reset the captcha counter, so the user starts getting them
# again. Mostly used for debugging.
sub reset_captcha {
    my $mckey = _captcha_mckey();
    $log->debug( 'Resetting captcha for: ', $mckey );
    LJ::MemCache::delete($mckey);
}

# Construct a redirect URL that will take us to get captchaed and
# then back to whatever page we're on now
sub redirect_url {
    my $r = DW::Request->get;

    my $uri = $r->uri;
    if ( my $qs = $r->query_string ) {
        $uri .= '?' . $qs;
    }

    my $host = $r->host;
    $uri = LJ::eurl( $host ? "https://$host$uri" : $uri );

    return "$LJ::SITEROOT/captcha?returnto=$uri";
}

sub _captcha_mckey {
    my $r          = DW::Request->get;
    my $ip         = $r->get_remote_ip;
    my $ip_trimmed = join( '.', ( split( /\./, $ip ) )[ 0 .. 2 ] ) . '.0';
    my $uniq       = LJ::UniqCookie->current_uniq;
    my $mckey      = "$uniq:$ip_trimmed";
    return wantarray ? ( $mckey, $ip ) : $mckey;
}

# internal method. Used to initialize the challenge and response fields
# must be implemented by subclasses
sub _init_opts {
    my ( $self, %opts ) = @_;

    # do something
}

sub page      { return $_[0]->{page} }
sub challenge { return $_[0]->{challenge} }
sub response  { return $_[0]->{response} }

# return true if the captcha has a valid response
# (use this instead of "if response" since correct response might be 0)
sub has_response {
    my ($self) = @_;
    my $resp = $self->response;

    # this should only be false if the response is empty or zero characters
    return defined $resp && length $resp ? 1 : 0;
}

1;
