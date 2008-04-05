#!/usr/bin/perl

package LJ::Captcha::Generate;
use strict;
use GD;
use File::Temp;
use Cwd ();
use Digest::MD5 ();
use LJ::Blob qw{};

use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";

# stolen from Authen::Captcha.  code was small enough that duplicating
# was easier than requiring that module, and removing all its automatic
# database tracking stuff and replacing it with ours.  maybe we'll move
# to using it in the future, but for now this works.  (both their code
# and ours is GPL)
sub generate_visual
{
    my ($class, $code) = @_;

    my $im_width = 25;
    my $im_height = 35;
    my $length = length($code);

    my $img = $LJ::CAPTCHA_IMAGE_RAW;

    # create a new image and color
    my $im = new GD::Image(($im_width * $length),$im_height);
    my $black = $im->colorAllocate(0,0,0);

    # copy the character images into the code graphic
    for(my $i=0; $i < $length; $i++)
    {
        my $letter = substr($code,$i,1);
        my $letter_png = "$img/$letter.png";
        die "Can't find file '$letter_png'" unless -e $letter_png;
        my $source = new GD::Image($letter_png);
        $im->copy($source,($i*($im_width),0,0,0,$im_width,$im_height));
        my $a = int(rand (int(($im_width)/14)))+0;
        my $b = int(rand (int(($im_height)/12)))+0;
        my $c = int(rand (int(($im_width)/3)))-(int(($im_width)/5));
        my $d = int(rand (int(($im_height)/3)))-(int(($im_height)/5));
        $im->copyResized($source,($i*($im_width))+$a,$b,0,0,($im_width)+$c,($im_height)+$d,$im_width,$im_height);
    }

    # distort the code graphic
    for(my $i=0; $i<($length*$im_width*$im_height/14+150); $i++)
    {
        my $a = int(rand($length*$im_width));
        my $b = int(rand($im_height));
        my $c = int(rand($length*$im_width));
        my $d = int(rand($im_height));
        my $index = $im->getPixel($a,$b);
        if ($i < (($length*($im_width)*($im_height)/14+200)/100))
        {
            $im->line($a,$b,$c,$d,$index);
        } elsif ($i < (($length*($im_width)*($im_height)/14+200)/2)) {
            $im->setPixel($c,$d,$index);
        } else {
            $im->setPixel($c,$d,$black);
        }
    }

    # generate a background
    my $a = int(rand 5)+1;
    my $background_img = "$img/background$a.png";
    my $source = new GD::Image($background_img);
    my ($background_width, $background_height) = $source->getBounds();
    my $b = int(rand (int($background_width/13)))+0;
    my $c = int(rand (int($background_height/7)))+0;
    my $d = int(rand (int($background_width/13)))+0;
    my $e = int(rand (int($background_height/7)))+0;
    my $source2 = new GD::Image(($length*($im_width)),$im_height);
    $source2->copyResized($source,0,0,$b,$c,$length*$im_width,$im_height,$background_width-$b-$d,$background_height-$c-$e);

    # merge the background onto the image
    $im->copyMerge($source2,0,0,0,0,($length*($im_width)),$im_height,40);

    # add a border
    $im->rectangle(0, 0, $length*$im_width-1, $im_height-1, $black);

    return $im->png;

}

# ($dir) -> ("$dir/speech.wav", $code)
#  Callers must:
#    -- create unique temporary directory, shared by no other process
#       calling this function
#    -- after return, do something with speech.wav (save on disk server/
#       db/etc), remove speech.wav, then rmdir $dir
#  Requires festival and sox.
sub generate_audio
{
    my ($class, $dir) = @_;
    my $old_dir =  Cwd::getcwd();
    chdir($dir) or return 0;

    my $bin_festival = $LJ::BIN_FESTIVAL || "festival";
    my $bin_sox = $LJ::BIN_SOX || "sox";

    # make up 7 random numbers, without any numbers in a row
    my @numbers;
    my $lastnum;
    for (1..7) {
        my $num;
        do {
            $num = int(rand(9)+1);
        } while ($num == $lastnum);
        $lastnum = $num;
        push @numbers, $num;
    }
    my $numbers_speak = join("... ", @numbers);
    my $numbers_clean = join('', @numbers);

    # generate the clean speech
    open FEST, '|-', $bin_festival or die "Couldn't invoke festival";
    print FEST "(Parameter.set 'Audio_Method 'Audio_Command)\n";
    print FEST "(Parameter.set 'Audio_Required_Format 'wav)\n";
    print FEST "(Parameter.set 'Audio_Required_Rate 44100)\n";
    print FEST "(Parameter.set 'Audio_Command \"mv \$FILE speech.wav\")\n";
    print FEST "(SayText \"$numbers_speak\")\n";
    close FEST or die "Error closing festival";

    my $sox = sub {
        my ($effect, $filename, $inopts, $outopts) = @_;
        $effect = [] unless $effect;
        $filename = "speech.wav" unless $filename;
        $inopts = [] unless $inopts;
        $outopts = [] unless $outopts;
        command($bin_sox, @$inopts, $filename, @$outopts, "tmp.wav", @$effect);
        rename('tmp.wav', $filename)
            or die;
    };

    # distort the speech
    $sox->([qw(reverb 0.5 200 100 60 echo 1 0.7 100 0.03 400 0.15)]);
    command($bin_sox, qw(speech.wav noise.wav synth brownnoise 0 vibro 3 0.8 vol 0.1));
    $sox->([qw(fade 0.5)], 'noise.wav');
    $sox->([qw(reverse)], 'noise.wav');
    $sox->([qw(fade 0.5)], 'noise.wav');

    command("${bin_sox}mix", qw(-v 4 speech.wav noise.wav -r 16000 tmp.wav));
    rename('tmp.wav', 'speech.wav') or die;
    unlink('oldspeech.wav', 'noise.wav');

    chdir($old_dir) or return 0;
    return ("$dir/speech.wav", $numbers_clean);
}

sub command {
    system(@_) >> 8 == 0 or die "audio command ($_[0]) failed, died";
}

1;
