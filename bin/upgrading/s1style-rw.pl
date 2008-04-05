#!/usr/bin/perl
#
# Library to read/write s1styles.dat
#

sub s1styles_read
{
    my $ss = {};

    open (F, "$ENV{'LJHOME'}/bin/upgrading/s1styles.dat");
    my $uniq;
    my $entry;
    my $read_entry = 0;
    my $line = 0;
    while (<F>) 
    {
        $line++;
        if ($read_entry && $entry) 
        {
            if ($_ eq ".\n") {
                chop $entry->{'formatdata'}; # we added a newline
                $read_entry = 0;
                undef $entry;
                next;
            }
            s!^\.!!;
            $entry->{'formatdata'} .= $_;
            next;
        }

        if (m!^Style:\s*(\w+?)/(.+?)\s*$!) {
            $uniq = "$1/$2";
            die "Repeat style in s1styles.dat at line $line!"
                if exists $ss->{$uniq};
            $entry = $ss->{$uniq} = {
                'type' => $1,
                'styledes' => $2,
            };
            $read_entry = 0;
            next;
        }

        if ($entry && $_ eq "\n") {
            $read_entry = 1;
            next;
        }

        next unless $entry;
        if (/^(\w+):\s*(.+?)\s*$/) {
            $entry->{$1} = $2;
            next;
        }

        die "s1styles.dat:$line: bogus line\n" if /\S/;
    }
    close F;

    return $ss;
}

sub s1styles_write
{
    my $ss = shift;

    open (F, ">$ENV{'LJHOME'}/bin/upgrading/s1styles.dat")
        or die "Can't open s1styles.dat for writing.\n";

    foreach my $uniq (sort keys %$ss) {
        my $s = $ss->{$uniq};
        print F "Style: $uniq\n";
        foreach (qw(is_public is_embedded is_colorfree opt_cache lastupdate)) {
            next unless exists $s->{$_};
            print F "$_: $s->{$_}\n";
        }
        
        my $formatdata = $s->{'formatdata'};
        $formatdata =~ s/\r//g;               # die, DOS line endings!
        $formatdata =~ s/\n\./\n\.\./g;
        print F "\n$formatdata\n.\n\n";
    }
    close F;

}

1;
