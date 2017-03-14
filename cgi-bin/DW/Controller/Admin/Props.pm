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
use DW::External::Account;

=head1 NAME

DW::Controller::Admin::Props - Viewing and editing user and logprops

=cut

DW::Routing->register_string( "/admin/propedit", \&propedit_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'propedit',
    ml_scope => '/admin/propedit.tt',
    privs => [ 'canview:userprops', 'canview:*' ]
);

DW::Routing->register_string( "/admin/entryprops", \&entryprops_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'entryprops',
    ml_scope => '/admin/entryprops.tt',
    privs => [ 'canview:entryprops', 'canview:*', sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml( "/admin/index.tt.devserver" ) );
    } ]
);

sub entryprops_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( privcheck => [ 'canview:entryprops', 'canview:*', sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml( "/admin/index.tt.devserver" ) );
    } ], form_auth => 0 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $remote = $rv->{remote};
    my %entry_info;
    my @props;

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        my $post = $r->post_args;
        my $entry = LJ::Entry->new_from_url( $post->{url} );

        my $url = LJ::ehtml( $post->{url} );
        $errors->add_string( 'url', "$url is not a valid entry URL." )
            unless $entry && $entry->valid;

        unless ( $errors->exist ) {
            # WE HAEV ENTRY!!

            my $subject;
            if ( $entry->visible_to( $remote ) ) {
                $subject = $entry->subject_html ? $entry->subject_html : "<em>no subject</em>";
            } else {
                $subject = "<em>hidden</em>";
            }

            my $security = $entry->security;
            if ( $security eq "usemask" ) {
                if ( $entry->allowmask == 1 ) {
                    $security = "friends";
                } else {
                    $security = "custom";
                }
            }

            my $pu = $entry->poster;
            my $journal = $entry->journal;
            %entry_info = (
                subject => $subject,
                security => $security,
                url => $entry->url,
                poster => $pu->ljuser_display,
                journal => $journal->ljuser_display,
                minsecurity => $journal->prop("newpost_minsecurity") || "public",
                user_time => $entry->eventtime_mysql,
                server_time => $entry->logtime_mysql,
                adult_content => $journal->adult_content || "none",
            );

            my %entry_props = %{$entry->props || {}};
            foreach my $prop_name ( sort keys %entry_props ) {
                my %prop = (
                    name => $prop_name,
                    value => $entry_props{$prop_name},
                    description => "",
                );
                if ( my $prop_meta = LJ::get_prop( "log", $prop_name ) ) {
                    $prop{description} = $prop_meta->{des};

                    # an ugly hack, i know
                    $prop{value} = LJ::mysql_time( $prop{value} ) if $prop_meta->{des} =~ /unix/i;

                    # render xpost prop into human readable form
                    if ( $prop_name eq "xpost" || $prop_name eq "xpostdetail" ) {
                        my %external_accounts_map = map { $_->acctid => $_->servername . ( $_->active ? "" : " (deleted)" ) } DW::External::Account->get_external_accounts( $pu, show_inactive => 1 );

                        # FIXME: temporary; trying to figure out when this is undef
                        my $xpost_prop = $prop{value};
                        my $xpost_hash = DW::External::Account->xpost_string_to_hash( $prop{value} );
                        my %xpost_map = %{ $xpost_hash || {} };

                        if ( $prop_name eq "xpost" ) {
                            $prop{value} = join ", ", map { ( $external_accounts_map{$_} || "unknown" ) . " => $xpost_map{$_}" } keys %xpost_map;
                            $prop{description} .= " (site name => itemid)";
                        } else {
                            $prop{value} = join ", ", map { ( $external_accounts_map{$_} || "unknown" ) . " => { $xpost_map{$_}->{itemid}, $xpost_map{$_}->{url} }" } keys %xpost_map;
                            $prop{description} .= " (site name => { itemid, url })";
                        }

                    } elsif ( $prop_name eq 'picture_mapid' && $pu->userpic_have_mapid ) {
                        my $result = "$prop{value} -> ";
                        my $kw = $pu->get_keyword_from_mapid( $prop{value},
                                    redir_callback => sub {
                                        $result .= "$_[2] -> ";
                                    });
                        $result .= $kw;
                        my $picid = $pu->get_picid_from_keyword( $kw, -1 );
                        if ( $picid == -1 ) {
                            $result .= " ( not assigned to an icon )";
                        } else {
                            $result .= " ( assigned to an icon )";
                        }
                        $prop{value} = $result;
                    }
                }
                push @props, \%prop;
            }
        }
    }

    my $vars = {
        entry => %entry_info ? \%entry_info : undef,
        props => \@props,
    };
    return DW::Template->render_template( "admin/entryprops.tt", $vars );
}

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
        $errors->add_string( 'username', "$username is not a valid username" ) unless $u;

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
