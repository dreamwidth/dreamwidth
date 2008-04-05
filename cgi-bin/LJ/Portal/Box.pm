# Portal box abstract base class
# Subclass Box to create useful modules for portal

# The box is responsible for managing all of its state in memory
# and in the database.

# Box contains lots of handy functions for setting and getting
# per-box configuration options, displaying, making a config dialog,
# moving around and more.

package LJ::Portal::Box;
use strict;
use LJ::Portal::Config;
use fields qw(pboxid col sortorder u boxprops);

sub new {
    my LJ::Portal::Box $self = shift;
    $self = fields::new($self) unless ref $self;

    my $pboxid = shift;
    my $u = shift;

    $self->{'u'} = $u if defined $u;
    $self->{'pboxid'} = $pboxid if defined $pboxid;

    # if called with $pboxid then load box config
    $self->load_config if ($pboxid && $u);

    return $self;
}

# box's display name
sub box_name { '(no name)'; }
# short description of what the box does
sub box_description { '(no description)'; }
# box class
sub box_class { print STDERR "box class not defined!\n"; }

#optional:
    #sub initialize
    #sub config_props
    #sub prop_keys
    #sub handle_request($get, $post)

#####################################################

# opts->{'force'} = don't load from memcache
sub load_config {
    my LJ::Portal::Box $self = shift;

    my $pboxid = shift;
    my $u = shift;
    my $opts = shift || {};

    $self->{'u'} ||= $u;
    $self->{'pboxid'} ||= $pboxid;

    return unless $self->{'u'} || $self->{'pboxid'};

    my $state = $self->get_memcache_state;
    if ($state && !$opts->{'force'}) {
        $self->{'col'} = $state->{'col'};
        $self->{'sortorder'} = $state->{'sortorder'};
    } else {
        my $sth = $self->{'u'}->prepare("SELECT col, sortorder FROM portal_config WHERE userid=? AND pboxid=?");
        $sth->execute($self->{'u'}->{'userid'}, $self->{'pboxid'});
        my ($col, $sortorder) = $sth->fetchrow_array;
        $self->{'col'} = $col;
        $self->{'sortorder'} = $sortorder;
    }

    # don't let the box load things if it's disabled
    unless ($self->box_is_disabled) {
        $self->load_props;

        # tell subclass to initialize itself
        $self->initialize if $self->can('initialize');
    }
}

# delete self
sub delete {
    my LJ::Portal::Box $self = shift;

    # delete this box from DB
    $self->{'u'}->do("DELETE FROM portal_config WHERE pboxid=? AND userid=?",
                     undef, $self->pboxid, $self->{'u'}->{'userid'});

    LJ::MemCache::delete($self->memcache_key);
    $self->delete_memcached_contents;
    $self->delete_all_props;
}

# remove cached contents
sub delete_memcached_contents {
    my $self = shift;
    LJ::MemCache::delete($self->contents_memcache_key) if $self->contents_memcache_key;
}

# memcache key for caching contents
sub contents_memcache_key {
    my $self = shift;

    my $globalcache = 0;

    # global if explicitly defined, otherwise per-box
    $globalcache = 1 if ($self->can('cache_global') && $self->cache_global);

    # calculate memcache key
    if ($globalcache) {
        return [$self->type_id, 'prtcong:' . $self->type_id];
    }

    return [$self->{'u'}->{'userid'}, 'prtconu:' .
            $self->{'u'}->{'userid'} . ':' . $self->pboxid ];
}

# create a new box and save it
# args: u, col, sortorder
sub create {
    my LJ::Portal::Box $self = shift;
    my ($u, $col, $sortorder) = @_;

    my $userid = $u->{'userid'};
    return unless ($userid && $self->type_id);

    $col ||= 'L';
    $sortorder ||= 0;
    my $pboxid = LJ::alloc_user_counter($u, 'O');
    return unless $pboxid;

    # save this box in the DB, then get the pboxid
    $u->do("INSERT INTO portal_config (col, sortorder, type, userid, pboxid) VALUES (?, ?, ?, ?, ?)",
                     undef, $col, $sortorder, $self->type_id,
                     $userid, $pboxid);
    if ($u->errstr) {
        print STDERR "Error: " . $u->errstr . "\n"; # where should these go?
        return undef;
    }

    $self->{'col'} = $col;
    $self->{'sortorder'} = $sortorder;
    $self->{'u'} = $u;
    $self->{'pboxid'} = $pboxid;

    $self->update_memcache_state;

    return $self;
}

# returns an image of the icon for this box if one exists
sub box_icon {
    my LJ::Portal::Box $self = shift;
    my $boxclass = $self->box_class;

    # is there an icon for this box?
    my $boxicon;
    if (-e "$LJ::HTDOCS/img/portal/ModuleIcons/$boxclass.gif") {
        $boxicon = "<span class=\"PortalBoxIcon\"><img src=\"$LJ::IMGPREFIX/portal/ModuleIcons/$boxclass.gif\" valign=\"bottom\" /></span>";
    }

    return $boxicon;
}

sub type_id {
    my LJ::Portal::Box $self = shift;
    return LJ::Portal::Config->type_string_to_id($self->box_class);
}

sub pboxid {
    my LJ::Portal::Box $self = shift;
    return $self->{'pboxid'};
}

sub box_is_disabled {
    my LJ::Portal::Box $self = shift;

    my $type = $self->box_class;
    return $LJ::DISABLED{"portal-$type"} || 0;
}

# getter and setter
sub col {
    my LJ::Portal::Box $self = shift;
    if ( $_[0] ) {
        my $newcol = shift if $_[0] =~ /^[A-Z]$/i;
        $self->{'col'} = $newcol;
        $self->{'u'}->do("UPDATE portal_config SET col=? WHERE userid=? AND pboxid=?",
                          undef, $self->{'col'}, $self->{'u'}->{'userid'}, $self->{'pboxid'});
        $self->update_memcache_state;
    }
    return $self->{'col'};
}

# getter and setter
sub sortorder {
    my LJ::Portal::Box $self = shift;
    my $userid = $self->{'u'}->{'userid'};
    if ( $_[0] ) {
        my $neworder = shift if $_[0] =~ /^\d$/;
        $self->{'sortorder'} = $neworder;
        $self->{'u'}->do("UPDATE portal_config SET sortorder=? WHERE userid=? AND pboxid=?",
                          undef, $self->{'sortorder'}, $userid, $self->{'pboxid'});
        $self->update_memcache_state;
    }

    return $self->{'sortorder'};
}

sub update_memcache_state {
    my LJ::Portal::Box $self = shift;
    LJ::MemCache::set($self->memcache_key, $self->get_state) if $self->memcache_key;
}

sub get_memcache_state {
    my LJ::Portal::Box $self = shift;
    my $state = LJ::MemCache::get($self->memcache_key);
    return $state;
}

sub memcache_key {
    my LJ::Portal::Box $self = shift;
    if ($self->{'u'} && $self->{'pboxid'}) {
        my $key = [ $self->{'u'}->{'userid'}, "prtbox:$self->{'u'}->{'userid'}:" . $self->pboxid ];
        return $key;
    }
    return undef;
}

# return a representation of the current box for storage
sub get_state {
    my LJ::Portal::Box $self = shift;
    my $state = {
                 'col'       => $self->{'col'},
                 'sortorder' => $self->{'sortorder'},
                 'pboxid'    => $self->{'pboxid'},
                 'boxprops'  => $self->{'boxprops'},
                };
    return $state;
}

sub move {
    my LJ::Portal::Box $self = shift;
    my ($col, $sortorder) = @_;
    return unless $self->{'u'};
    return if (!$col && !$sortorder);

    $self->{'col'} = $col if $col;
    $self->{'sortorder'} = $sortorder if $sortorder;

    # save settings
    $self->{'u'}->do("UPDATE portal_config SET col=?, sortorder=? WHERE pboxid=? AND userid=?",
                     undef, $self->{'col'}, $self->{'sortorder'},
                     $self->{'pboxid'}, $self->{'u'}->{'userid'});

    $self->update_memcache_state;
}

sub load_props {
    my LJ::Portal::Box $self = shift;
    my $userid = $self->{'u'}->{'userid'};
    my $pboxid = $self->{'pboxid'};

    return if ref $self->{'boxprops'};

    $self->{'boxprops'} = {};

    return unless ($userid && $pboxid);

    my $state = $self->get_memcache_state;
    if ($state) {
        $self->{'boxprops'} = $state->{'boxprops'};
    } else {
        my $sth = $self->{'u'}->prepare("SELECT propvalue,ppropid FROM portal_box_prop WHERE userid=? AND pboxid=?");
        $sth->execute($userid, $pboxid);

        while (my $row = $sth->fetchrow_hashref) {
            $self->{'boxprops'}->{$row->{'ppropid'}} = $row->{'propvalue'};
        }
    }
    $self->update_memcache_state;
}

sub box_props {
    my LJ::Portal::Box $self = shift;
    return $self->{'boxprops'};
}

sub get_props {
    my LJ::Portal::Box $self = shift;
    my $boxprops = $self->prop_keys;

    my $props = {};
    map { $props->{$_} = $self->get_prop($_) } keys %$boxprops;

    return $props;
}

sub get_prop {
    my LJ::Portal::Box $self = shift;
    my $propstr = shift;

    my $propid = $self->get_prop_id($propstr);
    my $propval = $self->{'boxprops'}->{$propid};
    my $_config_props = $self->config_props;

    my $default = $_config_props->{$propstr}->{'default'};
    $propval = defined $propval ? $propval : $default;

    return $propval;
}

# return a propid for a string
sub get_prop_id {
    my LJ::Portal::Box $self = shift;
    my $propname = shift;

    my $configprops = $self->prop_keys;
    return $configprops->{$propname};
}

sub set_default_props {
    my LJ::Portal::Box $self = shift;

    return unless $self->can('config_props') && $self->can('prop_keys');

    my $_config_props = $self->config_props;
    my $propkeys = $self->prop_keys;
    my $default_props = {};
    foreach my $propkey (keys %$_config_props) {
        my $default = $_config_props->{$propkey}->{'default'};
        $default_props->{$propkey} = $default if defined $default;
    }
    $self->set_props($default_props) if $default_props != {};
    $self->delete_memcached_contents;
    $self->update_memcache_state;
}

sub set_prop {
    my LJ::Portal::Box $self = shift;
    my ($propstr, $propval) = @_;

    my $propid = $self->get_prop_id($propstr);
    my $u = $self->{'u'};

    $propid += 0;
    return undef unless ($self->{'pboxid'} || $u || $propid);

    # don't update memcache and do query if setting prop to the current value
    if ($self->{'boxprops'}->{$propid} ne $propval) {
        $self->{'boxprops'}->{$propid} = $propval;

        #save prop
        $u->do("REPLACE INTO portal_box_prop (propvalue,ppropid,userid,pboxid) VALUES " .
                         "(?, ?, ?, ?)",
                         undef, $propval, $propid, $u->{'userid'}, $self->pboxid);

        if ($u->errstr) {
            print STDERR "Error: " . $u->errstr . "\n";
            return undef;
        }

        $self->update_memcache_state;
        $self->delete_memcached_contents;
    }

    return 1;
}

sub delete_prop {
    my LJ::Portal::Box $self = shift;
    my $propid = shift;

    $propid += 0;
    $self->{'u'}->do("DELETE FROM portal_box_prop WHERE userid=? AND pboxid=? AND ppropid=?",
                     undef, $self->{'u'}->{'userid'}, $self->pboxid, $propid);
    delete $self->{'boxprops'}->{$propid};
    $self->update_memcache_state;
}

sub delete_all_props {
    my LJ::Portal::Box $self = shift;

    foreach my $propid (keys %{$self->{'boxprops'} || {}}) {
        delete $self->{'boxprops'}->{$propid};
    }

    $self->{'u'}->do("DELETE FROM portal_box_prop WHERE userid=? AND pboxid=?",
                     undef, $self->{'u'}->{'userid'}, $self->pboxid);

    $self->update_memcache_state;
}

# TODO: optimize query?
sub set_props {
    my LJ::Portal::Box $self = shift;
    my $props = shift;

    foreach my $propstr (keys %$props) {
        $self->set_prop($propstr, $props->{$propstr});
    }
}

# create the html for a box that contains a config dialog for this box.
# When the user clicks save, it will try to do an XML HTTP request to save
# the config, and if that fails then a normal submit.
sub generate_box_config_dialog {
    my LJ::Portal::Box $self = shift;
    my $jsmode = shift;

    return unless $self->config_props;

    my $pboxid = $self->pboxid;
    my $props = $self->box_props;
    my $configopts = $self->config_props;
    my $formelements = '';
    my $config = '';
    my $selflink = '/portal/index.bml';

    $config .= qq {
        <form action='$selflink' method='POST' name='configform$pboxid' id='configform$pboxid' style='display: inline;'>
            <div class="PortalBoxConfigContent">
        };

    $config .= "<table><tbody>";
    $config .= LJ::html_hidden({'name' => 'realform', 'value' => 1, 'id' => "realform$pboxid"},
                               {'name' => 'pboxid', 'value' => $pboxid});

    my @opts = sort {$self->get_prop_id($a) <=> $self->get_prop_id($b)} keys %$configopts;

    foreach my $optkey (@opts) {
        my $opt = $configopts->{$optkey};
        my $name = LJ::ehtml($optkey);
        my $type = $opt->{'type'};
        my $disabled = $opt->{disabled} ? ((ref $opt->{disabled} eq 'CODE') ? $opt->{disabled}->($self) : '') : '';
        my $desc = LJ::ehtml($opt->{'desc'});
        my $propkey = $optkey;
        my $propval = LJ::ehtml($self->get_prop($propkey) || $opt->{'default'});

        my $inputfield;

        $config .= '<tr><td>';

        if ($type eq 'checkbox') {

            $inputfield .= "<label for='$name$pboxid'>";
            $inputfield .= "$desc: </td><td>";

            # checkboxes are dumb.
            if ($self->get_prop($propkey)) {
                $inputfield .= LJ::html_check({
                    'name' => $name . $pboxid,
                    'id' => $name . $pboxid,
                    'checked' => 1,
                    'disabled' => $disabled,
                });
            } else {
                $inputfield .= LJ::html_check({
                    'name' => $name . $pboxid,
                    'id' => $name . $pboxid,
                    'disabled' => $disabled,
                });
            }

            $inputfield .= "</label>";

        } elsif ($type eq 'dropdown') {

            $inputfield = "$desc: </td><td>";

            # make a dropdown menu composed of items
            my $selected = '';

            $inputfield .= "<select name='$name$pboxid' id='$name$pboxid'>\n";

            my $items = $opt->{'items'};

            foreach my $item (keys %$items) {
                if ($self->get_prop($propkey) eq $item) {
                    $selected = 'selected';
                } else {
                    $selected = '';
                }

                $item = LJ::ehtml($item);
                my $itemtitle = LJ::ehtml($items->{$item});
                $inputfield .= "<option value='$item' $selected>$itemtitle</option>\n";
            }
            $inputfield .= '</select>';

        } elsif ($type eq 'integer') {

            $inputfield = "$desc: </td><td>";

            $inputfield .= LJ::html_text({'id' => $name . $pboxid,
                                          'value' => $propval,
                                          'maxlength' => $opt->{'maxlength'},
                                          'size' => $opt->{'maxlength'} || 3,
                                          'max' => $opt->{'max'},
                                          'min' => $opt->{'min'},
                                          'name' => $name . $pboxid,
                                      });
       } elsif ($type eq 'string') {

            $inputfield = "$desc: </td><td>";

            $inputfield .= LJ::html_text({'id' => $name . $pboxid,
                                          'value' => $propval,
                                          'maxlength' => $opt->{'maxlength'},
                                          'size' => $opt->{'maxlength'} || 3,
                                          'name' => $name . $pboxid,
                                      });

        } elsif ($type eq 'hidden') {
            #do nothing
        } else {
            print STDERR "Warning: unknown box config type $type\n";
        }

        $formelements .= $name . ',' unless $type eq 'hidden';
        $config .= "<div>$inputfield</div></td></tr>";
    }
    $config .= '</tbody></table>';

    chop $formelements;

    my $buttons = '<div class="PortalConfigSubmitButtons">';

    $buttons .= "<span class=\"PortalConfigResetButton\">";

    # text link for non-javascript browsers
    if (!$jsmode) {
        $buttons .= "<a href=\"$selflink?resetbox=1&pboxid=$pboxid\" onclick=\"return resetBox($pboxid);\">Reset</a>";
    } else {
        $buttons .= qq {
            <input type="Button" value="Reset" onclick="return resetBox($pboxid);" />
            };
    }
    $buttons .= "</span>";

    $buttons .= qq {
        <span class="PortalConfigCancelButton">
            <input type="button" value="Cancel" onclick="fadeOut('config$pboxid'); return false;" />
        </span>
    } if $jsmode;

    $buttons .= '<span class="PortalConfigSubmitButton">';
    $buttons .= LJ::html_submit('saveconfig', 'Save Settings', {'raw' => "onclick=\"if(savePortalBoxConfig($pboxid)) configform$pboxid.submit(); else return false;\""});
    $buttons .= qq{<input type="hidden" id="box_config_elements$pboxid" value="$formelements"/>};
    $buttons .= qq {
          </span>
        </div>
      </form>
  };

    my $dialogbox = qq{
            $config
        </div>
        $buttons
    };

    return $dialogbox;
}

1;
