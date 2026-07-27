#!/usr/bin/perl
#
# DW::Controller::Memories
#
# Viewing and managing memories: /tools/memories lists a user's memorable
# entries by category (with filtering, sorting, and bulk delete), and
# /tools/memadd adds, edits, or deletes a single memory.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Memories;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Memories;

DW::Routing->register_string( '/tools/memories', \&memories_handler, app => 1, no_cache => 1 );
DW::Routing->register_string( '/tools/memadd',   \&memadd_handler,   app => 1, no_cache => 1 );

sub memories_handler {
    my $ml_scope = '/tools/memories.tt';

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $get    = $r->get_args;
    my $post   = $r->post_args;

    # find out if a 'user' argument is specified in the URL
    my $user = LJ::canonical_username( $get->{user} );
    return error_ml('error.malformeduser') if $get->{user} && !$user;

    # find out if an 'authas' argument is specified in the URL; if not, try
    # to authenticate as 'user', and failing that, use the remote user
    my $authasu = LJ::get_authas_user( $get->{authas} || $user || '' ) || $remote;

    unless ( $r->did_post ) {
        if ($authasu) {
            $rv->{authas_html} =
                LJ::make_authas_select( $remote, { authas => $authasu->user, foundation => 1 } );
            $user ||= $authasu->user;
        }
    }

    # now, whose memories page do we actually want to see?
    # - if 'user' is specified, we want to see theirs
    # - if no 'user', but 'authas' is specified, we want to see authas's
    #   ($user has been set to $authasu->user above)
    # - if neither is specified, we want to see remote's
    $user = $remote->user if !$user && $remote;
    return needlogin() unless $user;

    my $u = LJ::load_user($user)
        or return error_ml('error.username_notfound');

    # owner if you've authed as them or you administrate them
    my $is_owner = ( $authasu && $user eq $authasu->user )
        || ( $remote && $remote->can_manage_other($u) );

    if ( $u->is_redirect ) {
        my $renamedto = $u->prop('renamedto');
        return $r->redirect(
            LJ::create_url(
                '/tools/memories',
                args => {
                    user => $renamedto,
                    ( $authasu ? ( authas => $authasu->user ) : () ),
                }
            )
        );
    }

    $u->preload_props( 'opt_blockrobots', 'adult_content' ) if $u->is_visible;
    $rv->{robot_meta} = LJ::robot_meta_tags()
        unless $u->is_visible && !$u->should_block_robots;

    return DW::Template->render_template( 'error/suspended.tt', { u => $u, remote => $remote } )
        if $u->is_suspended;
    return $u->display_journal_deleted($remote) if $u->is_deleted;
    return DW::Template->render_template('error/purged.tt') if $u->is_expunged;

    if ( $r->did_post ) {
        return error_ml('error.invalidauth') unless $is_owner;

        my @to_delete;
        foreach my $key ( keys %$post ) {
            push @to_delete, $1 if $key =~ /^select_mem_(\d+)$/;
        }
        return error_ml("$ml_scope.delete.error.noneselected") unless @to_delete;

        # delete them!
        LJ::Memories::delete_by_id( $authasu, \@to_delete );

        $rv->{state} = 'deleted';
        $rv->{view_url} =
            LJ::create_url( '/tools/memories', args => { user => $authasu->user } );
        return DW::Template->render_template( 'tools/memories.tt', $rv );
    }

    my $filter = $get->{filter} || 'all';
    $filter = 'all' unless $filter =~ /^(?:all|own|other)$/;

    my $sort = $get->{sortby} || 'memid';
    $sort = 'memid' unless $sort =~ /^(?:memid|des|user)$/;

    my %sortfunc = (
        memid => sub {
            sort { $a->{memid} <=> $b->{memid} } @_;
        },
        des => sub {
            sort { $a->{des} cmp $b->{des} } @_;
        },
        user => sub {
            sort { $a->{user} cmp $b->{user} || $a->{des} cmp $b->{des} } @_;
        },
    );

    # which security levels of memories can the viewer see?
    my $securities = ['public'];
    if ($authasu) {
        if ($is_owner) {
            $securities = [];
        }
        elsif ( $authasu->is_person && $u->trusts_or_has_member($authasu) ) {
            $securities = [ 'public', 'friends' ];
        }
    }

    my $kwmap = LJ::Memories::get_keywords($u);
    return error_ml('error.nodb') unless defined $kwmap;

    $rv->{u_mem}      = $u;
    $rv->{user}       = $user;
    $rv->{is_owner}   = $is_owner;
    $rv->{filter}     = $filter;
    $rv->{sort}       = $sort;
    $rv->{get_user}   = $get->{user};
    $rv->{get_authas} = $get->{authas};

    if ( my $keyword = $get->{keyword} ) {
        my $key_id;
        foreach ( keys %$kwmap ) {
            $key_id = $_ if $kwmap->{$_} eq $keyword;
        }

        my $memoryhash = LJ::Memories::get_by_keyword( $u, $key_id,
            { security => $securities, filter => $filter } );
        return error_ml('error.nodb') unless defined $memoryhash;

        my @memories = $sortfunc{$sort}->( values %$memoryhash );
        my $mem_us   = LJ::load_userids( map { $_->{journalid} } @memories );

        my @rows;
        foreach my $mem (@memories) {
            my $mem_u = $mem_us->{ $mem->{journalid} };

            # we only support new-style userid+ditemid memories; LiveJournal's
            # old global itemid entries never existed on Dreamwidth
            next unless $mem->{user} && $mem_u;

            my $des = $mem->{des};
            LJ::text_out( \$des );

            my $itemid = int( $mem->{ditemid} / 256 );
            my $anum   = $mem->{ditemid} % 256;

            push @rows,
                {
                memid     => $mem->{memid},
                des       => $des,
                user      => $mem->{user},
                security  => $mem->{security},
                entry_url => LJ::item_link( $mem_u, $itemid, $anum ),
                edit_url  => LJ::create_url(
                    '/tools/memadd',
                    args => {
                        journal => $mem->{user},
                        itemid  => $mem->{ditemid},
                        ( $authasu ? ( authas => $authasu->user ) : () ),
                    }
                ),
                };
        }

        $rv->{state}          = 'keyword';
        $rv->{keyword}        = $keyword;
        $rv->{ekeyword}       = LJ::ehtml($keyword);
        $rv->{memories}       = \@rows;
        $rv->{multidelete}    = $get->{multidelete} ? 1 : 0;
        $rv->{delete_confirm} = LJ::ejs( LJ::Lang::ml("$ml_scope.delete.confirm") );
        $rv->{back_url}       = LJ::create_url(
            '/tools/memories',
            args => {
                user => $user,
                ( $authasu ? ( authas => $authasu->user ) : () ),
            }
        );

        return DW::Template->render_template( 'tools/memories.tt', $rv );
    }

    # no keyword: show the list of categories
    my $counts =
        LJ::Memories::get_keyword_counts( $u, { security => $securities, filter => $filter } );
    return error_ml('error.nodb') unless defined $counts;

    my @categories;
    foreach my $kwid ( keys %$counts ) {
        my $keyword = $kwmap->{$kwid};
        LJ::text_out( \$keyword );
        push @categories,
            {
            keyword => $keyword,
            count   => $counts->{$kwid},
            url     => LJ::create_url(
                '/tools/memories', args => { user => $user, keyword => $keyword, filter => $filter }
            ),
            };
    }
    @categories = sort { $a->{keyword} cmp $b->{keyword} } @categories;

    $rv->{state}      = 'categories';
    $rv->{categories} = \@categories;

    return DW::Template->render_template( 'tools/memories.tt', $rv );
}

sub memadd_handler {
    my $ml_scope = '/tools/memadd.tt';

    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r       = $rv->{r};
    my $remote  = $rv->{remote};
    my $memoryu = $rv->{u};
    my $get     = $r->get_args;
    my $post    = $r->post_args;

    # the template wraps the account switcher in its own form so it can carry
    # the entry identification along; controller()'s authas_form can't do that
    $rv->{authas_html} =
        LJ::make_authas_select( $remote, { authas => $memoryu->user, foundation => 1 } );

    return error_ml('error.utf8') unless LJ::text_in($post);

    my %secopts = (
        public  => LJ::Lang::ml('label.security.public'),
        friends => LJ::Lang::ml('label.security.accesslist'),
        private => LJ::Lang::ml('label.security.private'),
    );
    if ( $memoryu->is_community ) {
        $secopts{private} = LJ::Lang::ml('label.security.maintainers');
        $secopts{friends} = LJ::Lang::ml('label.security.members');
    }

    # the memories schema stores *display* itemids (with the anum mixed in),
    # so we work with the ditemid everywhere and split out the real itemid
    # for entry lookups
    my $journal = $get->{journal} || $post->{journal};
    my $ditemid = ( $get->{itemid} || $post->{itemid} || 0 ) + 0;

    my ( $ju, $jid, $itemid, $anum );
    if ($journal) {
        $ju     = LJ::load_user($journal);
        $jid    = $ju ? $ju->id : 0;
        $anum   = $ditemid % 256;
        $itemid = int( $ditemid / 256 );
    }

    return error_ml('error.nojournal') unless $ju && $itemid;

    # check to see if it already is memorable (thus we're editing, not adding)
    my $memory = LJ::Memories::get_by_ditemid( $memoryu, $jid, $ditemid );

    my $mode = $post->{mode} // '';
    return error_ml('error.unknownmode') if $r->did_post && $mode ne 'save';

    # the GET form resubmits to ourselves with the entry still identified
    my $form_url = LJ::create_url(
        '/tools/memadd',
        args => {
            itemid  => $ditemid,
            journal => $journal,
            (
                $memoryu->user ne $remote->user
                ? ( authas => $memoryu->user )
                : ()
            ),
        }
    );
    $rv->{form_url} = $form_url;
    $rv->{journal}  = $journal;
    $rv->{itemid}   = $ditemid;

    # always allow a user to delete their memories, regardless of other
    # permissions: an empty description on save means "delete"
    if ( $mode eq 'save' && !$post->{des} ) {
        return error_ml("$ml_scope.error.nodescription.body2")
            unless defined $memory;

        LJ::Memories::delete_by_id( $memoryu, $memory->{memid} );
        LJ::Memories::updated_keywords($memoryu);

        $rv->{state} = 'deleted';
        $rv->{des}   = LJ::ehtml( $memory->{des} );
        $rv->{view_url} =
            LJ::create_url( '/tools/memories', args => { user => $memoryu->user } );
        return DW::Template->render_template( 'tools/memadd.tt', $rv );
    }

    # do access check to see if they can see this entry
    my $log = LJ::get_log2_row( $ju, $itemid );
    if ($log) {
        my $entry = LJ::Entry->new_from_row(%$log);
        if ( $entry && !$entry->visible_to($remote) ) {
            $rv->{state}        = 'cantview';
            $rv->{offer_delete} = defined $memory ? 1 : 0;
            return DW::Template->render_template( 'tools/memadd.tt', $rv );
        }
    }

    # do check to see if entry is deleted
    unless ( $log || $r->did_post ) {
        $rv->{state}        = 'entrygone';
        $rv->{offer_delete} = defined $memory ? 1 : 0;
        return DW::Template->render_template( 'tools/memadd.tt', $rv );
    }

    my $subject = $log ? LJ::get_logtext2( $ju, $itemid )->{ $log->{jitemid} }[0] : undef;

    # if the entry is pre-UTF-8 conversion, the subject may need
    # conversion into UTF-8
    if ($log) {
        my $dbcr  = LJ::get_cluster_reader($ju);
        my %props = ();
        LJ::load_log_props2( $dbcr, $log->{journalid}, [$itemid], \%props );
        if ( $props{$itemid}->{unknown8bit} ) {
            my $u = LJ::load_userid( $log->{journalid} );
            my ( $error, $subj );
            $subj    = LJ::text_convert( $subject, $u, \$error );
            $subject = $subj unless $error;
        }
        LJ::text_out( \$subject );
    }

    # get keywords user has used
    my $exist_kw = LJ::Memories::get_keywords($memoryu);
    return error_ml("$ml_scope.error.keywords") unless $exist_kw;

    unless ( $r->did_post ) {
        my ( $des, $keywords );
        my %selected_keyword;

        if ( defined $memory ) {
            $rv->{title_ml} = '.title.edit_memory';
            $des = $memory->{des};

            my $kwids = LJ::Memories::get_keywordids( $memoryu, $memory->{memid} ) || [];
            foreach my $kwid (@$kwids) {
                my $kw = $exist_kw->{$kwid};
                next if $kw eq '*';
                $keywords .= ', ' if $keywords;
                $keywords .= $kw;
                $selected_keyword{$kw} = 1;
            }

            if ( !$log || ( $jid && $log->{anum} != $anum ) ) {
                LJ::Memories::delete_by_id( $memoryu, $memory->{memid} );
                LJ::Memories::updated_keywords($memoryu);
                return error_ml("$ml_scope.error.entry_deleted2");
            }
        }
        elsif ( !$log || ( $jid && $log->{anum} != $anum ) ) {
            return error_ml('error.noentry');
        }
        else {
            $rv->{title_ml} = '.title.add_memory';

            # this is a new memory
            my $user = LJ::get_username( $log->{journalid} );
            my $dt   = substr( $log->{eventtime}, 0, 10 );
            $des = "$dt: $user: $subject";
        }

        LJ::text_out( \$des );
        LJ::text_out( \$keywords );

        # security <select> options
        my @security_opts =
            map { { value => $_, label => $secopts{$_} } } qw(public friends private);

        # the '*' pseudo-keyword (uncategorized) is applied automatically when
        # no keywords are given, so it isn't offered in the picker
        my @all_keywords = sort grep { $_ ne '*' } values %$exist_kw;
        my $kw_size      = scalar @all_keywords;
        $kw_size = 15 if $kw_size > 15;

        $rv->{state}            = 'form';
        $rv->{is_edit}          = defined $memory ? 1 : 0;
        $rv->{is_comm}          = $memoryu->is_community ? 1 : 0;
        $rv->{des}              = $des;
        $rv->{keywords}         = $keywords;
        $rv->{all_keywords}     = \@all_keywords;
        $rv->{selected_keyword} = \%selected_keyword;
        $rv->{kw_size}          = $kw_size;
        $rv->{security_opts}    = \@security_opts;
        $rv->{security}         = defined $memory ? $memory->{security} : undef;
        $rv->{des_max}          = LJ::CMAX_MEMORY;

        return DW::Template->render_template( 'tools/memadd.tt', $rv );
    }

    # mode eq 'save' with a description: we're inserting/replacing now
    my @keywords;
    {
        my %kws;
        foreach ( split( /\s*,\s*/, $post->{keywords} // '' ) ) { $kws{$_} = 1; }
        foreach ( $post->get_all('oldkeywords') ) { $kws{$_} = 1; }
        @keywords = keys %kws;
    }
    return error_ml("$ml_scope.error.fivekeywords") if scalar(@keywords) > 5;

    @keywords = grep { $_ } map { s/\s\s+/ /g; LJ::trim($_); } @keywords;
    push @keywords, '*' unless @keywords;

    my @kwid;
    my $needflush = 0;
    foreach my $kw (@keywords) {
        return error_ml( "$ml_scope.error.maxsize", { keyword => LJ::ehtml($kw) } )
            if length($kw) > 40;

        my $kwid = $memoryu->get_keyword_id($kw);
        $needflush = 1 unless defined $exist_kw->{$kwid};
        push @kwid, $kwid;
    }

    return error_ml("$ml_scope.error.invalid_security")
        unless exists $secopts{ $post->{security} // '' };

    my $des = LJ::text_trim( $post->{des}, LJ::BMAX_MEMORY, LJ::CMAX_MEMORY );
    my $sec = $post->{security};

    # handle edits by deleting the old memory and recreating
    LJ::Memories::delete_by_id( $memoryu, $memory->{memid} )
        if defined $memory;
    LJ::Memories::create(
        $memoryu,
        {
            journalid => $jid,
            ditemid   => $ditemid,
            des       => $des,
            security  => $sec,
        },
        \@kwid
    );
    if ($needflush) {
        LJ::Memories::updated_keywords($memoryu);
        $exist_kw = LJ::Memories::get_keywords($memoryu);
    }

    # success: offer links onward
    my $entry = LJ::Entry->new( $ju, jitemid => $itemid );

    my @keyword_links;
    foreach my $kwid (@kwid) {
        my $kw = $exist_kw->{$kwid};
        LJ::text_out( \$kw );
        push @keyword_links,
            {
            display => $kw eq '*'
            ? LJ::Lang::ml("$ml_scope.uncategorized")
            : LJ::ehtml($kw),
            url => LJ::create_url(
                '/tools/memories',
                args => { user => $memoryu->user, keyword => $kw, filter => 'all' }
            ),
            };
    }

    $rv->{state}     = 'added';
    $rv->{entry_url} = $entry->url;
    $rv->{view_url} =
        LJ::create_url( '/tools/memories', args => { user => $memoryu->user } );
    $rv->{keyword_links} = \@keyword_links;
    $rv->{read_url}      = $remote->journal_base . "/read";
    $rv->{ju_ljuser}     = $ju->ljuser_display;

    return DW::Template->render_template( 'tools/memadd.tt', $rv );
}

1;
