#!/usr/bin/perl
#
# DW::Controller::Search::Journal
#
# Conversion of search.bml, used for full text search of journals.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009-2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Search::Journal;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use Storable;

DW::Routing->register_string( '/search', \&search_handler, app => 1 );

my $gc = LJ::gearman_client();

sub _do_search {
    return unless $gc && @LJ::SPHINX_SEARCHD;
    my ($arg) = @_;
    $arg = Storable::nfreeze($arg);
    my $result;

    my $task = Gearman::Task->new(
        'sphinx_search',
        \$arg,
        {
            uniq        => '-',
            on_complete => sub {
                my $res = $_[0] or return undef;
                $result = Storable::thaw($$res);
            },
        }
    );

    # setup the task set for gearman... really, isn't there a way to make this simpler?  oh well
    my $ts = $gc->new_task_set();
    $ts->add_task($task);
    $ts->wait( timeout => 20 );

    return $result;
}

sub search_handler {

    # before doing the usual setup, first make sure we have Gearman working
    return error_ml('/search.tt.error.notconfigured') unless $gc && @LJ::SPHINX_SEARCHD;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};

    my $r      = DW::Request->get;
    my $errors = DW::FormErrors->new;

    # some arguments are passed via GET even when posting
    my $get_args = $r->get_args;
    my $offset   = 0;
    $offset += $get_args->{offset} if defined $get_args->{offset};
    my $q = LJ::strip_html( LJ::trim( $get_args->{query} ) );    # may be overridden by POST

    # if there's an offset, return a fatal error if it's out of bounds
    return error_ml('/search.tt.error.wrongoffset') if $offset < 0 || $offset > 1000;

    # we can GET a user name, but we can't use the controller's specify_user
    # convenience method for this, because it will always default to remote,
    # and that will override selection of site search
    my $su = LJ::load_user( $get_args->{user} );    # may be overridden by POST
    return error_ml('error.invaliduser') if $get_args->{user} && !$su;

    # form processing
    if ( $r->did_post ) {
        my $post_args = $r->post_args;

        $su = LJ::load_user( $post_args->{mode} ) if $post_args->{mode};

        # if no $su, then this is a public search, that's allowed.  but if it's a user,
        # ensure that it's an account that we CAN search
        $errors->add( "mode", ".error.forbidden" )
            if $su && !$su->allow_search_by($remote);

        # make sure we got a query
        $q = LJ::strip_html( LJ::trim( $post_args->{query} ) );
        $errors->add( "query", ".error.noquery" ) unless $q;
        $errors->add( "query", ".error.longquery" ) if $q && length $q > 255;

        my $sby = $post_args->{sort_by} || 'new';
        $sby = 'new' unless $sby =~ /^(?:new|old|rel)$/;

        # see if the user wants to include comments, then verify that they are
        # allowed to do so; if not, just ignore that they checked the checkbox
        my $wc   = $post_args->{with_comments} ? 1 : 0;
        my $wc_u = $su || $remote;
        $wc &&= $wc_u->is_paid;    # comment search is a paid account feature

        $rv->{sort_by} = $sby;
        $rv->{wc}      = $wc;

        # at this point, we should have good form data; the form can still
        # have errors below, but they aren't the fault of the user input

        unless ( $errors->exist ) {

            # we have to set a few flags on what to search.  default to public and no bits.
            my ( $ignore_security, $allowmask ) = ( 0, 0 );
            if ($su) {

                # if it's you, all posts, all bits
                if ( $remote->equals($su) ) {
                    $ignore_security = 1;

                }
                elsif ( $su->is_community ) {

                    # if it's a community you administer, also all bits
                    if ( $remote->can_manage($su) ) {
                        $ignore_security = 1;

                        # for communities, member_of is the same as allow mask (no custom groups)
                    }
                    else {
                        $allowmask = $remote->member_of($su);
                    }

                    # otherwise, if they trust you, get the mask ...
                }
                elsif ( $su->trusts($remote) ) {
                    $allowmask = $su->trustmask($remote);
                }
            }

            # the arguments to the search (userid=0 implies global search)
            my $args = {
                userid           => $su ? $su->id : 0,
                remoteid         => $remote->id,
                query            => $q,
                offset           => $offset,
                sort_by          => $sby,
                ignore_security  => $ignore_security,
                allowmask        => $allowmask,
                include_comments => $wc
            };

            my $result = _do_search($args);
            $errors->add( "", ".error.timedout" ) unless $result;

            $rv->{result}  = $result;
            $rv->{matchct} = $result ? scalar( @{ $result->{matches} } ) : 0;
        }
    }

    # end form processing

    $rv->{su}       = $su;
    $rv->{q}        = $q;
    $rv->{offset}   = $offset;
    $rv->{did_post} = $r->did_post;

    $rv->{errors}   = $errors;
    $rv->{formdata} = $r->post_args;

    $rv->{load_uid} = sub { LJ::load_userid( $_[0] ) };
    $rv->{tagprint} = sub {
        join(
            ', ', map { "<strong>" . $_[0]->{$_} . "</strong>" }
                keys %{ $_[0] }
        );
    };
    $rv->{sec_icon} = sub {
        return {
            public  => '',
            private => LJ::img( "security-private", "" ),
            usemask => LJ::img( "security-groups", "" ),
            access  => LJ::img( "security-protected", "" ),
        }->{ $_[0] };
    };

    return DW::Template->render_template( 'search.tt', $rv );
}

# Translator's note: I couldn't find the format of the search result hash
# documented anywhere, so I reverse-engineered it from the display code.
# Preserving this here in case it comes in useful again in the future.

my $mock_results = {
    total   => 2,
    time    => '0.00',
    matches => [
        {
            journalid => 1,
            poster_id => 0,
            security  => 'public',
            jtalkid   => 0,
            url       => 'blank',
            subject   => 'testing',
            excerpt   => 'text goes here...',
            eventtime => LJ::mysql_time,
            tags      => { 1 => 'foo', 2 => 'bar' }
        },
        {
            journalid => 1,
            poster_id => 0,
            security  => 'access',
            jtalkid   => 0,
            url       => 'blank',
            subject   => 'testing',
            excerpt   => 'text goes here...',
            eventtime => LJ::mysql_time,
            tags      => {}
        },
    ]
};

1;
