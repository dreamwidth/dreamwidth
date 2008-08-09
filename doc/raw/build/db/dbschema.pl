#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbr = LJ::get_dbh("slave", "master");
my $sth;

sub magic_links
{
    my $des = shift;
    $$des =~ s!<!&lt;!g;
    $$des =~ s!>!&gt;!g;
    $$des =~ s!\[dbtable\[(\w+?)\]\]!<dbtblref tblid="$1">$1</dbtblref>!g;
}

sub dump_xml
{
    my $tables = shift;

    print "<?xml version=\"1.0\" ?>\n";
    print "<!DOCTYPE dbschema SYSTEM \"dbschema.dtd\">\n";
    print "<dbschema>\n";
    foreach my $table (sort keys %$tables)
    {
        print "<dbtbl id=\"$table\">\n";

        # table name
        print "<name>$table</name>\n";

        # description of table
        if ($tables->{$table}->{'des'}) {
            my $des = $tables->{$table}->{'des'};
            magic_links(\$des);
            print "<description>$des</description>\n";
        }

        # columns
        foreach my $col (@{$tables->{$table}->{'cols'}})
        {
            print "<dbcol id=\"$table.$col->{'name'}\" type=\"$col->{'type'}\" required=\"$col->{'required'}\" default=\"$col->{'default'}\">\n";
            print "<name>$col->{'name'}</name>\n";
            if ($col->{'des'}) {
                my $des = $col->{'des'};
                magic_links(\$des);
                print "<description>$des</description>\n";
            }
            print "</dbcol>\n";
        }

        # indexes
        foreach my $indexname (sort keys %{$tables->{$table}->{'index'}})
        {
            my $index = $tables->{$table}->{'index'}->{$indexname};

            print "<dbkey name=\"$indexname\" type=\"$index->{'type'}\" colids=\"", join(" ", @{$index->{'cols'}}), "\" />\n";
        }

        print "</dbtbl>\n";
    }
    print "</dbschema>\n";
}

my %table;
my %coldes;

foreach (`$LJ::HOME/bin/upgrading/update-db.pl --listtables`) {
    chomp;
    $table{$_} = {};
}

$sth = $dbr->prepare("SELECT tablename, public_browsable, des FROM schematables");
$sth->execute;
while (my ($name, $public, $des) = $sth->fetchrow_array) {
    next unless (defined $table{$name});
    $table{$name} = { 'public' => $public, 'des' => $des };
}

$sth = $dbr->prepare("SELECT tablename, colname, des FROM schemacols");
$sth->execute;
while (my ($table, $col, $des) = $sth->fetchrow_array) {
    next unless (defined $table{$table});
    $coldes{$table}->{$col} = $des;
}

foreach my $table (sort keys %table)
{
    $sth = $dbr->prepare("DESCRIBE $table");
    $sth->execute;
    while (my $r = $sth->fetchrow_hashref)
    {
        my $col = {};
        $col->{'name'} = $r->{'Field'};

        my $type = $r->{'Type'};
        $type =~ s/int\(\d+\)/int/g;
        if ($r->{'Extra'} eq "auto_increment") {
            $type .= " auto_increment";
        }
        $col->{'type'} = $type;

        $col->{'default'} = $r->{'Default'};
        $col->{'required'} = $r->{'Null'} eq "YES" ? "false" : "true";

        $col->{'des'} = $coldes{$table}->{$r->{'Field'}};

        push @{$table{$table}->{'cols'}}, $col;
    }

    $sth = $dbr->prepare("SHOW INDEX FROM $table");
    $sth->execute;
    while (my $r = $sth->fetchrow_hashref)
    {
        my $name = $r->{'Key_name'};
        my $type = $r->{'Non_unique'} ? "INDEX" : "UNIQUE";
        if ($name eq "PRIMARY") { $type = "PRIMARY"; }

        $table{$table}->{'index'}->{$name}->{'type'} = $type;
        push @{$table{$table}->{'index'}->{$name}->{'cols'}}, "$table.$r->{'Column_name'}";
    }
}

dump_xml(\%table);
