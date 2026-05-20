#!/usr/bin/perl
#
# DW::Controller::Admin::Invites
#
# Management tasks related to invite codes.
# Requires finduser:codetrace, siteadmin:invites, or payments privileges.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::Invites;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Task::DistributeInvites;
use DW::Template;
use DW::FormErrors;

use DW::InviteCodes;
use DW::InviteCodes::Promo;
use DW::InviteCodeRequests;
use DW::Pay;

my $all_invite_privs =
    [ 'finduser:codetrace', 'finduser:*', 'payments', 'siteadmin:invites', 'siteadmin:*' ];

my $light_invite_privs = [ 'payments', 'siteadmin:invites', 'siteadmin:*' ];

DW::Routing->register_string( "/admin/invites", \&index_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'invites',
    ml_scope => '/admin/invites/index.tt',
    privs    => $all_invite_privs
);

DW::Routing->register_string( "/admin/invites/codetrace",  \&codetrace_controller,  app => 1 );
DW::Routing->register_string( "/admin/invites/distribute", \&distribute_controller, app => 1 );
DW::Routing->register_string( "/admin/invites/requests",   \&requests_controller,   app => 1 );
DW::Routing->register_string( "/admin/invites/review",     \&review_controller,     app => 1 );
DW::Routing->register_string( "/admin/invites/promo",      \&promo_controller,      app => 1 );

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => $all_invite_privs );
    return $rv unless $ok;
    my $remote = $rv->{remote};

    # we show links to various subpages depending on which privs the remote has;
    # can_manage_invites_light consists of "payments" or "siteadmin:invites"

    my $vars = {
        has_payments => $remote->has_priv("payments"),
        has_finduser => $remote->has_priv( "finduser", "codetrace" ),
        has_invites  => $remote->can_manage_invites_light,
    };

    return DW::Template->render_template( 'admin/invites/index.tt', $vars );
}

sub codetrace_controller {
    my ( $ok, $rv ) = controller( privcheck => [ 'finduser:codetrace', 'finduser:*' ] );
    return $rv unless $ok;

    my $scope = '/admin/invites/codetrace.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->get_args;
    my $vars      = {};

    my $account;

    if ( $form_args->{code} ) {
        if ( my $code = DW::InviteCodes->new( code => $form_args->{code} ) ) {
            $account = $rv->{remote};
            $vars->{display_codes} = [$code];

        }
        else {
            $vars->{display_error} =
                LJ::Lang::ml( "$scope.error.invalidcode", { code => $form_args->{code} } );
        }

    }
    elsif ( $form_args->{account} ) {
        if ( $account = LJ::load_user( $form_args->{account} ) ) {
            my @used  = DW::InviteCodes->by_recipient( userid => $account->id );
            my @owned = DW::InviteCodes->by_owner( userid => $account->id );

            if ( @used or @owned ) {
                $vars->{display_codes} = [ @used, @owned ];
            }
            else {
                $vars->{display_error} =
                    LJ::Lang::ml( "$scope.error.nocodes", { account => $account->ljuser_display } );
            }

        }
        else {
            $vars->{display_error} =
                LJ::Lang::ml( "$scope.error.invaliduser", { user => $form_args->{account} } );
        }

    }

    $vars->{maxlength_code} = DW::InviteCodes::CODE_LEN;
    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;
    $vars->{time_to_http}   = sub { return LJ::time_to_http( $_[0] ) };

    $vars->{load_code_owner} = sub {
        return $_[0]->owner == $account->id ? $account : LJ::load_userid( $_[0]->owner );
    };

    $vars->{load_code_recipient} = sub {
        return $_[0]->is_used ? LJ::load_userid( $_[0]->recipient ) : undef;
    };

    return DW::Template->render_template( 'admin/invites/codetrace.tt', $vars );
}

sub distribute_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => $light_invite_privs );
    return $rv unless $ok;

    my $scope = '/admin/invites/distribute.tt';

    my $r         = DW::Request->get;
    my $post_args = $r->post_args;
    my $vars      = {};

    my $classes = DW::BusinessRules::InviteCodes::user_classes();

    # we can't just splat this hashref into an arrayref because
    # the order of the list will be randomized every time we load it
    # which is bad UX for a dropdown menu

    $vars->{classes} = [];
    foreach ( sort { $classes->{$a} cmp $classes->{$b} } keys %$classes ) {
        push @{ $vars->{classes} }, $_, $classes->{$_};
    }

    if ( $r->did_post ) {

        # sanitize the number of invites
        my $num_invites_requested = $post_args->{num_invites};
        $num_invites_requested =~ s/[^0-9]//g;
        $num_invites_requested += 0;

        if ($num_invites_requested) {

            # sanitize selected user class
            my $selected_user_class = $post_args->{user_class};

            if ( exists $classes->{$selected_user_class} ) {

                $vars->{dispatch} = DW::TaskQueue->dispatch(
                    DW::Task::DistributeInvites->new(
                        {
                            requester   => $rv->{remote}->userid,
                            searchclass => $selected_user_class,
                            invites     => $num_invites_requested,
                            reason      => $post_args->{reason}
                        }
                    )
                );

                $vars->{display_error} = LJ::Lang::ml("$scope.error.cantinsertjob")
                    unless $vars->{dispatch};
            }
            else {
                $vars->{display_error} =
                    LJ::Lang::ml( "$scope.error.nosuchclass", { class => $selected_user_class } );
            }
        }
        else {
            $vars->{display_error} = LJ::Lang::ml("$scope.error.noinvites");
        }

    }

    return DW::Template->render_template( 'admin/invites/distribute.tt', $vars );
}

sub requests_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => $light_invite_privs );
    return $rv unless $ok;

    my $scope = '/admin/invites/requests.tt';

    my $r    = DW::Request->get;
    my $vars = {};

    # we do the post processing in the template (radical!)
    $vars->{r} = $r;

    # get outstanding invites
    my @outstanding = DW::InviteCodeRequests->outstanding;
    $vars->{outstanding} = \@outstanding;

    # load user objects
    my $users = LJ::load_userids( map { $_->userid } @outstanding );
    $vars->{users} = $users;

    # count invites the user has
    $vars->{counts} = {};
    foreach my $u ( values %$users ) {
        $vars->{counts}->{ $u->id } =
            DW::InviteCodes->unused_count( userid => $u->id );
    }

    # subroutine for counting accounts registered to user's email.
    $vars->{pc_accts} = sub {
        my ($u) = @_;
        if ( my $acctids = $u->accounts_by_email ) {
            my $us = LJ::load_userids(@$acctids);
            my ( $pct, $cct ) = ( 0, 0 );
            foreach (@$acctids) {
                next unless $us->{$_};
                $pct++ if $us->{$_}->is_personal;
                $cct++ if $us->{$_}->is_comm;
            }
            return "$pct/$cct";
        }
        else {
            return "N/A";
        }
    };

    # subroutine to check whether the user is sysbanned
    $vars->{sysbanned} = sub { DW::InviteCodeRequests->invite_sysbanned( user => $_[0] ) };

    $vars->{time_to_http} = sub { return LJ::time_to_http( $_[0] ) };

    $vars->{reason_text} = sub { $_[0]->reason || LJ::Lang::ml("$scope.noreason") };
    $vars->{reason_link} = sub {
        my ( $u, $reason ) = @_;
        return $reason unless $rv->{remote}->has_priv("payments");
        return "<a href='review?user=$u->{user}'>$reason</a>";
    };

    return DW::Template->render_template( 'admin/invites/requests.tt', $vars );
}

sub review_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['payments'] );
    return $rv unless $ok;

    my $r    = DW::Request->get;
    my $vars = {};

    # we do the post processing in the template (radical!)
    $vars->{r} = $r;

    $vars->{getuser} = $r->get_args->{user};
    $vars->{u}       = LJ::load_user( $vars->{getuser} )
        if defined $vars->{getuser};

    $vars->{load_req} = sub { DW::InviteCodeRequests->new( reqid => $_[0] ) };
    $vars->{list_req} = sub { [ DW::InviteCodeRequests->by_user( userid => $_[0]->id ) ] };

    $vars->{unused_count} = sub { DW::InviteCodes->unused_count( userid => $_[0]->id ) };
    $vars->{usercodes}    = sub { [ DW::InviteCodes->by_owner( userid => $_[0]->id ) ] };

    $vars->{load_recipient} = sub { LJ::load_userid( $_[0]->recipient ) };

    $vars->{time_to_http} = sub { LJ::time_to_http( $_[0] ) };

    $vars->{paid_status} = sub { defined DW::Pay::get_paid_status( $_[0] ) };

    $vars->{get_oldest} = sub {

        # being tyrannical, and forcing the earliest outstanding
        # request to be the one which is processed

        my ($requests) = @_;
        return ( grep { $_->{status} eq 'outstanding' } @$requests )[0];
    };

    return DW::Template->render_template( 'admin/invites/review.tt', $vars );
}

sub promo_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => $light_invite_privs );
    return $rv unless $ok;

    my $r      = DW::Request->get;
    my $errors = DW::FormErrors->new;
    my $vars   = {};

    $vars->{code}  = $r->get_args->{code} || "";
    $vars->{state} = lc( $r->get_args->{state} || "" );

    $vars->{load_suggest_u} = sub {
        my ($data) = @_;
        return unless $data && $data->{suggest_journalid};
        return LJ::load_userid( $data->{suggest_journalid} );
    };

    $vars->{mysql_date} = sub { $_[0] ? LJ::mysql_date( $_[0] ) : "" };

    if ( $r->did_post ) {

        $vars->{code}  = $r->post_args->{code} || "";
        $vars->{state} = lc( $r->post_args->{state} || "" );

        my $post  = $r->post_args;
        my $valid = 1;
        my $info;

        my $data = {
            active               => defined( $post->{active} ) ? 1 : 0,
            code                 => $vars->{code},
            current_count        => 0,
            max_count            => $post->{max_count} || 0,
            suggest_journal      => $post->{suggest_journal},
            paid_class           => $post->{paid_class} || '',
            paid_months          => $post->{paid_months} || undef,
            expiry_date_unedited => $post->{expiry_date_unedited} || 0,
            expiry_date          => $post->{expiry_date} || 0,
            expiry_months        => $post->{expiry_months} || 0,
            expiry_days          => $post->{expiry_days} || 0,
        };

        if ( !$vars->{code} ) {
            $errors->add( 'code', '.error.code.missing' );
            $valid = 0;

        }
        elsif ( $vars->{state} eq 'create' ) {

            if ( $vars->{code} !~ /^[a-z0-9]+$/i ) {
                $errors->add( 'code', '.error.code.invalid_character' );
                $valid = 0;

            }
            elsif ( DW::InviteCodes::Promo->is_promo_code( code => $vars->{code} ) ) {
                $errors->add( 'code', '.error.code.exists' );
                $valid = 0;
            }

        }
        elsif ( !ref( $info = DW::InviteCodes::Promo->load( code => $vars->{code} ) ) ) {
            $errors->add( 'code', '.error.code.invalid' );
            $valid = 0;

        }
        else {
            $data->{current_count} = $info->{current_count};
        }

        if ( $post->{max_count} < 0 ) {
            $errors->add( 'max_count', '.error.count.negative' );
        }

        if ( $post->{suggest_journal} ) {

            if ( my $user = LJ::load_user( $post->{suggest_journal} ) ) {
                $data->{suggest_journalid} = $user->userid;

            }
            else {
                $errors->add( 'suggest_journal', '.error.suggest_journal.invalid' );
                $valid = 0;
            }

        }
        else {
            $data->{suggest_journal} = undef;
        }

        if ( $data->{paid_class} !~ /^(paid|premium)$/ ) {
            $data->{paid_class}  = undef;
            $data->{paid_months} = undef;
        }

        if ( $data->{expiry_date} ne $data->{expiry_date_unedited} ) {

            if ( $data->{expiry_days} || $data->{expiry_months} ) {
                $errors->add( 'expiry_date', '.error.date.double_specified' );
                $valid = 0;
            }

            $data->{expiry_db} = LJ::mysqldate_to_time( $data->{expiry_date} );

        }
        else {
            if ( $data->{expiry_days} < 0 ) {
                $errors->add( 'expiry_date', '.error.days.negative' );
                $valid = 0;
            }

            if ( $data->{expiry_months} < 0 ) {
                $errors->add( 'expiry_date', '.error.months.negative' );
                $valid = 0;
            }

            $data->{expiry_months} = 0 unless $data->{expiry_months};
            $data->{expiry_days}   = 0 unless $data->{expiry_days};

            if ( my $length = $data->{expiry_months} * 30 + $data->{expiry_days} ) {
                $data->{expiry_db} = time() + ( $length * 86400 );
            }
            else {
                $data->{expiry_db} = 0;
            }
        }

        if ($valid) {
            my $dbh = LJ::get_db_writer();

            if ( $vars->{state} eq 'create' ) {
                $dbh->do(
"INSERT INTO acctcode_promo (code, max_count, active, suggest_journalid, paid_class, paid_months, expiry_date) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    undef,
                    $data->{code},
                    $data->{max_count},
                    $data->{active},
                    $data->{suggest_journalid},
                    $data->{paid_class},
                    $data->{paid_months},
                    $data->{expiry_db}
                ) or die $dbh->errstr;

                delete $vars->{state};

            }
            else {
                $dbh->do(
"UPDATE acctcode_promo SET max_count = ?, active = ?, suggest_journalid = ?, paid_class = ?, paid_months = ?, expiry_date =? WHERE code = ?",
                    undef,
                    $data->{max_count},
                    $data->{active},
                    $data->{suggest_journalid},
                    $data->{paid_class},
                    $data->{paid_months},
                    $data->{expiry_db},
                    $data->{code}
                ) or die $dbh->errstr;
            }

        }
        else {
            $vars->{errors}   = $errors;
            $vars->{formdata} = $data;
            return DW::Template->render_template( 'admin/invites/promo-edit.tt', $vars );
        }

        delete $vars->{code};

    }    # end if did_post

    return DW::Template->render_template( 'admin/invites/promo-edit.tt', $vars )
        if $vars->{state} && $vars->{state} eq 'create';

    if ( DW::InviteCodes::Promo->is_promo_code( code => $vars->{code} ) ) {

        $vars->{formdata} = DW::InviteCodes::Promo->load( code => $vars->{code} );
        return DW::Template->render_template( 'admin/invites/promo-edit.tt', $vars );
    }

    # variables only used in promo.tt

    $vars->{codelist} = DW::InviteCodes::Promo->load_bulk( state => $vars->{state} );

    return DW::Template->render_template( 'admin/invites/promo.tt', $vars );
}

1;
