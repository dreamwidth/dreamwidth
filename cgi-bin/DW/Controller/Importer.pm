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

use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Controller;
use DW::Importer::Queue;
use DW::Importer::Registry;
use DW::Logic::Importer;
use DW::Request;
use DW::Routing;
use DW::Task::ImportEraser;
use DW::TaskQueue;
use DW::Template;
use LJ::Hooks;
use LJ::JSON;

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
    $vars->{authas_html}        = $rv->{authas_html};
    my $depth = get_queue();

    $vars->{queue} = join( ', ', map { "$_: " . ( $depth->{ lc $_ } + 0 ) } sort keys %$depth );

    # if these aren't the same users, make sure we're allowed to do a community import
    unless ( $u->equals($remote) ) {
        return error_ml('/tools/importer/index.tt.error.cant_import_comm')
            unless $LJ::ALLOW_COMM_IMPORTS
            && ( $u->can_import_comm || $remote->can_import_comm );
    }

    return error_ml('/tools/importer/index.tt.error.notperson')
        unless $remote->is_person;

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
            $vars->{widget} =
                render_choose_data( $vars, DW::Importer::Registry->source_for_hostname($hn) );
        }
        elsif ( $POST->{'choose_data'} ) {
            my $source = current_source($u)
                or return error_ml('widget.importchoosesource.error.nohostname');

            my @chosen = grep { $POST->{$_} } selectable_fields($source);
            return error_ml('widget.importchoosedata.error.noitemsselected')
                unless @chosen;

            $vars->{widget} = render_confirm( $vars, $source, \@chosen );

        }
        elsif ( $POST->{'confirm'} ) {

            # get import_data_id for the user
            my $imports = DW::Logic::Importer->get_import_data_for_user($u);
            my $source  = current_source($u)
                or return error_ml('widget.importchoosesource.error.nohostname');

            my $id = $imports->[0]->[0];
            my $error;

            # schedule everything that was chosen, plus what it needs
            my @chosen = grep { $POST->{$_} } selectable_fields($source);
            my %wanted =
                map { $_ => 1 }
                DW::Importer::Registry->expand_selection( $source->{name}, \@chosen,
                DW::Importer::Registry->journaltype($u) );

            foreach my $item ( DW::Importer::Registry->items( $source->{name} ) ) {
                next unless $wanted{ $item->{name} };

                my %opts;
                foreach ( @{ $item->{suboptions} } ) {
                    $opts{$_} = 1 if $POST->{$_};
                }
                $error = DW::Logic::Importer->set_import_items_for_user(
                    $u,
                    item => [ $item->{name}, $item->{initial_status} ],
                    id   => $id
                );
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

# the source (kind of site) of the user's most recent import setup, or undef
sub current_source {
    my ($u) = @_;

    my $imports = DW::Logic::Importer->get_import_data_for_user($u);
    return undef unless $imports && $imports->[0];
    return DW::Importer::Registry->source_for_hostname( $imports->[0]->[1] );
}

# the form fields that mean something on the choose-data page: the items users can pick
# and the options belonging to them
sub selectable_fields {
    my ($source) = @_;

    return map { ( $_->{name}, @{ $_->{suboptions} } ) }
        grep { $_->{selectable} } DW::Importer::Registry->items( $source->{name} );
}

sub render_choose_data {
    my ( $vars, $source ) = @_;

    my @items =
        sort { $a->{display_order} <=> $b->{display_order} }
        grep { $_->{selectable} } DW::Importer::Registry->items( $source->{name} );

    my $sitename = { sitename => $LJ::SITENAMESHORT };
    my $options  = [
        map {
            {
                name         => $_->{name},
                display_name => LJ::Lang::ml("widget.importstatus.item.$_->{name}"),
                desc => LJ::Lang::ml( "widget.importchoosedata.item.$_->{name}.desc", $sitename ),
                selected  => 0,
                comm_okay => $_->{comm_okay},
            }
        } @items
    ];

    my $fixup_options = [
        map {
            {
                name         => $_,
                display_name => LJ::Lang::ml("widget.importstatus.item.$_"),
                desc         => LJ::Lang::ml( "widget.importchoosedata.item.$_.desc", $sitename ),
                selected     => 0,
            }
        } map { @{ $_->{suboptions} } } @items
    ];

    $vars->{options}       = $options;
    $vars->{fixup_options} = $fixup_options;
    $vars->{dependencies_json} =
        to_json( DW::Importer::Registry->dependency_map( $source->{name} ) );

    return DW::Template->template_string( 'tools/importer/choose_data.tt', $vars );
}

sub render_choose_source {
    my $vars = shift;

    return error_ml('widget.importchoosesource.disabled1')
        unless LJ::is_enabled('importing');

    $vars->{services} = [ DW::Logic::Importer->allowed_sources ];

    return DW::Template->template_string( 'tools/importer/choose_source.tt', $vars );

}

sub render_confirm {
    my ( $vars, $source, $chosen ) = @_;

    # everything that will be imported, in order, with the chosen options after their item
    my %chosen   = map { $_ => 1 } @$chosen;
    my @selected = DW::Importer::Registry->expand_selection( $source->{name}, $chosen,
        DW::Importer::Registry->journaltype( $vars->{u} ) );

    my ( @items_fields, @items_display );
    foreach my $name (@selected) {
        my $item = DW::Importer::Registry->item($name);
        push @items_fields,  $name;
        push @items_display, LJ::Lang::ml("widget.importstatus.item.$name")
            unless $item->{always};

        foreach my $option ( grep { $chosen{$_} } @{ $item->{suboptions} } ) {
            push @items_fields,  $option;
            push @items_display, LJ::Lang::ml("widget.importstatus.item.$option");
        }
    }
    my $imports = DW::Logic::Importer->get_import_data_for_user( $vars->{u} );

    $vars->{items_fields}  = \@items_fields;
    $vars->{items_display} = \@items_display;
    $vars->{imports}       = $imports;

    return DW::Template->template_string( 'tools/importer/confirm.tt', $vars );
}

sub render_status {
    my $vars  = shift;
    my $items = DW::Logic::Importer->get_import_items_for_user( $vars->{u} );
    my $color = {
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
            my $i      = $import_item->{items}->{$item};
            my $dupect = 0;
            $i->{color} = $color->{ $i->{status} };
            $i->{ago}   = $i->{last_touch} ? LJ::diff_ago_text( $i->{last_touch} ) : "";
            if ( $i->{status} eq 'init' ) {
                $i->{status_txt} = LJ::Lang::ml("widget.importstatus.status.$i->{status}.$item");
            }
            else {
                $i->{status_txt} = LJ::Lang::ml("widget.importstatus.status.$i->{status}");

                # an aborted item may just be waiting behind an older job for the same item
                $dupect = DW::Importer::Queue->job_count( $vars->{u}, $item )
                    if $i->{status} eq "aborted";
            }

            $i->{dupe} =
                $dupect ? " " . LJ::Lang::ml("widget.importstatus.processingprevious") : "";
        }
        $vars->{items}    = $items;
        $vars->{time_ago} = \&LJ::diff_ago_text;
    }
    return DW::Template->template_string( 'tools/importer/status.tt', $vars );
}

# returns a hashref of lowercased worker name => jobs due, or an empty hashref if the
# queue can't be read
sub get_queue {
    my $depth = LJ::MemCache::get('importer_queue_depth');
    return $depth if $depth;

    # FIXME: don't make this slam the db with people asking the same question, use a lock
    # FIXME: we don't have ddlockd, maybe we should

    # get the counts of jobs in queue (active or not)
    my %registered = map { $_ => 1 } DW::Importer::Registry->classes;
    my %cts;
    my $reached = DW::Importer::Queue->each_dbh(
        sub {
            my ($dbh) = @_;
            my $funcmap =
                $dbh->selectall_hashref( 'SELECT funcid, funcname FROM funcmap', 'funcname' )
                or return;

            foreach my $funcname ( keys %$funcmap ) {
                next unless $registered{$funcname};

                my ($ct) =
                    $dbh->selectrow_array(
                    'SELECT COUNT(*) FROM job WHERE funcid = ? AND run_after < ?',
                    undef, $funcmap->{$funcname}->{funcid}, time() );

                ( my $name = $funcname ) =~ s/^.+::(\w+)$/$1/;
                $cts{ lc $name } += $ct || 0;
            }
        }
    );
    unless ($reached) {
        $log->error('No TheSchwartz database available to read the importer queue depth.');
        return {};
    }

    LJ::MemCache::set( 'importer_queue_depth', \%cts, 300 );
    return \%cts;
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
        DW::Task::ImportEraser->new(
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
