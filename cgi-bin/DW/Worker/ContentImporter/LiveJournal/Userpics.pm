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

use DW::Importer::Transform::LJMarkup qw( remap_user_tags );

sub run {
    my ( $class, $ctx ) = @_;
    my $data = $ctx->data;
    my $log  = sub { return $ctx->log(@_) };

    my ( $default, @pics ) = $class->source_for($ctx)->userpics($log);

    # (the default icon is one of the list, so it is rewritten with them)
    $_->{comment} = remap_user_tags( $_->{comment}, $data->{hostname} ) foreach @pics;

    my $errs         = [];
    my @imported     = $ctx->sink->import_userpics( $errs, $default, \@pics, $log );
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

1;
