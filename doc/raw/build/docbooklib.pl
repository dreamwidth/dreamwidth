#!/usr/bin/perl
#

 use strict;

 my %special = (
     'logprops' => '<xref linkend="ljp.csp.proplist" />',
     'ljhome'   => '<link linkend="lj.install.ljhome"><parameter>$<envar>LJHOME</envar></parameter></link>',
     'helpurls' => '<xref linkend="lj.install.ljconfig.helpurls" />',
     'disabled' => '<xref linkend="lj.install.ljconfig.disabled" />',
     'dbinfo' => '<xref linkend="lj.install.ljconfig.dbinfo" />',
     'caps' => '<xref linkend="lj.install.ljconfig.caps" />',
     'hooks' => '<xref linkend="hooksdef" />',
     'reluserdefs'  => '<xref linkend="reluserdefs" />',
     'mhprops'  => '<xref linkend="mhprops" />',
     'cspversion' => '<xref linkend="ljp.csp.versions" />',
 );

 sub cleanse
 {
     my $text = shift;
     # Escape bare ampersands
     $$text =~ s/&(?!(?:[a-zA-Z0-9]+|#\d+);)/&amp;/g;
     # Escape HTML
     $$text =~ s/</&lt;/g;
     $$text =~ s/>/&gt;/g;
     # Convert intended markup to docbook
     $$text =~ s/&lt;b&gt;(.+?)&lt;\/b&gt;/<emphasis role='strong'>$1<\/emphasis>/ig;
     $$text =~ s/&lt;strong&gt;(.+?)&lt;\/strong&gt;/<emphasis role='strong'>$1<\/emphasis>/ig;
     $$text =~ s/&lt;tt&gt;(.+?)&lt;\/tt&gt;/<literal>$1<\/literal>/ig;
     $$text =~ s/&lt;i&gt;(.+?)&lt;\/i&gt;/<replaceable class='parameter'>$1<\/replaceable>/ig;
     $$text =~ s/&lt;u&gt;(.+?)&lt;\/u&gt;/<emphasis>$1<\/emphasis>/ig;
     xlinkify($text);
 }

 sub canonize
 {
     my $type = lc(shift);
     my $name = shift;
     my $function = shift;
     my $string = lc($name);
     if ($type eq "func") {
         $string =~ s/::/./g;
         my $format = "ljp.api.$string";
         $string = $function eq "link" ? "<link linkend=\"$format\">$name</link>" : $format;
     } elsif($type eq "dbtable") {
         $string = "<link linkend=\"ljp.dbschema.$string\">$name</link>";
     } elsif($type eq "special") {
         $string = %special->{$string};
     } elsif($type eq "ljconfig") {
         $string = "<xref linkend=\"ljconfig.$string\" />";
     } elsif($type eq "var") {
         $string = "<xref linkend=\"ljp.styles.s1.$string\" />";
     } elsif($type eq "view") {
         $string = "<link linkend=\"ljp.styles.s1.$string\">$name</link>";
     }
 }

 sub xlinkify
 {
     my $a = shift;
     $$a =~ s/\[(\S+?)\[(\S+?)\]\]/canonize($1, $2, "link")/ge;
 }

