#!/usr/bin/perl
#

use strict;

require "$LJ::HOME/cgi-bin/ljlib.pl";

my $dbr = LJ::get_dbh("slave", "master");
my $sth;

my $sth = $dbr->prepare("SELECT * FROM logproplist ORDER BY sortorder");
$sth->execute;

    print "  <variablelist>\n";
    print "    <title>Entry Prop List</title>\n\n";

while (my $r = $sth->fetchrow_hashref)
{
    print "        <varlistentry>\n";
    print "           <term><literal role='log.prop'>$r->{'name'}</literal></term>\n";
    print "               <listitem>\n";
    print "                  <para>\n";
    print "                  <emphasis role=\"strong\">$r->{'prettyname'}.</emphasis>\n\n";
    print "                     $r->{'des'}\n";
    print "                     <itemizedlist>\n";
    print "                     <listitem><para><emphasis role=\"strong\">Datatype:</emphasis>\n";
    print "                     $r->{'datatype'}</para></listitem>\n";
    print "                     <listitem><para><emphasis role=\"strong\">Scope:</emphasis>\n";
    print "                     $r->{'scope'}</para></listitem>\n";
    print "                     </itemizedlist>\n";
    print "                  </para>\n";
    print "               </listitem>\n";
    print "        </varlistentry>\n\n";
}
print "</variablelist>\n";

