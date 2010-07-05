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

sub need_res {

   return qw( js/core.js
              js/dom.js
              js/json.js
              js/template.js
              js/ippu.js
              js/lj_ippu.js
              js/userpicselect.js
              js/httpreq.js
              js/hourglass.js
              js/inputcomplete.js
              stc/ups.css
              stc/entry.css
              js/datasource.js
              js/selectable_table.js
              );

}

sub handle_post {
    my $class = shift;

    return;
}

sub render_body {
    my ($class, $user, $head, $pic, $picform, $opts) = @_;

    my $u = $user;
    return "" unless $u;
    return "" unless LJ::is_enabled('userpicselect') || $u->can_use_userpic_select;

    my $res;
    $res = LJ::Protocol::do_request("login", {
        "ver" => $LJ::PROTOCOL_VER,
        "username" => $u->{'user'},
        "getpickws" => 1,
        "getpickwurls" => 1,
    }, undef, {
        "noauth" => 1,
        "u" => $u,
    });

    ### Userpic
    my $userpic_preview = "";

    # User Picture
    if ($res && ref $res->{'pickws'} eq 'ARRAY' && scalar @{$res->{'pickws'}} > 0) {
        my @pickws = map { ($_, $_) } @{$res->{'pickws'}};
        my $num = 0;
        my $userpics .= "    userpics[$num] = \"$res->{'defaultpicurl'}\";\n";
        my $altcode .= "     alttext[$num] = \"" . BML::ml('entryform.opt.defpic') . "\";\n";
        foreach (@{$res->{'pickwurls'}}) {
            $num++;
            $userpics .= "    userpics[$num] = \"$_\";\n";
        }
        $num = 0;
        foreach ( @{$res->{pickws}} ) {
           $num++;
           $altcode .= "     alttext[$num] = \"" . LJ::ejs($_) . "\";\n";
        }

        my $userpic_link_text;
        $userpic_link_text = BML::ml('entryform.userpic.choose') if $u;

        $$head .= qq {
            <script type="text/javascript" language="JavaScript"><!--
                if (document.getElementById) {
                    var userpics = new Array();
                    var alttext = new Array();
                    $userpics
                    $altcode
                    function userpic_preview() {
                        if (! document.getElementById) return false;
                        var userpic_select          = document.getElementById('prop_picture_keyword');

                        if (\$('userpic') && \$('userpic').style.display == 'none') {
                            \$('userpic').style.display = 'block';
                        }
                        var userpic_msg;
                        if (userpics[0] == "") { userpic_msg = 'Choose default userpic' }
                        if (userpics.length == 0) { userpic_msg = 'Upload a userpic' }

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
                            userpic_preview.innerHTML = '<a href="$LJ::SITEROOT/editicons"><img src="" alt="selected userpic" id="userpic_preview_image" style="display: none;" /><span id="userpic_msg">' + userpic_msg + '</span></a>';
                        }
                    }
                }
            //--></script>
            };

        $$head .= qq {
            <script type="text/javascript" language="JavaScript">
            // <![CDATA[
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

        $$pic .= "<div id='userpic' style='display: none;'><p id='userpic_preview'><a href='javascript:void(0);' id='lj_userpicselect_img'><img src='' alt='selected userpic' id='userpic_preview_image' /><span id='lj_userpicselect_img_txt'>$userpic_link_text</span></a></p></div>";
        $$pic .= "\n";

        $$picform .= "<p id='userpic_select_wrapper' class='pkg'>\n";
        $$picform .= "<label for='prop_picture_keyword' class='left'>" . BML::ml('entryform.userpic') . " </label> \n" ;
        $$picform .= LJ::html_select({
                         'name' => 'prop_picture_keyword',
                         'id' => 'prop_picture_keyword',
                         'class' => 'select',
                         'selected' => $opts->{'prop_picture_keyword'},
                         'onchange' => "userpic_preview()",
                        },
                        "", BML::ml('entryform.opt.defpic'),
                        @pickws) . "\n";
        $$picform .= "<a href='javascript:void(0);' id='lj_userpicselect'> </a>";
        # userpic browse button
        $$picform .= LJ::help_icon_html("userpics", "", " ") . "\n";
        $$picform .= "</p>\n\n";
        $$picform .= q {
                       <script type="text/javascript" language="JavaScript">
                       userpic_preview();
                 };
        $$picform .= "insertViewThumbs()"
            if $u->can_use_userpic_select;
        $$picform .= "</script>\n";

    } elsif (!$u)  {
        $$pic .= "<div id='userpic'><p id='userpic_preview'><img src='/img/nouserpic.png' alt='selected userpic' id='userpic_preview_image' class='userpic_loggedout'  /></p></div>";
    } else {
        $$pic .= "<div id='userpic'><p id='userpic_preview' class='userpic_preview_border'><a href='$LJ::SITEROOT/editicons'>Upload a userpic</a></p></div>";
    }


    return;
}

1;
