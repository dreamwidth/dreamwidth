#!/usr/bin/perl
#
# DW::Controller::Export
#
# Pages for exporting journal content.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2015-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Export;

use v5.10;
use strict;

use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::FormErrors;

use DW::Mood;
use Unicode::MapUTF8;

DW::Routing->register_string( '/export',    \&index_handler, app => 1 );
DW::Routing->register_string( '/export_do', \&post_handler,  app => 1 );

sub get_encodings {
    my ( %encodings, %encnames );
    LJ::load_codes( { "encoding" => \%encodings } );
    LJ::load_codes( { "encname"  => \%encnames } );

    my $rv = {};
    foreach my $id ( keys %encodings ) {
        next if lc $encodings{$id} eq 'none';
        $rv->{ $encodings{$id} } = $encnames{$id};
    }
    return $rv;
}

sub index_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my @enclist;
    my %e = %{ get_encodings() };
    push @enclist, ( $_ => $e{$_} ) foreach sort { $e{$a} cmp $e{$b} } keys %e;

    $rv->{encodings} = \@enclist;

    return DW::Template->render_template( 'export/index.tt', $rv );
}

sub post_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $post   = $r->post_args;
    my $scope  = '/export/index.tt';
    my $errors = DW::FormErrors->new;

    return error_ml('bml.requirepost') unless $r->did_post;

    my $u    = $rv->{u};
    my $dbcr = LJ::get_cluster_reader($u);
    return error_ml('error.nodb') unless $dbcr;

    my $ok_formats = { csv => 'csv', xml => 'xml' };
    my $format     = $ok_formats->{ lc $post->{format} };
    $errors->add( '', "$scope.error.format" ) unless $format;

    my $encoding;

    {
        if ( $post->{encid} ) {
            my %encodings;
            LJ::load_codes( { "encoding" => \%encodings } );
            $encoding = $encodings{ $post->{encid} };
        }

        $encoding ||= $post->{encoding};
        $encoding ||= 'utf-8';

        if ( lc($encoding) ne "utf-8"
            && !Unicode::MapUTF8::utf8_supported_charset($encoding) )
        {
            $errors->add( '', "$scope.error.encoding" );
        }
    }

    return DW::Template->render_template( 'error.tt',
        { errors => $errors, message => LJ::Lang::ml('bml.badcontent.body') } )
        if $errors->exist;

    ##### figure out what fields we're exporting

    my @fields;
    my $opts = { format => $format };    # information needed by printing routines

    foreach my $f (qw(itemid eventtime logtime subject event security allowmask)) {
        push @fields, $f if $post->{"field_${f}"};
    }

    if ( $post->{field_currents} ) {
        push @fields, ( "current_music", "current_mood" );
        $opts->{currents} = 1;
    }

    my $year  = $post->{year}  ? $post->{year} + 0  : 0;
    my $month = $post->{month} ? $post->{month} + 0 : 0;

    my $sth =
        $dbcr->prepare(
              "SELECT jitemid, anum, eventtime, logtime, security, allowmask FROM log2 "
            . "WHERE journalid=? AND year=? AND month=?" );
    $sth->execute( $u->id, $year, $month );

    return DW::Template->render_template( 'error.tt', { message => $dbcr->errstr } )
        if $dbcr->err;

    #### do file-format specific initialization

    if ( $format eq "csv" ) {
        $r->content_type("text/plain");
        my $filename = sprintf( "%s-%04d-%02d.csv", $u->user, $year, $month );
        $r->header_out_add( 'Content-Disposition' => "attachment; filename=$filename" );
        $r->print( join( ",", @fields ) . "\n" ) if $post->{header};
    }

    if ( $format eq "xml" ) {
        my $lenc = lc $encoding;
        $r->content_type("text/xml; charset=$lenc");
        $r->print(qq{<?xml version="1.0" encoding='$lenc'?>\n});
        $r->print("<livejournal>\n");
    }

    $opts->{fields}        = \@fields;
    $opts->{encoding}      = $encoding;
    $opts->{notranslation} = 1 if $post->{notranslation};

    my @buffer;

    while ( my $i = $sth->fetchrow_hashref ) {
        $i->{'ritemid'} = $i->{'jitemid'} || $i->{'itemid'};
        $i->{'itemid'}  = $i->{'jitemid'} * 256 + $i->{'anum'} if $i->{'jitemid'};
        push @buffer, $i;

        # process 20 entries at a time

        if ( scalar @buffer == 20 ) {
            $r->print($_) foreach @{ _load_buffer( $u, \@buffer, $dbcr, $opts ) };
            @buffer = ();
        }

    }

    $r->print($_) foreach @{ _load_buffer( $u, \@buffer, $dbcr, $opts ) };

    $r->print("</livejournal>\n") if $format eq "xml";

    return $r->OK;
}

sub _load_buffer {
    my ( $u, $buf, $dbcr, $opts ) = @_;
    my %props;

    my @ids = map { $_->{ritemid} } @{$buf};
    my $lt  = LJ::get_logtext2( $u, @ids );
    LJ::load_log_props2( $dbcr, $u->id, \@ids, \%props );

    my @result;

    foreach my $e ( @{$buf} ) {
        $e->{'subject'} = $lt->{ $e->{'ritemid'} }->[0];
        $e->{'event'}   = $lt->{ $e->{'ritemid'} }->[1];

        my $eprops = $props{ $e->{'ritemid'} };

        # convert to UTF-8 if necessary
        if ( $eprops->{'unknown8bit'} && !$opts->{'notranslation'} ) {
            my $error;
            $e->{'subject'} = LJ::text_convert( $e->{'subject'}, $u, \$error );
            $e->{'event'}   = LJ::text_convert( $e->{'event'},   $u, \$error );
            foreach ( keys %{$eprops} ) {
                $eprops->{$_} = LJ::text_convert( $eprops->{$_}, $u, \$error );
            }
        }

        if ( $opts->{'currents'} ) {
            $e->{'current_music'} = $eprops->{'current_music'};
            $e->{'current_mood'}  = $eprops->{'current_mood'};
            if ( $eprops->{current_moodid} ) {
                my $mood = DW::Mood->mood_name( $eprops->{current_moodid} );
                $e->{current_mood} = $mood if $mood;
            }
        }

        my $entry = _dump_entry( $e, $opts );

        # now translate this to the chosen encoding but only if this is a
        # Unicode environment. In a pre-Unicode environment the chosen encoding
        # is merely a label.

        if ( lc( $opts->{'encoding'} ) ne 'utf-8' && !$opts->{'notranslation'} ) {
            $entry = Unicode::MapUTF8::from_utf8(
                {
                    -string  => $entry,
                    -charset => $opts->{'encoding'}
                }
            );
        }

        push @result, $entry;
    }

    return \@result;
}

sub _dump_entry {
    my ( $e, $opts ) = @_;

    my $format = $opts->{format};
    my $entry  = "";
    my @vals   = ();

    if ( $format eq "xml" ) {
        $entry .= "<entry>\n";
    }

    foreach my $f ( @{ $opts->{fields} } ) {
        my $v = $e->{$f};
        if ( $format eq "csv" ) {
            if ( $v =~ /[\"\n\,]/ ) {
                $v =~ s/\"/\"\"/g;
                $v = "\"$v\"";
            }
        }
        if ( $format eq "xml" ) {
            $v = LJ::exml($v);
        }
        push @vals, $v;
    }

    if ( $format eq "csv" ) {
        $entry .= join( ",", @vals ) . "\n";
    }

    if ( $format eq "xml" ) {
        foreach my $f ( @{ $opts->{fields} } ) {
            my $v = shift @vals;
            $entry .= "<$f>" . $v . "</$f>\n";
        }
        $entry .= "</entry>\n";
    }

    return $entry;
}

1;
