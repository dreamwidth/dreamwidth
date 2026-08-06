#!/usr/bin/perl
#
# bin/dump-faqs.pl
#
# Dumps the FAQs and their full edit history to JSON Lines, for archiving.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use File::Path qw( make_path );
use File::Spec ();
use JSON       ();

# FAQ text is HTML containing newlines, so TSV is not an option here.
#
# utf8(0) with a :raw filehandle is deliberate: DW does not set
# mysql_enable_utf8, so DBI hands back UTF-8 *bytes*. Letting JSON encode them
# would treat each byte as a codepoint and double-encode the result. Passing the
# bytes through untouched keeps the dump byte-identical to what is in the table.
my $json = JSON->new->utf8(0)->canonical;

my $dir = shift @ARGV
    or die "Usage: dump-faqs.pl <output-directory>\n";

make_path($dir) unless -d $dir;
die "Not a directory: $dir\n" unless -d $dir;

my $dbr = LJ::get_db_reader()
    or die "Failed to get database reader.\n";

my $FAQ_DMID = do {
    my $dom = LJ::Lang::get_dom("faq")
        or die "No 'faq' translation domain.\n";
    $dom->{dmid};
};

# Both lookups are resolved up front: mysql_use_result monopolises the handle
# while streaming, so no second query can run mid-dump.
my %username   = %{ load_usernames() };
my %is_current = %{
    $dbr->selectall_hashref( "SELECT lnid, itid, txtid FROM ml_latest WHERE dmid=$FAQ_DMID",
        [qw( lnid itid )] )
};
my %chgtime = %{
    $dbr->selectall_hashref( "SELECT lnid, itid, chgtime FROM ml_latest WHERE dmid=$FAQ_DMID",
        [qw( lnid itid )] )
};

dump_rows(
    'faq.jsonl',
    "SELECT faqid, question, summary, answer, sortorder, faqcat,
            lastmodtime, lastmoduserid
     FROM faq ORDER BY faqid",
    sub {
        my $r = shift;
        $r->{lastmodusername} = $username{ $r->{lastmoduserid} };
        return $r;
    }
);

dump_rows( 'faqcat.jsonl', "SELECT faqcat, faqcatname, catorder FROM faqcat ORDER BY faqcat" );

# ml_text accumulates a row per edit (LJ::Lang::set_text appends rather than
# updating), so this is the actual FAQ revision history. It carries no
# timestamp of its own -- only the current revision has one, via ml_latest --
# so txtid, which is auto-increment, is the only ordering available.
dump_rows(
    'faq_history.jsonl',
    "SELECT t.txtid, t.itid, t.lnid, i.itcode, l.lnname, t.userid, t.text
     FROM ml_text t
     JOIN ml_items i ON i.dmid = t.dmid AND i.itid = t.itid
     JOIN ml_langs l ON l.lnid = t.lnid
     WHERE t.dmid = $FAQ_DMID
     ORDER BY t.itid, t.lnid, t.txtid",
    sub {
        my $r = shift;

        # The domain holds two kinds of item: FAQ text as "<faqid>.<n><field>"
        # (e.g. "26.1question"), and category display names as "cat.<faqcat>",
        # which the admin page also routes through set_text. Classify both so
        # category renames stay in the history rather than landing as nulls.
        if ( my ( $faqid, $field ) = $r->{itcode} =~ /^(\d+)\.\d+(\w+)$/ ) {
            $r->{kind}  = 'faq';
            $r->{faqid} = $faqid + 0;
            $r->{field} = $field;
        }
        elsif ( my ($faqcat) = $r->{itcode} =~ /^cat\.(.+)$/ ) {
            $r->{kind}   = 'faqcat';
            $r->{faqcat} = $faqcat;
            $r->{field}  = 'faqcatname';
        }
        else {
            $r->{kind} = 'unknown';
        }

        my $cur = $is_current{ $r->{lnid} }{ $r->{itid} };
        $r->{is_current} = ( $cur && $cur->{txtid} == $r->{txtid} ) ? 1 : 0;
        $r->{chgtime} =
            $r->{is_current} ? $chgtime{ $r->{lnid} }{ $r->{itid} }{chgtime} : undef;

        $r->{username} = $username{ $r->{userid} };
        return $r;
    }
);

# Every userid that appears in either dump, so the archive is readable without
# needing the user table alongside it.
sub load_usernames {
    my $ids = $dbr->selectcol_arrayref(
        "SELECT DISTINCT lastmoduserid FROM faq
         UNION
         SELECT DISTINCT userid FROM ml_text WHERE dmid=$FAQ_DMID"
    );
    die $dbr->errstr if $dbr->err;

    my @ids = grep { $_ } @$ids;
    return {} unless @ids;

    my $in = join ',', map { $_ + 0 } @ids;
    return $dbr->selectall_hashref( "SELECT userid, user FROM user WHERE userid IN ($in)",
        'userid' );
}

sub dump_rows {
    my ( $filename, $sql, $transform ) = @_;

    my $path = File::Spec->catfile( $dir, $filename );
    open my $fh, '>', $path or die "Failed to open $path: $!\n";
    binmode $fh, ':raw';

    my $sth = $dbr->prepare( $sql, { mysql_use_result => 1 } );
    $sth->execute;
    die $dbr->errstr if $dbr->err;

    my $rows = 0;
    while ( my $row = $sth->fetchrow_hashref ) {
        my %rec = %$row;
        my $out = $transform ? $transform->( \%rec ) : \%rec;
        print $fh $json->encode($out) . "\n";
        $rows++;
    }
    die $dbr->errstr if $dbr->err;

    close $fh or die "Failed to close $path: $!\n";

    die "Refusing to write an empty $filename\n" unless $rows;
    print "-I- $path: $rows rows\n";
}
