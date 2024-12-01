#!/usr/bin/perl
#
# DW::Controller::Manage::Profile
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#

package DW::Controller::Manage::Profile;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use LJ::Setting;
use DW::External::ProfileServices;
use DW::FormErrors;
use Data::Dumper;

DW::Routing->register_string( "/manage/profile", \&profile_handler, app => 1 );

sub profile_handler {
    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $u      = $rv->{u};
    my $remote = $rv->{remote};
    my $POST   = $r->post_args;
    my $scope  = '/manage/profile.tt';

    # create $iscomm to help with community-specific translation strings
    my $iscomm = $u->is_community ? '.comm' : '';
    my $curr_privacy =
        $iscomm
        ? {
        Y => LJ::Lang::ml("$scope.security.visibility.everybody2"),
        R => LJ::Lang::ml("$scope.security.visibility.regusers"),
        F => LJ::Lang::ml("$scope.security.visibility.members"),
        N => LJ::Lang::ml("$scope.security.visibility.admins"),
        }->{ $u->opt_showcontact }
        : {
        Y => LJ::Lang::ml("$scope.security.visibility.everybody2"),
        R => LJ::Lang::ml("$scope.security.visibility.regusers"),
        F => LJ::Lang::ml("$scope.security.visibility.access"),
        N => LJ::Lang::ml("$scope.security.visibility.nobody"),
        }->{ $u->opt_showcontact };

    my $errors = DW::FormErrors->new;
    my @errors;

    return DW::Template->render_template( 'error.tt', { message => $LJ::MSG_READONLY_USER } )
        if $u->is_readonly;

    ### user is now authenticated ###

    # The settings used on this page
    my @settings = ();
    push @settings, "LJ::Setting::FindByEmail" if LJ::is_enabled('opt_findbyemail');
    push @settings, "DW::Setting::ProfileEmail";

    my $profile_accts = $u->load_profile_accts( force_db => 1 );

    # list the userprops that are handled explicitly by code on this page
    # props in this list will be preloaded on page load and saved on post
    my @uprops = qw/
        opt_whatemailshow comm_theme
        url urlname gender
        opt_hidefriendofs opt_hidememberofs
        sidx_bdate sidx_bday
        opt_showmutualfriends
        opt_showbday opt_showlocation
        opt_sharebday
        /;

    my %legacy_service_props = map { $_ => 1 } @{ DW::External::ProfileServices->userprops };

    unless (%$profile_accts) {
        push @uprops, $_ foreach keys %legacy_service_props;
    }

    # load user props
    $u->preload_props( { use_master => 1 }, @uprops );

    # to store values before they undergo normalisation
    my %saved = ();
    $saved{'name'} = $u->{'name'};
    $saved{'url'}  = $u->{'url'};

    # clean userprops
    foreach ( values %$u ) { LJ::text_out( \$_ ); }

    # load and clean bio
    my $bio = $u->bio;
    $saved{bio} = $bio;

    LJ::EmbedModule->parse_module_embed( $u, \$bio, edit => 1 );
    LJ::text_out( \$bio, "force" );

    # load interests: $interests{name} = intid
    my %interests = %{ $u->interests( { forceids => 1 } ) };

    my @eintsl;
    foreach ( sort keys %interests ) {
        push @eintsl, $_ if LJ::text_in($_);
    }
    my $interests_str = join( ", ", @eintsl );

    # determine what the options in "Show to:" dropdowns should be, depending
    #  on user or community

    my @showtoopts;
    if ($iscomm) {
        @showtoopts = (
            A => LJ::Lang::ml("$scope.security.visibility.everybody2"),
            R => LJ::Lang::ml("$scope.security.visibility.regusers"),
            F => LJ::Lang::ml("$scope.security.visibility.members"),
            N => LJ::Lang::ml("$scope.security.visibility.admins"),
        );
    }
    else {
        @showtoopts = (
            A => LJ::Lang::ml("$scope.security.visibility.everybody2"),
            R => LJ::Lang::ml("$scope.security.visibility.regusers"),
            F => LJ::Lang::ml("$scope.security.visibility.access"),
            N => LJ::Lang::ml("$scope.security.visibility.nobody"),
        );
    }

    # Birthday form
    my %bdpart;
    if ( $u->{'bdate'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/ ) {
        ( $bdpart{'year'}, $bdpart{'month'}, $bdpart{'day'} ) = ( $1, $2, $3 );
        if ( $bdpart{'year'} eq "0000" ) { $bdpart{'year'} = ""; }
        if ( $bdpart{'day'} eq "00" )    { $bdpart{'day'}  = ""; }
    }

    my @months = map { $_, LJ::Lang::month_long_ml($_) } ( 1 .. 12 );
    $u->{'opt_showbday'} = "D" unless $u->{'opt_showbday'} =~ m/^(D|F|N|Y)$/;
    my $opt_sharebday = ( $u->opt_sharebday =~ m/^(A|F|N|R)$/ ) ? $u->opt_sharebday : 'F';

    # 'Other Services' display
    my $service_info = sub {
        my ($site) = @_;
        $site->{title} = LJ::Lang::ml( $site->{title_ml} );
        return $site;
    };

    my @services = map $service_info->($_), @{ DW::External::ProfileServices->list };
    my @dropdown = ( '' => '' );
    push @dropdown, ( $_->{service_id} => $_->{title} ) foreach @services;

    # Email display
    # This is one prop in the backend, but two form fields on the settings page
    # so we need to do some jumping around to get the correct values for both fields
    my $checked = ( $u->{'opt_whatemailshow'} =~ /[BVL]/ ) ? 'Y' : 'N';
    my $cur     = $u->opt_whatemailshow;

    # drop BVL values that govern site alias; we input that below instead
    $cur =~ tr/BVL/AAN/;    # D reset later

    my $vars = {
        u                => $u,
        authas_html      => $rv->{authas_html},
        formdata         => $POST,
        curr_privacy     => $curr_privacy,
        opt_sharebday    => $opt_sharebday,
        text_in          => \&LJ::text_in,
        help_icon        => \&LJ::help_icon,
        showtoopts       => \@showtoopts,
        interests        => $interests_str,
        month_select     => \@months,
        services         => \@services,
        service_dropdown => \@dropdown,
        saved            => \%saved,
        bdpart           => \%bdpart,
        checked          => $checked,
        cur              => $cur,
        profile_accts    => $profile_accts,
        profile_email    => DW::Setting::ProfileEmail->option($u),
        location => LJ::Widget::Location->render( skip_timezone => 1, minimal_display => 1 ),
        set_profile_settings_extra => LJ::Hooks::run_hook( "profile_settings_extra", $u )
    };

    if ( LJ::is_enabled('opt_findbyemail') ) {
        $vars->{findbyemail} = {
            label => LJ::Setting::FindByEmail->label,
            html  => LJ::Setting::FindByEmail->as_html(
                $u, undef, { minimal_display => 1, helper => 0 }
            )
        };
    }

    if ( $r->did_post ) {

        # name
        unless ( LJ::trim( $POST->{'name'} ) || defined( $POST->{'name_absent'} ) ) {
            $errors->add( 'name', '.error.noname' );
        }

        # name is stored in an 80-char column
        if ( length $POST->{'name'} > 80 ) {
            $errors->add( 'name', '.error.name.toolong' );
        }

        # birthday
        my $this_year = ( localtime() )[5] + 1900;

        if ( $POST->{'year'} && $POST->{'year'} < 100 ) {
            $errors->add( 'year', "$scope.error.year.notenoughdigits" );
        }

        if (   $POST->{'year'}
            && $POST->{'year'} >= 100
            && ( $POST->{'year'} < 1890 || $POST->{'year'} > $this_year ) )
        {
            $errors->add( 'year', "$scope.error.year.outofrange" );
        }

        if ( $POST->{'month'} && ( $POST->{'month'} < 1 || $POST->{'month'} > 12 ) ) {
            $errors->add( 'month', "$scope.error.month.outofrange" );
        }

        if ( $POST->{'day'} && ( $POST->{'day'} < 1 || $POST->{'day'} > 31 ) ) {
            $errors->add( 'day', "$scope.error.day.outofrange" );
        }

        if (   @errors == 0
            && $POST->{'day'}
            && $POST->{'day'} > LJ::days_in_month( $POST->{'month'}, $POST->{'year'} ) )
        {
            $errors->add( 'day', "$scope.error.day.notinmonth" );
        }

        if ( $POST->{'LJ__Setting__FindByEmail_opt_findbyemail'}
            && !$POST->{'LJ__Setting__FindByEmail_opt_findbyemail'} =~ /^[HNY]$/ )
        {
            $errors->add( undef, "$scope.error.findbyemail" );
        }

        # bio
        if ( length( $POST->{'bio'} ) >= LJ::BMAX_BIO ) {
            $errors->add( 'bio', "$scope.error.bio.toolong" );
        }

        # FIXME: validation AND POSTING are handled by widgets' handle_post() methods
        # (introduce validate_post() ?)
        my $save_search_index = $POST->{'opt_showlocation'} =~ /^[YR]$/;
        LJ::Widget->handle_post( $POST, 'Location' => { save_search_index => $save_search_index } );

        return LJ::error_list(@errors) if @errors;

        ### no errors

        my $dbh = LJ::get_db_writer();

        $POST->{'url'} =~ s/\s+$//;
        $POST->{'url'} =~ s/^\s+//;
        if ( $POST->{'url'} && $POST->{'url'} !~ /^https?:\/\// ) {
            $POST->{'url'} =~ s/^http\W*//;
            $POST->{'url'} = "http://$POST->{'url'}";
        }

        my $newname = defined $POST->{'name_absent'} ? $saved{'name'} : $POST->{'name'};
        $newname =~ s/[\n\r]//g;
        $newname = LJ::text_trim( $newname, LJ::BMAX_NAME, LJ::CMAX_NAME );

        my $newbio = defined( $POST->{'bio_absent'} ) ? $saved{'bio'} : $POST->{'bio'};
        my $has_bio = ( $newbio =~ /\S/ ) ? "Y" : "N";
        my $new_bdate = sprintf( "%04d-%02d-%02d",
            $POST->{'year'}  || 0,
            $POST->{'month'} || 0,
            $POST->{'day'}   || 0 );
        my $new_bday = sprintf( "%02d-%02d", $POST->{'month'} || 0, $POST->{'day'} || 0 );

        # setup what we're gonna update in the user table:
        my %update = (
            'name'            => $newname,
            'bdate'           => $new_bdate,
            'has_bio'         => $has_bio,
            'allow_getljnews' => $POST->{'allow_getljnews'} ? "Y" : "N",
        );

        if ( $POST->{'allow_contactshow'} ) {
            $update{'allow_contactshow'} = $POST->{'allow_contactshow'}
                if $POST->{'allow_contactshow'} =~ m/^[NRYF]$/;
        }

        if ( defined $POST->{'oldenc'} ) {
            $update{'oldenc'} = $POST->{'oldenc'};
        }

        my $save_rv = LJ::Setting->save_all( $u, $POST, \@settings );
        if ( LJ::Setting->save_had_errors($save_rv) ) {
            my @save_errors;
            for ( keys %$save_rv ) {
                my $e = $save_rv->{$_}->{save_errors};
                push @save_errors, $e->{ ( keys %$e )[0] };
            }
            return LJ::error_list(@save_errors);
        }

        $u->update_self( \%update );

        ### change any of the userprops ?
        {
            # opts
            $POST->{'opt_showmutualfriends'} = $POST->{'opt_showmutualfriends'} ? 1 : 0;
            $POST->{'opt_hidefriendofs'}     = $POST->{'opt_hidefriendofs'}     ? 0 : 1;
            $POST->{'opt_hidememberofs'}     = $POST->{'opt_hidememberofs'}     ? 0 : 1;
            $POST->{'gender'}        = 'U'   unless $POST->{'gender'} =~ m/^[UMFO]$/;
            $POST->{'opt_sharebday'} = undef unless $POST->{'opt_sharebday'} =~ m/^[AFNR]$/;
            $POST->{'opt_showbday'}  = 'D'   unless $POST->{'opt_showbday'} =~ m/^[DFNY]$/;

            # undefined means show to everyone, "N" means don't show
            $POST->{'opt_showlocation'} = undef unless $POST->{'opt_showlocation'} =~ m/^[NRYF]$/;

            # change value of opt_whatemailshow based on opt_usesite and
            # $u->profile_email (changed above by DW::Setting::ProfileEmail)
            $POST->{'opt_whatemailshow'} =~ tr/A/D/     if $u->profile_email;
            $POST->{'opt_whatemailshow'} =~ tr/ADN/BVL/ if $POST->{'opt_usesite'} eq 'Y';

            # for the directory.
            $POST->{'sidx_bdate'} = undef;
            $POST->{'sidx_bday'}  = undef;

            # if they share their birthdate publically
            if ( $POST->{'opt_sharebday'} =~ /^[AR]$/ ) {

                # and actually provided a birthday
                if ( $POST->{'month'} && $POST->{'month'} > 0 && $POST->{'day'} > 0 ) {

                    # and allow the entire thing to be displayed
                    if ( $POST->{'opt_showbday'} eq "F" && $POST->{'year'} ) {
                        $POST->{'sidx_bdate'} = $new_bdate;
                    }

                    # or allow the date portion to be displayed
                    if ( $POST->{'opt_showbday'} =~ /^[FD]$/ ) {
                        $POST->{'sidx_bday'} = $new_bday;
                    }
                }
            }

            # set userprops
            my %prop;
            foreach my $uprop (@uprops) {
                next if $legacy_service_props{$uprop};
                my $eff_val = $POST->{$uprop};    # effective value, since 0 isn't stored
                $eff_val = "" unless $eff_val;
                $prop{$uprop} = $eff_val;
            }
            $u->set_prop( \%prop, undef, { skip_db => 1 } );

            # update external services
            my %services = map { $_->{service_id} => $_ } @{ DW::External::ProfileServices->list };
            my %new_accts;

            foreach my $ct ( 1 .. 26 ) {
                my $s_id = $POST->{"extservice_site_$ct"};
                next unless $s_id;
                my $val = $POST->{"extservice_val_$ct"} // '';
                $val = LJ::text_trim( $val, 255, $services{$s_id}->{maxlen} );
                $new_accts{$s_id} //= [];
                if ( my $a_id = $POST->{"extservice_dbid_$ct"} ) {
                    push @{ $new_accts{$s_id} }, [ $a_id, $val ];
                }
                else {
                    push @{ $new_accts{$s_id} }, $val;
                }
            }

            $u->save_profile_accts( \%new_accts );

            # location or bday could've changed... (who cares about checking exactly)
            $u->invalidate_directory_record;

            # bday might've changed
            $u->set_next_birthday;
        }

        # update their bio text
        LJ::EmbedModule->parse_module_embed( $u, \$POST->{'bio'} );
        $u->set_bio( $POST->{'bio'}, $POST->{'bio_absent'} );

        # update interests
        unless ( $POST->{'interests_absent'} ) {
            my $maxinterests = $u->count_max_interests;

            my @ints      = LJ::interest_string_to_list( $POST->{'interests'} );
            my $intcount  = scalar(@ints);
            my @interrors = ();

            # Don't bother validating the interests if there are already too many
            if ( $intcount > $maxinterests ) {
                $errors->add(
                    'interests',
                    'error.interest.excessive2',
                    {
                        intcount     => $intcount,
                        maxinterests => $maxinterests
                    }
                );
            }
            else {
                # Clean interests, and make sure they're valid
                my @valid_ints = LJ::validate_interest_list( \@interrors, @ints );
                if ( @interrors > 0 ) {
                    map { $errors->add( 'interests', @$_ ) } @interrors;
                }
                else {
                    my $updated_interests_str = join( ", ", @valid_ints );
                    $u->set_interests( \@valid_ints );
                    $vars->{interests} = $updated_interests_str;
                }
            }
        }

        LJ::Hooks::run_hooks( 'profile_save', $u, \%saved, $POST );
        LJ::Hooks::run_hooks( 'spam_check',   $u, $POST,   'userbio' );
        LJ::Hooks::run_hook( 'set_profile_settings_extra', $u, $POST );

        # tell the user all is well
        my $base        = $u->journal_base;
        my $profile_url = $u->profile_url;
        my $success_msg;
        my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";

        if ( $u->is_community ) {
            $success_msg = "<p>"
                . LJ::Lang::ml( "$scope.success.text.comm",
                { commname => LJ::ljuser( $u->{user} ) } )
                . "</p>"
                . "<ul><li><a href='$LJ::SITEROOT/manage/profile/$getextra'>"
                . LJ::Lang::ml("$scope.success.editprofile.comm")
                . "</a></li>"
                . "<li><a href='$LJ::SITEROOT/manage/icons$getextra'>"
                . LJ::Lang::ml("$scope.success.editicons.comm")
                . "</a></li></ul>";
        }
        else {
            $success_msg = "<p>"
                . LJ::Lang::ml("$scope.success.text") . "</p>"
                . "<ul><li><a href='$LJ::SITEROOT/manage/profile/$getextra'>"
                . LJ::Lang::ml("$scope.success.editprofile")
                . "</a></li>"
                . "<li><a href='$LJ::SITEROOT/manage/icons$getextra'>"
                . LJ::Lang::ml("$scope.success.editicons")
                . "</a></li></ul>";
        }
        return $r->msg_redirect( $success_msg, $r->SUCCESS, $profile_url );
    }

    $vars->{errors} = $errors;

    return DW::Template->render_template( 'manage/profile.tt', $vars );
}

1;
