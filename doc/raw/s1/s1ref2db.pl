#!/usr/bin/perl
#

 use strict;

 unless (-d $ENV{'LJHOME'}) { die "\$LJHOME not set.\n"; }

 require "$ENV{'LJHOME'}/doc/raw/build/docbooklib.pl";
 require "$ENV{'LJHOME'}/cgi-bin/propparse.pl";
 require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

 my @views;
 my @vars;

 LJ::load_objects_from_file("views.dat", \@views);
 LJ::load_objects_from_file("vars.dat", \@vars);

 my $ret;
 my %done;
 foreach my $vi (@views)
 {
     $ret .= "<appendix id='ljp.styles.s1.$vi->{'name'}'><title>S1 Variable Reference: $vi->{'props'}->{'name'}</title>\n";
     cleanse->(\$vi->{'props'}->{'des'});
     $ret .= "  <abstract><para>$vi->{'props'}->{'des'}</para>";
     $ret .= "    <simpara><ulink url='" . LJ::ehtml($vi->{'props'}->{'url'}) . "'>Example page</ulink></simpara></abstract>\n";
         foreach my $v (sort { $a->{'name'} cmp $b->{'name'} } @vars)
         {
             next unless ($v->{'props'}->{'scope'} =~ /\b$vi->{'name'}\b/);
             next if $done{$v};

             cleanse->(\$v->{'props'}->{'des'});

             my $id = lc($v->{'name'});
             $ret .= "<refentry id='ljp.styles.s1.$id'>\n";
             $ret .= "  <refnamediv>\n<refname>$v->{'name'}</refname>\n<refpurpose>$v->{'props'}->{'des'}</refpurpose>\n</refnamediv>";

             $ret .= "  <refsection><title>View Types:</title><simpara>\n";
             foreach (split (/\s*\,\s*/, $v->{'props'}->{'scope'}))
             {
                 $ret .= "<link linkend='ljp.styles.s1.$_\'>$_</link>, ";
             }
             chop $ret; chop $ret;
             $ret .= "</simpara></refsection>";

             # overrideable?
             $ret .= " <refsection><title>Overrideable:</title><simpara>";
             if ($v->{'props'}->{'override'} eq "yes") {
                 $ret .= "Yes; users of this style may override this";
             } elsif ($v->{'props'}->{'override'} eq "only") {
                 $ret .= "Only users of this style may override this. It cannot be defined in a style.";
             } else {
                 $ret .= "No; users of the style cannot override this.  It may only be defined in the style.";
             }
             $ret .= "</simpara></refsection>\n";

             if (defined $v->{'props'}->{'type'})
             {
                 $ret .= "  <refsection><title>Variable Type</title><simpara>$v->{'props'}->{'type'}</simpara></refsection>\n";
             }
             if (defined $v->{'props'}->{'default'})
             {
                 $ret .= "  <refsection><title>Default Value</title><simpara>$v->{'props'}->{'default'}</simpara></refsection>\n";
             }
             if (defined $v->{'props'}->{'props'})
             {
                 $ret .= "  <refsection><title>Properties</title>\n";
                 $ret .= "    <informaltable><tgroup cols='2'><tbody>\n";
                 foreach my $p (@{$v->{'props'}->{'props'}})
                 {
                     cleanse->(\$p->{'props'}->{'des'});
                     $ret .= "<row><entry>$p->{'name'}</entry>\n";
                     $ret .= "<entry>$p->{'props'}->{'des'} ";
                     if ($p->{'props'}->{'min'} > 0)
                     {
                         $ret .= "[required]";
                     }
                     $ret .= "</entry></row>\n";
                 }
                 $ret .= "</tbody></tgroup></informaltable></refsection>\n";
             }
             $ret .= "</refentry>\n";
             $done{$v} = 1;
         }
     $ret .= "</appendix>\n";
 }

 print $ret;
