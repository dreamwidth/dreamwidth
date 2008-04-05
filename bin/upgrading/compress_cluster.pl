#!/usr/bin/perl

use strict;

my $clusterid = shift;
die "Usage: compress_cluster <clusterid>\n"
    unless $clusterid;

# load libraries now
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

# force this option on, since that's the point of the tool
$LJ::COMPRESS_TEXT = 1;

my $db = LJ::get_cluster_master($clusterid);
die "Invalid/down cluster: $clusterid\n" unless $db;

# table, column, [ prikey1, prikey2 ]
foreach my $t (['logtext2', 'event', ['journalid', 'jitemid']],
               ['talktext2', 'body', ['journalid', 'jtalkid']]) {

    my ($table, $col, $key) = @$t;
    my ($pk1, $pk2) = @$key; # 2 sections of primary key

    my $total = $db->selectrow_array("SELECT COUNT(*) FROM $table");

    print "Processing table: $table [$total total rows]\n";

    $db->do("HANDLER $table OPEN");
    my $ct = 0;
    my $modct = 0;

    my $bytes_pre;
    my $bytes_post;

    my $stats = sub {
        printf("%6.2f%% done (mod=%.2f%%, size=%.2f%%),\n", 
               ($ct / $total) * 100,
               ($modct / $ct) * 100,
               ($bytes_post / $bytes_pre) * 100);
    };

    my $loop = 1;
    while ($loop) {
        my $sth = $db->prepare("HANDLER $table READ `PRIMARY` NEXT LIMIT 100");
        $sth->execute;
        $loop = 0;

        while (my $row = $sth->fetchrow_hashref) {
         
            $loop = 1;
            # print status
            $stats->() if (++$ct % 1000 == 0);
            
            # try to compress the text
            my $orig_len = length($row->{$col});
            $bytes_pre += $orig_len;
            my $new_text = LJ::text_compress($row->{$col});
            my $new_len = length($new_text);
            $bytes_post += $new_len;
            
            # do nothing if the "compressed" and uncompressed sizes are the same
            next if $new_text eq $row->{$col};
            
            # update this row since it compressed
            $db->do("UPDATE $table SET $col=? WHERE $pk1=? AND $pk2=? AND $col=?",
                    undef, $new_text, $row->{$pk1}, $row->{$pk2}, $row->{$col});
            
            $modct++;
        }
    }
    $stats->();

    $db->do("HANDLER $table CLOSE");

    print "$ct rows processed, $modct modified\n\n";
}
