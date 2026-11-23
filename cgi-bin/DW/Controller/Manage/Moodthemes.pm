#!/usr/bin/perl
#
# DW::Controller::Manage::Moodthemes
#
# Lets a user (or a community's admin, via authas) manage custom mood themes:
# create a theme, pick one as the journal default, delete one, and edit the
# image URL / size of every mood in a theme, with per-mood inheritance from
# parent moods. The editor's image previews and field disabling are driven
# by js/moodtheme-editor.js.
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

package DW::Controller::Manage::Moodthemes;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

use DW::Mood;

DW::Routing->register_string(
    '/manage/moodthemes', \&moodthemes_handler,
    app      => 1,
    no_cache => 1
);

sub moodthemes_handler {
    my $ml_scope = '/manage/moodthemes.tt';

    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $u      = $rv->{u};
    my $post   = $r->post_args;
    my $scope  = sub { LJ::Lang::ml( "$ml_scope$_[0]", $_[1] ) };
    my $render = sub {
        $rv->{mode} = $_[0];
        return DW::Template->render_template( 'manage/moodthemes.tt', $rv );
    };

    my $self_uri = LJ::create_url( undef, keep_args => ['authas'] );
    $rv->{self_uri} = $self_uri;

    if ( $r->did_post ) {

        # figure out if they are editing a theme and which one it is
        my $themeid = $post->{themeid};
        my @ids     = split ',', $post->{themeids} // '';
        foreach (@ids) {
            $themeid = $_ if $post->{"edit:$_"};
        }

        if ( !$themeid ) {

            # they decided to use one of their custom themes
            my $use_theme;
            foreach (@ids) {
                $use_theme = $_ if $post->{"use:$_"};
            }

            if ($use_theme) {
                return error_ml("$ml_scope.error.notyourtheme")
                    unless
                    defined DW::Mood->get_themes( { themeid => $use_theme, ownerid => $u->id } );
                $u->update_self( { moodthemeid => $use_theme } )
                    unless $u->moodtheme == $use_theme;
                return $r->redirect($self_uri);
            }
        }

        # make sure they can even edit this theme, and load its info
        my $info;
        if ( $themeid && !$post->{isnew} ) {
            $info = DW::Mood->get_themes( { themeid => $themeid, ownerid => $u->id } );
            return error_ml("$ml_scope.error.notyourtheme") unless defined $info;
        }

        # are we deleting a theme?
        foreach my $tid (@ids) {
            if ( $post->{"delete:$tid"} ) {
                $u->delete_moodtheme($tid)
                    or return error_ml("$ml_scope.error.cantdeletetheme");
                return $r->redirect($self_uri);
            }
        }

        if ( ( $themeid && $post->{edit} ) || $post->{isnew} ) {

            # show the editor, creating the theme first if it's new
            if ( $post->{isnew} ) {
                return error_ml("$ml_scope.error.nonamegiven")
                    unless LJ::trim( $post->{name} );
                my $err;
                $themeid = $u->create_moodtheme( $post->{name}, '', \$err )
                    or return DW::Template->render_template( 'error.tt', { message => $err } );
                $info = { name => $post->{name} };
            }

            $rv->{themeid}         = $themeid;
            $rv->{theme_name}      = $info->{name};
            $rv->{theme_name_html} = LJ::ehtml( $info->{name} );
            $rv->{mood_tree}       = mood_tree( DW::Mood->new($themeid) );
            return $render->('edit');
        }
        elsif ($themeid) {

            # save their changes
            my $theme = DW::Mood->new($themeid)
                or return error_ml("$ml_scope.error.cantupdatetheme");

            # update the name if needed
            if ( $info->{name} ne $post->{name} ) {
                $theme->update( name => $post->{name} )
                    or return error_ml("$ml_scope.error.cantupdatetheme");
            }

            # figure out what needs to be changed in the db
            my ( @picdata, @results, @warnings );
            foreach my $key ( keys %$post ) {

                # a fully numeric key is a mood id; the other fields for that
                # mood build off the id number
                next unless $key =~ /^(\d+)$/;
                my $mid    = $1;
                my $width  = $post->{ $mid . 'w' } || 0;
                my $height = $post->{ $mid . 'h' } || 0;
                my $picurl = $post->{$key};
                my $mname  = DW::Mood->mood_name($mid);

                # don't update if nothing changed
                my %picdata;
                $theme->get_picture( $mid, \%picdata );
                next
                    if $picurl eq ( $picdata{pic} // '' )
                    && $width ==  ( $picdata{w} // 0 )
                    && $height == ( $picdata{h} // 0 );

                # allow width & height to default to that of the parent
                if ( my $pid = $post->{ $mid . 'parent' } ) {
                    $width  ||= $post->{ $pid . 'w' };
                    $height ||= $post->{ $pid . 'h' };
                    unless ( $width && $height ) {

                        # check the database
                        my %parent;
                        $theme->get_picture( $pid, \%parent );
                        $width  ||= $parent{w};
                        $height ||= $parent{h};
                    }
                }

                # one of these is blank, so delete the mood
                unless ( $picurl && $width && $height ) {
                    push @picdata, [ $mid, {} ];
                    if ( $picdata{pic} ) {
                        push @results, $scope->( '.mood.reset', { mood => "$mname($mid)" } );
                    }
                    else {
                        push @warnings, $scope->( '.mood.notcreated', { mood => "$mname($mid)" } );
                    }
                    next;
                }

                # we have a picurl, width, and height. add it.
                if ( $picurl =~ m!^https?://[^\'\"\0\s]+$! ) {
                    push @picdata,
                        [ $mid, { picurl => $picurl, width => $width, height => $height } ];
                    push @results,
                        $scope->(
                        '.mood.setpic', { mood => "$mname($mid)", url => LJ::ehtml($picurl) }
                        );
                }
            }

            # look again for inheritance
            # (the url field of an inherited mood was disabled, so no match above)
            foreach my $key ( keys %$post ) {
                next unless $key =~ /^(\d+)inherit$/;
                my $mid = $1;
                next if $post->{$mid};                 # already processed above
                next if $post->{ $mid . 'oldinh' };    # no change in status

                # inherited, don't represent in db
                if ( $post->{$key} eq 'on' ) {
                    my $mname = DW::Mood->mood_name($mid);
                    push @picdata, [ $mid, {} ];
                    push @results, $scope->( '.mood.deleted', { mood => "$mname($mid)" } );
                }
            }

            my $err;
            $theme->set_picture_multi( \@picdata, \$err )
                or return DW::Template->render_template( 'error.tt', { message => $err } );

            $rv->{results}  = \@results;
            $rv->{warnings} = \@warnings;
            return $render->('saved');
        }

        # a POST with nothing recognizable in it; start over
        return $r->redirect($self_uri);
    }

    # show the list of this user's themes, with create/edit/use/delete options
    $rv->{can_create}  = $u->can_create_moodthemes;
    $rv->{upsell_html} = LJ::Hooks::run_hook("moodtheme_upsell");

    if ( $rv->{can_create} ) {
        my @user_themes = DW::Mood->get_themes( { ownerid => $u->id } );
        my @themes;
        foreach my $theme (@user_themes) {
            my $tid  = $theme->{moodthemeid};
            my $tobj = DW::Mood->new($tid);

            # example pictures for the table header moods: happy, sad, angry
            my @pics;
            foreach my $moodid ( 15, 25, 2 ) {
                my %pic;
                $tobj->get_picture( $moodid, \%pic ) if $tobj;
                push @pics, %pic ? { pic => $pic{pic}, w => $pic{w}, h => $pic{h} } : undef;
            }

            push @themes,
                {
                id      => $tid,
                name    => $theme->{name},
                current => ( $tid == $u->moodtheme ? 1 : 0 ),
                pics    => \@pics,
                };
        }
        $rv->{themes}         = \@themes;
        $rv->{themeids}       = join ',', map { $_->{id} } @themes;
        $rv->{delete_confirm} = LJ::ejs( $scope->('.yourthemes.delete.confirm') );
    }

    return $render->('select');
}

# build a nested arrayref of every mood, each with this theme's picture data,
# sorted by name and nested under its parent mood
sub mood_tree {
    my ($theme) = @_;
    my $moods = DW::Mood->get_moods;

    my %lists;
    foreach ( sort { $moods->{$a}->{name} cmp $moods->{$b}->{name} } keys %$moods ) {
        my $m = $moods->{$_};
        push @{ $lists{ $m->{parent} } }, $m;
    }

    my $build;
    $build = sub {
        my ($num) = @_;
        return [] unless $lists{$num};

        my @out;
        foreach my $mood ( @{ $lists{$num} } ) {
            my %pic;
            $theme->get_picture( $mood->{id}, \%pic ) if $theme;

            push @out, {
                id          => $mood->{id},
                name        => $mood->{name},
                parent      => $mood->{parent},
                parent_name => $mood->{parent} ? DW::Mood->mood_name( $mood->{parent} ) : '',
                pic         => $pic{pic} // '',
                w           => $pic{w} // '',
                h           => $pic{h} // '',
                has_pic     => %pic ? 1 : 0,

                # the picture is really just inherited from a parent mood
                inherited => ( %pic && $pic{moodid} == $mood->{id} ) ? 0 : 1,
                children  => $build->( $mood->{id} ),
            };
        }
        return \@out;
    };

    return $build->(0);
}

1;
