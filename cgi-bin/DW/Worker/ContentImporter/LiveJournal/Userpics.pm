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
use DW::XML::Parser;

sub run {
    my ( $class, $ctx ) = @_;
    my ( $u, $data ) = ( $ctx->u, $ctx->data );
    my $log = sub { return $ctx->log(@_) };

    # FIXME: URL may not be accurate here for all sites
    my $fetch_error = "";
    my $un          = $data->{usejournal} || $data->{username};
    my ( $default, @pics ) = $class->get_lj_userpic_data( "http://$data->{hostname}/users/$un/",
        $data, $log, \$fetch_error );

    return $ctx->temp_fail("Could not import icons for $un: $fetch_error")
        if $fetch_error;

    my $errs = [];
    my @imported =
        DW::Worker::ContentImporter::Local::Userpics->import_userpics( $u, $errs, $default, \@pics,
        $log );
    my $num_imported = scalar(@imported);
    my $to_import    = scalar(@pics);

    # FIXME: Link to "select userpics later" (once it is created) if we have the backup.
    my $message =
          "$num_imported out of $to_import usericon"
        . ( $to_import == 1 ? "" : "s" )
        . " successfully imported.";
    $message = "None of your usericons imported successfully." if $num_imported == 0;
    $message = "There were no usericons to import."            if $to_import == 0;

    my $text;
    if (@$errs) {
        $text =
              "The following usericons failed to import:\n\n"
            . join( "\n", map { " * $_" } @$errs )
            . "\n\n$message";
    }
    elsif ( scalar(@imported) != scalar(@pics) ) {
        $text = "You did not have enough room to import all your usericons.\n\n$message";
    }
    else {
        # for example, when no icons could be imported.
        $text = $message;
    }

    $ctx->status( text => $text );
    return $ctx->ok;
}

sub get_lj_userpic_data {
    my ( $class, $url, $data, $log, $err_ref ) = @_;
    $url =~ s/\/$//;

    # default, if no log, do nothing
    $log ||= sub { undef };

    my $ua = LJ::get_useragent(
        role     => 'userpic',
        max_size => 524288,      # half meg, this should be plenty
        timeout  => 20,          # 20 seconds might need adjusting for slow sites
    );

    my $uurl = "$url/data/userpics";
    $log->( 'Fetching: %s', $uurl );

    my $resp = $ua->get($uurl);
    unless ( $resp && $resp->is_success ) {
        my $error_message = 'Failed retrieving page (' . $resp->status_line . ').';
        $$err_ref = $error_message if $err_ref;
        return $log->($error_message);
    }

    my $content = $resp->content;

    my ( @upics, $upic, $default_upic, $text_tag );

    my $cleanup_string = sub {

# FIXME: If LJ ever fixes their /data/userpics feed to double-escape, this will cause issues.
# Probably need to figure out a way to detect that a double-escape happened and only fix in that case.
        return LJ::dhtml( encode_utf8( $_[0] || "" ) );
    };

    my $upic_handler = sub {
        my $tag = $_[1];
        shift;
        shift;
        my %temp = (@_);

        if ( $tag eq 'entry' ) {
            $upic = { keywords => [] };
        }
        elsif ( $tag eq 'content' ) {
            $upic->{src} = $temp{src};
        }
        elsif ( $tag eq 'category' ) {

# keywords get triple-escaped
# DW::XML::Parser handles unescaping it once, $cleanup_string second, and then we have to unescape it a third time.
            push @{ $upic->{keywords} }, LJ::dhtml( $cleanup_string->( $temp{term} ) );
        }
        else {
            $text_tag = $tag;
        }
    };

    my $upic_content = sub {
        my $text = $_[1];

        if ( $text_tag eq 'title' && $text eq 'default userpic' ) {
            $default_upic = $upic;
            $upic->{default} = 1;
        }
        elsif ( $text_tag eq 'summary' ) {
            $text =~ s/\n//g;
            $text =~ s/^ +$//g;
            $upic->{comment} .= $text;
        }
        elsif ( $text_tag eq 'id' ) {
            my @parts = split( /:/, $text );
            $upic->{id} = $parts[-1];
            $text_tag = undef;
        }
    };

    my $upic_closer = sub {
        my $tag = $_[1];

        if ( $tag eq 'entry' ) {
            my @keywords;
            foreach my $kw ( @{ $upic->{keywords} } ) {
                push @keywords, $kw;
            }

            $upic->{keywords} = \@keywords;
            my $comment = $cleanup_string->( $upic->{comment} );
            $upic->{comment} = $class->remap_lj_user( $data, $comment );

            $log->( '    keywords: %s', join( ', ', @keywords ) );

            push @upics, $upic;
        }
    };

    my $parser = new DW::XML::Parser(
        Handlers => { Start => $upic_handler, Char => $upic_content, End => $upic_closer } );

    $log->('Parsing XML output.');
    $parser->parse($content);

    return ( $default_upic, @upics );
}

1;
