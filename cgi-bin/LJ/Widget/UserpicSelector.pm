# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Widget::UserpicSelector;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::Talk;

sub need_res {

    # force to not use beta, because this is not used in journal spaces
    return LJ::Talk::init_iconbrowser_js( 0, 'stc/entry.css' );
}

sub handle_post {
    return;
}

sub render_body {
    my ( $class, %opts ) = @_;
    my ( $u, $head, $pic, $picform ) = @{ $opts{picargs} };
    my $opts = \%opts;    # to avoid rewriting below

    return "" unless LJ::isu($u);
    return "" unless LJ::is_enabled('userpicselect') || $u->can_use_userpic_select;

    my $res;
    $res = LJ::Protocol::do_request(
        "login",
        {
            ver          => $LJ::PROTOCOL_VER,
            username     => $u->user,
            getpickws    => 1,
            getpickwurls => 1,
        },
        undef,
        {
            noauth => 1,
            u      => $u,
        }
    ) unless $opts->{no_auth};

    my $has_icons = $res && ref $res->{pickws} eq 'ARRAY' && scalar @{ $res->{pickws} } > 0;

    my $userpic_msg_default = LJ::Lang::ml('entryform.userpic.default');
    my $userpic_msg_upload  = LJ::Lang::ml('entryform.userpic.upload');
    my $defpic              = LJ::Lang::ml('entryform.opt.defpic');
    my $onload              = $opts->{onload};

    if ( !$opts->{altlogin} && $has_icons ) {

        # start with default picture info
        my $num = 0;
        my $userpics .= "    userpics[$num] = \"$res->{defaultpicurl}\";\n";
        my $altcode  .= "     alttext[$num] = \"$defpic\";\n";

        foreach ( @{ $res->{pickwurls} } ) {
            $num++;
            $userpics .= "    userpics[$num] = \"$_\";\n";
        }

        $num = 0;    # reset

        foreach ( @{ $res->{pickws} } ) {
            $num++;
            $altcode .= "     alttext[$num] = \"" . LJ::ejs($_) . "\";\n";
        }

        $$onload .= " userpic_preview();" if $onload;

        $$head .= qq {
            <script type="text/javascript" language="JavaScript"><!--
                if (document.getElementById) {
                    var userpics = new Array();
                    var alttext = new Array();
                    $userpics
                    $altcode
                    function userpic_preview() {
                        if (! document.getElementById) return false;
                        var userpic_select = document.getElementById('prop_picture_keyword');

                        if (\$('userpic') && \$('userpic').style.display == 'none') {
                            \$('userpic').style.display = 'block';
                        }
                        var userpic_msg;
                        if (userpics[0] == "") { userpic_msg = '$userpic_msg_default' }
                        if (userpics.length == 0) { userpic_msg = '$userpic_msg_upload' }

                        if (userpic_select && userpics[userpic_select.selectedIndex] != "") {
                            \$('userpic_preview').className = '';
                            var userpic_preview_image = \$('userpic_preview_image');
                            userpic_preview_image.style.display = 'block';
                            if (\$('userpic_msg')) {
                                \$('userpic_msg').style.display = 'none';
                            }
                            userpic_preview_image.src = userpics[userpic_select.selectedIndex];
                            userpic_preview_image.alt = alttext[userpic_select.selectedIndex];
                        } else {
                            userpic_preview.className += " userpic_preview_border";
                            userpic_preview.innerHTML = '<a href="$LJ::SITEROOT/manage/icons"><img src="" alt="selected userpic" id="userpic_preview_image" style="display: none;" /><span id="userpic_msg">' + userpic_msg + '</span></a>';
                        }
                    }
                }
            //--></script>
        };

        my $viewthumbnails_link = '';
        if ( $opts->{entry_js} ) {
            my $thumbnail_text = LJ::Lang::ml('/update.bml.link.view_thumbnails');
            $viewthumbnails_link = qq {
                var ml = new Object();
                ml.viewthumbnails_link = "$thumbnail_text";
            };
        }

        $$head .= qq {
            <script type="text/javascript" language="JavaScript">
            // <![CDATA[
                $viewthumbnails_link
                DOM.addEventListener(window, "load", function (evt) {
                // attach userpicselect code to userpicbrowse button
                    var ups_btn = \$("lj_userpicselect");
                    var ups_btn_img = \$("lj_userpicselect_img");
                if (ups_btn) {
                    DOM.addEventListener(ups_btn, "click", function (evt) {
                        var ups = new UserpicSelect();
                        ups.init();
                        ups.setPicSelectedCallback(function (picid, keywords) {
                            var kws_dropdown = \$("prop_picture_keyword");

                            if (kws_dropdown) {
                                var items = kws_dropdown.options;

                                // select the keyword in the dropdown
                                keywords.forEach(function (kw) {
                                    for (var i = 0; i < items.length; i++) {
                                        var item = items[i];
                                        if (item.value == kw) {
                                            kws_dropdown.selectedIndex = i;
                                            userpic_preview();
                                            return;
                                        }
                                    }
                                });
                            }
                        });
                        ups.show();
                    });
                }
                if (ups_btn_img) {
                    DOM.addEventListener(ups_btn_img, "click", function (evt) {
                        var ups = new UserpicSelect();
                        ups.init();
                        ups.setPicSelectedCallback(function (picid, keywords) {
                            var kws_dropdown = \$("prop_picture_keyword");

                            if (kws_dropdown) {
                                var items = kws_dropdown.options;

                                // select the keyword in the dropdown
                                keywords.forEach(function (kw) {
                                    for (var i = 0; i < items.length; i++) {
                                        var item = items[i];
                                        if (item.value == kw) {
                                            kws_dropdown.selectedIndex = i;
                                            userpic_preview();
                                            return;
                                        }
                                    }
                                });
                            }
                        });
                        ups.show();
                    });
                    DOM.addEventListener(ups_btn_img, "mouseover", function (evt) {
                        var msg = \$("lj_userpicselect_img_txt");
                        msg.style.display = 'block';
                    });
                    DOM.addEventListener(ups_btn_img, "mouseout", function (evt) {
                        var msg = \$("lj_userpicselect_img_txt");
                        msg.style.display = 'none';
                    });
                }
            });
            // ]]>
            </script>
        } if $u->can_use_userpic_select;

        $$pic .= "<div id='userpic' style='display: none;'><p id='userpic_preview'>";
        $$pic .= "<a href='javascript:void(0);' id='lj_userpicselect_img'>";
        $$pic .= "<img src='' alt='selected userpic' id='userpic_preview_image' />";
        $$pic .= "<span id='lj_userpicselect_img_txt'>";
        $$pic .= LJ::Lang::ml('entryform.userpic.choose');
        $$pic .= "</span></a></p></div>\n";
    }
    elsif ( !$u || $opts->{altlogin} ) {
        $$pic .=
"<div id='userpic'><p id='userpic_preview'><img src='/img/nouserpic.png' alt='selected userpic' id='userpic_preview_image' class='userpic_loggedout'  /></p></div>";
    }
    else {
        $$pic .=
"<div id='userpic'><p id='userpic_preview' class='userpic_preview_border'><a href='$LJ::SITEROOT/manage/icons'>$userpic_msg_upload</a></p></div>";
    }

    if ($has_icons) {

        my @pickws = map { ( $_, $_ ) } @{ $res->{pickws} };

        my $display = '';
        if ( exists $opts->{altlogin} ) {
            my $userpic_display = $opts->{altlogin} ? 'none' : 'block';
            $display = " style='display: $userpic_display;'";
        }
        my $tabindex = $opts->{entry_js} ? '~~TABINDEX~~' : undef;

        $$picform .= "<p id='userpic_select_wrapper' class='pkg'$display>\n";
        $$picform .= "<label for='prop_picture_keyword' class='left'>";
        $$picform .= LJ::Lang::ml('entryform.userpic') . " </label>\n";
        $$picform .= LJ::html_select(
            {
                name     => 'prop_picture_keyword',
                id       => 'prop_picture_keyword',
                class    => 'select',
                selected => $opts->{prop_picture_keyword},
                onchange => "userpic_preview()",
                tabindex => $tabindex,
            },
            "", $defpic, @pickws
        ) . "\n";
        $$picform .= "<a href='javascript:void(0);' id='lj_userpicselect'> </a>";

        # userpic browse button
        if ($onload) {
            $$onload .= " insertViewThumbs();" if $u->can_use_userpic_select;

            # random icon button
            $$picform .= "<a href='javascript:void(0)' onclick='randomicon();' id='randomicon'>";
            $$picform .= LJ::Lang::ml('entryform.userpic.random') . "</a>";
            $$onload  .= " showRandomIcon();";
        }
        else {
            $$picform .= q {
                           <script type="text/javascript" language="JavaScript">
                           userpic_preview();
                           };
            $$picform .= "insertViewThumbs()" if $u->can_use_userpic_select;
            $$picform .= "</script>\n";
        }
        $$picform .= LJ::help_icon_html( "userpics", "", " " );
        $$picform .= "</p>\n\n";
    }

    return;
}

1;
