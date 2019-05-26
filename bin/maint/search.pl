#!/usr/bin/perl
#
# bin/maint/search.pl
#
# Maintenance tasks related to the search system.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use Carp qw/ croak /;

our %maint;

$maint{'copy_supportlog'} = sub {
    my $dbsx = LJ::get_dbh('sphinx_search')
        or croak "Unable to connect to Sphinx search database.";
    my $dbr = LJ::get_db_reader()
        or croak "Unable to get database reader.";

    my $dbmax = $dbr->selectrow_array('SELECT MAX(splid) FROM supportlog');
    croak $dbr->errstr if $dbr->err;

    my $sxmax = $dbsx->selectrow_array('SELECT MAX(id) FROM support_raw');
    croak $dbsx->errstr if $dbsx->err;

    my $delta = $dbmax - $sxmax;
    if ( $delta <= 0 ) {
        print "-I- No new support log entries to copy.\n";
        return;
    }
    print "-I- Copying $delta support log entries...\n";

    for ( my $i = $sxmax ; $i <= $dbmax ; $i += 100 ) {
        my $rows = $dbr->selectall_arrayref(
            q{SELECT splid, spid, timelogged, faqid, userid, message
              FROM supportlog WHERE splid BETWEEN ? AND ?},
            undef, $i + 1, $i + 100
        );
        croak $dbr->errstr if $dbr->err;

        my $ct = scalar(@$rows);
        print "    ... inserting $ct entries\n";

        foreach my $row (@$rows) {
            $dbsx->do(
                q{INSERT INTO support_raw (id, spid, touchtime, faqid, poster_id, data)
                  VALUES (?, ?, ?, ?, ?, COMPRESS(?))},
                undef, @$row
            );
            croak $dbsx->errstr if $dbsx->err;
        }
    }
};

1;
