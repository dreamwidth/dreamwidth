# t/cleaner-eat-differential.t
#
# The cleaner discards the contents of some elements (object, applet, iframe, ...)
# up to the first matching close tag. Unclosed ones used to discard everything to
# the end of the text; now the opening tag alone is dropped and the rest renders.
# That is the ONLY intended change: wherever a close tag follows, the output must be
# byte-identical to what the cleaner produced before (captured from main at
# 3ed7cbfae and pinned below, for events, comments, anonymous comments, subjects and
# embed content). The "same" corpus asserts that; the "changed" list pins the new
# behavior for inputs with no close tag at all.
#
# Authors:
#      Mark Smith <mark@qq.is>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use JSON;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;

my %clean = (
    event => sub {
        my $t = shift;
        LJ::CleanHTML::clean_event( \$t, { editor => 'html_raw0' } );
        $t;
    },
    anon_comment => sub {
        my $t = shift;
        LJ::CleanHTML::clean_comment( \$t, { anon_comment => 1 } );
        $t;
    },
    comment => sub {
        my $t = shift;
        LJ::CleanHTML::clean_comment( \$t, {} );
        $t;
    },
    subject => sub {
        my $t = shift;
        LJ::CleanHTML::clean_subject( \$t );
        $t;
    },
    embed => sub {
        my $t = shift;
        local $LJ::DISABLED{'embedmodule-cleancontent'} = 0;
        LJ::CleanHTML::clean_embed( \$t, {} );
        $t;
    },
);

my $corpus = decode_json(
    do { local $/; <DATA> }
);

plan tests => scalar( @{ $corpus->{same} } ) * keys(%clean) + @{ $corpus->{changed} };

foreach my $case ( @{ $corpus->{same} } ) {
    foreach my $mode ( sort keys %clean ) {
        is(
            $clean{$mode}->( $case->{in} ),
            $case->{main}->{$mode},
            "$mode, as before: $case->{in}"
        );
    }
}

foreach my $case ( @{ $corpus->{changed} } ) {
    my %got = map { $_ => $clean{$_}->( $case->{in} ) } keys %{ $case->{branch} };
    is_deeply( \%got, $case->{branch}, "no close tag, so the rest renders: $case->{in}" );
}

__DATA__
{
 "changed": [
  {
   "branch": {
    "anon_comment": "before  visible tail",
    "comment": "before  visible tail",
    "event": "before  visible tail",
    "subject": "before  visible tail"
   },
   "in": "before <iframe src=\"https://example.invalid/\" /> visible tail"
  },
  {
   "branch": {
    "anon_comment": "before  visible tail",
    "comment": "before  visible tail",
    "event": "before  visible tail",
    "subject": "before  visible tail"
   },
   "in": "before <iframe src=\"https://example.invalid/\"/> visible tail"
  },
  {
   "branch": {
    "anon_comment": "a  b",
    "comment": "a  b"
   },
   "in": "a <object/> b"
  },
  {
   "branch": {
    "anon_comment": "a never closed &lt;b&gt;bold&lt;/b&gt; tail",
    "comment": "a never closed &lt;b&gt;bold&lt;/b&gt; tail",
    "embed": "a never closed &lt;b&gt;bold&lt;/b&gt; tail",
    "event": "a never closed &lt;b&gt;bold&lt;/b&gt; tail",
    "subject": "a never closed &lt;b&gt;bold&lt;/b&gt; tail"
   },
   "in": "a <iframe>never closed <b>bold</b> tail"
  },
  {
   "branch": {
    "anon_comment": "a never closed <b>bold</b> tail",
    "comment": "a never closed <b>bold</b> tail"
   },
   "in": "a <object>never closed <b>bold</b> tail"
  },
  {
   "branch": {
    "event": "a  b  c  d  e",
    "subject": "a  b  c  d  e"
   },
   "in": "a <layer>x</layer> b <xml>y</xml> c <param name=x> d <base href=x> e"
  },
  {
   "branch": {
    "anon_comment": "a never closed",
    "comment": "a never closed",
    "event": "a never closed",
    "subject": "a never closed"
   },
   "in": "a <applet>never closed"
  },
  {
   "branch": {
    "event": "tail",
    "subject": "tail"
   },
   "in": "<object><param name=x><embed src=y></embed></object>tail"
  },
  {
   "branch": {
    "anon_comment": "a  tail",
    "comment": "a  tail",
    "event": "a  tail",
    "subject": "a  tail"
   },
   "in": "a <iframe src=\"http://www.youtube.com/embed/ABC123abc_-\" /> tail"
  },
  {
   "branch": {
    "anon_comment": "a  tail",
    "comment": "a  tail",
    "event": "a  tail",
    "subject": "a  tail"
   },
   "in": "a <iframe src=\"http://www.youtube.com/embed/ABC123abc_-\"/> tail"
  },
  {
   "branch": {
    "anon_comment": "a  tail",
    "comment": "a  tail",
    "embed": "a  tail",
    "event": "a  tail",
    "subject": "a  tail"
   },
   "in": "a <iframe src=\"http://example.invalid/x\"> tail"
  },
  {
   "branch": {
    "anon_comment": "a  b",
    "comment": "a  b"
   },
   "in": "a <object/> b"
  }
 ],
 "same": [
  {
   "in": "<table><tr><td>outer<table><tr><td>inner</td></tr></table>visible tail</td></tr></table>after",
   "main": {
    "anon_comment": "visible tailafter",
    "comment": "<table><tr><td>outer<table><tr><td>inner</td></tr></table>visible tail</td></tr></table>after",
    "embed": "<table><tr><td>outer<table><tr><td>inner</td></tr></table>visible tail</td></tr></table>after",
    "event": "<table><tr><td>outer<table><tr><td>inner</td></tr></table>visible tail</td></tr></table>after",
    "subject": "outerinnervisible tailafter"
   }
  },
  {
   "in": "before <iframe src=\"https://example.invalid/\"></iframe> visible tail",
   "main": {
    "anon_comment": "before  visible tail",
    "comment": "before  visible tail",
    "embed": "before  visible tail",
    "event": "before  visible tail",
    "subject": "before  visible tail"
   }
  },
  {
   "in": "before <iframe src=\"https://example.invalid/\">inside</iframe> tail <iframe>x</iframe> end",
   "main": {
    "anon_comment": "before  tail  end",
    "comment": "before  tail  end",
    "embed": "before  tail  end",
    "event": "before  tail  end",
    "subject": "before  tail  end"
   }
  },
  {
   "in": "a <object>x<object>y</object>z</object> b",
   "main": {
    "anon_comment": "a z b",
    "comment": "a z b",
    "embed": "a <object>x<object>y</object>z</object> b",
    "event": "a xyz b",
    "subject": "a xyz b"
   }
  },
  {
   "in": "a <object>x</object> b <object>y</object> c",
   "main": {
    "anon_comment": "a  b  c",
    "comment": "a  b  c",
    "embed": "a <object>x</object> b <object>y</object> c",
    "event": "a x b y c",
    "subject": "a x b y c"
   }
  },
  {
   "in": "a <object /> b <object>z</object> c",
   "main": {
    "anon_comment": "a  c",
    "comment": "a  c",
    "embed": "a <object> b <object>z</object> c</object>",
    "event": "a  b z c",
    "subject": "a  b z c"
   }
  },
  {
   "in": "a <applet>x<applet>y</applet>z</applet> b",
   "main": {
    "anon_comment": "a z b",
    "comment": "a z b",
    "embed": "a <applet>x<applet>y</applet>z</applet> b",
    "event": "a z b",
    "subject": "a z b"
   }
  },
  {
   "in": "a <head>x</head> b <title>t</title> c <style>s{}</style> d <script>alert(1)</script> e",
   "main": {
    "anon_comment": "a  b  c  d  e",
    "comment": "a  b  c  d  e",
    "embed": "a <head>x</head> b <title>t</title> c \n<style>\n/* cleaned */\ns{}</style>\n d  e",
    "event": "a  b  c  d  e",
    "subject": "a  b  c  d  e"
   }
  },
  {
   "in": "a <script>alert(1) unclosed tail",
   "main": {
    "anon_comment": "a alert(1) unclosed tail",
    "comment": "a alert(1) unclosed tail",
    "embed": "a alert(1) unclosed tail",
    "event": "a alert(1) unclosed tail",
    "subject": "a alert(1) unclosed tail"
   }
  },
  {
   "in": "a <style>p{} unclosed tail",
   "main": {
    "anon_comment": "a p{} unclosed tail",
    "comment": "a p{} unclosed tail",
    "embed": "a \n<style>\n/* cleaned */\n</style>\np{} unclosed tail",
    "event": "a p{} unclosed tail",
    "subject": "a p{} unclosed tail"
   }
  },
  {
   "in": "a <SCRIPT>x</SCRIPT> b <ObJeCt>y</oBjEcT> c",
   "main": {
    "anon_comment": "a  b  c",
    "comment": "a  b  c",
    "embed": "a  b <object>y</object> c",
    "event": "a  b y c",
    "subject": "a  b y c"
   }
  },
  {
   "in": "a <!-- <object> --> b </object> c",
   "main": {
    "anon_comment": "a  b  c",
    "comment": "a  b  c",
    "embed": "a  b  c",
    "event": "a  b  c",
    "subject": "a  b  c"
   }
  },
  {
   "in": "a <object><!-- </object> --> hidden? </object> c",
   "main": {
    "anon_comment": "a  c",
    "comment": "a  c",
    "embed": "a <object> hidden? </object> c",
    "event": "a  hidden?  c",
    "subject": "a  hidden?  c"
   }
  },
  {
   "in": "x<table><tr><td>a</td></tr></table>y<table><tr><td>b</td></tr></table>z",
   "main": {
    "anon_comment": "xyz",
    "comment": "x<table><tr><td>a</td></tr></table>y<table><tr><td>b</td></tr></table>z",
    "embed": "x<table><tr><td>a</td></tr></table>y<table><tr><td>b</td></tr></table>z",
    "event": "x<table><tr><td>a</td></tr></table>y<table><tr><td>b</td></tr></table>z",
    "subject": "xaybz"
   }
  },
  {
   "in": "a <iframe src=\"http://example.invalid/x\" /> tail </iframe> more",
   "main": {
    "anon_comment": "a  more",
    "comment": "a  more",
    "embed": "a  tail  more",
    "event": "a  more",
    "subject": "a  more"
   }
  },
  {
   "in": "a <iframe src=\"http://example.invalid/x\"/> tail </iframe> more",
   "main": {
    "anon_comment": "a  more",
    "comment": "a  more",
    "embed": "a  tail  more",
    "event": "a  more",
    "subject": "a  more"
   }
  },
  {
   "in": "a <iframe src=\"http://example.invalid/x\"><iframe src=\"http://example.invalid/y\"></iframe> mid </iframe> end",
   "main": {
    "anon_comment": "a  mid  end",
    "comment": "a  mid  end",
    "embed": "a  mid  end",
    "event": "a  mid  end",
    "subject": "a  mid  end"
   }
  },
  {
   "in": "a <script>never closed tail",
   "main": {
    "anon_comment": "a never closed tail",
    "comment": "a never closed tail",
    "embed": "a never closed tail",
    "event": "a never closed tail",
    "subject": "a never closed tail"
   }
  },
  {
   "in": "a <style>never closed tail",
   "main": {
    "anon_comment": "a never closed tail",
    "comment": "a never closed tail",
    "embed": "a \n<style>\n/* cleaned */\n</style>\nnever closed tail",
    "event": "a never closed tail",
    "subject": "a never closed tail"
   }
  },
  {
   "in": "a <script>x</script> b <style>y</style> c",
   "main": {
    "anon_comment": "a  b  c",
    "comment": "a  b  c",
    "embed": "a  b \n<style>\n/* cleaned */\ny</style>\n c",
    "event": "a  b  c",
    "subject": "a  b  c"
   }
  },
  {
   "in": "a <object/> b </object> c",
   "main": {
    "anon_comment": "a  c",
    "comment": "a  c",
    "embed": "a <object> b </object> c",
    "event": "a  b  c",
    "subject": "a  b  c"
   }
  },
  {
   "in": "<table><tr><td>x</td></tr></table>",
   "main": {
    "anon_comment": "",
    "comment": "<table><tr><td>x</td></tr></table>",
    "embed": "<table><tr><td>x</td></tr></table>",
    "event": "<table><tr><td>x</td></tr></table>",
    "subject": "x"
   }
  }
 ]
}
