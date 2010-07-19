#!/usr/bin/perl
#
# LJ::Widget::CreateAccountInviter
#
# This widget contains the form for adding watch/trust edges for the person who
# invited you to the site, as well as join/watch edges for some of their
# relevant communities.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::CreateAccountInviter;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    my $post = $opts{post};
    my $from_post = $opts{from_post};
    my $errors = $from_post->{errors};

    my $inviter = $u ? $u->who_invited : undef;
    return "" unless LJ::isu( $inviter );

    my $error_msg = sub {
        my ( $key, $pre, $post ) = @_;
        my $msg = $errors->{$key};
        return unless $msg;
        return "$pre $msg $post";
    };

    my $ret;
    $ret .= "<h2>" . $class->ml( 'widget.createaccountinviter.title' ) . "</h2>";

    $ret .= $class->html_hidden( from => $inviter->user );

    # if the invite code came from a comm (promo) then don't offer to watch/trust
    if ( $inviter->is_individual ) {
        if ( $u->can_trust( $inviter ) ) {
            my $inviter_trust_name = 'inviter_trust_' . $inviter->id;
            $ret .= $class->html_check(
                name     => $inviter_trust_name,
                value    => 1,
                selected => defined $post->{$inviter_trust_name} ? $post->{$inviter_trust_name} : 1,
                id       => $inviter_trust_name,
            );
            $ret .= " <label for='$inviter_trust_name'>" . $class->ml( 'widget.createaccountinviter.addinviter.trust', { user => $inviter->ljuser_display } ) . "</label><br />";
        }

        if ( $u->can_watch( $inviter ) ) {
            my $inviter_watch_name = 'inviter_watch_' . $inviter->id;
            $ret .= $class->html_check(
                name     => $inviter_watch_name,
                value    => 1,
                selected => defined $post->{$inviter_watch_name} ? $post->{$inviter_watch_name} : 1,
                id       => $inviter_watch_name,
            );
            $ret .= " <label for='$inviter_watch_name'>" . $class->ml( 'widget.createaccountinviter.addinviter.watch', { user => $inviter->ljuser_display } ) . "</label><br />";
        }
    }

    my %comms;
    if ( $inviter->is_individual ) {
        %comms = $inviter->relevant_communities;
    } elsif ( $inviter->is_community ) {
        %comms = ( $inviter->id => { u => $inviter, istatus => 'normal' } );
    }

    if ( keys %comms ) {
        $ret .= "<br />";

        my ( $any_mm, $any_mod );

        my $i = 0;
        foreach my $commid ( sort { $comms{$a}->{u}->display_username cmp $comms{$b}->{u}->display_username } keys %comms ) {
            last if $i >= 20;

            my $commu = $comms{$commid}->{u};

            my $note_mm = $comms{$commid}->{istatus} eq 'mm' ? ' *' : '';
            $any_mm ||= $note_mm;

            my $note_moderated = $commu->is_moderated_membership ? ' **' : ''; # we will only get moderated or open communities
            $any_mod ||= $note_moderated;

            my $comm_join_name = "inviter_join_$commid";

            # selected if they have a link in that says to join, OR if they were invited
            # by a community (which is the only one in the list)
            my $sel = ( defined $post->{$comm_join_name} ? $post->{$comm_join_name} : 0 ) || $inviter->is_community;

            $ret .= $class->html_check(
                name     => $comm_join_name,
                value    => 1,
                selected => $sel,
                id       => $comm_join_name,
            );
            $ret .= " <label for='$comm_join_name'>";
            $ret .= $class->ml( 'widget.createaccountinviter.addcomms', { user => $commu->ljuser_display, name => $commu->name_html } );
            $ret .= "$note_mm$note_moderated</label><br />";

            $i++;
        }

        if ( $any_mm || $any_mod ) {
            $ret .= "<div style='margin: 10px;'>";
            $ret .= "<?de * " . $class->ml( 'widget.createaccountinviter.addcomms.note.mm', { user => $inviter->ljuser_display } ) . " de?><br />"
                if $any_mm;
            $ret .= "<?de ** " . $class->ml( 'widget.createaccountinviter.addcomms.note.moderated' ) . " de?>"
                if $any_mod;
            $ret .= "</div>";
        }
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    my %from_post;

    foreach my $key ( keys %$post ) {
        if ( $key =~ /^inviter_trust_(\d+)$/ ) {
            my $trustu = LJ::load_userid( $1 );
            $u->add_edge( $trustu, trust => {} )
                if LJ::isu( $trustu );
        } elsif ( $key =~ /inviter_watch_(\d+)$/ ) {
            my $watchu = LJ::load_userid( $1 );
            $u->add_edge( $watchu, watch => {} )
                if LJ::isu( $watchu );
        } elsif ( $key =~ /inviter_join_(\d+)$/ ) {
            my $joinu = LJ::load_userid( $1 );
            if ( LJ::isu( $joinu ) ) {
                # try to join the community
                # if it fails and the community's moderated, send a join request and watch it
                unless ( LJ::join_community( $u, $joinu, 1 ) ) {
                    if ( $joinu->is_moderated_membership ) {
                        LJ::comm_join_request( $joinu, $u );
                        $u->add_edge( $joinu, watch => {} );
                    }
                }
            }
        }
    }

    return %from_post;
}

1;
