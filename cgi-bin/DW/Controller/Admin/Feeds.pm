#!/usr/bin/perl
#
# DW::Controller::Admin::Feeds
#
# Feed merging / duplicates admin page
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::DuplicateFeeds;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;
use List::MoreUtils qw/ uniq any /;
use LJ::Feed;

DW::Routing->register_string( "/admin/feeds/duplicate", \&duplicate_controller );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'feeds/duplicate',
    ml_scope => '/admin/feeds/duplicate.tt',
    privs    => ['syn_edit']
);

DW::Routing->register_string( "/admin/feeds/merge", \&merge_controller );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'feeds/merge',
    ml_scope => '/admin/feeds/merge.tt',
    privs    => ['syn_edit']
);

sub duplicate_controller {
    my ( $ok, $rv ) = controller( privcheck => ["syn_edit"] );
    return $rv unless $ok;

    my $dbr  = LJ::get_db_reader();
    my $data = $dbr->selectall_arrayref(
              "SELECT COUNT(userid),fuzzy_token FROM syndicated WHERE fuzzy_token IS NOT NULL "
            . "GROUP BY fuzzy_token HAVING COUNT(userid) > 1" )
        or die $dbr->errstr;

    $data = [ sort { $b->[0] <=> $a->[0] } @$data ];

    return DW::Template->render_template( "admin/feeds/duplicate.tt", { data => $data } );
}

sub _score_url {
    my $url   = $_[0];
    my $score = 0;

    # Twitter feeds are gone for good
    return -1000
        if $url =~ m/twitter\.com/i;

    # If they are using feedburner
    #   this is likely the correct url
    $score += 20
        if $url =~ m/feedburner\.com/i;

    return $score + 10
        if $url =~ m/atom/i;
    return $score + 5
        if $url =~ m/rss/i;
    return 0;
}

sub merge_controller {
    my ( $ok, $rv ) = controller( privcheck => ["syn_edit"], form_auth => 1 );
    return $rv unless $ok;
    my $r = DW::Request->get;

    my $args = $r->did_post ? $r->post_args : $r->get_args;
    my $dbr  = LJ::get_db_reader();
    my $vars = { data => {} };
    $vars->{errors} = [];

    if ( $r->did_post ) {
        my $dest_feed = $args->{dest_feed};
        my $dest_url  = $args->{dest_url};
        my @userids   = $args->get_all('include');

        my $confirmed = $args->{confirmed};

        my $contains_dest_feed = any { $_ == $dest_feed } @userids;
        my $contains_dest_url  = any { $_ == $dest_url } @userids;

        unshift @userids, $dest_url if $contains_dest_url;
        @userids = uniq grep { $_ != $dest_feed } @userids;

        if ( scalar @userids == 0 ) {
            push @{ $vars->{errors} }, "No feeds to consider";
        }
        elsif ( !$contains_dest_feed ) {
            push @{ $vars->{errors} }, "Merge destination feed must be considered.";
        }
        elsif ( !$contains_dest_url ) {
            push @{ $vars->{errors} }, "URL destination feed must be considered.";
        }
        else {
            my $url = $dbr->selectrow_array( "SELECT synurl FROM syndicated WHERE userid = ?",
                undef, $dest_url );
            $vars->{url_to} = $url;
            my @merge_plan;
            my $failed = 0;
            my $to     = $dest_feed;
            my $to_u   = LJ::want_user($to);
            foreach my $feed_id (@userids) {
                my $from = $feed_id;
                my ( $ok, $msg ) = LJ::Feed::merge_feed(
                    from    => $from,
                    to      => $to_u,
                    url     => $url,
                    pretend => ( $confirmed ? 0 : 1 )
                );
                push @merge_plan, [ LJ::want_user($from), $to_u, $ok, $msg ];
                $failed = 1 unless $ok;
            }
            $vars->{merge_plan} = \@merge_plan;
            if ($failed) {
                push @{ $vars->{errors} }, "Merge plan fails";
            }
            elsif ($confirmed) {
                $vars->{merge_ok} = 1;
            }
            else {
                $vars->{dest_feed}    = $dest_feed;
                $vars->{dest_url}     = $dest_url;
                $vars->{to_include}   = [ $dest_feed, @userids ];
                $vars->{need_confirm} = 1;
            }
        }
    }

    if ( $args->{feeds} ) {
        $vars->{raw_feeds} = $args->{feeds};
        my @names = uniq map { s/^\s+//; s/\s+$//; LJ::canonical_username($_); } split ',',
            $args->{feeds};
        my $marks = join ',', map { '?' } @names;
        $vars->{feeds} = join ',', @names;
        $vars->{names} = \@names;
        my $feeds = $dbr->selectall_arrayref(
"SELECT s.userid,user,synurl,numreaders,fuzzy_token FROM syndicated AS s JOIN useridmap AS m ON s.userid=m.userid "
                . "WHERE m.user IN ($marks)",
            undef, @names
        ) or die $dbr->errstr;
        $vars->{data} = {
            map {
                $_->[0] => {
                    userid  => $_->[0],
                    name    => $_->[1],
                    url     => $_->[2],
                    readers => ( $_->[3] || 0 ),
                    score   => _score_url( $_->[2] ),
                    token   => $_->[4]
                }
            } @$feeds
        };
        $vars->{tokens} = [ uniq map { $_->{token} || "uknown" } values %{ $vars->{data} } ];
    }
    elsif ( $args->{token} ) {
        $vars->{raw_token} = $args->{token};
        my $feeds = $dbr->selectall_arrayref(
"SELECT s.userid,user,synurl,numreaders FROM syndicated AS s JOIN useridmap AS m ON s.userid=m.userid "
                . "WHERE fuzzy_token = ?",
            undef, $args->{token}
        ) or die $dbr->errstr;
        $vars->{data} = {
            map {
                $_->[0] => {
                    userid  => $_->[0],
                    name    => $_->[1],
                    url     => $_->[2],
                    readers => ( $_->[3] || 0 ),
                    score   => _score_url( $_->[2] ),
                    token   => $args->{token}
                }
            } @$feeds
        };
        $vars->{tokens} = [ $args->{token} ];
        $vars->{token}  = $args->{token};
    }
    else {
    }

    my $data    = $vars->{data};
    my @userids = keys %$data;
    my $users   = LJ::load_userids(@userids);
    foreach my $userid ( keys %$users ) {
        $data->{$userid}->{user} = $users->{$userid};
    }
    $vars->{best} = {
        scoring =>
            ( ( sort { $data->{$b}->{score} <=> $data->{$a}->{score} } @userids )[0] || undef ),
        readers =>
            ( ( sort { $data->{$b}->{readers} <=> $data->{$a}->{readers} } @userids )[0] || undef ),
    };

    return DW::Template->render_template( "admin/feeds/merge.tt", $vars );
}

1;
