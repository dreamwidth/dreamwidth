#!/usr/bin/perl
#

use strict;
package LJ::Img;
use vars qw(%img);

$img{'ins_obj'} = {
    'src' => '/ins-object.gif',
    'width' => 129,
    'height' => 52,
    'alt' => 'img.ins_obj',
};

$img{'btn_up'} = {
    'src' => '/btn_up.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_up',
};

$img{'btn_down'} = {
    'src' => '/btn_dn.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_down',
};

$img{'btn_del'} = {
    'src' => '/btn_del.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_del',
};

$img{'btn_freeze'} = {
    'src' => '/btn_freeze.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_freeze',
};

$img{'btn_unfreeze'} = {
    'src' => '/btn_unfreeze.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_unfreeze',
};

$img{'btn_scr'} = {
    'src' => '/btn_scr.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_scr',
};

$img{'btn_unscr'} = {
    'src' => '/btn_unscr.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.btn_unscr',
};

$img{'prev_entry'} = {
    'src' => '/btn_prev.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.prev_entry',
};

$img{'next_entry'} = {
    'src' => '/btn_next.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.next_entry',
};

$img{'memadd'} = {
    'src' => '/memadd.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.memadd',
};

$img{'editentry'} = {
    'src' => '/btn_edit.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.editentry',
};

$img{'edittags'} = {
    'src' => '/btn_edittags.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.edittags',
};

$img{'tellfriend'} = {
    'src' => '/btn_tellfriend.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.tellfriend',
};

$img{'placeholder'} = {
    'src' => '/imageplaceholder2.png',
    'width' => 35,
    'height' => 35,
    'alt' => 'img.placeholder',
};

$img{'xml'} = {
    'src' => '/xml.gif',
    'width' => 36,
    'height' => 14,
    'alt' => 'img.xml',
};

$img{'track'} = {
    'src' => '/btn_track.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.track',
};

$img{'track_active'} = {
    'src' => '/btn_tracking.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.track_active',
};

$img{'track_thread_active'} = {
    'src' => '/btn_tracking_thread.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.track_thread_active',
};

$img{'editcomment'} = {
    'src' => '/btn_edit.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'img.editcomment',
};

# load the site-local version, if it's around.
if (-e "$LJ::HOME/cgi-bin/imageconf-local.pl") {
    require "$LJ::HOME/cgi-bin/imageconf-local.pl";
}

1;

