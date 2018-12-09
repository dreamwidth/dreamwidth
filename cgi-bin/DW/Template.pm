#!/usr/bin/perl
#
# DW::Template
#
# Template Toolkit helpers for Apache2.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Template;
use strict;
use Template;
use Template::Plugins;
use Template::Namespace::Constants;
use DW::FragmentCache;
use DW::Request;
use LJ::Directories;

=head1 NAME

DW::Template - Template Toolkit helpers for Apache2.

=head1 SYNOPSIS

=cut 

# setting this to false -- have to explicitly specify which plugins we want.
$Template::Plugins::PLUGIN_BASE = '';

my $site_constants = Template::Namespace::Constants->new({
    name        => $LJ::SITENAME,
    nameshort   => $LJ::SITENAMESHORT,
    nameabbrev  => $LJ::SITENAMEABBREV,

    company          => $LJ::SITECOMPANY,
    address          => $LJ::SITEADDRESS,
    addressline      => $LJ::SITEADDRESSLINE,

    domain      => $LJ::DOMAIN,
    domainweb   => $LJ::DOMAIN_WEB,

    help => \%LJ::HELPURL,

    email => {
        abuse => $LJ::ABUSE_EMAIL,
        coppa => $LJ::COPPA_EMAIL,
        privacy => $LJ::PRIVACY_EMAIL,
    },
});

# precreating this
my $view_engine = Template->new({
    INCLUDE_PATH => join(':', LJ::get_all_directories('views') ),
    NAMESPACE => {
        site => $site_constants,
    },
    CACHE_SIZE => $LJ::TEMPLATE_CACHE_SIZE, # this can be undef, and that means cache everything.
    STAT_TTL => $LJ::IS_DEV_SERVER ? 1 : 3600,
    PLUGINS => {
        autoformat => 'Template::Plugin::Autoformat',
        date => 'Template::Plugin::Date',
        url => 'Template::Plugin::URL',
        dw => 'DW::Template::Plugin',
        form => 'DW::Template::Plugin::FormHTML',
    },
    PRE_PROCESS => '_init.tt',
});

my $scheme_engine = Template->new({
    INCLUDE_PATH => join(':', LJ::get_all_directories('schemes') ),
    NAMESPACE => {
        site => $site_constants,
    },
    CACHE_SIZE => $LJ::TEMPLATE_CACHE_SIZE, # this can be undef, and that means cache everything.
    STAT_TTL => $LJ::IS_DEV_SERVER ? 1 : 3600,
    PLUGINS => {
        dw => 'DW::Template::Plugin',
        dw_scheme => 'DW::Template::Plugin::SiteScheme',
    },
});

=head1 API

=head2 C<< $class->template_string( $filename, $opts, $extra ) >>

Render a template to a string.

=cut

sub template_string {
    my ( $class, $filename, $opts, $extra ) = @_;
    my $r = DW::Request->get;

    $opts->{sections} = $extra;
    $opts->{sections}->{errors} = $opts->{errors};

    # now we have to save the scope and update it for this rendering
    my $oldscope = $r->note( 'ml_scope' );
    $r->note( ml_scope => ( $extra->{ml_scope} || "/$filename" ) );

    my $out;
    $view_engine->process( $filename, $opts, \$out )
        or die $view_engine->error->as_string;

    # now revert the scope if we had one
    $r->note( ml_scope => $oldscope ) if $oldscope;

    return $out;
}

=head2 C<< $class->cached_template_string( $key, $filename, $opts_subref, $cache_opts, $extra ) >>

Render a template to a string -- optionally fragment caching it.
$opts_subref returns the options for template_string.

fragment opts:

=over

=item B< lock_failed > - The text returned by this subref is returned if the lock is failed and the grace period is up.

=item B< expire > - Number of seconds the fragment is valid for

=item B< grace_period > - Number of seconds that an expired fragment could still be served if the lock is in place

=back

=cut

sub cached_template_string {
    my ($class, $key, $filename, $opts_subref, $cache_opts, $extra ) = @_;


    return DW::FragmentCache->get( $key, {
        lock_failed => $cache_opts->{lock_failed},
        expire => $cache_opts->{expire},
        grace_period => $cache_opts->{grace_period},
        render => sub {
            return $class->template_string( $filename, $opts_subref->( $_[0] ), $extra );
        }
    }, $extra);
}

=head2 C<< $class->render_cached_template( $key, $filename, $subref, $extra ) >>

Render a template inside the sitescheme or alone.

See render_template, except note that the opts hash is returned by opts_subref if it's needed.

$cache_opts can contain:

=over

=item B< no_sitescheme > == render alone

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=item B< lock_failed > = subref for lock failed.

=item B< expire > - Number of seconds the fragment is valid for

=item B< grace_period > - Number of seconds that an expired fragment could still be served if the lock is in place

=back

=cut

sub render_cached_template {
    my ($class, $key, $filename, $opts_subref, $cache_opts, $extra) = @_;

    $extra ||= {};

    my $out = $class->cached_template_string( $key, $filename, $opts_subref, $cache_opts, $extra );

    return $class->render_string( $out, $extra );
}

=head2 C<< $class->render_template( $filename, $opts, $extra ) >>

Render a template inside the sitescheme or alone.

$extra can contain:

=over

=item B< no_sitescheme > == render alone

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=back

=cut

sub render_template {
    my ( $class, $filename, $opts, $extra ) = @_;

    $extra ||= {};
    my $out = $class->template_string( $filename, $opts, $extra );

    return $class->render_string( $out, $extra );
}

=head2 C<< $class->render_template_misc( $filename, $opts, $extra ) >>

Render a template inside the sitescheme or alone.
This can also be safely called ( with some work on the other side )
from a BML context and still spit the content where required.
( Note, the "alone" bit will be ignored from BML contexts )

Can safely directly return this from either trans/Controller, internal journal page generation or (most) BML contexts.

$extra can contain:

=over

=item B< no_sitescheme > == render alone

=over

This will be ignored for 'bml' scopes.

=back

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=item B< scope > = Scope, accepts nothing, 'bml', or 'journal'

=item B< scope_data > = Depends on B< scope >

=over

=item B< bml > Hashref of scalar-refs of where to throw the sections

=item B< journal > $opts hashref passed into LJ::make_journal and beyond.

=back 

=back

=cut

# FIXME(dre): Remove this method when BML is completely dead
#   and refactor the journal scope bits up into render_template or render_string.
sub render_template_misc {
    my ( $class, $filename, $opts, $extra ) = @_;

    $extra ||= {};
    my $out = $class->template_string( $filename, $opts, $extra );

    my $scope = $extra->{scope};

    if ( $scope eq 'bml' ) {
        my $r = DW::Request->get;
        my $bml = $extra->{scope_data};

        for my $item ( qw(title windowtitle head bodyopts) ) {
            ${$bml->{$item}} = $extra->{$item} || "";
        }
        return $out;
    }

    my $rv = $class->render_string( $out, $extra );
    if ( $scope eq 'journal' ) {
        $extra->{scope_data}->{handler_return} = $rv;
        return;
    } else {
        return $rv;
    }
}

=head2 C<< $class->render_string( $string, $extra ) >>

Render a string inside the sitescheme or alone.

$extra can contain:

=over

=item B< no_sitescheme > == render alone

=over

If you are just printing text or other data, do not call DW::Template->render_string and instead just
$r->print and return $r->OK.

This is mostly for being used from render_template.

=back

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=back

=cut

sub render_string {
    my ( $class, $out, $extra ) = @_;

    my $r = DW::Request->get;

    my $scheme = DW::SiteScheme->get;

    if ( $extra->{no_sitescheme} ) {
        $r->print( $out );

        return $r->OK;
    } elsif ( $extra->{fragment} ) {
        LJ::set_active_resource_group( "fragment" );
        $out .= LJ::res_includes( nojs => 1, nolib => 1 );
        $r->print( $out );

        return $r->OK;
    } elsif ( $scheme->supports_tt ) {
        $r->content_type("text/html; charset=utf-8");
        $r->print( $class->render_scheme( $scheme, $out, $extra ) );

        return $r->OK;
    } else {
        die "Can not use invalid/unknown engine " . $scheme->engine . " for scheme " . $scheme->name;
    }
}

=head2 C<< $class->render_scheme( $sitescheme, $body, $sections ) >>

Render the body and sections in a TT sitescheme

=over

=item B< sitescheme >

A DW::SiteScheme object

=back

=cut

sub render_scheme {
    my ( $class, $scheme, $body, $sections ) = @_;
    my $r = DW::Request->get;

    my $out;

    my $opts = $scheme->get_vars;
    $opts->{sections} = $sections;
    $opts->{inheritance} = [ map { "$_.tt" } reverse $scheme->inheritance ];
    $opts->{content} = $body;
    $opts->{is_ssl} = $LJ::IS_SSL;
    $opts->{get} = $r->get_args;
    $opts->{resource_group} = $LJ::ACTIVE_RES_GROUP;

    $scheme_engine->process( "_init.tt", $opts, \$out )
        or die $scheme_engine->error->as_string;

    return $out;
}

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
