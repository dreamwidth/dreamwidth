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

use strict;
package DW::Captcha;

use LJ::ModuleLoader;

my @CLASSES = LJ::ModuleLoader->module_subclasses( "DW::Captcha" );

my %impl2class;
foreach my $class ( @CLASSES ) {
    eval "use $class";
    die "Error loading class '$class': $@" if $@;
    $impl2class{lc $class->name} = $class;
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
    my $impl = $LJ::CAPTCHA_TYPES{delete $opts{want} || ""} || "";
    my $subclass = $impl2class{$impl};
    $subclass = $impl2class{$LJ::CAPTCHA_TYPES{$LJ::DEFAULT_CAPTCHA_TYPE}}
        unless $subclass && $subclass->site_enabled;

    my $self = bless {
        page => $page,
    }, $subclass;

    $self->_init_opts( %opts );

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

=cut

# must be implemented by subclasses
sub form_fields { qw() }

sub site_enabled { return LJ::is_enabled( 'captcha' ) && $_[0]->_implementation_enabled ? 1 : 0 }

# must be implemented by subclasses
sub _implementation_enabled { return 1; }


sub print {
    my $self = $_[0];
    return "" unless $self->enabled;

    my $ret = "<div class='captcha'>";
    $ret .= $self->_print;
    $ret .= "<p style='clear:both'>" . LJ::Lang::ml( 'captcha.accessibility.contact', { email => $LJ::SUPPORT_EMAIL } ) . "</p>";
    $ret .= "</div>";

    return $ret;
}

# must be implemented by subclasses
sub _print { return ""; }

sub validate {
    my ( $self, %opts ) = @_;

    # if disabled, then it's always valid to allow the post to go through
    return 1 unless $self->enabled;

    $self->_init_opts( %opts );

    my $err_ref = $opts{err_ref};

    # error catching for undefined page
    my $pageref = $self->page // '';
    # captcha type, page captcha appeared on
    my $stat_tags = [ (ref $self)->name, "page:$pageref" ];
    if ( $self->challenge && $self->_validate ) {
        DW::Stats::increment( "dw.captcha.success", 1, $stat_tags );
        return 1;
    }

    DW::Stats::increment( "dw.captcha.failure", 1, $stat_tags );
    $$err_ref = LJ::Lang::ml( 'captcha.invalid' );

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

# internal method. Used to initialize the challenge and response fields
# must be implemented by subclasses
sub _init_opts {
    my ( $self, %opts ) = @_;

    # do something
}

sub page      { return $_[0]->{page} }
sub challenge { return $_[0]->{challenge} }
sub response  { return $_[0]->{response} }


1;
