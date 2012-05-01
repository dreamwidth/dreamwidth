#!/usr/bin/perl
#

package S2::BackendHTML;

use strict;

use vars qw($CommentColor $IdentColor $KeywordColor
            $StringColor $PunctColor $BracketColor $TypeColor
            $VarColor $IntegerColor);

$CommentColor = "#008000";
$IdentColor = "#000000";
$KeywordColor = "#0000FF";
$StringColor = "#008080";
$PunctColor = "#000000";
$BracketColor = "#800080";
$TypeColor = "#000080";
$VarColor = "#000000";
$IntegerColor = "#000000";

sub new {
    my ($class, $l) = @_;
    my $this = {
        'layer' => $l,
    };
    bless $this, $class;
}

sub output {
    my ($this, $o) = @_;

    $o->write("<html><head>\n");
    $o->write("<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">\n");
    $o->write("<style type=\"text/css\">\n");
    $o->write("body { background: #ffffff none; color: #000000; }\n");
    $o->write(".c { background: #ffffff none; color: " . $CommentColor . "; }\n");
    $o->write(".i { background: #ffffff none; color: " . $IdentColor . "; }\n");
    $o->write(".k { background: #ffffff none; color: " . $KeywordColor . "; }\n");
    $o->write(".s { background: #ffffff none; color: " . $StringColor . "; }\n");
    $o->write(".p { background: #ffffff none; color: " . $PunctColor . "; }\n");
    $o->write(".b { background: #ffffff none; color: " . $BracketColor . "; }\n");
    $o->write(".t { background: #ffffff none; color: " . $TypeColor . "; }\n");
    $o->write(".v { background: #ffffff none; color: " . $VarColor . "; }\n");
    $o->write(".n { background: #ffffff none; color: " . $IntegerColor . "; }\n");
    $o->write("</style>\n");
    my $name = $this->{'layer'}->getLayerInfo('name');
    $o->write("<title>" . ( $name ? "$name - " : "" ) . "Layer Source</title>");
    $o->write("</head>\n<body>\n<pre>");
    my $nodes = $this->{'layer'}->getNodes();
    foreach my $n (@$nodes) {
        my $dbg = "Doing node: " . ref($n);
        if (ref $n eq "S2::NodeFunction") {
            $dbg .= " (" . $n->getName() . ")";
            if ($n->getName() eq "print_body") {
                #use Data::Dumper;
                #$dbg .= Dumper($n->{'tokenlist'});
            }
        }
        #Apache->request->log_error($dbg);
        #print $dbg;

        $n->asHTML($o);
    }
    $o->write("</pre></body></html>"); $o->newline();
}

sub quoteHTML {
    shift if ref $_[0];
    my $s = shift;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s;
}


1;
