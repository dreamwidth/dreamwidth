#!/usr/bin/perl
#

package LJ::S2;

use strict;
use lib "$LJ::HOME/src/s2";
use S2;
use S2::Color;
use Class::Autouse qw(
                      S2::Checker
                      S2::Compiler
                      HTMLCleaner
                      LJ::CSS::Cleaner
                      LJ::S2::RecentPage
                      LJ::S2::YearPage
                      LJ::S2::DayPage
                      LJ::S2::FriendsPage
                      LJ::S2::MonthPage
                      LJ::S2::EntryPage
                      LJ::S2::ReplyPage
                      LJ::S2::TagsPage
                      LJ::LastFM
                      );
use Storable;
use Apache2::Const qw/ :common /;
use POSIX ();

# TEMP HACK
sub get_s2_reader {
    return LJ::get_dbh("s2slave", "slave", "master");
}

sub make_journal
{
    my ($u, $styleid, $view, $remote, $opts) = @_;

    my $r = $opts->{'r'};
    my $ret;
    $LJ::S2::ret_ref = \$ret;

    my ( $entry, $page, $use_modtime );

    if ($view eq "res") {

        # the s1shortcomings virtual styleid doesn't have a styleid
        # so we're making the rule that it can't have resource URLs.
        if ($styleid eq "s1short") {
            $opts->{'handler_return'} = 404;
            return;
        }

        if ($opts->{'pathextra'} =~ m!/(\d+)/stylesheet$!) {
            $styleid = $1;
            $entry = "print_stylesheet()";
            $opts->{'contenttype'} = 'text/css';
            $use_modtime = 1;
        } else {
            $opts->{'handler_return'} = 404;
            return;
        }
    }

    $u->{'_s2styleid'} = $styleid + 0;

    # try to get an S2 context
    my $ctx = s2_context( $styleid, use_modtime => $use_modtime, u => $u, style_u => $opts->{style_u} );
    unless ($ctx) {
        $opts->{'handler_return'} = OK;
        return;
    }

    my $lang = 'en';
    LJ::run_hook('set_s2bml_lang', $ctx, \$lang);

    # note that's it's very important to pass LJ::Lang::get_text here explicitly
    # rather than relying on BML::set_language's fallback mechanism, which won't
    # work in this context since BML::cur_req won't be loaded if no BML requests
    # have been served from this Apache process yet
    BML::set_language($lang, \&LJ::Lang::get_text);

    # let layouts disable EntryPage / ReplyPage, using the BML version
    # instead.
    unless ($styleid eq "s1short") {
        if ( ! $ctx->[S2::PROPS]->{use_journalstyle_entry_page} && ( $view eq "entry" || $view eq "reply" ) ) {
            ${$opts->{'handle_with_bml_ref'}} = 1;
            return;
        }

        # make sure capability supports it
        if (($view eq "entry" || $view eq "reply") &&
            ! LJ::get_cap(($opts->{'checkremote'} ? $remote : $u), "s2view$view")) {
            ${$opts->{'handle_with_bml_ref'}} = 1;
            return;
        }
    }

    # setup tags backwards compatibility
    unless ($ctx->[S2::PROPS]->{'tags_aware'}) {
        $opts->{enable_tags_compatibility} = 1;
    }

    $opts->{'ctx'} = $ctx;
    $LJ::S2::CURR_CTX = $ctx;

    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    $u->{'_journalbase'} = LJ::journal_base($u->{'user'}, $opts->{'vhost'});

    my $view2class = {
        lastn    => "RecentPage",
        calendar => "YearPage",
        day      => "DayPage",
        read     => "FriendsPage",
        month    => "MonthPage",
        reply    => "ReplyPage",
        entry    => "EntryPage",
        tag      => "TagsPage",
        network  => "FriendsPage",
    };

    if (my $class = $view2class->{$view}) {
        $entry = "${class}::print()";
        no strict 'refs';
        # this will fail (bogus method), but in non-apache context will bring
        # in the right file because of Class::Autouse above
        eval { "LJ::S2::$class"->force_class_autouse; };
        my $cv = *{"LJ::S2::$class"}{CODE};
        die "No LJ::S2::$class function!" unless $cv;
        $page = $cv->($u, $remote, $opts);
    }

    return if $opts->{'suspendeduser'};
    return if $opts->{'handler_return'};

    # the friends mode=live returns raw HTML in $page, in which case there's
    # nothing to "run" with s2_run.  so $page isn't runnable, return it now.
    # but we have to make sure it's defined at all first, otherwise things
    # like print_stylesheet() won't run, which don't have an method invocant
    return $page if $page && ref $page ne 'HASH';

    # Include any head stc or js head content
    LJ::run_hooks("need_res_for_journals", $u);
    my $extra_js = LJ::statusvis_message_js($u);
    $page->{head_content} .= LJ::res_includes() . $extra_js;

    s2_run($r, $ctx, $opts, $entry, $page);

    if (ref $opts->{'errors'} eq "ARRAY" && @{$opts->{'errors'}}) {
        return join('',
                    "Errors occurred processing this page:<ul>",
                    map { "<li>$_</li>" } @{$opts->{'errors'}},
                    "</ul>");
    }

    # unload layers that aren't public
    LJ::S2::cleanup_layers($ctx);

    # If there's an entry for contenttype in the context 'scratch'
    # area, copy it into the "real" content type field.
    $opts->{contenttype} = $ctx->[S2::SCRATCH]->{contenttype}
        if defined $ctx->[S2::SCRATCH]->{contenttype};

    $ret = $page->{'LJ_cmtinfo'} . $ret if $opts->{'need_cmtinfo'} and defined $page->{'LJ_cmtinfo'};

    return $ret;
}

sub s2_run
{
    my ($r, $ctx, $opts, $entry, $page) = @_;
    $opts ||= {};

    local $LJ::S2::CURR_CTX  = $ctx;
    my $ctype = $opts->{'contenttype'} || "text/html";
    my $cleaner;

    my $cleaner_output = sub {
        my $text = shift;

        # expand lj-embed tags
        if ($text =~ /lj\-embed/i) {
            # find out what journal we're looking at
            my $r = eval { BML::get_request() };
            if ($r && $r->notes->{journalid}) {
                my $journal = LJ::load_userid($r->notes->{journalid});
                # expand tags
                LJ::EmbedModule->expand_entry($journal, \$text)
                    if $journal;
            }
        }

        $$LJ::S2::ret_ref .= $text;
    };

    if ($ctype =~ m!^text/html!) {
        $cleaner = HTMLCleaner->new(
                                    'output' => $cleaner_output,
                                    'valid_stylesheet' => \&LJ::valid_stylesheet_url,
                                    );
    }

    my $send_header = sub {
        my $status = $ctx->[S2::SCRATCH]->{'status'} || 200;
        $r->status($status);
        $r->content_type($ctx->[S2::SCRATCH]->{'ctype'} || $ctype);
        # FIXME: not necessary in ModPerl 2.0?
        #$r->send_http_header();
    };

    my $need_flush;

    my $print_ctr = 0;  # every 'n' prints we check the recursion depth

    my $out_straight = sub {
        # Hacky: forces text flush.  see:
        # http://zilla.livejournal.org/906
        if ($need_flush) {
            $cleaner->parse("<!-- -->");
            $need_flush = 0;
        }
        $$LJ::S2::ret_ref .= $_[0];
        S2::check_depth() if ++$print_ctr % 8 == 0;
    };
    my $out_clean = sub {
        my $text = shift;

        $cleaner->parse($text);

        $need_flush = 1;
        S2::check_depth() if ++$print_ctr % 8 == 0;
    };
    S2::set_output($out_straight);
    S2::set_output_safe($cleaner ? $out_clean : $out_straight);

    $LJ::S2::CURR_PAGE = $page;
    $LJ::S2::RES_MADE = 0;  # standard resources (Image objects) made yet

    my $css_mode = $ctype eq "text/css";

    S2::Builtin::LJ::start_css($ctx) if $css_mode;
    eval {
        S2::run_code($ctx, $entry, $page);
    };
    S2::Builtin::LJ::end_css($ctx) if $css_mode;

    $LJ::S2::CURR_PAGE = undef;

    if ($@) {
        my $error = $@;
        $error =~ s/\n/<br \/>\n/g;
        S2::pout("<b>Error running style:</b> $error");
        return 0;
    }
    $cleaner->eof if $cleaner;  # flush any remaining text/tag not yet spit out
    return 1;
}

# <LJFUNC>
# name: LJ::S2::get_tags_text
# class: s2
# des: Gets text for display in entry for tags compatibility.
# args: ctx, taglistref
# des-ctx: Current S2 context
# des-taglistref: Arrayref containing "Tag" S2 objects
# returns: String; can be appended to entry... undef on error (no context, no taglistref)
# </LJFUNC>
sub get_tags_text {
    my ($ctx, $taglist) = @_;
    return undef unless $ctx && $taglist;
    return "" unless @$taglist;

    # now get the customized tag text and insert the tag list and append to body
    my $tags = join(', ', map { "<a rel='tag' href='$_->{url}'>$_->{name}</a>" } @$taglist);
    my $tagtext = S2::get_property_value($ctx, 'text_tags');
    $tagtext =~ s/#/$tags/;
    return "<div class='ljtags'>$tagtext</div>";
}

# returns hashref { lid => $u }; undef on error
sub get_layer_owners {
    my @lids = map { $_ + 0 } @_;
    return {} unless @lids;

    my $ret = {}; # lid => uid/$u
    my %need = ( map { $_ => 1 } @lids ); # layerid => 1

    # see what we can get out of memcache first
    my @keys;
    push @keys, [ $_, "s2lo:$_" ] foreach @lids;
    my $memc = LJ::MemCache::get_multi(@keys);
    foreach my $lid (@lids) {
        if (my $uid = $memc->{"s2lo:$lid"}) {
            delete $need{$lid};
            $ret->{$lid} = $uid;
        }
    }

    # if we still need any from the database, get them now
    if (%need) {
        my $dbh = LJ::get_db_writer();
        my $in = join(',', keys %need);
        my $res = $dbh->selectall_arrayref("SELECT s2lid, userid FROM s2layers WHERE s2lid IN ($in)");
        die "Database error in LJ::S2::get_layer_owners: " . $dbh->errstr . "\n" if $dbh->err;

        foreach my $row (@$res) {
            # save info and add to memcache
            $ret->{$row->[0]} = $row->[1];
            LJ::MemCache::add([ $row->[0], "s2lo:$row->[0]" ], $row->[1]);
        }
    }

    # now load these users; they're likely process cached anyway, so it should
    # be pretty fast
    my $us = LJ::load_userids(values %$ret);
    foreach my $lid (keys %$ret) {
        $ret->{$lid} = $us->{$ret->{$lid}}
    }
    return $ret;
}

# returns max comptime of all lids requested to be loaded
sub load_layers {
    my @lids = map { $_ + 0 } @_;
    return 0 unless @lids;

    my $maxtime = 0;  # to be returned

    # figure out what is process cached...that goes to DB always
    # if it's not in process cache, hit memcache first
    my @from_db;   # lid, lid, lid, ...
    my @need_memc; # lid, lid, lid, ...

    # initial sweep, anything loaded for less than 60 seconds is golden
    # if dev server, only cache layers for 1 second
    foreach my $lid (@lids) {
        if (my $loaded = S2::layer_loaded($lid, $LJ::IS_DEV_SERVER ? 1 : 60)) {
            # it's loaded and not more than 60 seconds load, so we just go
            # with it and assume it's good... if it's been recompiled, we'll
            # figure it out within the next 60 seconds
            $maxtime = $loaded if $loaded > $maxtime;
        } else {
            push @need_memc, $lid;
        }
    }

    # attempt to get things in @need_memc from memcache
    my $memc = LJ::MemCache::get_multi(map { [ $_, "s2c:$_"] } @need_memc);
    foreach my $lid (@need_memc) {
        if (my $row = $memc->{"s2c:$lid"}) {
            # load the layer from memcache; memcache data should always be correct
            my ($updtime, $data) = @$row;
            if ($data) {
                $maxtime = $updtime if $updtime > $maxtime;
                S2::load_layer($lid, $data, $updtime);
            }
        } else {
            # make it exist, but mark it 0
            push @from_db, $lid;
        }
    }

    # it's possible we don't need to hit the database for anything
    return $maxtime unless @from_db;

    # figure out who owns what we need
    my $us = LJ::S2::get_layer_owners(@from_db);
    my $sysid = LJ::get_userid('system');

    # break it down by cluster
    my %bycluster; # cluster => [ lid, lid, ... ]
    foreach my $lid (@from_db) {
        next unless $us->{$lid};
        if ($us->{$lid}->{userid} == $sysid) {
            push @{$bycluster{0} ||= []}, $lid;
        } else {
            push @{$bycluster{$us->{$lid}->{clusterid}} ||= []}, $lid;
        }
    }

    # big loop by cluster
    foreach my $cid (keys %bycluster) {
        # if we're talking about cluster 0, the global, pass it off to the old
        # function which already knows how to handle that
        unless ($cid) {
            my $dbr = LJ::S2::get_s2_reader();
            S2::load_layers_from_db($dbr, @{$bycluster{$cid}});
            next;
        }

        my $db = LJ::get_cluster_master($cid);
        die "Unable to obtain handle to cluster $cid for LJ::S2::load_layers\n"
            unless $db;

        # create SQL to load the layers we want
        my $where = join(' OR ', map { "(userid=$us->{$_}->{userid} AND s2lid=$_)" } @{$bycluster{$cid}});
        my $sth = $db->prepare("SELECT s2lid, compdata, comptime FROM s2compiled2 WHERE $where");
        $sth->execute;

        # iterate over data, memcaching as we go
        while (my ($id, $comp, $comptime) = $sth->fetchrow_array) {
            LJ::text_uncompress(\$comp);
            LJ::MemCache::set([ $id, "s2c:$id" ], [ $comptime, $comp ])
                if length $comp <= $LJ::MAX_S2COMPILED_CACHE_SIZE;
            S2::load_layer($id, $comp, $comptime);
            $maxtime = $comptime if $comptime > $maxtime;
        }
    }

    # now we have to go through everything again and verify they're all loaded and
    # otherwise do a fallback to the global
    my @to_load;
    foreach my $lid (@from_db) {
        next if S2::layer_loaded($lid);

        unless ($us->{$lid}) {
            print STDERR "Style $lid has no available owner.\n" if $LJ::DEBUG{"s2style_load"};
            next;
        }

        if ($us->{$lid}->{userid} == $sysid) {
            print STDERR "Style $lid is owned by system but failed load from global.\n" if $LJ::DEBUG{"s2style_load"};
            next;
        }

        if ($LJ::S2COMPILED_MIGRATION_DONE) {
            LJ::MemCache::set([ $lid, "s2c:$lid" ], [ time(), 0 ]);
            next;
        }

        push @to_load, $lid;
    }
    return $maxtime unless @to_load;

    # get the dbh and start loading these
    my $dbr = LJ::S2::get_s2_reader();
    die "Failure getting S2 database handle in LJ::S2::load_layers\n"
        unless $dbr;

    my $where = join(' OR ', map { "s2lid=$_" } @to_load);
    my $sth = $dbr->prepare("SELECT s2lid, compdata, comptime FROM s2compiled WHERE $where");
    $sth->execute;
    while (my ($id, $comp, $comptime) = $sth->fetchrow_array) {
        S2::load_layer($id, $comp, $comptime);
        $maxtime = $comptime if $comptime > $maxtime;
    }
    return $maxtime;
}

# find existing re-distributed layers that are in the database
# and their styleids.
sub get_public_layers
{
    my $opts = ref $_[0] eq 'HASH' ? shift : {};
    my $sysid = shift;  # optional system userid (usually not used)

    unless ($opts->{force}) {
        $LJ::CACHED_PUBLIC_LAYERS ||= LJ::MemCache::get("s2publayers");
        return $LJ::CACHED_PUBLIC_LAYERS if $LJ::CACHED_PUBLIC_LAYERS;
    }

    $sysid ||= LJ::get_userid("system");
    my $layers = get_layers_of_user($sysid, "is_system", [qw(des note author author_name author_email)]);

    $LJ::CACHED_PUBLIC_LAYERS = $layers if $layers;
    LJ::MemCache::set("s2publayers", $layers, 60*10) if $layers;
    return $LJ::CACHED_PUBLIC_LAYERS;
}

# update layers whose b2lids have been remapped to new s2lids
sub b2lid_remap
{
    my ($uuserid, $s2lid, $b2lid) = @_;
    my $b2lid_new = $LJ::S2LID_REMAP{$b2lid};
    return undef unless $uuserid && $s2lid && $b2lid && $b2lid_new;

    my $sysid = LJ::get_userid("system");
    return undef unless $sysid;

    LJ::statushistory_add($uuserid, $sysid, 'b2lid_remap', "$s2lid: $b2lid=>$b2lid_new");

    my $dbh = LJ::get_db_writer();
    return $dbh->do("UPDATE s2layers SET b2lid=? WHERE s2lid=?",
                    undef, $b2lid_new, $s2lid);
}

sub get_layers_of_user
{
    my ($u, $is_system, $infokeys) = @_;
    
    my $subst_user = LJ::run_hook("substitute_s2_layers_user", $u);
    if (defined $subst_user && LJ::isu($subst_user)) {
        $u = $subst_user;
    }
    
    my $userid = LJ::want_userid($u);
    return undef unless $userid;
    undef $u unless LJ::isu($u);

    return $u->{'_s2layers'} if $u && $u->{'_s2layers'};

    my %layers;    # id -> {hashref}, uniq -> {same hashref}
    my $dbr = LJ::S2::get_s2_reader();

    my $extrainfo = $is_system ? "'redist_uniq', " : "";
    $extrainfo .= join(', ', map { $dbr->quote($_) } @$infokeys).", " if $infokeys;

    my $sth = $dbr->prepare("SELECT i.infokey, i.value, l.s2lid, l.b2lid, l.type ".
                            "FROM s2layers l, s2info i ".
                            "WHERE l.userid=? AND l.s2lid=i.s2lid AND ".
                            "i.infokey IN ($extrainfo 'type', 'name', 'langcode', ".
                            "'majorversion', '_previews')");
    $sth->execute($userid);
    die $dbr->errstr if $dbr->err;
    while (my ($key, $val, $id, $bid, $type) = $sth->fetchrow_array) {
        $layers{$id}->{'b2lid'} = $bid;
        $layers{$id}->{'s2lid'} = $id;
        $layers{$id}->{'type'} = $type;
        $key = "uniq" if $key eq "redist_uniq";
        $layers{$id}->{$key} = $val;
    }

    foreach (keys %layers) {
        # setup uniq alias.
        if ($layers{$_}->{'uniq'} ne "") {
            $layers{$layers{$_}->{'uniq'}} = $layers{$_};
        }

        # setup children keys
        my $bid = $layers{$_}->{b2lid};
        next unless $layers{$_}->{'b2lid'};

        # has the b2lid for this layer been remapped?
        # if so update this layer's specified b2lid
        if ($bid && $LJ::S2LID_REMAP{$bid}) {
            my $s2lid = $layers{$_}->{s2lid};
            b2lid_remap($userid, $s2lid, $bid);
            $layers{$_}->{b2lid} = $LJ::S2LID_REMAP{$bid};
        }

        if ($is_system) {
            my $bid = $layers{$_}->{'b2lid'};
            unless ($layers{$bid}) {
                delete $layers{$layers{$_}->{'uniq'}};
                delete $layers{$_};
                next;
            }
            push @{$layers{$bid}->{'children'}}, $_;
        }
    }

    if ($u) {
        $u->{'_s2layers'} = \%layers;
    }
    return \%layers;
}


# get_style:
#
# many calling conventions:
#    get_style($styleid, $verify)
#    get_style($u,       $verify)
#    get_style($styleid, $opts)
#    get_style($u,       $opts)
#
# opts may contain keys:
#   - 'u' -- $u object
#   - 'verify' --  if verify, the $u->{'s2_style'} key is deleted if style isn't found
#   - 'force_layers' -- if force_layers, then the style's layers are loaded from the database
sub get_style
{
    my ($arg, $opts) = @_;

    my $verify = 0;
    my $force_layers = 0;
    my ($styleid, $u);

    if (ref $opts eq "HASH") {
        $verify = $opts->{'verify'};
        $u = $opts->{'u'};
        $force_layers = $opts->{'force_layers'};
    } elsif ($opts) {
        $verify = 1;
        die "Bogus second arg to LJ::S2::get_style" if ref $opts;
    }

    if (ref $arg) {
        $u = $arg;
        $styleid = $u->prop('s2_style');
    } else {
        $styleid = $arg + 0;
    }

    my %style;
    my $have_style = 0;

    if ($verify && $styleid) {
        my $dbr = LJ::S2::get_s2_reader();
        my $style = $dbr->selectrow_hashref("SELECT * FROM s2styles WHERE styleid=$styleid");
        if (! $style && $u) {
            delete $u->{'s2_style'};
            $styleid = 0;
        }
    }

    if ($styleid) {
        my $stylay = $u ?
            LJ::S2::get_style_layers($u, $styleid, $force_layers) :
            LJ::S2::get_style_layers($styleid, $force_layers);
        while (my ($t, $id) = each %$stylay) { $style{$t} = $id; }
        $have_style = scalar %style;
    }

    # this is a hack to add remapping support for s2lids
    # - if a layerid is loaded above but it has a remapping
    #   defined in ljconfig, use the remap id instead and
    #   also save to database using set_style_layers
    if (%LJ::S2LID_REMAP) {
        my @remaps = ();

        # all system layer types (no user layers)
        foreach (qw(core i18nc i18n layout theme)) {
            my $lid = $style{$_};
            if (exists $LJ::S2LID_REMAP{$lid}) {
                $style{$_} = $LJ::S2LID_REMAP{$lid};
                push @remaps, "$lid=>$style{$_}";
            }
        }
        if (@remaps) {
            my $sysid = LJ::get_userid("system");
            LJ::statushistory_add($u, $sysid, 's2lid_remap', join(", ", @remaps));
            LJ::S2::set_style_layers($u, $styleid, %style);
        }
    }

    unless ($have_style) {
        my $public = get_public_layers();
        while (my ($layer, $name) = each %$LJ::DEFAULT_STYLE) {
            next unless $name ne "";
            next unless $public->{$name};
            my $id = $public->{$name}->{'s2lid'};
            $style{$layer} = $id if $id;
        }
    }

    return %style;
}

sub s2_context
{
    my ( $styleid, %opts ) = @_;

    # get arguments we'll use frequently
    my $r = DW::Request->get;
    my $u = $opts{u} || LJ::get_active_journal();
    my $style_u = $opts{style_u} || $u;

    # but it doesn't matter if we're using the minimal style ...
    my %style;
    eval {
        if ( $r->notes( 'use_minimal_scheme' ) ) {
            my $public = get_public_layers();
            while (my ($layer, $name) = each %LJ::MINIMAL_STYLE) {
                next unless $name ne "";
                next unless $public->{$name};
                my $id = $public->{$name}->{'s2lid'};
                $style{$layer} = $id if $id;
            }
        }
    };

    # styleid of "s1short" is special in that it makes a
    # dynamically-created s2 context
    if ($styleid eq "s1short") {
        %style = s1_shortcomings_style($u);
    }

    if (ref($styleid) eq "CODE") {
        %style = $styleid->();
    }

    # fall back to the standard call to get a user's styles
    unless (%style) {
        %style = $u ? get_style($styleid, { 'u' => $style_u }) : get_style($styleid);
    }

    my @layers;
    foreach (qw(core i18nc layout i18n theme user)) {
        push @layers, $style{$_} if $style{$_};
    }

    # TODO: memcache this.  only make core S2 (which uses the DB) load
    # when we can't get all the s2compiled stuff from memcache.
    # compare s2styles.modtime with s2compiled.comptime to see if memcache
    # version is accurate or not.
    my $dbr = LJ::S2::get_s2_reader();
    my $modtime = LJ::S2::load_layers(@layers);

    # check that all critical layers loaded okay from the database, otherwise
    # fall back to default style.  if i18n/theme/user were deleted, just proceed.
    my $okay = 1;
    foreach (qw(core layout)) {
        next unless $style{$_};
        $okay = 0 unless S2::layer_loaded($style{$_});
    }
    unless ($okay) {
        # load the default style instead, if we just tried to load a real one and failed
        return s2_context( 0, %opts )
            if $styleid;

        # were we trying to load the default style?
        $r->content_type( 'text/html' );
        $r->print( '<b>Error preparing to run:</b> One or more layers required to load the stock style have been deleted.' );
        return undef;
    }

    # if we are supposed to use modtime checking (i.e. for stylesheets) then go
    # ahead and do that logic now
    if ( $opts{use_modtime} ) {
        if ( $r->header_in( 'If-Modified-Since' ) eq LJ::time_to_http( $modtime )) {
            # 304 return; unload non-public layers
            LJ::S2::cleanup_layers(@layers);
            $r->status_line( '304 Not Modified' );
            return undef;
        } else {
            $r->set_last_modified( $modtime );
        }
    }

    my $ctx;
    eval {
        $ctx = S2::make_context(@layers);
    };

    if ($ctx) {
        # let's use the scratch field as a hashref
        $ctx->[S2::SCRATCH] ||= {};

        LJ::S2::populate_system_props($ctx);
        LJ::S2::alias_renamed_props( $ctx );
        S2::set_output(sub {});  # printing suppressed
        S2::set_output_safe(sub {});
        eval { S2::run_code($ctx, "prop_init()"); };
        escape_all_props($ctx, \@layers);

        return $ctx unless $@;
    }

    # failure to generate context; unload our non-public layers
    LJ::S2::cleanup_layers(@layers);
    $r->content_type( 'text/html' );
    $r->print( '<b>Error preparing to run:</b> ' . $@ );
    return undef;
}

sub escape_all_props {
    my ($ctx, $lids) = @_;

    foreach my $lid (@$lids) {
        foreach my $pname (S2::get_property_names($lid)) {
            next unless $ctx->[S2::PROPS]{$pname};

            my $prop = S2::get_property($lid, $pname);
            my $mode = $prop->{string_mode} || "plain";
            escape_prop_value($ctx->[S2::PROPS]{$pname}, $mode);
        }
    }
}

my $css_cleaner;
sub _css_cleaner {
    return $css_cleaner ||= LJ::CSS::Cleaner->new;
}

sub escape_prop_value {
    my $mode = $_[1];
    my $css_c = _css_cleaner();

    # This function modifies its first parameter in place.

    if (ref $_[0] eq 'ARRAY') {
        for (my $i = 0; $i < scalar(@{$_[0]}); $i++) {
            escape_prop_value($_[0][$i], $mode);
        }
    }
    elsif (ref $_[0] eq 'HASH') {
        foreach my $k (keys %{$_[0]}) {
            escape_prop_value($_[0]{$k}, $mode);
        }
    }
    elsif (! ref $_[0]) {
        if ($mode eq 'simple-html' || $mode eq 'simple-html-oneline') {
            LJ::CleanHTML::clean_subject(\$_[0]);
            $_[0] =~ s!\n!<br />!g if $mode eq 'simple-html';
        }
        elsif ($mode eq 'html' || $mode eq 'html-oneline') {
            LJ::CleanHTML::clean_event(\$_[0]);
            $_[0] =~ s!\n!<br />!g if $mode eq 'html';
        }
        elsif ($mode eq 'css') {
            my $clean = $css_c->clean($_[0]);
            LJ::run_hook('css_cleaner_transform', \$clean);
            $_[0] = $clean;
        }
        elsif ($mode eq 'css-attrib') {
            if ($_[0] =~ /[\{\}]/) {
                # If the string contains any { and } characters, it can't go in a style="" attrib
                $_[0] = "/* bad CSS: can't use braces in a style attribute */";
                return;
            }
            my $clean = $css_c->clean_property($_[0]);
            $_[0] = $clean;
        }
        else { # plain
            $_[0] =~ s/</&lt;/g;
            $_[0] =~ s/>/&gt;/g;
            $_[0] =~ s!\n!<br />!g;
        }
    }
    else {
        $_[0] = undef; # Something's gone very wrong. Zzap the value completely.
    }
}

sub s1_shortcomings_style {
    my $u = shift;
    my %style;

    my $public = get_public_layers();
    %style = (
              core => "core1",
              layout => "s1shortcomings/layout",
              );

    # convert the value names to s2layerid
    while (my ($layer, $name) = each %style) {
        next unless $public->{$name};
        my $id = $public->{$name}->{'s2lid'};
        $style{$layer} = $id;
    }

    return %style;
}

# parameter is either a single context, or just a bunch of layerids
# will then unregister the non-public layers
sub cleanup_layers {
    my $pub = get_public_layers();
    my @unload = ref $_[0] ? S2::get_layers($_[0]) : @_;
    S2::unregister_layer($_) foreach grep { ! $pub->{$_} } @unload;
}

sub clone_layer
{
    die "LJ::S2::clone_layer() has not been ported to use s2compiled2, but this function is not currently in use anywhere; if you use this function, please update it to use s2compiled2.\n";

    my $id = shift;
    return 0 unless $id;

    my $dbh = LJ::get_db_writer();
    my $r;

    $r = $dbh->selectrow_hashref("SELECT * FROM s2layers WHERE s2lid=?", undef, $id);
    return 0 unless $r;
    $dbh->do("INSERT INTO s2layers (b2lid, userid, type) VALUES (?,?,?)",
             undef, $r->{'b2lid'}, $r->{'userid'}, $r->{'type'});
    my $newid = $dbh->{'mysql_insertid'};
    return 0 unless $newid;

    foreach my $t (qw(s2compiled s2info s2source)) {
        if ($t eq "s2source") {
            $r = LJ::S2::load_layer_source_row($id);
        } else {
            $r = $dbh->selectrow_hashref("SELECT * FROM $t WHERE s2lid=?", undef, $id);
        }
        next unless $r;
        $r->{'s2lid'} = $newid;

        # kinda hacky:  we have to update the layer id
        if ($t eq "s2compiled") {
            $r->{'compdata'} =~ s/\$_LID = (\d+)/\$_LID = $newid/;
        }

        $dbh->do("INSERT INTO $t (" . join(',', keys %$r) . ") VALUES (".
                 join(',', map { $dbh->quote($_) } values %$r) . ")");
    }

    return $newid;
}

sub create_style
{
    my ($u, $name, $cloneid) = @_;

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    my $uid = $u->{userid} + 0
        or return 0;

    my $clone;
    $clone = load_style($cloneid) if $cloneid;

    # can't clone somebody else's style
    return 0 if $clone && $clone->{'userid'} != $uid;

    # can't create name-less style
    return 0 unless $name =~ /\S/;

    $dbh->do("INSERT INTO s2styles (userid, name, modtime) VALUES (?,?, UNIX_TIMESTAMP())",
             undef, $u->{'userid'}, $name);
    my $styleid = $dbh->{'mysql_insertid'};
    return 0 unless $styleid;

    if ($clone) {
        $clone->{'layer'}->{'user'} =
            LJ::clone_layer($clone->{'layer'}->{'user'});

        my $values;
        foreach my $ly ('core','i18nc','layout','theme','i18n','user') {
            next unless $clone->{'layer'}->{$ly};
            $values .= "," if $values;
            $values .= "($uid, $styleid, '$ly', $clone->{'layer'}->{$ly})";
        }
        $u->do("REPLACE INTO s2stylelayers2 (userid, styleid, type, s2lid) ".
               "VALUES $values") if $values;
    }

    return $styleid;
}

sub load_user_styles
{
    my $u = shift;
    my $opts = shift;
    return undef unless $u;

    my $dbr = LJ::S2::get_s2_reader();

    my %styles;
    my $load_using = sub {
        my $db = shift;
        my $sth = $db->prepare("SELECT styleid, name FROM s2styles WHERE userid=?");
        $sth->execute($u->{'userid'});
        while (my ($id, $name) = $sth->fetchrow_array) {
            $styles{$id} = $name;
        }
    };
    $load_using->($dbr);
    return \%styles if scalar(%styles) || ! $opts->{'create_default'};

    # create a new default one for them, but first check to see if they
    # have one on the master.
    my $dbh = LJ::get_db_writer();
    $load_using->($dbh);
    return \%styles if %styles;

    $dbh->do("INSERT INTO s2styles (userid, name, modtime) VALUES (?,?, UNIX_TIMESTAMP())", undef,
             $u->{'userid'}, $u->{'user'});
    my $styleid = $dbh->{'mysql_insertid'};
    return { $styleid => $u->{'user'} };
}

sub delete_user_style
{
    my ($u, $styleid) = @_;
    return 1 unless $styleid;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    foreach my $t (qw(s2styles s2stylelayers)) {
        $dbh->do("DELETE FROM $t WHERE styleid=?", undef, $styleid)
    }
    $u->do("DELETE FROM s2stylelayers2 WHERE userid=? AND styleid=?", undef,
           $u->{userid}, $styleid);

    LJ::MemCache::delete([$styleid, "s2s:$styleid"]);

    return 1;
}

sub rename_user_style
{
    my ($u, $styleid, $name) = @_;
    return 1 unless $styleid;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do("UPDATE s2styles SET name=? WHERE styleid=? AND userid=?", undef, $name, $styleid, $u->id);
    LJ::MemCache::delete([$styleid, "s2s:$styleid"]);

    return 1;
}

sub load_style
{
    my $db = ref $_[0] ? shift : undef;
    my $id = shift;
    return undef unless $id;
    my %opts = @_;

    my $memkey = [$id, "s2s:$id"];
    my $style = LJ::MemCache::get($memkey);
    unless ($style) {
        $db ||= LJ::S2::get_s2_reader()
            or die "Unable to get S2 reader";
        $style = $db->selectrow_hashref("SELECT styleid, userid, name, modtime ".
                                        "FROM s2styles WHERE styleid=?",
                                        undef, $id);
        die $db->errstr if $db->err;

        LJ::MemCache::add($memkey, $style, 3600);
    }
    return undef unless $style;

    unless ($opts{skip_layer_load}) {
        my $u = LJ::load_userid($style->{userid})
            or return undef;

        $style->{'layer'} = LJ::S2::get_style_layers($u, $id) || {};
    }

    return $style;
}

sub create_layer
{
    my ($userid, $b2lid, $type) = @_;
    $userid = LJ::want_userid($userid);

    return 0 unless $b2lid;  # caller should ensure b2lid exists and is of right type
    return 0 unless
        $type eq "user" || $type eq "i18n" || $type eq "theme" ||
        $type eq "layout" || $type eq "i18nc" || $type eq "core";

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do("INSERT INTO s2layers (b2lid, userid, type) ".
             "VALUES (?,?,?)", undef, $b2lid, $userid, $type);
    return $dbh->{'mysql_insertid'};
}

# takes optional $u as first argument... if user argument is specified, will
# look through s2stylelayers and delete all mappings that this user has to
# this particular layer.
sub delete_layer
{
    my $u = LJ::isu($_[0]) ? shift : undef;
    my $lid = shift;
    return 1 unless $lid;
    my $dbh = LJ::get_db_writer();
    foreach my $t (qw(s2layers s2compiled s2info s2source s2source_inno s2checker)) {
        $dbh->do("DELETE FROM $t WHERE s2lid=?", undef, $lid);
    }

    # make sure we have a user object if possible
    unless ($u) {
        my $us = LJ::S2::get_layer_owners($lid);
        $u = $us->{$lid} if $us->{$lid};
    }

    # delete s2compiled2 if this is a layer owned by someone other than system
    if ($u && $u->{user} ne 'system') {
        $u->do("DELETE FROM s2compiled2 WHERE userid = ? AND s2lid = ?",
               undef, $u->{userid}, $lid);
    }

    # now clear memcache of the compiled data
    LJ::MemCache::delete([ $lid, "s2c:$lid" ]);

    # now delete the mappings for this particular layer
    if ($u) {
        my $styles = LJ::S2::load_user_styles($u);
        my @ids = keys %{$styles || {}};
        if (@ids) {
            # map in the ids we got from the user's styles and clear layers referencing
            # this particular layer id
            my $in = join(',', map { $_ + 0 } @ids);
            $dbh->do("DELETE FROM s2stylelayers WHERE styleid IN ($in) AND s2lid = ?",
                     undef, $lid);

            $u->do("DELETE FROM s2stylelayers2 WHERE userid=? AND styleid IN ($in) AND s2lid = ?",
                   undef, $u->{userid}, $lid);

            # now clean memcache so this change is immediately visible
            LJ::MemCache::delete([ $_, "s2sl:$_" ]) foreach @ids;
        }
    }

    return 1;
}

sub get_style_layers
{
    my $u = LJ::isu($_[0]) ? shift : undef;
    my ($styleid, $force) = @_;
    return undef unless $styleid;

    # check memcache unless $force
    my $stylay = $force ? undef : $LJ::S2::REQ_CACHE_STYLE_ID{$styleid};
    return $stylay if $stylay;

    my $memkey = [$styleid, "s2sl:$styleid"];
    $stylay = LJ::MemCache::get($memkey) unless $force;
    if ($stylay) {
        $LJ::S2::REQ_CACHE_STYLE_ID{$styleid} = $stylay;
        return $stylay;
    }

    # if an option $u was passed as the first arg,
    # we won't load the userid... otherwise we have to
    unless ($u) {
        my $sty = LJ::S2::load_style($styleid) or
            die "couldn't load styleid $styleid";
        $u = LJ::load_userid($sty->{userid}) or
            die "couldn't load userid $sty->{userid} for styleid $styleid";
    }

    my %stylay;

    my $fetch = sub {
        my ($db, $qry, @args) = @_;

        my $sth = $db->prepare($qry);
        $sth->execute(@args);
        die "ERROR: " . $sth->errstr if $sth->err;
        while (my ($type, $s2lid) = $sth->fetchrow_array) {
            $stylay{$type} = $s2lid;
        }
        return 0 unless %stylay;
        return 1;
    };

    unless ($fetch->($u, "SELECT type, s2lid FROM s2stylelayers2 " .
                     "WHERE userid=? AND styleid=?", $u->{userid}, $styleid)) {
        my $dbh = LJ::get_db_writer();
        if ($fetch->($dbh, "SELECT type, s2lid FROM s2stylelayers WHERE styleid=?",
                     $styleid)) {
            LJ::S2::set_style_layers_raw($u, $styleid, %stylay);
        }
    }

    # set in memcache
    LJ::MemCache::set($memkey, \%stylay);
    $LJ::S2::REQ_CACHE_STYLE_ID{$styleid} = \%stylay;
    return \%stylay;
}

# the old interfaces.  handles merging with global database data if necessary.
sub set_style_layers
{
    my ($u, $styleid, %newlay) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    my @lay = ('core','i18nc','layout','theme','i18n','user');
    my %need = map { $_, 1 } @lay;
    delete $need{$_} foreach keys %newlay;
    if (%need) {
        # see if the needed layers are already on the user cluster
        my ($sth, $t, $lid);

        $sth = $u->prepare("SELECT type FROM s2stylelayers2 WHERE userid=? AND styleid=?");
        $sth->execute($u->{'userid'}, $styleid);
        while (($t) = $sth->fetchrow_array) {
            delete $need{$t};
        }

        # if we still don't have everything, see if they exist on the
        # global cluster, and we'll merge them into the %newlay being
        # posted, so they end up on the user cluster
        if (%need) {
            $sth = $dbh->prepare("SELECT type, s2lid FROM s2stylelayers WHERE styleid=?");
            $sth->execute($styleid);
            while (($t, $lid) = $sth->fetchrow_array) {
                $newlay{$t} = $lid;
            }
        }
    }

    set_style_layers_raw($u, $styleid, %newlay);
}

# just set in user cluster, not merging with global
sub set_style_layers_raw {
    my ($u, $styleid, %newlay) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    $u->do("REPLACE INTO s2stylelayers2 (userid,styleid,type,s2lid) VALUES ".
           join(",", map { sprintf("(%d,%d,%s,%d)", $u->{userid}, $styleid,
                                   $dbh->quote($_), $newlay{$_}) }
                keys %newlay));
    return 0 if $u->err;

    $dbh->do("UPDATE s2styles SET modtime=UNIX_TIMESTAMP() WHERE styleid=?",
             undef, $styleid);

    # delete memcache key
    LJ::MemCache::delete([$styleid, "s2sl:$styleid"]);
    LJ::MemCache::delete([$styleid, "s2s:$styleid"]);

    return 1;
}

sub load_layer
{
    my $db = ref $_[0] ? shift : LJ::S2::get_s2_reader();
    my $lid = shift;

    my $layerid = $LJ::S2::REQ_CACHE_LAYER_ID{$lid};
    return $layerid if $layerid;

    my $ret = $db->selectrow_hashref("SELECT s2lid, b2lid, userid, type ".
                                     "FROM s2layers WHERE s2lid=?", undef,
                                     $lid);
    die $db->errstr if $db->err;
    $LJ::S2::REQ_CACHE_LAYER_ID{$lid} = $ret;

    return $ret;
}

sub populate_system_props
{
    my $ctx = shift;
    $ctx->[S2::PROPS]->{'SITEROOT'} = $LJ::SITEROOT;
    $ctx->[S2::PROPS]->{'PALIMGROOT'} = $LJ::PALIMGROOT;
    $ctx->[S2::PROPS]->{'SITENAME'} = $LJ::SITENAME;
    $ctx->[S2::PROPS]->{'SITENAMESHORT'} = $LJ::SITENAMESHORT;
    $ctx->[S2::PROPS]->{'SITENAMEABBREV'} = $LJ::SITENAMEABBREV;
    $ctx->[S2::PROPS]->{'IMGDIR'} = $LJ::IMGPREFIX;
    $ctx->[S2::PROPS]->{'STATDIR'} = $LJ::STATPREFIX;
}

# renamed some props from core1 => core2. Make sure that S2 still handles these variables correctly when working with a core1 layer
sub alias_renamed_props
{
    my $ctx = shift;
    $ctx->[S2::PROPS]->{num_items_recent} = $ctx->[S2::PROPS]->{page_recent_items} 
        if exists $ctx->[S2::PROPS]->{page_recent_items};

    $ctx->[S2::PROPS]->{num_items_reading} = $ctx->[S2::PROPS]->{page_friends_items}
        if exists $ctx->[S2::PROPS]->{page_friends_items};
    
    $ctx->[S2::PROPS]->{reverse_sortorder_day} = $ctx->[S2::PROPS]->{page_day_sortorder} eq 'reverse' ? 1 : 0
        if exists $ctx->[S2::PROPS]->{page_day_sortorder};

    $ctx->[S2::PROPS]->{reverse_sortorder_year} = $ctx->[S2::PROPS]->{page_year_sortorder} eq 'reverse' ? 1 : 0
        if exists $ctx->[S2::PROPS]->{page_year_sortorder};
        
    $ctx->[S2::PROPS]->{use_journalstyle_entry_page} = ! $ctx->[S2::PROPS]->{view_entry_disabled}
        if exists $ctx->[S2::PROPS]->{view_entry_disabled};
}

sub layer_compile_user
{
    my ($layer, $overrides) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless ref $layer;
    return 0 unless $layer->{'s2lid'};
    return 1 unless ref $overrides;
    my $id = $layer->{'s2lid'};
    my $s2 = LJ::Lang::ml( 's2theme.autogenerated.warning' );
    $s2 .= "layerinfo \"type\" = \"user\";\n";
    $s2 .= "layerinfo \"name\" = \"Auto-generated Customizations\";\n";

    foreach my $name (keys %$overrides) {
        next if $name =~ /\W/;
        my $prop = $overrides->{$name}->[0];
        my $val = $overrides->{$name}->[1];
        if ($prop->{'type'} eq "int") {
            $val = int($val);
        } elsif ($prop->{'type'} eq "bool") {
            $val = $val ? "true" : "false";
        } else {
            $val =~ s/[\\\$\"]/\\$&/g;
            $val = "\"$val\"";
        }
        $s2 .= "set $name = $val;\n";
    }

    my $error;
    return 1 if LJ::S2::layer_compile($layer, \$error, { 's2ref' => \$s2 });
    return LJ::error($error);
}

sub layer_compile
{
    my ($layer, $err_ref, $opts) = @_;
    my $dbh = LJ::get_db_writer();

    my $lid;
    if (ref $layer eq "HASH") {
        $lid = $layer->{'s2lid'}+0;
    } else {
        $lid = $layer+0;
        $layer = LJ::S2::load_layer($dbh, $lid);
        unless ($layer) { $$err_ref = "Unable to load layer"; return 0; }
    }
    unless ($lid) { $$err_ref = "No layer ID specified."; return 0; }

    # get checker (cached, or via compiling) for parent layer
    my $checker = get_layer_checker($layer);
    unless ($checker) {
        $$err_ref = "Error compiling parent layer.";
        return undef;
    }

    # do our compile (quickly, since we probably have the cached checker)
    my $s2ref = $opts->{'s2ref'};
    unless ($s2ref) {
        my $s2 = LJ::S2::load_layer_source($lid);
        unless ($s2) { $$err_ref = "No source code to compile.";  return undef; }
        $s2ref = \$s2;
    }

    my $is_system = $layer->{'userid'} == LJ::get_userid("system");
    my $untrusted = ! $LJ::S2_TRUSTED{$layer->{'userid'}} && ! $is_system;

    # system writes go to global.  otherwise to user clusters.
    my $dbcm;
    if ($is_system) {
        $dbcm = $dbh;
    } else {
        my $u = LJ::load_userid($layer->{'userid'});
        $dbcm = $u;
    }

    unless ($dbcm) { $$err_ref = "Unable to get database handle"; return 0; }

    my $compiled;
    my $cplr = S2::Compiler->new({ 'checker' => $checker });
    eval {
        $cplr->compile_source({
            'type' => $layer->{'type'},
            'source' => $s2ref,
            'output' => \$compiled,
            'layerid' => $lid,
            'untrusted' => $untrusted,
            'builtinPackage' => "S2::Builtin::LJ",
        });
    };
    if ($@) { $$err_ref = "Compile error: $@"; return undef; }

    # save the source, since it at least compiles
    if ($opts->{'s2ref'}) {
        LJ::S2::set_layer_source($lid, $opts->{s2ref}) or return 0;
    }

    # save the checker object for later
    if ($layer->{'type'} eq "core" || $layer->{'type'} eq "layout") {
        $checker->cleanForFreeze();
        my $chk_frz = Storable::freeze($checker);
        LJ::text_compress(\$chk_frz);
        $dbh->do("REPLACE INTO s2checker (s2lid, checker) VALUES (?,?)", undef,
                 $lid, $chk_frz) or die "replace into s2checker (lid = $lid)";
    }

    # load the compiled layer to test it loads and then get layerinfo/etc from it
    S2::unregister_layer($lid);
    eval $compiled;
    if ($@) { $$err_ref = "Post-compilation error: $@"; return undef; }
    if ($opts->{'redist_uniq'}) {
        # used by update-db loader:
        my $redist_uniq = S2::get_layer_info($lid, "redist_uniq");
        die "redist_uniq value of '$redist_uniq' doesn't match $opts->{'redist_uniq'}\n"
            unless $redist_uniq eq $opts->{'redist_uniq'};
    }

    # put layerinfo into s2info
    my %info = S2::get_layer_info($lid);
    my $values;
    my $notin;
    foreach (keys %info) {
        $values .= "," if $values;
        $values .= sprintf("(%d, %s, %s)", $lid,
                           $dbh->quote($_), $dbh->quote($info{$_}));
        $notin .= "," if $notin;
        $notin .= $dbh->quote($_);
    }
    if ($values) {
        $dbh->do("REPLACE INTO s2info (s2lid, infokey, value) VALUES $values")
            or die "replace into s2info (values = $values)";
        $dbh->do("DELETE FROM s2info WHERE s2lid=? AND infokey NOT IN ($notin)", undef, $lid);
    }
    if ($opts->{'layerinfo'}) {
        ${$opts->{'layerinfo'}} = \%info;
    }

    # put compiled into database, with its ID number
    if ($is_system) {
        $dbh->do("REPLACE INTO s2compiled (s2lid, comptime, compdata) ".
                 "VALUES (?, UNIX_TIMESTAMP(), ?)", undef, $lid, $compiled) or die "replace into s2compiled (lid = $lid)";
    } else {
        my $gzipped = LJ::text_compress($compiled);
        $dbcm->do("REPLACE INTO s2compiled2 (userid, s2lid, comptime, compdata) ".
                  "VALUES (?, ?, UNIX_TIMESTAMP(), ?)", undef,
                  $layer->{'userid'}, $lid, $gzipped) or die "replace into s2compiled2 (lid = $lid)";

        # delete from memcache; we can't store since we don't know the exact comptime
        LJ::MemCache::delete([ $lid, "s2c:$lid" ]);
    }

    # caller might want the compiled source
    if (ref $opts->{'compiledref'} eq "SCALAR") {
        ${$opts->{'compiledref'}} = $compiled;
    }

    S2::unregister_layer($lid);
    return 1;
}

sub get_layer_checker
{
    my $lay = shift;
    my $err_ref = shift;
    return undef unless ref $lay eq "HASH";
    return S2::Checker->new() if $lay->{'type'} eq "core";
    my $parid = $lay->{'b2lid'}+0 or return undef;
    my $dbh = LJ::get_db_writer();

    my $get_cached = sub {
        my $frz = $dbh->selectrow_array("SELECT checker FROM s2checker WHERE s2lid=?",
                                        undef, $parid) or return undef;
        LJ::text_uncompress(\$frz);
        return Storable::thaw($frz); # can be undef, on failure
    };

    # the good path
    my $checker = $get_cached->();
    return $checker if $checker;

    # no cached checker (or bogus), so we have to [re]compile to get it
    my $parlay = LJ::S2::load_layer($dbh, $parid);
    return undef unless LJ::S2::layer_compile($parlay);
    return $get_cached->();
}

sub load_layer_info
{
    my ($outhash, $listref) = @_;
    return 0 unless ref $listref eq "ARRAY";
    return 1 unless @$listref;

    # check request cache
    my %layers_from_cache = ();
    foreach my $lid (@$listref) {
        my $layerinfo = $LJ::S2::REQ_CACHE_LAYER_INFO{$lid};
        if (keys %$layerinfo) {
            $layers_from_cache{$lid} = 1;
            foreach my $k (keys %$layerinfo) {
                $outhash->{$lid}->{$k} = $layerinfo->{$k};
            }
        }
    }

    # only return if we found all of the given layers in request cache
    if (keys %$outhash && (scalar @$listref == scalar keys %layers_from_cache)) {
        return 1;
    }

    # get all of the layers that weren't in request cache from the db
    my $in = join(',', map { $_+0 } grep { !$layers_from_cache{$_} } @$listref);
    my $dbr = LJ::S2::get_s2_reader();
    my $sth = $dbr->prepare("SELECT s2lid, infokey, value FROM s2info WHERE ".
                            "s2lid IN ($in)");
    $sth->execute;

    while (my ($id, $k, $v) = $sth->fetchrow_array) {
        $LJ::S2::REQ_CACHE_LAYER_INFO{$id}->{$k} = $v;
        $outhash->{$id}->{$k} = $v;
    }

    return 1;
}

sub set_layer_source
{
    my ($s2lid, $source_ref) = @_;

    my $dbh = LJ::get_db_writer();
    my $rv = $dbh->do("REPLACE INTO s2source_inno (s2lid, s2code) VALUES (?,?)",
                      undef, $s2lid, $$source_ref);
    die $dbh->errstr if $dbh->err;

    return $rv;
}

sub load_layer_source
{
    my $s2lid = shift;

    # s2source is the old global MyISAM table that contains s2 layer sources
    # s2source_inno is new global InnoDB table that contains new layer sources
    # -- lazy migration is done whenever an insert/delete happens

    my $dbh = LJ::get_db_writer();

    # first try InnoDB table
    my $s2source = $dbh->selectrow_array("SELECT s2code FROM s2source_inno WHERE s2lid=?", undef, $s2lid);
    return $s2source if $s2source;

    # fall back to MyISAM
    return $dbh->selectrow_array("SELECT s2code FROM s2source WHERE s2lid=?", undef, $s2lid);
}

sub load_layer_source_row
{
    my $s2lid = shift;

    # s2source is the old global MyISAM table that contains s2 layer sources
    # s2source_inno is new global InnoDB table that contains new layer sources
    # -- lazy migration is done whenever an insert/delete happens

    my $dbh = LJ::get_db_writer();

    # first try InnoDB table
    my $s2source = $dbh->selectrow_hashref("SELECT * FROM s2source_inno WHERE s2lid=?", undef, $s2lid);
    return $s2source if $s2source;

    # fall back to MyISAM
    return $dbh->selectrow_hashref("SELECT * FROM s2source WHERE s2lid=?", undef, $s2lid);
}

sub get_layout_langs
{
    my $src = shift;
    my $layid = shift;
    my %lang;
    foreach (keys %$src) {
        next unless /^\d+$/;
        my $v = $src->{$_};
        next unless $v->{'langcode'};
        $lang{$v->{'langcode'}} = $src->{$_}
            if ($v->{'type'} eq "i18nc" ||
                ($v->{'type'} eq "i18n" && $layid && $v->{'b2lid'} == $layid));
    }
    return map { $_, $lang{$_}->{'name'} } sort keys %lang;
}

# returns array of hashrefs
sub get_layout_themes
{
    my $src = shift; $src = [ $src ] unless ref $src eq "ARRAY";
    my $layid = shift;
    my @themes;
    foreach my $src (@$src) {
        foreach (sort { $src->{$a}->{'name'} cmp $src->{$b}->{'name'} } keys %$src) {
            next unless /^\d+$/;
            my $v = $src->{$_};
            $v->{b2layer} = $src->{$src->{$_}->{b2lid}}; # include layout information
            my $is_active = LJ::run_hook("layer_is_active", $v->{'uniq'});
            push @themes, $v if
                ($v->{type} eq "theme" &&
                 $layid &&
                 $v->{b2lid} == $layid &&
                 (!defined $is_active || $is_active));
        }
    }
    return @themes;
}

# src, layid passed to get_layout_themes; u is optional
sub get_layout_themes_select
{
    my ($src, $layid, $u) = @_;
    my (@sel, $last_uid, $text, $can_use_layer, $layout_allowed);

    foreach my $t (get_layout_themes($src, $layid)) {
        # themes should be shown but disabled if you can't use the layout
        unless (defined $layout_allowed) {
            if (defined $u && $t->{b2layer} && $t->{b2layer}->{uniq}) {
                $layout_allowed = LJ::S2::can_use_layer($u, $t->{b2layer}->{uniq});
            } else {
                # if no parent layer information, or no uniq (user style?),
                # then just assume it's allowed
                $layout_allowed = 1;
            }
        }

        $text = $t->{name};
        $can_use_layer = $layout_allowed &&
                         (! defined $u || LJ::S2::can_use_layer($u, $t->{uniq})); # if no u, accept theme; else check policy
        $text = "$text*" unless $can_use_layer;

        if ($last_uid && $t->{userid} != $last_uid) {
            push @sel, 0, '---';  # divider between system & user
        }
        $last_uid = $t->{userid};

        # these are passed to LJ::html_select which can take hashrefs
        push @sel, {
            value => $t->{s2lid},
            text => $text,
            disabled => ! $can_use_layer,
        };
    }

    return @sel;
}

sub get_policy
{
    return $LJ::S2::CACHE_POLICY if $LJ::S2::CACHE_POLICY;
    my $policy = {};

    # localize $_ so that the while (<P>) below doesn't clobber it and cause problems
    # in anybody that happens to be calling us
    local $_;

    foreach my $infix ("", "-local") {
        my $file = "$LJ::HOME/bin/upgrading/s2layers/policy${infix}.dat";
        my $layer = undef;
        open (P, $file) or next;
        while (<P>) {
            s/\#.*//;
            next unless /\S/;
            if (/^\s*layer\s*:\s*(\S+)\s*$/) {
                $layer = $1;
                next;
            }
            next unless $layer;
            s/^\s+//; s/\s+$//;
            my @words = split(/\s+/, $_);
            next unless $words[-1] eq "allow" || $words[-1] eq "deny";
            my $allow = $words[-1] eq "allow" ? 1 : 0;
            if ($words[0] eq "use" && @words == 2) {
                $policy->{$layer}->{'use'} = $allow;
            }
            if ($words[0] eq "props" && @words == 2) {
                $policy->{$layer}->{'props'} = $allow;
            }
            if ($words[0] eq "prop" && @words == 3) {
                $policy->{$layer}->{'prop'}->{$words[1]} = $allow;
            }
        }
    }

    return $LJ::S2::CACHE_POLICY = $policy;
}

sub can_use_layer
{
    my ($u, $uniq) = @_;  # $uniq = redist_uniq value
    return 1 if LJ::get_cap($u, "s2styles");
    return 0 unless $uniq;
    return 1 if LJ::run_hook('s2_can_use_layer', {
        u => $u,
        uniq => $uniq,
    });
    my $pol = get_policy();
    my $can = 0;

    my @try = ($uniq =~ m!/layout$!) ?
              ('*', $uniq)           : # this is a layout
              ('*/themes', $uniq);     # this is probably a theme

    foreach (@try) {
        next unless defined $pol->{$_};
        next unless defined $pol->{$_}->{'use'};
        $can = $pol->{$_}->{'use'};
    }
    return $can;
}

sub can_use_prop
{
    my ($u, $uniq, $prop) = @_;  # $uniq = redist_uniq value
    return 1 if LJ::get_cap($u, "s2styles");
    return 1 if LJ::get_cap($u, "s2props");
    my $pol = get_policy();
    my $can = 0;
    my @layers = ('*');
    my $pub = get_public_layers();
    if ($pub->{$uniq} && $pub->{$uniq}->{'type'} eq "layout") {
        my $cid = $pub->{$uniq}->{'b2lid'};
        push @layers, $pub->{$cid}->{'uniq'} if $pub->{$cid};
    }
    push @layers, $uniq;
    foreach my $lay (@layers) {
        foreach my $it ('props', 'prop') {
            if ($it eq "props" && defined $pol->{$lay}->{'props'}) {
                $can = $pol->{$lay}->{'props'};
            }
            if ($it eq "prop" && defined $pol->{$lay}->{'prop'}->{$prop}) {
                $can = $pol->{$lay}->{'prop'}->{$prop};
            }
        }
    }
    return $can;
}

sub get_journal_day_counts
{
    my ($s2page) = @_;
    return $s2page->{'_day_counts'} if defined $s2page->{'_day_counts'};

    my $u = $s2page->{'_u'};
    my $counts = {};

    my $remote = LJ::get_remote();
    my $days = LJ::get_daycounts($u, $remote) or return {};
    foreach my $day (@$days) {
        $counts->{$day->[0]}->{$day->[1]}->{$day->[2]} = $day->[3];
    }
    return $s2page->{'_day_counts'} = $counts;
}

## S2 object constructors

sub CommentInfo
{
    my $opts = shift;
    $opts->{'_type'} = "CommentInfo";
    $opts->{'count'} += 0;
    return $opts;
}

sub Date
{
    my @parts = @_;
    my $dt = { '_type' => 'Date' };
    $dt->{'year'} = $parts[0]+0;
    $dt->{'month'} = $parts[1]+0;
    $dt->{'day'} = $parts[2]+0;
    $dt->{'_dayofweek'} = $parts[3];
    die "S2 Builtin Date() takes day of week 1-7, not 0-6"
        if defined $parts[3] && $parts[3] == 0;
    return $dt;
}

sub DateTime_unix
{
    my $time = shift;
    my @gmtime = gmtime($time);
    my $dt = { '_type' => 'DateTime' };
    $dt->{'year'} = $gmtime[5]+1900;
    $dt->{'month'} = $gmtime[4]+1;
    $dt->{'day'} = $gmtime[3];
    $dt->{'hour'} = $gmtime[2];
    $dt->{'min'} = $gmtime[1];
    $dt->{'sec'} = $gmtime[0];
    $dt->{'_dayofweek'} = $gmtime[6] + 1;
    return $dt;
}

sub DateTime_tz
{
    # timezone can be scalar timezone name, DateTime::TimeZone object, or LJ::User object
    my ($epoch, $timezone) = @_;
    return undef unless $timezone;

    if (ref $timezone eq "LJ::User") {
        $timezone = $timezone->prop("timezone");
        return undef unless $timezone;
    }

    my $dt = eval {
        DateTime->from_epoch(
                             epoch => $epoch,
                             time_zone => $timezone,
                             );
    };
    return undef unless $dt;

    my $ret = { '_type' => 'DateTime' };
    $ret->{'year'} = $dt->year;
    $ret->{'month'} = $dt->month;
    $ret->{'day'} = $dt->day;
    $ret->{'hour'} = $dt->hour;
    $ret->{'min'} = $dt->minute;
    $ret->{'sec'} = $dt->second;

    # DateTime.pm's dayofweek is 1-based/Mon-Sun, but S2's is 1-based/Sun-Sat,
    # so first we make DT's be 0-based/Sun-Sat, then shift it up to 1-based.
    $ret->{'_dayofweek'} = ($dt->day_of_week % 7) + 1;
    return $ret;
}

sub DateTime_parts
{
    my @parts = split(/\s+/, shift);
    my $dt = { '_type' => 'DateTime' };
    $dt->{'year'} = $parts[0]+0;
    $dt->{'month'} = $parts[1]+0;
    $dt->{'day'} = $parts[2]+0;
    $dt->{'hour'} = $parts[3]+0;
    $dt->{'min'} = $parts[4]+0;
    $dt->{'sec'} = $parts[5]+0;
    # the parts string comes from MySQL which has range 0-6,
    # but internally and to S2 we use 1-7.
    $dt->{'_dayofweek'} = $parts[6] + 1 if defined $parts[6];
    return $dt;
}

sub Tag
{
    my ($u, $kwid, $kw) = @_;
    return undef unless $u && $kwid && $kw;

    my $t = {
        _type => 'Tag',
        _id => $kwid,
        name => LJ::ehtml($kw),
        url => LJ::journal_base($u) . '/tag/' . LJ::eurl($kw),
    };

    return $t;
}

sub TagDetail
{
    my ($u, $kwid, $tag) = @_;
    return undef unless $u && $kwid && ref $tag eq 'HASH';

    my $t = {
        _type => 'TagDetail',
        _id => $kwid,
        name => LJ::ehtml($tag->{name}),
        url => LJ::journal_base($u) . '/tag/' . LJ::eurl($tag->{name}),
        use_count => $tag->{uses},
        visibility => $tag->{security_level},
    };

    my $sum = 0;
    $sum += $tag->{security}->{groups}->{$_}
        foreach keys %{$tag->{security}->{groups} || {}};
    $t->{security_counts}->{$_} = $tag->{security}->{$_}
        foreach qw(public private friends);
    $t->{security_counts}->{groups} = $sum;

    return $t;
}

sub Entry
{
    my ($u, $arg) = @_;
    my $e = {
        '_type' => 'Entry',
        'link_keyseq' => [ 'edit_entry', 'edit_tags' ],
        'metadata' => {},
    };
    foreach (qw(subject text journal poster new_day end_day
                comments userpic permalink_url itemid tags)) {
        $e->{$_} = $arg->{$_};
    }

    my $remote = LJ::get_remote();
    my $poster = $e->{poster}->{_u};

    $e->{'tags'} ||= [];
    $e->{'time'} = DateTime_parts($arg->{'dateparts'});
    $e->{'system_time'} = DateTime_parts($arg->{'system_dateparts'});
    $e->{'depth'} = 0;  # Entries are always depth 0.  Comments are 1+.

    my $link_keyseq = $e->{'link_keyseq'};
    push @$link_keyseq, 'mem_add' unless $LJ::DISABLED{'memories'};
    push @$link_keyseq, 'tell_friend' unless $LJ::DISABLED{'tellafriend'};
    push @$link_keyseq, 'watch_comments' unless $LJ::DISABLED{'esn'};
    push @$link_keyseq, 'unwatch_comments' unless $LJ::DISABLED{'esn'};
    push @$link_keyseq, 'flag' unless LJ::conf_test($LJ::DISABLED{content_flag});

    # Note: nav_prev and nav_next are not included in the keyseq anticipating
    #      that their placement relative to the others will vary depending on
    #      layout.

    if ($arg->{'security'} eq "public") {
        # do nothing.
    } elsif ($arg->{'security'} eq "usemask") {
        if ($arg->{'allowmask'} == 0) { # custom security with no group -- essentially private
            $e->{'security'} = "private";
            $e->{'security_icon'} = Image_std("security-private");
        } elsif ($arg->{'allowmask'} > 1 && $poster && $poster->equals($remote)) { # custom group -- only show to journal owner
            $e->{'security'} = "custom";
            $e->{'security_icon'} = Image_std("security-groups");
        } else { # friends only or custom group showing to non journal owner
            $e->{'security'} = "protected";
            $e->{'security_icon'} = Image_std("security-protected");
        }
    } elsif ($arg->{'security'} eq "private") {
        $e->{'security'} = "private";
        $e->{'security_icon'} = Image_std("security-private");
    }

    $e->{'age_restriction'} = "";
    if ($arg->{'age_restriction'} eq "explicit") {
        $e->{'age_restriction'} = "18";
        $e->{'age_restriction_icon'} = Image_std("age-18");
    } elsif ($arg->{'age_restriction'} eq "concepts") {
        $e->{'age_restriction'} = "14";
        $e->{'age_restriction_icon'} = Image_std("age-14");
    } else {
        # do nothing.
    }

    my $p = $arg->{'props'};
    if ($p->{'current_music'}) {
        $e->{'metadata'}->{'music'} = LJ::LastFM::format_current_music_string($p->{'current_music'});
        LJ::CleanHTML::clean_subject(\$e->{'metadata'}->{'music'});
    }
    if (my $mid = $p->{'current_moodid'}) {
        my $theme = defined $arg->{'moodthemeid'} ? $arg->{'moodthemeid'} : $u->{'moodthemeid'};
        my %pic;
        $e->{'mood_icon'} = Image($pic{'pic'}, $pic{'w'}, $pic{'h'})
            if LJ::get_mood_picture($theme, $mid, \%pic);
        if (my $mood = LJ::mood_name($mid)) {
            my $extra = LJ::run_hook("current_mood_extra", $theme) || "";
            $e->{'metadata'}->{'mood'} = "$mood$extra";
        }
    }
    if ($p->{'current_mood'}) {
        $e->{'metadata'}->{'mood'} = $p->{'current_mood'};
        LJ::CleanHTML::clean_subject(\$e->{'metadata'}->{'mood'});
    }

    if ($p->{'current_location'} || $p->{'current_coords'}) {
        my $loc = eval { LJ::Location->new(coords   => $p->{'current_coords'},
                                           location => $p->{'current_location'}) };
        $e->{'metadata'}->{'location'} = $loc->as_html_current if $loc;
    }

    my $r = BML::get_request();

    # custom friend groups
    my $entry = LJ::Entry->new($e->{journal}->{_u}, ditemid => $e->{itemid});
    my $group_names = $entry->group_names;
    $e->{metadata}->{groups} = $group_names if $group_names;

    # TODO: Populate this field more intelligently later, but for now this will
    #   hopefully disuade people from hardcoding logic like this into their S2
    #   layers when they do weird parsing/manipulation of the text member in
    #   untrusted layers.
    $e->{text_must_print_trusted} = 1 if $e->{text} =~ m!<(script|object|applet|embed|iframe)\b!i;

    return $e;
}

sub Friend
{
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'} = "Friend";
    $o->{'bgcolor'} = S2::Builtin::LJ::Color__Color($u->{'bgcolor'});
    $o->{'fgcolor'} = S2::Builtin::LJ::Color__Color($u->{'fgcolor'});
    return $o;
}

sub Null
{
    my $type = shift;
    return {
        '_type' => $type,
        '_isnull' => 1,
    };
}

sub Page
{
    my ($u, $opts) = @_;
    my $styleid = $u->{'_s2styleid'} + 0;
    my $base_url = $u->{'_journalbase'};

    my $get = $opts->{'getargs'};
    my %args;
    foreach my $k (keys %$get) {
        my $v = $get->{$k};
        next unless $k =~ s/^\.//;
        $args{$k} = $v;
    }

    # get MAX(modtime of style layers)
    my $stylemodtime = S2::get_style_modtime($opts->{'ctx'});
    my $style = load_style($styleid);
    $stylemodtime = $style->{'modtime'} if $style->{'modtime'} > $stylemodtime;

    my $linkobj = LJ::Links::load_linkobj($u);
    my $linklist = [ map { UserLink($_) } @$linkobj ];

    my $remote = LJ::get_remote();
    my $tz_remote;
    if ($remote) {
        my $tz = $remote->prop( "timezone" );
        $tz_remote = $tz ? eval { DateTime::TimeZone->new( name => $tz); } : undef;
    }

    my $p = {
        '_type' => 'Page',
        '_u' => $u,
        'view' => '',
        'args' => \%args,
        'journal' => User($u),
        'journal_type' => $u->{'journaltype'},
        'time' => DateTime_unix(time),
        'local_time' => $tz_remote ? DateTime_tz( time, $tz_remote ) : DateTime_unix(time),
        'base_url' => $base_url,
        'stylesheet_url' => "$base_url/res/$styleid/stylesheet?$stylemodtime",
        'view_url' => {
            recent   => "$base_url/",
            userinfo => $u->profile_url,
            archive  => "$base_url/calendar",
            read     => "$base_url/read",
            tags     => "$base_url/tag",
            memories => "$LJ::SITEROOT/tools/memories.bml?user=$u->{user}",
        },
        'linklist' => $linklist,
        'views_order' => [ 'recent', 'archive', 'read', 'tags', 'memories', 'userinfo' ],
        'global_title' =>  LJ::ehtml($u->{'journaltitle'} || $u->{'name'}),
        'global_subtitle' => LJ::ehtml($u->{'journalsubtitle'}),
        'head_content' => '',
        'data_link' => {},
        'data_links_order' => [],
    };

    if ($LJ::UNICODE && $opts && $opts->{'saycharset'}) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset=' . $opts->{'saycharset'} . "\" />\n";
    }

    if (LJ::are_hooks('s2_head_content_extra')) {
        $p->{head_content} .= LJ::run_hook('s2_head_content_extra', $remote, $opts->{r});
    }

    # Automatic Discovery of RSS/Atom
    if ($opts && $opts->{'addfeeds'}) {
        $p->{'head_content'} .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$p->{'base_url'}/data/rss" />\n};
        $p->{'head_content'} .= qq{<link rel="alternate" type="application/atom+xml" title="Atom" href="$p->{'base_url'}/data/atom" />\n};
        $p->{'head_content'} .= qq{<link rel="service.feed" type="application/atom+xml" title="AtomAPI-enabled feed" href="$LJ::SITEROOT/interface/atomapi/$u->{'user'}/feed" />\n};
        $p->{'head_content'} .= qq{<link rel="service.post" type="application/atom+xml" title="Create a new post" href="$LJ::SITEROOT/interface/atomapi/$u->{'user'}/post" />\n};
    }

    # OpenID information if the caller asked us to include it here.
    $p->{'head_content'} .= $u->openid_tags if $opts && $opts->{'addopenid'};

    # other useful link rels
    $p->{head_content} .= qq{<link rel="help" href="$LJ::SITEROOT/support/faq" />\n};

    # Control strip
    my $show_control_strip = LJ::run_hook( 'show_control_strip' );
    if ($show_control_strip) {
        LJ::run_hook( 'control_strip_stylesheet_link' );
        $p->{'head_content'} .= LJ::control_strip_js_inject( user => $u->{user} );
    }

    # FOAF autodiscovery
    my $foafurl = $u->{external_foaf_url} ? LJ::eurl($u->{external_foaf_url}) : "$p->{base_url}/data/foaf";
    $p->{head_content} .= qq{<link rel="meta" type="application/rdf+xml" title="FOAF" href="$foafurl" />\n};

    if ($u->email_visible($remote)) {
        my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->email_raw);
        $p->{head_content} .= qq{<meta name="foaf:maker" content="foaf:mbox_sha1sum '$digest'" />\n};
    }

    # Identity (type I) accounts only have read views
    $p->{'views_order'} = [ 'read', 'userinfo' ] if $u->{'journaltype'} eq 'I';

    return $p;
}

sub Link {
    my ($url, $caption, $icon) = @_;

    my $lnk = {
        '_type'   => 'Link',
        'caption' => $caption,
        'url'     => $url,
        'icon'    => $icon,
    };

    return $lnk;
}

sub Image
{
    my ($url, $w, $h, $alttext, %extra) = @_;
    return {
        '_type' => 'Image',
        'url' => $url,
        'width' => $w,
        'height' => $h,
        'alttext' => $alttext,
        'extra' => {%extra},
    };
}

sub Image_std
{
    my $name = shift;
    my $ctx = $LJ::S2::CURR_CTX or die "No S2 context available ";

    unless ($LJ::S2::RES_MADE++) {
        $LJ::S2::RES_CACHE = {
            'security-protected' => Image("$LJ::IMGPREFIX/icon_protected.gif", 14, 15, $ctx->[S2::PROPS]->{'text_icon_alt_protected'}),
            'security-private' => Image("$LJ::IMGPREFIX/icon_private.gif", 16, 16, $ctx->[S2::PROPS]->{'text_icon_alt_private'}),
            'security-groups' => Image("$LJ::IMGPREFIX/icon_groups.gif", 19, 16, $ctx->[S2::PROPS]->{'text_icon_alt_groups'}),
            'age-14' => Image("$LJ::IMGPREFIX/icon_14.gif", 14, 15, $ctx->[S2::PROPS]->{'text_icon_alt_14_plus'}),
            'age-18' => Image("$LJ::IMGPREFIX/icon_18.gif", 14, 15, $ctx->[S2::PROPS]->{'text_icon_alt_18_plus'}),
        };
    }
    return $LJ::S2::RES_CACHE->{$name};
}

sub Image_userpic
{
    my ($u, $picid, $kw) = @_;

    $picid ||= LJ::get_picid_from_keyword($u, $kw);
    return Null("Image") unless $picid;

    # get the Userpic object
    my $p = LJ::Userpic->new($u, $picid);

    # load the alttext.  use description by default, keyword as fallback,
    # and all keywords as final fallback (should be for default icon only).
    my $description = $p->description;
    my $alttext;

    if ($description) {
        $alttext = $description;
    } elsif ($kw) {
        $alttext = $kw;
    } else {
        my $kwstr = $p->keywords;
        $alttext = $kwstr;
    }

    return {
        '_type' => "Image",
        'url' => "$LJ::USERPIC_ROOT/$picid/$u->{'userid'}",
        'width' => $p->{'width'},
        'height' => $p->{'height'},
        'alttext' => $alttext,
    };
}

sub ItemRange_fromopts
{
    my $opts = shift;
    my $ir = {};

    my $items = $opts->{'items'};
    my $page_size = ($opts->{'pagesize'}+0) || 25;
    my $page = $opts->{'page'}+0 || 1;
    my $num_items = scalar @$items;

    my $pages = POSIX::ceil($num_items / $page_size) || 1;
    if ($page > $pages) { $page = $pages; }

    splice(@$items, 0, ($page-1)*$page_size) if $page > 1;
    splice(@$items, $page_size) if @$items > $page_size;

    $ir->{'current'} = $page;
    $ir->{'total'} = $pages;
    $ir->{'total_subitems'} = $num_items;
    $ir->{'from_subitem'} = ($page-1) * $page_size + 1;
    $ir->{'num_subitems_displayed'} = @$items;
    $ir->{'to_subitem'} = $ir->{'from_subitem'} + $ir->{'num_subitems_displayed'} - 1;
    $ir->{'all_subitems_displayed'} = ($pages == 1);
    $ir->{'_url_of'} = $opts->{'url_of'};
    return ItemRange($ir);
}

sub ItemRange
{
    my $h = shift;  # _url_of = sub($n)
    $h->{'_type'} = "ItemRange";

    my $url_of = ref $h->{'_url_of'} eq "CODE" ? $h->{'_url_of'} : sub {"";};

    $h->{'url_next'} = $url_of->($h->{'current'} + 1)
        unless $h->{'current'} >= $h->{'total'};
    $h->{'url_prev'} = $url_of->($h->{'current'} - 1)
        unless $h->{'current'} <= 1;
    $h->{'url_first'} = $url_of->(1)
        unless $h->{'current'} == 1;
    $h->{'url_last'} = $url_of->($h->{'total'})
        unless $h->{'current'} == $h->{'total'};

    return $h;
}

sub User
{
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'} = "User";
    $o->{'default_pic'} = Image_userpic($u, $u->{'defaultpicid'});
    $o->{'userpic_listing_url'} = "$LJ::SITEROOT/allpics.bml?user=".$u->{'user'};
    $o->{'website_url'} = LJ::ehtml($u->{'url'});
    $o->{'website_name'} = LJ::ehtml($u->{'urlname'});
    return $o;
}

sub UserLink
{
    my $link = shift; # hashref

    # a dash means pass to s2 as blank so it will just insert a blank line
    $link->{'title'} = '' if $link->{'title'} eq "-";

    return {
        '_type' => 'UserLink',
        'is_heading' => $link->{'url'} ? 0 : 1,
        'url' => LJ::ehtml($link->{'url'}),
        'title' => LJ::ehtml($link->{'title'}),
        'children' => $link->{'children'} || [], # TODO: implement parent-child relationships
    };
}

sub UserLite
{
    my ($u) = @_;
    my $o;
    return $o unless $u;

    $o = {
        '_type' => 'UserLite',
        '_u' => $u,
        'username' => LJ::ehtml($u->display_name),
        'name' => LJ::ehtml($u->{'name'}),
        'journal_type' => $u->{'journaltype'},
        'data_link' => {
            'foaf' => Link("$LJ::SITEROOT/users/" . LJ::ehtml($u->{'user'}) . '/data/foaf',
                           "FOAF",
                           Image("$LJ::IMGPREFIX/data_foaf.gif", 32, 15, "FOAF")),
        },
        'data_links_order' => [ "foaf" ],
        'link_keyseq' => [ ],
    };
    my $lks = $o->{link_keyseq};
    push @$lks, qw(manage_membership trust watch post_entry track message);
    push @$lks, 'tell_friend' unless $LJ::DISABLED{tellafriend};

    # TODO: Figure out some way to use the userinfo_linkele hook here?

    return $o;
}

# Given an S2 Entry object, return if it's the first, second, third, etc. entry that we've seen
sub nth_entry_seen {
    my $e = shift;
    my $key = "$e->{'journal'}->{'username'}-$e->{'itemid'}";
    my $ref = $LJ::REQ_GLOBAL{'nth_entry_keys'};
    
    if (exists $ref->{$key}) {
        return $ref->{$key};
    }
    return $LJ::REQ_GLOBAL{'nth_entry_keys'}->{$key} = ++$LJ::REQ_GLOBAL{'nth_entry_ct'};
}

sub curr_page_supports_ebox {
    my $u = shift;
    my $rv = LJ::run_hook('curr_page_supports_ebox', $u, $LJ::S2::CURR_PAGE->{'view'});
    return $rv if defined $rv;
    return $LJ::S2::CURR_PAGE->{'view'} =~ /^(?:recent|read|day)$/ ? 1 : 0;
}

sub current_box_type {
    my $u = shift;

    # Must be an ad user to see any box
    return undef unless S2::Builtin::LJ::viewer_sees_ads();

    # Ads between posts are shown if:
    # 1. eboxes are enabled for the site AND
    # 2. User has selected the ebox option AND
    # 3. eboxes are supported by the current page or there is no current page
    if ($u->can_use_ebox) {
        my $user_has_chosen_ebox = LJ::run_hook('user_has_chosen_ebox', $u) || $u->prop('journal_box_entries');
        return "ebox" if $user_has_chosen_ebox && (LJ::S2::curr_page_supports_ebox($u) || !$LJ::S2::CURR_PAGE->{'view'});
    }

    # Horizontal ads are shown if:
    # 1. ebox isn't applicable AND
    # 2. User has S2 style system and selected the hbox option
    return "hbox" if $u->prop('stylesys') == 2 && $u->prop('journal_box_placement') eq 'h';

    # Otherwise, vbox is the default
    return "vbox";
}


###############

package S2::Builtin::LJ;
use strict;

sub UserLite {
    my ($ctx,$username) = @_;
    my $u = LJ::load_user($username);
    return LJ::S2::UserLite($u);
}

sub start_css {
    my ($ctx) = @_;
    my $sc = $ctx->[S2::SCRATCH];
    $sc->{_start_css_pout}   = S2::get_output();
    $sc->{_start_css_pout_s} = S2::get_output_safe();
    $sc->{_start_css_buffer} = "";
    my $printer = sub {
        $sc->{_start_css_buffer} .= shift;
    };
    S2::set_output($printer);
    S2::set_output_safe($printer);
}

sub end_css {
    my ($ctx) = @_;
    my $sc = $ctx->[S2::SCRATCH];

    # restore our printer/safe printer
    S2::set_output($sc->{_start_css_pout});
    S2::set_output_safe($sc->{_start_css_pout_s});

    # our CSS to clean:
    my $css = $sc->{_start_css_buffer};
    my $cleaner = LJ::CSS::Cleaner->new;

    my $clean = $cleaner->clean($css);
    LJ::run_hook('css_cleaner_transform', \$clean);

    $sc->{_start_css_pout}->("/* Cleaned CSS: */\n" .
                             $clean .
                             "\n");
}

sub alternate
{
    my ($ctx, $one, $two) = @_;

    my $scratch = $ctx->[S2::SCRATCH];

    $scratch->{alternate}{"$one\0$two"} = ! $scratch->{alternate}{"$one\0$two"};
    return $scratch->{alternate}{"$one\0$two"} ? $one : $two;
}

sub set_content_type
{
    my ($ctx, $type) = @_;

    die "set_content_type is not yet implemented";
    $ctx->[S2::SCRATCH]->{contenttype} = $type;
}

sub striphtml
{
    my ($ctx, $s) = @_;

    $s =~ s/<.*?>//g;
    return $s;
}

sub ehtml
{
    my ($ctx, $text) = @_;
    return LJ::ehtml($text);
}

sub eurl
{
    my ($ctx, $text) = @_;
    return LJ::eurl($text);
}

# escape tags only
sub etags {
    my ($ctx, $text) = @_;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

# sanitize URLs
sub clean_url {
    my ($ctx, $text) = @_;
    unless ($text =~ m!^https?://[^\'\"\\]*$!) {
        $text = "";
    }
    return $text;
}

sub get_page
{
    return $LJ::S2::CURR_PAGE;
}

sub get_plural_phrase
{
    my ($ctx, $n, $prop) = @_;
    my $form = S2::run_function($ctx, "lang_map_plural(int)", $n);
    my $a = $ctx->[S2::PROPS]->{"_plurals_$prop"};
    unless (ref $a eq "ARRAY") {
        $a = $ctx->[S2::PROPS]->{"_plurals_$prop"} = [ split(m!\s*//\s*!, $ctx->[S2::PROPS]->{$prop}) ];
    }
    my $text = $a->[$form];

    # this fixes missing plural forms for russians (who have 2 plural forms)
    # using languages like english with 1 plural form
    $text = $a->[-1] unless defined $text;

    $text =~ s/\#/$n/;
    return LJ::ehtml($text);
}

sub get_url
{
    my ($ctx, $obj, $view) = @_;
    my $user;

    # now get data from one of two paths, depending on if we were given a UserLite
    # object or a string for the username, so make sure we have the username.
    if (ref $obj eq 'HASH') {
        $user = $obj->{username};
    } else {
        $user = $obj;
    }

    my $u = LJ::load_user($user);
    return "" unless $u;

    # construct URL to return
    $view = "profile" if $view eq "userinfo";
    $view = "calendar" if $view eq "archive";
    $view = "" if $view eq "recent";
    my $base = $u->journal_base;
    return "$base/$view";
}

sub htmlattr
{
    my ($ctx, $name, $value) = @_;
    return "" if $value eq "";
    $name = lc($name);
    return "" if $name =~ /[^a-z]/;
    return " $name=\"" . LJ::ehtml($value) . "\"";
}

sub rand
{
    my ($ctx, $aa, $bb) = @_;
    my ($low, $high);
    if (ref $aa eq "ARRAY") {
        ($low, $high) = (0, @$aa - 1);
    } elsif (! defined $bb) {
        ($low, $high) = (1, $aa);
    } else {
        ($low, $high) = ($aa, $bb);
    }
    return int(rand($high - $low + 1)) + $low;
}

sub pageview_unique_string {
    my ($ctx) = @_;

    return LJ::pageview_unique_string();
}

sub viewer_logged_in
{
    my ($ctx) = @_;
    my $remote = LJ::get_remote();
    return defined $remote;
}

sub viewer_is_owner
{
    my ($ctx) = @_;
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined($LJ::S2::CURR_PAGE);
    return $remote->{'userid'} == $LJ::S2::CURR_PAGE->{'_u'}->{'userid'};
}

# NOTE: this method is old and deprecated, but we still support it for people
# who are importing styles from old sites.  since we don't know if the style
# is asking if the viewer is "watched" or if they're "trusted", we default to
# returning true if they're trusted.  since we believe that the majority of
# trust relationships also include a watch relationship, this should be the
# right behavior in 90%+ of cases.  in the few that it is not, we humbly
# suggest that people update their styles to use the DW core/functions.
sub viewer_is_friend
{
    my ($ctx) = @_;
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined($LJ::S2::CURR_PAGE);

    my $ju = $LJ::S2::CURR_PAGE->{'_u'};
    return 0 if $ju->{journaltype} eq 'C';
    return $ju->trusts( $remote );
}

sub viewer_is_member
{
    my ($ctx) = @_;
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined($LJ::S2::CURR_PAGE);

    my $ju = $LJ::S2::CURR_PAGE->{'_u'};
    return 0 unless $ju->is_community;
    return $remote->member_of( $ju );
}

sub viewer_sees_control_strip
{
    return 0 unless $LJ::USE_CONTROL_STRIP;

    my $r = BML::get_request();
    return LJ::run_hook( 'show_control_strip' );
}

sub _get_ad_box_args {
    my $ctx = shift;
    
    my $r = BML::get_request();
    my $journalu = LJ::load_userid($r->notes->{journalid});
    return 0 unless $journalu;
    
    my $colors = _get_colors_for_ad($ctx);

    my $qotd = 0;
    if ($LJ::S2::CURR_PAGE->{view} eq "entry" || $LJ::S2::CURR_PAGE->{view} eq "reply") {
        my $entry = LJ::Entry->new($journalu, ditemid => $LJ::S2::CURR_PAGE->{entry}->{itemid});
        $qotd = $entry->prop("qotdid") if $entry;
    }
 
    return {
        journalu => $journalu,
        pubtext  => $LJ::REQ_GLOBAL{text_of_first_public_post},
        tags     => $LJ::REQ_GLOBAL{tags_of_first_public_post},
        colors   => $colors,
        interests_extra => $qotd ? { qotd => $qotd } : {},
        s2_view  => $LJ::S2::CURR_PAGE->{'view'},
        total_posts_number => scalar( @{$LJ::S2::CURR_PAGE->{'entries'} || []}),
    };    

}

sub viewer_sees_vbox
{
    my $args = _get_ad_box_args(@_);
    $args->{location} = 's2.vertical' if $args;
    return $args ? LJ::should_show_ad($args):0;
}

sub viewer_sees_hbox_top
{
    my $args = _get_ad_box_args(@_);
    $args->{location} = 's2.top' if $args;
    return $args ? LJ::should_show_ad($args):0;
}

sub viewer_sees_hbox_bottom
{
    my $args = _get_ad_box_args(@_);
    $args->{location} = 's2.bottom' if $args;
    return $args ? LJ::should_show_ad($args):0;
}

sub viewer_sees_ad_box {
    my ($ctx, $location) = @_;
    my $args = _get_ad_box_args($ctx);
    $args->{location} = $location if $args;
    return $args ? LJ::should_show_ad($args):0;
}

sub viewer_sees_ebox {
    my $r = BML::get_request();
    my $u = LJ::load_userid($r->notes->{journalid});
    return 0 unless $u;

    if (LJ::S2::current_box_type($u) eq "ebox") {
        return 1;
    }

    return 0;
}

sub _get_Entry_ebox_args {
    my ($ctx, $this) = @_;

    my $r = BML::get_request();
    my $journalu = LJ::load_userid($r->notes->{journalid});
    return 0 unless $journalu;

    my $curr_entry_ct = LJ::S2::nth_entry_seen($this);
    my $entries = $LJ::S2::CURR_PAGE->{'entries'} || [];
    my $total_entry_ct = @$entries;

    $LJ::REQ_GLOBAL{ebox_count} = $LJ::REQ_GLOBAL{ebox_count} > 1 ? $LJ::REQ_GLOBAL{ebox_count} : 1;
    
    #return unless (LJ::S2::current_box_type($journalu) eq "ebox");
    
    my $colors = _get_colors_for_ad($ctx);
    my $pubtext;
    my @tag_names;

    # If this entry is public, get this entry's text and tags
    # If this entry is non-public, get the first public entry's text and tags
    if ($this->{security}) { # if non-public
        $pubtext = $LJ::REQ_GLOBAL{text_of_first_public_post};
        @tag_names = @{$LJ::REQ_GLOBAL{tags_of_first_public_post} || []};
    } else { # if public
        $pubtext = $this->{text};
        if (@{$this->{tags}}) {
            @tag_names = map { $_->{name} } @{$this->{tags}};
        }
    }

    my $qotd = 0;
    if ($LJ::S2::CURR_PAGE->{view} eq "entry" || $LJ::S2::CURR_PAGE->{view} eq "reply") {
        my $entry = LJ::Entry->new($journalu, ditemid => $LJ::S2::CURR_PAGE->{entry}->{itemid});
        $qotd = $entry->prop("qotdid") if $entry;
    }

    return {
        location    => 's2.ebox',       
        journalu    => $journalu,
        pubtext     => $pubtext,
        tags        => \@tag_names,
        colors      => $colors,
        position    => $LJ::REQ_GLOBAL{ebox_count},
        total_entry_ct  => $total_entry_ct,
        interests_extra => $qotd ? { qotd => $qotd } : {},
        s2_view        => $LJ::S2::CURR_PAGE->{view},
        current_post_number => LJ::S2::nth_entry_seen($this),
        total_posts_number  => scalar( @{$LJ::S2::CURR_PAGE->{'entries'} || []} ),
    }; 
}

sub Entry__viewer_sees_ebox {
    my $args = _get_Entry_ebox_args(@_);
    return $args ? LJ::should_show_ad($args):0;
}

sub viewer_sees_ads # deprecated.
{
    return 0 unless $LJ::USE_ADS;

    my $r = BML::get_request();
    return LJ::run_hook('should_show_ad', {
        ctx  => 'journal',
        userid => $r->notes->{journalid},
    });
}

sub control_strip_logged_out_userpic_css
{
    my $r = BML::get_request();
    my $u = LJ::load_userid($r->notes->{journalid});
    return '' unless $u;

    return LJ::run_hook('control_strip_userpic', $u);
}

sub control_strip_logged_out_full_userpic_css
{
    my $r = BML::get_request();
    my $u = LJ::load_userid($r->notes->{journalid});
    return '' unless $u;

    return LJ::run_hook('control_strip_loggedout_userpic', $u);
}

sub weekdays
{
    my ($ctx) = @_;
    return [ 1..7 ];  # FIXME: make this conditionally monday first: [ 2..7, 1 ]
}

sub journal_current_datetime {
    my ($ctx) = @_;

    my $ret = { '_type' => 'DateTime' };

    my $r = BML::get_request();
    my $u = LJ::load_userid($r->notes->{journalid});
    return $ret unless $u;

    # turn the timezone offset number into a four character string (plus '-' if negative)
    # e.g. -1000, 0700, 0430
    my $timezone = $u->timezone;

    my $partial_hour = "00";
    if ($timezone =~ /(\.\d+)/) {
        $partial_hour = $1*60;
    }

    my $neg = $timezone =~ /-/ ? 1 : 0;
    my $hour = sprintf("%02d", abs(int($timezone))); # two character hour
    $hour = $neg ? "-$hour" : "$hour";
    $timezone = $hour . $partial_hour;

    my $now = DateTime->now( time_zone => $timezone );
    $ret->{year} = $now->year;
    $ret->{month} = $now->month;
    $ret->{day} = $now->day;
    $ret->{hour} = $now->hour;
    $ret->{min} = $now->minute;
    $ret->{sec} = $now->second;

    # DateTime.pm's dayofweek is 1-based/Mon-Sun, but S2's is 1-based/Sun-Sat,
    # so first we make DT's be 0-based/Sun-Sat, then shift it up to 1-based.
    $ret->{_dayofweek} = ($now->day_of_week % 7) + 1;

    return $ret;
}

sub style_is_active {
    my ($ctx) = @_;
    my $layoutid = $ctx->[S2::LAYERLIST]->[1];
    my $themeid = $ctx->[S2::LAYERLIST]->[2];
    my $pub = LJ::S2::get_public_layers();

    my $layout_is_active = LJ::run_hook("layer_is_active", $pub->{$layoutid}->{uniq});
    return 0 unless !defined $layout_is_active || $layout_is_active;

    if (defined $themeid) {
        my $theme_is_active = LJ::run_hook("layer_is_active", $pub->{$themeid}->{uniq});
        return 0 unless !defined $theme_is_active || $theme_is_active;
    }

    return 1;
}

sub set_handler
{
    my ($ctx, $hook, $stmts) = @_;
    my $p = $LJ::S2::CURR_PAGE;
    return unless $hook =~ /^\w+\#?$/;
    $hook =~ s/\#$/ARG/;

    $S2::pout->("<script> function userhook_$hook () {\n");
    foreach my $st (@$stmts) {
        my ($cmd, @args) = @$st;

        my $get_domexp = sub {
            my $domid = shift @args;
            my $domexp = "";
            while ($domid ne "") {
                $domexp .= " + " if $domexp;
                if ($domid =~ s/^(\w+)//) {
                    $domexp .= "\"$1\"";
                } elsif ($domid =~ s/^\#//) {
                    $domexp .= "arguments[0]";
                } else {
                    return undef;
                }
            }
            return $domexp;
        };

        my $get_color = sub {
            my $color = shift @args;
            return undef unless
                $color =~ /^\#[0-9a-f]{3,3}$/ ||
                $color =~ /^\#[0-9a-f]{6,6}$/ ||
                $color =~ /^\w+$/ ||
                $color =~ /^rgb(\d+,\d+,\d+)$/;
            return $color;
        };

        #$S2::pout->("  // $cmd: @args\n");
        if ($cmd eq "style_bgcolor" || $cmd eq "style_color") {
            my $domexp = $get_domexp->();
            my $color = $get_color->();
            if ($domexp && $color) {
                $S2::pout->("setStyle($domexp, 'background', '$color');\n") if $cmd eq "style_bgcolor";
                $S2::pout->("setStyle($domexp, 'color', '$color');\n") if $cmd eq "style_color";
            }
        } elsif ($cmd eq "set_class") {
            my $domexp = $get_domexp->();
            my $class = shift @args;
            if ($domexp && $class =~ /^\w+$/) {
                $S2::pout->("setAttr($domexp, 'class', '$class');\n");
            }
        } elsif ($cmd eq "set_image") {
            my $domexp = $get_domexp->();
            my $url = shift @args;
            if ($url =~ m!^http://! && $url !~ /[\'\"\n\r]/) {
                $url = LJ::eurl($url);
                $S2::pout->("setAttr($domexp, 'src', \"$url\");\n");
            }
        }
    }
    $S2::pout->("} </script>\n");
}

sub zeropad
{
    my ($ctx, $num, $digits) = @_;
    $num += 0;
    $digits += 0;
    return sprintf("%0${digits}d", $num);
}
*int__zeropad = \&zeropad;

sub int__compare
{
    my ($ctx, $this, $other) = @_;
    return $other <=> $this;
}

sub Color__update_hsl
{
    my ($this, $force) = @_;
    return if $this->{'_hslset'}++;
    ($this->{'_h'}, $this->{'_s'}, $this->{'_l'}) =
        S2::Color::rgb_to_hsl($this->{'r'}, $this->{'g'}, $this->{'b'});
    $this->{$_} = int($this->{$_} * 255 + 0.5) foreach qw(_h _s _l);
}

sub Color__update_rgb
{
    my ($this) = @_;

    ($this->{'r'}, $this->{'g'}, $this->{'b'}) =
        S2::Color::hsl_to_rgb( map { $this->{$_} / 255 } qw(_h _s _l) );
    Color__make_string($this);
}

sub Color__make_string
{
    my ($this) = @_;
    $this->{'as_string'} = sprintf("\#%02x%02x%02x",
                                  $this->{'r'},
                                  $this->{'g'},
                                  $this->{'b'});
}

# public functions
sub Color__Color
{
    my ($s) = @_;
    $s =~ s/^\#//;
    $s =~ s/^(\w)(\w)(\w)$/$1$1$2$2$3$3/s;  #  'c30' => 'cc3300'
    return if $s =~ /[^a-fA-F0-9]/ || length($s) != 6;

    my $this = { '_type' => 'Color' };
    $this->{'r'} = hex(substr($s, 0, 2));
    $this->{'g'} = hex(substr($s, 2, 2));
    $this->{'b'} = hex(substr($s, 4, 2));
    $this->{$_} = $this->{$_} % 256 foreach qw(r g b);

    Color__make_string($this);
    return $this;
}

sub Color__clone
{
    my ($ctx, $this) = @_;
    return { %$this };
}

sub Color__set_hsl
{
    my ($this, $h, $s, $l) = @_;
    $this->{'_h'} = $h % 256;
    $this->{'_s'} = $s % 256;
    $this->{'_l'} = $l % 256;
    $this->{'_hslset'} = 1;
    Color__update_rgb($this);
}

sub Color__red {
    my ($ctx, $this, $r) = @_;
    if (defined $r) {
        $this->{'r'} = $r % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'r'};
}

sub Color__green {
    my ($ctx, $this, $g) = @_;
    if (defined $g) {
        $this->{'g'} = $g % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'g'};
}

sub Color__blue {
    my ($ctx, $this, $b) = @_;
    if (defined $b) {
        $this->{'b'} = $b % 256;
        delete $this->{'_hslset'};
        Color__make_string($this);
    }
    $this->{'b'};
}

sub Color__hue {
    my ($ctx, $this, $h) = @_;

    if (defined $h) {
        $this->{'_h'} = $h % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }
    $this->{'_h'};
}

sub Color__saturation {
    my ($ctx, $this, $s) = @_;
    if (defined $s) {
        $this->{'_s'} = $s % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }
    $this->{'_s'};
}

sub Color__lightness {
    my ($ctx, $this, $l) = @_;

    if (defined $l) {
        $this->{'_l'} = $l % 256;
        $this->{'_hslset'} = 1;
        Color__update_rgb($this);
    } elsif (! $this->{'_hslset'}) {
        Color__update_hsl($this);
    }

    $this->{'_l'};
}

sub Color__inverse {
    my ($ctx, $this) = @_;
    my $new = {
        '_type' => 'Color',
        'r' => 255 - $this->{'r'},
        'g' => 255 - $this->{'g'},
        'b' => 255 - $this->{'b'},
    };
    Color__make_string($new);
    return $new;
}

sub Color__average {
    my ($ctx, $this, $other) = @_;
    my $new = {
        '_type' => 'Color',
        'r' => int(($this->{'r'} + $other->{'r'}) / 2 + .5),
        'g' => int(($this->{'g'} + $other->{'g'}) / 2 + .5),
        'b' => int(($this->{'b'} + $other->{'b'}) / 2 + .5),
    };
    Color__make_string($new);
    return $new;
}

sub Color__blend {
    my ($ctx, $this, $other, $value) = @_;
    my $multiplier = $value / 100;
    my $new = {
        '_type' => 'Color',
        'r' => int($this->{'r'} - (($this->{'r'} - $other->{'r'}) * $multiplier) + .5),
        'g' => int($this->{'g'} - (($this->{'g'} - $other->{'g'}) * $multiplier) + .5),
        'b' => int($this->{'b'} - (($this->{'b'} - $other->{'b'}) * $multiplier) + .5),
    };
    Color__make_string($new);
    return $new;
}

sub Color__lighter {
    my ($ctx, $this, $amt) = @_;
    $amt = defined $amt ? $amt : 30;

    Color__update_hsl($this);

    my $new = {
        '_type' => 'Color',
        '_hslset' => 1,
        '_h' => $this->{'_h'},
        '_s' => $this->{'_s'},
        '_l' => ($this->{'_l'} + $amt > 255 ? 255 : $this->{'_l'} + $amt),
    };

    Color__update_rgb($new);
    return $new;
}

sub Color__darker {
    my ($ctx, $this, $amt) = @_;
    $amt = defined $amt ? $amt : 30;

    Color__update_hsl($this);

    my $new = {
        '_type' => 'Color',
        '_hslset' => 1,
        '_h' => $this->{'_h'},
        '_s' => $this->{'_s'},
        '_l' => ($this->{'_l'} - $amt < 0 ? 0 : $this->{'_l'} - $amt),
    };

    Color__update_rgb($new);
    return $new;
}

sub _Comment__get_link
{
    my ($ctx, $this, $key) = @_;
    my $page = get_page();
    my $u = $page->{'_u'};
    my $post_user = $page->{'entry'} ? $page->{'entry'}->{'poster'}->{'username'} : undef;
    my $com_user = $this->{'poster'} ? $this->{'poster'}->{'username'} : undef;
    my $remote = LJ::get_remote();
    my $null_link = { '_type' => 'Link', '_isnull' => 1 };
    my $dtalkid = $this->{talkid};
    my $comment = LJ::Comment->new($u, dtalkid => $dtalkid);

    if ($key eq "delete_comment") {
        return $null_link unless LJ::Talk::can_delete($remote, $u, $post_user, $com_user);
        return LJ::S2::Link("$LJ::SITEROOT/delcomment.bml?journal=$u->{'user'}&amp;id=$this->{'talkid'}",
                            $ctx->[S2::PROPS]->{"text_multiform_opt_delete"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_del.gif", 22, 20));
    }
    if ($key eq "freeze_thread") {
        return $null_link if $this->{'frozen'};
        return $null_link unless LJ::Talk::can_freeze($remote, $u, $post_user, $com_user);
        return LJ::S2::Link("$LJ::SITEROOT/talkscreen.bml?mode=freeze&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                            $ctx->[S2::PROPS]->{"text_multiform_opt_freeze"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_freeze.gif", 22, 20));
    }
    if ($key eq "unfreeze_thread") {
        return $null_link unless $this->{'frozen'};
        return $null_link unless LJ::Talk::can_unfreeze($remote, $u, $post_user, $com_user);
        return LJ::S2::Link("$LJ::SITEROOT/talkscreen.bml?mode=unfreeze&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                            $ctx->[S2::PROPS]->{"text_multiform_opt_unfreeze"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_unfreeze.gif", 22, 20));
    }
    if ($key eq "screen_comment") {
        return $null_link if $this->{'screened'};
        return $null_link unless LJ::Talk::can_screen($remote, $u, $post_user, $com_user);
        return LJ::S2::Link("$LJ::SITEROOT/talkscreen.bml?mode=screen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                            $ctx->[S2::PROPS]->{"text_multiform_opt_screen"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_scr.gif", 22, 20));
    }
    if ($key eq "unscreen_comment") {
        return $null_link unless $this->{'screened'};
        return $null_link unless LJ::Talk::can_unscreen($remote, $u, $post_user, $com_user);
        return LJ::S2::Link("$LJ::SITEROOT/talkscreen.bml?mode=unscreen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                            $ctx->[S2::PROPS]->{"text_multiform_opt_unscreen"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_unscr.gif", 22, 20));
    }

    # added new button
    if ($key eq "unscreen_to_reply") {
        #return $null_link unless $this->{'screened'};
        #return $null_link unless LJ::Talk::can_unscreen($remote, $u, $post_user, $com_user);
        return LJ::S2::Link("$LJ::SITEROOT/talkscreen.bml?mode=unscreen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
                            $ctx->[S2::PROPS]->{"text_multiform_opt_unscreen_to_reply"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_unscr.gif", 22, 20));
    }

    
    if ($key eq "watch_thread" || $key eq "unwatch_thread" || $key eq "watching_parent") {
        return $null_link if $LJ::DISABLED{'esn'};
        return $null_link unless $remote && $remote->can_use_esn;

        if ($key eq "unwatch_thread") {
            return $null_link unless $remote->has_subscription(journal => $u, event => "JournalNewComment", arg2 => $comment->jtalkid);

            my @subs = $remote->has_subscription(journal => $comment->entry->journal,
                                                 event => "JournalNewComment",
                                                 arg2 => $comment->jtalkid);
            my $subscr = $subs[0];
            return $null_link unless $subscr;

            my $auth_token = LJ::Auth->ajax_auth_token($remote, '/__rpc_esn_subs',
                                                       subid  => $subscr->id,
                                                       action => 'delsub');

            my $etypeid = 'LJ::Event::JournalNewComment'->etypeid;

            return LJ::S2::Link("$LJ::SITEROOT/manage/subscriptions/comments.bml?journal=$u->{'user'}&amp;talkid=" . $comment->dtalkid,
                                $ctx->[S2::PROPS]->{"text_multiform_opt_untrack"},
                                LJ::S2::Image("$LJ::IMGPREFIX/btn_tracking.gif", 22, 20, 'Untrack this',
                                              'lj_etypeid'    => $etypeid,
                                              'lj_journalid'  => $u->id,
                                              'lj_subid'      => $subscr->id,
                                              'class'         => 'TrackButton',
                                              'id'            => 'lj_track_btn_' . $dtalkid,
                                              'lj_dtalkid'    => $dtalkid,
                                              'lj_arg2'       => $comment->jtalkid,
                                              'lj_auth_token' => $auth_token));
        }

        return $null_link if $remote->has_subscription(journal => $u, event => "JournalNewComment", arg2 => $comment->jtalkid);

        # at this point, we know that the thread is either not being watched or its parent is being watched
        # in other words, the user is not subscribed to this particular comment

        # see if any parents are being watched
        my $watching_parent = 0;
        while ($comment && $comment->valid && $comment->parenttalkid) {
            # check cache
            $comment->{_watchedby} ||= {};
            my $thread_watched = $comment->{_watchedby}->{$u->{userid}};

            # not cached
            if (! defined $thread_watched) {
                $thread_watched = $remote->has_subscription(journal => $u, event => "JournalNewComment", arg2 => $comment->parenttalkid);
            }

            $watching_parent = 1 if ($thread_watched);

            # cache in this comment object if it's being watched by this user
            $comment->{_watchedby}->{$u->{userid}} = $thread_watched;

            $comment = $comment->parent;
        }

        my $etypeid = 'LJ::Event::JournalNewComment'->etypeid;
        my %subparams = (
                         journalid => $comment->entry->journal->id,
                         etypeid   => $etypeid,
                         arg2      => LJ::Comment->new($comment->entry->journal, dtalkid => $dtalkid)->jtalkid,
                         );
        my $auth_token = LJ::Auth->ajax_auth_token($remote, '/__rpc_esn_subs', action => 'addsub', %subparams);

        my %btn_params = map { ('lj_' . $_, $subparams{$_}) } keys %subparams;

        $btn_params{'class'}         = 'TrackButton';
        $btn_params{'lj_auth_token'} = $auth_token;
        $btn_params{'lj_subid'}      = 0;
        $btn_params{'lj_dtalkid'}    = $dtalkid;
        $btn_params{'id'}            = "lj_track_btn_" . $dtalkid;

        if ($key eq "watch_thread" && !$watching_parent) {
            return LJ::S2::Link("$LJ::SITEROOT/manage/subscriptions/comments.bml?journal=$u->{'user'}&amp;talkid=$dtalkid",
                                $ctx->[S2::PROPS]->{"text_multiform_opt_track"},
                                LJ::S2::Image("$LJ::IMGPREFIX/btn_track.gif", 22, 20, 'Track This', %btn_params));
        }
        if ($key eq "watching_parent" && $watching_parent) {
            return LJ::S2::Link("$LJ::SITEROOT/manage/subscriptions/comments.bml?journal=$u->{'user'}&amp;talkid=$dtalkid",
                                $ctx->[S2::PROPS]->{"text_multiform_opt_track"},
                                LJ::S2::Image("$LJ::IMGPREFIX/btn_tracking_thread.gif", 22, 20, 'Untrack This', %btn_params));
        }
        return $null_link;
    }
    if ($key eq "edit_comment") {
        return $null_link unless $comment->remote_can_edit;
        my $edit_url = $this->{edit_url} || $comment->edit_url;
        return LJ::S2::Link($edit_url,
                            $ctx->[S2::PROPS]->{"text_multiform_opt_edit"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_edit.gif", 22, 20));
    }
    if ($key eq "expand_comments") {
        return $null_link unless $u->show_thread_expander( $remote );
        ## show "Expand" link only if 
        ## 1) the comment is collapsed 
        ## 2) any of comment's children are collapsed
        my $show_expand_link;
        if (!$this->{full} and !$this->{deleted}) {
            $show_expand_link = 1;
        }
        else {
            foreach my $c (@{ $this->{replies} }) {
                if (!$c->{full} and !$c->{deleted}) {
                    $show_expand_link = 1;
                    last;
                }
            }
        }
        return $null_link unless $show_expand_link;
        return LJ::S2::Link("#",        ## actual link is javascript: onclick='....'
                            $ctx->[S2::PROPS]->{"text_comment_expand"});
    }
}

sub Comment__print_multiform_check
{
    my ($ctx, $this) = @_;
    my $tid = $this->{'talkid'} >> 8;
    $S2::pout->("<input type='checkbox' name='selected_$tid' class='ljcomsel' id='ljcomsel_$this->{'talkid'}' />");
}

sub Comment__print_reply_link
{
    my ($ctx, $this, $opts) = @_;
    $opts ||= {};

    my $basesubject = $this->{'subject'};
    $opts->{'basesubject'} = $basesubject;
    $opts->{'target'} ||= $this->{'talkid'};

    _print_quickreply_link($ctx, $this, $opts);
}

*Page__print_reply_link = \&_print_quickreply_link;
*EntryPage__print_reply_link = \&_print_quickreply_link;

sub _print_quickreply_link
{
    my ($ctx, $this, $opts) = @_;

    $opts ||= {};
    
    # one of these had better work
    my $replyurl =  $opts->{'reply_url'} || $this->{'reply_url'} || $this->{'entry'}->{'comments'}->{'post_url'};

    # clean up input:
    my $linktext = LJ::ehtml($opts->{'linktext'}) || "";

    my $target = $opts->{'target'};
    return unless $target =~ /^\w+$/; # if no target specified bail the fuck out

    my $opt_class = $opts->{'class'};
    undef $opt_class unless $opt_class =~ /^[\w\s-]+$/;

    my $opt_img = LJ::CleanHTML::canonical_url($opts->{'img_url'});
    $replyurl = LJ::CleanHTML::canonical_url($replyurl);

    # if they want an image change the text link to the image,
    # and add the text after the image if they specified it as well
    if ($opt_img) {
        # hella robust img options. (width,height,align,alt,title)
        # s2quickreply does it all. like whitaker's mom.
        my $width = $opts->{'img_width'} + 0;
        my $height = $opts->{'img_height'} + 0;
        my $align = $opts->{'img_align'};
        my $alt = LJ::ehtml($opts->{'alt'});
        my $title = LJ::ehtml($opts->{'title'});
        my $border = $opts->{'img_border'} + 0;

        $width  = $width  ? "width=$width" : "";
        $height = $height ? "height=$height" : "";
        $border = $border ne "" ? "border=$border" : "";
        $alt    = $alt    ? "alt=\"$alt\"" : "";
        $title  = $title  ? "title=\"$title\"" : "";
        $align  = $align =~ /^\w+$/ ? "align=\"$align\"" : "";

        $linktext = "<img src=\"$opt_img\" $width $height $align $title $alt $border />$linktext";
    }

    my $basesubject = $opts->{'basesubject'}; #cleaned later

    if ($opt_class) {
        $opt_class = "class=\"$opt_class\"";
    }

    my $page = get_page();
    my $remote = LJ::get_remote();
    LJ::load_user_props($remote, "opt_no_quickreply");
    my $onclick = "";
    unless ($remote->{'opt_no_quickreply'}) {
        my $pid = (int($target)&&$page->{'_type'} eq 'EntryPage') ? int($target /256) : 0;

        $basesubject =~ s/^(Re:\s*)*//i;
        $basesubject = "Re: $basesubject" if $basesubject;
        $basesubject = LJ::ejs($basesubject);
        $onclick = "return quickreply(\"$target\", $pid, \"$basesubject\")";
        $onclick = "onclick='$onclick'";
    }

    $onclick = "" unless $page->{'_type'} eq 'EntryPage';
    $onclick = "" if $LJ::DISABLED{'s2quickreply'};

    # See if we want to force them to change their password
    my $bp = LJ::bad_password_redirect({ 'returl' => 1 });

    if ($bp) {
        $S2::pout->("<a href='$bp'>$linktext</a>");
    } else {
        $S2::pout->("<a $onclick href='$replyurl' $opt_class>$linktext</a>");
    }
}

sub _print_reply_container
{
    my ($ctx, $this, $opts) = @_;

    my $page = get_page();
    return unless $page->{'_type'} eq 'EntryPage';

    my $target = $opts->{'target'};
    undef $target unless $target =~ /^\w+$/;

    my $class = $opts->{'class'} || undef;

    # set target to the dtalkid if no target specified (link will be same)
    my $dtalkid = $this->{'talkid'} || undef;
    $target ||= $dtalkid;
    return if !$target;

    undef $class unless $class =~ /^([\w\s]+)$/;

    if ($class) {
        $class = "class=\"$class\"";
    }

    $S2::pout->("<div $class id=\"ljqrt$target\" style=\"display: none;\"></div>");

    # unless we've already inserted the big qrdiv ugliness, do it.
    unless ($ctx->[S2::SCRATCH]->{'quickreply_printed_div'}++) {
        my $u = $page->{'_u'};
        my $ditemid = $page->{'entry'}{'itemid'} || 0;

        my $userpic = LJ::ehtml($page->{'_picture_keyword'}) || "";
        my $thread = $page->{'viewing_thread'} + 0 || "";
        $S2::pout->(LJ::create_qr_div($u, $ditemid, $page->{'_stylemine'} || 0, $userpic, $thread));
    }
}

*Comment__print_reply_container = \&_print_reply_container;
*EntryPage__print_reply_container = \&_print_reply_container;
*Page__print_reply_container = \&_print_reply_container;

sub Comment__expand_link
{
    my ($ctx, $this, $opts) = @_;
    $opts ||= {};

    my $prop_text = LJ::ehtml($ctx->[S2::PROPS]->{"text_comment_expand"});

    my $text = LJ::ehtml($opts->{text});
    $text =~ s/&amp;nbsp;/&nbsp;/gi; # allow &nbsp; in the text

    my $opt_img = LJ::CleanHTML::canonical_url($opts->{img_url});

    # if they want an image change the text link to the image,
    # and add the text after the image if they specified it as well
    if ($opt_img) {
        my $width = $opts->{img_width};
        my $height = $opts->{img_height};
        my $border = $opts->{img_border};
        my $align = LJ::ehtml($opts->{img_align});
        my $alt = LJ::ehtml($opts->{img_alt}) || $prop_text;
        my $title = LJ::ehtml($opts->{img_title}) || $prop_text;

        $width  = defined $width  && $width  =~ /^\d+$/ ? " width=\"$width\"" : "";
        $height = defined $height && $height =~ /^\d+$/ ? " height=\"$height\"" : "";
        $border = defined $border && $border =~ /^\d+$/ ? " border=\"$border\"" : "";

        $align  = $align =~ /^\w+$/ ? " align=\"$align\"" : "";
        $alt    = $alt   ? " alt=\"$alt\"" : "";
        $title  = $title ? " title=\"$title\"" : "";

        $text = "<img src=\"$opt_img\"$width$height$border$align$title$alt />$text";
    } elsif (!$text) {
        $text = $prop_text;
    }

    my $title = $opts->{title} ? " title='" . LJ::ehtml($opts->{title}) . "'" : "";
    my $class = $opts->{class} ? " class='" . LJ::ehtml($opts->{class}) . "'" : "";

    return "<a href='$this->{thread_url}'$title$class onClick=\"Expander.make(this,'$this->{thread_url}','$this->{talkid}'); return false;\">$text</a>";
}

sub Comment__print_expand_link
{
    $S2::pout->(Comment__expand_link(@_));
}

sub Page__print_trusted
{
    my ($ctx, $this, $key) = @_;

    my $username = $this->{journal}->{username};
    my $fullkey = "$username-$key";

    if ($LJ::TRUSTED_S2_WHITELIST_USERNAMES{$username}) {
        # more restrictive way: username-key
        $S2::pout->(LJ::conf_test($LJ::TRUSTED_S2_WHITELIST{$fullkey}))
            if exists $LJ::TRUSTED_S2_WHITELIST{$fullkey};
    } else {
        # less restrictive way: key
        $S2::pout->(LJ::conf_test($LJ::TRUSTED_S2_WHITELIST{$key}))
            if exists $LJ::TRUSTED_S2_WHITELIST{$key};
    }
}

# class 'date'
sub Date__day_of_week
{
    my ($ctx, $dt) = @_;
    return $dt->{'_dayofweek'} if defined $dt->{'_dayofweek'};
    return $dt->{'_dayofweek'} = LJ::day_of_week($dt->{'year'}, $dt->{'month'}, $dt->{'day'}) + 1;
}
*DateTime__day_of_week = \&Date__day_of_week;

sub Date__compare
{
    my ($ctx, $this, $other) = @_;

    return $other->{year} <=> $this->{year}
           || $other->{month} <=> $this->{month}
           || $other->{day} <=> $this->{day}
           || $other->{hour} <=> $this->{hour}
           || $other->{min} <=> $this->{min}
           || $other->{sec} <=> $this->{sec};
}
*DateTime__compare = \&Date__compare;

my %dt_vars = (
               'm' => "\$time->{month}",
               'mm' => "sprintf('%02d', \$time->{month})",
               'd' => "\$time->{day}",
               'dd' => "sprintf('%02d', \$time->{day})",
               'yy' => "sprintf('%02d', \$time->{year} % 100)",
               'yyyy' => "\$time->{year}",
               'mon' => "\$ctx->[S2::PROPS]->{lang_monthname_short}->[\$time->{month}]",
               'month' => "\$ctx->[S2::PROPS]->{lang_monthname_long}->[\$time->{month}]",
               'da' => "\$ctx->[S2::PROPS]->{lang_dayname_short}->[Date__day_of_week(\$ctx, \$time)]",
               'day' => "\$ctx->[S2::PROPS]->{lang_dayname_long}->[Date__day_of_week(\$ctx, \$time)]",
               'dayord' => "S2::run_function(\$ctx, \"lang_ordinal(int)\", \$time->{day})",
               'H' => "\$time->{hour}",
               'HH' => "sprintf('%02d', \$time->{hour})",
               'h' => "(\$time->{hour} % 12 || 12)",
               'hh' => "sprintf('%02d', (\$time->{hour} % 12 || 12))",
               'min' => "sprintf('%02d', \$time->{min})",
               'sec' => "sprintf('%02d', \$time->{sec})",
               'a' => "(\$time->{hour} < 12 ? 'a' : 'p')",
               'A' => "(\$time->{hour} < 12 ? 'A' : 'P')",
            );

sub _dt_vars_html {
    my $datecode = shift;
    
    return qq{ "/",$dt_vars{yyyy}, "/", $dt_vars{mm}, "/", $dt_vars{dd}, "/" } if $datecode =~ /^(d|dd|dayord)$/;
    return qq{ "/",$dt_vars{yyyy}, "/", $dt_vars{mm}, "/" } if $datecode =~ /^(m|mm|mon|month)$/;
    return qq{ "/",$dt_vars{yyyy}, "/" } if $datecode =~ /^(yy|yyyy)$/;
}
sub Date__date_format
{
    my ($ctx, $this, $fmt, $as_link) = @_;
    $fmt ||= "short";
    # formatted as link is separate from format as not link
    my $c = \$ctx->[S2::SCRATCH]->{'_code_datefmt'}->{$fmt . $as_link};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_datefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"};
    } elsif ($fmt eq "iso") {
        $realfmt = "%%yyyy%%-%%mm%%-%%dd%%";
    }


    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join('',";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { 
            # translate date %%variable%% to value
            my $link = _dt_vars_html( $_ );
            $code .= $as_link && $link
                ? qq{"<a href=\\\"", $link, "\\\">", $dt_vars{$_},"</a>",}
                : $dt_vars{$_} . ",";
        } else { $_ = LJ::ehtml( $_ ); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}
*DateTime__date_format = \&Date__date_format;

sub DateTime__time_format
{
    my ($ctx, $this, $fmt) = @_;
    $fmt ||= "short";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_timefmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"};
    }
    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join('',";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { $code .= $dt_vars{$_} . ","; }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}

sub UserLite__ljuser
{
    my ($ctx, $UserLite, $link_color) = @_;
    my $link_color_string = $link_color ? $link_color->{as_string} : "";
    return LJ::ljuser($UserLite->{_u}, {link_color => $link_color_string});
}

sub UserLite__get_link
{
    my ($ctx, $this, $key) = @_;

    my $linkbar = $this->{_u}->user_link_bar( LJ::get_remote() );

    my $button = sub {
        my $link = $_[0];
        return undef unless $link;

        return LJ::S2::Link($link->{url}, $link->{title}, LJ::S2::Image($link->{image}, 20, 18));
    };

    return $button->( $linkbar->manage_membership ) if $key eq 'manage_membership';
    return $button->( $linkbar->trust ) if $key eq 'trust';
    return $button->( $linkbar->watch ) if $key eq 'watch';
    return $button->( $linkbar->post ) if $key eq 'post_entry';
    return $button->( $linkbar->message ) if $key eq 'message';    
    return $button->( $linkbar->track ) if $key eq 'track';
    return $button->( $linkbar->memories ) if $key eq 'memories';
    return $button->( $linkbar->tellafriend ) if $key eq 'tell_friend';

    # Else?
    return undef;
}
*User__get_link = \&UserLite__get_link;

sub EntryLite__get_link
{
    my ($ctx, $this, $key) = @_;
    my $null_link = { '_type' => 'Link', '_isnull' => 1 };
    
    if ($this->{_type} eq 'Entry') {
        return _Entry__get_link($ctx, $this, $key);
    }
    elsif ($this->{_type} eq 'Comment') {
        return _Comment__get_link($ctx, $this, $key);
    }
    else {
        return $null_link;
    }
}
*Entry__get_link = \&EntryLite__get_link;
*Comment__get_link = \&EntryLite__get_link;

# method for smart converting raw subject to html-link
sub EntryLite__formatted_subject {
    my ($ctx, $this, $attrs) = @_;
    my $subject = $this->{subject};
    
    if ( $this->{_type} eq 'Entry' ) {
        # if an entry does not have a subject, and text_nosubject is not set, return nothing
        return if $subject eq ""  && $ctx->[S2::PROPS]->{text_nosubject} eq "";

        # if an entry does not have a subject, text_nosubject is set, and all_entrysubjects, then use text_nosubject as the subject
        $subject = $ctx->[S2::PROPS]->{text_nosubject}        
            if $subject eq ""
                && $ctx->[S2::PROPS]->{text_nosubject} ne "" 
                && $ctx->[S2::PROPS]->{all_entrysubjects};

        # if an entry does not have a subject, text_nosubject is set, and all_entrysubjects is false, then only return the formatted subject with text_nosubject on the month view
        $subject = $ctx->[S2::PROPS]->{text_nosubject}
            if $subject eq ""
                && $ctx->[S2::PROPS]->{text_nosubject} ne "" 
                && ! $ctx->[S2::PROPS]->{all_entrysubjects} 
                && $LJ::S2::CURR_PAGE->{view} eq 'month';

    } elsif ( $this->{_type} eq "Comment" ) {
        # if a comment does not have a subject, text_nosubject is set, and all_commentsubjects is false, then return nothing
        return if $subject eq "" && $ctx->[S2::PROPS]->{all_commentsubjects} eq "";
        
        # if a comment does not have a subject, text_nosubject is set, and all_commentsubjects is true, then return the formatted subject with text_nosubject
        $subject = $ctx->[S2::PROPS]->{text_nosubject}
            if $subject eq ""
                && $ctx->[S2::PROPS]->{text_nosubject} ne ""
                && $ctx->[S2::PROPS]->{all_commentsubjects};
    }
    
    my $class = $attrs->{class} ? " class=\"".LJ::ehtml($attrs->{class})."\" " : '';
    my $style = $attrs->{style} ? " style=\"".LJ::ehtml($attrs->{style})."\" " : '';

    # if subject has a link, display raw subject
    # TODO: how about other HTML tags?
     if($subject =~ /href/) {
        return $subject;
    } else {        
        return "<a href=\"" . $this->{permalink_url} . "\"$class$style>" 
            . $subject . "</a>";
    }   
}

*Entry__formatted_subject = \&EntryLite__formatted_subject;
*Comment__formatted_subject = \&EntryLite__formatted_subject;

sub EntryLite__get_tags_text
{
    my ($ctx, $this) = @_;
    return LJ::S2::get_tags_text($ctx, $this->{tags}) || "";
}
*Entry__get_tags_text = \&EntryLite__get_tags_text;

sub EntryLite__get_plain_subject
{
    my ($ctx, $this) = @_;
    return $this->{'_plainsubject'} if $this->{'_plainsubject'};
    my $subj = $this->{'subject'};
    LJ::CleanHTML::clean_subject_all(\$subj);
    return $this->{'_plainsubject'} = $subj;
}
*Entry__get_plain_subject = \&EntryLite__get_plain_subject;
*Comment__get_plain_subject = \&EntryLite__get_plain_subject;

sub _Entry__get_link
{
    my ($ctx, $this, $key) = @_;
    my $journal = $this->{'journal'}->{'username'};
    my $poster = $this->{'poster'}->{'username'};
    my $remote = LJ::get_remote();
    my $null_link = { '_type' => 'Link', '_isnull' => 1 };
    my $journalu = LJ::load_user($journal);

    if ($key eq "edit_entry") {
        return $null_link unless $remote && ($remote->{'user'} eq $journal ||
                                        $remote->{'user'} eq $poster ||
                                        LJ::can_manage($remote, LJ::load_user($journal)));
        return LJ::S2::Link("$LJ::SITEROOT/editjournal.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                            $ctx->[S2::PROPS]->{"text_edit_entry"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_edit.gif", 22, 20));
    }
    if ($key eq "edit_tags") {
        return $null_link unless $remote && LJ::Tags::can_add_tags(LJ::load_user($journal), $remote);
        return LJ::S2::Link("$LJ::SITEROOT/edittags.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                            $ctx->[S2::PROPS]->{"text_edit_tags"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_edittags.gif", 22, 20));
    }
    if ($key eq "tell_friend") {
        return $null_link if $LJ::DISABLED{'tellafriend'};
        my $entry = LJ::Entry->new($journalu->{'userid'}, ditemid => $this->{'itemid'});
        return $null_link unless $entry->can_tellafriend($remote);
        return LJ::S2::Link("$LJ::SITEROOT/tools/tellafriend.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                            $ctx->[S2::PROPS]->{"text_tell_friend"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_tellfriend.gif", 22, 20));
    }
    if ($key eq "mem_add") {
        return $null_link if $LJ::DISABLED{'memories'};
        return LJ::S2::Link("$LJ::SITEROOT/tools/memadd.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                            $ctx->[S2::PROPS]->{"text_mem_add"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_memories.gif", 22, 20));
    }
    if ($key eq "nav_prev") {
        return LJ::S2::Link("$LJ::SITEROOT/go.bml?journal=$journal&amp;itemid=$this->{'itemid'}&amp;dir=prev",
                            $ctx->[S2::PROPS]->{"text_entry_prev"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_prev.gif", 22, 20));
    }
    if ($key eq "nav_next") {
        return LJ::S2::Link("$LJ::SITEROOT/go.bml?journal=$journal&amp;itemid=$this->{'itemid'}&amp;dir=next",
                            $ctx->[S2::PROPS]->{"text_entry_next"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_next.gif", 22, 20));
    }
    if ($key eq "flag") {
        return $null_link unless LJ::is_enabled("content_flag");

        my $entry = LJ::Entry->new($journalu, ditemid => $this->{itemid});
        return $null_link unless $remote && $remote->can_see_content_flag_button( content => $entry );
        return LJ::S2::Link(LJ::ContentFlag->adult_flag_url($entry),
                            $ctx->[S2::PROPS]->{"text_flag"},
                            LJ::S2::Image("$LJ::IMGPREFIX/button-flag.gif", 22, 20));
    }

    my $etypeid          = 'LJ::Event::JournalNewComment'->etypeid;
    my $newentry_etypeid = 'LJ::Event::JournalNewEntry'->etypeid;

    my ($newentry_sub) = $remote ? $remote->has_subscription(
                                                             journalid      => $journalu->id,
                                                             event          => "JournalNewEntry",
                                                             require_active => 1,
                                                             ) : undef;

    my $newentry_auth_token;

    if ($newentry_sub) {
        $newentry_auth_token = LJ::Auth->ajax_auth_token($remote, '/__rpc_esn_subs',
                                                         subid     => $newentry_sub->id,
                                                         action    => 'delsub',
                                                         );
    } elsif ($remote) {
        $newentry_auth_token = LJ::Auth->ajax_auth_token($remote, '/__rpc_esn_subs',
                                                         journalid => $journalu->id,
                                                         action    => 'addsub',
                                                         etypeid   => $newentry_etypeid,
                                                         );
    }

    if ($key eq "watch_comments") {
        return $null_link if $LJ::DISABLED{'esn'};
        return $null_link unless $remote && $remote->can_use_esn;
        return $null_link if $remote->has_subscription(
                                                       journal => LJ::load_user($journal),
                                                       event   => "JournalNewComment",
                                                       arg1    => $this->{'itemid'},
                                                       arg2    => 0,
                                                       require_active => 1,
                                                       );

        my $auth_token = LJ::Auth->ajax_auth_token($remote, '/__rpc_esn_subs',
                                                   journalid => $journalu->id,
                                                   action    => 'addsub',
                                                   etypeid   => $etypeid,
                                                   arg1      => $this->{itemid},
                                                   );

        return LJ::S2::Link("$LJ::SITEROOT/manage/subscriptions/entry.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                            $ctx->[S2::PROPS]->{"text_watch_comments"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_track.gif", 22, 20, 'Track This',
                                          'lj_journalid'        => $journalu->id,
                                          'lj_etypeid'          => $etypeid,
                                          'lj_subid'            => 0,
                                          'lj_arg1'             => $this->{itemid},
                                          'lj_auth_token'       => $auth_token,
                                          'lj_newentry_etypeid' => $newentry_etypeid,
                                          'lj_newentry_token'   => $newentry_auth_token,
                                          'lj_newentry_subid'   => $newentry_sub ? $newentry_sub->id : 0,
                                          'class'               => 'TrackButton'));
    }
    if ($key eq "unwatch_comments") {
        return $null_link if $LJ::DISABLED{'esn'};
        return $null_link unless $remote && $remote->can_use_esn;
        my @subs = $remote->has_subscription(
                                             journal => LJ::load_user($journal),
                                             event => "JournalNewComment",
                                             arg1 => $this->{'itemid'},
                                             arg2 => 0,
                                             require_active => 1,
                                             );
        my $subscr = $subs[0];
        return $null_link unless $subscr;

        my $auth_token = LJ::Auth->ajax_auth_token($remote, '/__rpc_esn_subs',
                                                   subid  => $subscr->id,
                                                   action => 'delsub');

        return LJ::S2::Link("$LJ::SITEROOT/manage/subscriptions/entry.bml?journal=$journal&amp;itemid=$this->{'itemid'}",
                            $ctx->[S2::PROPS]->{"text_unwatch_comments"},
                            LJ::S2::Image("$LJ::IMGPREFIX/btn_tracking.gif", 22, 20, 'Untrack this',
                                          'lj_journalid'        => $journalu->id,
                                          'lj_subid'            => $subscr->id,
                                          'lj_etypeid'          => $etypeid,
                                          'lj_arg1'             => $this->{itemid},
                                          'lj_auth_token'       => $auth_token,
                                          'lj_newentry_etypeid' => $newentry_etypeid,
                                          'lj_newentry_token'   => $newentry_auth_token,
                                          'lj_newentry_subid'   => $newentry_sub ? $newentry_sub->id : 0,
                                          'class'               => 'TrackButton'));
    }
}

sub Entry__plain_subject
{
    my ($ctx, $this) = @_;
    return $this->{'_subject_plain'} if defined $this->{'_subject_plain'};
    $this->{'_subject_plain'} = $this->{'subject'};
    LJ::CleanHTML::clean_subject_all(\$this->{'_subject_plain'});
    return $this->{'_subject_plain'};
}

sub EntryPage__print_multiform_actionline
{
    my ($ctx, $this) = @_;
    return unless $this->{'multiform_on'};
    my $pr = $ctx->[S2::PROPS];
    $S2::pout->($pr->{'text_multiform_des'} . "\n" .
                LJ::html_select({'name' => 'mode' },
                                "" => "",
                                map { $_ => $pr->{"text_multiform_opt_$_"} }
                                qw(unscreen screen delete deletespam)) . "\n" .
                LJ::html_submit('', $pr->{'text_multiform_btn'},
                                { "onclick" =>
                                      'return ((document.multiform.mode.value != "delete" ' .
                                      '&& document.multiform.mode.value != "deletespam")) ' .
                                      "|| confirm(\"" . LJ::ejs($pr->{'text_multiform_conf_delete'}) . "\");" }));
}

sub EntryPage__print_multiform_end
{
    my ($ctx, $this) = @_;
    return unless $this->{'multiform_on'};
    $S2::pout->("</form>");
}

sub EntryPage__print_multiform_start
{
    my ($ctx, $this) = @_;
    return unless $this->{'multiform_on'};
    $S2::pout->("<form style='display: inline' method='post' action='$LJ::SITEROOT/talkmulti.bml' name='multiform'>\n" .
                LJ::html_hidden("ditemid", $this->{'entry'}->{'itemid'},
                                "journal", $this->{'entry'}->{'journal'}->{'username'}) . "\n");
}

sub Page__print_control_strip
{
    my ($ctx, $this) = @_;

    return "" unless $LJ::USE_CONTROL_STRIP;
    my $control_strip = LJ::control_strip(user => $LJ::S2::CURR_PAGE->{'journal'}->{'_u'}->{'user'});

    return "" unless $control_strip;
    $S2::pout->($control_strip);
}
*RecentPage__print_control_strip = \&Page__print_control_strip;
*DayPage__print_control_strip = \&Page__print_control_strip;
*MonthPage__print_control_strip = \&Page__print_control_strip;
*YearPage__print_control_strip = \&Page__print_control_strip;
*FriendsPage__print_control_strip = \&Page__print_control_strip;
*EntryPage__print_control_strip = \&Page__print_control_strip;
*ReplyPage__print_control_strip = \&Page__print_control_strip;
*TagsPage__print_control_strip = \&Page__print_control_strip;

sub Page__print_hbox_top
{
    my $args = _get_ad_box_args(@_);
    return unless $args;
    $args->{location} = 's2.top';
    my $ad_html = LJ::get_ads($args);
    $S2::pout->($ad_html) if $ad_html;
}

sub Page__print_hbox_bottom
{
    my $args = _get_ad_box_args(@_);
    return unless $args;
    $args->{location} = 's2.bottom';
    my $ad_html = LJ::get_ads($args);
    $S2::pout->($ad_html) if $ad_html;
}

sub Page__print_vbox {
    my $args = _get_ad_box_args(@_);
    return unless $args;
    $args->{location} = 's2.vertical';
    my $ad_html = LJ::get_ads($args);
    $S2::pout->($ad_html) if $ad_html;
}

sub Page__print_ad_box {
    my ($ctx, $this, $location) = @_;
    my $args = _get_ad_box_args($ctx, $this);
    return unless $args;
    $args->{location} = $location;
    my $ad_html = LJ::get_ads($args);
    $S2::pout->($ad_html) if $ad_html;
}

sub Entry__print_ebox {
    my $args = _get_Entry_ebox_args(@_);
    return unless $args;
    my $ad_html = LJ::get_ads($args);
    $LJ::REQ_GLOBAL{ebox_count}++;
    $S2::pout->($ad_html) if $ad_html;
}

sub _get_colors_for_ad {
    my $ctx = shift;

    # Load colors from the layout and remove the # in front of them
    my ($bgcolor, $fgcolor, $bordercolor, $linkcolor);
    my $bgcolor_prop = S2::get_property_value($ctx, "theme_bgcolor");
    my $fgcolor_prop = S2::get_property_value($ctx, "theme_fgcolor");
    my $bordercolor_prop = S2::get_property_value($ctx, "theme_bordercolor");
    my $linkcolor_prop = S2::get_property_value($ctx, "theme_linkcolor");

    if ($bgcolor_prop) {
        $bgcolor = $bgcolor_prop->{as_string};
        $bgcolor =~ s/^#//;
    }
    if ($fgcolor_prop) {
        $fgcolor = $fgcolor_prop->{as_string};
        $fgcolor =~ s/^#//;
    }
    if ($bordercolor_prop) {
        $bordercolor = $bordercolor_prop->{as_string};
        $bordercolor =~ s/^#//;
    }
    if ($linkcolor_prop) {
        $linkcolor = $linkcolor_prop->{as_string};
        $linkcolor =~ s/^#//;
    }

    my %colors = (
        bgcolor     => $bgcolor,
        fgcolor     => $fgcolor,
        bordercolor => $bordercolor,
        linkcolor   => $linkcolor,
    );

    return \%colors;
}

# deprecated, should use print_(v|h)box
sub Page__print_ad
{
    my ($ctx, $this, $type) = @_;

    #my $ad = '';
    #return '' unless $ad;
    #$S2::pout->($ad);
}

# map vbox/hbox/ebox methods into *Page classes
foreach my $class (qw(RecentPage FriendsPage YearPage MonthPage DayPage EntryPage ReplyPage TagsPage)) {
    foreach my $func (qw(print_ad print_vbox print_hbox_top print_hbox_bottom print_ebox)) {
        ##
        ## Oops, years later after this code was written, an error is found:
        ## the argument string to eval must have an extra \:
        ##      "*${class}__$func = \\&Page__$func"; 
        ## eval "*${class}__$func = \&Page__$func";
        ##
        ## How did it work all this time?
        ##
    }
}


sub Page__visible_tag_list
{
    my ($ctx, $this, $limit) = @_;
    return $this->{'_visible_tag_list'}
        if defined $this->{'_visible_tag_list'};

    my $remote = LJ::get_remote();
    my $u = $LJ::S2::CURR_PAGE->{'_u'};
    return [] unless $u;

    my $tags = LJ::Tags::get_usertags($u, { remote => $remote });
    return [] unless $tags;

    my @taglist;
    foreach my $kwid (keys %{$tags}) {
        # only show tags for display
        next unless $tags->{$kwid}->{display};

        # create tag object
        push @taglist, LJ::S2::TagDetail($u, $kwid => $tags->{$kwid});
    }

    if ($limit) {
        @taglist = sort { $b->{use_count} <=> $a->{use_count} } @taglist;
        @taglist = splice @taglist, 0, $limit;
    }

    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;
    return $this->{'_visible_tag_list'} = \@taglist;
}
*RecentPage__visible_tag_list = \&Page__visible_tag_list;
*DayPage__visible_tag_list = \&Page__visible_tag_list;
*MonthPage__visible_tag_list = \&Page__visible_tag_list;
*YearPage__visible_tag_list = \&Page__visible_tag_list;
*FriendsPage__visible_tag_list = \&Page__visible_tag_list;
*EntryPage__visible_tag_list = \&Page__visible_tag_list;
*ReplyPage__visible_tag_list = \&Page__visible_tag_list;
*TagsPage__visible_tag_list = \&Page__visible_tag_list;

sub Page__get_latest_month
{
    my ($ctx, $this) = @_;
    return $this->{'_latest_month'} if defined $this->{'_latest_month'};
    my $counts = LJ::S2::get_journal_day_counts($this);

    # defaults to current year/month
    my @now = gmtime(time);
    my ($curyear, $curmonth) = ($now[5]+1900, $now[4]+1);
    my ($year, $month) = ($curyear, $curmonth);

    # only want to look at current years, not future-dated posts
    my @years = grep { $_ <= $curyear } sort { $a <=> $b } keys %$counts;
    if (@years) {
        # year/month of last post
        $year = $years[-1];

        # we'll take any month of previous years, or anything up to the current month
        $month = (grep { $year < $curyear || $_ <= $curmonth } sort { $a <=> $b } keys %{$counts->{$year}})[-1];
    }

    return $this->{'_latest_month'} = LJ::S2::YearMonth($this, {
        'year' => $year,
        'month' => $month,
    });
}
*RecentPage__get_latest_month = \&Page__get_latest_month;
*DayPage__get_latest_month = \&Page__get_latest_month;
*MonthPage__get_latest_month = \&Page__get_latest_month;
*YearPage__get_latest_month = \&Page__get_latest_month;
*FriendsPage__get_latest_month = \&Page__get_latest_month;
*EntryPage__get_latest_month = \&Page__get_latest_month;
*ReplyPage__get_latest_month = \&Page__get_latest_month;

sub palimg_modify
{
    my ($ctx, $filename, $items) = @_;
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::PALIMGROOT/$filename";
    return $url unless $items && @$items;
    return undef if @$items > 7;
    $url .= "/p";
    foreach my $pi (@$items) {
        die "Can't modify a palette index greater than 15 with palimg_modify\n" if
            $pi->{'index'} > 15;
        $url .= sprintf("%1x%02x%02x%02x",
                        $pi->{'index'},
                        $pi->{'color'}->{'r'},
                        $pi->{'color'}->{'g'},
                        $pi->{'color'}->{'b'});
    }
    return $url;
}

sub palimg_tint
{
    my ($ctx, $filename, $bcol, $dcol) = @_;  # bright color, dark color [opt]
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::PALIMGROOT/$filename";
    $url .= "/pt";
    foreach my $col ($bcol, $dcol) {
        next unless $col;
        $url .= sprintf("%02x%02x%02x",
                        $col->{'r'}, $col->{'g'}, $col->{'b'});
    }
    return $url;
}

sub palimg_gradient
{
    my ($ctx, $filename, $start, $end) = @_;
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::PALIMGROOT/$filename";
    $url .= "/pg";
    foreach my $pi ($start, $end) {
        next unless $pi;
        $url .= sprintf("%02x%02x%02x%02x",
                        $pi->{'index'},
                        $pi->{'color'}->{'r'},
                        $pi->{'color'}->{'g'},
                        $pi->{'color'}->{'b'});
    }
    return $url;
}

sub userlite_base_url
{
    my ($ctx, $UserLite) = @_;
    my $u = $UserLite->{_u};
    return "#"
            unless $UserLite && $u;
    return $u->journal_base;
}

sub userlite_as_string
{
    my ($ctx, $UserLite) = @_;
    return LJ::ljuser($UserLite->{'_u'});
}

sub PalItem
{
    my ($ctx, $idx, $color) = @_;
    return undef unless $color && $color->{'_type'} eq "Color";
    return undef unless $idx >= 0 && $idx <= 255;
    return {
        '_type' => 'PalItem',
        'color' => $color,
        'index' => $idx+0,
    };
}

sub YearMonth__month_format
{
    my ($ctx, $this, $fmt, $as_link) = @_;
    $fmt ||= "long";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_monthfmt'}->{$fmt . $as_link};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_month_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_month_$fmt"};
    }

    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join('',";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { 
            # translate date %%variable%% to value
            my $link = _dt_vars_html( $_ );
            $code .= $as_link && $link
                ? qq{"<a href=\\\"", $link, "\\\">", $dt_vars{$_},"</a>",}
                : $dt_vars{$_} . ",";
        } else { $_ = LJ::ehtml( $_ ); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}

sub Image__set_url {
    my ($ctx, $img, $newurl) = @_;
    $img->{'url'} = LJ::eurl($newurl);
}

sub ItemRange__url_of
{
    my ($ctx, $this, $n) = @_;
    return "" unless ref $this->{'_url_of'} eq "CODE";
    return $this->{'_url_of'}->($n+0);
}

sub UserLite__equals
{
    return $_[1]->{'_u'}{'userid'} == $_[2]->{'_u'}{'userid'};
}
*User__equals = \&UserLite__equals;
*Friend__equals = \&UserLite__equals;

sub string__index
{
    use utf8;
    my ($ctx, $this, $substr, $position) = @_;
    return index( $this, $substr, $position );
}

sub string__substr
{
    my ($ctx, $this, $start, $length) = @_;
    
    use Encode qw/decode_utf8 encode_utf8/;
    my $ustr = decode_utf8($this);
    my $result = substr($ustr, $start, $length);
    return encode_utf8($result);
}

sub string__length
{
    use utf8;
    my ($ctx, $this) = @_;
    return length($this);
}

sub string__lower
{
    use utf8;
    my ($ctx, $this) = @_;
    return lc($this);
}

sub string__upper
{
    use utf8;
    my ($ctx, $this) = @_;
    return uc($this);
}

sub string__upperfirst
{
    use utf8;
    my ($ctx, $this) = @_;
    return ucfirst($this);
}

sub string__starts_with
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /^\Q$str\E/;
}

sub string__ends_with
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /\Q$str\E$/;
}

sub string__contains
{
    use utf8;
    my ($ctx, $this, $str) = @_;
    return $this =~ /\Q$str\E/;
}

sub string__replace
{
    use utf8;
    my ($ctx, $this, $find, $replace) = @_;
    $this =~ s/\Q$find\E/\Q$replace\E/g;
    return $this;
}

sub string__split
{
    use utf8;
    my ($ctx, $this, $splitby) = @_;
    my @result = split /\Q$splitby\E/, $this;
    return \@result;
}

sub string__repeat
{
    use utf8;
    my ($ctx, $this, $num) = @_;
    $num += 0;
    my $size = length($this) * $num;
    return "[too large]" if $size > 5000;
    return $this x $num;
}

sub string__compare
{
    use utf8; # Does this actually make any difference here?
    my ($ctx, $this, $other) = @_;
    return $other cmp $this;
}

sub string__css_length_value
{
    my ($ctx, $this) = @_;

    $this =~ s/^\s+//g;
    $this =~ s/\s+$//g;

    # Is it one of the acceptable keywords?
    my %allowed_keywords = map { $_ => 1 } qw(larger smaller xx-small x-small small medium large x-large xx-large auto inherit);
    return $this if $allowed_keywords{$this};

    # Is it a number followed by an acceptable unit?
    my %allowed_units = map { $_ => 1 } qw(em ex px in cm mm pt pc %);
    return $this if $this =~ /^[\-\+]?(\d*\.)?\d+([a-z]+|\%)$/ && $allowed_units{$2};

    # Is it zero?
    return "0" if $this =~ /^(0*\.)?0+$/;

    return '';
}

sub string__css_string
{
    my ($ctx, $this) = @_;

    $this =~ s/\\/\\\\/g;
    $this =~ s/\"/\\\"/g;

    return '"'.$this.'"';

}

sub string__css_url_value
{
    my ($ctx, $this) = @_;

    return '' if $this !~ m!^https?://!;
    return '' if $this =~ /[^a-z0-9A-Z\.\@\$\-_\.\+\!\*'\(\),&=#;:\?\/\%~]/;
    return 'url('.string__css_string($ctx, $this).')';
}

sub string__css_keyword
{
    my ($ctx, $this, $allowed) = @_;

    $this =~ s/^\s+//g;
    $this =~ s/\s+$//g;

    return '' if $this =~ /[^a-z\-]/i;

    if ($allowed) {
        # If we've got an arrayref, transform it into a hashref.
        $allowed = { map { $_ => 1 } @$allowed } if ref $allowed eq 'ARRAY';
        return '' unless $allowed->{$this};
    }

    return lc($this);
}

sub string__css_keyword_list
{
    my ($ctx, $this, $allowed) = @_;

    $this =~ s/^\s+//g;
    $this =~ s/\s+$//g;

    my @in = split(/\s+/, $this);
    my @out = ();

    # Do the transform of $allowed to a hash once here rather than once for each keyword
    $allowed = { map { $_ => 1 } @$allowed } if ref $allowed eq 'ARRAY';

    foreach my $kw (@in) {
        $kw = string__css_keyword($ctx, $kw, $allowed);
        push @out, $kw if $kw;
    }

    return join(' ', @out);
}


1;
