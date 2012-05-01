#!/usr/bin/perl
#

package S2::Compiler;

use strict;
use S2::Tokenizer;
use S2::Checker;
use S2::Layer;
use S2::Util;
use S2::BackendPerl;
use S2::BackendHTML;
use S2::OutputScalar;

sub new # (fh) class method
{
    my ($class, $opts) = @_;
    $opts->{'checker'} ||= new S2::Checker;
    bless $opts, $class;
}

sub compile_source {
    my ($this, $opts) = @_;
    $S2::CUR_COMPILER = $this;
    my $ref = ref $opts->{'source'} ? $opts->{'source'} : \$opts->{'source'};
    my $toker = S2::Tokenizer->new($ref);
    my $s2l = S2::Layer->new($toker, $opts->{'type'});
    my $o = new S2::OutputScalar($opts->{'output'});
    my $be;
    $opts->{'format'} ||= "perl";
    if ($opts->{'format'} eq "html") {
        $be = new S2::BackendHTML($s2l);
    } elsif ($opts->{'format'} eq "perl") {
        $this->{'checker'}->checkLayer($s2l);
        $be = new S2::BackendPerl($s2l, $opts->{'layerid'}, $opts->{'untrusted'});
        if ($opts->{'builtinPackage'}) {
            $be->setBuiltinPackage($opts->{'builtinPackage'});
        }
    } elsif ($opts->{'format'} eq "perloo") {
        $this->{'checker'}->checkLayer($s2l);
        $be = new S2::BackendPerl($s2l, undef, $opts->{'untrusted'}, 1, $opts->{'sourcename'});
        if ($opts->{'builtinPackage'}) {
            $be->setBuiltinPackage($opts->{'builtinPackage'});
        }
    } elsif ($opts->{'format'} eq "lua") {
        require S2::BackendLua;
        $this->{'checker'}->checkLayer($s2l);
        $be = new S2::BackendLua($s2l, $opts->{'untrusted'});
        if ($opts->{'builtinPackage'}) {
            $be->setBuiltinPackage($opts->{'builtinPackage'});
        }
    } elsif ($opts->{'format'} eq "javascript") {
        require S2::BackendJS;
        $this->{'checker'}->checkLayer($s2l);
        $be = new S2::BackendJS($s2l, $opts->{'layerid'}, $opts->{'untrusted'}, {
            'propmeta' => 1, # FIXME: Don't hardcode this
        });
        if ($opts->{'builtinPackage'}) {
            $be->setBuiltinPackage($opts->{'builtinPackage'});
        }
    } else {
        S2::error("Unknown output type in S2::Compiler");
    }
    $be->output($o);
    undef $S2::CUR_COMPILER;
    return 1;
}


1;
