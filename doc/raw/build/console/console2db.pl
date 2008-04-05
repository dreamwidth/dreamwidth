#!/usr/bin/perl
#

use strict;

# FIXME This needs updating. Does not work with LJ::Console, which superseded console.pl.

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

require "$ENV{'LJHOME'}/doc/raw/build/docbooklib.pl";
require "$ENV{'LJHOME'}/cgi-bin/console.pl";
my $ret;

$ret .= "<variablelist><title>Administrative Console Commands</title>\n";
foreach my $cmdname (sort keys %LJ::Con::cmd) {
    my $cmd = $LJ::Con::cmd{$cmdname};
    next if ($cmd->{'hidden'});
    $ret .= "<varlistentry>\n";
    $ret .= "  <term><literal role=\"console.command\">$cmdname</literal></term>\n";
    my $des  = $cmd->{'des'};
    cleanse(\$des);
    $ret .= "  <listitem><para>\n$des\n";
    if ($cmd->{'args'}) {
        $ret .= "    <itemizedlist>\n      <title>Arguments:</title>\n";
        my @args = @{$cmd->{'args'}};
        while (my ($argname, $argdes) = splice(@args, 0, 2)) {
            $ret .= "      <listitem><formalpara>";
            $ret .= "<title>$argname</title>\n";
            cleanse(\$argdes);
            $ret .= "      <para>$argdes</para>\n";
            $ret .= "      </formalpara></listitem>\n";
        }
        $ret .= "    </itemizedlist>\n";
    }
    $ret .= "  </para></listitem>\n";
    $ret .= "</varlistentry>\n";
}
$ret .= "</variablelist>\n";
print $ret;
