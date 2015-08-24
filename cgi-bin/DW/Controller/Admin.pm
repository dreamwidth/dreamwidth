#!/usr/bin/perl
#
# DW::Controller::Admin
#
# Controller for admin action list index pages.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Denise Paolucci <denise@dreamwidth.org>
#      Sophie Hamilton <dw-bugzilla@theblob.org>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin;

=head1 NAME

DW::Controller::Admin - Controller for admin action list index pages.

This is for pages like /admin/index which list other pages, displaying only what the current user can do

=head1 API

=cut

use strict;
use warnings;
use DW::Controller;
use DW::Template;

# this needs to be included at run time to avoid circular requirements
require DW::Routing;

my $admin_pages = {};

DW::Controller::Admin->register_admin_scope( '/', title_ml => '.admin.title' );

# DO NOT add anything to here
DW::Controller::Admin->_register_admin_pages_legacy( '/', 
    [ 'faq/',
        '.admin.faq.link', '.admin.faq.text', [ 'faqadd', 'faqedit', 'faqcat' ] ],
    [ 'fileedit/',
        '.admin.file_edit.link', '.admin.file_edit.text', [ 'fileedit' ] ],
    [ 'invites/', '.admin.invites.link', '.admin.invites.text', [ 'finduser:codetrace', 'finduser:*', 'payments' ] ],
    [ 'memcache',
        '.admin.memcache.link', '.admin.memcache.text', [ 'siteadmin:memcacheview', 'siteadmin:*' ] ],
    [ 'memcache_view',
        '.admin.memcache_view.link', '.admin.memcache_view.text', [ 'siteadmin:memcacheview', 'siteadmin:*', sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml( "/admin/index.tt.devserver" ) );
        } ] ],
    [ 'pay/',
        '.admin.pay.link', '.admin.pay.text', [ 'payments' ] ],
    [ 'priv/',
        '.admin.priv.link', '.admin.priv.text' ],
    [ 'recent_comments',
        '.admin.recent_comments.link', '.admin.recent_comments.text', [ 'siteadmin:commentview', 'siteadmin:*' ] ],
    [ 'statushistory',
        '.admin.statushistory.link', '.admin.statushistory.text', [ 'historyview', sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml( "/admin/index.tt.devserver" ) );
        } ] ],
    [ 'styleinfo',
        '.admin.styleinfo.link', '.admin.styleinfo.text', [ sub {
            return ( LJ::Support::has_any_support_priv($_[0]->{remote}),
                LJ::Lang::ml( "/admin/index.tt.anysupportpriv" ) );
        }, sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml( "/admin/index.tt.devserver" ) );
        } ] ],
    [ 'sysban',
        '.admin.sysban.link', '.admin.sysban.text', [ 'sysban' ] ],
    [ 'translate/',
        '.admin.translate.link', '.admin.translate.text' ],
    [ 'userlog',
        '.admin.userlog.link', '.admin.userlog.text', [ 'canview:userlog', 'canview:*' ] ],
    [ 'vgifts/',
        '.admin.vgifts.link', '.admin.vgifts.text', [ 'siteadmin:vgifts', 'vgifts', sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml( "/admin/index.tt.devserver" ) );
        } ] ],
);


sub admin_handler {
    my $opts = shift @_;
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};

    my $args = $opts->args || {};
    my $scope = $args->{scope} || "/";

    my $data = $admin_pages->{$scope};

    my $vars = $rv;

    $vars->{$_} = $data->{$_} foreach qw( title_ml description_ml ml_scope );

    my @pages;
    my $adminstar = $remote && $remote->has_priv( 'admin', '*' );
    foreach my $page ( @{ $data->{pages} } ) {
        my ( $path, $link_ml, $description_ml, $privs ) = @{$page};
        my $showpage = 0;
        my ( @needsprivs, @gotprivs );
        my $haspriv = 0;
        foreach my $priv ( @{$privs} ) {
            my $code_result;
            $code_result = [
                $priv->( { remote => $remote } )
            ] if ref( $priv ) eq "CODE";

            my $result = ( $code_result ?
                             $code_result->[0] :
                             $remote && $remote->has_priv( split( /:/, $priv ) ) );
            my $displayedpriv = ( $code_result ?
                                        $code_result->[1] :
                                        $priv );
            push( @gotprivs,   $displayedpriv ) if $result;
            push( @needsprivs, $displayedpriv ) if !$result;
            $haspriv  = 1 if $result;
            $showpage = 1 if $adminstar || $result;
        }
        if ( @$privs == 0 ) {
            $showpage = 1;
            $haspriv  = 1;
        }
        $path = "/admin$scope$path" unless $path =~ m!^((https?://)|/)!;
        if ( $showpage ) {
            push @pages, {
                path => $path,
                link_ml => $link_ml,
                description_ml => $description_ml,
                haspriv => $haspriv,
                gotprivs => \@gotprivs,
                needsprivs => \@needsprivs,
            };
        }
    }
    $vars->{pages} = \@pages;

    return DW::Template->render_template( 'admin/index.tt', $vars );
}

=head2 C<< $class->register_admin_scope( $scope, %opts ) >>

Register an admin scope.

Arguments:

=over 4

=item scope

The name of the scope

=back

Additional options:

=over 4

=item ml_scope

The ML scope for the ml strings.

=item title_ml

ML string for title

=item description_ml

ML string for description

=back

=cut

sub register_admin_scope {
    my ( $class, $scope, %opts ) = @_;

    $admin_pages->{$scope} = \%opts;

    my $url = "/admin" . ( $scope eq '/' ? '' : $scope ) . '/index';

    DW::Routing->register_string( $url, \&admin_handler, args => { scope => $scope } );
}

=head2 C<< $class->register_admin_page( $scope, %opts ) >>

Register an admin page.

Arguments:

=over 4

=item scope

The name of the scope

=back

Additional options:

=over 4

=item ml_scope

The ML scope for the ml strings.

=item link_ml

ML string for link text ( defaults to ".admin.link" )

=item description_ml

ML string for description ( defaults to ".admin.text" )

=item path

Path, either relative to the scope ( no leading slash ), relative to the domain ( leading slash ), or a full URI

=item privs

An arrayref of priv names or subroutine refs

The subref needs to return [ $has_priv, $string ]

=back

=cut

sub register_admin_page {
    my ( $class, $scope, %args ) = @_;

    my ( $path, $link_ml, $desc_ml, $privs );

    $path = $args{path};
    $privs = $args{privs};

    $link_ml = $args{link_ml} || ".admin.link";
    $desc_ml = $args{description_ml} || ".admin.text";

    if ( $args{ml_scope} ) {
        $link_ml = $args{ml_scope} . $link_ml;
        $desc_ml = $args{ml_scope} . $desc_ml;
    } 

    $scope ||= "/";
    push @{$admin_pages->{$scope}->{pages}}, [ $path, $link_ml, $desc_ml, $privs ];
}

# DO NOT USE OUTSIDE THIS FILE!
# FIXME: Remove once the big scary array up above is gone!
sub _register_admin_pages_legacy {
    my ( $class, $scope, @pages ) = @_;

    $scope ||= "/";
    foreach my $part ( @pages ) {
        push @{$admin_pages->{$scope}->{pages}}, $part;
    }
}

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=item Denise Paolucci <denise@dreamwidth.org>

=item Sophie Hamilton <dw-bugzilla@theblob.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
