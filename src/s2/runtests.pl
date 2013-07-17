#!/usr/bin/perl
#

use strict;
use Getopt::Long;
use S2;
use S2::Compiler;

my $opt_output;
my $opt_perl = 1;
my $opt_force;
my $opt_verbose;
my $opt_besource;
GetOptions("output" => \$opt_output,
           "perl" => \$opt_perl,
           "force" => \$opt_force,
           "verbose" => \$opt_verbose,
           "backend-source" => \$opt_besource,
           );

my $runwhat = shift;

my $TESTDIR = "tests";

my @files;
if ($runwhat) { 
    $runwhat =~ s!^.*\/!!;
    $runwhat .= ".s2" unless $runwhat =~ /s2$/;
    @files = ($runwhat);    
} else {
    opendir(D, $TESTDIR) || die "Can't open 'tests' directory.\n";
    while (my $f = readdir(D)) {
        if (-f "$TESTDIR/$f" && $f =~ /\.s2$/) {
            push @files, $f;
        }
    }
    closedir(D);
    @files = sort @files;
}

my ($to_stat, $to_run) = ("s2compile.jar", "./s2compile");
($to_stat, $to_run) = ("s2compile.pl", "./s2compile.pl") if $opt_perl;

my $jtime = (stat($to_stat))[9];
my @errors;

foreach my $f (@files)
{
    print STDERR "Testing: $f\n";
    my $pfile = "$TESTDIR/$f.pl";
    my $stime = (stat("$TESTDIR/$f"))[9];
    my $ptime = (stat($pfile))[9];

    my $build = $opt_force ? 1 : 0;
    if (-s $pfile == 0) { $build = 1; }
    unless ($ptime > $stime && $ptime > $jtime) {
        if ($stime > $ptime || $jtime > $ptime) {
            $build = 1;
        }
    }

    my $result;
    my $cerr = undef;

    if ($build) {
        my $error_file = "error-runtests.dat";

        open(IN,'<',"$TESTDIR/$f");
        my $source = join('',<IN>);
        close(IN);

        my $ck = new S2::Checker;
        my $cplr = S2::Compiler->new({ 'checker' => $ck });
        
        eval { 
            $cplr->compile_source({
                'type' => 'core',
                'source' => \$source,
                'output' => \$result,
                'layerid' => 1,
                'untrusted' => 0,
                'builtinPackage' => "S2::Builtin",
                'format' => 'perl',
            });
        };
        if ($@) {
            $cerr = $@;
            print "$cerr\n" if $opt_verbose;
        }

        
    }

    if ($opt_besource) {
        print $result;
        print "\n";
    }

    my $output = "";
    my $error;
    if ($result =~ /^\#\!/) {
        S2::set_output(sub { $output .= $_[0]; });
        S2::set_run_timeout(0);
        S2::unregister_layer(1);
          eval $result;
          $error = $@ if $@;
          my $ctx = S2::make_context([ 1 ]);
          eval {
              S2::run_code($ctx, "main()");
          };
          $error = $@ if $@;
      } else {
          $error = $cerr;
      }
    
    if ($opt_output) {
        print $output;
    }

    my $ofile = "$TESTDIR/$f.out";
    if (-e $ofile) {
        open (O, $ofile);
        my $goodout = join('',<O>);
        close O;
        if (trim($output) ne trim($goodout)) {
            push @errors, [ $f, "Output differs." ];
        }
    } elsif ($output) {
        push @errors, [ $f, "Output, and no expected output file." ];
    }

    my $efile = "$TESTDIR/$f.err";
    my $gooderror;
    if (-e $efile) {
        open (E, $efile);
        $gooderror = join('',<E>);
        close E;
        $gooderror = trim($gooderror);
        if ($error !~ /\Q$gooderror\E/) {
            push @errors, [ $f, "Wrong error encountered" ];
            print "$f: $error\n" if $opt_verbose;
        }
    } elsif ($error) {
        push @errors, [ $f, "Error occurred, but not anticipated." ];
        print "$f: $error\n" if $opt_verbose;
    }

    my $lfile = "$TESTDIR/$f.layerinfo";
    if (-e $lfile) {
        my $layerinfo = eval { do $lfile };
        die "Couldn't execute $lfile: $@" if $@;
        die "$lfile didn't return a hashref" unless ref $layerinfo eq 'HASH';

        my %info = S2::get_layer_info(1);

        while (my ($key, $val) = each %$layerinfo) {
            push @errors, [ $f, "Layerinfo '$key' contained '$info{$key}' when it should have contained '$val'." ]
                unless ($val eq $info{$key});
        }
    }
}

unless (@errors) {
    print STDERR "\nAll tests passed.\n\n";
    exit 0;
}

print STDERR "\nERRORS:\n======\n";
foreach my $e (@errors)
{
    printf STDERR "%-30s %s\n", $e->[0], $e->[1];
}
print STDERR "\n";
exit 1;

sub trim
{
    my $a = shift;
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

package S2::Builtin;

sub Color__update_hsl
{
    my ($this, $force) = @_;
    return if $this->{'_hslset'}++;
    ($this->{'_h'}, $this->{'_s'}, $this->{'_l'}) =
        LJ::Color::rgb_to_hsl($this->{'r'}, $this->{'g'}, $this->{'b'});
    $this->{$_} = int($this->{$_} * 255 + 0.5) foreach qw(_h _s _l);
}

sub Color__update_rgb
{
    my ($this) = @_;

    ($this->{'r'}, $this->{'g'}, $this->{'b'}) = 
        LJ::Color::hsl_to_rgb( map { $this->{$_} / 255 } qw(_h _s _l) );
    Color__make_string($this);
}

sub Color__make_string
{
    my ($this) = @_;
    $this->{'as_string'} = sprintf("\#%02x%02x%02x",
                                  $this->{'r'},
                                  $this->{'g'},
                                  $this->{'b'});
}

# public functions
sub Color__Color
{
    my ($s) = @_;
    $s =~ s/^\#//;
    return if $s =~ /[^a-fA-F0-9]/ || length($s) != 6;

    my $this = { '_type' => 'Color' };
    $this->{'r'} = hex(substr($s, 0, 2));
    $this->{'g'} = hex(substr($s, 2, 2));
    $this->{'b'} = hex(substr($s, 4, 2));
    $this->{$_} = $this->{$_} % 256 foreach qw(r g b);

    Color__make_string($this);
    return $this;
}

sub Color__clone
{
    my ($ctx, $this) = @_;
    return { %$this };
}

sub Color__set_hsl
{
    my ($this, $h, $s, $l) = @_;
    $this->{'_h'} = $h % 256;
    $this->{'_s'} = $s % 256;
    $this->{'_l'} = $l % 256;
    $this->{'_hslset'} = 1;
    Color__update_rgb($this);
}

sub Color__red {
    my ($ctx, $this, $r) = @_;
    if ($r) { 
        $this->{'r'} = $r % 256;
        delete $this->{'_hslset'};
        Color__make_string($this); 
    }
    $this->{'r'};
}

sub Color__green {
    my ($ctx, $this, $g) = @_;
    if ($g) {
        $this->{'g'} = $g % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'g'};
}

sub Color__blue {
    my ($ctx, $this, $b) = @_;
    if ($b) {
        $this->{'b'} = $b % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'b'};
}

sub Color__hue {
    my ($ctx, $this, $h) = @_;

    if ($h) {
        $this->{'_h'} = $h % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }
    $this->{'_h'};
}

sub Color__saturation {
    my ($ctx, $this, $s) = @_;
    if ($s) { 
        $this->{'_s'} = $s % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }
    $this->{'_s'};
}

sub Color__lightness {
    my ($ctx, $this, $l) = @_;

    if ($l) {
        $this->{'_l'} = $l % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }

    $this->{'_l'};
}

sub Color__inverse {
    my ($ctx, $this) = @_;
    my $new = {
        '_type' => 'Color',
        'r' => 255 - $this->{'r'},
        'g' => 255 - $this->{'g'},
        'b' => 255 - $this->{'b'},
    };
    Color__make_string($new);
    return $new;
}

sub Color__average {
    my ($ctx, $this, $other) = @_;
    my $new = {
        '_type' => 'Color',
        'r' => int(($this->{'r'} + $other->{'r'}) / 2 + .5),
        'g' => int(($this->{'g'} + $other->{'g'}) / 2 + .5),
        'b' => int(($this->{'b'} + $other->{'b'}) / 2 + .5),
    };
    Color__make_string($new);
    return $new;
}

sub Color__lighter {
    my ($ctx, $this, $amt) = @_;
    $amt = defined $amt ? $amt : 30;

    Color__update_hsl($this);

    my $new = {
        '_type' => 'Color',
        '_hslset' => 1,
        '_h' => $this->{'_h'},
        '_s' => $this->{'_s'},
        '_l' => ($this->{'_l'} + $amt > 255 ? 255 : $this->{'_l'} + $amt),
    };

    Color__update_rgb($new);
    return $new;
}

sub Color__darker {
    my ($ctx, $this, $amt) = @_;
    $amt = defined $amt ? $amt : 30;

    Color__update_hsl($this);

    my $new = {
        '_type' => 'Color',
        '_hslset' => 1,
        '_h' => $this->{'_h'},
        '_s' => $this->{'_s'},
        '_l' => ($this->{'_l'} - $amt < 0 ? 0 : $this->{'_l'} - $amt),
    };

    Color__update_rgb($new);
    return $new;
}

sub string__substr
{
    my ($ctx, $this, $start, $length) = @_;
    use utf8;
    return substr($this, $start, $length);
}

sub string__length
{
    use utf8;
    my ($ctx, $this) = @_;
    return length($this);
}

sub string__lower
{
    use utf8;
    my ($ctx, $this) = @_;
    return lc($this);
}

sub string__upper
{
    use utf8;
    my ($ctx, $this) = @_;
    return uc($this);
}

sub string__upperfirst
{
    use utf8;
    my ($ctx, $this) = @_;
    return ucfirst($this);
}

sub string__starts_with
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /^\Q$str\E/;
}

sub string__ends_with
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /\Q$str\E$/;
}

sub string__contains
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /\Q$str\E/;
}

sub string__repeat
{
    use utf8;
    my ($ctx, $this, $num) = @_;
    $num += 0;
    my $size = length($this) * $num;
    return "[too large]" if $size > 5000;
    return $this x $num;
}

sub BracketWrapper__as_string
{
    my ($ctx, $this) = @_;
    return undef unless S2::check_defined($this);
    return "[$this->{'text'}]";
}

sub BracketWrapper2__toString
{
    my ($ctx, $this) = @_;
    return undef unless S2::check_defined($this);
    return "[$this->{'text'}]";
}

1;
