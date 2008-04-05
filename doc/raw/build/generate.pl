#!/usr/bin/perl

use strict;
use Getopt::Long;

my $XSL_VERSION_RECOMMENDED = "1.73.2";

my $opt_clean;
my ($opt_myxsl, $opt_getxsl, $opt_single);
exit 1 unless GetOptions('clean' => \$opt_clean,
                         'myxsl' => \$opt_myxsl,
                         'getxsl' => \$opt_getxsl,
                         'single' => \$opt_single,
                         );

my $home = $ENV{'LJHOME'};
require "$home/cgi-bin/ljlib.pl";
$ENV{'XML_CATALOG_FILES'} = $LJ::CATALOG_FILES || "/usr/share/xml/docbook/schema/dtd/4.4/catalog.xml";

unless (-e $ENV{'XML_CATALOG_FILES'}) {
    die "Catalog files don't exist.  Either set \$LJ::CATALOG_FILES, install docbook-xml (on Debian), or symlink $ENV{'XML_CATALOG_FILES'} to XML DocBook 4.4's catalog.xml.";
}

die "One or more of Siteroot, Domain, or Admin e-mail not set" unless $LJ::SITEROOT;
open F, "> $home/doc/raw/entities/prevar.gen.ent" or die "Can't open prevar.gen.ent : $!";
{
    print F "<!ENTITY siteroot '$LJ::SITEROOT'>\n";
    print F "<!ENTITY domain '$LJ::DOMAIN'>\n";
    print F "<!ENTITY adminemail '$LJ::ADMIN_EMAIL'>\n";
}
close F;

if ($opt_getxsl) {
    chdir "$home/doc/raw/build" or die "Where is build dir?";
    unlink "xsl-docbook.tar.gz";
    my $fetched =  0;
    my $url = "http://code.sixapart.com/svn/ljdocbook/trunk/dist/xsl/xsl-docbook.tar.gz";
    my @fetcher = ([ 'wget', "wget $url", ],
                   [ 'lynx', "lynx -source $url > xsl-docbook.tar.gz", ],
                   [ 'GET', "GET $url > xsl-docbook.tar.gz", ]);
    foreach my $fet (@fetcher) {
        next if $fetched;
        print "Looking for $fet->[0] ...\n";
        next unless `which $fet->[0]`;
        print "RUNNING: $fet->[1]\n";
        system($fet->[1])
            and die "Error running $fet->[0].  Interrupted?\n";
        $fetched = 1;
    }
    unless ($fetched) {
        die "Couldn't find a program to download things from the web.  I looked for:\n\t".
            join(", ", map { $_->[0] } @fetcher) . "\n";
    }
    system("tar", "zxvf", "xsl-docbook.tar.gz")
        and die "Error extracting xsl-docbook.tar.gz; GNU tar installed?\n";
}

my $output_dir = "$home/htdocs/doc/server";
my $docraw_dir = "$home/doc/raw";
my $XSL = "$docraw_dir/build/xsl-docbook";
my $stylesheet = "$XSL/html/chunk.xsl";
open (F, "$XSL/VERSION");
my $XSL_VERSION;
{
    local $/ = undef; my $file = <F>;
$XSL_VERSION = $1 if $file =~ /Version>(.+?)\</;
}
close F;
my $download;
if ($XSL_VERSION && $XSL_VERSION ne $XSL_VERSION_RECOMMENDED && ! $opt_myxsl) {
    print "\nUntested DocBook XSL found at $XSL.\n";
    print "   Your version: $XSL_VERSION.\n";
    print "    Recommended: $XSL_VERSION_RECOMMENDED.\n\n";
    print "Options at this point.  Re-run with:\n";
    print "    --myxsl    to proceed with yours, or\n";
    print "    --getxsl   to install recommended XSL\n\n";
    exit 1;
}
if (! $XSL_VERSION) {
    print "\nDocBook XSL not found at $XSL.\n\nEither symlink that dir to the right ";
    print "place (preferably at version $XSL_VERSION_RECOMMENDED),\nor re-run with --getxsl ";
    print "for me to do it for you.\n\n";
    exit 1;
}

chdir "$docraw_dir/build" or die;

print "Generating API reference\n";
system("api/api2db.pl --exclude=BML:: --book=ljp > $docraw_dir/ljp.book/api/api.gen.xml")
    and die "Error generating General API reference.\n";
system("api/api2db.pl --include=BML:: --book=bml > $docraw_dir/bml.book/api.gen.xml")
    and die "Error generating BML API reference.\n";

print "Generating DB Schema reference\n";
chdir "$docraw_dir/build/db" or die;
system("./dbschema.pl > dbschema.gen.xml")
    and die "Error generating DB schema\n";

my $err = system("xsltproc", "-o", "$docraw_dir/ljp.book/db/schema.gen.xml",
                 "db2ref.xsl", "dbschema.gen.xml");
if ($err == -1) { die "Error; Package 'xsltproc' not installed?\n"; }
elsif ($err) { $err<<8; die "Error transforming DB schema. (error=$err)\n"; }

print "Generating XML-RPC protocol reference\n";
chdir "$docraw_dir/build/protocol" or die;
system("xsltproc", "-o", "$docraw_dir/ljp.book/csp/xml-rpc/protocol.gen.xml",
       "xml-rpc2db.xsl", "xmlrpc.xml")
    and die "Error processing protocol reference.\n";

print "Generating Flat protocol reference\n";
system("./flat2db.pl > $docraw_dir/ljp.book/csp/flat/protocol.gen.xml")
    and die "Error processing protocol reference.\n";

print "Generating Log Prop List\n";
system("./proplist2db.pl > $docraw_dir/ljp.book/csp/proplist.ref.gen.xml")
    and die "Error generating log prop list\n";

print "Generating Privilege list reference\n";
chdir "$docraw_dir/build/priv" or die;
system("./priv2db.pl > $docraw_dir/lj.book/admin/privs.ref.gen.xml")
    and die "Error generating privilege list\n";

#  [placemkr] consoleref gen. removed. breaks now console.pl superseded by LJ::Console

print "Generating Capability Class Reference\n";
chdir "$docraw_dir/build/caps" or die;
system("./cap2db.pl > $docraw_dir/lj.book/admin/cap.ref.gen.xml")
    and die "Error generating caps reference\n";
system("./cap2db.pl > $docraw_dir/ljp.book/int/cap.ref.gen.xml")
    and die "Error generating caps reference\n";

print "Generating Hook Function Reference\n";
chdir "$docraw_dir/build/hooks" or die;
system("./hooks2db.pl > $docraw_dir/lj.book/customize/hooks.ref.gen.xml")
    and die "Error generating hooks reference\n";
system("./hooks2db.pl > $docraw_dir/ljp.book/int/hooks.ref.gen.xml")
    and die "Error generating hooks reference\n";

print "Generating Configuration Variable Reference\n";
chdir "$docraw_dir/build/ljconfig" or die;
system("./ljconfig2db.pl > $docraw_dir/lj.book/install/ljconfig.vars.gen.xml")
    and die "Error generating ljconfig.pl variable reference\n";

print "Generating S1 Variable Reference\n";
chdir "$docraw_dir/s1" or die;
system("./s1ref2db.pl > $docraw_dir/ljp.book/styles/s1/ref.gen.xml")
    and die "Error generating s1 variable reference\n";

print "Generating Perl Module List\n";
chdir "$docraw_dir/build/install" or die;
system("./modulelist2db.pl > $docraw_dir/lj.book/install/perl.module.gen.xml")
    and die "Error generating perl module list\n";

print "Converting to HTML\n";
mkdir $output_dir, 0755 unless -d $output_dir;
chdir $output_dir or die "Couldn't chdir to $output_dir\n";

my $cssparam;
if (-e "$docraw_dir/build/style.css") {
    $cssparam = "--stringparam html.stylesheet style.css";
    system("cp", "$docraw_dir/build/style.css", "$output_dir")
        and die "Error copying stylesheet.\n";
}

system("xsltproc --nonet $cssparam ".
       "$docraw_dir/build/chunk.xsl $docraw_dir/index.xml")
    and die "Error generating chunked HTML.\n";

# FIXME: This is meant to build manual as single HTML page.
if ($opt_single) {
    system("xsltproc --nonet --output manual.html $cssparam ".
       "$docraw_dir/build/nochunk.xsl $docraw_dir/index.xml")
    and die "Error generating single HTML.\n";
}

if ($opt_clean) {
    print "Removing auto-generated files\n";
    system("find $docraw_dir -name '*.gen.*' -type f -print0 \| xargs -0 rm -f");
}

