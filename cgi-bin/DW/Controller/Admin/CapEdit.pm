#!/usr/bin/perl
#
# DW::Controller::Admin::CapEdit
#
# Edit user capabilities, which are listed in the site's config files; requires
# admin:capedit or payments:* privileges.
#
# Authors:
#      foxfirefey <foxfirefey@gmail.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::CapEdit;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use LJ::User;

DW::Routing->register_string( "/admin/capedit/index", \&index_controller );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'capedit',
    ml_scope => '/admin/capedit.tt',
    privs    => [
        'admin:capedit',
        'payments',
        sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
        }
    ]
);

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "admin:capedit", "payments" ] );
    return $rv unless $ok;

    my $vars = {%$rv};
    my $r    = DW::Request->get;
    my $args = $r->did_post ? $r->post_args : $r->get_args;
    my @errors;

    if ( $args->{user} ) {
        my $user = LJ::canonical_username( $args->{user} );
        my $u    = $user ? LJ::load_user($user) : undef;

        push @errors, "Unknown user: " . LJ::ehtml( $args->{user} ) unless $u;

        $vars->{u} = $u;

        # do this first so later when we construct the user caps it will be already there
        if ( $r->did_post ) {
            push @errors, "Invalid form auth" unless LJ::check_form_auth( $args->{lj_form_auth} );

            unless (@errors) {

                my @cap_add = ();
                my @cap_del = ();
                my $newcaps = $u->{caps};

                foreach my $n ( sort { $a <=> $b } keys %LJ::CAP ) {
                    if ( $args->{"class_$n"} ) {
                        push @cap_add, $n;
                        $newcaps |= ( 1 << $n );
                    }
                    else {
                        push @cap_del, $n;
                        $newcaps &= ~( 1 << $n );
                    }
                }

                # note which caps were changed and log $logmsg to statushistory
                my $add_txt = join( ",", @cap_add );
                my $del_txt = join( ",", @cap_del );
                my $remote  = LJ::get_remote();

                LJ::statushistory_add( $u->{userid}, $remote->{userid},
                    "capedit", "add: $add_txt, del: $del_txt\n" );

                $u->modify_caps( \@cap_add, \@cap_del )
                    or push @errors, "Error: Unable to modify caps.";

                # $u->{caps} is now updated in memory for later in this request
                $u->{caps} = $newcaps;

                # set this flag to let the template know we have saved
                $vars->{save} = 1;
            }

        }

        # make information for all of the caps based on the current info
        my @caps;

        foreach my $n ( sort { $a <=> $b } keys %LJ::CAP ) {
            push @caps,
                {
                "n"    => $n,
                "on"   => ( ( $u->{caps} + 0 ) & ( 1 << $n ) ) ? 1 : 0,
                "name" => $LJ::CAP{$n}->{'_name'} || "Unnamed capability class #$n",
                };
        }

        $vars->{caps} = \@caps;
    }
    else {
        $vars->{u} = 0;
    }

    $vars->{error_list} = \@errors if @errors;
    return DW::Template->render_template( 'admin/capedit.tt', $vars );
}

1;
