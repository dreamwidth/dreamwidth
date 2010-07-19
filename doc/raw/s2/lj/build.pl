#!/usr/bin/perl
#
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

my $home = $LJ::HOME;
require "$home/cgi-bin/ljlib.pl";
require "$home/cgi-bin/LJ/S2.pm";

$ENV{'XML_CATALOG_FILES'} = $LJ::CATALOG_FILES || "/usr/share/xml/docbook/schema/dtd/4.4/catalog.xml";
unless (-e $ENV{'XML_CATALOG_FILES'}) {
    die "Catalog files don't exist.  Either set \$LJ::CATALOG_FILES, install docbook-xml (on Debian), or symlink $ENV{'XML_CATALOG_FILES'} to XML DocBook 4.4's catalog.xml.";
}
if ($opt_getxsl) {
    chdir "$home/doc/raw/build" or die "Where is build dir?";
    unlink "xsl-docbook.tar.gz";
    my $fetched =  0;
    my $url = "http://code.livejournal.org/svn/ljdocbook/trunk/dist/xsl/xsl-docbook.tar.gz";
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
my $output_dir = "$home/htdocs/doc/s2";
my $docraw_dir = "$home/doc/raw";
my $XSL = "$docraw_dir/build/xsl-docbook";
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

open(AUTOGEN, ">$docraw_dir/s2/lj/autogen-entities.xml") || die "Can't open autogen-entities.xml\n";
print AUTOGEN "<!ENTITY siteroot \"$LJ::SITEROOT\">\n";
close(AUTOGEN);

autogen_core();

mkdir $output_dir, 0755 unless -d $output_dir;
chdir $output_dir or die "Couldn't chdir to $output_dir\n";

my $cssparam;
if (-e "$docraw_dir/build/style.css") {
    $cssparam = "--stringparam html.stylesheet style.css";
    system("cp", "$docraw_dir/build/style.css", "$output_dir")
        and die "Error copying stylesheet.\n";
}

system("xsltproc --nonet $cssparam ".
       "$docraw_dir/build/chunk.xsl $docraw_dir/s2/lj/index.xml")
    and die "Error generating chunked HTML.  (No xsltproc?)\n";

if ($opt_single)
{
    system("xsltproc --nonet --output manual.html $cssparam ".
           "$docraw_dir/build/nochunk.xsl $docraw_dir/s2/lj/index.xml")
        and die "Error generating single HTML. (No xsltproc?)\n";
}

sub autogen_core
{
    my $cv = shift;
    unless ($cv) {
        autogen_core(1);
        return;
    }

    my $pub = LJ::S2::get_public_layers();
    my $id = $pub->{"core$cv"};
    $id = $id ? $id->{'s2lid'} : 0;
    die unless $id;

    my $dbr = LJ::get_db_reader();
    my $rv = S2::load_layers_from_db($dbr, $id);
    my $s2info = S2::get_layer_all($id);
    my $class = $s2info->{'class'} || {};

    open (AC, ">$docraw_dir/s2/lj/autogen-core$cv.xml") or die "Can't open autogen-core$cv.xml\n";

    my $xlink = sub {
        my $r = shift;
        $$r =~ s/\[class\[(\w+)\]\]/<link linkend=\"&s2.idroot;core$cv.class.$1\">$1<\/link>/g;
        $$r =~ s/\[method\[(.+?)\]\]/<link linkend=\"&s2.idroot;core$cv.meth.$1\">$1<\/link>/g;
        $$r =~ s/\[function\[(.+?)\]\]/<link linkend=\"&s2.idroot;core$cv.func.$1\">$1<\/link>/g;
        $$r =~ s/\[member\[(.+?)\]\]/<link linkend=\"&s2.idroot;core$cv.member.$1\">$1<\/link>/g;

        my @parts = split(/\s*\/\/\/\s*/, $$r);
        if (@parts > 1) {
            $$r = shift @parts;
            my $see_also;
            foreach my $p (@parts) {
                if ($p =~ /^SeeAlso:\s*(.+)/) {
                    my $ids = $1;
                    my $str = "  (See also: " . join(', ',
                                                     map { "<xref linkend='$_' />"; }
                                                     split(/\s*\,\s*/, $ids)) . ")";
                    $$r .= $str;
                }
            }
        }
    };

    my $xlink_args = sub {
        my $r = shift;
        return unless
            $$r =~ /^(.+?\()(.*)\)$/;
        my ($new, @args) = ($1, split(/\s*\,\s*/, $2));
        foreach (@args) {
            s/^(\w+)/defined $class->{$1} ? "[class[$1]]" : $1/eg;
        }
        $new .= join(", ", @args) . ")";
        $$r = $new;
        $xlink->($r);
    };

    # layerinfo
    #if (my $info = $s2info->{'info'}) {
    #    $body .= "<?h1 Layer Info h1?>";
    #    $body .= "<table class='postheading' style='margin-bottom: 10px' border='1' cellpadding='2'>";
    #    foreach my $k (sort keys %$info) {
    #        my ($ek, $ev) = map { LJ::ehtml($_) } ($k, $info->{$k});
    #        $title = $ev if $k eq "name";
    #        $body .= "<tr><td><b>$ek</b></td><td>$ev</td></tr>\n";
    #    }
    #    $body .= "</table>";
    #}

    # sets
    if (my $prop = $s2info->{'prop'}) {
        my $set = $s2info->{'set'};
        print AC "<section id='&s2.idroot;core$cv.props'>\n";
        print AC "<title>Properties</title>";
        print AC "<variablelist>\n";

        foreach my $pname (sort keys %$prop) {
            my $prop = $prop->{$pname};
            my $des = $prop->{'doc'} || $prop->{'des'};
            $xlink->(\$des);
            print AC "<varlistentry id='&s2.idroot;core$cv.prop.$pname'><term><varname>\$*$pname</varname> : <classname>$prop->{type}</classname></term>\n";
            print AC "<listitem><para>$des</para></listitem>";

            my $v = $set->{$pname};
            if (defined $v) {
                if (ref $v eq "HASH") {
                    if ($v->{'_type'} eq "Color") {
                        # FIXME: emit something we can turn into a colored box in DocBook XSLT
                        $v = $v->{'as_string'};
                    } else {
                        $v = "[unknown object type]";
                    }
                } elsif (ref $v eq "ARRAY") {
                    $v = "<emphasis>List:</emphasis> (" . join(", ", @$v) . ")";
                }

                print AC "<listitem><para><emphasis role='strong'>Base value:</emphasis> $v</para></listitem>\n";
            }

            print AC "</varlistentry>\n";
        }

        print AC "</variablelist>\n";
        print AC "</section>\n";
    }

    # global functions
    my $gb = $s2info->{'global'};
    if (ref $gb eq "HASH" && %$gb) {
        print AC "<section id='&s2.idroot;core$cv.funcs'>\n";
        print AC "<title>Functions</title>";
        print AC "<variablelist>\n";

        foreach my $fname (sort keys %$gb) {
            my $rt = $gb->{$fname}->{'returntype'};
            if (defined $class->{$rt}) {
                $rt = "[class[$rt]]";
            }
            $xlink->(\$rt);
            my $ds = $gb->{$fname}->{'docstring'};
            $xlink->(\$ds);

            my $args = $gb->{$fname}->{'args'};
            $xlink_args->(\$args);

            my $idsig = $fname;
            print AC "<varlistentry id='&s2.idroot;core$cv.func.$idsig'><term><function>$args</function> : $rt</term><listitem><para>$ds</para></listitem></varlistentry>\n";
        }

        print AC "</variablelist>\n";
        print AC "</section>\n";
    }

    if (%$class)
    {
        print AC "<section id='&s2.idroot;core$cv.classes'>\n";
        print AC "  <title>Classes</title>\n";
        print AC "  <toc/>\n";
        foreach my $cname (sort { lc($a) cmp lc($b) } keys %$class) {
            print AC "<refentry id='&s2.idroot;core$cv.class.$cname'>";
            print AC "<refmeta><refentrytitle>$cname Class</refentrytitle></refmeta>";
            my $ds = "<refnamediv><refname>$cname Class</refname><refpurpose>$class->{$cname}->{'docstring'}</refpurpose></refnamediv>";
            if ($class->{$cname}->{'parent'}) {
                $ds .= "<refsect1><title>Parent Class</title><para> Child class of [class[$class->{$cname}->{'parent'}]].</para></refsect1>";
            }

            my @children = grep { $class->{$_}->{'parent'} eq $cname } keys %$class;
            if (@children) {
                $ds .= "<refsect1><title>Derived Classes</title><para> Child classes: " .
                    join(", ", map { "[class[$_]]" } @children) . ".</para></refsect1>";
            }

            if ($ds) {
                $xlink->(\$ds);
                print AC $ds;
            }

            # build functions & methods
            my (%func, %var);
            my $add = sub {
                my ($self, $aname) = @_;
                foreach (keys %{$class->{$aname}->{'funcs'}}) {
                    $func{$_} = $class->{$aname}->{'funcs'}->{$_};
                    $func{$_}->{'_declclass'} = $aname;
                }
                foreach (keys %{$class->{$aname}->{'vars'}}) {
                    $var{$_} = $class->{$aname}->{'vars'}->{$_};
                    $var{$_}->{'_declclass'} = $aname;
                }

                my $parent = $class->{$aname}->{'parent'};
                $self->($self, $parent) if $parent;
            };
            $add->($add, $cname);

            print AC "<refsect1><title>Members</title><variablelist>" if %var;
            foreach (sort keys %var) {
                my $type = $var{$_}->{'type'};
                $type =~ s/(\w+)/defined $class->{$1} ? "[class[$1]]" : $1/eg;
                $xlink->(\$type);

                my $ds = LJ::ehtml($var{$_}->{'docstring'});
                $xlink->(\$ds);

                if ($var{$_}->{'readonly'}) {
                    $ds = "<emphasis role='strong'>(Read-only)</emphasis> $ds";
                }

                print AC "<varlistentry id='&s2.idroot;core$cv.member.${cname}.$_'>";
                print AC "<term><varname>$type $_</varname></term>";
                print AC "<listitem><para>$ds</para></listitem></varlistentry>";
            }
            print AC "</variablelist></refsect1>" if %var;

            print AC "<refsect1><title>Methods</title><variablelist>" if %func;
            foreach (sort keys %func) {
                my $rt = $func{$_}->{'returntype'};
                if (defined $class->{$rt}) {
                    $rt = "[class[$rt]]";
                }
                $xlink->(\$rt);
                my $ds = LJ::ehtml($func{$_}->{'docstring'});
                $xlink->(\$ds);

                my $args = $_;
                $xlink_args->(\$args);

                print AC "<varlistentry id='&s2.idroot;core$cv.meth.${cname}.$_'>";
                print AC "<term><methodname>$args : $rt</methodname></term>";
                print AC "<listitem><para>$ds</para></listitem></varlistentry>";
            }
            print AC "</variablelist></refsect1>" if %func;
            print AC "</refentry>";
        }
        print AC "</section>";
    }

    close AC;

    return;
}
__END__

