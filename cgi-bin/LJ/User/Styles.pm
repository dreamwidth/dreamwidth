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

package LJ::User;
use strict;
no warnings 'uninitialized';

use Carp;
use DW::SiteScheme;
use DW::Template;

use LJ::S2;
use LJ::S2Theme;
use LJ::Customize;

########################################################################
###  24. Styles and S2-Related Functions

=head2 Styles and S2-Related Functions
=cut

sub display_journal_deleted {
    my ( $u, $remote, %opts ) = @_;
    return undef unless LJ::isu( $u );

    my $r = DW::Request->get;
    $r->status( 404 );

    my $extra = {};
    if ( $opts{bml} ) {
        $extra->{scope} = 'bml';
        $extra->{scope_data} = $opts{bml};
    } elsif ( $opts{journal_opts} ) {
        $extra->{scope} = 'journal';
        $extra->{scope_data} = $opts{journal_opts};
    }

    #get information on who deleted the account.
    my $deleter_name_html;
    if ( $u->is_community ) {
        my $userid = $u->userid;
        my $logtime = $u->statusvisdate_unix;
        my $dbcr = LJ::get_cluster_reader( $u );
        my ( $deleter_id ) = $dbcr->selectrow_array(
            "SELECT remoteid FROM userlog" .
            " WHERE userid=? AND logtime=? LIMIT 1", undef, $userid, $logtime );
        my $deleter_name = LJ::get_username( $deleter_id );
        $deleter_name_html = $deleter_name ?
            LJ::ljuser( $deleter_name ) : 'Unknown';
    } else {
        #If this isn't a community, it can only have been deleted by the
        # journal owner.
        $deleter_name_html = LJ::ljuser( $u );
    }

    #Information to pass to the "deleted account" template
    my $data = {
        reason => $u->prop( 'delete_reason' ),
        u => $u,

        #Showing an earliest purge date of 29 days after deletion, not 30,
        # to be safe with time zones.
        purge_date => LJ::mysql_date(
            $u->statusvisdate_unix + ( 29*24*3600 ), 0 ),

        deleter_name_html => $deleter_name_html,
        u_name_html => LJ::ljuser( $u ),

        is_comm => $u->is_community,
        is_protected => LJ::User->is_protected_username( $u->user ),
    };

    if ( $remote ) {
        $data = {
            %$data,

            logged_in => 1,

            #booleans for comms
            is_admin => $u->is_community && $remote->can_manage( $u ),
            is_sole_admin => $u->is_community && $remote->can_manage( $u ) &&
                scalar( $u->maintainer_userids ) == 1,
            is_member_or_watcher => $u->is_community &&
                ( $remote->member_of( $u ) || $remote->watches( $u ) ),

            #booleans for personal journals
            is_remote => $u->equals( $remote ),
            has_relationship => $remote->watches( $u ) || $remote->trusts( $u ),
        };

        #construct relationship description & link
        my $relationship_ml;
        my @relationship_links;
        if ( $u->is_community && !( $remote->can_manage( $u ) && scalar( $u->maintainer_userids ) == 1 ) ) {
         #don't offer the last admin of a deleted community a link to leave it
             my $watching = $remote->watches( $u );
             my $memberof = $remote->member_of( $u );

             if ( $watching && $memberof ) {
                 $relationship_ml = 'web.controlstrip.status.memberwatcher';
                 @relationship_links = (
                     { ml => 'web.controlstrip.links.leavecomm',
                       url => "$LJ::SITEROOT/circle/$u->{user}/edit"
                     } );
             } elsif ( $watching ) {
                 $relationship_ml = 'web.controlstrip.status.watcher';
                 @relationship_links = (
                     { ml => 'web.controlstrip.links.removecomm',
                       url => "$LJ::SITEROOT/circle/$u->{user}/edit"
                     } );
             } elsif ( $memberof ) {
                 $relationship_ml = 'web.controlstrip.status.member';
                 @relationship_links = (
                     { ml => 'web.controlstrip.links.leavecomm',
                       url => "$LJ::SITEROOT/circle/$u->{user}/edit"
                     } );
             }
        }

        if ( !$u->is_community && !$remote->equals( $u ) ) {
            #Check that it isn't the deleted account's owner, otherwise we'd
            #tell them that they had granted access to themselves!
            my $trusts = $remote->trusts( $u );
            my $watches = $remote->watches( $u );

            if ( $trusts && $watches ) {
                $relationship_ml = 'web.controlstrip.status.trust_watch';
                @relationship_links = (
                    { ml => 'web.controlstrip.links.modifycircle',
                      url => "$LJ::SITEROOT/circle/$u->{user}/edit"
                    } );
            } elsif ( $trusts ) {
                $relationship_ml = 'web.controlstrip.status.trusted';
                @relationship_links = (
                    { ml => 'web.controlstrip.links.modifycircle',
                      url => "$LJ::SITEROOT/circle/$u->{user}/edit"
                    } );
            } elsif ( $watches ) {
                $relationship_ml = 'web.controlstrip.status.watched';
                @relationship_links = (
                    { ml => 'web.controlstrip.links.modifycircle',
                      url => "$LJ::SITEROOT/circle/$u->{user}/edit"
                    } );
            }
        }

        $data->{relationship_ml} = $relationship_ml if $relationship_ml;
        $data->{relationship_links} = \@relationship_links if @relationship_links;

    }

    return DW::Template->render_template_misc( "journal/deleted.tt", $data, $extra );
}
# returns undef on error, or otherwise arrayref of arrayrefs,
# each of format [ year, month, day, count ] for all days with
# non-zero count.  examples:
#  [ [ 2003, 6, 5, 3 ], [ 2003, 6, 8, 4 ], ... ]
#
sub get_daycounts {
    my ( $u, $remote, $not_memcache ) = @_;
    return undef unless LJ::isu( $u );
    my $uid = $u->id;

    my $memkind = 'p'; # public only, changed below
    my $secwhere = "AND security='public'";
    my $viewall = 0;

    if ( LJ::isu( $remote ) ) {
        # do they have the viewall priv?
        my $r = DW::Request->get;
        my %getargs = %{ $r->get_args };
        if ( defined $getargs{'viewall'} and $getargs{'viewall'} eq '1' ) {
            $viewall = $remote->has_priv( 'canview', '*' );
            LJ::statushistory_add( $u->userid, $remote->userid,
                "viewall", "archive" ) if $viewall;
        }

        if ( $viewall || $remote->can_manage( $u ) ) {
            $secwhere = "";   # see everything
            $memkind = 'a'; # all
        } elsif ( $remote->is_individual ) {
            my $gmask = $u->is_community ? $remote->member_of( $u ) : $u->trustmask( $remote );
            if ( $gmask ) {
                $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))";
                $memkind = 'g' . $gmask; # friends case: allowmask == gmask == 1
            }
        }
    }

    my $memkey = [$uid, "dayct2:$uid:$memkind"];
    unless ($not_memcache) {
        my $list = LJ::MemCache::get($memkey);
        if ($list) {
            # this was an old version of the stored memcache value
            # where the first argument was the list creation time
            # so throw away the first argument
            shift @$list unless ref $list->[0];
            return $list;
        }
    }

    my $dbcr = LJ::get_cluster_def_reader($u) or return undef;
    my $sth = $dbcr->prepare("SELECT year, month, day, COUNT(*) ".
                             "FROM log2 WHERE journalid=? $secwhere GROUP BY 1, 2, 3");
    $sth->execute($uid);
    my @days;
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
        # we force each number from string scalars (from DBI) to int scalars,
        # so they store smaller in memcache
        push @days, [ int($y), int($m), int($d), int($c) ];
    }

    if ( $memkind ne "g1" && $memkind =~ /^g\d+$/ ) {
        # custom groups are cached for only 15 minutes
        LJ::MemCache::set( $memkey, [@days], 15 * 60 );
    } else {
        # all other security levels are cached indefinitely
        # because we clear them when there are updates
        LJ::MemCache::set( $memkey, [@days]  );
    }
    return \@days;
}

sub meta_discovery_links {
    my $u = shift;
    my $journalbase = $u->journal_base;

    my %opts = ref $_[0] ? %{$_[0]} : @_;

    my $ret = "";

    # Automatic Discovery of RSS/Atom
    if ( $opts{feeds} ) {
        if ( $opts{tags} && @{$opts{tags}||[]}) {
            my $taglist = join( ',', map( { LJ::eurl($_) } @{$opts{tags}||[]} ) );
            $ret .= qq{<link rel="alternate" type="application/rss+xml" title="RSS: filtered by selected tags" href="$journalbase/data/rss?tag=$taglist" />\n};
            $ret .= qq{<link rel="alternate" type="application/atom+xml" title="Atom: filtered by selected tags" href="$journalbase/data/atom?tag=$taglist" />\n};
        }

        $ret .= qq{<link rel="alternate" type="application/rss+xml" title="RSS: all entries" href="$journalbase/data/rss" />\n};
        $ret .= qq{<link rel="alternate" type="application/atom+xml" title="Atom: all entries" href="$journalbase/data/atom" />\n};
        $ret .= qq{<link rel="service" type="application/atomsvc+xml" title="AtomAPI service document" href="} . $u->atom_service_document . qq{" />\n};
    }

    # OpenID Server and Yadis
    $ret .= $u->openid_tags if $opts{openid};

    # FOAF autodiscovery
    if ( $opts{foaf} ) {
        my $foafurl = "$journalbase/data/foaf";
        $ret .= qq{<link rel="meta" type="application/rdf+xml" title="FOAF" href="$foafurl" />\n};

        if ($u->email_visible($opts{remote})) {
            my $digest = Digest::SHA1::sha1_hex( 'mailto:' . $u->email_raw );
            $ret .= qq{<meta name="foaf:maker" content="foaf:mbox_sha1sum '$digest'" />\n};
        }
    }

    return $ret;
}


sub opt_ctxpopup {
    my $u = shift;

    # if unset, default to on
    my $prop = $u->raw_prop('opt_ctxpopup') || 'Y';

    return $prop;
}

# should contextual hover be displayed for icons
sub opt_ctxpopup_icons {
    return ( $_[0]->prop( 'opt_ctxpopup' ) eq "Y" || $_[0]->prop( 'opt_ctxpopup' ) eq "I" );
}

# should contextual hover be displayed for the graphical userhead
sub opt_ctxpopup_userhead {
    return ( $_[0]->prop( 'opt_ctxpopup' ) eq "Y" || $_[0]->prop( 'opt_ctxpopup' ) eq "U" );
}


sub opt_embedplaceholders {
    my $u = shift;

    my $prop = $u->raw_prop('opt_embedplaceholders');

    if (defined $prop) {
        return $prop;
    } else {
        my $imagelinks = $u->prop('opt_imagelinks');
        return $imagelinks;
    }
}

sub set_default_style {
    my $style = eval { LJ::Customize->verify_and_load_style( $_[0] ); };
    warn $@ if $@;

    return $style;
}

sub show_control_strip {
    my $u = shift;

    LJ::Hooks::run_hook('control_strip_propcheck', $u, 'show_control_strip') if LJ::is_enabled('control_strip_propcheck');

    my $prop = $u->raw_prop('show_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}


sub view_control_strip {
    my $u = shift;

    LJ::Hooks::run_hook('control_strip_propcheck', $u, 'view_control_strip') if LJ::is_enabled('control_strip_propcheck');

    my $prop = $u->raw_prop('view_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}


# BE VERY CAREFUL about the return values and arguments you pass to this
# method.  please understand the security implications of this, and how to
# properly and safely use it.
#
sub view_priv_check {
    my ( $remote, $u, $requested, $page, $itemid ) = @_;

    # $requested is set to the 'viewall' GET argument.  this should ONLY be on if the
    # user is EXPLICITLY requesting to view something they can't see normally.  most
    # of the time this is off, so we can bail now.
    return unless $requested;

    # now check the rest of our arguments for validity
    return unless LJ::isu( $remote ) && LJ::isu( $u );
    return if defined $page && $page !~ /^\w+$/;
    return if defined $itemid && $itemid !~ /^\d+$/;

    # viewsome = "this user can view suspended content"
    my $viewsome = $remote->has_priv( canview => 'suspended' );

    # viewall = "this user can view all content, even private"
    my $viewall = $viewsome && $remote->has_priv( canview => '*' );

    # make sure we log the content being viewed
    if ( $viewsome && $page ) {
        my $user = $u->user;
        $user .= ", itemid: $itemid" if defined $itemid;
        my $sv = $u->statusvis;
        LJ::statushistory_add( $u->userid, $remote->userid, 'viewall',
                               "$page: $user, statusvis: $sv");
    }

    return wantarray ? ( $viewall, $viewsome ) : $viewsome;
}

=head2 C<< $u->viewing_style( $view ) >>
Takes a user and a view argument and returns what that user's preferred
style is for a given view.
=cut
sub viewing_style {
    my ( $u, $view ) = @_;

    $view ||= 'entry';

    my %style_types = ( O => "original", M => "mine", S => "site", L => "light" );
    my %view_props = (
        entry => 'opt_viewentrystyle',
        reply => 'opt_viewentrystyle',
        icons => 'opt_viewiconstyle',
    );

    my $prop = $view_props{ $view } || 'opt_viewjournalstyle';
    return 'original' unless defined $u->prop( $prop );
    return $style_types{ $u->prop( $prop ) } || 'original';
}

########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

use Carp;

########################################################################
###  24. Styles and S2-Related Functions

=head2 Styles and S2-Related Functions (LJ)
=cut


# FIXME: Update to pull out S1 support.
# <LJFUNC>
# name: LJ::make_journal
# class:
# des:
# info:
# args: dbarg, user, view, remote, opts
# des-:
# returns:
# </LJFUNC>
sub make_journal {
    my ($user, $view, $remote, $opts) = @_;

    my $r = DW::Request->get;
    my $geta = $r->get_args;
    $opts->{getargs} = $geta;

    my $u = $opts->{'u'} || LJ::load_user($user);
    unless ($u) {
        $opts->{'baduser'} = 1;
        return "<!-- No such user -->";  # return value ignored
    }
    LJ::set_active_journal($u);

    my ($styleid);
    if ($opts->{'styleid'}) {  # s1 styleid
        confess 'S1 was removed, sorry.';
    } else {

        $view ||= "lastn";    # default view when none specified explicitly in URLs
        if ($LJ::viewinfo{$view} || $view eq "month" ||
            $view eq "entry" || $view eq "reply")  {
            $styleid = -1;    # to get past the return, then checked later for -1 and fixed, once user is loaded.
        } else {
            $opts->{'badargs'} = 1;
        }
    }
    return unless $styleid;


    $u->{'_journalbase'} = $u->journal_base( vhost => $opts->{'vhost'} );

    my $eff_view = $LJ::viewinfo{$view}->{'styleof'} || $view;

    my @needed_props = ("stylesys", "s2_style", "url", "urlname", "opt_nctalklinks",
                        "renamedto",  "opt_blockrobots", "opt_usesharedpic", "icbm",
                        "journaltitle", "journalsubtitle",
                        "adult_content", "opt_viewjournalstyle", "opt_viewentrystyle");

    # preload props the view creation code will need later (combine two selects)
    if (ref $LJ::viewinfo{$eff_view}->{'owner_props'} eq "ARRAY") {
        push @needed_props, @{$LJ::viewinfo{$eff_view}->{'owner_props'}};
    }

    $u->preload_props(@needed_props);

    # if the remote is the user to be viewed, make sure the $remote
    # hashref has the value of $u's opt_nctalklinks (though with
    # LJ::load_user caching, this may be assigning between the same
    # underlying hashref)
    $remote->{opt_nctalklinks} = $u->{opt_nctalklinks}
        if $remote && $remote->equals( $u );

    # What style are we shooting for, based on user preferences and get arguments?
    my $stylearg = LJ::determine_viewing_style( $geta, $view, $remote );
    my $stylesys = 1;

    if ($styleid == -1) {

        my $get_styleinfo = sub {

            # forced s2 style id (must be numeric)
            if ($geta->{s2id} && $geta->{s2id} =~ /^\d+$/) {

                # get the owner of the requested style
                my $style = LJ::S2::load_style( $geta->{s2id} );
                my $owner = $style && $style->{userid} ? $style->{userid} : 0;

                # remote can use s2id on this journal if:
                # owner of the style is remote or managed by remote OR
                # owner of the style has s2styles cap and remote is viewing owner's journal OR
                # all layers in this style are public (public layer or is_public)

                if ($u->id == $owner && $u->get_cap("s2styles")) {
                    $opts->{'style_u'} = LJ::load_userid($owner);
                    return (2, $geta->{'s2id'});
                }

                if ($remote && $remote->can_manage($owner)) {
                    # check is owned style still available: paid user possible became plus...
                    my $lay_id = $style->{layer}->{layout};
                    my $theme_id = $style->{layer}->{theme};
                    my %lay_info;
                    LJ::S2::load_layer_info(\%lay_info, [$style->{layer}->{layout}, $style->{layer}->{theme}]);

                    if (LJ::S2::can_use_layer($remote, $lay_info{$lay_id}->{redist_uniq})
                        and LJ::S2::can_use_layer($remote, $lay_info{$theme_id}->{redist_uniq})) {
                        $opts->{'style_u'} = LJ::load_userid($owner);
                        return (2, $geta->{'s2id'});
                    } # else this style not allowed by policy
                }

                return ( 2, $geta->{s2id} ) if LJ::S2::style_is_public( $style );
            }

            # style=mine passed in GET or userprop to use mine?
            if ( $remote && $stylearg eq 'mine' ) {
                # get remote props and decide what style remote uses
                $remote->preload_props("stylesys", "s2_style");

                # remote using s2; make sure we pass down the $remote object as the style_u to
                # indicate that they should use $remote to load the style instead of the regular $u
                if ($remote->{'stylesys'} == 2 && $remote->{'s2_style'}) {
                    $opts->{'checkremote'} = 1;
                    $opts->{'style_u'} = $remote;
                    return (2, $remote->{'s2_style'});
                }

                # return stylesys 2; will fall back on default style
                $opts->{style_u} = $remote;
                return ( 2, undef );
            }

            # resource URLs have the styleid in it
            # unless they're a special style, like sitefeeds (which have no styleid)
            # in which case, let them fall through. Something else will handle it
            if ( $view eq "res" && $opts->{'pathextra'} =~ m!^/(\d+)/! && $1 ) {
                return (2, $1);
            }

            # feed accounts have a special style
            if ( $u->is_syndicated && %$LJ::DEFAULT_FEED_STYLE ) {
                return (2, "sitefeeds");
            }

            my $forceflag = 0;
            LJ::Hooks::run_hooks("force_s1", $u, \$forceflag);

            # if none of the above match, they fall through to here
            if ( !$forceflag && $u->{'stylesys'} == 2 ) {
                return (2, $u->{'s2_style'});
            }

            # no special case, let it fall back on the default
            return ( 2, undef );
        };

        ($stylesys, $styleid) = $get_styleinfo->();
    }

    # transcode the tag filtering information into the tag getarg; this has to
    # be done above the s1shortcomings section so that we can fall through to that
    # style for lastn filtered by tags view
    if ($view eq 'lastn' && $opts->{pathextra} && $opts->{pathextra} =~ /^\/tag\/(.+)$/) {
        $opts->{getargs}->{tag} = LJ::durl($1);
        $opts->{pathextra} = undef;
    }

    # do the same for security filtering
    elsif ( ( $view eq 'lastn' || $view eq 'read' ) && $opts->{pathextra} && $opts->{pathextra} =~ /^\/security\/(.*)$/ ) {
        $opts->{getargs}->{security} = LJ::durl($1);
        $opts->{pathextra} = undef;
    }

    $r->note( journalid => $u->userid )
        if $r;

    my $notice = sub {
        my ( $msg, $status ) = @_;

        my $url = "$LJ::SITEROOT/users/$user/";
        $opts->{'status'} = $status if $status;

        my $head = $u->meta_discovery_links( feeds => 1, openid => 1, foaf => 1, remote => $remote );

        return qq{
            <html>
            <head>
            $head
            </head>
            <body>
             <h1>Notice</h1>
             <p>$msg</p>
             <p>Instead, please use <nobr><a href=\"$url\">$url</a></nobr></p>
            </body>
            </html>
        }.("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 50);
    };
    my $error = sub {
        my ( $msg, $status, $header ) = @_;
        $header ||= 'Error';
        $opts->{'status'} = $status if $status;

        return qq{
            <h1>$header</h1>
            <p>$msg</p>
        }.("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 50);
    };
    if ( $LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && ! $u->is_redirect &&
        ! LJ::get_cap( $u, "userdomain" ) ) {
        return $notice->( BML::ml( 'error.vhost.nodomain1', { user_domain => $LJ::USER_DOMAIN } ) );
    }
    if ( $opts->{'vhost'} =~ /^other:/ ) {
        return $notice->( BML::ml( 'error.vhost.noalias1' ) );
    }
    if ($opts->{'vhost'} eq "community" && $u->journaltype !~ /[CR]/) {
        $opts->{'badargs'} = 1; # Output a generic 'bad URL' message if available
        return $notice->( BML::ml( 'error.vhost.nocomm' ) );
    }
    if ($view eq "network" && ! LJ::get_cap($u, "friendsfriendsview")) {
        return BML::ml('cprod.friendsfriendsinline.text3.v1');
    }

    # signal to LiveJournal.pm that we can't handle this
    if ( $stylesys == 1 || $stylearg eq 'site' || $stylearg eq 'light' ) {
        # If they specified ?format=light, it means they want a page easy
        # to deal with text-only or on a mobile device.  For now that means
        # render it in the lynx site scheme.
        DW::SiteScheme->set_for_request( 'lynx' )
            if $stylearg eq 'light';

        # Render a system-owned S2 style that renders
        # this content, then passes it to get treated as BML
        $stylesys = 2;
        $styleid = "siteviews";
    }

    # now, if there's a GET argument for tags, split those out
    if (exists $opts->{getargs}->{tag}) {
        my $tagfilter = $opts->{getargs}->{tag};

        unless ( $tagfilter ) {
            $opts->{redir} = $u->journal_base . "/tag/";
            return;
        }

        # error if disabled
        return $error->( BML::ml( 'error.tag.disabled' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            unless LJ::is_enabled('tags');

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $error->( BML::ml( 'error.tag.s1' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            if $stylesys == 1 && $view ne 'data' && ! $u->is_redirect;

        # overwrite any tags that exist
        $opts->{tags} = [];
        return $error->( BML::ml( 'error.tag.invalid' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            unless LJ::Tags::is_valid_tagstring($tagfilter, $opts->{tags}, { omit_underscore_check => 1 });

        # get user's tags so we know what remote can see, and setup an inverse mapping
        # from keyword to tag
        $opts->{tagids} = [];
        my $tags = LJ::Tags::get_usertags($u, { remote => $remote });
        my %kwref = ( map { $tags->{$_}->{name} => $_ } keys %{$tags || {}} );

        foreach (@{$opts->{tags}}) {
            return $error->( BML::ml( 'error.tag.undef' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
                unless $kwref{$_};
            push @{$opts->{tagids}}, $kwref{$_};
        }

        my $tagmode = $opts->{getargs}->{mode} || '';
        $opts->{tagmode} = $tagmode eq 'and' ? 'and' : 'or';
        # also allow mode=all (equivalent to 'and')
        $opts->{tagmode} = 'and' if $tagmode eq 'all';
    }

    # validate the security filter
    if (exists $opts->{getargs}->{security}) {
        my $securityfilter = $opts->{getargs}->{security};

        my $canview_groups = ( $view eq "lastn"  # viewing recent entries
          # ... or your own read page (can't see locked entries on others' read page anyway)
            || ( $view eq "read" && $u->equals( $remote ) ) );

        my $r = DW::Request->get;
        my $security_err = sub {
            my ( $args, %opts ) = @_;

            my $status = $opts{status} || $r->NOT_FOUND;

            my @levels;
            my @groups;
            # error message is an appropriate type to show the list
            if ( $opts{show_list} && $canview_groups ) {

                my $path = $view eq "read" ? "/read/security" : "/security";
                @levels  = ( { link => LJ::create_url( "$path/public", viewing_style => 1 ),
                                name_ml => "label.security.public" } );

                if ( $u->is_comm ) {
                    push @levels, { link => LJ::create_url( "$path/access", viewing_style => 1 ),
                                    name_ml => "label.security.members" }
                                if $remote && $remote->member_of( $u );

                    push @levels, { link => LJ::create_url( "$path/private", viewing_style => 1 ),
                                    name_ml => "label.security.maintainers" }
                                if $remote && $remote->can_manage_other( $u );
                } else {
                    push @levels, { link => LJ::create_url( "$path/access", viewing_style => 1 ),
                                    name_ml => "label.security.accesslist" }
                                if $u->trusts( $remote );

                    push @levels, { link => LJ::create_url( "$path/private", viewing_style => 1 ),
                                    name_ml => "label.security.private" }
                                if $u->equals( $remote );
                }

                $args->{levels} = \@levels;

                @groups = map { { link => LJ::create_url( "$path/group:" . $_->{groupname} ), name => $_->{groupname} } } $remote->trust_groups if $u->equals( $remote );
                $args->{groups} = \@groups;
            }

            ${$opts->{handle_with_siteviews_ref}} = 1;
            my $ret = DW::Template->template_string( "journal/security.tt",
                $args,
                {
                    status => $status,
                }
            );
            $opts->{siteviews_extra_content} = $args->{sections};
            return $ret;
        };

        return $security_err->( { message => undef }, show_list => 1 )
            unless $securityfilter;

        return $security_err->( { message => "error.security.nocap2" }, status => $r->FORBIDDEN )
            unless LJ::get_cap( $remote, "security_filter" ) || LJ::get_cap( $u, "security_filter" );

        return $security_err->( { message => "error.security.disabled2" } )
            unless LJ::is_enabled( "security_filter" );

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $security_err->( { message => "error.security.s1.2" } )
            if $stylesys == 1 && $view ne 'data' && ! $u->is_redirect;

        # check the filter itself
        if ( lc( $securityfilter ) eq 'friends' ) {
            $opts->{securityfilter} = 'access';
        } elsif ($securityfilter =~ /^(?:public|access|private)$/i) {
            $opts->{securityfilter} = lc($securityfilter);

        # see if they want to filter by a custom group
        } elsif ( $securityfilter =~ /^group:(.+)$/i && $canview_groups ) {
            my $tf = $u->trust_groups( name => $1 );
            if ( $tf && ( $u->equals( $remote ) ||
                          $u->trustmask( $remote ) & ( 1 << $tf->{groupnum} ) ) ) {
                # let them filter the results page by this group
                $opts->{securityfilter} = $tf->{groupnum};
            }
        }

        return $security_err->( { message => "error.security.invalid2" }, show_list => 1 )
            unless defined $opts->{securityfilter};
    }

    unless ( $geta->{'viewall'} && $remote && $remote->has_priv( "canview", "suspended" ) ||
             $opts->{'pathextra'} =~ m!/(\d+)/stylesheet$! ) { # don't check style sheets
        return $u->display_journal_deleted( $remote, journal_opts => $opts ) if $u->is_deleted;

        if ( $u->is_suspended ) {
            my $warning = BML::ml( 'error.suspended.text', { user => $u->ljuser_display, sitename => $LJ::SITENAME } );
            return $error->( $warning, "403 Forbidden", BML::ml( 'error.suspended.name' ) );
        }

        my $entry = $opts->{ljentry};
        if ( $entry && $entry->is_suspended_for( $remote ) ) {
            my $journal_base = $u->journal_base;
            my $warning = BML::ml( 'error.suspended.entry', { aopts => "href='$journal_base/'" } );
            return $error->( $warning, "403 Forbidden", BML::ml( 'error.suspended.name' ) );
        }
    }
    return $error->( BML::ml( 'error.purged.text' ), "410 Gone", BML::ml( 'error.purged.name' ) ) if $u->is_expunged;

    my %valid_identity_views = (
        read => 1,
        res  => 1,
        icons => 1,
    );
    # FIXME: pretty this up at some point, to maybe auto-redirect to
    # the external URL or something, but let's just do this for now
    # res is a resource, such as an external stylesheet
    if ( $u->is_identity && !$valid_identity_views{$view} ) {
        my $location = $u->openid_identity;
        my $warning = BML::ml( 'error.nojournal.openid', { aopts => "href='$location'", id => $location } );
        return $error->( $warning, "404 Not here" );
    }

    $opts->{'view'} = $view;

    # what charset we put in the HTML
    $opts->{'saycharset'} ||= "utf-8";

    if ($view eq 'data') {
        return LJ::Feed::make_feed($r, $u, $remote, $opts);
    }

    if ($stylesys == 2) {
        $r->note(codepath => "s2.$view")
            if $r;

        eval { LJ::S2->can("dostuff") };  # force Class::Autouse

        my $mj;

        eval {
            $mj = LJ::S2::make_journal($u, $styleid, $view, $remote, $opts);
        };
        if ( $@ ) {
            if ( $remote && $remote->show_raw_errors ) {
                my $r = DW::Request->get;
                $r->content_type("text/html");
                $r->print("<b>[Error: $@]</b>");
                warn $@;
                return;
            } else {
                die $@;
            }
        }

        return $mj;
    }

    # if we get here, then we tried to run the old S1 path, so die and hope that
    # somebody comes along to fix us :(
    confess 'Tried to run S1 journal rendering path.';
}


1;
