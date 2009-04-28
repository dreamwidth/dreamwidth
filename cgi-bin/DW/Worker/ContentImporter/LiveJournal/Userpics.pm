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
use Time::HiRes qw/ tv_interval gettimeofday /;
use DW::Worker::ContentImporter::Local::Userpics;

sub work {

    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_userpics', $job, 'Failure running job: %s', $msg );
    }
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;
    my $begin_time = [ gettimeofday() ];

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_userpics', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_userpics', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_userpics', $job, @_ ); };
    my $status    = sub { return $class->status( $data, 'lj_userpics', { @_ } ); };

    # logging sub
    my ( $logfile, $last_log_time );
    my $log = sub {
        $last_log_time ||= [ gettimeofday() ];

        unless ( $logfile ) {
            mkdir "$LJ::HOME/logs/imports";
            mkdir "$LJ::HOME/logs/imports/$opts->{userid}";
            open $logfile, ">>$LJ::HOME/logs/imports/$opts->{userid}/$opts->{import_data_id}.lj_userpics.$$"
                or return $temp_fail->( 'Internal server error creating log.' );
            print $logfile "[0.00s 0.00s] Log started at " . LJ::mysql_time(gmtime()) . ".\n";
        }

        my $fmt = "[%0.4fs %0.1fs] " . shift() . "\n";
        my $msg = sprintf( $fmt, tv_interval( $last_log_time ), tv_interval( $begin_time), @_ );

        print $logfile $msg;
        $job->debug( $msg );

        $last_log_time = [ gettimeofday() ];

        return undef;
    };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    $0 = sprintf( 'content-importer [userpics: %s(%d)]', $u->user, $u->id );

# FIXME: URL may not be accurate here for all sites
    my ( $default, @pics ) = $class->get_lj_userpic_data( "http://$data->{hostname}/users/$data->{username}/", $data, $log );

    my $errs = [];
    my @imported = DW::Worker::ContentImporter::Local::Userpics->import_userpics( $u, $errs, $default, \@pics, $log );
    my $num_imported = scalar( @imported );
    my $to_import = scalar( @pics );

    # FIXME: Uncomment when "select userpics later is implemented"
    #my $has_backup = 0;
    # There's nothing the user can do at this point if Mogile is not available, and any error relating to that will likely confuse them.
    if ( scalar( @imported ) != scalar( @pics ) ) {
        my $mog = LJ::mogclient();
        if ( $mog ) {
            $opts->{userpics_later} = 1;
            my $data = freeze {
                imported => \@imported,
                pics => \@pics,
            };
            $mog->store_content( 'import_upi:' . $u->id, 'temp', $data );
            # FIXME: Uncomment when "select userpics later is implemented"
            #$has_backup = 1;
        }
    }

    # FIXME: Link to "select userpics later" (once it is created) if we have the backup.
    my $message = "$num_imported out of $to_import usericon" . ( $num_imported == 1 ? "" : "s" ) . " successfully imported.";
    $message = "None of your usericons imported successfully." if $num_imported == 0;

    my $text;
    if ( @$errs ) {
        $text = "The following usericons failed to import:\n\n" . join( "\n", map { " * $_" } @$errs ) . "\n\n$message";
    } elsif ( scalar( @imported ) != scalar( @pics ) ) {
        $text = "You did not have enough room to import all your usericons.\n\n$message";
    }

    $status->( text => $text );
    return $ok->();
}

sub get_lj_userpic_data {
    my ( $class, $url, $data, $log ) = @_;
    $url =~ s/\/$//;

    # default, if no log, do nothing
    $log ||= sub { undef };

    my $ua = LJ::get_useragent(
        role     => 'userpic',
        max_size => 524288, # half meg, this should be plenty
        timeout  => 20,     # 20 seconds might need adjusting for slow sites
    );

    my $uurl = "$url/data/userpics";
    $log->( 'Fetching: %s', $uurl );

    my $resp = $ua->get( $uurl );
    return $log->( 'Failed retrieving page.' )
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

            $log->( '    keywords: %s', join( ', ', @keywords ) );

            push @upics, $upic;
        }
    };

    my $parser = new XML::Parser( Handlers => { Start => $upic_handler, Char => $upic_content, End => $upic_closer } );

    $log->( 'Parsing XML output.' );
    $parser->parse( $content );

    return ( $default_upic, @upics );
}


1;
