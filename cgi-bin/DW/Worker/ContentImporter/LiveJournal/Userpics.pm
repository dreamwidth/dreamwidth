#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal
#
# Importer worker for LiveJournal-based sites userpics.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::LiveJournal::Userpics;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use Carp qw/ croak confess /;
use Encode qw/ encode_utf8 /;
use DW::Worker::ContentImporter::Local::Userpics;

sub work {
    my ( $class, $job ) = @_;

    eval { try_work( $class, $job ); };
    if ( $@ ) {
        warn "Failure running job: $@\n";
        return $class->temp_fail( $job, 'Failure running job: %s', $@ );
    }
}

sub try_work {
    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_userpics', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_userpics', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );

    my ( $default, @pics ) = get_lj_userpic_data( "http://$data->{username}.$data->{hostname}/" );

# FIXME: we need to be aware of errors that will be returned by this method and
# properly handle them/expose them (add import_errors table?)
    my @imported = DW::Worker::ContentImporter::Local::Userpics->import_userpics( $u, [], $default, \@pics );

    if ( scalar( @imported ) != scalar( @pics ) ) {
        my $mog = LJ::mogclient();
        if ( $mog ) {
            $opts->{userpics_later} = 1;
            my $data = freeze {
                imported => \@imported,
                pics => \@pics,
            };
            $mog->store_content( 'import_upi:' . $u->id, 'temp', $data );
        } else {
            return $fail->( 'Userpic import failed and MogileFS not available for backup.' );
        }
    }

    return $ok->();
}

sub get_lj_userpic_data {
    my $url = shift();
    $url =~ s/\/$//;

    my $ua = LJ::get_useragent(
        role     => 'userpic',
        max_size => 524288, # half meg, this should be plenty
        timeout  => 20,     # 20 seconds might need adjusting for slow sites
    );

    my $resp = $ua->get( "$url/data/userpics" );
    return undef
        unless $resp && $resp->is_success;
    my $content = $resp->content;

    my ( @upics, $upic, $default_upic, $text_tag );

    my $upic_handler = sub {
        my $tag = $_[1];
        shift; shift;
        my %temp = ( @_ );

        if ( $tag eq 'entry' ) {
            $upic = {keywords=>[]};
        } elsif ( $tag eq 'content' ) {
            $upic->{src} = $temp{src};
        } elsif ( $tag eq 'category' ) {
            push @{$upic->{keywords}}, encode_utf8( $temp{term} || "" );
        } else {
            $text_tag = $tag;
        }
    };

    my $upic_content = sub {
        my $text = $_[1];

        if ( $text_tag eq 'title' && $text eq 'default userpic' ) {
            $default_upic = $upic;
            $upic->{default} = 1;
        } elsif ( $text_tag eq 'summary' ) {
            $text =~ s/\n//g;
            $text =~ s/^ +$//g;
            $upic->{comment} .= $text;
        } elsif ( $text_tag eq 'id' ) {
            my @parts = split( /:/, $text );
            $upic->{id} = $parts[-1];
            $text_tag = undef;
        }
    };

    my $upic_closer = sub {
        my $tag = $_[1];

        if ( $tag eq 'entry' ) {
            my @keywords;
            foreach my $kw ( @{$upic->{keywords}} ) {
                push @keywords, $kw;
            }

            $upic->{keywords} = \@keywords;
            $upic->{comment} = encode_utf8( $upic->{comment} || "" );
            push @upics, $upic;
        }
    };

    my $parser = new XML::Parser( Handlers => { Start => $upic_handler, Char => $upic_content, End => $upic_closer } );
    $parser->parse( $content );

    return ( $default_upic, @upics );
}


1;
