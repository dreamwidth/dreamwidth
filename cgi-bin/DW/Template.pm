#!/usr/bin/perl
#
# DW::Template
#
# Template Toolkit helpers for Apache2.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
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

=head1 NAME

DW::Template - Template Toolkit helpers for Apache2.

=head1 SYNOPSIS

=cut 

# setting this to 0 -- have to explicitly specify which plugins we want.
$Template::Plugins::PLUGIN_BASE = '';

my $site_constants = Template::Namespace::Constants->new({
    name => $LJ::SITENAME,
    nameshort => $LJ::SITENAMESHORT,
    nameabbrev => $LJ::SITENAMEABBREV,
    company => $LJ::SITECOMPANY,
});

my $roots_constants = Template::Namespace::Constants->new({
    site => $LJ::SITEROOT,
});

# precreating this
my $view_engine = Template->new({
    INCLUDE_PATH => "$LJ::HOME/views/",
    NAMESPACE => {
        site => $site_constants,
        roots => $roots_constants,
    },
    FILTERS => {
        ml => [ \&ml, 1 ],
    },
    CACHE_SIZE => $LJ::TEMPLATE_CACHE_SIZE, # this can be undef, and that means cache everything.
    STAT_TTL => $LJ::IS_DEV_SERVER ? 1 : 3600,
    PLUGINS => {
        autoformat => 'Template::Plugin::Autoformat',
        date => 'Template::Plugin::Date',
        url => 'Template::Plugin::URL',
    },
});

=head1 API

=head2 C<< $class->template_string( $filename, $opts ) >>

Render a template to a string.

=cut

sub template_string {
    my ($class, $filename, $opts) = @_;
    my $r = DW::Request->get;

    $r->note('ml_scope',"/$filename") unless $r->note('ml_scope');

    my $out;
    $view_engine->process( $filename, $opts, \$out )
        or die Template->error();

    return $out;
}

=head2 C<< $class->cached_template_string( $key, $filename, $subref, $opts, $extra ) >>

Render a template to a string -- optionally fragment caching it.
$subref returns the options for template_string.

fragment opts:

=over

=item B< lock_failed > - The text returned by this subref is returned if the lock is failed and the grace period is up.

=item B< expire > - Number of seconds the fragment is valid for

=item B< grace_period > - Number of seconds that an expired fragment could still be served if the lock is in place

=back

=cut

sub cached_template_string {
    my ($class, $key, $filename, $subref, $opts, $extra ) = @_;

    $extra ||= {};
    $opts->{sections} = $extra;
    return DW::FragmentCache->get( $key, {
        lock_failed => $opts->{lock_failed},
        expire => $opts->{expire},
        grace_period => $opts->{grace_period},
        render => sub {
            return $class->template_string( $filename, $subref->( $_[0] ) );
        }
    }, $extra);
}

=head2 C<< $class->render_cached_template( $key, $filename, $subref, $extra ) >>

Render a template inside the sitescheme or alone.

See render_template, except note that the opts hash is returned by subref if it's needed.

$extra can contain:

=over

=item B< no_sitescheme > == render alone

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=item B< content_type > = content type

=item B< status > = HTTP status code

=item B< lock_failed > = subref for lock failed.

=item B< expire > - Number of seconds the fragment is valid for

=item B< grace_period > - Number of seconds that an expired fragment could still be served if the lock is in place

=back

=cut

sub render_cached_template {
    my ($class, $key, $filename, $subref, $opts, $extra) = @_;

    my $out = $class->cached_template_string( $key, $filename, $subref, $opts, $extra );

    return $class->render_string( $out, $extra );
}

=head2 C<< $class->render_template( $filename, $opts, $extra ) >>

Render a template inside the sitescheme or alone.

$extra can contain:

=over

=item B< no_sitescheme > == render alone

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=item B< content_type > = content type

=item B< status > = HTTP status code

=back

=cut

sub render_template {
    my ( $class, $filename, $opts, $extra ) = @_;

    $extra ||= {};
    $opts->{sections} = $extra;

    my $out = $class->template_string( $filename, $opts );

    return $class->render_string( $out, $extra );
}

=head2 C<< $class->render_string( $string, $extra ) >>

Render a string inside the sitescheme or alone.

$extra can contain:

=over

=item B< no_sitescheme > == render alone

=item B< title / windowtitle / head / bodyopts / ... > == text to get thrown in the section if inside sitescheme

=item B< content_type > = content type

=item B< status > = HTTP status code

=back

=cut

sub render_string {
    my ( $class, $out, $extra ) = @_;

    my $r = DW::Request->get;
    $r->status( $extra->{status} ) if $extra->{status};
    $r->content_type( $extra->{content_type} ) if $extra->{content_type};

    if ( $extra->{no_sitescheme} ) {
        $r->print( $out );

        return $r->OK;
    } else {
        $r->pnote(render_sitescheme_code => $out);
        $r->pnote(render_sitescheme_extra => $extra || {});

        return $r->call_bml("$LJ::HOME/htdocs/misc/render_sitescheme.bml");
    }
}

=head1 ML Stuff

NOTE: All these methods use DW::Template::blah, not DW::Template->blah.

=head2 C<< DW::Template::ml_scope( $scope ) >>

Gets the scope or sets the scope to the given location

=cut

sub ml_scope {
    return DW::Request->get->note('ml_scope', $_[0]);
}

=head2 C<< DW::Template::ml( $code, $vars ) >>

=cut

sub ml {
    # save the last argument as the hashref, hopefully
    my $args = $_[-1];
    $args = {} unless $args && ref $args eq 'HASH';

    # we have to return a sub here since we are a dynamic filter
    return sub {
        my ( $code ) = @_;

        $code = DW::Request->get->note( 'ml_scope' ) . $code
            if rindex( $code, '.', 0 ) == 0;

        my $lang = decide_language();
        return $code if $lang eq 'debug';
        return LJ::Lang::get_text( $lang, $code, undef, $args );
    };
}

sub decide_language {
    my $r = DW::Request->get;
    return $r->note( 'ml_lang' ) if $r->note( 'ml_lang' );
    
    my $lang = _decide_language();
    
    $r->note( 'ml_lang', $lang );
    return $lang;
}

sub _decide_language
{
    my $r = DW::Request->get;

    my $args = $r->get_args;
    # GET param 'uselang' takes priority
    my $uselang = $args->{'uselang'};
    if ( $uselang eq "debug" || LJ::Lang::get_lang($uselang) ) {
        return $uselang;
    }

    # next is their cookie preference
    #FIXME: COOKIE!
    #if ($BML::COOKIEIE{'langpref'} =~ m!^(\w{2,10})/(\d+)$!) {
    #    if (exists $env->{"Langs-$1"}) {
    #        # FIXME: Probably should actually do this!!!
    #        # make sure the document says it was changed at least as new as when
    #        # the user last set their current language, else their browser might
    #        # show a cached (wrong language) version.
    #        return $1;
    #    }
    #}

    # FIXME: next is their browser's preference

    # next is the default language
    return $LJ::DEFAULT_LANG || $LJ::LANGS[0];

    # lastly, english.
    return "en";
}

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
