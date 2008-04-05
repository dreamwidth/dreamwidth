#!/usr/bin/perl

# A portal Config object is a class designed for wrangling Box objects.
# It loads a user's box configuration and is responsible for arranging
# and maintaining a list of the current portal box configuration in memory.

package LJ::Portal::Config;

use lib "$ENV{LJHOME}/cgi-bin";
use LJ::Portal::Box;

# u: user object that is who this config is for
# boxes: arrayref of loaded Box objects for the user
# boxlist: arrayref of pboxid => type boxes for this user (memcached)
use fields qw(u boxes boxconfig boxlist profile);

use strict;

sub get_box_classes {
    # if someone is calling this function they want to do something
    # with all the modules available. To make sure nothing bad happens,
    # we need to "require" all the modules specified in ljconfig. If
    # the module is already loaded, splendid. If not, require will make
    # sure that it's loaded so errors don't get thrown.

    # require everything
    LJ::Portal->load_portal_boxes(); # requires all modules in config

    # return boxes, which should now all be loaded
    return @LJ::PORTAL_BOXES;
}

# args: $u, $profile
# profile: time the loading of boxes (value = how many times to benchmark)
sub new {
    my LJ::Portal::Config $self = shift;
    $self = fields::new($self) unless ref $self;

    my $u = shift;

    $self->{'u'} = {};
    $self->{'boxes'} = {};
    $self->{'boxlist'} = {};

    my $profile = shift;
    $profile ||= 0;
    $self->{'profile'} = $profile;

    # if called with $u then load config for user
    $self->load_config($u) if $u;

    return $self;
}

# arguments: takes a user to load configuration for
# opts hashref (options: 'force' = force load from DB and don't
#  even try memcache)
sub load_config {
    my LJ::Portal::Config $self = shift;
    my $u = shift;
    my $opts = shift || {};

    $self->{'u'} = $u if $u;
    return unless $self->{'u'};

    # get all portal boxes for this user:
    $self->{'boxlist'} = LJ::MemCache::get($self->memcache_key) unless $opts->{'force'};

    if (!$self->{'boxlist'}) {
        $self->{'boxlist'} = {};
        my $sth = $u->prepare("SELECT pboxid,type FROM portal_config WHERE userid=?");
        $sth->execute($self->{'u'}->{'userid'});
        while (my $row = $sth->fetchrow_hashref) {
            my $pboxid = $row->{'pboxid'};
            my $typeid = $row->{'type'};
            next unless ($pboxid && $typeid);

            $self->{'boxlist'}->{$pboxid} = $typeid;
        }

        # no boxes for user
        if (!%{$self->{'boxlist'}}) {
            # do we need to load the default state?
            if (!$u->prop('portalinit')) {
                # load default state
                $self->load_default_boxes;
                $u->set_prop('portalinit', localtime());
            }
        }

        $self->update_memcache_state;
    }

    # load the boxes themselves
    foreach my $pboxid (keys %{$self->{'boxlist'}}) {
        my $typeid = $self->{'boxlist'}->{$pboxid};
        next unless ($pboxid && $typeid);

        my $box = $self->new_box_by_type($typeid);
        next unless $box;

        $box->load_config($pboxid, $self->{'u'});
        $self->{'boxes'}->{$pboxid} = $box;
    }

    return 1;
}

# get the default column for a box class
# default is 'R' unless defined
sub get_box_default_col {
    my LJ::Portal::Config $self = shift;
    my $boxclass = shift;

    return $LJ::PORTAL_DEFAULTBOXSTATES{$boxclass}->{'col'} || 'R';
}

# get whether or not you can have more than one of a box
sub get_box_unique {
    my LJ::Portal::Config $self = shift;
    my $boxclass = shift;

    return $LJ::PORTAL_DEFAULTBOXSTATES{$boxclass}->{'notunique'} ? 0 : 1;
}

# add all the default boxes
sub load_default_boxes {
    my LJ::Portal::Config $self = shift;

    my @classes = $self->get_box_classes;

    foreach my $boxclass (sort @classes) {
        # check to see if the box has it's own code that needs to be run to determine
        # if it should be added by default
        my $fullboxclass = "LJ::Portal::Box::$boxclass";
        my $toadd;
        if ($fullboxclass->can('default_added')) {
            $toadd = $fullboxclass->default_added($self->{'u'});
        } else {
            $toadd = $LJ::PORTAL_DEFAULTBOXSTATES{$boxclass} && $LJ::PORTAL_DEFAULTBOXSTATES{$boxclass}->{'added'};
        }

        if ($toadd) {
            my $col = $self->get_box_default_col($boxclass);
            my $order = $LJ::PORTAL_DEFAULTBOXSTATES{$boxclass}->{'sort'};

            my $box = $self->add_box($boxclass, $col);
            # does it have a default position in the column? (it should, but...)
            if ($order && $box) {
                $box->move(undef, $order);
            }
        }
    }
}

# reset all of a user's settings
sub reset_all {
    my LJ::Portal::Config $self = shift;

    foreach my $pboxid (keys %{$self->{'boxlist'}}) {
        $self->remove_box($pboxid);
    }

    $self->load_default_boxes;
    $self->update_memcache_state;
}

# retreive all loaded boxes
sub get_boxes {
    my LJ::Portal::Config $self = shift;
    return $self->{'boxes'};
}

sub get_box_by_id {
    my LJ::Portal::Config $self = shift;
    my $id = shift;

    return $self->{'boxes'}->{$id};
}

# return the key for portal config memcache
sub memcache_key {
    my LJ::Portal::Config $self = shift;
    if ($self->{'u'}) {
        my $key = [ $self->{'u'}->{'userid'}, "prtcfg:$self->{'u'}->{'userid'}" ];
        return $key;
    }
    return undef;
}
sub update_memcache_state {
    my LJ::Portal::Config $self = shift;
    LJ::MemCache::set($self->memcache_key, $self->{'boxlist'})
        if $self->memcache_key && $self->{'boxlist'};
}

# return a new box object of type type
sub new_box_by_type {
    my LJ::Portal::Config $self = shift;
    my $type = shift;

    my $typeid = int($type) ? $type : $self->type_string_to_id($type);

    return undef unless (my $typename = $self->type_id_to_string($typeid));

    my $class = "LJ::Portal::Box::$typename";

    # if a box of this type already exists and this box type can only have one
    # at a time, don't do it
    if ($self->get_box_unique($typename)) {
        return undef if $self->find_box_by_class($typename);
    }

    my $box = $class->new;
    return $box;
}

# add a box
sub add_box {
    my LJ::Portal::Config $self = shift;
    my ($type, $column) = @_;
    return unless ($type && $column && $self->{'u'});

    # if this is a unique box, make sure we aren't duplicating it
    if ($self->get_box_unique($type)) {
        return if $self->find_box_by_class($type);
    }

    my $box = $self->new_box_by_type($type);
    return unless $box;
    my $sortorder = $self->max_sortorder($column)+1;

    if ($box->create($self->{'u'}, $column, $sortorder)) {
        # save box in self
        $self->{'boxes'}->{$box->pboxid} = $box;

        # save in memcache
        my $typeid = int($type) ? $type : $self->type_string_to_id($type);
        $self->{'boxlist'}->{$box->pboxid} = $typeid;
        $self->update_memcache_state;
    }

    return $box;
}

# insert a box at the sortorder and shift all the boxes below down
sub insert_box {
    my LJ::Portal::Config $self = shift;
    my ($box, $col, $sortorder) = @_;

    return unless ($box && $col && $sortorder);

    my $insertbefore = $self->find_box($col, $sortorder);
    if ($insertbefore) {
        # increase the sortorder of all the boxes underneath by 1
        my @colboxes = $self->get_col_boxes($col);
        foreach my $cbox (@colboxes) {
            if ($cbox->sortorder >= $sortorder && $cbox->pboxid != $box->pboxid) {
                my $neworder = $cbox->sortorder+1;
                $cbox->move($col, $neworder);
            }
        }

        $self->update_memcache_state;
    }
    return $self->move_box($box, $col, $sortorder);
}

# returns a box that the current box replaced
sub move_box {
    my LJ::Portal::Config $self = shift;
    my ($box, $col, $sortorder) = @_;
    return unless ($box && ($col || defined $sortorder));

    # if no col defined use the col the box is currently in
    $col ||= $box->col;

    # put box at end of list if moving cols
    $sortorder = $self->max_sortorder($col)+1 if !defined $sortorder;

    my $samebox = $self->find_box($col, $sortorder);

    if ($samebox) {
        $samebox->move($col, $box->sortorder);
    }

    $box->move($col, $sortorder);
    return $samebox;
}

sub move_box_up {
    my LJ::Portal::Config $self = shift;
    my $box = shift;

    my $sort = $box->sortorder;
    my $prevbox = $self->prev_box($box);
    return undef unless $prevbox;

    $self->move_box($box, $box->col, $prevbox->sortorder);

    return $prevbox;
}

sub move_box_down {
    my LJ::Portal::Config $self = shift;
    my $box = shift;

    my $sort = $box->sortorder;
    my $nextbox = $self->next_box($box);
    return undef unless $nextbox;

    $self->move_box($box, $box->col, $nextbox->sortorder);

    return $nextbox;
}


sub next_box {
    my LJ::Portal::Config $self = shift;
    my $box = shift;

    my $sortorder = $box->sortorder;

    return undef if ($sortorder >= $self->max_sortorder($box->col));

    my $boxes = $self->get_boxes;

    # get the boxes in this column sorted by sortorder then
    # iterate through the boxes until we find the first one that
    # has a greater sortorder
    my @colboxes = $self->get_col_boxes($box->col); # returns sorted by sortorder
    foreach my $pbox (@colboxes) {
        next unless $pbox;
        return $pbox if ($pbox->sortorder > $sortorder);
    }

    return undef;
}

sub prev_box {
    my LJ::Portal::Config $self = shift;
    my $box = shift;

    my $sortorder = $box->sortorder;

    return undef if ($sortorder <= $self->min_sortorder($box->col));

    my $boxes = $self->get_boxes;

    # see next_box
    my @colboxes = reverse $self->get_col_boxes($box->col); # returns sorted by sortorder
    foreach my $pbox (@colboxes) {
        next unless $pbox;
        return $pbox if ($pbox->sortorder < $sortorder);
    }

    return undef;
}

# returns what position in a column a box is in (not the same as sortorder)
sub col_order {
    my LJ::Portal::Config $self = shift;
    my $box = shift;

    my $boxes = $self->get_boxes;

    my @colboxes = $self->get_col_boxes($box->col); # returns sorted by sortorder
    my $colorder = 1;
    foreach my $cbox (@colboxes) {
        last if ($cbox->pboxid == $box->pboxid);
        $colorder++;
    }
    return $colorder;
}

sub find_box_by_col_order {
    my LJ::Portal::Config $self = shift;
    my ($col, $order) = @_;
    my $boxes = $self->get_boxes;

    my @colboxes = $self->get_col_boxes($col); # returns sorted by sortorder
    foreach my $box (@colboxes) {
        return $box if ($self->col_order($box) == $order);
    }

    return undef;
}

sub get_col_boxes {
    my LJ::Portal::Config $self = shift;
    my $col = shift;

    my $boxes = $self->get_boxes;

    # courtesy b-wizzle
    return grep { $_->col eq $col }
           map  { $boxes->{$_} }
           sort { $boxes->{$a}->sortorder <=> $boxes->{$b}->sortorder ||
                  $boxes->{$a}->pboxid    <=> $boxes->{$b}->pboxid }
           keys %$boxes;
}

# return all of the columns that have boxes
# ex. return value: ('R', 'L')
sub get_cols {
    my LJ::Portal::Config $self = shift;

    my $boxes = $self->get_boxes;
    my %cols;

    foreach my $boxkey (keys %$boxes) {
        my $col = $boxes->{$boxkey}->col;
        if (!$cols{$col}) {
            $cols{$col} = 1;
        }
    }

    return keys %cols;
}

# find a box based on col, sortorder
sub find_box {
    my LJ::Portal::Config $self = shift;
    my ($col, $sortorder) = @_;

    return undef unless $col && defined $sortorder;

    my $boxes = $self->get_boxes;

    my @colboxes = $self->get_col_boxes($col);
    foreach my $box (@colboxes) {
        next unless ($box);
        return $box if ($box->sortorder == $sortorder);
    }
    return undef;
}

# remove a box (id or object)
sub remove_box {
    my LJ::Portal::Config $self = shift;
    my $delbox = shift;

    # if delbox is an id then get the box, otherwise it should be
    # a box object
    my $box = int($delbox) ? $self->{'boxes'}->{$delbox} : $delbox;
    return unless $box;

    my $pboxid = $box->pboxid;
    my $userid = $self->{'u'}->{'userid'};
    return unless $pboxid && $userid;

    delete $self->{'boxes'}->{$box->{'pboxid'}};

    # update memcache state:
    delete $self->{'boxlist'}->{$box->{'pboxid'}};
    $self->update_memcache_state;

    # tell box to clean itself up and self-destruct
    $box->delete;
}

sub type_string_to_id {
    my LJ::Portal::Config $self = shift;
    my $typestring = shift;

    if (!$LJ::PORTAL_TYPEMAP{$typestring}) {
        LJ::Portal->load_box_typeid($typestring);
    }

    my $typeid = $LJ::PORTAL_TYPEMAP{$typestring} || undef;
    die "Invalid box type $typestring\n" unless $typeid;
    return $typeid;
}

sub type_id_to_string {
    my LJ::Portal::Config $self = shift;
    my $typeid = shift;

    foreach my $typestring ($self->get_box_classes) {
        if (!$LJ::PORTAL_TYPEMAP{$typestring}) {
            LJ::Portal->load_box_typeid($typestring);
        }

        if ($LJ::PORTAL_TYPEMAP{$typestring} == $typeid) {
            return $typestring;
        }
    }

    # box could not be mapped, die silently
    return undef;
}

# look to see if there are any boxes of this class instantiated and return
# the first match if there is one
sub find_box_by_class {
    my LJ::Portal::Config $self = shift;
    my $class = shift;

    my $boxes = $self->get_boxes;

    foreach my $box (keys %$boxes) {
        return $box if ($boxes->{$box}->box_class eq $class);
    }

    return undef;
}

sub min_sortorder {
    my LJ::Portal::Config $self = shift;
    my $col = shift;

    my $boxes = $self->get_boxes;

    my @colboxes = $self->get_col_boxes($col);

    my $minsort = $self->max_sortorder($col);
    foreach my $box (@colboxes) {
        next unless $box;
        $minsort = $box->sortorder if ($box->sortorder < $minsort);
    }

    return $minsort;
}

sub max_sortorder {
    my LJ::Portal::Config $self = shift;
    my $col = shift;

    my $boxes = $self->get_boxes;

    my @colboxes = $self->get_col_boxes($col);
    my $maxsort = 0;
    foreach my $box (@colboxes) {
        next unless $box;
        $maxsort = $box->sortorder if ($box->sortorder > $maxsort);
    }

    return $maxsort;
}

sub last_box {
    my LJ::Portal::Config $self = shift;
    my $col = shift;

    my $lastsort = $self->max_sortorder($col);
    return $self->find_box($col, $lastsort);
}

sub generate_box_with_container {
    my LJ::Portal::Config $self = shift;
    my $boxid = shift;

    my $box = $self->{'boxes'}->{$boxid};
    return unless $box;

    my $pboxid = $box->pboxid;
    my $boxinsides = $self->generate_box_insides($pboxid);

    return qq{
            <div class="PortalBox" id="pbox$pboxid" pboxid="$pboxid">
              $boxinsides
            </div>
        };
}

sub generate_box_titlebar {
    my LJ::Portal::Config $self = shift;
    my $box = shift;

    my $boxhtml = "";
    my $pboxid = $box->{'pboxid'};
    my $post_url = "$LJ::SITEROOT/portal/index.bml";
    my $boxtitle = $box->box_name;
    my $col = $box->col;
    my $colorder = $self->col_order($box);

    my $sort = $box->sortorder;
    my $maxsort = $self->max_sortorder($col);
    my $minsort = $self->min_sortorder($col);

    my $editable;

    if ($box->can('config_props')) {
        my $props = $box->config_props;
        $editable = grep { $props->{$_}->{type} ne 'hidden' } keys %$props;
    }

    # is there an icon for this box?
    my $moduleicon = $box->box_icon;

    my $closebutton = qq {
        <a onclick="return deletePortalBox($pboxid);" href="$post_url?delbox=1&pboxid=$pboxid">
            <img src="$LJ::IMGPREFIX/portal/PortalBoxClose.gif" title="Remove this module" />
            </a>
        };

    my $refreshbutton = '';

    if ($box->can('can_refresh') && $box->can_refresh) {
        $refreshbutton = qq {
            <a onclick="return reloadPortalBox($pboxid);" href="">
                <img src="$LJ::IMGPREFIX/portal/PortalBoxRefresh.gif" title="Reload the contents of this module" id='refresh$pboxid' />
            </a>
        };
    }

    my $configlink;

    if ($editable) {
        $configlink = qq {
            <a onclick="return showConfigPortalBox($pboxid);" href="$post_url?configbox=1&pboxid=$pboxid">
                <img src="$LJ::IMGPREFIX/portal/PortalBoxConfig.gif" title="Edit this module"
                id = 'edit$pboxid' />
            </a>
        };
    }

    # buttons to move box around
    my $moveBoxButtons = '';

    my $leftcol = '';
    if ($col eq 'R') {
        $leftcol = 'L';
    }
    my $rightcol = '';
    if ($col eq 'L') {
        $rightcol = 'R';
    }

    my $colpos = $self->col_order($box);

    if ($leftcol) {
        $moveBoxButtons .= qq{
            <a onclick="return movePortalBoxToCol($pboxid, '$leftcol', $colpos);" href="$post_url?movebox=1&pboxid=$pboxid&boxcol=$leftcol&boxcolpos=$colpos">
                <img src="$LJ::IMGPREFIX/portal/PortalBoxArrowLeft.gif" title="Move this module left" class="toolbutton" />
            </a>
        };
    }
    if ($rightcol) {
        $moveBoxButtons .= qq{
            <a onclick="return movePortalBoxToCol($pboxid, '$rightcol', $colpos);" href="$post_url?movebox=1&pboxid=$pboxid&boxcol=$rightcol&boxcolpos=$colpos">
                <img src="$LJ::IMGPREFIX/portal/PortalBoxArrowRight.gif" title="Move this module right" class="toolbutton" />
            </a>
        };
    }

    if (!($sort <= $minsort)) {
        $moveBoxButtons .= qq{
            <a onclick="return movePortalBoxUp($pboxid);" href="$post_url?movebox=1&pboxid=$pboxid&up=1">
                <img src="$LJ::IMGPREFIX/portal/PortalBoxArrowUp.gif" title="Move this module up" class="toolbutton" />
            </a>
        }
    }

    if (!($sort >= $maxsort)) {
        $moveBoxButtons .= qq{
            <a onclick="return movePortalBoxDown($pboxid);" href="$post_url?movebox=1&pboxid=$pboxid&down=1">
                <img src="$LJ::IMGPREFIX/portal/PortalBoxArrowDown.gif" title="Move this module down" class="toolbutton" />
            </a>
        }
    }

    my $titlebarhtml = qq {
            $moduleicon<span class="PortalBoxTitleText">$boxtitle</span>
            <span class="PortalBoxMoveButtons" id="PortalBoxMoveButtons$pboxid">$closebutton $refreshbutton $moveBoxButtons $configlink</span>
        };

    return $titlebarhtml;
}

# args: boxid, force?
# force: don't use cached box contents
sub generate_box_insides {
    my LJ::Portal::Config $self = shift;
    my $boxid = shift;
    my $force = shift;

    $force ||= 0;

    my $box = $self->{'boxes'}->{$boxid};
    return 'Could not find box.' unless $box;

    my $sort = $box->sortorder;
    my $boxclass = $box->can('box_class') ? $box->box_class : '';
    my $titlebar = $self->generate_box_titlebar($box);
    my $content;

    # don't let the box do anything if it's disabled
    if ($box->box_is_disabled) {
        $content = 'Sorry, this feature is disabled at this time.';
    }

    my $passback;

    if ($LJ::PORTAL_BOX_PROFILE_START) {
        $passback = $LJ::PORTAL_BOX_PROFILE_START->($box);
    }

    my $gencont = sub {
        my $usecache = shift;
        $usecache ||= 0;
        if (!$content) {
            $content = $self->get_box_cached_contents($box) if $usecache;
            $content = $box->generate_content if !$content;
        }
    };

    if ($LJ::IS_DEV_SERVER && $self->{'profile'}) {
        eval "use Benchmark ':hireswallclock';";

        return if $LJ::PORTAL_PROFILED_BOX{$boxclass};

        my $runtime = Benchmark::timeit($self->{'profile'}, $gencont);
        $LJ::PORTAL_DEBUG_CONTENT .= sprintf("%20s%40s", $boxclass, ": " .
                                             Benchmark::timestr($runtime) . "\n");

        $LJ::PORTAL_PROFILED_BOX{$boxclass} = 1;
    } else {
        $gencont->(!$force);
    }

    if ($LJ::PORTAL_BOX_PROFILE_END) {
        $LJ::PORTAL_BOX_PROFILE_END->($passback);
    }

    my $ret = qq{
        <div class="PortalBoxTitleBar" id="pboxtitlebar$boxid">
            $titlebar
        </div>
        <div class="PortalBoxContent $boxclass">
            $content
        </div>
        };

    return $ret;
}

sub get_box_cached_contents {
    my ($self, $box) = @_;

    # is this box supposed to be memcached?
    return undef unless ($box->can('cache_global'));

    my $content;

    my $memcachekey = $box->contents_memcache_key;

    # firstly, check if there is a cache in memory
    my $box_cached = LJ::MemCache::get($memcachekey);

    my $time = time();

    my $etag = $box->can('etag') ? $box->etag : 1;

    # are the contents of this box cached?
    if ($box_cached) {
        my $boxcontent_cached;
        my $etag_cached;
        ($etag_cached, $time, $boxcontent_cached) = @$box_cached;

        # is it time to check to see if this content has been modified?
        if (time() > $time) {
            # compare etags. if they don't match, regenerate contents
            if ($box->can('etag') && $etag && $box->etag == $etag_cached && $boxcontent_cached) {
                $content = $boxcontent_cached;
            }

            # reset time
            $time = time() + $box->cache_time if $box->can('cache_time');
        } else {
            $content = $boxcontent_cached ? $boxcontent_cached : undef;
        }
    }

    # update memcache
    $content = $box->generate_content if !$content;
    LJ::MemCache::set($memcachekey, [$etag, $time, $content]);

    return $content;
}

1;
