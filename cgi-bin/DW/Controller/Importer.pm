#!/usr/bin/perl
#
# DW::Controller::Importer
#
# Controller for the /tools/importer pages.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Importer;

use strict;
use warnings;

use DW::Routing;
use DW::Template;
use LJ::Hooks;

DW::Routing->register_string( '/tools/importer/erase', \&erase_handler,    app => 1 );
DW::Routing->register_string( '/tools/importer',       \&importer_handler, app => 1 );

sub importer_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $u      = $rv->{u};
    my $remote = $rv->{remote};
    my $authas = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $vars;

    $vars->{remote}             = $remote;
    $vars->{u}                  = $u;
    $vars->{allow_comm_imports} = $LJ::ALLOW_COMM_IMPORTS;
    $vars->{authas}             = $authas;
    $vars->{authas_html}		= $rv->{authas_html}
    my $depth = get_queue();

    $vars->{queue} = join( ', ', map { "$_: " . ( $depth->{ lc $_ } + 0 ) } sort keys %$depth );

    # if these aren't the same users, make sure we're allowed to do a community import
    unless ( $u->equals($remote) ) {
        return error_ml('/tools/importer/index.tt.error.cant_import_comm')
            unless $LJ::ALLOW_COMM_IMPORTS
            && ( $u->can_import_comm || $remote->can_import_comm );
    }

    return error_ml('/tools/importer/index.tt.error.notperson')
        unless $u->is_person;

    if ( $r->did_post ) {

        return error_ml('.error.invalidform')
            unless LJ::check_form_auth( $POST->{lj_form_auth} );

        if ( $POST->{'import'} ) {
            $vars->{widget} = render_choose_source($vars);
        }
        elsif ( $POST->{'choose_source'} ) {
            my $hn = $POST->{hostname};
            return error_ml('widget.importchoosesource.error.nohostname') unless $hn;

            # be sure to sanitize the username
            my $un = LJ::trim( lc $POST->{username} );
            $un =~ s/-/_/g;

            # be sure to sanitize the usejournal, and require one if they're importing to
            # a community
            my $uj;
            if ( $u->is_community ) {
                $uj = LJ::trim( lc $POST->{usejournal} );
                $uj =~ s/-/_/g;
                return error_ml('/tools/importer/index.tt.error.missing_comm')
                    unless $uj;
            }

            my $pw = LJ::trim( $POST->{password} );
            return error_ml('widget.importchoosesource.error.nocredentials') unless $un && $pw;
            my $error = DW::Logic::Importer->set_import_data_for_user(
                $u,
                hostname   => $hn,
                username   => $un,
                password   => $pw,
                usejournal => $uj
            );
            return error_ml($error) if $error;
            $vars->{widget} = render_choose_data($vars);
        }
        elsif ( $POST->{'choose_data'} ) {
            my $has_items = 0;
            foreach my $key ( keys %$POST ) {
                if ( $key =~ /^lj_/ && $POST->{$key} ) {
                    $has_items = 1;
                    last;
                }
            }
            return error_ml('widget.importchoosedata.error.noitemsselected')
                unless $has_items;

            # if we're doing the suboption, turn on the parent option
            $POST->{lj_entries} = 1
                if $POST->{lj_entries_remap_icon};

            # if comments are on, turn entries on
            $POST->{lj_entries} = 1
                if $POST->{lj_comments};

            # okay, this is kinda hacky but turn on the right things so we can do
            # a proper entry import...
            if ( $POST->{lj_entries} ) {
                $POST->{lj_tags}         = 1;
                $POST->{lj_friendgroups} = 1;
            }

            # if friends are on, turn on groups
            $POST->{lj_friendgroups} = 1
                if $POST->{lj_friends};

            # everybody needs a verifier
            $POST->{lj_verify} = 1;

            # and finally, make sure modes that make no sense for communities are off
            if ( $u->is_community ) {
                $POST->{lj_friends}      = 0;
                $POST->{lj_friendgroups} = 0;
            }

            $vars->{widget} = render_confirm( $vars, $POST );

        }
        elsif ( $POST->{'confirm'} ) {

            # default job status
            my @jobs = (
                [ 'lj_verify',       'ready' ],
                [ 'lj_userpics',     'init' ],
                [ 'lj_bio',          'init' ],
                [ 'lj_tags',         'init' ],
                [ 'lj_friendgroups', 'init' ],
                [ 'lj_friends',      'init' ],
                [ 'lj_entries',      'init' ],
                [ 'lj_comments',     'init' ],
            );

            my %suboptions = ( lj_entries => ['lj_entries_remap_icon'], );

            # get import_data_id for the user
            my $imports = DW::Logic::Importer->get_import_data_for_user($u);

            my $id = $imports->[0]->[0];
            my $error;

            # schedule userpic, bio, and tag imports
            foreach my $item (@jobs) {
                next unless $POST->{ $item->[0] };

                my $suboption = $suboptions{ $item->[0] } || [];
                my %opts;
                foreach (@$suboption) {
                    $opts{$_} = 1 if $POST->{$_};
                }
                $error =
                    DW::Logic::Importer->set_import_items_for_user( $u, item => $item, id => $id );
                return error_ml($error) if $error;

                $error = DW::Logic::Importer->set_import_data_options_for_user(
                    $u,
                    import_data_id => $id,
                    %opts
                );
                return error_ml($error) if $error;
            }
            return $r->redirect("$LJ::SITEROOT/tools/importer$authas");
        }

    }
    else {
        if ( scalar keys %{ DW::Logic::Importer->get_import_items_for_user($u) } ) {
            $vars->{widget} = render_status($vars);
        }
        else {
            $vars->{widget} = render_choose_source($vars);
        }

    }

    return DW::Template->render_template( 'tools/importer/index.tt', $vars );
}

sub render_choose_data {
    my $vars    = shift;
    my $options = [
        {
            name         => 'lj_bio',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_bio'),
            desc         => LJ::Lang::ml('widget.importchoosedata.item.lj_bio.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_friends',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_friends'),
            desc         => LJ::Lang::ml('widget.importchoosedata.item.lj_friends.desc'),
            selected     => 0,
            comm_okay    => 0,
        },
        {
            name         => 'lj_friendgroups',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_friendgroups'),
            desc         => LJ::Lang::ml(
                'widget.importchoosedata.item.lj_friendgroups.desc',
                { sitename => $LJ::SITENAMESHORT }
            ),
            selected  => 0,
            comm_okay => 0,
        },
        {
            name         => 'lj_entries',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_entries'),
            desc         => LJ::Lang::ml('widget.importchoosedata.item.lj_entries.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_comments',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_comments'),
            desc         => LJ::Lang::ml('widget.importchoosedata.item.lj_comments.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_tags',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_tags'),
            desc         => LJ::Lang::ml('widget.importchoosedata.item.lj_tags.desc'),
            selected     => 0,
            comm_okay    => 1,
        },
        {
            name         => 'lj_userpics',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_userpics'),
            desc         => LJ::Lang::ml(
                'widget.importchoosedata.item.lj_userpics.desc',
                { sitename => $LJ::SITENAMESHORT }
            ),
            selected  => 0,
            comm_okay => 1,
        },
    ];

    my $fixup_options = [
        {
            name         => 'lj_entries_remap_icon',
            display_name => LJ::Lang::ml('widget.importstatus.item.lj_entries_remap_icon'),
            desc         => LJ::Lang::ml('widget.importchoosedata.item.lj_entries_remap_icon.desc'),
            selected     => 0,
        },
    ];

    $vars->{options}       = $options;
    $vars->{fixup_options} = $fixup_options;

    return DW::Template->template_string( 'tools/importer/choose_data.tt', $vars );
}

sub render_choose_source {
    my $vars = shift;

    return error_ml('widget.importchoosesource.disabled1')
        unless LJ::is_enabled('importing');

    my @services;

    for my $service (
        (
            {
                name         => 'livejournal',
                url          => 'livejournal.com',
                display_name => 'LiveJournal',
            },
            {
                name         => 'insanejournal',
                url          => 'insanejournal.com',
                display_name => 'InsaneJournal',
            },
            {
                name         => 'dreamwidth',
                url          => 'dreamwidth.org',
                display_name => 'Dreamwidth',
            },
        )
        )
    {
        # only dev servers can import from Dreamwidth for testing
        next if ( $service->{name} eq 'dreamwidth' ) && !$LJ::IS_DEV_SERVER;
        push @services,
            $service
            if LJ::is_enabled( "external_sites",
            { sitename => $service->{display_name}, domain => $service->{url} } );
    }
    $vars->{services} = \@services;

    return DW::Template->template_string( 'tools/importer/choose_source.tt', $vars );

}

sub render_confirm {
    my ( $vars, $opts ) = @_;

    my @items_fields;
    my @items_display;
    foreach my $item ( keys %$opts ) {
        next unless $item =~ /^lj_/ && $opts->{$item};
        push @items_fields, $item unless $item eq 'lj_form_auth';
        push @items_display, LJ::Lang::ml("widget.importstatus.item.$item")
            unless ( $item eq 'lj_verify' )
            or ( $item eq 'lj_form_auth' );
    }
    my $imports = DW::Logic::Importer->get_import_data_for_user( $vars->{u} );

    $vars->{items_fields}  = \@items_fields;
    $vars->{items_display} = \@items_display;
    $vars->{imports}       = $imports;

    return DW::Template->template_string( 'tools/importer/confirm.tt', $vars );
}

sub render_status {
    my $vars             = shift;
    my $items            = DW::Logic::Importer->get_import_items_for_user( $vars->{u} );
    my $item_to_funcname = {
        lj_bio          => 'DW::Worker::ContentImporter::LiveJournal::Bio',
        lj_tags         => 'DW::Worker::ContentImporter::LiveJournal::Tags',
        lj_entries      => 'DW::Worker::ContentImporter::LiveJournal::Entries',
        lj_comments     => 'DW::Worker::ContentImporter::LiveJournal::Comments',
        lj_userpics     => 'DW::Worker::ContentImporter::LiveJournal::Userpics',
        lj_friends      => 'DW::Worker::ContentImporter::LiveJournal::Friends',
        lj_friendgroups => 'DW::Worker::ContentImporter::LiveJournal::FriendGroups',
        lj_verify       => 'DW::Worker::ContentImporter::LiveJournal::Verify',
    };

    my $dbr;
    my $funcmap;
    my $dupect = 0;
    my $color  = {
        init      => '#333',
        ready     => '#33a',
        queued    => '#3a3',
        failed    => '#a33',
        succeeded => '#0f0',
        aborted   => '#f00'
    };
    foreach my $importid ( sort { $b <=> $a } keys %$items ) {
        my $import_item = $items->{$importid};
        foreach my $item ( sort keys %{ $import_item->{items} } ) {
            my $i = $import_item->{items}->{$item};
            $i->{color} = $color->{ $i->{status} };
            $i->{ago}   = $i->{last_touch} ? LJ::diff_ago_text( $i->{last_touch} ) : "";
            if ( $i->{status} eq 'init' ) {
                $i->{status_txt} = LJ::Lang::ml("widget.importstatus.status.$i->{status}.$item");
            }
            else {
                $i->{status_txt} = LJ::Lang::ml("widget.importstatus.status.$i->{status}");

                if ( $i->{status} eq "aborted" ) {
                    unless ($dbr) {

                        # do manual connection
                        my $db = $LJ::THESCHWARTZ_DBS[0];
                        $dbr = DBI->connect( $db->{dsn}, $db->{user}, $db->{pass} );
                    }

                    if ($dbr) {

                        # get the ids for the function map
                        $funcmap ||=
                            $dbr->selectall_hashref( 'SELECT funcid, funcname FROM funcmap',
                            'funcname' );

                        $dupect = $dbr->selectrow_array(
                            q{SELECT COUNT(*) from job
                                    WHERE funcid  = ?
                                      AND uniqkey = ? },
                            undef, $funcmap->{ $item_to_funcname->{$item} }->{funcid},
                            join( "-", ( $item, $vars->{u}->id ) )
                        );
                    }
                }
            }

            $i->{dupe} =
                $dupect ? " " . LJ::Lang::ml("widget.importstatus.processingprevious") : "";
        }
        $vars->{items}    = $items;
        $vars->{time_ago} = \&LJ::diff_ago_text;
    }
    return DW::Template->template_string( 'tools/importer/status.tt', $vars );
}

sub get_queue {
    my $depth = LJ::MemCache::get('importer_queue_depth');
    unless ($depth) {

        # FIXME: don't make this slam the db with people asking the same question, use a lock
        # FIXME: we don't have ddlockd, maybe we should

        # do manual connection
        my $db  = $LJ::THESCHWARTZ_DBS[0];
        my $dbr = DBI->connect( $db->{dsn}, $db->{user}, $db->{pass} )
            or return "Unable to manually connect to TheSchwartz database.";

        # get the ids for the function map
        my $tmpmap = $dbr->selectall_hashref( 'SELECT funcid, funcname FROM funcmap', 'funcname' );

        # get the counts of jobs in queue (active or not)
        my %cts;
        foreach my $map ( keys %$tmpmap ) {
            next unless $map =~ /^DW::Worker::ContentImporter::LiveJournal::/;

            my $ct = $dbr->selectrow_array(
                q{SELECT COUNT(*) FROM job
                  WHERE funcid = ?
                    AND run_after < UNIX_TIMESTAMP()},
                undef, $tmpmap->{$map}->{funcid}
            ) + 0;

            $map =~ s/^.+::(\w+)$/$1/;
            $cts{ lc $map } = $ct;
        }

        LJ::MemCache::set( 'importer_queue_depth', \%cts, 300 );
        $depth = \%cts;
    }
    return $depth;
}

sub erase_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    unless ( $r->did_post ) {

        # No post, return form.
        return DW::Template->render_template(
            'tools/importer/erase.tt',
            {
                authas_html => $rv->{authas_html},
                u           => $rv->{u},
            }
        );
    }

    my $args = $r->post_args;
    die "Invalid form auth.\n"
        unless LJ::check_form_auth( $args->{lj_form_auth} );

    unless ( $args->{confirm} eq 'DELETE' ) {
        return DW::Template->render_template(
            'tools/importer/erase.tt',
            {
                notconfirmed => 1,
                authas_html  => $rv->{authas_html},
                u            => $rv->{u},
            }
        );
    }

    # Confirmed, let's schedule.
    DW::TaskQueue->dispatch(
        TheSchwartz::Job->new_from_array(
            'DW::Worker::ImportEraser',
            {
                userid => $rv->{u}->userid
            }
        )
    ) or die "Failed to insert eraser job.\n";

    return DW::Template->render_template(
        'tools/importer/erase.tt',
        {
            u         => $rv->{u},
            confirmed => 1,
        }
    );
}

1;
