#!/usr/bin/perl
#
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

package LJ::S2;

use strict;
use DW;
use lib DW->home . "/src/s2";
use S2;
use S2::Color;
use S2::Checker;
use S2::Compiler;
use HTMLCleaner;
use LJ::CSS::Cleaner;
use LJ::S2::RecentPage;
use LJ::S2::YearPage;
use LJ::S2::DayPage;
use LJ::S2::FriendsPage;
use LJ::S2::MonthPage;
use LJ::S2::EntryPage;
use LJ::S2::ReplyPage;
use LJ::S2::TagsPage;
use LJ::S2::IconsPage;
use Storable;
use Apache2::Const qw/ :common /;
use POSIX ();

use DW::SiteScheme;
use LJ::PageStats;

# TEMP HACK
sub get_s2_reader {
    return LJ::get_dbh( "s2slave", "slave", "master" );
}

sub make_journal {
    my ( $u, $styleid, $view, $remote, $opts ) = @_;

    my $apache_r = $opts->{'r'};
    my $ret;
    $LJ::S2::ret_ref = \$ret;

    my ( $entry, $page, $use_modtime );

    if ( $view eq "res" ) {
        if ( $opts->{'pathextra'} =~ m!/(\d+)/stylesheet$! ) {
            $styleid = $1 unless $styleid && $styleid eq "sitefeeds";

            $entry = [
                qw( Page::print_contextual_stylesheet() Page::print_default_stylesheet() print_stylesheet() Page::print_theme_stylesheet() )
            ];
            $opts->{'contenttype'} = 'text/css';
            $use_modtime = 1;
        }
        else {
            $opts->{'handler_return'} = 404;
            return;
        }
    }

    $u->{'_s2styleid'} = ( $styleid && $styleid =~ /^\d+$/ ) ? $styleid + 0 : 0;

    # try to get an S2 context
    my $ctx =
        s2_context( $styleid, use_modtime => $use_modtime, u => $u, style_u => $opts->{style_u} );
    unless ($ctx) {
        $opts->{'handler_return'} = OK;
        return;
    }

    # see also Apache/LiveJournal.pm
    my $lang = $LJ::DEFAULT_LANG;

    # note that's it's very important to pass LJ::Lang::get_text here explicitly
    # rather than relying on BML::set_language's fallback mechanism, which won't
    # work in this context since BML::cur_req won't be loaded if no BML requests
    # have been served from this Apache process yet
    BML::set_language( $lang, \&LJ::Lang::get_text );

    # let layouts disable EntryPage / ReplyPage, using the siteviews version
    # instead.  We may also have explicitly asked to use siteviews by the caller
    my $style_u = $opts->{style_u} || $u;

    if (
        !LJ::S2::use_journalstyle_entry_page( $style_u, $ctx )
        && ( $view eq "entry" || $view eq "reply" )    # reply / entry page
        || !LJ::S2::use_journalstyle_icons_page( $style_u, $ctx ) && ( $view eq "icons" )    # icons
        || (
            ( $view eq "entry" || $view eq "reply" )    # make sure capability supports it
            && !LJ::get_cap( ( $opts->{'checkremote'} ? $remote : $u ), "s2view$view" )
        )
        )
    {
        $styleid = "siteviews";

        # we changed the styleid, so generate a new context
        $ctx = s2_context(
            "siteviews",
            use_modtime => $use_modtime,
            u           => $u,
            style_u     => $opts->{style_u}
        );
    }

    if ( $styleid && $styleid eq "siteviews" ) {
        $apache_r->notes->{'no_control_strip'} = 1;

        ${ $opts->{'handle_with_siteviews_ref'} } = 1;
        $opts->{siteviews_extra_content} ||= {};

        my $siteviews_class = {
            '_type'           => "Siteviews",
            '_input_captures' => [],
            '_content'        => $opts->{siteviews_extra_content},
        };

        $ctx->[S2::SCRATCH]->{siteviews_enabled} = 1;
        $ctx->[S2::PROPS]->{SITEVIEWS}           = $siteviews_class;
    }

    # setup tags backwards compatibility
    unless ( $ctx->[S2::PROPS]->{'tags_aware'} ) {
        $opts->{enable_tags_compatibility} = 1;
    }

    $opts->{'ctx'} = $ctx;
    $LJ::S2::CURR_CTX = $ctx;

    foreach ( "name", "url", "urlname" ) { LJ::text_out( \$u->{$_} ); }

    $u->{'_journalbase'} = $u->journal_base( vhost => $opts->{'vhost'} );

    my $view2class = {
        lastn   => "RecentPage",
        archive => "YearPage",
        day     => "DayPage",
        read    => "FriendsPage",
        month   => "MonthPage",
        reply   => "ReplyPage",
        entry   => "EntryPage",
        tag     => "TagsPage",
        network => "FriendsPage",
        icons   => "IconsPage",
    };

    if ( my $class = $view2class->{$view} ) {
        $entry = "${class}::print()";
        no strict 'refs';

        # this will fail (bogus method), but in non-apache context will bring
        # in the right file because of Class::Autouse above
        eval { "LJ::S2::$class"->force_class_autouse; };
        my $cv = *{"LJ::S2::$class"}{CODE};
        die "No LJ::S2::$class function!" unless $cv;
        $page = $cv->( $u, $remote, $opts );
    }

    return if $opts->{'suspendeduser'};
    return if $opts->{'handler_return'};

    # the friends mode=live returns raw HTML in $page, in which case there's
    # nothing to "run" with s2_run.  so $page isn't runnable, return it now.
    # but we have to make sure it's defined at all first, otherwise things
    # like print_stylesheet() won't run, which don't have an method invocant
    return $page if $page && ref $page ne 'HASH';

    LJ::set_active_resource_group('jquery');

    # Control strip
    my $show_control_strip = LJ::Hooks::run_hook('show_control_strip');
    if ($show_control_strip) {
        LJ::Hooks::run_hook('control_strip_stylesheet_link');

        # used if we're using our jquery library
        LJ::need_res(
            { group => "jquery" }, qw(
                js/md5.js
                js/login-jquery.js
                )
        );
    }

    LJ::need_res(
        { group => "jquery" }, qw(
            js/jquery/jquery.ui.core.js
            js/jquery/jquery.ui.widget.js
            js/jquery/jquery.ui.tooltip.js
            js/jquery/jquery.ui.button.js
            js/jquery/jquery.ui.dialog.js
            js/jquery/jquery.ui.position.js
            js/jquery.ajaxtip.js

            stc/jquery/jquery.ui.core.css
            stc/jquery/jquery.ui.tooltip.css
            stc/jquery/jquery.ui.button.css
            stc/jquery/jquery.ui.dialog.css
            stc/jquery/jquery.ui.theme.smoothness.css

            js/jquery.poll.js
            js/journals/jquery.tag-nav.js

            js/jquery.mediaplaceholder.js
            )
    );

    # Include any head stc or js head content
    LJ::Hooks::run_hooks( "need_res_for_journals", $u );
    my $extra_js = LJ::statusvis_message_js($u);

    # this will cause double-JS and likely cause issues if called during siteviews
    # as this is done once the page is out of S2's control.
    $page->{head_content} .= LJ::res_includes()
        unless $ctx->[S2::SCRATCH]->{siteviews_enabled};

    $page->{head_content} .= $extra_js;
    $page->{head_content} .= LJ::PageStats->new->render_head('journal');

    # inject the control strip JS, but only after any libraries have been injected
    $page->{head_content} .= LJ::control_strip_js_inject( user => $u->user )
        if $show_control_strip;

    s2_run( $apache_r, $ctx, $opts, $entry, $page );

    if ( ref $opts->{'errors'} eq "ARRAY" && @{ $opts->{'errors'} } ) {
        return join( '',
            "Errors occurred processing this page:<ul>",
            map { "<li>$_</li>" } @{ $opts->{'errors'} }, "</ul>" );
    }

    # unload layers that aren't public
    LJ::S2::cleanup_layers($ctx);

    # If there's an entry for contenttype in the context 'scratch'
    # area, copy it into the "real" content type field.
    $opts->{contenttype} = $ctx->[S2::SCRATCH]->{contenttype}
        if defined $ctx->[S2::SCRATCH]->{contenttype};

    $ret = $page->{'LJ_cmtinfo'} . $ret
        if $opts->{'need_cmtinfo'} and defined $page->{'LJ_cmtinfo'};

    return $ret;
}

sub s2_run {
    my ( $apache_r, $ctx, $opts, $entry, $page ) = @_;
    $opts ||= {};

    local $LJ::S2::CURR_CTX = $ctx;
    my $ctype = $opts->{'contenttype'} || "text/html";
    my $cleaner;

    my $cleaner_output = sub {
        my $text = shift;

        # expand lj-embed tags
        if ( $text =~ /lj\-embed/i ) {

            # find out what journal we're looking at
            my $apache_r = eval { BML::get_request() };
            if ( $apache_r && $apache_r->notes->{journalid} ) {
                my $journal = LJ::load_userid( $apache_r->notes->{journalid} );

                # expand tags
                LJ::EmbedModule->expand_entry( $journal, \$text )
                    if $journal;
            }
        }

        $$LJ::S2::ret_ref .= $text;
    };

    if ( $ctype =~ m!^text/html! ) {
        $cleaner = HTMLCleaner->new(
            'output'           => $cleaner_output,
            'valid_stylesheet' => \&LJ::valid_stylesheet_url,
        );
    }

    my $send_header = sub {
        my $status = $ctx->[S2::SCRATCH]->{'status'} || 200;
        $apache_r->status($status);
        $apache_r->content_type( $ctx->[S2::SCRATCH]->{'ctype'} || $ctype );

        # FIXME: not necessary in ModPerl 2.0?
        #$apache_r->send_http_header();
    };

    my $need_flush;

    my $print_ctr = 0;    # every 'n' prints we check the recursion depth

    my $out_straight = sub {

        # Hacky: forces text flush.  see:
        # http://zilla.livejournal.org/906
        if ($need_flush) {
            $cleaner->parse("<!-- -->");
            $need_flush = 0;
        }
        my $output = $_[0];
        $output = '' unless defined $output;
        $$LJ::S2::ret_ref .= $output;
        S2::check_depth() if ++$print_ctr % 8 == 0;
    };
    my $out_clean = sub {
        my $text = shift;
        $text = '' unless defined $text;

        $cleaner->parse($text);

        $need_flush = 1;
        S2::check_depth() if ++$print_ctr % 8 == 0;
    };
    S2::set_output($out_straight);
    S2::set_output_safe( $cleaner ? $out_clean : $out_straight );

    $LJ::S2::CURR_PAGE = $page;
    $LJ::S2::RES_MADE  = 0;       # standard resources (Image objects) made yet

    my $css_mode = $ctype eq "text/css";

    S2::Builtin::LJ::start_css($ctx) if $css_mode;
    eval {
        if ( ref $entry ) {
            foreach (@$entry) {
                S2::run_code( $ctx, $_, $page )
                    if S2::function_exists( $ctx, $_ );
            }
        }
        else {
            S2::run_code( $ctx, $entry, $page );
        }
    };
    S2::Builtin::LJ::end_css($ctx) if $css_mode;

    $LJ::S2::CURR_PAGE = undef;

    if ($@) {
        my $error = $@;
        $error =~ s/\n/<br \/>\n/g;
        S2::pout("<b>Error running style:</b> $error");
        return 0;
    }
    $cleaner->eof if $cleaner;    # flush any remaining text/tag not yet spit out
    return 1;
}

# <LJFUNC>
# name: LJ::S2::make_link
# des: Takes a group of key=value pairs to append to a URL.
# returns: The finished URL.
# args: url, vars
# des-url: A string with the URL to append to.  The URL
#          should not have a question mark in it.
# des-vars: A hashref of the key=value pairs to append with.
# </LJFUNC>
sub make_link {
    my $url    = shift;
    my $vars   = shift;
    my $append = "?";
    foreach ( keys %$vars ) {
        next if ( $vars->{$_} eq "" );
        $url .= "${append}${_}=$vars->{$_}";
        $append = "&";
    }
    return $url;
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
    my ( $ctx, $taglist ) = @_;
    return undef unless $ctx && $taglist;
    return "" unless @$taglist;

    # now get the customized tag text and insert the tag list and append to body
    my $tags    = join( ', ', map { "<a rel='tag' href='$_->{url}'>$_->{name}</a>" } @$taglist );
    my $tagtext = S2::get_property_value( $ctx, 'text_tags' );
    $tagtext =~ s/#/$tags/;
    return "<div class='ljtags'>$tagtext</div>";
}

# returns hashref { lid => $u }; undef on error
sub get_layer_owners {
    my @lids = map { $_ + 0 } @_;
    return {} unless @lids;

    my $ret  = {};                           # lid => uid/$u
    my %need = ( map { $_ => 1 } @lids );    # layerid => 1

    # see what we can get out of memcache first
    my @keys;
    push @keys, [ $_, "s2lo:$_" ] foreach @lids;
    my $memc = LJ::MemCache::get_multi(@keys);
    foreach my $lid (@lids) {
        if ( my $uid = $memc->{"s2lo:$lid"} ) {
            delete $need{$lid};
            $ret->{$lid} = $uid;
        }
    }

    # if we still need any from the database, get them now
    if (%need) {
        my $dbh = LJ::get_db_writer();
        my $in  = join( ',', keys %need );
        my $res =
            $dbh->selectall_arrayref("SELECT s2lid, userid FROM s2layers WHERE s2lid IN ($in)");
        die "Database error in LJ::S2::get_layer_owners: " . $dbh->errstr . "\n" if $dbh->err;

        foreach my $row (@$res) {

            # save info and add to memcache
            $ret->{ $row->[0] } = $row->[1];
            LJ::MemCache::add( [ $row->[0], "s2lo:$row->[0]" ], $row->[1] );
        }
    }

    # now load these users; they're likely process cached anyway, so it should
    # be pretty fast
    my $us = LJ::load_userids( values %$ret );
    foreach my $lid ( keys %$ret ) {
        $ret->{$lid} = $us->{ $ret->{$lid} };
    }
    return $ret;
}

# returns max comptime of all lids requested to be loaded
sub load_layers {
    my @lids = map { $_ + 0 } @_;
    return 0 unless @lids;

    my $maxtime = 0;    # to be returned

    # figure out what is process cached...that goes to DB always
    # if it's not in process cache, hit memcache first
    my @from_db;      # lid, lid, lid, ...
    my @need_memc;    # lid, lid, lid, ...

    # initial sweep, anything loaded for less than 60 seconds is golden
    # if dev server, only cache layers for 1 second
    foreach my $lid (@lids) {
        if ( my $loaded = S2::layer_loaded( $lid, $LJ::IS_DEV_SERVER ? 1 : 60 ) ) {

            # it's loaded and not more than 60 seconds load, so we just go
            # with it and assume it's good... if it's been recompiled, we'll
            # figure it out within the next 60 seconds
            $maxtime = $loaded if $loaded > $maxtime;
        }
        else {
            push @need_memc, $lid;
        }
    }

    # attempt to get things in @need_memc from memcache
    my $memc = LJ::MemCache::get_multi( map { [ $_, "s2c:$_" ] } @need_memc );
    foreach my $lid (@need_memc) {
        if ( my $row = $memc->{"s2c:$lid"} ) {

            # load the layer from memcache; memcache data should always be correct
            my ( $updtime, $data ) = @$row;
            if ($data) {
                $maxtime = $updtime if $updtime > $maxtime;
                S2::load_layer( $lid, $data, $updtime );
            }
        }
        else {
            # make it exist, but mark it 0
            push @from_db, $lid;
        }
    }

    # it's possible we don't need to hit the database for anything
    return $maxtime unless @from_db;

    # figure out who owns what we need
    my $us    = LJ::S2::get_layer_owners(@from_db);
    my $sysid = LJ::get_userid('system');

    # break it down by cluster
    my %bycluster;    # cluster => [ lid, lid, ... ]
    foreach my $lid (@from_db) {
        next unless $us->{$lid};
        if ( $us->{$lid}->{userid} == $sysid ) {
            push @{ $bycluster{0} ||= [] }, $lid;
        }
        else {
            push @{ $bycluster{ $us->{$lid}->{clusterid} } ||= [] }, $lid;
        }
    }

    # big loop by cluster
    foreach my $cid ( keys %bycluster ) {

        # if we're talking about cluster 0, the global, pass it off to the old
        # function which already knows how to handle that
        unless ($cid) {
            my $dbr = LJ::S2::get_s2_reader();
            S2::load_layers_from_db( $dbr, @{ $bycluster{$cid} } );
            next;
        }

        my $db = LJ::get_cluster_master($cid);
        die "Unable to obtain handle to cluster $cid for LJ::S2::load_layers\n"
            unless $db;

        # create SQL to load the layers we want
        my $where = join( ' OR ',
            map { "(userid=$us->{$_}->{userid} AND s2lid=$_)" } @{ $bycluster{$cid} } );
        my $sth = $db->prepare("SELECT s2lid, compdata, comptime FROM s2compiled2 WHERE $where");
        $sth->execute;

        # iterate over data, memcaching as we go
        while ( my ( $id, $comp, $comptime ) = $sth->fetchrow_array ) {
            LJ::text_uncompress( \$comp );
            LJ::MemCache::set( [ $id, "s2c:$id" ], [ $comptime, $comp ] )
                if length $comp <= $LJ::MAX_S2COMPILED_CACHE_SIZE;
            S2::load_layer( $id, $comp, $comptime );
            $maxtime = $comptime if $comptime > $maxtime;
        }
    }

    # now we have to go through everything again and verify they're all loaded
    foreach my $lid (@from_db) {
        next if S2::layer_loaded($lid);

        unless ( $us->{$lid} ) {
            print STDERR "Style $lid has no available owner.\n" if $LJ::DEBUG{"s2style_load"};
            next;
        }

        if ( $us->{$lid}->{userid} == $sysid ) {
            print STDERR "Style $lid is owned by system but failed load from global.\n"
                if $LJ::DEBUG{"s2style_load"};
            next;
        }

        LJ::MemCache::set( [ $lid, "s2c:$lid" ], [ time(), 0 ] );
    }

    return $maxtime;
}

sub is_public_internal_layer {
    my $layerid = shift;

    my $pub = get_public_layers();
    while ($layerid) {

        # doesn't exist, probably private
        return 0 unless defined $pub->{$layerid};
        my $internal = $pub->{$layerid}->{is_internal};

        return 1 if defined $internal && $internal;
        return 0 if defined $internal && !$internal;

        $layerid = $pub->{$layerid}->{b2lid};
    }
    return 0;
}

# whether all layers in this style are public
sub style_is_public {
    my $style = $_[0];
    return 0 unless $style;

    my %lay_info;
    LJ::S2::load_layer_info(
        \%lay_info,
        [
            $style->{layer}->{layout}, $style->{layer}->{theme}, $style->{layer}->{user},
            $style->{layer}->{i18n},   $style->{layer}->{i18nc}
        ]
    );

    my $pub = get_public_layers();
    while ( my ( $layerid, $layerinfo ) = each %lay_info ) {
        return 0 unless $pub->{$layerid} || $layerinfo->{is_public};
    }

    return 1;
}

# find existing re-distributed layers that are in the database
# and their styleids.
sub get_public_layers {
    my $opts  = ref $_[0] eq 'HASH' ? shift : {};
    my $sysid = shift;                              # optional system userid (usually not used)

    unless ( $opts->{force} ) {
        $LJ::CACHED_PUBLIC_LAYERS ||= LJ::MemCache::get("s2publayers");
        return $LJ::CACHED_PUBLIC_LAYERS if $LJ::CACHED_PUBLIC_LAYERS;
    }

    $sysid ||= LJ::get_userid("system");
    my $layers = get_layers_of_user( $sysid, "is_system",
        [qw(des note author author_name author_email is_internal)] );

    $LJ::CACHED_PUBLIC_LAYERS = $layers if $layers;
    LJ::MemCache::set( "s2publayers", $layers, 60 * 10 ) if $layers;
    return $LJ::CACHED_PUBLIC_LAYERS;
}

# update layers whose b2lids have been remapped to new s2lids
sub b2lid_remap {
    my ( $uuserid, $s2lid, $b2lid ) = @_;
    my $b2lid_new = $LJ::S2LID_REMAP{$b2lid};
    return undef unless $uuserid && $s2lid && $b2lid && $b2lid_new;

    my $sysid = LJ::get_userid("system");
    return undef unless $sysid;

    LJ::statushistory_add( $uuserid, $sysid, 'b2lid_remap', "$s2lid: $b2lid=>$b2lid_new" );

    my $dbh = LJ::get_db_writer();
    return $dbh->do( "UPDATE s2layers SET b2lid=? WHERE s2lid=?", undef, $b2lid_new, $s2lid );
}

sub get_layers_of_user {
    my ( $u, $is_system, $infokeys ) = @_;

    my $subst_user = LJ::Hooks::run_hook( "substitute_s2_layers_user", $u );
    if ( defined $subst_user && LJ::isu($subst_user) ) {
        $u = $subst_user;
    }

    my $userid = LJ::want_userid($u);
    return undef unless $userid;
    undef $u unless LJ::isu($u);

    return $u->{'_s2layers'} if $u && $u->{'_s2layers'};

    my %layers;    # id -> {hashref}, uniq -> {same hashref}
    my $dbr = LJ::S2::get_s2_reader();

    my $extrainfo = $is_system ? "'redist_uniq', " : "";
    $extrainfo .= join( ', ', map { $dbr->quote($_) } @$infokeys ) . ", " if $infokeys;

    my $sth =
        $dbr->prepare( "SELECT i.infokey, i.value, l.s2lid, l.b2lid, l.type "
            . "FROM s2layers l, s2info i "
            . "WHERE l.userid=? AND l.s2lid=i.s2lid AND "
            . "i.infokey IN ($extrainfo 'type', 'name', 'langcode', "
            . "'majorversion', '_previews')" );
    $sth->execute($userid);
    die $dbr->errstr if $dbr->err;

    while ( my ( $key, $val, $id, $bid, $type ) = $sth->fetchrow_array ) {
        $layers{$id}->{'b2lid'} = $bid;
        $layers{$id}->{'s2lid'} = $id;
        $layers{$id}->{'type'}  = $type;
        $key                    = "uniq" if $key eq "redist_uniq";
        $layers{$id}->{$key}    = $val;
    }

    foreach ( keys %layers ) {

        # setup uniq alias.
        if ( defined $layers{$_}->{uniq} && $layers{$_}->{uniq} ne "" ) {
            $layers{ $layers{$_}->{'uniq'} } = $layers{$_};
        }

        # setup children keys
        my $bid = $layers{$_}->{b2lid};
        next unless $layers{$_}->{'b2lid'};

        # has the b2lid for this layer been remapped?
        # if so update this layer's specified b2lid
        if ( $bid && $LJ::S2LID_REMAP{$bid} ) {
            my $s2lid = $layers{$_}->{s2lid};
            b2lid_remap( $userid, $s2lid, $bid );
            $layers{$_}->{b2lid} = $LJ::S2LID_REMAP{$bid};
        }

        if ($is_system) {
            my $bid = $layers{$_}->{'b2lid'};
            unless ( $layers{$bid} ) {
                delete $layers{ $layers{$_}->{'uniq'} };
                delete $layers{$_};
                next;
            }
            push @{ $layers{$bid}->{'children'} }, $_;
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
sub get_style {
    my ( $arg, $opts ) = @_;

    my $verify       = 0;
    my $force_layers = 0;
    my ( $styleid, $u );

    if ( ref $opts eq "HASH" ) {
        $verify       = $opts->{'verify'};
        $u            = $opts->{'u'};
        $force_layers = $opts->{'force_layers'};
    }
    elsif ($opts) {
        $verify = 1;
        die "Bogus second arg to LJ::S2::get_style" if ref $opts;
    }

    if ( ref $arg ) {
        $u       = $arg;
        $styleid = $u->prop('s2_style');
    }
    else {
        $styleid = ( $arg || 0 ) + 0;
    }

    my %style;
    my $have_style = 0;

    if ( $verify && $styleid ) {
        my $dbr   = LJ::S2::get_s2_reader();
        my $style = $dbr->selectrow_hashref("SELECT * FROM s2styles WHERE styleid=$styleid");
        if ( !$style && $u ) {
            delete $u->{'s2_style'};
            $styleid = 0;
        }
    }

    if ($styleid) {
        my $stylay =
            $u
            ? LJ::S2::get_style_layers( $u, $styleid, $force_layers )
            : LJ::S2::get_style_layers( $styleid, $force_layers );
        while ( my ( $t, $id ) = each %$stylay ) { $style{$t} = $id; }
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
            if ( exists $LJ::S2LID_REMAP{$lid} ) {
                $style{$_} = $LJ::S2LID_REMAP{$lid};
                push @remaps, "$lid=>$style{$_}";
            }
        }
        if (@remaps) {
            my $sysid = LJ::get_userid("system");
            LJ::statushistory_add( $u, $sysid, 's2lid_remap', join( ", ", @remaps ) );
            LJ::S2::set_style_layers( $u, $styleid, %style );
        }
    }

    unless ($have_style) {
        my $public = get_public_layers();
        while ( my ( $layer, $name ) = each %$LJ::DEFAULT_STYLE ) {
            next unless $name ne "";
            next unless $public->{$name};
            my $id = $public->{$name}->{'s2lid'};
            $style{$layer} = $id if $id;
        }
    }

    return %style;
}

sub s2_context {
    my ( $styleid, %opts ) = @_;

    # get arguments we'll use frequently
    my $r       = DW::Request->get;
    my $u       = $opts{u} || LJ::get_active_journal();
    my $remote  = $opts{remote} || LJ::get_remote();
    my $style_u = $opts{style_u} || $u;

    # but it doesn't matter if we're using the minimal style ...
    my %style;
    eval {
        if ( $r->note('use_minimal_scheme') ) {
            my $public = get_public_layers();
            while ( my ( $layer, $name ) = each %LJ::MINIMAL_STYLE ) {
                next unless $name ne "";
                next unless $public->{$name};
                my $id = $public->{$name}->{'s2lid'};
                $style{$layer} = $id if $id;
            }
        }
    };

    if ( $styleid && $styleid eq "siteviews" ) {
        %style = siteviews_style( $u, $remote, $opts{mode} );
    }
    elsif ( $styleid && $styleid eq "sitefeeds" ) {
        %style = sitefeeds_style();
    }

    if ( ref($styleid) eq "CODE" ) {
        %style = $styleid->();
    }

    # fall back to the standard call to get a user's styles
    unless (%style) {
        %style = $u ? get_style( $styleid, { 'u' => $style_u } ) : get_style($styleid);
    }

    my @layers;
    foreach (qw(core i18nc layout i18n theme user)) {
        push @layers, $style{$_} if $style{$_};
    }

    # TODO: memcache this.  only make core S2 (which uses the DB) load
    # when we can't get all the s2compiled stuff from memcache.
    # compare s2styles.modtime with s2compiled.comptime to see if memcache
    # version is accurate or not.
    my $dbr     = LJ::S2::get_s2_reader();
    my $modtime = LJ::S2::load_layers(@layers);

    # check that all critical layers loaded okay from the database, otherwise
    # fall back to default style.  if i18n/theme/user were deleted, just proceed.
    my $okay = 1;
    foreach (qw(core layout)) {
        next unless $style{$_};
        $okay = 0 unless S2::layer_loaded( $style{$_} );
    }
    unless ($okay) {

        # load the default style instead, if we just tried to load a real one and failed
        return s2_context( 0, %opts )
            if $styleid;

        # were we trying to load the default style?
        $r->content_type('text/html');
        $r->print(
'<b>Error preparing to run:</b> One or more layers required to load the stock style have been deleted.'
        );
        return undef;
    }

    # if we are supposed to use modtime checking (i.e. for stylesheets) then go
    # ahead and do that logic now
    if ( $opts{use_modtime} ) {
        my $mod_since = $r->header_in('If-Modified-Since') || '';
        if ( $mod_since eq LJ::time_to_http($modtime) ) {

            # 304 return; unload non-public layers
            LJ::S2::cleanup_layers(@layers);
            $r->status_line('304 Not Modified');
            return undef;
        }
        else {
            $r->set_last_modified($modtime);
        }
    }

    my $ctx;
    eval { $ctx = S2::make_context(@layers); };

    if ($ctx) {

        # let's use the scratch field as a hashref
        $ctx->[S2::SCRATCH] ||= {};

        LJ::S2::populate_system_props($ctx);
        LJ::S2::alias_renamed_props($ctx);
        LJ::S2::alias_overriding_props($ctx);
        S2::set_output( sub      { } );    # printing suppressed
        S2::set_output_safe( sub { } );
        eval { S2::run_code( $ctx, "prop_init()" ); };
        eval { S2::run_code( $ctx, "modules_init()" ); };
        escape_all_props( $ctx, \@layers );

        return $ctx unless $@;
    }

    # failure to generate context; unload our non-public layers
    LJ::S2::cleanup_layers(@layers);
    $r->content_type('text/html');
    $r->print( '<b>Error preparing to run:</b> ' . $@ );
    return undef;
}

sub escape_all_props {
    my ( $ctx, $lids ) = @_;

    foreach my $lid (@$lids) {
        foreach my $pname ( S2::get_property_names($lid) ) {
            next unless $ctx->[S2::PROPS]{$pname};

            my $prop = S2::get_property( $lid, $pname );
            my $mode = $prop->{string_mode} || "plain";
            escape_prop_value( $ctx->[S2::PROPS]{$pname}, $mode );
        }
    }
}

my $css_cleaner;

sub _css_cleaner {
    return $css_cleaner ||= LJ::CSS::Cleaner->new;
}

sub escape_prop_value_ret {
    my $what = $_[0];
    escape_prop_value( $what, $_[1] );
    return $what;
}

sub escape_prop_value {
    my $mode  = $_[1];
    my $css_c = _css_cleaner();

    # This function modifies its first parameter in place.

    if ( ref $_[0] eq 'ARRAY' ) {
        for ( my $i = 0 ; $i < scalar( @{ $_[0] } ) ; $i++ ) {
            escape_prop_value( $_[0][$i], $mode );
        }
    }
    elsif ( ref $_[0] eq 'HASH' ) {
        foreach my $k ( keys %{ $_[0] } ) {
            escape_prop_value( $_[0]{$k}, $mode );
        }
    }
    elsif ( !ref $_[0] ) {
        if ( $mode eq 'simple-html' || $mode eq 'simple-html-oneline' ) {
            LJ::CleanHTML::clean_subject( \$_[0] );
            $_[0] =~ s!\n!<br />!g if $mode eq 'simple-html';
        }
        elsif ( $mode eq 'html' || $mode eq 'html-oneline' ) {
            LJ::CleanHTML::clean_event( \$_[0] );
            $_[0] =~ s!\n!<br />!g if defined $_[0] && $mode eq 'html';
        }
        elsif ( $mode eq 'css' ) {
            my $clean = $css_c->clean( $_[0] );
            LJ::Hooks::run_hook( 'css_cleaner_transform', \$clean );
            $_[0] = $clean;
        }
        elsif ( $mode eq 'css-attrib' ) {
            if ( $_[0] =~ /[\{\}]/ ) {

                # If the string contains any { and } characters, it can't go in a style="" attrib
                $_[0] = "/* bad CSS: can't use braces in a style attribute */";
                return;
            }
            my $clean = $css_c->clean_property( $_[0] );
            $_[0] = $clean;
        }
        elsif ( defined $_[0] ) {    # plain
            $_[0] =~ s/</&lt;/g;
            $_[0] =~ s/>/&gt;/g;
            $_[0] =~ s!\n!<br />!g;
        }
    }
    else {
        $_[0] = undef;               # Something's gone very wrong. Zzap the value completely.
    }
}

sub siteviews_style {
    my ( $u, $remote, $mode ) = @_;
    my %style;

    my $public = get_public_layers();
    my $theme  = "siteviews/default";
    foreach my $candidate ( DW::SiteScheme->inheritance ) {
        if ( $public->{"siteviews/$candidate"} ) {
            $theme = "siteviews/$candidate";
            last;
        }
    }
    %style = (
        core   => "core2",
        layout => "siteviews/layout",
        theme  => $theme,
    );

    # convert the value names to s2layerid
    while ( my ( $layer, $name ) = each %style ) {
        next unless $public->{$name};
        my $id = $public->{$name}->{'s2lid'};
        $style{$layer} = $id;
    }

    return %style;
}

sub sitefeeds_style {
    return unless %$LJ::DEFAULT_FEED_STYLE;

    my $public = get_public_layers();

    my %style;

    # convert the value names to s2layerid
    while ( my ( $layer, $name ) = each %$LJ::DEFAULT_FEED_STYLE ) {
        next unless $public->{$name};
        my $id = $public->{$name}->{'s2lid'};
        $style{$layer} = $id;
    }

    return %style;
}

# parameter is either a single context, or just a bunch of layerids
# will then unregister the non-public layers
sub cleanup_layers {
    my $pub    = get_public_layers();
    my @unload = ref $_[0] ? S2::get_layers( $_[0] ) : @_;
    S2::unregister_layer($_) foreach grep { !$pub->{$_} } @unload;
}

sub create_style {
    my ( $u, $name ) = @_;

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    my $uid = $u->{userid} + 0
        or return 0;

    # can't create name-less style
    return 0 unless $name =~ /\S/;

    $dbh->do( "INSERT INTO s2styles (userid, name, modtime) VALUES (?,?, UNIX_TIMESTAMP())",
        undef, $u->userid, $name );
    my $styleid = $dbh->{'mysql_insertid'};
    return 0 unless $styleid;

    # in case we had an invalid / empty value from before
    LJ::MemCache::delete( [ $styleid, "s2s:$styleid" ] );

    return $styleid;
}

sub load_user_styles {
    my $u    = shift;
    my $opts = shift;
    return undef unless $u;

    my $dbr = LJ::S2::get_s2_reader();

    my %styles;
    my $load_using = sub {
        my $db  = shift;
        my $sth = $db->prepare("SELECT styleid, name FROM s2styles WHERE userid=?");
        $sth->execute( $u->userid );
        while ( my ( $id, $name ) = $sth->fetchrow_array ) {
            $styles{$id} = $name;
        }
    };
    $load_using->($dbr);
    return \%styles if scalar(%styles) || !$opts->{'create_default'};

    # create a new default one for them, but first check to see if they
    # have one on the master.
    my $dbh = LJ::get_db_writer();
    $load_using->($dbh);
    return \%styles if %styles;

    $dbh->do( "INSERT INTO s2styles (userid, name, modtime) VALUES (?,?, UNIX_TIMESTAMP())",
        undef, $u->{'userid'}, $u->{'user'} );
    my $styleid = $dbh->{'mysql_insertid'};
    return { $styleid => $u->{'user'} };
}

sub delete_user_style {
    my ( $u, $styleid ) = @_;
    return 1 unless $styleid;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    $dbh->do( "DELETE FROM s2styles WHERE styleid=?", undef, $styleid );
    $u->do( "DELETE FROM s2stylelayers2 WHERE userid=? AND styleid=?",
        undef, $u->{userid}, $styleid );

    LJ::MemCache::delete( [ $styleid, "s2s:$styleid" ] );

    return 1;
}

sub rename_user_style {
    my ( $u, $styleid, $name ) = @_;
    return 1 unless $styleid;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do( "UPDATE s2styles SET name=? WHERE styleid=? AND userid=?",
        undef, $name, $styleid, $u->id );
    LJ::MemCache::delete( [ $styleid, "s2s:$styleid" ] );

    return 1;
}

sub load_style {
    my $db = ref $_[0] ? shift : undef;
    my $id = shift;
    return undef unless $id;
    my %opts = @_;

    my $memkey = [ $id, "s2s:$id" ];
    my $style  = LJ::MemCache::get($memkey);
    unless ( defined $style ) {
        $db ||= LJ::S2::get_s2_reader()
            or die "Unable to get S2 reader";
        $style = $db->selectrow_hashref(
            "SELECT styleid, userid, name, modtime " . "FROM s2styles WHERE styleid=?",
            undef, $id );
        die $db->errstr if $db->err;

        LJ::MemCache::add( $memkey, $style || {}, 3600 );
    }
    return undef unless $style;

    unless ( $opts{skip_layer_load} ) {
        my $u = LJ::load_userid( $style->{userid} )
            or return undef;

        $style->{'layer'} = LJ::S2::get_style_layers( $u, $id ) || {};
    }

    return $style;
}

sub create_layer {
    my ( $userid, $b2lid, $type ) = @_;
    $userid = LJ::want_userid($userid);

    return 0 unless $b2lid;    # caller should ensure b2lid exists and is of right type
    return 0
        unless $type eq "user"
        || $type eq "i18n"
        || $type eq "theme"
        || $type eq "layout"
        || $type eq "i18nc"
        || $type eq "core";

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do( "INSERT INTO s2layers (b2lid, userid, type) " . "VALUES (?,?,?)",
        undef, $b2lid, $userid, $type );
    return $dbh->{'mysql_insertid'};
}

# takes optional $u as first argument... if user argument is specified, will
# look through s2stylelayers2 and delete all mappings that this user has to
# this particular layer.
sub delete_layer {
    my $u   = LJ::isu( $_[0] ) ? shift : undef;
    my $lid = shift;
    return 1 unless $lid;
    my $dbh = LJ::get_db_writer();
    foreach my $t (qw(s2layers s2compiled s2info s2source s2source_inno s2checker)) {
        $dbh->do( "DELETE FROM $t WHERE s2lid=?", undef, $lid );
    }

    # make sure we have a user object if possible
    unless ($u) {
        my $us = LJ::S2::get_layer_owners($lid);
        $u = $us->{$lid} if $us->{$lid};
    }

    # delete s2compiled2 if this is a layer owned by someone other than system
    if ( $u && $u->{user} ne 'system' ) {
        $u->do( "DELETE FROM s2compiled2 WHERE userid = ? AND s2lid = ?",
            undef, $u->{userid}, $lid );
    }

    # now clear memcache of the compiled data
    LJ::MemCache::delete( [ $lid, "s2c:$lid" ] );

    # now delete the mappings for this particular layer
    if ($u) {
        my $styles = LJ::S2::load_user_styles($u);
        my @ids    = keys %{ $styles || {} };
        if (@ids) {

            # map in the ids we got from the user's styles and clear layers referencing
            # this particular layer id
            my $in = join( ',', map { $_ + 0 } @ids );
            $u->do( "DELETE FROM s2stylelayers2 WHERE userid=? AND styleid IN ($in) AND s2lid = ?",
                undef, $u->{userid}, $lid );

            # now clean memcache so this change is immediately visible
            LJ::MemCache::delete( [ $_, "s2sl:$_" ] ) foreach @ids;
        }
    }

    return 1;
}

sub get_style_layers {
    my $u = LJ::isu( $_[0] ) ? shift : undef;
    my ( $styleid, $force ) = @_;
    return undef unless $styleid;

    # check memcache unless $force
    my $stylay = $force ? undef : $LJ::S2::REQ_CACHE_STYLE_ID{$styleid};
    return $stylay if $stylay;

    my $memkey = [ $styleid, "s2sl:$styleid" ];
    $stylay = LJ::MemCache::get($memkey) unless $force;
    if ($stylay) {
        $LJ::S2::REQ_CACHE_STYLE_ID{$styleid} = $stylay;
        return $stylay;
    }

    # if an option $u was passed as the first arg,
    # we won't load the userid... otherwise we have to
    unless ($u) {
        my $sty = LJ::S2::load_style($styleid)
            or die "couldn't load styleid $styleid";
        $u = LJ::load_userid( $sty->{userid} )
            or die "couldn't load userid $sty->{userid} for styleid $styleid";
    }

    my %stylay;

    my $fetch = sub {
        my ( $db, $qry, @args ) = @_;

        my $sth = $db->prepare($qry);
        $sth->execute(@args);
        die "ERROR: " . $sth->errstr if $sth->err;
        while ( my ( $type, $s2lid ) = $sth->fetchrow_array ) {
            $stylay{$type} = $s2lid;
        }
        return 0 unless %stylay;
        return 1;
    };

    $fetch->(
        $u, "SELECT type, s2lid FROM s2stylelayers2 " . "WHERE userid=? AND styleid=?",
        $u->userid, $styleid
    );

    # set in memcache
    LJ::MemCache::set( $memkey, \%stylay );
    $LJ::S2::REQ_CACHE_STYLE_ID{$styleid} = \%stylay;
    return \%stylay;
}

sub set_style_layers {
    my ( $u, $styleid, %newlay ) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh && $u->writer;

    $u->do(
        "REPLACE INTO s2stylelayers2 (userid,styleid,type,s2lid) VALUES "
            . join( ",",
            map { sprintf( "(%d,%d,%s,%d)", $u->id, $styleid, $dbh->quote($_), $newlay{$_} // 0 ) }
                keys %newlay )
    );
    return 0 if $u->err;

    $dbh->do( "UPDATE s2styles SET modtime=UNIX_TIMESTAMP() WHERE styleid=?", undef, $styleid );

    # delete memcache key
    LJ::MemCache::delete( [ $styleid, "s2sl:$styleid" ] );
    LJ::MemCache::delete( [ $styleid, "s2s:$styleid" ] );

    return 1;
}

sub load_layer {
    my $db  = ref $_[0] ? shift : LJ::S2::get_s2_reader();
    my $lid = shift;

    my $layerid = $LJ::S2::REQ_CACHE_LAYER_ID{$lid};
    return $layerid if $layerid;

    my $ret = $db->selectrow_hashref(
        "SELECT s2lid, b2lid, userid, type " . "FROM s2layers WHERE s2lid=?",
        undef, $lid );
    die $db->errstr if $db->err;
    $LJ::S2::REQ_CACHE_LAYER_ID{$lid} = $ret;

    return $ret;
}

sub populate_system_props {
    my $ctx = shift;
    $ctx->[S2::PROPS]->{'SITEROOT'}       = $LJ::SITEROOT;
    $ctx->[S2::PROPS]->{'PALIMGROOT'}     = $LJ::PALIMGROOT;
    $ctx->[S2::PROPS]->{'SITENAME'}       = $LJ::SITENAME;
    $ctx->[S2::PROPS]->{'SITENAMESHORT'}  = $LJ::SITENAMESHORT;
    $ctx->[S2::PROPS]->{'SITENAMEABBREV'} = $LJ::SITENAMEABBREV;
    $ctx->[S2::PROPS]->{'IMGDIR'}         = $LJ::IMGPREFIX;
    $ctx->[S2::PROPS]->{'STYLES_IMGDIR'}  = $LJ::IMGPREFIX . "/styles";
    $ctx->[S2::PROPS]->{'STATDIR'}        = $LJ::STATPREFIX;
}

# renamed some props from core1 => core2. Make sure that S2 still handles these variables correctly when working with a core1 layer
sub alias_renamed_props {
    my $ctx = shift;
    $ctx->[S2::PROPS]->{num_items_recent} = $ctx->[S2::PROPS]->{page_recent_items}
        if exists $ctx->[S2::PROPS]->{page_recent_items};

    $ctx->[S2::PROPS]->{num_items_reading} = $ctx->[S2::PROPS]->{page_friends_items}
        if exists $ctx->[S2::PROPS]->{page_friends_items};

    $ctx->[S2::PROPS]->{reverse_sortorder_day} =
        $ctx->[S2::PROPS]->{page_day_sortorder} eq 'reverse' ? 1 : 0
        if exists $ctx->[S2::PROPS]->{page_day_sortorder};

    $ctx->[S2::PROPS]->{reverse_sortorder_year} =
        $ctx->[S2::PROPS]->{page_year_sortorder} eq 'reverse' ? 1 : 0
        if exists $ctx->[S2::PROPS]->{page_year_sortorder};

    # Not adding the new views to core1, force non-entry use_journalstyle_ to 0 for core1
    if ( exists $ctx->[S2::PROPS]->{view_entry_disabled} ) {
        $ctx->[S2::PROPS]->{use_journalstyle_entry_page} =
            !$ctx->[S2::PROPS]->{view_entry_disabled};
        $ctx->[S2::PROPS]->{use_journalstyle_icons_page} = 0;
    }
}

# use the "grouped_property_override" property to determine whether a custom property should override a default property.
# one potential use: to customize which sections a module may show up in.
sub alias_overriding_props {
    my $ctx = $_[0];

    my %overrides = %{ $ctx->[S2::PROPS]->{grouped_property_override} || {} };
    return unless %overrides;

    while ( my ( $original, $overriding ) = each %overrides ) {
        $ctx->[S2::PROPS]->{$original} = $ctx->[S2::PROPS]->{$overriding}
            if $ctx->[S2::PROPS]->{$overriding};
    }
}

sub convert_prop_val {
    my ( $prop, $val ) = @_;
    $prop ||= {};
    my $type = $prop->{type} || '';

    return int($val) if $type eq "int";
    return $val ? "true" : "false" if $type eq "bool";

    # if not int or bool, treat property as text - use quotes,
    # use zero-width lookahead to insert a backslash where needed
    $val =~ s/(?=[\\\$\"])/\\/g;
    return qq{"$val"};
}

sub layer_compile_user {
    my ( $layer, $overrides ) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless ref $layer;
    return 0 unless $layer->{'s2lid'};
    return 1 unless ref $overrides;
    my $id = $layer->{'s2lid'};
    my $s2 = LJ::Lang::ml('s2theme.autogenerated.warning');
    $s2 .= "layerinfo \"type\" = \"user\";\n";
    $s2 .= "layerinfo \"name\" = \"Auto-generated Customizations\";\n";

    foreach my $name ( sort keys %$overrides ) {
        next if $name =~ /\W/;
        my $val = convert_prop_val( @{ $overrides->{$name} } );
        $s2 .= "set $name = $val;\n";
    }

    my $error;
    return 1 if LJ::S2::layer_compile( $layer, \$error, { 's2ref' => \$s2 } );
    return LJ::error($error);
}

sub layer_compile {
    my ( $layer, $err_ref, $opts ) = @_;
    my $dbh = LJ::get_db_writer();

    my $lid;
    if ( ref $layer eq "HASH" ) {
        $lid = $layer->{'s2lid'} + 0;
    }
    else {
        $lid   = $layer + 0;
        $layer = LJ::S2::load_layer( $dbh, $lid );
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
        unless ($s2) { $$err_ref = "No source code to compile."; return undef; }
        $s2ref = \$s2;
    }

    my $is_system = $layer->{userid} == LJ::get_userid("system");
    my $untrusted = !$is_system;

    # system writes go to global.  otherwise to user clusters.
    my $dbcm;
    if ($is_system) {
        $dbcm = $dbh;
    }
    else {
        my $u = LJ::load_userid( $layer->{userid} );
        $dbcm = $u;
    }

    unless ($dbcm) { $$err_ref = "Unable to get database handle"; return 0; }

    my $compiled;
    my $cplr = S2::Compiler->new( { 'checker' => $checker } );
    eval {
        $cplr->compile_source(
            {
                'type'           => $layer->{'type'},
                'source'         => $s2ref,
                'output'         => \$compiled,
                'layerid'        => $lid,
                'untrusted'      => $untrusted,
                'builtinPackage' => "S2::Builtin::LJ",
            }
        );
    };
    if ($@) { $$err_ref = "Compile error: $@"; return undef; }

    # save the source, since it at least compiles
    if ( $opts->{'s2ref'} ) {
        LJ::S2::set_layer_source( $lid, $opts->{s2ref} ) or return 0;
    }

    # save the checker object for later
    if ( $layer->{'type'} eq "core" || $layer->{'type'} eq "layout" ) {
        $checker->cleanForFreeze();
        my $chk_frz = Storable::freeze($checker);
        LJ::text_compress( \$chk_frz );
        $dbh->do( "REPLACE INTO s2checker (s2lid, checker) VALUES (?,?)", undef, $lid, $chk_frz )
            or die "replace into s2checker (lid = $lid)";
    }

    # load the compiled layer to test it loads and then get layerinfo/etc from it
    S2::unregister_layer($lid);
    eval $compiled;
    if ($@) { $$err_ref = "Post-compilation error: $@"; return undef; }
    if ( $opts->{'redist_uniq'} ) {

        # used by update-db loader:
        my $redist_uniq = S2::get_layer_info( $lid, "redist_uniq" );
        die "redist_uniq value of '$redist_uniq' doesn't match $opts->{'redist_uniq'}\n"
            unless $redist_uniq eq $opts->{'redist_uniq'};
    }

    # put layerinfo into s2info
    my %info = S2::get_layer_info($lid);
    my $values;
    my $notin;
    foreach ( keys %info ) {
        $values .= "," if $values;
        $values .= sprintf( "(%d, %s, %s)", $lid, $dbh->quote($_), $dbh->quote( $info{$_} ) );
        $notin  .= "," if $notin;
        $notin  .= $dbh->quote($_);
    }
    if ($values) {
        $dbh->do("REPLACE INTO s2info (s2lid, infokey, value) VALUES $values")
            or die "replace into s2info (values = $values)";
        $dbh->do( "DELETE FROM s2info WHERE s2lid=? AND infokey NOT IN ($notin)", undef, $lid );
    }
    if ( $opts->{'layerinfo'} ) {
        ${ $opts->{'layerinfo'} } = \%info;
    }

    # put compiled into database, with its ID number
    if ($is_system) {
        $dbh->do(
            "REPLACE INTO s2compiled (s2lid, comptime, compdata) "
                . "VALUES (?, UNIX_TIMESTAMP(), ?)",
            undef, $lid, $compiled
        ) or die "replace into s2compiled (lid = $lid)";
    }
    else {
        my $gzipped = LJ::text_compress($compiled);
        $dbcm->do(
            "REPLACE INTO s2compiled2 (userid, s2lid, comptime, compdata) "
                . "VALUES (?, ?, UNIX_TIMESTAMP(), ?)",
            undef,
            $layer->{userid},
            $lid,
            $gzipped
        ) or die "replace into s2compiled2 (lid = $lid)";
    }

    # delete from memcache; we can't store since we don't know the exact comptime
    LJ::MemCache::delete( [ $lid, "s2c:$lid" ] );

    # caller might want the compiled source
    if ( ref $opts->{'compiledref'} eq "SCALAR" ) {
        ${ $opts->{'compiledref'} } = $compiled;
    }

    S2::unregister_layer($lid);
    return 1;
}

sub get_layer_checker {
    my $lay     = shift;
    my $err_ref = shift;
    return undef unless ref $lay eq "HASH";
    return S2::Checker->new() if $lay->{'type'} eq "core";
    my $parid = $lay->{'b2lid'} + 0 or return undef;
    my $dbh   = LJ::get_db_writer();

    my $get_cached = sub {
        my $frz =
            $dbh->selectrow_array( "SELECT checker FROM s2checker WHERE s2lid=?", undef, $parid )
            or return undef;
        LJ::text_uncompress( \$frz );
        return Storable::thaw($frz);    # can be undef, on failure
    };

    # the good path
    my $checker = $get_cached->();
    return $checker if $checker;

    # no cached checker (or bogus), so we have to [re]compile to get it
    my $parlay = LJ::S2::load_layer( $dbh, $parid );
    return undef unless LJ::S2::layer_compile($parlay);
    return $get_cached->();
}

sub load_layer_info {
    my ( $outhash, $listref ) = @_;
    return 0 unless ref $listref eq "ARRAY";
    return 1 unless @$listref;

    # check request cache
    my %layers_from_cache = ();
    foreach my $lid (@$listref) {
        my $layerinfo = $LJ::S2::REQ_CACHE_LAYER_INFO{$lid};
        if ( keys %$layerinfo ) {
            $layers_from_cache{$lid} = 1;
            foreach my $k ( keys %$layerinfo ) {
                $outhash->{$lid}->{$k} = $layerinfo->{$k};
            }
        }
    }

    # only return if we found all of the given layers in request cache
    if ( keys %$outhash && ( scalar @$listref == scalar keys %layers_from_cache ) ) {
        return 1;
    }

    # get all of the layers that weren't in request cache from the db
    my $in  = join( ',', map { $_ + 0 } grep { !$layers_from_cache{$_} } @$listref );
    my $dbr = LJ::S2::get_s2_reader();
    my $sth = $dbr->prepare( "SELECT s2lid, infokey, value FROM s2info WHERE " . "s2lid IN ($in)" );
    $sth->execute;

    while ( my ( $id, $k, $v ) = $sth->fetchrow_array ) {
        $LJ::S2::REQ_CACHE_LAYER_INFO{$id}->{$k} = $v;
        $outhash->{$id}->{$k} = $v;
    }

    return 1;
}

sub set_layer_source {
    my ( $s2lid, $source_ref ) = @_;

    my $dbh = LJ::get_db_writer();
    my $rv  = $dbh->do( "REPLACE INTO s2source_inno (s2lid, s2code) VALUES (?,?)",
        undef, $s2lid, $$source_ref );
    die $dbh->errstr if $dbh->err;

    return $rv;
}

sub load_layer_source {
    my $s2lid = shift;
    my $dbh   = LJ::get_db_writer();

    return $dbh->selectrow_array( "SELECT s2code FROM s2source_inno WHERE s2lid=?", undef, $s2lid );
}

sub load_layer_source_row {
    my $s2lid = shift;
    my $dbh   = LJ::get_db_writer();

    return $dbh->selectrow_hashref( "SELECT * FROM s2source_inno WHERE s2lid=?", undef, $s2lid );
}

sub get_layout_langs {
    my $src   = shift;
    my $layid = shift;
    my %lang;
    foreach ( keys %$src ) {
        next unless /^\d+$/;
        my $v = $src->{$_};
        next unless $v->{'langcode'};
        $lang{ $v->{'langcode'} } = $src->{$_}
            if ( $v->{'type'} eq "i18nc"
            || ( $v->{'type'} eq "i18n" && $layid && $v->{'b2lid'} == $layid ) );
    }
    return map { $_, $lang{$_}->{'name'} } sort keys %lang;
}

# returns array of hashrefs
sub get_layout_themes {
    my $src = shift;
    $src = [$src] unless ref $src eq "ARRAY";
    my $layid = shift;
    my @themes;
    foreach my $src (@$src) {
        foreach ( sort { $src->{$a}->{'name'} cmp $src->{$b}->{'name'} } keys %$src ) {
            next unless /^\d+$/;
            my $v = $src->{$_};
            $v->{b2layer} = $src->{ $src->{$_}->{b2lid} };    # include layout information
            my $is_active = LJ::Hooks::run_hook( "layer_is_active", $v->{'uniq'} );
            push @themes, $v
                if ( $v->{type} eq "theme"
                && $layid
                && $v->{b2lid} == $layid
                && ( !defined $is_active || $is_active ) );
        }
    }
    return @themes;
}

# src, layid passed to get_layout_themes; u is optional
sub get_layout_themes_select {
    my ( $src, $layid, $u ) = @_;
    my ( @sel, $last_uid, $text, $can_use_layer, $layout_allowed );

    foreach my $t ( get_layout_themes( $src, $layid ) ) {

        # themes should be shown but disabled if you can't use the layout
        unless ( defined $layout_allowed ) {
            if ( defined $u && $t->{b2layer} && $t->{b2layer}->{uniq} ) {
                $layout_allowed = LJ::S2::can_use_layer( $u, $t->{b2layer}->{uniq} );
            }
            else {
                # if no parent layer information, or no uniq (user style?),
                # then just assume it's allowed
                $layout_allowed = 1;
            }
        }

        $text          = $t->{name};
        $can_use_layer = $layout_allowed
            && ( !defined $u || LJ::S2::can_use_layer( $u, $t->{uniq} ) )
            ;    # if no u, accept theme; else check policy
        $text = "$text*" unless $can_use_layer;

        if ( $last_uid && $t->{userid} != $last_uid ) {
            push @sel, 0, '---';    # divider between system & user
        }
        $last_uid = $t->{userid};

        # these are passed to LJ::html_select which can take hashrefs
        push @sel,
            {
            value    => $t->{s2lid},
            text     => $text,
            disabled => !$can_use_layer,
            };
    }

    return @sel;
}

sub get_policy {
    return $LJ::S2::CACHE_POLICY if $LJ::S2::CACHE_POLICY;
    my $policy = {};

    # localize $_ so that the while (<P>) below doesn't clobber it and cause problems
    # in anybody that happens to be calling us
    local $_;

    foreach my $infix ( "", "-local" ) {
        my $file  = "$LJ::HOME/styles/policy${infix}.dat";
        my $layer = undef;
        open( P, $file ) or next;
        while (<P>) {
            s/\#.*//;
            next unless /\S/;
            if (/^\s*layer\s*:\s*(\S+)\s*$/) {
                $layer = $1;
                next;
            }
            next unless $layer;
            s/^\s+//;
            s/\s+$//;
            my @words = split( /\s+/, $_ );
            next unless $words[-1] eq "allow" || $words[-1] eq "deny";
            my $allow = $words[-1] eq "allow" ? 1 : 0;
            if ( $words[0] eq "use" && @words == 2 ) {
                $policy->{$layer}->{'use'} = $allow;
            }
            if ( $words[0] eq "props" && @words == 2 ) {
                $policy->{$layer}->{'props'} = $allow;
            }
            if ( $words[0] eq "prop" && @words == 3 ) {
                $policy->{$layer}->{'prop'}->{ $words[1] } = $allow;
            }
        }
    }

    return $LJ::S2::CACHE_POLICY = $policy;
}

sub can_use_layer {
    my ( $u, $uniq ) = @_;    # $uniq = redist_uniq value
    return 1 if $u->can_create_s2_styles;
    return 0 unless $uniq;
    return 1 if LJ::Hooks::run_hook(
        's2_can_use_layer',
        {
            u    => $u,
            uniq => $uniq,
        }
    );
    my $pol = get_policy();
    my $can = 0;

    my @try = ( $uniq =~ m!/layout$! ) ? ( '*', $uniq ) :    # this is a layout
        ( '*/themes', $uniq );                               # this is probably a theme

    foreach (@try) {
        next unless defined $pol->{$_};
        next unless defined $pol->{$_}->{'use'};
        $can = $pol->{$_}->{'use'};
    }
    return $can;
}

sub can_use_prop {
    my ( $u, $uniq, $prop ) = @_;                            # $uniq = redist_uniq value
    return 1 if $u->can_create_s2_styles;
    return 1 if $u->can_create_s2_props;
    my $pol    = get_policy();
    my $can    = 0;
    my @layers = ('*');
    my $pub    = get_public_layers();
    if ( $pub->{$uniq} && $pub->{$uniq}->{'type'} eq "layout" ) {
        my $cid = $pub->{$uniq}->{'b2lid'};
        push @layers, $pub->{$cid}->{'uniq'} if $pub->{$cid};
    }
    push @layers, $uniq;
    foreach my $lay (@layers) {
        foreach my $it ( 'props', 'prop' ) {
            if ( $it eq "props" && defined $pol->{$lay}->{'props'} ) {
                $can = $pol->{$lay}->{'props'};
            }
            if ( $it eq "prop" && defined $pol->{$lay}->{'prop'}->{$prop} ) {
                $can = $pol->{$lay}->{'prop'}->{$prop};
            }
        }
    }
    return $can;
}

sub get_journal_day_counts {
    my ($s2page) = @_;
    return $s2page->{'_day_counts'} if defined $s2page->{'_day_counts'};

    my $u = $s2page->{'_u'};
    return {} unless LJ::isu($u);
    my $counts = {};

    my $remote = LJ::get_remote();
    my $days   = $u->get_daycounts($remote) or return {};
    foreach my $day (@$days) {
        $counts->{ $day->[0] }->{ $day->[1] }->{ $day->[2] } = $day->[3];
    }
    return $s2page->{'_day_counts'} = $counts;
}

sub use_journalstyle_entry_page {
    my ( $u, $ctx ) = @_;
    return 0 if !$u || $u->is_syndicated;    # see sitefeeds/layout.s2
    my $userprop = $u->prop('use_journalstyle_entry_page');

    my $reparse_userprop = sub {

        # We can't use a regular boolean for this, because "false"
        # userprops are deleted, and it would always fall back to
        # the style's previous setting in the negative case.
        # So let's store this as 'Y' or 'N' and then reparse
        # it to return the expected boolean value.

        my $val = $userprop;
        return 1 if $val && $val eq 'Y';
        return 0 if $val && $val eq 'N';
        return undef;    # unexpected or undefined value
    };

    my $reparsed;
    $reparsed = $reparse_userprop->() if defined $userprop;
    return $reparsed if defined $reparsed;

    # if the userprop isn't defined, or we got an unexpected value
    # check the current style for the legacy S2 prop, and then
    # set the userprop going forward
    $ctx ||= LJ::S2::s2_context( $u->{s2_style} ) or return undef;
    my $ctxval = $ctx->[S2::PROPS]->{use_journalstyle_entry_page};
    $userprop = $ctxval ? 'Y' : 'N';

    $u->set_prop( 'use_journalstyle_entry_page', $userprop );
    return $reparse_userprop->();
}

sub tracking_popup_js {
    return LJ::is_enabled('esn_ajax')
        ? (
        { group => 'jquery' }, qw(
            js/jquery/jquery.ui.core.js
            js/jquery/jquery.ui.widget.js

            js/jquery/jquery.ui.tooltip.js
            js/jquery.ajaxtip.js
            js/jquery/jquery.ui.position.js

            stc/jquery/jquery.ui.core.css
            stc/jquery/jquery.ui.tooltip.css

            js/jquery.esn.js
            )
        )
        : ();
}

sub use_journalstyle_icons_page {
    my ( $u, $ctx ) = @_;
    return 0 if !$u || $u->is_syndicated;                       # see sitefeeds/layout.s2
    return 0 unless exists $ctx->[S2::CLASSES]->{IconsPage};    # core1 doesn't support IconsPage

    return $u->prop('use_journalstyle_icons_page') ? 1 : 0;
}

## S2 object constructors

sub CommentInfo {
    my $opts = shift;
    $opts->{'_type'} = "CommentInfo";
    $opts->{'count'} += 0;
    return $opts;
}

sub Date {
    my @parts = @_;
    my $dt    = { '_type' => 'Date' };
    $dt->{'year'}       = $parts[0] + 0;
    $dt->{'month'}      = $parts[1] + 0;
    $dt->{'day'}        = $parts[2] + 0;
    $dt->{'_dayofweek'} = $parts[3];
    die "S2 Builtin Date() takes day of week 1-7, not 0-6"
        if defined $parts[3] && $parts[3] == 0;
    return $dt;
}

sub DateTime_unix {
    my $time   = shift;
    my @gmtime = gmtime($time);
    my $dt     = { '_type' => 'DateTime' };
    $dt->{'year'}       = $gmtime[5] + 1900;
    $dt->{'month'}      = $gmtime[4] + 1;
    $dt->{'day'}        = $gmtime[3];
    $dt->{'hour'}       = $gmtime[2];
    $dt->{'min'}        = $gmtime[1];
    $dt->{'sec'}        = $gmtime[0];
    $dt->{'_dayofweek'} = $gmtime[6] + 1;
    return $dt;
}

sub DateTime_tz {

    # timezone can be scalar timezone name, DateTime::TimeZone object, or LJ::User object
    my ( $epoch, $timezone ) = @_;
    return undef unless $timezone;

    if ( ref $timezone eq "LJ::User" ) {
        $timezone = $timezone->prop("timezone");
        return undef unless $timezone;
    }

    my $dt = eval { DateTime->from_epoch( epoch => $epoch, time_zone => $timezone, ); };
    return undef unless $dt;

    my $ret = { '_type' => 'DateTime' };
    $ret->{'year'}  = $dt->year;
    $ret->{'month'} = $dt->month;
    $ret->{'day'}   = $dt->day;
    $ret->{'hour'}  = $dt->hour;
    $ret->{'min'}   = $dt->minute;
    $ret->{'sec'}   = $dt->second;

    # DateTime.pm's dayofweek is 1-based/Mon-Sun, but S2's is 1-based/Sun-Sat,
    # so first we make DT's be 0-based/Sun-Sat, then shift it up to 1-based.
    $ret->{'_dayofweek'} = ( $dt->day_of_week % 7 ) + 1;
    return $ret;
}

sub DateTime_parts {
    my $datestr = defined $_[0] ? $_[0] : '';
    my @parts   = split /\s+/, $datestr;

    my $dt = { '_type' => 'DateTime' };
    $dt->{year}  = defined $parts[0] ? $parts[0] + 0 : 0;
    $dt->{month} = defined $parts[1] ? $parts[1] + 0 : 0;
    $dt->{day}   = defined $parts[2] ? $parts[2] + 0 : 0;
    $dt->{hour}  = defined $parts[3] ? $parts[3] + 0 : 0;
    $dt->{min}   = defined $parts[4] ? $parts[4] + 0 : 0;
    $dt->{sec}   = defined $parts[5] ? $parts[5] + 0 : 0;

    # the parts string comes from MySQL which has range 0-6,
    # but internally and to S2 we use 1-7.
    $dt->{'_dayofweek'} = $parts[6] + 1 if defined $parts[6];
    return $dt;
}

sub Tag {
    my ( $u, $kwid, $kw ) = @_;
    return undef unless $u && $kwid && $kw;

    my $url = LJ::Tags::tag_url( $u, $kw );

    my $t = {
        _type => 'Tag',
        _id   => $kwid,
        name  => LJ::ehtml($kw),
        url   => $url,
    };

    return $t;
}

sub TagDetail {
    my ( $u, $kwid, $tag ) = @_;
    return undef unless $u && $kwid && ref $tag eq 'HASH';

    my $t = {
        _type      => 'TagDetail',
        _id        => $kwid,
        name       => LJ::ehtml( $tag->{name} ),
        url        => LJ::Tags::tag_url( $u, $tag->{name} ),
        visibility => $tag->{security_level},
    };

    # Work out how many uses of the tag the current remote (if any)
    # should be able to see. This is easy for public & protected
    # entries, but gets tricky with group filters because a post can
    # be visible to >1 of them. Instead of working it out accurately
    # every time, we give an approximation that will either be accurate
    # or an underestimate.
    my $count  = 0;
    my $remote = LJ::get_remote();

    if ( defined $remote && $remote->can_manage($u) ) {    #own journal
        $count = $tag->{uses};
        my $groupcount = $tag->{uses};
        foreach (qw(public private protected)) {
            $t->{security_counts}->{$_} = $tag->{security}->{$_};
            $groupcount -= $tag->{security}->{$_};
        }
        $t->{security_counts}->{group} = $groupcount;

    }
    elsif ( defined $remote ) {                            #logged in, not own journal
        my $trusted = $u->trusts_or_has_member($remote);
        my $grpmask = $u->trustmask($remote);

        $count = $tag->{security}->{public};
        $t->{security_counts}->{public} = $tag->{security}->{public};
        if ($trusted) {
            $count += $tag->{security}->{protected};
            $t->{security_counts}->{protected} = $tag->{security}->{protected};
        }
        if ( $grpmask > 1 ) {

            # Find the greatest number of uses of this tag in any one group
            # that this remote is a member of, and add that number to the count
            my $maxgroupsize = 0;
            foreach ( LJ::bit_breakdown($grpmask) ) {
                $maxgroupsize = $tag->{security}->{groups}->{$_}
                    if $tag->{security}->{groups}->{$_}
                    && $tag->{security}->{groups}->{$_} > $maxgroupsize;
            }
            $count += $maxgroupsize;
        }

    }
    else {    #logged out.
        $count = $tag->{security}->{public};
        $t->{security_counts}->{public} = $tag->{security}->{public};
    }

    $t->{use_count} = $count;

    return $t;
}

sub TagList {
    my ( $tags, $u, $jitemid, $opts, $taglist ) = @_;

    while ( my ( $kwid, $keyword ) = each %{ $tags || {} } ) {
        push @$taglist, Tag( $u, $kwid => $keyword );
    }

    LJ::Hooks::run_hooks(
        'augment_s2_tag_list',
        u        => $u,
        jitemid  => $jitemid,
        tag_list => $taglist
    );
    @$taglist = sort { $a->{name} cmp $b->{name} } @$taglist;

    return "" if $opts->{no_entry_body};
    return "" unless $opts->{enable_tags_compatibility} && @$taglist;
    return LJ::S2::get_tags_text( $opts->{ctx}, $taglist );
}

sub Entry {
    my ( $u, $arg ) = @_;
    my $e = {
        '_type'       => 'Entry',
        'link_keyseq' => [ 'edit_entry', 'edit_tags' ],
        'metadata'    => {},
    };
    foreach (
        qw( subject text journal poster new_day end_day
        comments userpic permalink_url itemid tags timeformat24
        admin_post dom_id )
        )
    {
        $e->{$_} = $arg->{$_};
    }

    my $pic = $e->{userpic};
    if ( $pic->{url} ) {
        my $userpic_style = $arg->{userpic_style} || "";

        if ( $userpic_style eq 'small' ) {
            $pic->{width}  = $pic->{width} * 3 / 4;
            $pic->{height} = $pic->{height} * 3 / 4;
        }
        elsif ( $userpic_style eq "smaller" ) {
            $pic->{width}  = $pic->{width} / 2;
            $pic->{height} = $pic->{height} / 2;
        }
    }

    my $remote = LJ::get_remote();
    my $poster = $e->{poster}->{_u};

    $e->{'tags'} ||= [];
    $e->{'time'}        = DateTime_parts( $arg->{'dateparts'} );
    $e->{'system_time'} = DateTime_parts( $arg->{'system_dateparts'} );
    $e->{'depth'} = 0;    # Entries are always depth 0.  Comments are 1+.

    my $link_keyseq = $e->{'link_keyseq'};
    push @$link_keyseq, 'mem_add'          if LJ::is_enabled('memories');
    push @$link_keyseq, 'tell_friend'      if LJ::is_enabled('tellafriend');
    push @$link_keyseq, 'watch_comments'   if LJ::is_enabled('esn');
    push @$link_keyseq, 'unwatch_comments' if LJ::is_enabled('esn');

    # Note: nav_prev and nav_next are not included in the keyseq anticipating
    #      that their placement relative to the others will vary depending on
    #      layout.

    if ( $arg->{'security'} eq "public" ) {

        # do nothing.
    }
    elsif ( $arg->{'security'} eq "usemask" ) {
        if ( $arg->{'allowmask'} == 0 ) {    # custom security with no group -- essentially private
            $e->{'security'}      = "private";
            $e->{'security_icon'} = Image_std("security-private");
        }
        elsif ( $arg->{'allowmask'} > 1 && $poster && $poster->equals($remote) )
        {                                    # custom group -- only show to journal owner
            $e->{'security'}      = "custom";
            $e->{'security_icon'} = Image_std("security-groups");
        }
        else {    # friends only or custom group showing to non journal owner
            $e->{'security'}      = "protected";
            $e->{'security_icon'} = Image_std("security-protected");
        }
    }
    elsif ( $arg->{'security'} eq "private" ) {
        $e->{'security'}      = "private";
        $e->{'security_icon'} = Image_std("security-private");
    }

    $e->{adult_content_level} = "";
    if ( $arg->{adult_content_level} eq "explicit" ) {
        $e->{adult_content_level} = "18";
        $e->{adult_content_icon}  = Image_std("adult-18");
    }
    elsif ( $arg->{adult_content_level} eq "concepts" ) {
        $e->{adult_content_level} = "NSFW";
        $e->{adult_content_icon}  = Image_std("adult-nsfw");
    }
    else {
        # do nothing.
    }

    my $m_arg = $arg;

    # if moodthemeid not given, look up the user's if we have it
    $m_arg = $u if !defined $arg->{moodthemeid} && LJ::isu($u);

    my $p = $arg->{props};
    my $img_arg;
    my %current = LJ::currents( $p, $m_arg, { s2imgref => \$img_arg } );
    $e->{metadata}->{ lc $_ } = $current{$_} foreach keys %current;
    $e->{mood_icon} = Image(@$img_arg) if defined $img_arg;

    my $apache_r = BML::get_request();

    # custom friend groups
    my $group_names = $arg->{group_names};
    unless ($group_names) {
        my $entry = LJ::Entry->new( $e->{journal}->{_u}, ditemid => $e->{itemid} );
        $group_names = $entry->group_names;
    }
    $e->{metadata}->{groups} = $group_names if $group_names;

    # TODO: Populate this field more intelligently later, but for now this will
    #   hopefully disuade people from hardcoding logic like this into their S2
    #   layers when they do weird parsing/manipulation of the text member in
    #   untrusted layers.
    $e->{text_must_print_trusted} = 1 if $e->{text} =~ m!<(script|object|applet|embed|iframe)\b!i;

    return $e;
}

#returns an S2 Entry from a user object and an entry object
sub Entry_from_entryobj {
    my ( $u, $entry_obj, $opts ) = @_;
    my $remote        = LJ::get_remote();
    my $get           = $opts->{getargs};
    my $no_entry_body = $opts->{no_entry_body};

    my $anum    = $entry_obj->anum;
    my $jitemid = $entry_obj->jitemid;
    my $ditemid = $entry_obj->ditemid;

    # $journal: journal posted to
    my $journalid = $entry_obj->journalid;
    my $journal   = LJ::load_userid($journalid);

    # is style=mine used?  or if remote has it on and this entry is not part of
    # their journal.  if either are yes, it needs to be added to comment links
    my %opt_stylemine =
           $remote
        && $remote->prop('opt_stylemine')
        && $remote->id != $journalid ? ( style => 'mine' ) : ();
    my $style_args = LJ::viewing_style_args( %$get, %opt_stylemine );

    #load and prepare subject and text of entry
    my $subject = LJ::CleanHTML::quote_html( $entry_obj->subject_html, $get->{nohtml} );
    my $text =
        $no_entry_body ? "" : LJ::CleanHTML::quote_html( $entry_obj->event_raw, $get->{nohtml} );
    LJ::item_toutf8( $journal, \$subject, \$text, $entry_obj->props )
        if $entry_obj->props->{unknown8bit};

    my $suspend_msg = $entry_obj && $entry_obj->should_show_suspend_msg_to($remote) ? 1 : 0;

    unless ($no_entry_body) {

        # cleaning the entry text: cuts and such
        my $cut_disable    = $opts->{cut_disable};
        my $cleanhtml_opts = {
            cuturl =>
                $entry_obj->url( style_opts => LJ::viewing_style_opts( %$get, %opt_stylemine ) ),
            ljcut_disable       => $cut_disable,
            journal             => $journal->username,
            ditemid             => $ditemid,
            suspend_msg         => $suspend_msg,
            unsuspend_supportid => $suspend_msg ? $entry_obj->prop('unsuspend_supportid') : 0,
            preformatted        => $entry_obj->prop("opt_preformatted"),
        };

        # reading pages might need to display image placeholders
        my $cleanhtml_extra = $opts->{cleanhtml_extra} || {};
        foreach my $k ( keys %$cleanhtml_extra ) {
            $cleanhtml_opts->{$k} = $cleanhtml_extra->{$k};
        }
        LJ::CleanHTML::clean_event( \$text, $cleanhtml_opts );

        LJ::expand_embedded( $journal, $jitemid, $remote, \$text );
        $text = DW::Logic::AdultContent->transform_post(
            post    => $text,
            journal => $journal,
            remote  => $remote,
            entry   => $entry_obj
        );
    }

    # journal: posted to; poster: posted by
    my $posterid         = $entry_obj->posterid;
    my $userlite_journal = UserLite($journal);
    my $poster           = $journal;

# except for communities, posterid and journalid should match, only load separate UserLite object if that is not the case
    my $userlite_poster = $userlite_journal;
    unless ( $posterid == $journalid ) {
        $poster          = LJ::load_userid($posterid);
        $userlite_poster = UserLite($poster);
    }

    # loading S2 Userpic
    my $userpic;
    my $userpic_position = S2::get_property_value( $opts->{ctx}, 'userpics_position' ) || "";
    my $userpic_style;

    unless ( $userpic_position eq "none" ) {

# if the post was made in a community, use either the userpic it was posted with or the community pic depending on the style setting
        if ( $posterid == $journalid || !S2::get_property_value( $opts->{ctx}, 'use_shared_pic' ) )
        {
            my ( $pic, $kw ) = $entry_obj->userpic;
            $userpic = Image_userpic( $poster, $pic->picid, $kw ) if $pic;
        }
        else {
            $userpic = Image_userpic( $journal, $journal->userpic->picid ) if $journal->userpic;
        }

        $userpic_style = S2::get_property_value( $opts->{ctx}, 'entry_userpic_style' );
    }

    # override used moodtheme if necessary
    my $moodthemeid = $u->prop('opt_forcemoodtheme') eq 'Y' ? $u->moodtheme : $poster->moodtheme;

    # tags loading and sorting
    my $tags    = LJ::Tags::get_logtags( $journal, $jitemid );
    my $taglist = [];
    $text .= TagList( $tags->{$jitemid}, $journal, $jitemid, $opts, $taglist );
    my $tagnav;

    # building the CommentInfo and Entry objects
    my $comments = CommentInfo(
        $entry_obj->comment_info(
            u          => $u,
            remote     => $remote,
            style_args => $style_args,
            journal    => $journal
        )
    );

    my $entry = Entry(
        $u,
        {
            subject             => $subject,
            text                => $text,
            dateparts           => LJ::alldatepart_s2( $entry_obj->{eventtime} ),
            system_dateparts    => LJ::alldatepart_s2( $entry_obj->{logtime} ),
            security            => $entry_obj->security,
            adult_content_level => $entry_obj->adult_content_calculated
                || $journal->adult_content_calculated,
            allowmask     => $entry_obj->allowmask,
            props         => $entry_obj->props,
            itemid        => $ditemid,
            journal       => $userlite_journal,
            poster        => $userlite_poster,
            comments      => $comments,
            new_day       => 0,                                         #if true, set later
            end_day       => 0,                                         #if true, set later
            userpic       => $userpic,
            userpic_style => $userpic_style,
            tags          => $taglist,
            tagnav        => $tagnav,
            permalink_url => $entry_obj->url,
            moodthemeid   => $moodthemeid,
            timeformat24  => $remote && $remote->use_24hour_time,
            admin_post    => $entry_obj->admin_post,
            dom_id        => "entry-" . $journal->user . "-$ditemid",
        }
    );

    return $entry;
}

sub Friend {
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'}   = "Friend";
    $o->{'bgcolor'} = S2::Builtin::LJ::Color__Color( $u->{'bgcolor'} );
    $o->{'fgcolor'} = S2::Builtin::LJ::Color__Color( $u->{'fgcolor'} );
    return $o;
}

sub Null {
    my $type = shift;
    return {
        '_type'   => $type,
        '_isnull' => 1,
    };
}

sub Page {
    my ( $u, $opts ) = @_;
    my $styleid  = $u->{'_s2styleid'} + 0;
    my $base_url = $u->{'_journalbase'};

    my $get = $opts->{'getargs'};
    my %args;
    foreach my $k ( keys %$get ) {
        my $v = $get->{$k};
        next unless $k =~ s/^\.//;
        $args{$k} = $v;
    }

    my $layoutname;
    my $themename;
    my $layouturl;

    $layouturl = "";

    if ($styleid) {
        my $style = load_style($styleid);
        my $theme;

        if ( $style && $style->{layer}->{theme} ) {
            $theme = LJ::S2Theme->new(
                themeid          => $style->{layer}->{theme},
                user             => $opts->{style_u} || $u,
                undef_if_missing => 1
            );
        }

        if ($theme) {
            $layoutname = $theme->layout_name;
            $themename  = $theme->name;
            $layouturl  = "$LJ::SITEROOT/customize/?layoutid=" . $theme->layoutid
                if $theme->is_system_layout;
        }
        else {
            $layoutname = S2::get_layer_info( $style->{layer}->{layout}, 'name' );
            $themename  = LJ::Lang::ml("s2theme.themename.notheme");
        }
    }

    # get MAX(modtime of style layers)
    my $stylemodtime = S2::get_style_modtime( $opts->{'ctx'} );
    if ($styleid) {
        my $style = load_style($styleid);
        $stylemodtime = $style->{'modtime'} if $style->{'modtime'} > $stylemodtime;
    }

    my $linkobj  = LJ::Links::load_linkobj($u);
    my $linklist = [ map { UserLink($_) } @$linkobj ];

    my $remote = LJ::get_remote();
    my $tz_remote;
    if ($remote) {
        my $tz = $remote->prop("timezone");
        $tz_remote = $tz ? eval { DateTime::TimeZone->new( name => $tz ); } : undef;
    }

    unless ( $u->prop('customtext_content') ) {
        $u->set_prop( 'customtext_content',
            $opts->{ctx}->[S2::PROPS]->{text_module_customtext_content} );
    }
    unless ( $u->prop('customtext_url') ) {
        $u->set_prop( 'customtext_url', $opts->{ctx}->[S2::PROPS]->{text_module_customtext_url} );
    }
    if (   !defined $u->prop('customtext_title')
        || $u->prop('customtext_title') eq ''
        || $u->prop('customtext_title') eq "Custom Text" )
    {
        $u->set_prop( 'customtext_title', $opts->{ctx}->[S2::PROPS]->{text_module_customtext} );
    }

    my $r = DW::Request->get;
    my $p = {
        '_type'          => 'Page',
        '_u'             => $u,
        'view'           => '',
        'args'           => \%args,
        'journal'        => User($u),
        'journal_type'   => $u->{'journaltype'},
        'layout_name'    => $layoutname,
        'theme_name'     => $themename,
        'layout_url'     => $layouturl,
        'time'           => DateTime_unix(time),
        'local_time'     => $tz_remote ? DateTime_tz( time, $tz_remote ) : DateTime_unix(time),
        'base_url'       => $base_url,
        'stylesheet_url' => "$base_url/res/$styleid/stylesheet?$stylemodtime",
        'view_url'       => {
            recent   => LJ::create_url( "/", viewing_style => 1 ),
            userinfo => $u->profile_url,
            archive  => LJ::create_url( "/archive", viewing_style => 1 ),
            read     => LJ::create_url( "/read", viewing_style => 1 ),
            network  => LJ::create_url( "/network", viewing_style => 1 ),
            tags     => LJ::create_url( "/tag/", viewing_style => 1 ),
            memories => "$LJ::SITEROOT/tools/memories?user=$u->{user}",
        },
        'linklist'            => $linklist,
        'customtext_title'    => escape_prop_value_ret( $u->prop('customtext_title'), 'plain' ),
        'customtext_url'      => escape_prop_value_ret( $u->prop('customtext_url'), 'plain' ),
        'customtext_content'  => escape_prop_value_ret( $u->prop('customtext_content'), 'html' ),
        'views_order'         => [ 'recent', 'archive', 'read', 'tags', 'memories', 'userinfo' ],
        'global_title'        => LJ::ehtml( $u->{'journaltitle'} || $u->{'name'} ),
        'global_subtitle'     => LJ::ehtml( $u->{'journalsubtitle'} ),
        'head_content'        => '',
        'data_link'           => {},
        'data_links_order'    => [],
        _styleopts            => LJ::viewing_style_opts(%$get),
        timeformat24          => $remote && $remote->use_24hour_time,
        include_meta_viewport => $r->cookie('no_mobile') ? 0 : 1,
    };

    if ( $opts && $opts->{'saycharset'} ) {
        $p->{'head_content'} .=
              '<meta http-equiv="Content-Type" content="text/html; charset='
            . $opts->{'saycharset'}
            . "\" />\n";
    }

    if ( LJ::Hooks::are_hooks('s2_head_content_extra') ) {
        $p->{head_content} .= LJ::Hooks::run_hook( 's2_head_content_extra', $remote, $opts->{r} );
    }

    my %meta_opts =
        $opts
        ? (
        feeds  => $opts->{addfeeds},
        tags   => $opts->{tags},
        openid => $opts->{addopenid},
        )
        : ();
    $meta_opts{remote} = $remote;
    $p->{head_content} .= $u->meta_discovery_links(%meta_opts);

    # other useful link rels
    $p->{head_content} .= qq{<link rel="help" href="$LJ::SITEROOT/support/faq" />\n};
    $p->{head_content} .= qq{<link rel="apple-touch-icon" href="$LJ::APPLE_TOUCH_ICON" />\n}
        if $LJ::APPLE_TOUCH_ICON;
    $p->{head_content} .= qq{<meta property="og:image" content="$LJ::FACEBOOK_PREVIEW_ICON"/>\n}
        if $LJ::FACEBOOK_PREVIEW_ICON;
    $p->{head_content} .= qq{<meta property="og:image:width" content="363"/>\n};
    $p->{head_content} .= qq{<meta property="og:image:height" content="363"/>\n};

    # Identity (type I) accounts only have read views
    $p->{views_order} = [ 'read', 'userinfo' ] if $u->is_identity;

    # feed accounts only have recent entries views
    $p->{views_order} = [ 'recent', 'archive', 'userinfo' ] if $u->is_syndicated;
    $p->{views_order} = [ 'recent', 'archive', 'read', 'network', 'tags', 'memories', 'userinfo' ]
        if $u->can_use_network_page;

    $p->{has_activeentries} = 0;

    # don't need to load active entries if the user does not have the cap to display them
    if ( $u->can_use_active_entries ) {
        my @active = $u->active_entries;

        # array to hold the Entry objects
        my @activeentries;
        foreach my $itemid (@active) {
            my $entry_obj = LJ::Entry->new( $u, jitemid => $itemid );

            # copy over $opts so that we don't inadvertently affect other things
            my $activeentry_opts = { %{ $opts || {} }, no_entry_body => 1 };

            # only show the entries $remote has the permission to view
            if ( $entry_obj->visible_to($remote) ) {
                my $activeentry = Entry_from_entryobj( $u, $entry_obj, $activeentry_opts );
                push @{ $p->{activeentries} }, $activeentry;

             # if at least one is accessible to $remote , show active entries module on journal page
                $p->{has_activeentries} = 1;
            }
        }
    }

    return $p;
}

sub Link {
    my ( $url, $caption, $icon, %extra ) = @_;

    my $lnk = {
        '_type'   => 'Link',
        'caption' => $caption,
        'url'     => $url,
        'icon'    => $icon,
        'extra'   => {%extra},
    };

    return $lnk;
}

sub Image {
    my ( $url, $w, $h, $alttext, %extra ) = @_;
    return {
        '_type'   => 'Image',
        'url'     => $url,
        'width'   => $w,
        'height'  => $h,
        'alttext' => $alttext,
        'extra'   => {%extra},
    };
}

sub Image_std {
    my $name = shift;
    my $ctx  = $LJ::S2::CURR_CTX or die "No S2 context available ";

    my $imgprefix = $LJ::IMGPREFIX;
    $imgprefix =~ s/^https?://;

    unless ( $LJ::S2::RES_MADE++ ) {
        $LJ::S2::RES_CACHE = {};
        my $textmap = {
            'security-protected' => 'text_icon_alt_protected',
            'security-private'   => 'text_icon_alt_private',
            'security-groups'    => 'text_icon_alt_groups',
            'adult-nsfw'         => 'text_icon_alt_nsfw',
            'adult-18'           => 'text_icon_alt_18',
            'sticky-entry'       => 'text_icon_alt_sticky_entry',
            'admin-post'         => 'text_icon_alt_admin_post',
        };
        foreach ( keys %$textmap ) {
            my $i = $LJ::Img::img{$_};
            $LJ::S2::RES_CACHE->{$_} =
                Image( "$imgprefix$i->{src}", $i->{width}, $i->{height},
                $ctx->[S2::PROPS]->{ $textmap->{$_} } );
        }

        # additional icons from LJ::Img
        # with alt text from translation system
        my @ic = qw( btn_del btn_freeze btn_unfreeze btn_scr btn_unscr
            editcomment editentry edittags tellfriend memadd
            prev_entry next_entry track untrack atom rss );
        foreach (@ic) {
            my $i = $LJ::Img::img{$_};
            $LJ::S2::RES_CACHE->{$_} =
                Image( "$imgprefix$i->{src}", $i->{width}, $i->{height},
                LJ::Lang::ml( $i->{alt} ) );
        }
    }
    return $LJ::S2::RES_CACHE->{$name};
}

sub Image_userpic {
    my ( $u, $picid, $kw, $width, $height ) = @_;

    $picid ||= $u->get_picid_from_keyword($kw) if LJ::isu($u);
    return Null("Image") unless $picid;

    # get the Userpic object
    my $p = LJ::Userpic->new( $u, $picid );

    #  load the dimensions, unless they have been passed in explicitly
    $width  ||= $p->width;
    $height ||= $p->height;

    my $alttext = $p->alttext($kw);
    my $title   = $p->titletext($kw);

    return {
        '_type'   => "Image",
        'url'     => "$LJ::USERPIC_ROOT/$picid/$u->{'userid'}",
        'width'   => $width,
        'height'  => $height,
        'alttext' => $alttext,
        'extra'   => { title => $title },
    };
}

sub ItemRange_fromopts {
    my $opts = shift;
    my $ir   = {};

    my $items     = $opts->{'items'};
    my $page_size = ( $opts->{'pagesize'} + 0 ) || 25;
    my $page      = $opts->{'page'} + 0 || 1;
    my $num_items = scalar @$items;

    my $pages = POSIX::ceil( $num_items / $page_size ) || 1;
    if ( $page > $pages ) { $page = $pages; }

    splice( @$items, 0, ( $page - 1 ) * $page_size ) if $page > 1;
    splice( @$items, $page_size ) if @$items > $page_size;

    $ir->{'current'}                = $page;
    $ir->{'total'}                  = $pages;
    $ir->{'total_subitems'}         = $num_items;
    $ir->{'from_subitem'}           = ( $page - 1 ) * $page_size + 1;
    $ir->{'num_subitems_displayed'} = @$items;
    $ir->{'to_subitem'}             = $ir->{'from_subitem'} + $ir->{'num_subitems_displayed'} - 1;
    $ir->{'all_subitems_displayed'} = ( $pages == 1 );
    $ir->{'url_all'}                = $opts->{'url_all'} unless $ir->{'all_subitems_displayed'};
    $ir->{'_url_of'}                = $opts->{'url_of'};
    return ItemRange($ir);
}

sub ItemRange {
    my $h = shift;    # _url_of = sub($n)
    $h->{'_type'} = "ItemRange";

    my $url_of = ref $h->{'_url_of'} eq "CODE" ? $h->{'_url_of'} : sub { ""; };

    $h->{'url_next'} = $url_of->( $h->{'current'} + 1 )
        unless $h->{'current'} >= $h->{'total'};
    $h->{'url_prev'} = $url_of->( $h->{'current'} - 1 )
        unless $h->{'current'} <= 1;
    $h->{'url_first'} = $url_of->(1)
        unless $h->{'current'} == 1;
    $h->{'url_last'} = $url_of->( $h->{'total'} )
        unless $h->{'current'} == $h->{'total'};

    return $h;
}

sub CommentNav {
    my $h = shift;
    $h->{'_type'} = "CommentNav";

    return $h;
}

sub User {
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'}        = "User";
    $o->{'default_pic'}  = Image_userpic( $u, $u->{'defaultpicid'} );
    $o->{'website_url'}  = LJ::ehtml( $u->{'url'} );
    $o->{'website_name'} = LJ::ehtml( $u->{'urlname'} );
    return $o;
}

sub UserLink {
    my $link = shift;    # hashref

    # a dash means pass to s2 as blank so it will just insert a blank line
    $link->{'title'} = '' if $link->{'title'} eq "-";

    return {
        '_type'      => 'UserLink',
        'is_heading' => $link->{'url'} ? 0 : 1,
        'url'        => LJ::ehtml( $link->{'url'} ),
        'title'      => LJ::ehtml( $link->{'title'} ),
        'hover'      => LJ::ehtml( $link->{'hover'} ),
        'children'   => $link->{'children'} || [],      # TODO: implement parent-child relationships
    };
}

sub UserLite {
    my ($u) = @_;
    my $o;
    return $o unless $u;

    $o = {
        '_type'               => 'UserLite',
        '_u'                  => $u,
        'user'                => LJ::ehtml( $u->user ),
        'username'            => LJ::ehtml( $u->display_name ),
        'name'                => LJ::ehtml( $u->{'name'} ),
        'journal_type'        => $u->{'journaltype'},
        'userpic_listing_url' => $u->allpics_base,
        'link_keyseq'         => [],
    };
    my $lks = $o->{link_keyseq};
    push @$lks, qw(manage_membership trust watch post_entry track message);
    push @$lks, 'tell_friend' if LJ::is_enabled('tellafriend');

    # TODO: Figure out some way to use the userinfo_linkele hook here?

    return $o;
}

# Given an S2 Entry object, return if it's the first, second, third, etc. entry that we've seen
sub nth_entry_seen {
    my $e   = shift;
    my $key = "$e->{'journal'}->{'username'}-$e->{'itemid'}";
    my $ref = $LJ::REQ_GLOBAL{'nth_entry_keys'};

    if ( exists $ref->{$key} ) {
        return $ref->{$key};
    }
    return $LJ::REQ_GLOBAL{'nth_entry_keys'}->{$key} = ++$LJ::REQ_GLOBAL{'nth_entry_ct'};
}

sub sitescheme_secs_to_iso {
    my ( $secs, $opts ) = @_;
    my $remote = LJ::get_remote();
    my @ret;

    # time format (12/24 hr)
    my $fmt_time = "%%hh%%:%%min%% %%a%%m";    # 12-hr default
    $fmt_time = "%%HH%%:%%min%%" if $remote && $remote->use_24hour_time;

    # convert date to S2 object
    my $s2_ctx = [];                           # fake S2 context object

    my $s2_datetime;
    my $has_tz = '';                           # don't display timezone unless requested below

    # if opts has a true tz key, get the remote user's timezone if possible
    if ( $opts->{tz} ) {
        $s2_datetime = DateTime_tz( $secs, $remote );
        $has_tz      = defined $s2_datetime ? "(local)" : "UTC";
    }

    # if timezone execution failed, use GMT
    $s2_datetime = DateTime_unix($secs) unless defined $s2_datetime;

    my @s2_args = ( $s2_ctx, $s2_datetime );

    # reformat date and time display for user
    push @ret, S2::Builtin::LJ::Date__date_format( @s2_args, "iso" );
    push @ret, S2::Builtin::LJ::DateTime__time_format( @s2_args, $fmt_time );
    push @ret, $has_tz;

    return join ' ', @ret;
}

# adectomy
sub current_box_type        { }
sub curr_page_supports_ebox { 0 }

# Convenience method since it gets checked multiple times
sub has_quickreply {
    my ($page) = @_;
    return 0 if $page->{_type} eq 'EntryPreviewPage';

    my $view = $page->{view};

    # Also needs adding to the list in core2.s2
    return
           $view eq 'entry'
        || $view eq 'read'
        || $view eq 'day'
        || $view eq 'recent'
        || $view eq 'network';
}

###############

package S2::Builtin::LJ;
use strict;

sub UserLite {
    my ( $ctx, $user ) = @_;
    my $u = LJ::load_user($user);
    return LJ::S2::UserLite($u);
}

sub start_css {
    my ($ctx) = @_;
    my $sc = $ctx->[S2::SCRATCH];

    # Always increment, but only continue if it was 0
    return if $sc->{_css_depth}++;

    $sc->{_start_css_pout}   = S2::get_output();
    $sc->{_start_css_pout_s} = S2::get_output_safe();
    $sc->{_start_css_buffer} = "";
    my $printer = sub {
        my $arg = shift;
        $sc->{_start_css_buffer} .= $arg if defined $arg;
    };
    S2::set_output($printer);
    S2::set_output_safe($printer);
}

sub end_css {
    my ($ctx) = @_;
    my $sc = $ctx->[S2::SCRATCH];

    # Only decrement _css_depth if it is non-zero, only continue if it becomes zero
    return unless $sc->{_css_depth} && ( --$sc->{_css_depth} == 0 );

    # restore our printer/safe printer
    S2::set_output( $sc->{_start_css_pout} );
    S2::set_output_safe( $sc->{_start_css_pout_s} );

    # our CSS to clean:
    my $css     = $sc->{_start_css_buffer};
    my $cleaner = LJ::CSS::Cleaner->new;

    my $clean = $cleaner->clean($css);
    LJ::Hooks::run_hook( 'css_cleaner_transform', \$clean );

    $sc->{_start_css_pout}->( "/* Cleaned CSS: */\n" . $clean . "\n" );
}

sub alternate {
    my ( $ctx, $one, $two ) = @_;

    my $scratch = $ctx->[S2::SCRATCH];

    $scratch->{alternate}{"$one\0$two"} = !$scratch->{alternate}{"$one\0$two"};
    return $scratch->{alternate}{"$one\0$two"} ? $one : $two;
}

sub clean_css_classname {
    my ( $ctx, $classname ) = @_;
    my $clean_classname;

    if ( $classname =~ /eval/ ) {
        $clean_classname = $classname . " ";
        $classname =~ s/eval/ev-l/g;
        $clean_classname .= $classname;
    }
    else {
        $clean_classname = $classname;
    }
    return $clean_classname;
}

sub get_image {
    return LJ::S2::Image_std( $_[1] );
}

sub set_content_type {
    my ( $ctx, $type ) = @_;

    die "set_content_type is not yet implemented";
    $ctx->[S2::SCRATCH]->{contenttype} = $type;
}

sub striphtml {
    my ( $ctx, $s ) = @_;

    $s =~ s/<.*?>//g;
    return $s;
}

sub ehtml {
    my ( $ctx, $text ) = @_;
    return LJ::ehtml($text);
}

sub eurl {
    my ( $ctx, $text ) = @_;
    return LJ::eurl($text);
}

# escape tags only
sub etags {
    my ( $ctx, $text ) = @_;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

# sanitize URLs
sub clean_url {
    my ( $ctx, $text ) = @_;
    unless ( $text =~ m!^https?://[^\'\"\\]*$! ) {
        $text = "";
    }
    return $text;
}

sub get_page {
    return $LJ::S2::CURR_PAGE;
}

sub get_plural_phrase {
    my ( $ctx, $n, $prop ) = @_;
    $n = 0 unless defined $n;
    my $form = S2::run_function( $ctx, "lang_map_plural(int)", $n );
    my $a    = $ctx->[S2::PROPS]->{"_plurals_$prop"};
    unless ( ref $a eq "ARRAY" ) {
        $a = $ctx->[S2::PROPS]->{"_plurals_$prop"} =
            [ split( m!\s*//\s*!, $ctx->[S2::PROPS]->{$prop} ) ];
    }
    my $text = $a->[$form];

    # this fixes missing plural forms for russians (who have 2 plural forms)
    # using languages like english with 1 plural form
    $text = $a->[-1] unless defined $text;

    $text =~ s/\#/$n/;
    return LJ::ehtml($text);
}

sub get_url {
    my ( $ctx, $obj, $view ) = @_;
    my $user;

    # now get data from one of two paths, depending on if we were given a UserLite
    # object or a string for the username, so make sure we have the username.
    if ( ref $obj eq 'HASH' ) {
        $user = $obj->{user};
    }
    else {
        $user = $obj;
    }

    my $u = LJ::load_user($user);
    return "" unless $u;

    # construct URL to return
    $view = "profile" if $view eq "userinfo";
    $view = ""        if $view eq "recent";
    my $base = $u->journal_base;
    return "$base/$view";
}

sub htmlattr {
    my ( $ctx, $name, $value ) = @_;
    return "" if $value eq "";
    $name = lc($name);
    return "" if $name =~ /[^a-z]/;
    return " $name=\"" . LJ::ehtml($value) . "\"";
}

sub rand {
    my ( $ctx, $aa, $bb ) = @_;
    my ( $low, $high );
    if ( ref $aa eq "ARRAY" ) {
        ( $low, $high ) = ( 0, @$aa - 1 );
    }
    elsif ( !defined $bb ) {
        ( $low, $high ) = ( 1, $aa );
    }
    else {
        ( $low, $high ) = ( $aa, $bb );
    }
    return int( CORE::rand( $high - $low + 1 ) ) + $low;
}

sub pageview_unique_string {
    my ($ctx) = @_;

    return LJ::pageview_unique_string();
}

sub viewer_logged_in {
    my $remote = LJ::get_remote();
    return defined $remote;
}

sub viewer_is_owner {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined($LJ::S2::CURR_PAGE);
    return $remote->equals( $LJ::S2::CURR_PAGE->{_u} );
}

# NOTE: this method is old and deprecated, but we still support it for people
# who are importing styles from old sites.  since we don't know if the style
# is asking if the viewer is "watched" or if they're "trusted", we default to
# returning true if they're trusted.  since we believe that the majority of
# trust relationships also include a watch relationship, this should be the
# right behavior in 90%+ of cases.  in the few that it is not, we humbly
# suggest that people update their styles to use the DW core/functions.
sub viewer_is_friend {
    return viewer_has_access();
}

sub viewer_has_access {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined($LJ::S2::CURR_PAGE);

    my $ju = $LJ::S2::CURR_PAGE->{_u};
    return viewer_is_member() if $ju->is_community;
    return $ju->trusts($remote);
}

sub viewer_is_subscribed {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined $LJ::S2::CURR_PAGE;

    my $ju = $LJ::S2::CURR_PAGE->{_u};
    return $remote->watches($ju);
}

sub viewer_is_member {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined($LJ::S2::CURR_PAGE);

    my $ju = $LJ::S2::CURR_PAGE->{_u};
    return 0 unless $ju->is_community;
    return $remote->member_of($ju);
}

sub viewer_is_admin {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined $LJ::S2::CURR_PAGE;

    my $ju = $LJ::S2::CURR_PAGE->{_u};
    return 0 unless $ju->is_community;
    return $remote->can_manage($ju);
}

sub viewer_is_moderator {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined $LJ::S2::CURR_PAGE;

    my $ju = $LJ::S2::CURR_PAGE->{_u};
    return 0 unless $ju->is_community;
    return $remote->can_moderate($ju);
}

sub viewer_can_manage_tags {
    return 0 unless defined $LJ::S2::CURR_PAGE;

    my $ju = $LJ::S2::CURR_PAGE->{_u};

    # use the same function as that used in /manage/tags
    return LJ::get_authas_user( $ju->user ) ? 1 : 0;
}

sub viewer_sees_control_strip {
    my $apache_r = BML::get_request();
    return LJ::Hooks::run_hook('show_control_strip');
}

# Returns true if the viewer can search this person's journal
sub viewer_can_search {
    my $remote = LJ::get_remote();
    return 0 unless $remote;
    return 0 unless defined $LJ::S2::CURR_PAGE;

    my $ju = $LJ::S2::CURR_PAGE->{_u};

    # return based on this function
    return $ju->allow_search_by($remote);
}

# Returns a search form for this journal
sub print_search_form {
    return "" unless defined($LJ::S2::CURR_PAGE);

    my $ju = $LJ::S2::CURR_PAGE->{_u};

    my $search_form = '<div class="search-form">';
    $search_form .=
        '<form method="post" action="' . $LJ::SITEROOT . '/search?user=' . $ju->user . '">';
    $search_form .= LJ::form_auth();
    $search_form .=
'<span class="search-box-item"><input class="search-box" type="text" name="query" maxlength="255"></span>';
    if ( $ju->allow_comments_indexed ) {
        $search_form .=
'<span class="comment_search_checkbox_item"><input class="comment_search_checkbox" name="with_comments" id="with_comments" type="checkbox"></span>';
        $search_form .=
'<span class="comment_search_label"><label for="with_comments">Include comments</label></span>';
    }
    $search_form .=
          '<span class="search-button-item"><input class="search-button" type="submit" value="'
        . $_[1]
        . '" /></span>';
    $search_form .= '</form></div>';

    S2::pout($search_form);
}

# maintained only for compatibility with core1, eventually these can be removed
# when we've upgraded everybody.  or we keep this cruft until the cows come home
# as a stolid reminder to our past.
sub viewer_sees_vbox        { 0 }
sub viewer_sees_hbox_top    { 0 }
sub viewer_sees_hbox_bottom { 0 }
sub viewer_sees_ad_box      { 0 }
sub viewer_sees_ebox        { 0 }
sub viewer_sees_ads         { 0 }
sub _get_Entry_ebox_args    { 0 }
sub Entry__viewer_sees_ebox { 0 }

sub control_strip_logged_out_userpic_css {
    my $apache_r = BML::get_request();
    my $u        = LJ::load_userid( $apache_r->notes->{journalid} );
    return '' unless $u;

    return LJ::Hooks::run_hook( 'control_strip_userpic', $u );
}

sub control_strip_logged_out_full_userpic_css {
    my $apache_r = BML::get_request();
    my $u        = LJ::load_userid( $apache_r->notes->{journalid} );
    return '' unless $u;

    return LJ::Hooks::run_hook( 'control_strip_loggedout_userpic', $u );
}

sub weekdays {
    my ($ctx) = @_;
    return S2::get_property_value( $ctx, 'reg_firstdayofweek' ) eq "monday"
        ? [ 2 .. 7, 1 ]
        : [ 1 .. 7 ];
}

sub journal_current_datetime {
    my ($ctx) = @_;

    my $ret = { '_type' => 'DateTime' };

    my $apache_r = BML::get_request();
    my $u        = LJ::load_userid( $apache_r->notes->{journalid} );
    return $ret unless $u;

    # turn the timezone offset number into a four character string (plus '-' if negative)
    # e.g. -1000, 0700, 0430
    my $timezone = $u->timezone;

    my $partial_hour = "00";
    if ( $timezone =~ /(\.\d+)/ ) {
        $partial_hour = $1 * 60;
    }

    my $neg  = $timezone =~ /-/ ? 1 : 0;
    my $hour = sprintf( "%02d", abs( int($timezone) ) );    # two character hour
    $hour     = $neg ? "-$hour" : "$hour";
    $timezone = $hour . $partial_hour;

    my $now = DateTime->now( time_zone => $timezone );
    $ret->{year}  = $now->year;
    $ret->{month} = $now->month;
    $ret->{day}   = $now->day;
    $ret->{hour}  = $now->hour;
    $ret->{min}   = $now->minute;
    $ret->{sec}   = $now->second;

    # DateTime.pm's dayofweek is 1-based/Mon-Sun, but S2's is 1-based/Sun-Sat,
    # so first we make DT's be 0-based/Sun-Sat, then shift it up to 1-based.
    $ret->{_dayofweek} = ( $now->day_of_week % 7 ) + 1;

    return $ret;
}

sub SubscriptionFilter {
    my ( $name, $sortorder, $public, $url ) = @_;
    return {
        '_type'     => 'SubscriptionFilter',
        'name'      => $name,
        'public'    => $public ? 1 : 0,
        'sortorder' => $sortorder,
        'url'       => $url,
    };
}

sub journal_subscription_filters {
    my ($ctx) = @_;

    # only owners can see non-public filters
    my $public_only = not viewer_is_owner();
    my @ret;

    # automatically gets the content filters in the right order
    my @filters = $LJ::S2::CURR_PAGE->{_u}->content_filters;
    foreach my $filter (@filters) {
        my $filterurl = $LJ::S2::CURR_PAGE->{_u}->journal_base() . "/read/$filter->{name}";
        my $subfilter =
            SubscriptionFilter( $filter->name, $filter->sortorder, $filter->public, $filterurl );
        push @ret, $subfilter if ( $filter->public || !$public_only );
    }

    return \@ret;
}

sub style_is_active {
    my ($ctx)    = @_;
    my $layoutid = $ctx->[S2::LAYERLIST]->[1];
    my $themeid  = $ctx->[S2::LAYERLIST]->[2];
    my $pub      = LJ::S2::get_public_layers();

    my $layout_is_active = LJ::Hooks::run_hook( "layer_is_active", $pub->{$layoutid}->{uniq} );
    return 0 unless !defined $layout_is_active || $layout_is_active;

    if ( defined $themeid ) {
        my $theme_is_active = LJ::Hooks::run_hook( "layer_is_active", $pub->{$themeid}->{uniq} );
        return 0 unless !defined $theme_is_active || $theme_is_active;
    }

    return 1;
}

sub set_handler {
    my ( $ctx, $hook, $stmts ) = @_;
    my $p = $LJ::S2::CURR_PAGE;
    return unless $hook =~ /^\w+\#?$/;
    $hook =~ s/\#$/ARG/;

    $S2::pout->("<script> function userhook_$hook () {\n");
    foreach my $st (@$stmts) {
        my ( $cmd, @args ) = @$st;

        my $get_domexp = sub {
            my $domid  = shift @args;
            my $domexp = "";
            while ( $domid ne "" ) {
                $domexp .= " + " if $domexp;
                if ( $domid =~ s/^(\w+)// ) {
                    $domexp .= "\"$1\"";
                }
                elsif ( $domid =~ s/^\#// ) {
                    $domexp .= "arguments[0]";
                }
                else {
                    return undef;
                }
            }
            return $domexp;
        };

        my $get_color = sub {
            my $color = shift @args;
            return undef
                unless $color =~ /^\#[0-9a-f]{3,3}$/
                || $color =~ /^\#[0-9a-f]{6,6}$/
                || $color =~ /^\w+$/
                || $color =~ /^rgb(\d+,\d+,\d+)$/;
            return $color;
        };

        #$S2::pout->("  // $cmd: @args\n");
        if ( $cmd eq "style_bgcolor" || $cmd eq "style_color" ) {
            my $domexp = $get_domexp->();
            my $color  = $get_color->();
            if ( $domexp && $color ) {
                $S2::pout->("setStyle($domexp, 'background', '$color');\n")
                    if $cmd eq "style_bgcolor";
                $S2::pout->("setStyle($domexp, 'color', '$color');\n") if $cmd eq "style_color";
            }
        }
        elsif ( $cmd eq "set_class" ) {
            my $domexp = $get_domexp->();
            my $class  = shift @args;
            if ( $domexp && $class =~ /^\w+$/ ) {
                $S2::pout->("setAttr($domexp, 'class', '$class');\n");
            }
        }
        elsif ( $cmd eq "set_image" ) {
            my $domexp = $get_domexp->();
            my $url    = shift @args;
            if ( $url =~ m!^https?://! && $url !~ /[\'\"\n\r]/ ) {
                $url = LJ::eurl($url);
                $S2::pout->("setAttr($domexp, 'src', \"$url\");\n");
            }
        }
    }
    $S2::pout->("} </script>\n");
}

sub zeropad {
    my ( $ctx, $num, $digits ) = @_;
    $num    += 0;
    $digits += 0;
    return sprintf( "%0${digits}d", $num );
}
*int__zeropad = \&zeropad;

sub int__compare {
    my ( $ctx, $this, $other ) = @_;
    return $other <=> $this;
}

sub _Color__update_hsl {
    my ( $this, $force ) = @_;
    return if $this->{'_hslset'}++;
    ( $this->{'_h'}, $this->{'_s'}, $this->{'_l'} ) =
        S2::Color::rgb_to_hsl( $this->{'r'}, $this->{'g'}, $this->{'b'} );
    $this->{$_} = int( $this->{$_} * 255 + 0.5 ) foreach qw(_h _s _l);
}

sub _Color__update_rgb {
    my ($this) = @_;

    ( $this->{'r'}, $this->{'g'}, $this->{'b'} ) =
        S2::Color::hsl_to_rgb( map { $this->{$_} / 255 } qw(_h _s _l) );
    _Color__make_string($this);
}

sub _Color__make_string {
    my ($this) = @_;
    $this->{'as_string'} = sprintf( "\#%02x%02x%02x", $this->{'r'}, $this->{'g'}, $this->{'b'} );
}

# public functions
sub Color__Color {
    my ($s) = @_;
    $s =~ s/^\#//;
    $s =~ s/^(\w)(\w)(\w)$/$1$1$2$2$3$3/s;    #  'c30' => 'cc3300'
    return { '_type' => 'Color', as_string => "" } if $s eq "";
    return if $s =~ /[^a-fA-F0-9]/ || length($s) != 6;

    my $this = { '_type' => 'Color' };
    $this->{'r'} = hex( substr( $s, 0, 2 ) );
    $this->{'g'} = hex( substr( $s, 2, 2 ) );
    $this->{'b'} = hex( substr( $s, 4, 2 ) );
    $this->{$_} = $this->{$_} % 256 foreach qw(r g b);

    _Color__make_string($this);
    return $this;
}

sub Color__clone {
    my ( $ctx, $this ) = @_;
    return {%$this};
}

sub Color__set_hsl {
    my ( $ctx, $this, $h, $s, $l ) = @_;
    $this->{_h}      = $h % 256;
    $this->{_s}      = $s % 256;
    $this->{_l}      = $l % 256;
    $this->{_hslset} = 1;
    _Color__update_rgb($this);
}

sub Color__red {
    my ( $ctx, $this, $r ) = @_;
    if ( defined $r ) {
        $this->{'r'} = $r % 256;
        delete $this->{'_hslset'};
        _Color__make_string($this);
    }
    $this->{'r'};
}

sub Color__green {
    my ( $ctx, $this, $g ) = @_;
    if ( defined $g ) {
        $this->{'g'} = $g % 256;
        delete $this->{'_hslset'};
        _Color__make_string($this);
    }
    $this->{'g'};
}

sub Color__blue {
    my ( $ctx, $this, $b ) = @_;
    if ( defined $b ) {
        $this->{'b'} = $b % 256;
        delete $this->{'_hslset'};
        _Color__make_string($this);
    }
    $this->{'b'};
}

sub Color__hue {
    my ( $ctx, $this, $h ) = @_;

    _Color__update_hsl($this) unless $this->{_hslset};
    if ( defined $h ) {
        $this->{_h} = $h % 256;
        _Color__update_rgb($this);
    }

    $this->{_h};
}

sub Color__saturation {
    my ( $ctx, $this, $s ) = @_;

    _Color__update_hsl($this) unless $this->{_hslset};
    if ( defined $s ) {
        $this->{_s} = $s % 256;
        _Color__update_rgb($this);
    }

    $this->{_s};
}

sub Color__lightness {
    my ( $ctx, $this, $l ) = @_;

    _Color__update_hsl($this) unless $this->{_hslset};
    if ( defined $l ) {
        $this->{_l} = $l % 256;
        _Color__update_rgb($this);
    }

    $this->{_l};
}

sub Color__inverse {
    my ( $ctx, $this ) = @_;
    my $new = {
        '_type' => 'Color',
        'r'     => 255 - $this->{'r'},
        'g'     => 255 - $this->{'g'},
        'b'     => 255 - $this->{'b'},
    };
    _Color__make_string($new);
    return $new;
}

sub Color__average {
    my ( $ctx, $this, $other ) = @_;
    my $new = {
        '_type' => 'Color',
        'r'     => int( ( $this->{'r'} + $other->{'r'} ) / 2 + .5 ),
        'g'     => int( ( $this->{'g'} + $other->{'g'} ) / 2 + .5 ),
        'b'     => int( ( $this->{'b'} + $other->{'b'} ) / 2 + .5 ),
    };
    _Color__make_string($new);
    return $new;
}

sub Color__blend {
    my ( $ctx, $this, $other, $value ) = @_;
    my $multiplier = $value / 100;
    my $new        = {
        '_type' => 'Color',
        'r'     => int( $this->{'r'} - ( ( $this->{'r'} - $other->{'r'} ) * $multiplier ) + .5 ),
        'g'     => int( $this->{'g'} - ( ( $this->{'g'} - $other->{'g'} ) * $multiplier ) + .5 ),
        'b'     => int( $this->{'b'} - ( ( $this->{'b'} - $other->{'b'} ) * $multiplier ) + .5 ),
    };
    _Color__make_string($new);
    return $new;
}

sub Color__lighter {
    my ( $ctx, $this, $amt ) = @_;
    $amt = defined $amt ? $amt : 30;

    _Color__update_hsl($this);

    my $new = {
        '_type'   => 'Color',
        '_hslset' => 1,
        '_h'      => $this->{'_h'},
        '_s'      => $this->{'_s'},
        '_l'      => ( $this->{'_l'} + $amt > 255 ? 255 : $this->{'_l'} + $amt ),
    };

    _Color__update_rgb($new);
    return $new;
}

sub Color__darker {
    my ( $ctx, $this, $amt ) = @_;
    $amt = defined $amt ? $amt : 30;

    _Color__update_hsl($this);

    my $new = {
        '_type'   => 'Color',
        '_hslset' => 1,
        '_h'      => $this->{'_h'},
        '_s'      => $this->{'_s'},
        '_l'      => ( $this->{'_l'} - $amt < 0 ? 0 : $this->{'_l'} - $amt ),
    };

    _Color__update_rgb($new);
    return $new;
}

sub _Comment__get_link {
    my ( $ctx, $this, $key ) = @_;
    my $page      = get_page();
    my $u         = $page->{'_u'};
    my $post_user = $page->{'entry'} ? $page->{'entry'}->{'poster'}->{'user'} : undef;
    my $com_user  = $this->{'poster'} ? $this->{'poster'}->{'user'} : undef;
    my $remote    = LJ::get_remote();
    my $null_link = { '_type' => 'Link', '_isnull' => 1 };
    my $dtalkid   = $this->{talkid};
    my $comment   = LJ::Comment->new( $u, dtalkid => $dtalkid );

    if ( $key eq "delete_comment" ) {
        return $null_link unless LJ::Talk::can_delete( $remote, $u, $post_user, $com_user );
        return LJ::S2::Link(
            "$LJ::SITEROOT/delcomment?journal=$u->{'user'}&amp;id=$this->{'talkid'}",
            $ctx->[S2::PROPS]->{"text_multiform_opt_delete"},
            LJ::S2::Image_std('btn_del')
        );
    }
    if ( $key eq "freeze_thread" ) {
        return $null_link if $this->{'frozen'};
        return $null_link unless LJ::Talk::can_freeze( $remote, $u, $post_user, $com_user );
        return LJ::S2::Link(
"$LJ::SITEROOT/talkscreen?mode=freeze&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
            $ctx->[S2::PROPS]->{"text_multiform_opt_freeze"}, LJ::S2::Image_std('btn_freeze')
        );
    }
    if ( $key eq "unfreeze_thread" ) {
        return $null_link unless $this->{'frozen'};
        return $null_link unless LJ::Talk::can_unfreeze( $remote, $u, $post_user, $com_user );
        return LJ::S2::Link(
"$LJ::SITEROOT/talkscreen?mode=unfreeze&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
            $ctx->[S2::PROPS]->{"text_multiform_opt_unfreeze"},
            LJ::S2::Image_std('btn_unfreeze')
        );
    }
    if ( $key eq "screen_comment" ) {
        return $null_link if $this->{'screened'};
        return $null_link unless LJ::Talk::can_screen( $remote, $u, $post_user, $com_user );
        return LJ::S2::Link(
"$LJ::SITEROOT/talkscreen?mode=screen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
            $ctx->[S2::PROPS]->{"text_multiform_opt_screen"}, LJ::S2::Image_std('btn_scr')
        );
    }
    if ( $key eq "unscreen_comment" ) {
        return $null_link unless $this->{'screened'};
        return $null_link unless LJ::Talk::can_unscreen( $remote, $u, $post_user, $com_user );
        return LJ::S2::Link(
"$LJ::SITEROOT/talkscreen?mode=unscreen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
            $ctx->[S2::PROPS]->{"text_multiform_opt_unscreen"}, LJ::S2::Image_std('btn_unscr')
        );
    }

    # added new button
    if ( $key eq "unscreen_to_reply" ) {

        #return $null_link unless $this->{'screened'};
        #return $null_link unless LJ::Talk::can_unscreen($remote, $u, $post_user, $com_user);
        return LJ::S2::Link(
"$LJ::SITEROOT/talkscreen?mode=unscreen&amp;journal=$u->{'user'}&amp;talkid=$this->{'talkid'}",
            $ctx->[S2::PROPS]->{"text_multiform_opt_unscreen_to_reply"},
            LJ::S2::Image_std('btn_unscr')
        );
    }

    if ( $key eq "watch_thread" || $key eq "unwatch_thread" || $key eq "watching_parent" ) {
        return $null_link unless LJ::is_enabled('esn');
        return $null_link unless $remote && $remote->can_use_esn && $remote->can_track_thread;

        if ( $key eq "unwatch_thread" ) {
            return $null_link
                unless $remote->has_subscription(
                journal => $u,
                event   => "JournalNewComment",
                arg2    => $comment->jtalkid
                );

            my @subs = $remote->has_subscription(
                journal => $comment->entry->journal,
                event   => "JournalNewComment",
                arg2    => $comment->jtalkid
            );
            my $subscr = $subs[0];
            return $null_link unless $subscr;

            my $auth_token = $remote->ajax_auth_token(
                '/__rpc_esn_subs',
                subid  => $subscr->id,
                action => 'delsub'
            );

            my $etypeid = 'LJ::Event::JournalNewComment'->etypeid;

            return LJ::S2::Link(
                "$LJ::SITEROOT/manage/tracking/comments?journal=$u->{'user'}&amp;talkid="
                    . $comment->dtalkid,
                $ctx->[S2::PROPS]->{"text_multiform_opt_untrack"},
                LJ::S2::Image_std('untrack'),
                'lj_etypeid'    => $etypeid,
                'lj_journalid'  => $u->id,
                'lj_subid'      => $subscr->id,
                'class'         => 'TrackButton',
                'id'            => 'lj_track_btn_' . $dtalkid,
                'lj_dtalkid'    => $dtalkid,
                'lj_arg2'       => $comment->jtalkid,
                'lj_auth_token' => $auth_token,
                'js_swapname'   => $ctx->[S2::PROPS]->{text_multiform_opt_track}
            );
        }

        return $null_link
            if $remote->has_subscription(
            journal => $u,
            event   => "JournalNewComment",
            arg2    => $comment->jtalkid
            );

 # at this point, we know that the thread is either not being watched or its parent is being watched
 # in other words, the user is not subscribed to this particular comment

        # see if any parents are being watched
        my $watching_parent = $comment->thread_has_subscription( $remote, $u );

        my $etypeid   = 'LJ::Event::JournalNewComment'->etypeid;
        my %subparams = (
            journalid => $comment->entry->journal->id,
            etypeid   => $etypeid,
            arg2      => LJ::Comment->new( $comment->entry->journal, dtalkid => $dtalkid )->jtalkid,
        );
        my $auth_token =
            $remote->ajax_auth_token( '/__rpc_esn_subs', action => 'addsub', %subparams );

        my %btn_params = map { ( 'lj_' . $_, $subparams{$_} ) } keys %subparams;

        $btn_params{'class'}         = 'TrackButton';
        $btn_params{'lj_auth_token'} = $auth_token;
        $btn_params{'lj_subid'}      = 0;
        $btn_params{'lj_dtalkid'}    = $dtalkid;
        $btn_params{'id'}            = "lj_track_btn_" . $dtalkid;
        $btn_params{'js_swapname'}   = $ctx->[S2::PROPS]->{text_multiform_opt_untrack};

        if ( $key eq "watch_thread" && !$watching_parent ) {
            return LJ::S2::Link(
                "$LJ::SITEROOT/manage/tracking/comments?journal=$u->{'user'}&amp;talkid=$dtalkid",
                $ctx->[S2::PROPS]->{"text_multiform_opt_track"},
                LJ::S2::Image_std('track'),
                %btn_params
            );
        }
        if ( $key eq "watching_parent" && $watching_parent ) {
            return LJ::S2::Link(
                "$LJ::SITEROOT/manage/tracking/comments?journal=$u->{'user'}&amp;talkid=$dtalkid",
                $ctx->[S2::PROPS]->{"text_multiform_opt_track"},
                LJ::S2::Image_std('untrack'),
                %btn_params
            );
        }
        return $null_link;
    }
    if ( $key eq "edit_comment" ) {
        return $null_link unless $comment->remote_can_edit;
        my $edit_url = $this->{edit_url} || $comment->edit_url;
        return LJ::S2::Link(
            $edit_url,
            $ctx->[S2::PROPS]->{"text_multiform_opt_edit"},
            LJ::S2::Image_std('editcomment')
        );
    }
    if ( $key eq "expand_comments" ) {
        return $null_link unless $u->show_thread_expander($remote);
        ## show "Expand" link only if
        ## 1) the comment is collapsed
        ## 2) any of comment's children are collapsed
        my $show_expand_link;
        if ( !$this->{full} and !$this->{deleted} ) {
            $show_expand_link = 1;
        }
        else {
            foreach my $c ( @{ $this->{replies} } ) {
                if ( !$c->{full} and !$c->{deleted} ) {
                    $show_expand_link = 1;
                    last;
                }
            }
        }
        return $null_link unless $show_expand_link;
        return LJ::S2::Link(
            "#",    ## actual link is javascript: onclick='....'
            $ctx->[S2::PROPS]->{"text_comment_expand"}
        );
    }
    if ( $key eq "hide_comments" ) {
        ## show "Hide/Show" link if the comment has any children
        # only show hide/show comments if using jquery
        if ( @{ $this->{replies} || [] } > 0 ) {
            return LJ::S2::Link(
                "#",    ## actual link is javascript: onclick='....'
                $ctx->[S2::PROPS]->{"text_comment_hide"}
            );
        }
        else {
            return $null_link;
        }
    }
    if ( $key eq "unhide_comments" ) {
        ## show "Hide/Unhide" link if the comment has any children
        # only show hide/show comments if using jquery
        if ( @{ $this->{replies} || [] } > 0 ) {
            return LJ::S2::Link(
                "#",    ## actual link is javascript: onclick='....'
                $ctx->[S2::PROPS]->{"text_comment_unhide"}
            );
        }
        else {
            return $null_link;
        }
    }
}

sub Comment__print_multiform_check {
    my ( $ctx, $this ) = @_;
    my $tid = $this->{'talkid'} >> 8;
    $S2::pout->(
"<input type='checkbox' name='selected_$tid' class='ljcomsel' id='ljcomsel_$this->{'talkid'}' />"
    );
}

sub Comment__print_reply_link {
    my ( $ctx, $this, $opts ) = @_;
    $opts ||= {};

    my $basesubject = $this->{'subject'};
    $opts->{'basesubject'} = $basesubject;
    $opts->{'target'} ||= $this->{'talkid'};

    _print_quickreply_link( $ctx, $this, $opts );
}

*EntryLite__print_reply_link = \&_print_quickreply_link;
*Entry__print_reply_link     = \&_print_quickreply_link;
*Page__print_reply_link      = \&_print_quickreply_link;
*EntryPage__print_reply_link = \&_print_quickreply_link;

sub _print_quickreply_link {
    my ( $ctx, $this, $opts ) = @_;

    $opts ||= {};

    # one of these had better work
    my $replyurl = $opts->{'reply_url'} || $this->{'reply_url'}    # entrypage comments
        || $this->{'entry'}->{'comments'}->{'post_url'}            # entrypage entry
        || $this->{comments}->{post_url};                          # readpage entry

    # clean up input:
    my $linktext = LJ::ehtml( $opts->{'linktext'} ) || "";

    my $target = $opts->{target} || '';
    return unless $target =~ /^[\w-]+$/;                           # if no target specified bail out

    my $opt_class = $opts->{class} || '';
    undef $opt_class unless $opt_class =~ /^[\w\s-]+$/;

    my $opt_img = LJ::CleanHTML::canonical_url( $opts->{'img_url'} );
    $replyurl = LJ::CleanHTML::canonical_url($replyurl);

    # if they want an image change the text link to the image,
    # and add the text after the image if they specified it as well
    if ($opt_img) {

        # hella robust img options. (width,height,align,alt,title)
        my $width  = $opts->{'img_width'} + 0;
        my $height = $opts->{'img_height'} + 0;
        my $align  = $opts->{'img_align'};
        my $alt    = LJ::ehtml( $opts->{'alt'} );
        my $title  = LJ::ehtml( $opts->{'title'} );
        my $border = $opts->{'img_border'} + 0;

        $width  = $width            ? "width=$width"     : "";
        $height = $height           ? "height=$height"   : "";
        $border = $border ne ""     ? "border=$border"   : "";
        $alt    = $alt              ? "alt=\"$alt\""     : "";
        $title  = $title            ? "title=\"$title\"" : "";
        $align  = $align =~ /^\w+$/ ? "align=\"$align\"" : "";

        $linktext = "<img src=\"$opt_img\" $width $height $align $title $alt $border />$linktext";
    }

    my $basesubject = $opts->{basesubject} || '';    #cleaned later

    $opt_class = $opt_class ? "class=\"$opt_class\"" : "";

    my $page    = get_page();
    my $remote  = LJ::get_remote();
    my $onclick = "";
    unless ( $remote && $remote->prop("opt_no_quickreply") ) {
        my $pid =
            ( $target =~ /^\d+$/ && $page->{_type} eq 'EntryPage' ) ? int( $target / 256 ) : 0;

        $basesubject =~ s/^(Re:\s*)*//i;
        $basesubject = "Re: $basesubject" if $basesubject;
        $basesubject = LJ::ejs($basesubject);
        $onclick =
"return function(that) {return quickreply(\"$target\", $pid, \"$basesubject\",that)}(this)";
        $onclick = "onclick='$onclick'";
    }

    $onclick = "" unless LJ::S2::has_quickreply($page);
    $onclick = "" unless LJ::is_enabled('s2quickreply');
    $onclick = "" if $page->{'_u'}->does_not_allow_comments_from($remote);

    $S2::pout->("<a $onclick href='$replyurl' $opt_class>$linktext</a>");
}

sub _print_reply_container {
    my ( $ctx, $this, $opts ) = @_;

    my $page = get_page();
    return unless LJ::S2::has_quickreply($page);

    my $target = $opts->{target} || '';
    undef $target unless $target =~ /^[\w-]+$/;

    my $class = $opts->{class} || '';

    # set target to the dtalkid if no target specified (link will be same)
    my $dtalkid = $this->{'talkid'} || undef;
    $target ||= $dtalkid;
    return if !$target;

    undef $class unless $class =~ /^([\w\s]+)$/;

    $class = $class ? "class=\"$class\"" : "";

    $S2::pout->(
"<div $class id=\"ljqrt$target\" data-quickreply-container=\"$target\" style=\"display: none;\"></div>"
    );

    # unless we've already inserted the big qrdiv ugliness, do it.
    unless ( $ctx->[S2::SCRATCH]->{'quickreply_printed_div'}++ ) {
        my $u       = $page->{'_u'};
        my $ditemid = $page->{'entry'}{'itemid'} || $this->{itemid} || 0;
        my $userpic = LJ::ehtml( $page->{'_picture_keyword'} ) || "";
        my $thread  = "";
        $thread = $page->{_viewing_thread_id} + 0
            if defined $page->{_viewing_thread_id};
        $S2::pout->(
            LJ::create_qr_div(
                $u, $ditemid,
                style_opts => $page->{_styleopts},
                userpic    => $userpic,
                thread     => $thread,
                minimal    => $page->{view} ne "entry",
            )
        );
    }
}

*EntryLite__print_reply_container = \&_print_reply_container;
*Entry__print_reply_container     = \&_print_reply_container;
*Comment__print_reply_container   = \&_print_reply_container;
*EntryPage__print_reply_container = \&_print_reply_container;
*Page__print_reply_container      = \&_print_reply_container;

sub Comment__expand_link {
    my ( $ctx, $this, $opts ) = @_;
    $opts ||= {};

    my $prop_text = LJ::ehtml( $ctx->[S2::PROPS]->{"text_comment_expand"} );

    my $text = LJ::ehtml( $opts->{text} );
    $text =~ s/&amp;nbsp;/&nbsp;/gi;    # allow &nbsp; in the text

    my $opt_img = LJ::CleanHTML::canonical_url( $opts->{img_url} );

    # if they want an image change the text link to the image,
    # and add the text after the image if they specified it as well
    if ($opt_img) {
        my $width  = $opts->{img_width};
        my $height = $opts->{img_height};
        my $border = $opts->{img_border};
        my $align  = LJ::ehtml( $opts->{img_align} );
        my $alt    = LJ::ehtml( $opts->{img_alt} ) || $prop_text;
        my $title  = LJ::ehtml( $opts->{img_title} ) || $prop_text;

        $width  = defined $width  && $width =~ /^\d+$/  ? " width=\"$width\""   : "";
        $height = defined $height && $height =~ /^\d+$/ ? " height=\"$height\"" : "";
        $border = defined $border && $border =~ /^\d+$/ ? " border=\"$border\"" : "";

        $align = $align =~ /^\w+$/ ? " align=\"$align\"" : "";
        $alt   = $alt              ? " alt=\"$alt\""     : "";
        $title = $title            ? " title=\"$title\"" : "";

        $text = "<img src=\"$opt_img\"$width$height$border$align$title$alt />$text";
    }
    elsif ( !$text ) {
        $text = $prop_text;
    }

    my $title = $opts->{title} ? " title='" . LJ::ehtml( $opts->{title} ) . "'" : "";
    my $class = $opts->{class} ? " class='" . LJ::ehtml( $opts->{class} ) . "'" : "";

    my $onclick = "";

    # if we're in top-only mode, then we display the expand link as
    # the unhide ('show x comments') message

    if ( $this->{"hide_children"} ) {
        my $comment_count = $this->{'showable_children'};

        $text = LJ::ehtml( get_plural_phrase( $ctx, $comment_count, "text_comment_unhide" ) );
        my $remote = LJ::get_remote();

        $onclick =
" onClick=\"Expander.make(this,'$this->{expand_url}','$this->{talkid}', true); return false;\"";
    }
    else {
        $onclick =
" onClick=\"Expander.make(this,'$this->{expand_url}','$this->{talkid}'); return false;\"";
    }
    return "<a href='$this->{expand_url}'$title$class$onclick>$text</a>";
}

sub Comment__print_expand_link {
    $S2::pout->( Comment__expand_link(@_) );
}

# creates the (javascript) link that hides comments under this comment.
sub Comment__print_hide_link {
    my ( $ctx, $this, $opts ) = @_;
    $opts ||= {};

    my $comment_count = $this->{'showable_children'};

    my $prop_text = LJ::ehtml( get_plural_phrase( $ctx, $comment_count, "text_comment_hide" ) );

    my $text = LJ::ehtml( $opts->{text} );
    $text =~ s/&amp;nbsp;/&nbsp;/gi;    # allow &nbsp; in the text

    my $opt_img = LJ::CleanHTML::canonical_url( $opts->{img_url} );

    # if they want an image change the text link to the image,
    # and add the text after the image if they specified it as well
    if ($opt_img) {
        my $width  = $opts->{img_width};
        my $height = $opts->{img_height};
        my $border = $opts->{img_border};
        my $align  = LJ::ehtml( $opts->{img_align} );
        my $alt    = LJ::ehtml( $opts->{img_alt} ) || $prop_text;
        my $title  = LJ::ehtml( $opts->{img_title} ) || $prop_text;

        $width  = defined $width  && $width =~ /^\d+$/  ? " width=\"$width\""   : "";
        $height = defined $height && $height =~ /^\d+$/ ? " height=\"$height\"" : "";
        $border = defined $border && $border =~ /^\d+$/ ? " border=\"$border\"" : "";

        $align = $align =~ /^\w+$/ ? " align=\"$align\"" : "";
        $alt   = $alt              ? " alt=\"$alt\""     : "";
        $title = $title            ? " title=\"$title\"" : "";

        $text = "<img src=\"$opt_img\"$width$height$border$align$title$alt />$text";
    }
    elsif ( !$text ) {
        $text = $prop_text;
    }

    my $title = $opts->{title} ? " title='" . LJ::ehtml( $opts->{title} ) . "'" : "";
    my $class = $opts->{class} ? " class='" . LJ::ehtml( $opts->{class} ) . "'" : "";

    $S2::pout->(
"<a href='#cmt$this->{talkid}'$title$class onClick=\"Expander.hideComments(this, '$this->{talkid}'); return false;\">$text</a>"
    );
}

# creates the (javascript) link that unhides comments under this comment.
sub Comment__print_unhide_link {
    my ( $ctx, $this, $opts ) = @_;
    $opts ||= {};

    my $comment_count = $this->{'showable_children'};

    my $prop_text = LJ::ehtml( get_plural_phrase( $ctx, $comment_count, "text_comment_unhide" ) );

    my $text = LJ::ehtml( $opts->{text} );
    $text =~ s/&amp;nbsp;/&nbsp;/gi;    # allow &nbsp; in the text

    my $opt_img = LJ::CleanHTML::canonical_url( $opts->{img_url} );

    # if they want an image change the text link to the image,
    # and add the text after the image if they specified it as well
    if ($opt_img) {
        my $width  = $opts->{img_width};
        my $height = $opts->{img_height};
        my $border = $opts->{img_border};
        my $align  = LJ::ehtml( $opts->{img_align} );
        my $alt    = LJ::ehtml( $opts->{img_alt} ) || $prop_text;
        my $title  = LJ::ehtml( $opts->{img_title} ) || $prop_text;

        $width  = defined $width  && $width =~ /^\d+$/  ? " width=\"$width\""   : "";
        $height = defined $height && $height =~ /^\d+$/ ? " height=\"$height\"" : "";
        $border = defined $border && $border =~ /^\d+$/ ? " border=\"$border\"" : "";

        $align = $align =~ /^\w+$/ ? " align=\"$align\"" : "";
        $alt   = $alt              ? " alt=\"$alt\""     : "";
        $title = $title            ? " title=\"$title\"" : "";

        $text = "<img src=\"$opt_img\"$width$height$border$align$title$alt />$text";
    }
    elsif ( !$text ) {
        $text = $prop_text;
    }

    my $title = $opts->{title} ? " title='" . LJ::ehtml( $opts->{title} ) . "'" : "";
    my $class = $opts->{class} ? " class='" . LJ::ehtml( $opts->{class} ) . "'" : "";

    $S2::pout->(
"<a href='$this->{expand_url}'$title$class onClick=\"Expander.unhideComments(this, '$this->{talkid}'); return false;\">$text</a>"
    );
}

sub Page__print_trusted {
    my ( $ctx, $this, $key ) = @_;

    # use 'username' so that we can put 'foo.site.com' in the hash instead of
    # having to look up their 'ext_nnnn' name
    my $username = $this->{journal}->{username};
    my $fullkey  = "$username-$key";

    if ( $LJ::TRUSTED_S2_WHITELIST_USERNAMES{$username} ) {

        # more restrictive way: username-key
        $S2::pout->( LJ::conf_test( $LJ::TRUSTED_S2_WHITELIST{$fullkey} ) )
            if exists $LJ::TRUSTED_S2_WHITELIST{$fullkey};
    }
    else {
        # less restrictive way: key
        $S2::pout->( LJ::conf_test( $LJ::TRUSTED_S2_WHITELIST{$key} ) )
            if exists $LJ::TRUSTED_S2_WHITELIST{$key};
    }
}

# class 'date'
sub Date__day_of_week {
    my ( $ctx, $dt ) = @_;
    return $dt->{'_dayofweek'} if defined $dt->{'_dayofweek'};
    return $dt->{'_dayofweek'} = LJ::day_of_week( $dt->{'year'}, $dt->{'month'}, $dt->{'day'} ) + 1;
}
*DateTime__day_of_week = \&Date__day_of_week;

sub Date__compare {
    my ( $ctx, $this, $other ) = @_;

    return
           $other->{year} <=> $this->{year}
        || $other->{month} <=> $this->{month}
        || $other->{day} <=> $this->{day}
        || $other->{hour} <=> $this->{hour}
        || $other->{min} <=> $this->{min}
        || $other->{sec} <=> $this->{sec};
}
*DateTime__compare = \&Date__compare;

my %dt_vars = (
    'm'      => "\$time->{month}",
    'mm'     => "sprintf('%02d', \$time->{month})",
    'd'      => "\$time->{day}",
    'dd'     => "sprintf('%02d', \$time->{day})",
    'yy'     => "sprintf('%02d', \$time->{year} % 100)",
    'yyyy'   => "\$time->{year}",
    'mon'    => "\$ctx->[S2::PROPS]->{lang_monthname_short}->[\$time->{month}]",
    'month'  => "\$ctx->[S2::PROPS]->{lang_monthname_long}->[\$time->{month}]",
    'da'     => "\$ctx->[S2::PROPS]->{lang_dayname_short}->[Date__day_of_week(\$ctx, \$time)]",
    'day'    => "\$ctx->[S2::PROPS]->{lang_dayname_long}->[Date__day_of_week(\$ctx, \$time)]",
    'dayord' => "S2::run_function(\$ctx, \"lang_ordinal(int)\", \$time->{day})",
    'H'      => "\$time->{hour}",
    'HH'     => "sprintf('%02d', \$time->{hour})",
    'h'      => "(\$time->{hour} % 12 || 12)",
    'hh'     => "sprintf('%02d', (\$time->{hour} % 12 || 12))",
    'min'    => "sprintf('%02d', \$time->{min})",
    'sec'    => "sprintf('%02d', \$time->{sec})",
    'a'      => "(\$time->{hour} < 12 ? 'a' : 'p')",
    'A'      => "(\$time->{hour} < 12 ? 'A' : 'P')",
);

sub _dt_vars_html {
    my $datecode = shift;

    return qq{ "/",$dt_vars{yyyy}, "/", $dt_vars{mm}, "/", $dt_vars{dd}, "/" }
        if $datecode =~ /^(d|dd|dayord)$/;
    return qq{ "/",$dt_vars{yyyy}, "/", $dt_vars{mm}, "/" } if $datecode =~ /^(m|mm|mon|month)$/;
    return qq{ "/",$dt_vars{yyyy}, "/" }                    if $datecode =~ /^(yy|yyyy)$/;
}

sub Date__date_format {
    my ( $ctx, $this, $fmt, $as_link ) = @_;
    $fmt     ||= "short";
    $as_link ||= "";

    # formatted as link is separate from format as not link
    my $c = \$ctx->[S2::SCRATCH]->{'_code_datefmt'}->{ $fmt . $as_link };
    return $$c->($this) if ref $$c eq "CODE";
    if ( ++$ctx->[S2::SCRATCH]->{'_code_datefmt_count'} > 15 ) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if ( defined $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"} ) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"};
    }
    elsif ( $fmt eq "iso" ) {
        $realfmt = "%%yyyy%%-%%mm%%-%%dd%%";
    }

    my @parts = split( /\%\%/, $realfmt );
    my $code  = "\$\$c = sub { my \$time = shift; return join('',";
    my $i     = 0;
    foreach (@parts) {
        if ( $i % 2 ) {

            # translate date %%variable%% to value
            my $link = _dt_vars_html($_);
            $code .=
                $as_link && $link
                ? qq{"<a href=\\\"", $link, "\\\">", $dt_vars{$_},"</a>",}
                : $dt_vars{$_} . ",";
        }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}
*DateTime__date_format = \&Date__date_format;

sub DateTime__time_format {
    my ( $ctx, $this, $fmt ) = @_;
    $fmt ||= "short";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_timefmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if ( ++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15 ) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if ( defined $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"} ) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"};
    }
    my @parts = split( /\%\%/, $realfmt );
    my $code  = "\$\$c = sub { my \$time = shift; return join('',";
    my $i     = 0;
    foreach (@parts) {
        if   ( $i % 2 ) { $code                     .= $dt_vars{$_} . ","; }
        else            { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}

sub UserLite__ljuser {
    my ( $ctx, $UserLite, $link_color ) = @_;
    my $link_color_string = $link_color ? $link_color->{as_string} : "";
    return LJ::ljuser( $UserLite->{_u}, { link_color => $link_color_string } );
}

sub UserLite__get_link {
    my ( $ctx, $this, $key ) = @_;

    my $linkbar = $this->{_u}->user_link_bar( LJ::get_remote() );

    my $button = sub {
        my ( $link, $key ) = @_;
        return undef unless $link;

        my $caption =
              $ctx->[S2::PROPS]->{userlite_interaction_links} eq "text"
            ? $link->{text}
            : $link->{title};

        return LJ::S2::Link( $link->{url}, $caption,
            LJ::S2::Image( $link->{image}, $link->{width} || 20, $link->{height} || 18 ) );
    };

    return $button->( $linkbar->manage_membership, $key ) if $key eq 'manage_membership';
    return $button->( $linkbar->trust,             $key ) if $key eq 'trust';
    return $button->( $linkbar->watch,             $key ) if $key eq 'watch';
    return $button->( $linkbar->post,              $key ) if $key eq 'post_entry';
    return $button->( $linkbar->message,           $key ) if $key eq 'message';
    return $button->( $linkbar->track,             $key ) if $key eq 'track';
    return $button->( $linkbar->memories,          $key ) if $key eq 'memories';
    return $button->( $linkbar->tellafriend,       $key ) if $key eq 'tell_friend';

    # Else?
    return undef;
}
*User__get_link = \&UserLite__get_link;

sub EntryLite__get_link {
    my ( $ctx, $this, $key ) = @_;
    my $null_link = { '_type' => 'Link', '_isnull' => 1 };

    if ( $this->{_type} eq 'Entry' || $this->{_type} eq 'StickyEntry' ) {
        return _Entry__get_link( $ctx, $this, $key );
    }
    elsif ( $this->{_type} eq 'Comment' ) {
        return _Comment__get_link( $ctx, $this, $key );
    }
    else {
        return $null_link;
    }
}
*Entry__get_link   = \&EntryLite__get_link;
*Comment__get_link = \&EntryLite__get_link;

# method for smart converting raw subject to html-link
sub EntryLite__formatted_subject {
    my ( $ctx, $this, $opts ) = @_;
    my $subject    = $this->{subject};
    my $format     = delete $opts->{format} || "";
    my $force_text = $format eq "text" ? 1 : 0;

    # Figure out what subject to show. Even if the settings are configured
    # to show nothing for entries or comments without subjects, there should
    # always be at a minimum a hidden visibility subject line for screenreaders.
    my $set_subject = sub {
        my ( $all_subs, $always ) = @_;
        return if defined $subject and $subject ne "";

        # no subject
        my $text_nosubject = $ctx->[S2::PROPS]->{text_nosubject};
        if ( $text_nosubject ne "" ) {

            # if text_nosubject is set, use it as the subject if
            # all_entrysubjects/all_commentsubjects is true,
            # or if we're in the month view for entries,
            # or if we're in the collapsed view for comments

            $subject = $text_nosubject
                if $ctx->[S2::PROPS]->{$all_subs} || $always;

        }
        if ( $subject eq "" ) {

            # still no subject, so use hidden text_nosubject_screenreader
            $subject = $ctx->[S2::PROPS]->{text_nosubject_screenreader};
            $opts->{class} .= " invisible";
        }
    };

    # Leave the subject as is if it exists. Otherwise, determine what to show.
    if ( $this->{_type} eq 'Entry' || $this->{_type} eq 'StickyEntry' ) {

        $set_subject->( 'all_entrysubjects', $LJ::S2::CURR_PAGE->{view} eq 'month' );

    }
    elsif ( $this->{_type} eq "Comment" ) {

        $set_subject->( 'all_commentsubjects', !$this->{full} );

    }

    my $class = $opts->{class} ? " class=\"" . LJ::ehtml( $opts->{class} ) . "\" " : '';
    my $style = $opts->{style} ? " style=\"" . LJ::ehtml( $opts->{style} ) . "\" " : '';

# display subject as-is (cleaned but not wrapped in a link)
# if we forced it to plain text
#   or subject has a link and we are on a full comment/single entry view and don't need to click through
# TODO: how about other HTML tags?
    if (
        $force_text
        || (
            $subject =~ /href/
            && (   $this->{full}
                || $LJ::S2::CURR_PAGE->{view} eq "reply"
                || $LJ::S2::CURR_PAGE->{view} eq "entry" )
        )
        )
    {
        return "<span $class$style>$subject</span>";
    }
    else {
        # we need to be able to click through this subject, so remove links
        LJ::CleanHTML::clean( \$subject,
            { noexpandembedded => 1, mode => "allow", remove => ["a"] } );

        # additional cleaning for title attribute, necessary to enable
        # screenreaders to see the names of the invisible links
        my $title = $subject;
        LJ::CleanHTML::clean_subject_all( \$title );

        return "<a title=\"$title\" href=\"$this->{permalink_url}\"$class$style>$subject</a>";
    }
}

*Entry__formatted_subject   = \&EntryLite__formatted_subject;
*Comment__formatted_subject = \&EntryLite__formatted_subject;

sub EntryLite__get_tags_text {
    my ( $ctx, $this ) = @_;
    return LJ::S2::get_tags_text( $ctx, $this->{tags} ) || "";
}
*Entry__get_tags_text = \&EntryLite__get_tags_text;

sub EntryLite__get_plain_subject {
    my ( $ctx, $this ) = @_;
    return $this->{'_plainsubject'} if $this->{'_plainsubject'};
    my $subj = $this->{'subject'};
    LJ::CleanHTML::clean_subject_all( \$subj );
    return $this->{'_plainsubject'} = $subj;
}
*Entry__get_plain_subject   = \&EntryLite__get_plain_subject;
*Comment__get_plain_subject = \&EntryLite__get_plain_subject;

sub _Entry__get_link {
    my ( $ctx, $this, $key ) = @_;
    my $journal    = $this->{'journal'}->{'user'};
    my $poster     = $this->{'poster'}->{'user'};
    my $remote     = LJ::get_remote();
    my $null_link  = { '_type' => 'Link', '_isnull' => 1 };
    my $journalu   = LJ::load_user($journal);
    my $esnjournal = $journalu->is_community ? $journal : $poster;

    if ( $key eq "edit_entry" ) {
        return $null_link
            unless $remote
            && ( $remote->user eq $journal
            || $remote->user eq $poster
            || $remote->can_manage($journalu) );
        return LJ::S2::Link(
            "$LJ::SITEROOT/editjournal?journal=$journal&amp;itemid=$this->{'itemid'}",
            $ctx->[S2::PROPS]->{"text_edit_entry"},
            LJ::S2::Image_std('editentry')
        );
    }
    if ( $key eq "edit_tags" ) {
        my $entry = LJ::Entry->new( $journalu, ditemid => $this->{itemid} );

        return $null_link unless $remote && LJ::Tags::can_add_entry_tags( $remote, $entry );
        return LJ::S2::Link(
            "$LJ::SITEROOT/edittags?journal=$journal&amp;itemid=$this->{'itemid'}",
            $ctx->[S2::PROPS]->{"text_edit_tags"},
            LJ::S2::Image_std('edittags')
        );
    }
    if ( $key eq "tell_friend" ) {
        return $null_link unless LJ::is_enabled('tellafriend');
        my $entry = LJ::Entry->new( $journalu->userid, ditemid => $this->{itemid} );
        return $null_link unless $entry->can_tellafriend($remote);
        return LJ::S2::Link(
            "$LJ::SITEROOT/tools/tellafriend?journal=$journal&amp;itemid=$this->{'itemid'}",
            $ctx->[S2::PROPS]->{"text_tell_friend"},
            LJ::S2::Image_std('tellfriend')
        );
    }
    if ( $key eq "mem_add" ) {
        return $null_link unless LJ::is_enabled('memories');
        return LJ::S2::Link(
            "$LJ::SITEROOT/tools/memadd?journal=$journal&amp;itemid=$this->{'itemid'}",
            $ctx->[S2::PROPS]->{"text_mem_add"},
            LJ::S2::Image_std('memadd')
        );
    }
    if ( $key eq "nav_prev" ) {
        return LJ::S2::Link(
            LJ::create_url(
                "/go",
                host          => $LJ::DOMAIN_WEB,
                viewing_style => 1,
                args          => {
                    journal => $journal,
                    itemid  => $this->{itemid},
                    dir     => "prev",
                }
            ),
            $ctx->[S2::PROPS]->{"text_entry_prev"},
            LJ::S2::Image_std('prev_entry')
        );
    }
    if ( $key eq "nav_next" ) {
        return LJ::S2::Link(
            LJ::create_url(
                "/go",
                host          => $LJ::DOMAIN_WEB,
                viewing_style => 1,
                args          => {
                    journal => $journal,
                    itemid  => $this->{itemid},
                    dir     => "next",
                }
            ),
            $ctx->[S2::PROPS]->{"text_entry_next"},
            LJ::S2::Image_std('next_entry')
        );
    }
    if ( $key eq "nav_tag_prev" ) {
        return LJ::S2::Link(
            LJ::create_url(
                "/go",
                host          => $LJ::DOMAIN_WEB,
                viewing_style => 1,
                args          => {
                    journal   => $journal,
                    itemid    => $this->{itemid},
                    redir_key => $this->{tagnav}->{name},
                    dir       => "prev",
                }
            ),
            $ctx->[S2::PROPS]->{"text_entry_prev"},
            LJ::S2::Image_std('prev_entry')
        );
    }
    if ( $key eq "nav_tag_next" ) {
        return LJ::S2::Link(
            LJ::create_url(
                "/go",
                host          => $LJ::DOMAIN_WEB,
                viewing_style => 1,
                args          => {
                    journal   => $journal,
                    itemid    => $this->{itemid},
                    redir_key => $this->{tagnav}->{name},
                    dir       => "next",
                }
            ),
            $ctx->[S2::PROPS]->{"text_entry_next"},
            LJ::S2::Image_std('next_entry')
        );
    }

    my $etypeid          = 'LJ::Event::JournalNewComment'->etypeid;
    my $newentry_etypeid = 'LJ::Event::JournalNewEntry'->etypeid;

    my ($newentry_sub) =
        $remote
        ? $remote->has_subscription(
        journalid      => $journalu->id,
        event          => "JournalNewEntry",
        require_active => 1,
        )
        : undef;

    my $newentry_auth_token;

    if ($newentry_sub) {
        $newentry_auth_token = $remote->ajax_auth_token(
            '/__rpc_esn_subs',
            subid  => $newentry_sub->id,
            action => 'delsub',
        );
    }
    elsif ($remote) {
        $newentry_auth_token = $remote->ajax_auth_token(
            '/__rpc_esn_subs',
            journalid => $journalu->id,
            action    => 'addsub',
            etypeid   => $newentry_etypeid,
        );
    }

    if ( $key eq "watch_comments" ) {
        return $null_link unless LJ::is_enabled('esn');
        return $null_link unless $remote && $remote->can_use_esn;
        return $null_link
            if $remote->has_subscription(
            journal        => LJ::load_user($journal),
            event          => "JournalNewComment",
            arg1           => $this->{'itemid'},
            arg2           => 0,
            require_active => 1,
            );

        my $auth_token = $remote->ajax_auth_token(
            '/__rpc_esn_subs',
            journalid => $journalu->id,
            action    => 'addsub',
            etypeid   => $etypeid,
            arg1      => $this->{itemid},
        );

        return LJ::S2::Link(
            "$LJ::SITEROOT/manage/tracking/entry?journal=$journal&amp;itemid=$this->{'itemid'}",
            $ctx->[S2::PROPS]->{"text_watch_comments"},
            LJ::S2::Image_std('track'),
            'lj_journalid'        => $journalu->id,
            'lj_etypeid'          => $etypeid,
            'lj_subid'            => 0,
            'lj_arg1'             => $this->{itemid},
            'lj_auth_token'       => $auth_token,
            'lj_newentry_etypeid' => $newentry_etypeid,
            'lj_newentry_token'   => $newentry_auth_token,
            'lj_newentry_subid'   => $newentry_sub ? $newentry_sub->id : 0,
            'class'               => 'TrackButton',
            'js_swapname'         => $ctx->[S2::PROPS]->{text_unwatch_comments},
            'journal'             => $esnjournal
        );
    }
    if ( $key eq "unwatch_comments" ) {
        return $null_link unless LJ::is_enabled('esn');
        return $null_link unless $remote && $remote->can_use_esn;
        my @subs = $remote->has_subscription(
            journal        => LJ::load_user($journal),
            event          => "JournalNewComment",
            arg1           => $this->{'itemid'},
            arg2           => 0,
            require_active => 1,
        );
        my $subscr = $subs[0];
        return $null_link unless $subscr;

        my $auth_token = $remote->ajax_auth_token(
            '/__rpc_esn_subs',
            subid  => $subscr->id,
            action => 'delsub'
        );

        return LJ::S2::Link(
            "$LJ::SITEROOT/manage/tracking/entry?journal=$journal&amp;itemid=$this->{'itemid'}",
            $ctx->[S2::PROPS]->{"text_unwatch_comments"},
            LJ::S2::Image_std('untrack'),
            'lj_journalid'        => $journalu->id,
            'lj_subid'            => $subscr->id,
            'lj_etypeid'          => $etypeid,
            'lj_arg1'             => $this->{itemid},
            'lj_auth_token'       => $auth_token,
            'lj_newentry_etypeid' => $newentry_etypeid,
            'lj_newentry_token'   => $newentry_auth_token,
            'lj_newentry_subid'   => $newentry_sub ? $newentry_sub->id : 0,
            'class'               => 'TrackButton',
            'js_swapname'         => $ctx->[S2::PROPS]->{text_watch_comments},
            'journal'             => $esnjournal
        );
    }
}

sub Entry__plain_subject {
    my ( $ctx, $this ) = @_;
    return $this->{'_subject_plain'} if defined $this->{'_subject_plain'};
    $this->{'_subject_plain'} = $this->{'subject'};
    LJ::CleanHTML::clean_subject_all( \$this->{'_subject_plain'} );
    return $this->{'_subject_plain'};
}

sub EntryPage__print_multiform_actionline {
    my ( $ctx, $this ) = @_;
    return unless $this->{'multiform_on'};
    my $pr      = $ctx->[S2::PROPS];
    my @actions = qw( unscreen screen delete );
    push @actions, "deletespam"
        unless LJ::sysban_check( 'spamreport', $this->{entry}->{journal}->{username} );
    $S2::pout->(
        LJ::labelfy( 'multiform_mode', $pr->{text_multiform_des} ) . "\n"
            . LJ::html_select(
            { name => 'mode', id => 'multiform_mode' },
            "" => "",
            map { $_ => $pr->{"text_multiform_opt_$_"} } @actions
            )
            . "\n"
            . LJ::html_submit(
            '',
            $pr->{'text_multiform_btn'},
            {
                      "onclick" => 'return ((document.multiform.mode.value != "delete" '
                    . '&& document.multiform.mode.value != "deletespam")) '
                    . "|| confirm(\""
                    . LJ::ejs( $pr->{'text_multiform_conf_delete'} ) . "\");"
            }
            )
    );
}

sub EntryPage__print_multiform_end {
    my ( $ctx, $this ) = @_;
    return unless $this->{'multiform_on'};
    $S2::pout->("</form>");
}

sub EntryPage__print_multiform_start {
    my ( $ctx, $this ) = @_;
    return unless $this->{'multiform_on'};
    $S2::pout->(
"<form style='display: inline' method='post' action='$LJ::SITEROOT/talkmulti' name='multiform'>\n"
            . LJ::html_hidden(
            "ditemid", $this->{'entry'}->{'itemid'},
            "journal", $this->{'entry'}->{'journal'}->{'user'}
            )
            . "\n"
    );
}

sub Page__print_control_strip {
    my ( $ctx, $this ) = @_;

    my $control_strip =
        LJ::control_strip( user => $LJ::S2::CURR_PAGE->{'journal'}->{'_u'}->{'user'} );

    return "" unless $control_strip;
    $S2::pout->($control_strip);
}
*RecentPage__print_control_strip  = \&Page__print_control_strip;
*DayPage__print_control_strip     = \&Page__print_control_strip;
*MonthPage__print_control_strip   = \&Page__print_control_strip;
*YearPage__print_control_strip    = \&Page__print_control_strip;
*FriendsPage__print_control_strip = \&Page__print_control_strip;
*EntryPage__print_control_strip   = \&Page__print_control_strip;
*ReplyPage__print_control_strip   = \&Page__print_control_strip;
*TagsPage__print_control_strip    = \&Page__print_control_strip;

# removed as part of generic ads removal
sub Page__print_hbox_top    { }
sub Page__print_hbox_bottom { }
sub Page__print_vbox        { }
sub Page__print_ad_box      { }
sub Entry__print_ebox       { }
sub Page__print_ad          { }

sub Page__visible_tag_list {
    my ( $ctx, $this, $limit ) = @_;

    $limit ||= "";
    return $this->{'_visible_tag_list'}
        if defined $this->{'_visible_tag_list'} && !$limit;

    my $remote = LJ::get_remote();
    my $u      = $LJ::S2::CURR_PAGE->{'_u'};
    return [] unless $u;

    # use the cached tag list, if we have it
    my @taglist = @{ $this->{'_visible_tag_list'} || [] };

    unless (@taglist) {
        my $tags = LJ::Tags::get_usertags( $u, { remote => $remote } );
        return [] unless $tags;

        foreach my $kwid ( keys %{$tags} ) {

            # only show tags for display
            next unless $tags->{$kwid}->{display};

            # create tag object
            push @taglist, LJ::S2::TagDetail( $u, $kwid => $tags->{$kwid} );
        }
    }

    if ($limit) {
        @taglist = sort { $b->{use_count} <=> $a->{use_count} } @taglist;
        @taglist = splice @taglist, 0, $limit;
    }

    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;
    return $this->{'_visible_tag_list'} = \@taglist;
}
*RecentPage__visible_tag_list  = \&Page__visible_tag_list;
*DayPage__visible_tag_list     = \&Page__visible_tag_list;
*MonthPage__visible_tag_list   = \&Page__visible_tag_list;
*YearPage__visible_tag_list    = \&Page__visible_tag_list;
*FriendsPage__visible_tag_list = \&Page__visible_tag_list;
*EntryPage__visible_tag_list   = \&Page__visible_tag_list;
*ReplyPage__visible_tag_list   = \&Page__visible_tag_list;
*TagsPage__visible_tag_list    = \&Page__visible_tag_list;

sub Page__get_latest_month {
    my ( $ctx, $this ) = @_;
    return $this->{'_latest_month'} if defined $this->{'_latest_month'};
    my $counts = LJ::S2::get_journal_day_counts($this);

    # defaults to current year/month
    my @now = gmtime(time);
    my ( $curyear, $curmonth ) = ( $now[5] + 1900, $now[4] + 1 );
    my ( $year, $month ) = ( $curyear, $curmonth );

    # only want to look at current years, not future-dated posts
    my @years = grep { $_ <= $curyear } sort { $a <=> $b } keys %$counts;
    if (@years) {

        # year/month of last post
        $year = $years[-1];

        # we'll take any month of previous years, or anything up to the current month
        $month = (
            grep { $year < $curyear || $_ <= $curmonth }
            sort { $a <=> $b } keys %{ $counts->{$year} }
        )[-1];
    }

    return $this->{'_latest_month'} = LJ::S2::YearMonth(
        $this,
        {
            'year'  => $year,
            'month' => $month,
        },
        S2::get_property_value( $ctx, 'reg_firstdayofweek' ) eq "monday" ? 1 : 0
    );
}
*RecentPage__get_latest_month  = \&Page__get_latest_month;
*DayPage__get_latest_month     = \&Page__get_latest_month;
*MonthPage__get_latest_month   = \&Page__get_latest_month;
*YearPage__get_latest_month    = \&Page__get_latest_month;
*FriendsPage__get_latest_month = \&Page__get_latest_month;
*EntryPage__get_latest_month   = \&Page__get_latest_month;
*ReplyPage__get_latest_month   = \&Page__get_latest_month;

sub palimg_modify {
    my ( $ctx, $filename, $items ) = @_;
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::PALIMGROOT/$filename";
    return $url unless $items && @$items;
    return undef if @$items > 7;
    $url .= "/p";
    foreach my $pi (@$items) {
        die "Can't modify a palette index greater than 15 with palimg_modify\n"
            if $pi->{'index'} > 15;
        $url .= sprintf( "%1x%02x%02x%02x",
            $pi->{'index'},
            $pi->{'color'}->{'r'},
            $pi->{'color'}->{'g'},
            $pi->{'color'}->{'b'} );
    }
    return $url;
}

sub palimg_tint {
    my ( $ctx, $filename, $bcol, $dcol ) = @_;    # bright color, dark color [opt]
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::PALIMGROOT/$filename";
    $url .= "/pt";
    foreach my $col ( $bcol, $dcol ) {
        next unless $col;
        $url .= sprintf( "%02x%02x%02x", $col->{'r'}, $col->{'g'}, $col->{'b'} );
    }
    return $url;
}

sub palimg_gradient {
    my ( $ctx, $filename, $start, $end ) = @_;
    return undef unless $filename =~ /^\w[\w\/\-]*\.(gif|png)$/;
    my $url = "$LJ::PALIMGROOT/$filename";
    $url .= "/pg";
    foreach my $pi ( $start, $end ) {
        next unless $pi;
        $url .= sprintf(
            "%02x%02x%02x%02x",
            $pi->{'index'},
            $pi->{'color'}->{'r'},
            $pi->{'color'}->{'g'},
            $pi->{'color'}->{'b'}
        );
    }
    return $url;
}

sub userlite_base_url {
    my ( $ctx, $UserLite ) = @_;
    my $u = $UserLite->{_u};
    return "#"
        unless $UserLite && $u;
    return $u->journal_base;
}

sub userlite_as_string {
    my ( $ctx, $UserLite ) = @_;
    return LJ::ljuser( $UserLite->{'_u'} );
}

sub PalItem {
    my ( $ctx, $idx, $color ) = @_;
    return undef unless $color && $color->{'_type'} eq "Color";
    return undef unless $idx >= 0 && $idx <= 255;
    return {
        '_type' => 'PalItem',
        'color' => $color,
        'index' => $idx + 0,
    };
}

sub YearMonth__month_format {
    my ( $ctx, $this, $fmt, $as_link ) = @_;
    $fmt     ||= "long";
    $as_link ||= "";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_monthfmt'}->{ $fmt . $as_link };
    return $$c->($this) if ref $$c eq "CODE";
    if ( ++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15 ) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if ( defined $ctx->[S2::PROPS]->{"lang_fmt_month_$fmt"} ) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_month_$fmt"};
    }

    my @parts = split( /\%\%/, $realfmt );
    my $code  = "\$\$c = sub { my \$time = shift; return join('',";
    my $i     = 0;
    foreach (@parts) {
        if ( $i % 2 ) {

            # translate date %%variable%% to value
            my $link = _dt_vars_html($_);
            $code .=
                $as_link && $link
                ? qq{"<a href=\\\"", $link, "\\\">", $dt_vars{$_},"</a>",}
                : $dt_vars{$_} . ",";
        }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}

sub Image__set_url {
    my ( $ctx, $img, $newurl ) = @_;
    $img->{'url'} = LJ::eurl($newurl);
}

sub ItemRange__url_of {
    my ( $ctx, $this, $n ) = @_;
    return "" unless ref $this->{'_url_of'} eq "CODE";
    return $this->{'_url_of'}->( $n + 0 );
}

sub UserLite__equals {
    return $_[1]->{'_u'}{'userid'} == $_[2]->{'_u'}{'userid'};
}
*User__equals   = \&UserLite__equals;
*Friend__equals = \&UserLite__equals;

sub string__index {
    use utf8;
    my ( $ctx, $this, $substr, $position ) = @_;
    return index( $this, $substr, $position );
}

sub string__substr {
    my ( $ctx, $this, $start, $length ) = @_;

    use Encode qw/decode_utf8 encode_utf8/;
    my $ustr   = decode_utf8($this);
    my $result = substr( $ustr, $start, $length );
    return encode_utf8($result);
}

sub string__length {
    use utf8;
    my ( $ctx, $this ) = @_;
    return length($this);
}

sub string__lower {
    use utf8;
    my ( $ctx, $this ) = @_;
    return lc($this);
}

sub string__upper {
    use utf8;
    my ( $ctx, $this ) = @_;
    return uc($this);
}

sub string__upperfirst {
    use utf8;
    my ( $ctx, $this ) = @_;
    return ucfirst($this);
}

sub string__starts_with {
    use utf8;
    my ( $ctx, $this, $str ) = @_;
    return $this =~ /^\Q$str\E/;
}

sub string__ends_with {
    use utf8;
    my ( $ctx, $this, $str ) = @_;
    return $this =~ /\Q$str\E$/;
}

sub string__contains {
    use utf8;
    my ( $ctx, $this, $str ) = @_;
    return $this =~ /\Q$str\E/;
}

sub string__replace {
    use utf8;
    my ( $ctx, $this, $find, $replace ) = @_;
    $this =~ s/\Q$find\E/$replace/g;
    return $this;
}

sub string__split {
    use utf8;
    my ( $ctx, $this, $splitby ) = @_;
    my @result = split /\Q$splitby\E/, $this;
    return \@result;
}

sub string__repeat {
    use utf8;
    my ( $ctx, $this, $num ) = @_;
    $num += 0;
    my $size = length($this) * $num;
    return "[too large]" if $size > 5000;
    return $this x $num;
}

sub string__compare {
    use utf8;    # Does this actually make any difference here?
    my ( $ctx, $this, $other ) = @_;
    return $other cmp $this;
}

sub string__css_length_value {
    my ( $ctx, $this ) = @_;

    $this =~ s/^\s+//g;
    $this =~ s/\s+$//g;

    # Is it one of the acceptable keywords?
    my %allowed_keywords = map { $_ => 1 }
        qw(larger smaller xx-small x-small small medium large x-large xx-large auto inherit);
    return $this if $allowed_keywords{$this};

    # Is it a number followed by an acceptable unit?
    my %allowed_units = map { $_ => 1 } qw(em ex px in cm mm pt pc %);
    return $this if $this =~ /^[\-\+]?(\d*\.)?\d+([a-z]+|\%)$/ && $allowed_units{$2};

    # Is it zero?
    return "0" if $this =~ /^(0*\.)?0+$/;

    return '';
}

sub string__css_multiply_length {
    my ( $ctx, $this, $multiplier ) = @_;
    my ( $length, $unit ) = $this =~ /(\d+)(.+)/;
    return string__css_length_value( $ctx, ( $length * $multiplier ) . $unit );
}

sub string__css_divide_length {
    my ( $ctx, $this, $divisor ) = @_;
    my ( $length, $unit ) = $this =~ /(\d+)(.+)/;
    return string__css_length_value( $ctx, int( $length / $divisor ) . $unit );
}

sub string__css_string {
    my ( $ctx, $this ) = @_;

    $this =~ s/\\/\\\\/g;
    $this =~ s/\"/\\\"/g;

    return '"' . $this . '"';

}

sub string__css_url_value {
    my ( $ctx, $this ) = @_;

    return '' if $this !~ m!^https?://!;
    return '' if $this =~ /[^a-z0-9A-Z\.\@\$\-_\.\+\!\*'\(\),&=#;:\?\/\%~]/;
    return 'url(' . string__css_string( $ctx, $this ) . ')';
}

sub string__css_keyword {
    my ( $ctx, $this, $allowed ) = @_;

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

sub string__css_keyword_list {
    my ( $ctx, $this, $allowed ) = @_;

    $this =~ s/^\s+//g;
    $this =~ s/\s+$//g;

    my @in  = split( /\s+/, $this );
    my @out = ();

    # Do the transform of $allowed to a hash once here rather than once for each keyword
    $allowed = { map { $_ => 1 } @$allowed } if ref $allowed eq 'ARRAY';

    foreach my $kw (@in) {
        $kw = string__css_keyword( $ctx, $kw, $allowed );
        push @out, $kw if $kw;
    }

    return join( ' ', @out );
}

sub Siteviews__need_res {
    my ( $ctx, $this, $res ) = @_;
    die "Siteviews doesn't work standalone" unless $ctx->[S2::SCRATCH]->{siteviews_enabled};
    LJ::need_res($res);
}

sub Siteviews__start_capture {
    my ( $ctx, $this ) = @_;
    die "Siteviews doesn't work standalone" unless $ctx->[S2::SCRATCH]->{siteviews_enabled};

    # force flush
    S2::get_output()->("");

    push @{ $this->{_input_captures} }, $LJ::S2::ret_ref;
    my $text = "";
    $LJ::S2::ret_ref = \$text;
}

sub Siteviews__end_capture {
    my ( $ctx, $this ) = @_;
    die "Siteviews doesn't work standalone" unless $ctx->[S2::SCRATCH]->{siteviews_enabled};

    return "" unless scalar( @{ $this->{_input_captures} } );

    # force flush
    S2::get_output()->("");
    my $text_ref = $LJ::S2::ret_ref;
    $LJ::S2::ret_ref = pop @{ $this->{_input_captures} };
    return $$text_ref;
}

sub Siteviews__set_content {
    my ( $ctx, $this, $content, $text ) = @_;
    die "Siteviews doesn't work standalone" unless $ctx->[S2::SCRATCH]->{siteviews_enabled};

    $this->{_content}->{$content} = $text;
}

sub keys_alpha {
    my ( $ctx, $ref ) = @_;
    return undef unless ref $ref eq 'HASH';

    # return reference to array of sorted keys
    return [ sort { $a cmp $b } keys %$ref ];
}

1;
