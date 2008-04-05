#!/usr/bin/perl

package LJ::Portal;

use strict;

use lib "$ENV{LJHOME}/cgi-bin";
use LJ::Portal::Config;
use LJ::Portal::Box;

sub new {
    my LJ::Portal $self = shift;

    bless $self, "LJ::Portal";
    return $self;
}


# Make sure that there is a typeid loaded for $class, and
# insert one into the DB if none exists.
# also loads typemaps from DB into $LJ::PORTAL_TYPEMAP

# args: portal classname to look up ID for
sub load_box_typeid {
    my ($self, $class) = @_;

    die "No portal box class defined" unless $class;

    # is it process-cached?
    return 1 if $LJ::PORTAL_TYPEMAP{$class};

    # is it memcached?
    my $memcached_typemap = LJ::MemCache::get("portal_typemap");
    if ($memcached_typemap) {
        # process-cache it
        %LJ::PORTAL_TYPEMAP = %$memcached_typemap;

        # if we have the class, we're cool
        return 1 if $LJ::PORTAL_TYPEMAP{$class};
    }

    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    # load typemap from DB
    my $sth = $dbr->prepare("SELECT id, class_name FROM portal_typemap");
    return undef unless $sth;
    $sth->execute;

    while (my $idmap = $sth->fetchrow_hashref) {
        $LJ::PORTAL_TYPEMAP{$idmap->{'class_name'}} = $idmap->{'id'};
    }

    my $classid = $LJ::PORTAL_TYPEMAP{$class};

    # do we have this class's ID?
    if (!$classid) {
        my $dbh = LJ::get_db_writer();
        # box does not have an ID registered for itself in the DB
        # try to insert

        $dbh->do("INSERT IGNORE INTO portal_typemap (class_name) VALUES (?)",
                 undef, $class);

        if ($dbh->{'mysql_insertid'}) {
            # inserted fine, get ID
            $classid = $dbh->{'mysql_insertid'};
        } else {
            # race condition, try to select again
            $classid = $dbh->selectrow_array("SELECT id FROM portal_typemap WHERE class_name = ?",
                                           undef, $class)
                or die "Portal typemap should have found ID after race";
        }

        # we had better have a classid by now... big trouble if we don't
        die "Could not create typeid for portal module $class" unless $classid;

        # save new classid
        $LJ::PORTAL_TYPEMAP{$class} = $classid;
    }

    # memcache typeids
    LJ::MemCache::set("portal_typemap", \%LJ::PORTAL_TYPEMAP, 120);

    return $classid;
}

sub load_portal_boxes {
    my $self = shift;

    foreach my $boxclass (@LJ::PORTAL_BOXES) {
        require "LJ/Portal/Box/${boxclass}.pm";
    }
}

sub get_close_button {
    return qq{<img src="$LJ::IMGPREFIX/portal/PortalConfigCloseButton.gif" width=19 height=19 title="Close" title="Close" valign="middle" />};
}

# get a little faq link and help icon
sub get_faq_link {
    my LJ::Portal $self = shift;
    my $faqkey = shift;

    return qq {
        <a href="$LJ::HELPURL{$faqkey}"><img src="$LJ::IMGPREFIX/help.gif" class="PortalFaqLink" title="Help" /></a>
    };
}

sub create_button {
    my LJ::Portal $self = shift;
    my ($text, $action) = @_;
    $text = LJ::ehtml($text);
    return qq{
        <div class="PortalButton" onmousedown="this.className='PortalButton PortalButtonMouseDown';" onclick="$action" onmouseup="this.className='PortalButton';">$text</div>
        };
}

sub get_portal_box_display_script {
    my LJ::Portal $self = shift;
    my ($id, $class_name, $inner_html, $parent) = @_;

    # escape everything
    $class_name = LJ::ejs($class_name);
    $inner_html = LJ::ejs($inner_html);
    $id = LJ::ejs($id);
    $parent = LJ::ejs($parent);

    return qq{
        var boxelement = xCreateElement("div");
        var parentelement = xGetElementById("$parent");
        if (boxelement && parentelement) {
            boxelement.id = "$id";
            boxelement.className = "$class_name PortalBox";
            boxelement.innerHTML = '$inner_html';
            xAppendChild(parentelement, boxelement);
            fadeIn(boxelement, 200);
        }
    };
}

sub get_portal_box_update_script {
    my LJ::Portal $self = shift;
    my ($config, $box) = @_;

    my $pboxid = $box->pboxid();

    # does this box have a handler to generate extra javascript to be executed
    # when the box is reloaded?
    my $onreload = '';
    if ($box->can('box_updated')) {
        $onreload = $box->box_updated;
    }

    my $newcontents = LJ::ejs($config->generate_box_insides($pboxid), 1);

    return
        qq{
            var box = xGetElementById('pbox$pboxid');
            if (box) {
                box.innerHTML = "$newcontents";
            }
            if (box_reloading && box_reloading[$pboxid]) box_reloading[$pboxid]=0;
            $onreload
        };
}

sub get_portal_box_titlebar_update_script {
    my LJ::Portal $self = shift;
    my ($config, $box) = @_;

    my $pboxid = $box->pboxid();
    my $newcontents = LJ::ejs($config->generate_box_titlebar($box));
    return
        qq{
            var bar = xGetElementById('pboxtitlebar$pboxid');
            if (bar) {
                bar.innerHTML = "$newcontents";
            }
        };
}

sub get_portal_config_box_update_script {
    my LJ::Portal $self = shift;
    my $box = shift;
    return unless $box;

    my $pboxid = $box->pboxid;
    my $newcontents = LJ::ejs($box->generate_box_config_dialog(1));
    return qq{
            var confbox = xGetElementById('PortalFensterContentconfig$pboxid');
            if (confbox) {
                confbox.innerHTML = "$newcontents";
            }
        };
}

sub create_fenster {
    my LJ::Portal $self = shift;
    my ($id, $class_name, $inner_html, $parent, $title) = @_;

    # escape everything
    $title = LJ::ehtml($title);
    $class_name = LJ::ejs($class_name);
    $inner_html = LJ::ejs($inner_html);
    $id = LJ::ejs($id);
    $parent = LJ::ejs($parent);

    my $titlebar_html = LJ::ejs(qq{
        <div class="PortalPatternedTitleBar" id="portalbar$id">
            <span class="PortalTitleBarText">$title</span>
            </div>
        });
    return qq{
        var boxelement    = xCreateElement("div");
        var parentelement = xGetElementById("$parent");
        if (boxelement && parentelement) {
            xAppendChild(document.body, boxelement);
            boxelement.id = "$id";
            boxelement.style.position='absolute';
            boxelement.className = "$class_name PortalFenster";
            boxelement.innerHTML = '$titlebar_html <div class=\"PortalFensterContent NormalCursor\" id=\"PortalFensterContent$id\">$inner_html</div>';
            fadeIn(boxelement);
            boxelement.style.zIndex=4;
        }
    };
}


### XML HTTP Request Fun Stuff

sub addbox {
    my LJ::Portal $self = shift;
    my ($portalconfig, $boxtype, $boxcol) = @_;

    my $returncode = '';

    if ($boxtype =~ /^\w+$/ && $boxcol =~ /^\w$/) {
        my $newbox = $portalconfig->add_box("$boxtype", $boxcol);
        if ($newbox) {
            my $pboxid = $newbox->pboxid;
            my $innerHTML = $portalconfig->generate_box_insides($pboxid);
            my $boxclass = $newbox->box_class;
            $returncode .= LJ::Portal->get_portal_box_display_script("pbox$pboxid", "PortalBox $boxclass", $innerHTML, "PortalCol$boxcol");

            # update the arrows on the last box in the column
            my $prevbox = $portalconfig->prev_box($newbox);
            if ($prevbox) {
                $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $prevbox);
            }

            $returncode = 'alert("Could not add box.");' if ! $returncode;
        } else {
            $returncode = 'alert("Could not create a box of that type.");';
        }
    } else {
        $returncode = 'alert("Invalid box creation parameters.");';
    }

    # update add module menu in background
    $returncode .= "\nupdateAddPortalModuleMenu();\n";

    return $returncode;
}

sub configbox {
    my LJ::Portal $self = shift;
    my ($pboxid, $portalconfig, $jsmode) = @_;

    my $box = $portalconfig->get_box_by_id($pboxid);
    my $configboxhtml;
    my $returncode;

    if ($box) {
        $configboxhtml = $box->generate_box_config_dialog($jsmode);

        my $insertConfigBox =
            LJ::Portal->create_fenster(
                                       "config$pboxid", 'PortalBoxConfig',
                                       $configboxhtml, "pbox$pboxid",
                                       "Configure " . $box->box_name,
                                       );

        my $configboxjs = $insertConfigBox . qq{
            var pbox = xGetElementById("pbox$pboxid");
            var configbox = xGetElementById("config$pboxid");
            if (pbox && configbox) {
                xTop(configbox, xPageY(pbox));
                centerBoxX(configbox);
            }
        };
        $returncode = $configboxjs;
    } else {
        $returncode = 'alert("Could not load box properties.");';
    }

    return ($returncode, $configboxhtml);
}

sub movebox {
    my LJ::Portal $self = shift;
    my ($pboxid, $portalconfig, $boxcol,
        $boxcolpos, $moveUp, $moveDown) = @_;

    my $returncode;
    my $oldSwapBox = undef;

    if (($boxcolpos || $moveUp || $moveDown || $boxcol =~ /^\w$/) && $pboxid) {
        my $box = $portalconfig->get_box_by_id($pboxid);
        if ($box) {
            my $inserted = 0;
            my $oldPrevBox = $portalconfig->prev_box($box);
            my $oldNextBox = $portalconfig->next_box($box);

            if ($moveUp) {
                $oldSwapBox = $portalconfig->move_box_up($box);
            } elsif ($moveDown) {
                $oldSwapBox = $portalconfig->move_box_down($box);
            } else {
                if ($boxcolpos) {
                    # insert this box instead of append
                    my $insertbeforebox = $portalconfig->find_box_by_col_order($boxcol, $boxcolpos+1);
                    if ($insertbeforebox && $boxcol ne $box->col) {
                        my $newsortorder = $insertbeforebox->sortorder;
                        $portalconfig->insert_box(
                                                  $box, $boxcol,
                                                  $newsortorder
                                                  );
                        $inserted = 1;
                        $oldSwapBox = $insertbeforebox;
                    } else {
                        # nothing to insert before, append
                        $oldSwapBox = $portalconfig->move_box($box, $boxcol);
                    }
                } else {
                    $oldSwapBox = $portalconfig->move_box($box, $boxcol);
                }
            }

            $returncode = LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $box);

            if ($oldPrevBox) {
                $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $oldPrevBox);
            }
            if ($oldNextBox) {
                $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $oldNextBox);
            }

            # if this box is going where a box already exists do a swap
            if ($oldSwapBox) {
                if ($inserted) {
                    my $nextid = $oldSwapBox->pboxid;
                    $returncode .= qq {
                        var nextbox = xGetElementById("pbox$nextid");
                        var toinsert = xGetElementById("pbox$pboxid");
                        if (toinsert) {
                            var par = xParent(toinsert, true);
                            if (nextbox)
                                par.insertBefore(toinsert, nextbox);
                            else
                                par.appendChild(toinsert);
                        }
                    };
                }
            }

            # update the arrows on all adjacent boxes
            my $prevbox = $portalconfig->prev_box($box);
            my $nextbox = $portalconfig->next_box($box);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $prevbox) if ($prevbox && $prevbox != $oldPrevBox && $prevbox != $oldNextBox);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $nextbox) if ($nextbox && $nextbox != $oldPrevBox && $nextbox != $oldNextBox);
        } else {
            $returncode = 'alert("Box not found.");';
        }
    } else {
        $returncode = 'alert("Invalid move parameters.");';
    }

    return $returncode;
}

sub getmenu {
    my LJ::Portal $self = shift;
    my ($portalconfig, $menu) = @_;

    my $returncode;

    if ($menu) {
        if ($menu eq 'addbox') {
            my @classes = $portalconfig->get_box_classes;

            my $addboxtitle = BML::ml('/portal/index.bml.addbox');

            $returncode .= qq{
                    <div class="DropDownMenuContent PortalMenuItem">
                    <table style="width:100%;" class="PortalMenuItem">
                };

            my $row = 0;
            @classes = sort { "LJ::Portal::Box::$a"->box_name cmp "LJ::Portal::Box::$b"->box_name } @classes;
            foreach my $boxclass (@classes) {
                my $fullboxclass = "LJ::Portal::Box::$boxclass";
                # if there can only be one of these boxes at a time and there
                # already is one, don't show it
                if ($portalconfig->get_box_unique($boxclass)) {
                    next if $portalconfig->find_box_by_class($boxclass);
                }

                # is this box hidden from users?
                # either box_hidden returns true or the box is in
                # @LJ::PORTAL_BOXES_HIDDEN
                if ( (@LJ::PORTAL_BOXES_HIDDEN && grep { $_ eq $boxclass }
                      @LJ::PORTAL_BOXES_HIDDEN) || ($fullboxclass->can('box_hidden') &&
                                                    $fullboxclass->box_hidden) ) {
                    next;
                }

                my $boxname = $fullboxclass->box_name;
                my $boxdesc = $fullboxclass->box_description;
                my $boxcol  = $portalconfig->get_box_default_col($boxclass);
                my $boxicon = $fullboxclass->box_icon;
                my $addlink = qq{href="$LJ::SITEROOT/portal/index.bml?addbox=1&boxtype=$boxclass&boxcol=$boxcol" onclick="if(addPortalBox('$boxclass', '$boxcol')) return true; hidePortalMenu('addbox'); return false;"};
                my $rowmod = $row % 2 + 1;
                $returncode .= qq{
                    <tr class="PortalMenuRow$rowmod PortalMenuItem">
                        <td class="PortalMenuItem">
                          <a $addlink class="PortalMenuItem">
                            $boxicon <span class="PortalBoxTitleText PortalMenuItem">$boxname</span>
                          </a>
                          <div class="BoxDescription PortalMenuItem">$boxdesc</div>
                        </td>
                        <td align="center" valign="middle" class="PortalMenuItem">
                          <a $addlink class="PortalMenuItem">
                              <img src="$LJ::IMGPREFIX/portal/AddIcon.gif" title="Add this module" width="25" height="25" class="PortalMenuItem" />
                          </a>
                        </td>
                        </tr>
                        <br/>};
                $row++;
            }

            my $resetask = LJ::ejs(BML::ml('/portal/index.bml.resetall'));

            $returncode .= qq {
                      <tr class="PortalMenuItem"><td colspan="2" class="PortalMenuItem">
                          <div id="PortalResetAllButton" class="PortalMenuItem">
                            <form action="$LJ::SITEROOT/portal/index.bml" method="POST" style="display: inline;">
                                <input type="Submit" value="Reset..." name="resetall" onclick="return askResetAll('$resetask');" />
                            </form>
                          </div>
                      </td></tr>
                    </table>
                </div>
            };
        }
    } else {
        $returncode = 'alert("Menu not specified.");';
    }

    return $returncode;
}

sub saveconfig {
    my LJ::Portal $self = shift;
    my ($portalconfig, $pboxid, $realform, $postvars) = @_;

    my $box = $portalconfig->get_box_by_id($pboxid);
    my $returncode;

    if ($box) {
        my $configprops = $box->config_props;
        foreach my $propkey (keys %$configprops) {
            if ($propkey) {
                # slightly different format for non-POST submitted data
                my $postkey = $realform ? "$propkey$pboxid" : $propkey;
                my $propval = LJ::ehtml($postvars->{$postkey});

                my $type = $configprops->{$propkey}->{'type'};
                next if $type eq 'hidden';

                # check to see if value is valid:
                my $invalid = 0;

                if ($type eq 'integer') {
                    $invalid = 1 if ($propval != int($propval));
                    $propval = int($propval);
                    my $min = $configprops->{$propkey}->{'min'};
                    my $max = $configprops->{$propkey}->{'max'};
                    $invalid = 1 if ($min && $propval < $min);
                    $invalid = 1 if ($max && $propval > $max);
                } else {
                    $propval = LJ::ehtml($propval);
                }

                if (!$invalid) {
                    unless ($box->set_prop($propkey, $propval)) {
                        return 'alert("Error saving configuration");';
                    }
                } else {
                    return 'alert("Invalid input");';
                }
            }
        }
        $returncode .= LJ::Portal->get_portal_box_update_script($portalconfig, $box);
        $returncode .= "hideConfigPortalBox($pboxid);";
    } else {
        $returncode = 'alert("Box not found.");';
    }

    return $returncode;
}

sub delbox {
    my LJ::Portal $self = shift;
    my ($portalconfig, $pboxid) = @_;

    my $returncode;

    if ($pboxid) {
        my $box = $portalconfig->get_box_by_id($pboxid);
        if ($box) {
            $portalconfig->remove_box($pboxid);

            # update the arrows on nearby boxes
            my $prevbox = $portalconfig->prev_box($box);
            my $nextbox = $portalconfig->next_box($box);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $prevbox) if ($prevbox);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $nextbox) if ($nextbox);
        } else {
            $returncode = 'alert("Box not found.");';
        }
    } else {
        $returncode = 'alert("Box not specified.");';
    }

    # update add module menu in background
    $returncode .= "\nupdateAddPortalModuleMenu();\n";

    return $returncode;
}

sub resetbox {
    my LJ::Portal $self = shift;
    my ($pboxid, $portalconfig) = @_;

    my $returncode;

    if ($pboxid) {
        my $box = $portalconfig->get_box_by_id($pboxid);

        if ($box) {
            $box->set_default_props;

            $returncode .= LJ::Portal->get_portal_box_update_script($portalconfig, $box);
            $returncode .= LJ::Portal->get_portal_config_box_update_script($box);
            $returncode .= "hideConfigPortalBox($pboxid);\n";
        } else {
            $returncode = 'alert("Box not found.");';
        }
    } else {
        $returncode = 'alert("Box not specified.");';
    }

    return $returncode;
}

1;
