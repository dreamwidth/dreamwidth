#!/usr/bin/perl
#
# DW::Controller::Entry
#
# This controller is for creating and managing entries
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Entry;

use strict;

use LJ::Global::Constants;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

use Hash::MultiValue;
use HTTP::Status qw( :constants );
use LJ::JSON;

use DW::External::Account;


my %form_to_props = (
    # currents / metadata
    current_mood        => "current_moodid",
    current_mood_other  => "current_mood",
    current_music       => "current_music",
    current_location    => "current_location",
);


my @modules = qw(
    tags displaydate slug
    currents comments age_restriction
    icons crosspost sticky
);


=head1 NAME

DW::Controller::Entry - Controller which handles posting and editing entries

=head1 Controller API

Handlers for creating and editing entries

=cut

DW::Routing->register_string( '/entry/new', \&new_handler, app => 1 );
DW::Routing->register_regex( '^/entry/([^/]+)/new$', \&new_handler, app => 1 );

DW::Routing->register_string( '/entry/preview', \&preview_handler, app => 1, methods => { POST => 1 } );

DW::Routing->register_string( '/entry/options', \&options_handler, app => 1 );
DW::Routing->register_string( '/__rpc_entryoptions', \&options_rpc_handler, app => 1 );
DW::Routing->register_string( '/__rpc_entryformcollapse', \&collapse_rpc_handler, app => 1, methods => { GET => 1 }, format => 'json' );

                             # /entry/username/ditemid/edit
DW::Routing->register_regex( '^/entry/(?:(.+)/)?(\d+)/edit$', \&edit_handler, app => 1 );

DW::Routing->register_string( '/entry/new', \&_new_handler_userspace, user => 1 );

# redirect to app-space
sub _user_to_app_role {
    my ( $path ) = @_;
    return DW::Request->get->redirect( LJ::create_url( $path, host => $LJ::DOMAIN_WEB ) );
}

sub _new_handler_userspace { return _user_to_app_role( "/entry/$_[0]->{username}/new" ) }

=head2 C<< DW::Controller::Entry::new_handler( ) >>

Handles posting a new entry

=cut
sub new_handler {
    my ( $call_opts, $usejournal ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $remote = $rv->{remote};

    # these kinds of errors prevent us from initializing the form at all
    # so abort and return it without the form
    if ( $remote ) {
        return error_ml( "/entry/form.tt.error.nonusercantpost", { sitename => $LJ::SITENAME } )
                if $remote->is_identity;

        return error_ml( "/entry/form.tt.error.cantpost" )
                unless $remote->can_post;

        return error_ml( '/entry/form.tt.error.disabled' )
                if $remote->can_post_disabled;
    }


    my $errors = DW::FormErrors->new;
    my $warnings = DW::FormErrors->new;
    my $post = $r->did_post ? $r->post_args : undef;
    my %spellcheck;

    # figure out times
    my $datetime;
    my $trust_datetime_value = 0;

    if ( $post && $post->{entrytime_date} && $post->{entrytime_time} ) {
        $datetime = "$post->{entrytime_date} $post->{entrytime_time}";
        $trust_datetime_value = 1;
    } else {
        my $now = DateTime->now;

        # if user has timezone, use it!
        if ( $remote && $remote->prop( "timezone" ) ) {
            my $tz = $remote->prop( "timezone" );
            $tz = $tz ? eval { DateTime::TimeZone->new( name => $tz ); } : undef;
            $now = eval { DateTime->from_epoch( epoch => time(), time_zone => $tz ); }
               if $tz;
        }

        $datetime = $now->strftime( "%F %R" ),
        $trust_datetime_value = 0;  # may want to override with client-side JS
    }

    # crosspost account selected?
    my %crosspost;
    if ( ! $r->did_post && $remote ) {
        %crosspost = map { $_->acctid => $_->xpostbydefault }
            DW::External::Account->get_external_accounts( $remote )
    }

    my $get = $r->get_args;
    $usejournal ||= $get->{usejournal};
    my $vars = _init( { usejournal  => $usejournal,
                        remote      => $remote,

                        datetime    => $datetime || "",
                        trust_datetime_value => $trust_datetime_value,

                        crosspost => \%crosspost,
                      }, @_ );

    # now look for errors that we still want to recover from
    $errors->add( undef, ".error.invalidusejournal" )
        if defined $usejournal && ! $vars->{usejournal};

    if ( $r->did_post ) {
        my $mode_preview    = $post->{"action:preview"} ? 1 : 0;
        my $mode_spellcheck = $post->{"action:spellcheck"} ? 1 : 0;

        $errors->add( undef, 'bml.badinput.body1' )
            unless LJ::text_in( $post );

        my $okay_formauth = ! $remote || LJ::check_form_auth( $post->{lj_form_auth} );

        $errors->add( undef, "error.invalidform" )
            unless $okay_formauth;

        if ( $mode_preview ) {
            # do nothing
        } elsif ( $mode_spellcheck ) {
            if ( $LJ::SPELLER ) {
                my $spellchecker = LJ::SpellCheck-> new( {
                                    spellcommand => $LJ::SPELLER,
                                    class        => "searchhighlight",
                                } );
                my $event = $post->{event};
                $spellcheck{results} = $spellchecker->check_html( \$event, 1 );
                $spellcheck{did_spellcheck} = 1;
            }
        } elsif ( $okay_formauth && $post->{showform} ) {  # some other form posted content to us, which the user will want to edit further

        } elsif ( $okay_formauth ) {
            my $flags = {};

            my %auth = _auth( $flags, $post, $remote );

            my $uj = $auth{journal};
            $errors->add_string( undef, $LJ::MSG_READONLY_USER )
                if $uj && $uj->readonly;

            # do a login action to check if we can authenticate as unverified_username
            # and to display any important messages connected to your account
            {
                # build a clientversion string
                my $clientversion = "Web/3.0.0";

                # build a request object
                my %login_req = (
                    ver             => $LJ::PROTOCOL_VER,
                    clientversion   => $clientversion,
                    username        => $auth{unverified_username},
                );

                my $err;
                my $login_res = LJ::Protocol::do_request( "login", \%login_req, \$err, $flags );

                unless ( $login_res ) {
                    $errors->add( undef, ".error.login",
                        { error => LJ::Protocol::error_message( $err ) } );
                }

                # e.g. not validated
                $warnings->add_string( undef, LJ::auto_linkify( LJ::ehtml( $login_res->{message} ) ) )
                    if $login_res->{message};
            }

            my $form_req = {};
            _form_to_backend( $form_req, $post, errors => $errors );

            # if we didn't have any errors with decoding the form, proceed to post
            unless ( $errors->exist ) {
                my %post_res = _do_post( $form_req, $flags, \%auth, warnings => $warnings );
                return $post_res{render} if $post_res{status} eq "ok";

                # oops errors when posting: show error, fall through to show form
                $errors->add_string( undef, $post_res{errors} ) if $post_res{errors};
            }
        }
    }


    # this is an error in the user-submitted data, so regenerate the form with the error message and previous values
    $vars->{errors} = $errors;
    $vars->{warnings} = $warnings;

    $vars->{spellcheck} = \%spellcheck;

    # prepopulate if we haven't been through this form already
    $vars->{formdata} = $post || _prepopulate( $get );

    $vars->{editable} = { map { $_ => 1 } @modules };

    # we don't need this JS magic if we are sending everything over SSL
    $vars->{usessl} = $LJ::IS_SSL;
    if ( ! $LJ::IS_SSL && ! $remote ) {
        $vars->{login_chal} = LJ::challenge_generate( 3600 ); # one hour to post if they're not logged in
    }

    $vars->{action} = {
        url  => LJ::create_url( undef, keep_args => 1 ),
    };

    return DW::Template->render_template( 'entry/form.tt', $vars );
}


# Initializes entry form values.
# Can be used when posting a new entry or editing an old entry.
# Arguments:
# * form_opts: options for initializing the form
#       usejournal    string: username of the journal we're posting to (if not provided,
#                        use journal of the user we're posting as)
#       datetime      string: display date of the entry in format "$year-$mon-$mday $hour:$min" (already taking into account timezones)
# * call_opts: instance of DW::Routing::CallInfo (currently unused)
sub _init {
    my ( $form_opts, $call_opts ) = @_;

    my $u = $form_opts->{remote};
    my $vars = {};

    my @icons;
    my $defaulticon;

    my %moodtheme;
    my @moodlist;
    my $moods = DW::Mood->get_moods;

    # we check whether the user can actually post to this journal on form submission
    # journal we explicitly say we want to post to
    my $usejournal = LJ::load_user( $form_opts->{usejournal} );
    my @journallist;
    push @journallist, $usejournal if LJ::isu( $usejournal );

    # the journal we are actually posting to (whether implicitly or overriden by usejournal)
    my $journalu = LJ::isu( $usejournal ) ? $usejournal : $u;

    my @crosspost_list;
    my $crosspost_main = 0;
    my %crosspost_selected = %{ $form_opts->{crosspost} || {} };

    my $panels;
    my $formwidth;
    my $min_animation;
    my $displaydate_check;
    if ( $u ) {
        # icons
        @icons = grep { ! ( $_->inactive || $_->expunged ) } LJ::Userpic->load_user_userpics( $u );

        @icons = LJ::Userpic->separate_keywords( \@icons )
            if @icons;

        $defaulticon = $u->userpic;


        # moods
        my $theme = DW::Mood->new( $u->{moodthemeid} );

        if ( $theme ) {
            $moodtheme{id} = $theme->id;
            foreach my $mood ( values %$moods )  {
                $theme->get_picture( $mood->{id}, \ my %pic );
                next unless keys %pic;

                $moodtheme{pics}->{$mood->{id}}->{pic} = $pic{pic};
                $moodtheme{pics}->{$mood->{id}}->{width} = $pic{w};
                $moodtheme{pics}->{$mood->{id}}->{height} = $pic{h};
                $moodtheme{pics}->{$mood->{id}}->{name} = $mood->{name};
            }
        }

        @journallist = ( $u, $u->posting_access_list )
            unless $usejournal;

        # crosspost
        my @accounts = DW::External::Account->get_external_accounts( $u );
        if ( scalar @accounts ) {
            foreach my $acct ( @accounts ) {
                my $id = $acct->acctid;

                my $selected = $crosspost_selected{$id};

                push @crosspost_list, {
                    id          => $id,
                    name        => $acct->displayname,
                    selected    => $selected,
                    need_password => $acct->password ? 0 : 1,
                };

                $crosspost_main = 1 if $selected;
            }
        }

        $panels = $u->entryform_panels;
        $formwidth = $u->entryform_width;
        $min_animation = $u->prop( "js_animations_minimal" ) ? 1 : 0;
        $displaydate_check = ( $u->displaydate_check && not $form_opts->{trust_datetime_value}) ? 1 : 0;
    } else {
        $panels = LJ::User::default_entryform_panels( anonymous => 1 );
    }

    @moodlist = ( { id => "", name => LJ::Lang::ml( "entryform.mood.noneother" ) } );
    push @moodlist, { id => $_, name => $moods->{$_}->{name} }
        foreach sort { $moods->{$a}->{name} cmp $moods->{$b}->{name} } keys %$moods;

    my %security_options = (
        "public" => {
            value => "public",
            label => ".public.label",
            format => ".public.format",
        },
        "private" => {
            value => "private",
            label => ".private.label",
            format => ".private.format",
            image => $LJ::Img::img{"security-private"},
        },
        "admin" => {
            value => "private",
            label => ".admin.label",
            format => ".private.format",
            image => $LJ::Img::img{"security-private"},
        },
        "access" => {
            value => "access",
            label => ".access.label",
            format => ".access.format",
            image => $LJ::Img::img{"security-protected"},
        },
        "members" => {
            value => "access",
            label => ".members.label",
            format => ".members.format",
            image => $LJ::Img::img{"security-protected"},
        },
        "custom" => {
            value => "custom",
            label => ".custom.label",
            format => ".custom.format",
            image => $LJ::Img::img{"security-groups"},
        }
    );
    foreach my $data ( values %security_options ) {
        my $prefix = ".select.security";

        $data->{label} = $prefix . $data->{label};
        $data->{format} = $prefix . $data->{format};
    }

    my $is_community = $journalu && $journalu->is_community;
    my @security = $is_community ? qw( public members admin ) : qw( public access private );
    my @custom_groups;
    if ( $u && ! $is_community ) {
        @custom_groups = map { { value => $_->{groupnum}, label => $_->{groupname} } } $u->trust_groups;
        push @security, "custom" if @custom_groups;
    }
    @security = map { $security_options{$_} } @security;

    my ( $year, $mon, $mday, $hour, $min ) = split( /\D/, $form_opts->{datetime} || "" );
    my %displaydate;
    $displaydate{year}  = $year;
    $displaydate{month} = $mon;
    $displaydate{day}   = $mday;
    $displaydate{hour}  = $hour;
    $displaydate{minute}   = $min;

    $displaydate{trust_initial} = $form_opts->{trust_datetime_value};

# TODO:
#             # JavaScript sets this value, so we know that the time we get is correct
#             # but always trust the time if we've been through the form already
#             my $date_diff = ($opts->{'mode'} eq "edit" || $opts->{'spellcheck_html'}) ? 1 : 0;

    $vars = {
        remote => $u,

        icons       => @icons ? [ { userpic => $defaulticon }, @icons ] : [],
        defaulticon => $defaulticon,

        icon_browser => {
            metatext => $u ? $u->iconbrowser_metatext : "",
            smallicons => $u ? $u->iconbrowser_smallicons : "",
        },

        moodtheme => \%moodtheme,
        moods     => \@moodlist,

        journallist => \@journallist,
        usejournal  => $usejournal,

        security     => \@security,
        customgroups => \@custom_groups,
        security_options => \%security_options,

        journalu    => $journalu,

        crosspost_entry => $crosspost_main,
        crosspostlist => \@crosspost_list,
        crosspost_url => "$LJ::SITEROOT/manage/settings/?cat=othersites",

        sticky_url => "$LJ::SITEROOT/manage/settings/?cat=display#DW__Setting__StickyEntry_",
        sticky_entry => $form_opts->{sticky_entry},

        displaydate => \%displaydate,
        displaydate_check => $displaydate_check,


        can_spellcheck => $LJ::SPELLER,

        panels      => $panels,
        formwidth   => $formwidth && $formwidth eq "P" ? "narrow" : "wide",
        min_animation => $min_animation ? 1 : 0,

        limits => {
            subject_length => LJ::CMAX_SUBJECT,
        },

        # TODO: Remove this when beta is over
        betacommunity => LJ::load_user( "dw_beta" ),
    };

    return $vars;
}

=head2 C<< DW::Controller::Entry::edit_handler( ) >>

Handles generating the form for, and handling the actual edit of an entry

=cut
sub edit_handler {
    return _edit(@_);
}

sub _edit {
    my ( $opts, $username, $ditemid ) = @_;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $remote = $rv->{remote};
    my $journal = defined $username ? LJ::load_user( $username ) : $remote;

    return error_ml( 'error.invalidauth' ) unless $journal;

    my $errors = DW::FormErrors->new;
    my $warnings = DW::FormErrors->new;
    my $post;
    my %spellcheck;

    if ( $r->did_post ) {
        $post = $r->post_args;

        # no difference because we rely on the entry info, but let's get rid of this
        # just to make sure it doesn't trip us up in the future...
        $post->remove( 'poster_remote' );
        $post->remove( 'usejournal' );


        my $mode_preview    = $post->{"action:preview"} ? 1 :0;
        my $mode_spellcheck = $post->{"action:spellcheck"} ? 1 : 0;
        my $mode_delete     = $post->{"action:delete"} ? 1 : 0;

        $errors->add( undef, 'bml.badinput.body1' )
            unless LJ::text_in( $post );


        my $okay_formauth =  LJ::check_form_auth( $post->{lj_form_auth} );
        $errors->add( undef, "error.invalidform" )
            unless $okay_formauth;

        if ( $mode_preview ) {
            # do nothing
        } elsif ( $mode_spellcheck ) {
            if ( $LJ::SPELLER ) {
                my $spellchecker = LJ::SpellCheck-> new( {
                                    spellcommand => $LJ::SPELLER,
                                    class        => "searchhighlight",
                                } );
                my $event = $post->{event};
                $spellcheck{results} = $spellchecker->check_html( \$event, 1 );
                $spellcheck{did_spellcheck} = 1;
            }
        } elsif ( $okay_formauth ) {
            $errors->add_string( undef, $LJ::MSG_READONLY_USER )
                if $journal && $journal->readonly;

            my $form_req = {};
            _form_to_backend( $form_req, $post,
                allow_empty => $mode_delete, errors => $errors );

            # if we didn't have any errors with decoding the form, proceed to post
            unless ( $errors->exist ) {

                if ( $mode_delete ) {
                    $form_req->{event} = "";

                    # now log the event created above
                    $journal->log_event('delete_entry', {
                            remote => $remote,
                            actiontarget => $ditemid,
                            method => 'web',
                    });

                }

                my %edit_res = _do_edit(
                        $ditemid,
                        $form_req,
                        { remote => $remote, journal => $journal },
                        warnings => $warnings,
                        );
                return $edit_res{render} if $edit_res{status} eq "ok";

                # oops errors when posting: show error, fall through to show form
                $errors->add_string( undef, $edit_res{errors} ) if $edit_res{errors};
            }
        }
    }

    # we can always trust this value:
    # it either came straight from the entry
    # or it's from the user's POST
    my $trust_datetime_value = 1;

    my $entry_obj = LJ::Entry->new( $journal, ditemid => $ditemid );

    # are you authorized to view this entry
    # and does the entry we got match the provided ditemid exactly?
    my $anum = $ditemid % 256;
    my $itemid = $ditemid >> 8;
    return error_ml( "/entry/form.tt.error.nofind" )
        unless $entry_obj->editable_by( $remote )
            && $anum == $entry_obj->anum && $itemid == $entry_obj->jitemid;

    # so at this point, we know that we are authorized to edit this entry
    # but we need to handle things differently if we're an admin
    # FIXME: handle communities
    return error_ml( 'IS AN ADMIN' ) unless $entry_obj->poster->equals( $remote );

    my %crosspost;
    if ( ! $r->did_post && ( my $xpost = $entry_obj->prop( "xpostdetail" ) ) )  {
        my $xposthash = DW::External::Account->xpost_string_to_hash( $xpost );

        %crosspost = map { $_ => 1 } keys %{ $xposthash || {} };
    }

    my $vars = _init( { usejournal  => $journal->username,
                        remote      => $remote,

                        datetime => $entry_obj->eventtime_mysql,
                        trust_datetime_value => $trust_datetime_value,

                        crosspost => \%crosspost,
                        sticky_entry => $journal->sticky_entries_lookup->{$ditemid},
                      }, @_ );

    # now look for errors that we still want to recover from
    my $get = $r->get_args;
    $errors->add( undef, ".error.invalidusejournal" )
        if defined $get->{usejournal} && ! $vars->{usejournal};

    # this is an error in the user-submitted data, so regenerate the form with the error message and previous values
    $vars->{errors} = $errors;
    $vars->{warnings} = $warnings;

    $vars->{spellcheck} = \%spellcheck;


    $vars->{formdata} = $post || _backend_to_form( $entry_obj );

    my %editable = map { $_ => 1 } @modules;
    $vars->{editable} = \%editable;

    # this can't be edited after posting
    delete $editable{journal};

    $vars->{action} = {
        edit => 1,
        url  => LJ::create_url( undef, keep_args => 1 ),
    };

    return DW::Template->render_template( 'entry/form.tt', $vars );
}

# returns:
# poster: user object that contains the poster of the entry. may be the current remote user,
#           or may be someone logging in via the login form on the entry
# journal: user object for the journal the entry is being posted to. may be the same as the
#           poster, or may be a community
# unverified_username: username that current remote is trying to post as; remote may not
#           actually have access to this journal so don't treat as trusted
#
# modifies/sets:
# flags: hashref of flags for the protocol
#   noauth = 1 if the user is the same as remote or has authenticated successfully
#   u = user we're posting as

sub _auth {
    my ( $flags, $post, $remote, $referer ) = @_;
    # referer only should be passed in if outside web context, such as when running tests

    my %auth;
    foreach ( qw( username chal response password ) ) {
        $auth{$_} = $post->{$_} || "";
    }

    my %ret;

    if ( $auth{username}            # user argument given
        && ! $remote            ) { # user not logged in

        my $u = LJ::load_user( $auth{username} );

        my $ok;
        my $hashed_password = $auth{response} ||
                                # js disabled, fallback to plaintext
                                Digest::MD5::md5_hex($auth{chal} . Digest::MD5::md5_hex($auth{password}));
        # verify entered password, if it is present
        $ok = LJ::challenge_check_login( $u, $auth{chal}, $hashed_password );

        if ( $ok ) {
            $flags->{noauth} = 1;
            $flags->{u} = $u;

            $ret{poster} = $u;
            $ret{journal} = $post->{usejournal} ? LJ::load_user( $post->{usejournal} ) : $u;
        }
    } elsif ( $remote && LJ::check_referer( undef, $referer ) ) {
        $flags->{noauth} = 1;
        $flags->{u} = $remote;

        $ret{poster} = $remote;
        $ret{journal} = $post->{usejournal} ? LJ::load_user( $post->{usejournal} ) : $remote;
    }

    $ret{unverified_username} = $ret{poster} ? $ret{poster}->username : $auth{username};
    return %ret;
}

# decodes the posted form into a hash suitable for use with the protocol
# $post is expected to be an instance of Hash::MultiValue
sub _form_to_backend {
    my ( $req, $post, %opts ) = @_;

    my $errors = $opts{errors};

    # handle event subject and body
    $req->{subject} = $post->{subject};
    $req->{event} = $post->{event} || "";

    $errors->add( undef, ".error.noentry" )
        if $errors && $req->{event} eq "" && ! $opts{allow_empty};


    # initialize props hash
    $req->{props} ||= {};
    my $props = $req->{props};

    while ( my ( $formname, $propname ) = each %form_to_props ) {
        $props->{$propname} = $post->{$formname}
            if defined $post->{$formname};
    }
    $props->{taglist} = $post->{taglist} if defined $post->{taglist};
    $props->{picture_keyword} = $post->{icon} if defined $post->{icon};
    $props->{opt_backdated} = $post->{entrytime_outoforder} ? 1 : 0;
    # FIXME
    $props->{opt_preformatted} = 0;
#     $req->{"prop_opt_preformatted"} ||= $POST->{'switched_rte_on'} ? 1 :
#         $POST->{event_format} && $POST->{event_format} eq "preformatted" ? 1 : 0;

    # old implementation of comments
    # FIXME: remove this before taking the page out of beta
    $props->{opt_screening}  = $post->{opt_screening};
    $props->{opt_nocomments} = $post->{comment_settings} && $post->{comment_settings} eq "nocomments" ? 1 : 0;
    $props->{opt_noemail}    = $post->{comment_settings} && $post->{comment_settings} eq "noemail" ? 1 : 0;


    # see if an "other" mood they typed in has an equivalent moodid
    if ( $props->{current_mood} ) {
        if ( my $moodid = DW::Mood->mood_id( $props->{current_mood} ) ) {
            $props->{current_moodid} = $moodid;
            delete $props->{current_mood};
        }
    }

    # nuke taglists that are just blank
    $props->{taglist} = "" unless $props->{taglist} && $props->{taglist} =~ /\S/;

    if ( LJ::is_enabled( 'adult_content' ) ) {
        my $restriction_key = $post->{age_restriction} || '';
        $props->{adult_content} = {
            ''              => '',
            'none'          => 'none',
            'discretion'    => 'concepts',
            'restricted'    => 'explicit',
        }->{$restriction_key} || "";

        $props->{adult_content_reason} = $post->{age_restriction_reason} || "";
    }

    # Set entry slug if it's been specified
    $req->{slug} = LJ::canonicalize_slug( $post->{entry_slug} // '' );

    # Check if this is a community.
    $props->{admin_post} = $post->{flags_adminpost} || 0;

    # entry security
    my $sec = "public";
    my $amask = 0;
    {
        my $security = $post->{security} || "";
        if ( $security eq "private" ) {
            $sec = "private";
        } elsif ( $security eq "access" ) {
            $sec = "usemask";
            $amask = 1;
        } elsif ( $security eq "custom" ) {
            $sec = "usemask";
            foreach my $bit ( $post->get_all( "custom_bit" ) ) {
                $amask |= (1 << $bit);
            }
        }
    }
    $req->{security} = $sec;
    $req->{allowmask} = $amask;


    # date/time
    my ( $year, $month, $day ) = split( /\D/, $post->{entrytime_date} || "" );
    my ( $hour, $min ) = split( /\D/, $post->{entrytime_time} || "" );

    # if we trust_datetime, it's because we either are in a mode where we've saved the datetime before (e.g., edit)
    # or we have run the JS that syncs the datetime with the user's current time
    # we also have to trust the datetime when the user has JS disabled, because otherwise we won't have any fallback value
    if ( $post->{trust_datetime} || $post->{nojs} ) {
        delete $req->{tz};
        $req->{year}    = $year;
        $req->{mon}     = $month;
        $req->{day}     = $day;
        $req->{hour}    = $hour;
        $req->{min}     = $min;
    }

    $req->{update_displaydate} = $post->{update_displaydate};

    # crosspost
    $req->{crosspost_entry} = $post->{crosspost_entry} ? 1 : 0;
    if ( $req->{crosspost_entry} ) {
        foreach my $acctid ( $post->get_all( "crosspost" ) ) {
            $req->{crosspost}->{$acctid} = {
                id          => $acctid,
                password    => $post->{"crosspost_password_$acctid"},
                chal        => $post->{"crosspost_chal_$acctid"},
                resp        => $post->{"crosspost_resp_$acctid"},
            };
        }
    }

    $req->{sticky_entry} = $post->{sticky_entry};

    return 1;
}

# given an LJ::Entry object, returns a hashref populated with data suitable for use in generating the form
sub _backend_to_form {
    my ( $entry ) = @_;

#             my $entry = {
#                 'usejournal' => $usejournal,
#                 'auth' => $auth,
#                 'richtext' => LJ::is_enabled('richtext'),
#                 'suspended' => $suspend_msg,
#                 'unsuspend_supportid' => $suspend_msg ? $entry_obj->prop("unsuspend_supportid") : 0,
#             };

    # direct translation of prop values to the form

    my %formprops = map { $_ => $entry->prop( $form_to_props{$_} ) } keys %form_to_props;

    # some properties aren't in the hash above, so go through them manually
    my %otherprops = (
        taglist => join( ', ', $entry->tags ),

        entrytime_outoforder => $entry->prop( "opt_backdated" ),

        age_restriction     =>  {
                                    ''          => '',
                                    'none'      => 'none',
                                    'concepts'  => 'discretion',
                                    'explicit'  => 'restricted',
                                }->{ $entry->prop( "adult_content" ) || '' },
        age_restriction_reason => $entry->prop( "adult_content_reason" ),

        entry_slug => $entry->slug,

        flags_adminpost => $entry->prop("admin_post"),

        # FIXME:
        # ...       => $entry->prop( "opt_preformatted" )

        # FIXME: remove before taking the page out of beta
        opt_screening       => $entry->prop( "opt_screening" ),
        comment_settings    => $entry->prop( "opt_nocomments" ) ? "nocomments"
                            :  $entry->prop( "opt_noemail" ) ? "noemail"
                            : undef,
    );


    my $security = $entry->security || "";
    my @custom_groups;
    if ( $security eq "usemask" ) {
        my $amask = $entry->allowmask;

        if ( $amask == 1 ) {
            $security = "access";
        } else {
            $security = "custom";
            @custom_groups = grep { $amask & ( 1 << $_ ) } 1..60;
        }
    }

    # allow editing of embedded content
    my $event = $entry->event_raw;
    my $ju = $entry->journal;
    LJ::EmbedModule->parse_module_embed( $ju, \$event, edit => 1 );

    return {
        subject => $entry->subject_raw,
        event   => $event,

        icon        => $entry->userpic_kw,
        security    => $security,
        custom_bit  => \@custom_groups,
        is_sticky   => $entry->journal->sticky_entries_lookup->{$entry->ditemid},

        %formprops,
        %otherprops,
    };
}

sub _queue_crosspost {
    my ( $form_req, %opts ) = @_;

    my $u = delete $opts{remote};
    my $ju = delete $opts{journal};
    my $deleted = delete $opts{deleted};
    my $editurl = delete $opts{editurl};
    my $ditemid = delete $opts{ditemid};

    my @crossposts;
    if ( $u->equals( $ju ) && $form_req->{crosspost_entry} ) {
        my $user_crosspost = $form_req->{crosspost};
        my ( $xpost_successes, $xpost_errors ) =
            LJ::Protocol::schedule_xposts( $u, $ditemid, $deleted,
                    sub {
                        my $submitted = $user_crosspost->{$_[0]->acctid} || {};

                        # first argument is true if user checked the box
                        # false otherwise
                        return ( $submitted->{id} ? 1 : 0,
                            {
                                password => $submitted->{password},
                                auth_challenge => $submitted->{chal},
                                auth_response => $submitted->{resp},
                            }
                        );
                    } );

        foreach my $crosspost ( @{$xpost_successes||[]} ) {
            push @crossposts, { text => LJ::Lang::ml( "xpost.request.success2", {
                                            account => $crosspost->displayname,
                                            sitenameshort => $LJ::SITENAMESHORT,
                                        } ),
                                status => "ok",
                            };
        }

        foreach my $crosspost( @{$xpost_errors||[]} ) {
            push @crossposts, { text => LJ::Lang::ml( 'xpost.request.failed', {
                                                account => $crosspost->displayname,
                                                editurl => $editurl,
                                            } ),
                                status => "error",
                             };
        }
    }

    return @crossposts;
}

sub _save_new_entry {
    my ( $form_req, $flags, $auth ) = @_;

    my $req = {
        ver         => $LJ::PROTOCOL_VER,
        username    => $auth->{poster} ? $auth->{poster}->user : undef,
        usejournal  => $auth->{journal} ? $auth->{journal}->user : undef,
        tz          => 'guess',
        xpost       => '0', # don't crosspost by default; we handle this ourselves later
        %$form_req
    };


    my $err = 0;
    my $res = LJ::Protocol::do_request( "postevent", $req, \$err, $flags );

    return { errors => LJ::Protocol::error_message( $err ) } unless $res;
    return $res;
}

# helper sub for printing success messages when posting or editing
sub _get_extradata {
    my ( $form_req, $journal ) = @_;
    my $extradata = {
        security_ml => "",
        filters => "",
    };

    # use the HTML cleaner on the entry subject if one exists
    my $subject = $form_req->{subject};
    LJ::CleanHTML::clean_subject( \$subject ) if $subject;
    $extradata->{subject} = $subject;

    my $c_or_p = $journal->is_community ? 'c' : 'p';

    if ( $form_req->{security} eq "usemask" ) {
        if ( $form_req->{allowmask} == 1 ) { # access list
            $extradata->{security_ml} = "post.security.access.$c_or_p";
        } elsif ( $form_req->{allowmask} > 1 ) { # custom group
            $extradata->{security_ml} = "post.security.custom";
            $extradata->{filters} = $journal->security_group_display( $form_req->{allowmask} );
        } else { # custom security with no group - essentially private
            $extradata->{security_ml} = "post.security.private.$c_or_p";
        }
    } elsif ( $form_req->{security} eq "private" ) {
        $extradata->{security_ml} = "post.security.private.$c_or_p";
    } else { #public
        $extradata->{security_ml} = "post.security.public";
    }

    return $extradata;
}

sub _do_post {
    my ( $form_req, $flags, $auth, %opts ) = @_;

    my $res = _save_new_entry( $form_req, $flags, $auth );
    return %$res if $res->{errors};

    # post succeeded, time to do some housecleaning
    _persist_props( $auth->{poster}, $form_req, 0 );

    my $render_ret;
    my @links;

    # we may have warnings generated by previous parts of the process
    my $warnings = $opts{warnings} || DW::FormErrors->new;

    # special-case moderated: no itemid, but have a message
    if ( ! defined $res->{itemid} && $res->{message} ) {
        $render_ret = DW::Template->render_template(
            'entry/success.tt', {
                moderated_message  => $res->{message},
            }
        );
    } else {
        # e.g., bad HTML in the entry
        $warnings->add_string( undef, LJ::auto_linkify( LJ::ehtml( $res->{message} ) ) )
            if $res->{message};

        my $u = $auth->{poster};
        my $ju = $auth->{journal} || $auth->{poster};

        # we updated successfully! Now tell the user
        my $poststatus = {
            ml_string => $ju->is_community ? ".new.community" : ".new.journal",
            url => $ju->journal_base . "/",
        };

        # bunch of helpful links
        my $juser = $ju->user;
        my $ditemid = $res->{itemid} * 256 + $res->{anum};
        my $itemlink = $res->{url};
        my $edititemlink = "$LJ::SITEROOT/entry/$juser/$ditemid/edit";

        my @links = (
            { url => $itemlink,
                ml_string => ".new.links.view" }
        );

        push @links, (
            { url => $edititemlink,
                ml_string => ".new.links.edit" },
            { url => "$LJ::SITEROOT/tools/memadd?journal=$juser&itemid=$ditemid",
                ml_string => ".new.links.memories" },
            { url => "$LJ::SITEROOT/edittags?journal=$juser&itemid=$ditemid",
                ml_string => ".new.links.tags" },
        );

        push @links, { url => $ju->journal_base . "?poster=" . $auth->{poster}->user,
                        ml_string => ".new.links.myentries" } if $ju->is_community;


        # crosspost!
        my @crossposts = _queue_crosspost( $form_req,
                remote => $u,
                journal => $ju,
                deleted => 0,
                editurl => $edititemlink,
                ditemid => $ditemid,
        );

        # set sticky
        if ( $form_req->{sticky_entry} && $u->can_manage( $ju ) ) {
            my $added_sticky = $ju->sticky_entry_new( $ditemid );
            $warnings->add( '', '.sticky.max', { limit => $u->count_max_stickies } ) unless $added_sticky;
        }

        $render_ret = DW::Template->render_template(
            'entry/success.tt', {
                poststatus  => $poststatus, # did the update succeed or fail?
                warnings    => $warnings,   # warnings about the entry or your account
                crossposts  => \@crossposts,# crosspost status list
                links       => \@links,
                links_header => ".new.links",
                extradata   => _get_extradata( $form_req, $ju ),
            }
        );
    }

    return ( status => "ok", render => $render_ret );
}

sub _save_editted_entry {
    my ( $ditemid, $form_req, $auth ) = @_;

    my $req = {
        ver         => $LJ::PROTOCOL_VER,
        username    => $auth->{remote} ? $auth->{remote}->user : undef,
        usejournal  => $auth->{journal} ? $auth->{journal}->user : undef,
        xpost       => '0', # don't crosspost by default; we handle this ourselves later
        itemid      => $ditemid >> 8,
        %$form_req
    };

    my $err = 0;
    my $res = LJ::Protocol::do_request( "editevent", $req, \$err, {
            noauth => 1,
            u =>  $auth->{remote},
        } );

    return { errors => LJ::Protocol::error_message( $err ) } unless $res;
    return $res;
}

sub _do_edit {
    my ( $ditemid, $form_req, $auth, %opts ) = @_;

    my $res = _save_editted_entry( $ditemid, $form_req, $auth );
    return %$res if $res->{errors};

    my $remote = $auth->{remote};
    my $journal = $auth->{journal};

    my $deleted = $form_req->{event} ? 0 : 1;

    # post succeeded, time to do some housecleaning
    _persist_props( $remote, $form_req, 1 );

    my $poststatus_ml;
    my $render_ret;
    my @links;

    # we may have warnings generated by previous parts of the process
    my $warnings = $opts{warnings} || DW::FormErrors->new;

    # e.g., bad HTML in the entry
    $warnings->add_string( undef, LJ::auto_linkify( LJ::html_newlines( LJ::ehtml( $res->{message} ) ) ) )
        if $res->{message};

    # bunch of helpful links:
    my $juser = $journal->user;
    my $entry_url = $res->{url};
    my $edit_url = "$LJ::SITEROOT/entry/$juser/$ditemid/edit";

    my $is_sticky_entry = $journal->sticky_entries_lookup->{$ditemid};
    if ( $remote->can_manage( $journal ) ) {
        if ( $form_req->{sticky_entry} ) {
            $journal->sticky_entry_new( $ditemid )
                unless $is_sticky_entry;
        } elsif ( $form_req->{sticky_select} ) {
            $journal->sticky_entry_remove( $ditemid )
                if $is_sticky_entry;
        }
    }

    if ( $deleted ) {
        $poststatus_ml = ".edit.delete";

        $journal->sticky_entry_remove( $ditemid )
            if $is_sticky_entry && $remote->can_manage( $journal );
    } else {
        $poststatus_ml = ".edit.edited";

        push @links, {
            url => $entry_url,
            ml_string => ".edit.links.viewentry",
        };

        push @links, {
            url => $edit_url,
            ml_string => ".edit.links.editentry",
        };

    }

    push @links, ( {
        url => $journal->journal_base,
        ml_string => '.edit.links.viewentries',
    }, {
        url => "$LJ::SITEROOT/editjournal",
        ml_string => '.edit.links.manageentries',
    } );

    my @crossposts = _queue_crosspost( $form_req,
        remote => $remote,
        journal => $journal,
        deleted => $deleted,
        ditemid => $ditemid,
        editurl => $edit_url,
    );

    my $poststatus = { ml_string => $poststatus_ml };
    $render_ret = DW::Template->render_template(
        'entry/success.tt', {
            poststatus  => $poststatus, # did the update succeed or fail?
            warnings    => $warnings,   # warnings about the entry or your account
            crossposts  => \@crossposts,# crosspost status list
            links       => \@links,
            links_header => '.edit.links',
            extradata   => _get_extradata( $form_req, $journal ),
        }
    );

    return ( status => "ok", render => $render_ret );
}

# remember value of properties, to use the next time the user makes a post
sub _persist_props {
    my ( $u, $form, $is_edit ) = @_;

    return unless $u;

    $u->displaydate_check($form->{update_displaydate} ? 1 : 0) unless $is_edit;
# FIXME:
#
#                 # persist the default value of the disable auto-formatting option
#                 $u->disable_auto_formatting( $POST{event_format} ? 1 : 0 );
#
#                 # Clear out a draft
#                 $remote->set_prop('entry_draft', '')
#                     if $remote;
#
#                 # Store what editor they last used
#                 unless (!$remote || $remote->prop('entry_editor') =~ /^always_/) {
#                      $POST{'switched_rte_on'} ?
#                          $remote->set_prop('entry_editor', 'rich') :
#                          $remote->set_prop('entry_editor', 'plain');
#                  }

}

sub _prepopulate {
    my $get = $_[0];

    my $subject = $get->{subject};
    my $event   = $get->{event};
    my $tags    = $get->{tags};

    # if a share url was passed in, fill in the fields with the appropriate text
    if ( $get->{share} ) {
        eval "use DW::External::Page; 1;";
        if ( ! $@ && ( my $page = DW::External::Page->new( url => $get->{share} ) ) ) {
            $subject = LJ::ehtml( $page->title );
            $event = '<a href="' . $page->url . '">' . ( LJ::ehtml( $page->description ) || $subject || $page->url ) . "</a>\n\n";
        }
    }

    return {
        subject => $subject,
        event   => $event,
        taglist => $tags,
    };
}


=head2 C<< DW::Controller::Entry::preview_handler( ) >>

Shows a preview of this entry

=cut
sub preview_handler {
    my $r = DW::Request->get;
    my $remote = LJ::get_remote();

    my $post = $r->post_args;
    my $styleid;
    my $siteskinned = 1;

    my $username = $remote ? $remote->username : $post->{username};
    my $usejournal = $post->{usejournal};

    # figure out poster/journal
    my ( $u, $up );
    if ( $usejournal ) {
        $u = LJ::load_user( $usejournal );
        $up = $username ? LJ::load_user( $username ) : $remote;
    } elsif ( ! $remote && $username ) {
        $u = LJ::load_user( $username );
    } else {
        $u = $remote;
    }
    $up ||= $u;

    # set up preview variables
    my ( $ditemid, $anum, $itemid );

    my $form_req = {};
    _form_to_backend( $form_req, $post );

    my ( $event, $subject ) = ( $form_req->{event}, $form_req->{subject} );
    LJ::CleanHTML::clean_subject( \$subject );

    # preview poll
    if ( LJ::Poll->contains_new_poll( \$event ) ) {
        my $error;
        my @polls = LJ::Poll->new_from_html( \$event, \$error, {
            'journalid' => $u->userid,
            'posterid' => $up->userid,
        });

        my $can_create_poll = $up->can_create_polls || ( $u->is_community && $u->can_create_polls );
        my $poll_preview = sub {
            my $poll = shift @polls;
            return '' unless $poll;
            return $can_create_poll ? $poll->preview : qq{<div class="highlight-box">} . LJ::Lang::ml( '/poll/create.bml.error.accttype2' ) . qq{</div>};
        };

        $event =~ s/<poll-placeholder>/$poll_preview->()/eg;
    }

    # expand existing polls (for editing, or when transferring polls to another entry)
    LJ::Poll->expand_entry( \$event );

    # parse out embed tags from the RTE
    $event = LJ::EmbedModule->transform_rte_post( $event );

    # do first expand_embedded pass with the preview flag to extract
    # embedded content before cleaning and replace with tags
    # the cleaner won't eat
    LJ::EmbedModule->parse_module_embed( $u, \$event, preview => 1 );

    # clean content normally
    LJ::CleanHTML::clean_event( \$event, {
        preformatted => $form_req->{props}->{opt_preformatted},
    } );

    # expand the embedded content for real
    LJ::EmbedModule->expand_entry($u, \$event, preview => 1 );


    my $ctx;
    if ( $u && $up ) {
        $r->note( "_journal"    => $u->{user} );
        $r->note( "journalid"   => $u->{userid} );

        # load necessary props
        $u->preload_props( qw( s2_style journaltitle journalsubtitle ) );

        # determine style system to preview with
        $ctx = LJ::S2::s2_context( $u->{s2_style} );
        my $view_entry_disabled = ! LJ::S2::use_journalstyle_entry_page( $u, $ctx );

        if ( $view_entry_disabled ) {
            # force site-skinned
            ( $siteskinned, $styleid ) = ( 1, 0 );
        } else {
            ( $siteskinned, $styleid ) = ( 0, $u->{s2_style} );
        }
    } else {
        ( $siteskinned, $styleid ) = ( 1, 0 );
    }


    if ( $siteskinned ) {
        my $vars = {
            event   => $event,
            subject => $subject,
            journal => $u,
            poster  => $up,
        };

        my $pic = LJ::Userpic->new_from_keyword( $up, $form_req->{props}->{picture_keyword} );
        $vars->{icon} = $pic ? $pic->imgtag : undef;


        my $date = "$form_req->{year}-$form_req->{mon}-$form_req->{day}";
        my $etime = $u ? LJ::date_to_view_links( $u, $date ) : $date;
        my $hour = sprintf( "%02d", $form_req->{hour} );
        my $min = sprintf( "%02d", $form_req->{min} );
        $vars->{displaydate} = "$etime $hour:$min:00";


        my %current = LJ::currents( $form_req->{props}, $up );
        if ( $u ) {
            $current{Groups} = $u->security_group_display( $form_req->{allowmask} );
            delete $current{Groups} unless $current{Groups};
        }

        my @taglist = ();
        LJ::Tags::is_valid_tagstring( $form_req->{props}->{taglist}, \@taglist );
        if ( @taglist ) {
            my $base = $u ? $u->journal_base : "";
            $current{Tags} = join( ', ',
                                   map { "<a href='$base/tag/" . LJ::eurl( $_ ) . "'>" . LJ::ehtml( $_ ) . "</a>" }
                                   @taglist
                               );
        }
        $vars->{currents} = LJ::currents_table( %current );

        my $security = "";
        if ( $form_req->{security} eq "private" ) {
            $security = $LJ::Img::img{"security-private"};
        } elsif ( $form_req->{security} eq "usemask" ) {
            $security = $form_req->{allowmask} > 1 ? $LJ::Img::img{"security-groups"}
                                                   : $LJ::Img::img{"security-protected"};
        }
        $vars->{security} = $security;

        return DW::Template->render_template( 'entry/preview.tt', $vars );
    } else {
        my $ret = "";
        my $opts = {};

        $LJ::S2::ret_ref = \$ret;
        $opts->{r} = $r;

        $u->{_s2styleid} = ( $styleid || 0 ) + 0;
        $u->{_journalbase} = $u->journal_base;

        $LJ::S2::CURR_CTX = $ctx;

        my $p = LJ::S2::Page( $u, $opts );
        $p->{_type} = "EntryPreviewPage";
        $p->{view} = "entry";


        # Mock up entry from form data
        my $userlite_journal = LJ::S2::UserLite( $u );
        my $userlite_poster  = LJ::S2::UserLite( $up );

        my $userpic = LJ::S2::Image_userpic( $up, 0, $form_req->{props}->{picture_keyword} );
        my $comments = LJ::S2::CommentInfo({
            read_url => "#",
            post_url => "#",
            permalink_url => "#",
            count => "0",
            maxcomments => 0,
            enabled => ( $u->{opt_showtalklinks} eq "Y"
                            && ! $form_req->{props}->{opt_nocomments} ) ? 1 : 0,
            screened => 0,
            });

        # build tag objects, faking kwid as '-1'
        # * invalid tags will be stripped by is_valid_tagstring()
        my @taglist = ();
        LJ::Tags::is_valid_tagstring( $form_req->{props}->{taglist}, \@taglist );
        @taglist = map { LJ::S2::Tag( $u, -1, $_ ) } @taglist;

        # custom friends groups
        my $group_names = $u ? $u->security_group_display( $form_req->{allowmask} ) : undef;

        # format it
        my $raw_subj = $form_req->{subject};
        my $s2entry = LJ::S2::Entry($u, {
            subject     => $subject,
            text        => $event,
            dateparts   => "$form_req->{year} $form_req->{mon} $form_req->{day} $form_req->{hour} $form_req->{min} 00 ",
            security    => $form_req->{security},
            allowmask   => $form_req->{allowmask},
            props       => $form_req->{props},
            itemid      => -1,
            comments    => $comments,
            journal     => $userlite_journal,
            poster      => $userlite_poster,
            new_day     => 0,
            end_day     => 0,
            tags        => \@taglist,
            userpic     => $userpic,
            permalink_url       => "#",
            adult_content_level => $form_req->{props}->{adult_content},
            group_names         => $group_names,
        });

        my $copts;
        $copts->{out_pages} = $copts->{out_page} = 1;
        $copts->{out_items} = 0;
        $copts->{out_itemfirst} = $copts->{out_itemlast} = undef;

        $p->{comment_pages} = LJ::S2::ItemRange({
            all_subitems_displayed  => ( $copts->{out_pages} == 1 ),
            current                 => $copts->{out_page},
            from_subitem            => $copts->{out_itemfirst},
            num_subitems_displayed  => 0,
            to_subitem              => $copts->{out_itemlast},
            total                   => $copts->{out_pages},
            total_subitems          => $copts->{out_items},
            _url_of                 => sub { return "#"; },
        });

        $p->{entry} = $s2entry;
        $p->{comments} = [];
        $p->{preview_warn_text} = LJ::Lang::ml( '/entry/preview.tt.entry.preview_warn_text' );

        $p->{viewing_thread} = 0;
        $p->{multiform_on} = 0;


        # page display settings
        if ( $u->should_block_robots ) {
            $p->{head_content} .= LJ::robot_meta_tags();
        }
        my $charset = $opts->{saycharset} // '';
        $p->{head_content} .= '<meta http-equiv="Content-Type" content="text/html; charset=' . $charset . "\" />\n";
        # Don't show the navigation strip or invisible content
        $p->{head_content} .= qq{
            <style type="text/css">
            html body {
                padding-top: 0 !important;
            }
            #lj_controlstrip {
                display: none !important;
            }
            .invisible {
                position: absolute;
                left: -10000px;
                top: auto;
            }
            .highlight-box {
                border: 1px solid #c1272c;
                background-color: #ffd8d8;
                color: #000;
            }
            </style>
        };


        LJ::S2::s2_run( $r, $ctx, $opts, "EntryPage::print()", $p );
        $r->print( $ret );
        return $r->OK;
    }
}


=head2 C<< DW::Controller::Entry::options_handler( ) >>

Show the entry options page in a separate page

=cut
sub options_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    return DW::Template->render_template( 'entry/options.tt', _options( $rv->{remote} ) );
}


=head2 C<< DW::Controller::Entry::options_rpc_handler( ) >>

Show the entry options page in a form suitable for loading via JS

=cut
sub options_rpc_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $vars = _options( $rv->{remote} );
    $vars->{use_js} = 1;

    my $r = DW::Request->get;
    $r->status( $vars->{errors} && $vars->{errors}->exist ? HTTP_BAD_REQUEST : HTTP_OK );

    return DW::Template->render_template( 'entry/options.tt', $vars, { fragment => 1 } );
}

=head2 C<< DW::Controller::Entry::collapse_rpc_handler( ) >>

Load or save entry form module header settings

=cut
sub collapse_rpc_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $u = $rv->{remote};
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my $module = $args->{id} || "";
    my $expand = $args->{expand} && $args->{expand} eq "true" ? 1 : 0;

    my $show = sub {
        $r->print( to_json( $u->entryform_panels_collapsed ) );
        return $r->OK;
    };

    if ( $module ) {
        my $is_collapsed = $u->entryform_panels_collapsed;

        # no further action needed
        return $show->() if $is_collapsed->{$module} && ! $expand;
        return $show->() if ! $is_collapsed->{$module} && $expand;

        if ( $expand ) {
            delete $is_collapsed->{$module};
        } else {
            $is_collapsed->{$module} = 1;
        }
        $u->entryform_panels_collapsed( $is_collapsed );

        return $show->();
    } else {
        # just view
        return $show->();
    }
}

sub _load_visible_panels {
    my $u = $_[0];

    my $user_panels = $u->entryform_panels;

    my @panels;
    foreach my $panel_group ( @{$user_panels->{order}} ) {
        foreach my $panel ( @$panel_group ) {
            push @panels, $panel if $user_panels->{show}->{$panel};
        }
    }

    return \@panels;
}

sub _options {
    my $u = $_[0];

    my $panel_element_name = "visible_panels";
    my @panel_options = map +{
                            label_ml    => "/entry/module-$_.tt.header",
                            panel_name  => $_,
                            id          => "panel_$_",
                            name        =>  $panel_element_name, }, @modules;

    my $vars = {
        panels => \@panel_options
    };

    my $r = DW::Request->get;
    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        my $post = $r->post_args;
        $vars->{formdata} = $post;

        if ( LJ::check_form_auth( $post->{lj_form_auth} ) ) {
            if ( $post->{reset_panels} ) {
                $vars->{formdata}->remove( "reset_panels" );
                $u->set_prop( "entryform_panels" => undef );
                $vars->{formdata}->set( $panel_element_name => @{_load_visible_panels( $u )||[]} );
            } else {
                $u->set_prop( entryform_width => $post->{entry_field_width} );

                my %panels;
                my %post_panels = map { $_ => 1 } $post->get_all( $panel_element_name );
                foreach my $panel ( @panel_options ) {
                    my $name = $panel->{panel_name};
                    $panels{$name} = $post_panels{$name} ? 1 : 0;
                }
                $u->entryform_panels_visibility( \%panels );


                my @columns;
                my $didpost_order = 0;
                foreach my $column_index ( 0...2 ) {
                    my @col;

                    foreach ( $post->get_all( "column_$column_index" ) ) {
                        my ( $order, $panel ) = m/(\d+):(.+)/;
                        $col[$order] = $panel;

                        $didpost_order = 1;
                    }

                    # remove any in-betweens in case we managed to skip a number in the order somehow
                    $columns[$column_index] = [ grep { $_ } @col];
                }
                $u->entryform_panels_order( \@columns ) if $didpost_order;
            }

            $u->set_prop( js_animations_minimal => $post->{minimal_animations} );
        } else {
            $errors->add( undef, "error.invalidform" );
        }

        $vars->{errors} = $errors;
    } else {

        my $default = {
            entry_field_width   => $u->entryform_width,
            minimal_animations  => $u->prop( "js_animations_minimal" ) ? 1 : 0,
        };

        $default->{$panel_element_name} = _load_visible_panels( $u );

        $vars->{formdata} = $default;
    }

    return $vars;
}

1;
