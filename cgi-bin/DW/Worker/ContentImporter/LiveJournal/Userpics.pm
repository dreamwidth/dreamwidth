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

use XML::Parser;
use HTML::Entities;
use Storable qw/ freeze /;
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
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_userpics', $job, @_ ); };
    my $status    = sub { return $class->status( $data, 'lj_userpics', { @_ } ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );

# FIXME: URL may not be accurate here for all sites
    my ( $default, @pics ) = $class->get_lj_userpic_data( "http://$data->{username}.$data->{hostname}/", $data );

    my $errs = [];
    my @imported = DW::Worker::ContentImporter::Local::Userpics->import_userpics( $u, $errs, $default, \@pics );
    $status->( text => "Your usericon import had some errors:\n\n" . join("\n", map { " * $_" } @$errs) )
        if @$errs;

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
    my ( $class, $url, $data ) = @_;
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

    my $cleanup_string = sub {
        # FIXME: If LJ ever fixes their /data/userpics feed to double-escepe, this will cause issues.
        # Probably need to figure out a way to detect that a double-escape happened and only fix in that case.
        return HTML::Entities::decode_entities( encode_utf8( $_[0] || "" ) );
    };

    my $upic_handler = sub {
        my $tag = $_[1];
        shift; shift;
        my %temp = ( @_ );

        if ( $tag eq 'entry' ) {
            $upic = {keywords=>[]};
        } elsif ( $tag eq 'content' ) {
            $upic->{src} = $temp{src};
        } elsif ( $tag eq 'category' ) {
            # keywords get triple-escaped
            # XML::Parser handles unescaping it once, $cleanup_string second, and then we have to unescape it a third time.
            push @{$upic->{keywords}}, HTML::Entities::decode_entities( $cleanup_string->( $temp{term} ) );
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
            my $comment = $cleanup_string->( $upic->{comment} );
            $upic->{comment} = $class->remap_lj_user( $data, $comment );
            push @upics, $upic;
        }
    };

    my $parser = new XML::Parser( Handlers => { Start => $upic_handler, Char => $upic_content, End => $upic_closer } );
    $parser->parse( $content );

    return ( $default_upic, @upics );
}


1;
