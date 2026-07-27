#!/usr/bin/perl
#
# DW::Controller::Mobile::Post
#
# The mobile post-an-entry page (/mobile/post): a minimal standalone (no
# sitescheme) form that posts an entry via the protocol, supporting lj-mood /
# lj-music markers in the body, a security selector, and posting to communities.
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
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Mobile::Post;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/mobile/post", \&post_handler, app => 1 );

sub post_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    # Not logged in: render the "log in first" message (the page is anonymous so
    # we can point at the mobile login rather than the site-wide login flow).
    unless ($remote) {
        $rv->{not_logged_in} = 1;
        return DW::Template->render_template( 'mobile/post.tt', $rv, { no_sitescheme => 1 } );
    }

    # Pull the user's postable journals (and userpic keywords) via the protocol.
    my $res = LJ::Protocol::do_request(
        "login", { ver => $LJ::PROTOCOL_VER, username => $remote->user, getpickws => 1 },
        undef, { noauth => 1, u => $remote },
    );
    my $usejournals = $res->{usejournals} || [];

    # The journal dropdown: the user's own journal plus any they may post to.
    $rv->{usejournal_items} = [ "", $remote->user, map { $_, $_ } @$usejournals ];

    # The security dropdown.
    $rv->{security_items} = [
        public  => LJ::Lang::ml('label.security.public'),
        private => LJ::Lang::ml('label.security.private'),
        friends => LJ::Lang::ml('label.security.accesslist'),
    ];

    if ( $r->did_post ) {
        my $post  = $r->post_args;
        my $event = _parse_content( $post->{event} );

        my $sec = $post->{security};
        my $allowmask;
        if ( $sec eq "friends" ) {
            $sec       = "usemask";
            $allowmask = 1;
        }

        my $journal = $post->{usejournal};
        my $req     = {
            usejournal => ( $journal && $journal ne $remote->user ) ? $journal : undef,
            ver        => 1,
            username   => $remote->user,
            event      => $event->{event},
            subject    => $post->{subject},
            props      => $event->{props},
            tz         => 'guess',
            security   => $sec,
            allowmask  => $allowmask,
        };

        my $errcode;
        my $pres =
            LJ::Protocol::do_request( "postevent", $req, \$errcode, { noauth => 1, u => $remote } );
        if ($errcode) {
            $rv->{post_error} = LJ::Protocol::error_message($errcode);
        }
        else {
            $rv->{posted_url} = $pres->{url};
        }
    }

    return DW::Template->render_template( 'mobile/post.tt', $rv, { no_sitescheme => 1 } );
}

# Split lj-mood: / lj-music: markers out of the body into entry props, returning
# { event => $text, props => { ... } }.
sub _parse_content {
    my $content = shift // '';

    my $event = { props => {} };
    if ( $content =~ s/(^|\n)lj-mood:\s*(.*)\n//i ) {
        $event->{props}->{current_mood} = $2;
    }
    if ( $content =~ s/(^|\n)lj-music:\s*(.*)\n//i ) {
        $event->{props}->{current_music} = $2;
    }
    $content =~ s/^\s+//;
    $content =~ s/\s+$//;
    $event->{event} = $content;

    return $event;
}

1;
