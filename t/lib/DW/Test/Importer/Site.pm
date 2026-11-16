#!/usr/bin/perl
#
# DW::Test::Importer::Site
#
# A canned LiveJournal-compatible site for tests.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Test::Importer::Site;

=head1 NAME

DW::Test::Importer::Site - A fake remote site, in the shape of an import transport

=head1 DESCRIPTION

Answers the three things an import transport does (see
L<DW::Importer::Source::LiveJournal::Transport>) from the files in C<t/data/importer>.

=cut

use strict;
use warnings;

use HTTP::Response;

sub _slurp {
    my ($name) = @_;
    open my $fh, '<', "$ENV{LJHOME}/t/data/importer/$name" or die "can't read $name: $!";
    local $/;
    return scalar <$fh>;
}

sub new {
    my ($class) = @_;
    my $data = do "$ENV{LJHOME}/t/data/importer/lj-site.pl" or die "bad fixture: $@$!";

    return bless {
        data  => $data,
        pages => {
            "http://someone.livejournal.com/data/foaf"           => _slurp('foaf.xml'),
            "http://livejournal.com/users/someone/data/userpics" => _slurp('userpics.xml'),
        },
        export => {
            comment_meta => _slurp('comments-meta.xml'),
            comment_body => _slurp('comments-body.xml')
        },
        asked => [],
    }, $class;
}

sub data { $_[0]->{data} }

sub xmlrpc {
    my ( $self, $mode, $hash ) = @_;
    push @{ $self->{asked} }, $mode;
    my $data = $self->{data};

    return { tags => $data->{tags} } if $mode eq 'getusertags';
    return { friendgroups => $data->{friendgroups}, friends => $data->{friends} }
        if $mode eq 'getfriends';

    if ( $mode eq 'getevents' ) {
        my @events = @{ $data->{events} };
        return { events => [ $events[-1] ] } if $hash->{selecttype} eq 'lastn';

        my %wanted = map { $_ => 1 } split /,/, $hash->{itemids};
        return {
            events => [
                map {
                    { %$_ }
                } grep { $wanted{ $_->{itemid} } } @events
            ]
        };
    }

    return { fault => 1, faultString => "the fake site does not do $mode" };
}

sub get {
    my ( $self, $url ) = @_;
    my $body = $self->{pages}->{$url};
    return HTTP::Response->new( 404, 'Not Found' ) unless defined $body;

    my $r = HTTP::Response->new( 200, 'OK' );
    $r->content($body);
    return $r;
}

sub comment_export {
    my ( $self, $mode, $startid ) = @_;

    # the whole export is one window; anything after it is empty
    return $self->{export}->{$mode} if $startid == 1;
    return qq{<?xml version="1.0" encoding="utf-8"?><livejournal><comments/></livejournal>};
}

1;
