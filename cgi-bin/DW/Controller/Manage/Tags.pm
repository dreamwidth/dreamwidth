#!/usr/bin/perl
#
# DW::Controller::Manage::Tags
#
# Lets a user (or a community's admin, via authas) review and edit the tags
# defined in a journal: create, rename, merge, and delete tags, and set the
# tag permission levels. The interactive bits are driven by js/tags.js.
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

package DW::Controller::Manage::Tags;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

use LJ::Tags;

DW::Routing->register_string( '/manage/tags', \&tags_handler, app => 1, no_cache => 1 );

sub tags_handler {
    my $ml_scope = '/manage/tags.tt';

    return error_ml("$ml_scope.disabled") unless LJ::is_enabled('tags');

    my ( $ok, $rv ) = controller( anonymous => 0, authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $u      = $rv->{u};
    my $get    = $r->get_args;
    my $post   = $r->post_args;

    LJ::need_res("js/tags.js");
    LJ::need_res( { priority => $LJ::OLD_RES_PRIORITY }, "stc/tags.css" );

    my $add_text = LJ::Lang::ml("$ml_scope.addnew");
    my $errors   = DW::FormErrors->new;

    if ( $r->did_post ) {

        # adding new tags ('add' image submit sends add.x / add.y)
        my $do_add = $post->{add} || $post->{'add.x'} || $post->{'add.y'};
        if ( $do_add || ( $post->{add_field} && $post->{add_field} ne $add_text ) ) {
            my $tagerr  = "";
            my $created = LJ::Tags::create_usertag( $u, $post->{add_field},
                { display => 1, err_ref => \$tagerr } );
            $errors->add_string( '', $tagerr ) unless $created;
        }

        # deleting tags
        if ( $post->{delete} ) {
            foreach my $id ( split /\0/, ( $post->{tags} // '' ) ) {
                $id =~ s/_.*//;
                LJ::Tags::delete_usertag( $u, 'id', $id );
            }
        }

        # renaming a tag
        if ( $post->{rename} ) {
            my @tagnames = map { s/\d+_//; $_; } split /\0/, ( $post->{tags} // '' );
            my $new_tag  = LJ::trim( $post->{rename_field} );
            if ( $new_tag =~ /,/ ) {
                $errors->add( '', "$ml_scope.error.rename.multiple" );
            }
            else {
                my $tagerr = "";
                my $renamed =
                    LJ::Tags::rename_usertag( $u, 'name', $tagnames[0], $new_tag, \$tagerr );
                $errors->add_string( '', $tagerr ) unless $renamed;
            }
        }

        # merging tags
        if ( $post->{merge} ) {
            my @tagnames    = map { s/\d+_//; $_; } split /\0/, ( $post->{tags} // '' );
            my $new_tagname = LJ::trim( $post->{merge_field} );
            if ( $new_tagname =~ /,/ ) {
                $errors->add( '', "$ml_scope.error.rename.multiple" );
            }
            else {
                my $tagerr = "";
                my $merged = LJ::Tags::merge_usertags( $u, $new_tagname, \$tagerr, @tagnames );
                $errors->add_string( '', $tagerr ) unless $merged;
            }
        }

        # show journal entries for the selected tags
        if ( $post->{'show posts'} ) {
            my $tags    = LJ::Tags::get_usertags($u);
            my $taglist = LJ::eurl(
                join ',',
                map     { $tags->{$_}->{name} }
                    map { /^(\d+)_/; $1; } split /\0/,
                ( $post->{tags} // '' )
            );
            return $r->redirect( $u->journal_base . "/tag/$taglist" );
        }

        # saving the permission levels
        if ( $post->{save_levels} ) {
            my $add     = $post->{add_level}     // '';
            my $control = $post->{control_level} // '';
            if (   $add =~ /^(?:private|public|protected|author_admin|group:\d+)$/
                && $control =~ /^(?:private|public|protected|group:\d+)$/ )
            {
                $u->set_prop( "opt_tagpermissions", "$add,$control" );
            }
            else {
                $errors->add( '', "$ml_scope.error.invalidsettings" );
            }
        }
    }

    # get the (possibly updated) tag list
    my $tags     = LJ::Tags::get_usertags($u);
    my $tagcount = scalar keys %$tags;

    # build histogram usage levels from 'uses' counts, for the cell-bar icons
    if ($tagcount) {
        my $groups = 5;
        my @data   = map { [ $_, $tags->{$_}->{uses} ] }
            sort { $tags->{$a}->{uses} <=> $tags->{$b}->{uses} } keys %$tags;
        my $max   = $data[-1]->[1];
        my $min   = $data[0]->[1];
        my $width = ( $max - $min ) / $groups || 1;

        my %range;
        $range{$_} = [ $min + ( $_ - 1 ) * $width, $min + ( $_ * $width ) ] for 1 .. $groups;

        foreach (@data) {
            my ( $id, $use ) = @$_;
            for ( 1 .. $groups ) {
                if ( $use >= $range{$_}->[0] && $use <= $range{$_}->[1] ) {
                    $tags->{$id}->{histogram_group} = $_;
                    last;
                }
            }
        }
    }

    # ordered tag list for the <select> (alpha by default, or by usage)
    my $sort    = $get->{sort} || '';
    my @ordered = sort {
              $sort eq 'use'
            ? $tags->{$b}->{uses} <=> $tags->{$a}->{uses}
            : $tags->{$a}->{name} cmp $tags->{$b}->{name}
    } keys %$tags;
    my @tag_options =
        map { { id => $_, name => $tags->{$_}->{name}, level => $tags->{$_}->{histogram_group} } }
        @ordered;

    # per-tag data for the JS `tags` array (keyed by id)
    my @tags_js;
    foreach ( sort { $a <=> $b } keys %$tags ) {
        my $tag = $tags->{$_};
        my $sec = $tag->{security};
        my ( $pub, $pri, $fr, $tot ) =
            ( $sec->{public}, $sec->{private}, $sec->{protected}, $tag->{uses} );
        push @tags_js,
            {
            id    => $_,
            name  => $tag->{name},
            level => $tag->{security_level},
            pub   => $pub,
            pri   => $pri,
            fr    => $fr,
            grp   => $tot - ( $pub + $pri + $fr ),
            tot   => $tot,
            };
    }

    # permission-level <select> option lists ([ value, label, ... ] flat)
    my @control_groups = ( "public", LJ::Lang::ml("$ml_scope.setting.public") );
    if ( $u->is_person ) {
        push @control_groups, ( "protected", LJ::Lang::ml("$ml_scope.setting.trusted") );
        push @control_groups, ( "private",   LJ::Lang::ml("$ml_scope.setting.private") );
    }
    else {
        push @control_groups, ( "protected", LJ::Lang::ml("$ml_scope.setting.members") );
        push @control_groups, ( "private",   LJ::Lang::ml("$ml_scope.setting.maintainers") );
    }

    my @add_groups = @control_groups;
    push @add_groups, ( "author_admin", LJ::Lang::ml("$ml_scope.setting.author_admin") )
        if $u->is_community;

    my @custom_groups = map { ( "group:" . $_->{groupnum}, $_->{groupname} ) } $u->trust_groups;
    push @control_groups, @custom_groups;
    push @add_groups,     @custom_groups;

    my $security = LJ::Tags::get_permission_levels($u);

    $rv->{errors}         = $errors;
    $rv->{add_text}       = $add_text;
    $rv->{merge_confirm}  = LJ::ejs( LJ::Lang::ml("$ml_scope.confirm.merge") );
    $rv->{delete_confirm} = LJ::ejs( LJ::Lang::ml("$ml_scope.confirm.delete") );
    $rv->{did_post}       = $r->did_post;
    $rv->{tagcount}       = $tagcount;
    $rv->{tagmax}         = $u->count_tags_max;
    $rv->{tag_options}    = \@tag_options;
    $rv->{tags_js}        = \@tags_js;
    $rv->{sort}           = $sort;
    $rv->{control_groups} = \@control_groups;
    $rv->{add_groups}     = \@add_groups;
    $rv->{control_level}  = $security->{control};
    $rv->{add_level}      = $security->{add};

    return DW::Template->render_template( 'manage/tags.tt', $rv );
}

1;
