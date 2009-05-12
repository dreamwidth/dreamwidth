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
    'src' => '/silk/comments/delete.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.btn_del',
};

$img{'btn_freeze'} = {
    'src' => '/silk/comments/freeze.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.btn_freeze',
};

$img{'btn_unfreeze'} = {
    'src' => '/silk/comments/unfreeze.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.btn_unfreeze',
};

$img{'btn_scr'} = {
    'src' => '/silk/comments/screen.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.btn_scr',
};

$img{'btn_unscr'} = {
    'src' => '/silk/comments/unscreen.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.btn_unscr',
};

$img{'prev_entry'} = {
    'src' => '/silk/entry/previous.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.prev_entry',
};

$img{'next_entry'} = {
    'src' => '/silk/entry/next.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.next_entry',
};

$img{'memadd'} = {
    'src' => '/silk/entry/memories_add.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.memadd',
};

$img{'editentry'} = {
    'src' => '/silk/entry/edit.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.editentry',
};

$img{'edittags'} = {
    'src' => '/silk/entry/tag_edit.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.edittags',
};

$img{'tellfriend'} = {
    'src' => '/silk/entry/tellafriend.png',
    'width' => 16,
    'height' => 16,
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
    'src' => '/silk/entry/track.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.track',
};

$img{'track_active'} = {
    'src' => '/silk/entry/untrack.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.track_active',
};

$img{'track_thread_active'} = {
    'src' => '/silk/entry/untrack.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.track_thread_active',
};

$img{'editcomment'} = {
    'src' => '/silk/comments/edit.png',
    'width' => 16,
    'height' => 16,
    'alt' => 'img.editcomment',
};

# load the site-local version, if it's around.
if (-e "$LJ::HOME/cgi-bin/imageconf-local.pl") {
    require "$LJ::HOME/cgi-bin/imageconf-local.pl";
}

1;

