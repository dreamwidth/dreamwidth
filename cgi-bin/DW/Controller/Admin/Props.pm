#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Admin::Props;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use DW::Controller::Admin;

=head1 NAME

DW::Controller::Admin::Props - Viewing and editing user and logprops

=cut

DW::Routing->register_string( "/admin/propedit", \&propedit_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'propedit',
    ml_scope => '/admin/propedit.tt',
    privs => [ 'canview:userprops', 'canview:*' ]
);

sub propedit_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( privcheck => [ 'canview:userprops', 'canview:*' ], form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $remote = $rv->{remote};
    my $u;
    my @props;

    my $can_save = $remote && $remote->has_priv( "siteadmin", "propedit" );

    my $errors = DW::FormErrors->new;
    if ( $r->did_post && LJ::check_referer( '/admin/propedit' ) ) {
        my $post = $r->post_args;

        $u = LJ::load_user( $post->{username} );
        my $username = LJ::ehtml( $post->{username} );
        $errors->add_string( "$username is not a valid username" ) unless $u;

        if ( ! $errors->exist && $can_save && $post->{_save} ) {
            foreach my $key ( $post->keys ) {
                next if $key eq 'username';
                next if $key eq '_save';
                next if $key eq 'value';
                next if $key eq 'lj_form_auth';

                next unless LJ::get_prop( "user", $key );
                $u->set_prop( $key, $post->{$key} );
            }
        }

        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare( "SELECT * from userproplist ORDER BY name;" );
        $sth->execute;

        while ( my $p = $sth->fetchrow_hashref ) {
            push @props, {
                name => $p->{name},
                value => $u->raw_prop( $p->{name} ),
                description => $p->{des},
                is_text => $p->{des} !~ /Storable hashref/,
            };
        }
    }

    # statusvis => english
    my %statusvis_map = (
        'V' => 'Visible',
        'D' => 'Deleted',
        'E' => 'Expunged',
        'S' => 'Suspended',
        'L' => 'Locked',
        'M' => 'Memorial',
        'O' => 'Read-Only',
        'R' => 'Renamed',
    );

    my $vars = {
        can_save => $can_save,
        u => $u ? {
                username => $u->username,
                userid => $u->userid,
                clusterid => $u->clusterid,
                dversion => $u->dversion,
                statusvis => $u->statusvis,
                statusvis_display => $statusvis_map{$u->statusvis} || "???",
            } : undef,
        props => \@props,
    };
    return DW::Template->render_template( "admin/propedit.tt", $vars );
}

1;