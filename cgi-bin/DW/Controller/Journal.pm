#!/usr/bin/perl
#
# DW::Controller::Journal
#
# Shared journal rendering controller. Extracts the journal viewing pipeline
# from Apache::LiveJournal.pm so both Apache and Plack can render journals.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Journal;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::BML;
use DW::Request;
use DW::Routing;
use DW::Template;
use LJ::Entry;
use LJ::Links;
use LJ::PageStats;

# determine_view( $user, $uri, $args_wq, %GET )
#
# Pure URI parsing logic extracted from Apache::LiveJournal.pm's $determine_view.
# Maps a journal-relative URI to a view mode.
#
# Returns hashref { mode => ..., pathextra => ..., ljentry => ... }
# or a numeric HTTP status code (e.g. 404)
# or { redirect => $url, status => 301|302 }
# or undef if no mode could be determined.
sub determine_view {
    my ( $class, $user, $uuri, $args_wq, %GET ) = @_;

    my $mode;
    my $pe;
    my $ljentry;

    # Favicon: not handled under Plack journal routing
    return undef if $uuri eq "/favicon.ico";

    # Redirect /tags -> /tag
    if ( $uuri =~ m#^/tags(.*)# ) {
        my $u = LJ::load_user($user) or return 404;
        return { redirect => $u->journal_base . "/tag$1" };
    }

    # Redirect /calendar -> /archive
    if ( $uuri =~ m#^/calendar(.*)# ) {
        my $u = LJ::load_user($user) or return 404;
        return { redirect => $u->journal_base . "/archive$1" };
    }

    # Entry by ditemid: /1234.html
    if ( $uuri =~ m#^/(\d+)(\.html?)$#i ) {
        return { redirect => "/$1.html$args_wq" }
            unless $2 eq '.html';

        my $u = LJ::load_user($user)
            or return 404;

        $ljentry = LJ::Entry->new( $u, ditemid => $1 );
        if ( $GET{'mode'} eq "reply" || $GET{'replyto'} || $GET{'edit'} ) {
            $mode = "reply";
        }
        else {
            $mode = "entry";
        }
    }

    # Entry by slug: /2026/02/01/my-slug.html
    elsif ( $uuri =~ m#^/(\d\d\d\d/\d\d/\d\d)/([a-z0-9_-]+)\.html$# ) {
        my $u = LJ::load_user($user)
            or return 404;

        my $date = $1;
        $ljentry = LJ::Entry->new( $u, slug => $2 );
        if ( defined $ljentry ) {
            my $dt = join( '/', split( '-', substr( $ljentry->eventtime_mysql, 0, 10 ) ) );
            return 404 unless $dt eq $date;
        }

        if ( $GET{'mode'} eq "reply" || $GET{'replyto'} || $GET{'edit'} ) {
            $mode = "reply";
        }
        else {
            $mode = "entry";
        }
    }

    # Date views: /2026/, /2026/02/, /2026/02/01/
    elsif ( $uuri =~ m#^/(\d\d\d\d)(?:/(\d\d)(?:/(\d\d))?)?(/?)$# ) {
        my ( $year, $mon, $day, $slash ) = ( $1, $2, $3, $4 );
        unless ($slash) {
            my $u = LJ::load_user($user)
                or return 404;
            my $proper = $u->journal_base . "/$year";
            $proper .= "/$mon" if defined $mon;
            $proper .= "/$day" if defined $day;
            $proper .= "/";
            return { redirect => $proper };
        }

        $pe = $uuri;

        if ( defined $day ) {
            $mode = "day";
        }
        elsif ( defined $mon ) {
            $mode = "month";
        }
        else {
            $mode = "archive";
        }
    }

    # Named views: /read, /tag, /archive, /network, etc.
    elsif (
        $uuri =~ m!
             /([a-z\_]+)?           # optional /<viewname>
             (.*)                   # path extra
             !x && ( $1 eq "" || defined $LJ::viewinfo{$1} )
        )
    {
        ( $mode, $pe ) = ( $1, $2 );
        $mode ||= "" unless length $pe;    # if no pathextra, then imply 'lastn'

        # redirect old-style URLs
        if ( $mode =~ /^day|calendar$/ && $pe =~ m!^/\d\d\d\d! ) {
            my $newuri = $uuri;
            $newuri =~ s!$mode/(\d\d\d\d)!$1!;
            return { redirect => LJ::journal_base($user) . $newuri };
        }
        elsif ( $mode eq 'rss' ) {
            return { redirect => LJ::journal_base($user) . "/data/rss$args_wq", status => 301 };
        }
        elsif ( $mode eq 'tag' ) {
            return { redirect => LJ::journal_base($user) . "$uuri/" } unless $pe;
            if ( $pe eq '/' ) {
                $mode = 'tag';
                $pe   = undef;
            }
            else {
                $mode = 'lastn';
                $pe   = "/tag$pe";
            }
        }
        elsif ( $mode eq 'security' ) {
            return { redirect => LJ::journal_base($user) . "$uuri/" } unless $pe;
            $mode = 'lastn';
            $pe   = "/security$pe";
        }
    }
    elsif ( $uuri eq "/robots.txt" ) {
        $mode = "robots_txt";
    }
    else {
        my $u = LJ::load_user($user)
            or return 404;

        # Unknown URI under journal context
        return undef;
    }

    return undef unless defined $mode;

    # Redirect renamed journals
    my $u = LJ::load_user($user);
    if ( $u && $u->is_redirect && $u->is_renamed ) {
        my $renamedto = $u->prop('renamedto');
        if ( $renamedto ne '' ) {
            my $redirect_url =
                ( $renamedto =~ m!^https?://! )
                ? $renamedto
                : LJ::journal_base($renamedto) . $uuri . $args_wq;
            return { redirect => $redirect_url, status => 301 };
        }
    }

    return {
        mode      => $mode,
        pathextra => $pe,
        ljentry   => $ljentry,
    };
}

# render( user => $username, uri => $path, args => $query_string )
#
# Main entry point for journal rendering under Plack. Combines the logic from
# Apache::LiveJournal's $journal_view and journal_content subs.
#
# Returns the DW::Request response (via $r->OK, etc.) or undef if not handled.
sub render {
    my ( $class, %params ) = @_;

    my $orig_user = $params{user};
    my $user      = LJ::canonical_username($orig_user);
    my $uri       = $params{uri} || '/';
    my $args      = $params{args} || '';
    my $args_wq   = $args ? "?$args" : '';

    my $r      = DW::Request->get;
    my $remote = LJ::get_remote();

    my %GET = LJ::parse_args($args);

    # Try DW::Routing first for user-context controllers
    my $ret = DW::Routing->call( username => $user );
    return $ret if defined $ret;

    # Parse the URI into a view mode
    my $view = $class->determine_view( $user, $uri, $args_wq, %GET );

    # Not a journal URL we understand
    return undef unless defined $view;

    # Numeric return = HTTP status
    return $view if !ref $view && $view =~ /^\d+$/;

    # Redirect
    if ( ref $view eq 'HASH' && $view->{redirect} ) {
        my $status = $view->{status} || 302;
        return $r->redirect( $view->{redirect}, $status );
    }

    my $mode    = $view->{mode};
    my $pe      = $view->{pathextra};
    my $ljentry = $view->{ljentry};

    my $u = LJ::load_user($user);

    # Handle special modes that redirect away
    if ( $mode eq "info" ) {
        $u or return 404;
        my $m = $GET{mode} eq 'full' ? '?mode=full' : '';
        return $r->redirect( $u->profile_url . $m );
    }

    if ( $mode eq "profile" ) {
        $r->note( '_journal', $user );
        if ($u) {
            $r->note( 'journalid', $u->{userid} );
        }
        return DW::Routing->call( uri => '/profile' );
    }

    if ( $mode eq "update" ) {
        $u or return 404;
        return $r->redirect( "$LJ::SITEROOT/update.bml?usejournal=" . $u->{'user'} );
    }

    # Robots.txt
    if ( $mode eq "robots_txt" ) {
        $u or return 404;
        $u->preload_props( "opt_blockrobots", "adult_content" );
        $r->content_type("text/plain");
        my @extra = LJ::Hooks::run_hook( "robots_txt_extra", $u ), ();
        $r->print($_) for @extra;
        $r->print("User-Agent: *\n");
        if ( $u->should_block_robots ) {
            $r->print("Disallow: /\n");
        }
        return $r->OK;
    }

    # Data handlers (RSS, Atom, FOAF, etc.)
    if ( $mode eq "data" && $pe =~ m!^/(\w+)(/.*)?! ) {
        my ( $data_mode, $data_path ) = ( $1, $2 );
        if ( my $handler = LJ::Hooks::run_hook( "data_handler:$data_mode", $user, $data_path ) ) {

            # Data handlers are coderefs that expect an Apache request object.
            # Create an adapter and call it directly.
            my $adapter = DW::BML::RequestAdapter->new($r);
            $handler->($adapter);
            return $r->OK;
        }
    }

    # Main journal rendering via LJ::make_journal
    my $handle_with_siteviews = 0;
    my %headers;
    my $adapter = DW::BML::RequestAdapter->new($r);

    my $opts = {
        'r'         => $adapter,
        'headers'   => \%headers,
        'args'      => $args,
        'vhost'     => 'users',
        'pathextra' => $pe,
        'header'    => {
            'If-Modified-Since' => $r->header_in("If-Modified-Since"),
        },
        'handle_with_siteviews_ref' => \$handle_with_siteviews,
        'siteviews_extra_content'   => {},
        'ljentry'                   => $ljentry,
    };

    $r->note( 'view', $mode );

    my $html = LJ::make_journal( $user, $mode, $remote, $opts );

    # After-journal hooks
    LJ::Hooks::run_hooks( "after_journal_content_created", $opts, \$html )
        unless $handle_with_siteviews;

    # Internal redirect
    if ( $opts->{internal_redir} ) {
        my $int_redir = DW::Routing->call( uri => $opts->{internal_redir} );
        if ( defined $int_redir ) {
            LJ::start_request();
            return $int_redir;
        }
    }

    # External redirect
    return $r->redirect( $opts->{'redir'} ) if $opts->{'redir'};
    return $opts->{'handler_return'} if defined $opts->{'handler_return'};

    # Siteviews handling
    return DW::Template->render_string( $html, $opts->{siteviews_extra_content} )
        if $handle_with_siteviews && $html;

    # Set status
    my $status = $opts->{'status'} || "200 OK";
    $opts->{'contenttype'} ||= "text/html";
    if (   $opts->{'contenttype'} =~ m!^text/!
        && $opts->{'contenttype'} !~ /charset=/ )
    {
        $opts->{'contenttype'} .= "; charset=utf-8";
    }

    my $generate_iejunk = 0;

    if ( $opts->{'badargs'} ) {
        return 404;
    }
    elsif ( $opts->{'badfriendgroup'} ) {
        if ( $remote && $remote->{'user'} eq $user ) {
            return 404;
        }
        else {
            $status = "403 Forbidden";
            $html =
"<h1>Invalid Filter</h1><p>Either this reading filter doesn't exist or you are not authorized to view it. Try <a href='$LJ::SITEROOT/login'>checking that you are logged in</a> if you're sure you have the name right.</p>";
        }
        $generate_iejunk = 1;
    }
    elsif ( $opts->{'suspendeduser'} ) {
        $status = "403 User suspended";
        $html   = "<h1>Suspended User</h1><p>The content at this URL is from a suspended user.</p>";
        $generate_iejunk = 1;
    }
    elsif ( $opts->{'suspendedentry'} ) {
        $status = "403 Entry suspended";
        $html =
"<h1>Suspended Entry</h1><p>The entry at this URL is suspended.  You cannot reply to it.</p>";
        $generate_iejunk = 1;
    }
    elsif ( $opts->{'readonlyremote'} || $opts->{'readonlyjournal'} ) {
        $status = "403 Read-only user";
        $html   = "<h1>Read-Only User</h1>";
        $html .=
            $opts->{'readonlyremote'}
            ? "<p>You are read-only.  You cannot post comments.</p>"
            : "<p>This journal is read-only.  You cannot comment in it.</p>";
        $generate_iejunk = 1;
    }

    unless ($html) {
        $status = "500 Bad Template";
        $html =
"<h1>Error</h1><p>User <b>$user</b> has messed up their journal template definition.</p>";
        $generate_iejunk = 1;
    }

    $r->status( $status =~ m/^(\d+)/ && $1 );

    # Set response headers
    foreach my $hname ( keys %headers ) {
        if ( ref( $headers{$hname} ) && ref( $headers{$hname} ) eq "ARRAY" ) {
            foreach ( @{ $headers{$hname} } ) {
                $r->header_out( $hname, $_ );
            }
        }
        else {
            $r->header_out( $hname, $headers{$hname} );
        }
    }

    $r->content_type( $opts->{'contenttype'} );
    $r->header_out( "Cache-Control", "private, proxy-revalidate" );

    $html .= ( "<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 100 ) if $generate_iejunk;

    # Parse the page content for any temporary matches
    if ( my $cb = $LJ::TEMP_PARSE_MAKE_JOURNAL ) {
        $cb->( \$html );
    }

    # Add stuff before </body>
    my $before_body_close = "";
    LJ::Hooks::run_hooks( "insert_html_before_body_close",            \$before_body_close );
    LJ::Hooks::run_hooks( "insert_html_before_journalctx_body_close", \$before_body_close );
    $before_body_close .= LJ::PageStats->new->render('journal');
    $html =~ s!</body>!$before_body_close</body>!i if $before_body_close;

    # No manual gzip — let Plack::Middleware::Deflater handle it

    $r->header_out( "Content-length", length($html) );
    $r->print($html) unless $r->method eq 'HEAD';

    return $r->OK;
}

1;
