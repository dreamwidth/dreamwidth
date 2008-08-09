#!/usr/bin/perl
#

use strict;
use Getopt::Long;

my ($opt_include, $opt_exclude, $opt_book);
die unless GetOptions(
                      'include=s' => \$opt_include,
                      'exclude=s' => \$opt_exclude,
                      'book=s' => \$opt_book,
                      );
die "Unknown arguments.\n" if @ARGV;
die "Can't exclude and include at same time!\n" if $opt_include && $opt_exclude;

$LJ::HOME = $ENV{'LJHOME'};

unless (-d $LJ::HOME) {
    die "\$LJHOME not set.\n";
}

require "$LJ::HOME/doc/raw/build/docbooklib.pl";

chdir $LJ::HOME or die "Can't cd to $ENV{'LJHOME'}\n";

unless ($opt_book) { $opt_book = "ljp"; }

### apidoc.pl does all the hard work.
my $VAR1;
my $param;
$param = "--include=$opt_include" if $opt_include;
$param = "--exclude=$opt_exclude" if $opt_exclude;
eval `$LJ::HOME/doc/raw/build/apidoc.pl --conf=$ENV{'LJHOME'}/doc/raw/build/api/apidoc.conf $param`;
my $api = $VAR1;

print "<reference id=\"$opt_book.api.ref\">\n";
print "  <title>API Documentation</title>\n";

foreach my $func (sort keys %$api) {
    my $f = $api->{$func};
    my $argstring;

    my $canonized = canonize("func" , $func, "", $opt_book);
    print "  <refentry id=\"$canonized\">\n";

    ### name and short description:
    cleanse(\$f->{'des'}, $opt_book);
    print "    <refnamediv>\n";
    print "      <refname>$func</refname>\n";
    print "      <refpurpose>$f->{'des'}</refpurpose>\n";
    print "    </refnamediv>\n";

    ### usage:
    print "    <refsynopsisdiv>\n";
    print "      <title>Use</title>\n";
    print "      <funcsynopsis>\n";
    print "        <funcprototype>\n";
    print "          <funcdef><function>$func</function></funcdef>\n";
    if (@{$f->{'args'}}) {
        foreach my $arg (@{$f->{'args'}}) {
            print "          <paramdef><parameter>$arg->{'name'}</parameter></paramdef>\n";
        }
    } else {
            print "          <void/>\n"; }
    print "        </funcprototype>\n";
    print "      </funcsynopsis>\n";
    print "    </refsynopsisdiv>\n";

    ### arguments:
    if (@{$f->{'args'}}) {
        print "    <refsect1>\n";
        print "      <title>Arguments</title>\n";
        print "      <itemizedlist>\n";

        foreach my $arg (@{$f->{'args'}}) {
            print "        <listitem><formalpara>\n";
            print "          <title>$arg->{'name'}</title>\n";
            my $des = $arg->{'des'};
            cleanse(\$des, $opt_book);
            print "          <para>$des</para>\n";
            print "        </formalpara></listitem>\n";
        }
        print "      </itemizedlist>\n";
        print "    </refsect1>\n";
    }

    ### info:
    if ($f->{'info'}) {
        cleanse(\$f->{'info'}, $opt_book);
        print "    <refsect1>\n";
        print "      <title>Info</title>\n";
        print "      <para>$f->{'info'}</para>\n";
        print "    </refsect1>\n";
    }

    ### source file:
    print "    <refsect1>\n";
    print "      <title>Source:</title>\n";
    print "      <para><filename>$f->{'source'}</filename></para>\n";
    print "    </refsect1>\n";

    ### returning:
    if ($f->{'returns'}) {
        cleanse(\$f->{'returns'}, $opt_book);
        print "    <refsect1>\n";
        print "      <title>Returns:</title>\n";
        print "      <para>$f->{'returns'}</para>\n";
        print "    </refsect1>\n";
    }

    print "  </refentry>\n";
}

print "</reference>\n";
