#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use Getopt::Long;
use Storable;
use IO::File;
use File::Path;

# Make sure we can get at the main S2 compiler libs
use lib "$Bin/../..";

use S2::Tokenizer;
use S2::Checker;
use S2::Layer;
use S2::OutputConsole;
use S2::OutputScalar;
use S2::BackendPerl;
use S2::Compiler;

# Load in our stuff to patch the compiler with asPHP functions
require "$Bin/compiler/codegen.pl";

my $layertype;
my $corefile;
my $layoutfile;
my $outdir;
my $ckoutfile;
my $ckinfile;

exit usage() unless GetOptions(
    "layertype=s" => \$layertype,
    "core=s" => \$corefile,
    "layout=s" => \$layoutfile,
    "outdir=s" => \$outdir,
    "dumpchecker=s" => \$ckoutfile,
    "usechecker=s" => \$ckinfile,
);

exit usage() unless @ARGV == 1;

my $infile = shift;

die "--layertype argument is required" unless $layertype;
die "--outdir argument is required" unless $outdir;

my $ck;

if ($ckinfile) {
    $ck = Storable::retrieve($ckinfile);
}
else {
    $ck = new S2::Checker();
    if ($layertype ne 'core') {
        die "--core argument is required when compiling non-core layers" unless $corefile;
        load_layer($corefile, 'core', $ck);
        
        if ($layertype ne 'layout') {
            die "--layout argument is required when compiling $layertype layers" unless $layoutfile;
            load_layer($layoutfile, 'layout', $ck);
        }
    }
}

my $layer = load_layer($infile, $layertype, $ck);


# LAME: Need to optimize this a bit so that it
# doesn't do so many passes over the entire array

my $nodes = $layer->getNodes();

my @classes = grep { $_->isa('S2::NodeClass') } @$nodes;
my @functions = grep { $_->isa('S2::NodeFunction') } @$nodes;
my @propsets = grep { $_->isa('S2::NodeSet') } @$nodes;
my @propdecls = grep { $_->isa('S2::NodeProperty') } @$nodes;
my @propgroups = grep { $_->isa('S2::NodeGroup') } @$nodes;

#my $o = new S2::OutputScalar(\$output);
my $o = new S2::OutputConsole();
my $oi = new S2::Indenter($o, 4);

my $be = new S2::BackendPHP($ck);

File::Path::mkpath($outdir);
File::Path::mkpath($outdir."/func");
chdir($outdir) or die "Failed to switch to $outdir";

open(FUNCTABLE, '>', 'functable.php');
print FUNCTABLE "<? return array(\n";

my $funcnum = 0;
foreach my $func (@functions) {
    my $names = $ck->getFuncIDs($func);

    my $funcid = sprintf("%08x", $funcnum++);
    
    foreach my $name (@$names) {
        print FUNCTABLE "    '$name' => '$funcid',\n";
    }
    
    open(FUNC, '>', "func/${funcid}.php");
    select(FUNC);
    
    $oi->writeln("<?");
    $oi->tabIn();
    $func->asPHP($be, $oi);
    $oi->tabOut();
    $oi->writeln("?>");
    
    select(STDOUT);
    close(FUNC);
}

print FUNCTABLE "); ?>\n";

close(FUNCTABLE);

#print $output;

########################################################################################

sub file_get_contents {
    my $filename = shift;
    my $fh;

    if ($filename eq "-") {
        $fh = new IO::Handle;
        return $fh if $fh->fdopen(fileno(STDIN),"r");
        die "Couldn't open STDIN?\n";
    }
    $fh = new IO::File $filename, "r";
    die "Can't open file: $filename\n" unless $fh;

    my $body = join('', <$fh>);
    return \$body;
}

sub load_layer {
    my ($filename, $type, $ck) = @_;
    unless ($filename) {
        die "Undefined filename for '$type' layer.\n";
    }
    
    my $toker = S2::Tokenizer->new(file_get_contents($filename));
    my $layer = S2::Layer->new($toker, $type);
    $ck->checkLayer($layer);
    return $layer;
}

sub usage {
    print STDERR <<'USAGE';
Usage: s2tophp [opts]* <file>

Options:
   --layertype <type>    One of: core, i18nc, layout, theme, i18n, user
   --core <filename>     Core S2 file, if layertype is not core
   --layout <filename>   Layout S2 file, if layertype is not core or layout
   --outdir <path>       Directory for output files
   --dumpchecker <filename>
                         If compile is successful, will write a serialized
                        checker object to the given filename.
   --usechecker <filename>
                         Use a serialized checker (as written by
                        --dumpchecker) rather than compiling previous layers.
                        Use this instead of --core and --layout.

USAGE

   return 1;
}

package S2::BackendPHP;

use strict;
use Carp;

sub new {
    return bless {}, $_[0];
}

sub quoteString {
    shift if ref $_[0];
    my $s = shift;
    return "\"" . quoteStringInner($s) . "\"";
}

sub quoteStringInner {
    shift if ref $_[0];
    my $s = shift;
    $s =~ s/([\\\$\"\@])/\\$1/g;
    $s =~ s/\n/\\n/g;
    return $s;
}

# PHP has function-level scope while S2 has block-level
# scope. Therefore we must decorate all local variables with
# a scope identifier to ensure there are no collisions between
# blocks.
sub decorateLocal {
    my ($this, $varname, $scope) = @_;
    
    return $varname unless $scope->localVarMustBeDecorated($varname);
    
    # HACK: Use part of Perl's stringification of the
    # owning block to decorate the variable name. Should
    # do something better later.
    my $decorate;
    my $block = $scope."";
    if ($block =~ /HASH\(0x(\w+)\)/) {
        $decorate = $1;
    }
    else {
        croak "Unable to decorate $varname in $block";
    }

    return "__".$decorate."_".$varname;
}
