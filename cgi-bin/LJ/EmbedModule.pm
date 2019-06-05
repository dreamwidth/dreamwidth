#!/usr/bin/perl
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

package LJ::EmbedModule;
use strict;
use Carp qw (croak);
use LJ::Auth;
use HTML::TokeParser;
use LJ::JSON;
use TheSchwartz;

# states for a finite-state machine we use in parse()
use constant {

    # reading plain html without <object>, <embed> or <lj-embed>
    REGULAR => 1,

    # inside <object> or <embed> tag
    IMPLICIT => 2,

    # inside explicit <lj-embed> tag
    EXPLICIT => 3,

    # maximum embed width and height
    MAX_WIDTH          => 800,
    MAX_HEIGHT         => 800,
    MAX_WIDTH_PERCENT  => 100,
    MAX_HEIGHT_PERCENT => 100,
};

my %embeddable_tags = map { $_ => 1 } qw( object embed iframe );

# can optionally pass in an id of a module to change its contents
# returns module id
sub save_module {
    my ( $class, %opts ) = @_;

    my $contents = $opts{contents} || '';
    my $id       = $opts{id};
    my $journal  = $opts{journal}
        or croak "No journal passed to LJ::EmbedModule::save_module";
    my $preview = $opts{preview};

    my $need_new_id = !defined $id;

    if ( defined $id ) {
        my $old_content = $class->module_content(
            moduleid  => $id,
            journalid => LJ::want_userid($journal)
        )->{content}
            || '';
        my $new_content = $contents;

        # old content is cleaned by module_content(); new is not
        LJ::CleanHTML::clean_embed( \$new_content );

        $old_content =~ s/\s//sg;
        $new_content =~ s/\s//sg;

        $need_new_id = 1 unless $old_content eq $new_content;
    }

    # are we creating a new entry?
    if ($need_new_id) {
        $id = LJ::alloc_user_counter( $journal, 'D' )
            or die "Could not allocate embed module ID";
    }

    my $cmptext = 'C-' . LJ::text_compress($contents);

    # construct a direct link to the object if possible
    my $src_info = $class->extract_src_info(
        {
            contents => $contents,
            cmptext  => $cmptext,
            journal  => $journal,
            preview  => $preview,
            id       => $id,
        }
    );

    ## embeds for journal entry pre-post preview are stored in a special table,
    ## where new items overwrites old ones
    my $table_name = ($preview) ? 'embedcontent_preview' : 'embedcontent';
    $journal->do(
        "REPLACE INTO $table_name "
            . "(userid, moduleid, content, linktext, url) "
            . "VALUES (?, ?, ?, ?, ?)",
        undef, $journal->userid, $id, $cmptext, $src_info->{linktext}, $src_info->{url}
    );
    die $journal->errstr if $journal->err;

    # save in memcache
    my $memkey = $class->memkey( $journal->userid, $id, $preview );
    my $cref   = {
        content  => $cmptext,
        linktext => $src_info->{linktext},
        url      => $src_info->{url},
    };
    LJ::MemCache::set( $memkey, $cref );

    return $id;
}

# changes <div class="ljembed"... tags from the RTE into proper lj-embed tags
sub transform_rte_post {
    my ( $class, $txt ) = @_;
    return $txt unless $txt && $txt =~ /ljembed/i;

    # FIXME: shouldn't use regexes to parse this
    $txt =~
s/<div\s*class="ljembed"\s*(embedid="(\d+)")?\s*>(((?!<\/div>).)*)<\/div>/<site-embed id="$2">$3<\/site-embed>/ig;
    $txt =~
s/<div\s*(embedid="(\d+)")?\s*class="ljembed"\s*>(((?!<\/div>).)*)<\/div>/<site-embed id="$2">$3<\/site-embed>/ig;
    return $txt;
}

# takes a scalarref to entry text and expands lj-embed tags
# REPLACE
sub expand_entry {
    my ( $class, $journal, $entryref, %opts ) = @_;

    $$entryref =~
        s/(<(?:lj|site)\-embed[^>]+\/>)/$class->_expand_tag($journal, $1, $opts{edit}, %opts)/ge
        if $$entryref;
}

sub _expand_tag {
    my $class   = shift;
    my $journal = shift;
    my $tag     = shift;
    my $edit    = shift;
    my %opts    = @_;

    my %attrs = $tag =~ /(\w+)="?(\-?\d+)"?/g;

    return '[invalid site-embed, id is missing]' unless $attrs{id};

    if ( $opts{expand_full} ) {
        return $class->module_content( moduleid => $attrs{id}, journalid => $journal->id )
            ->{content};
    }
    elsif ($edit) {
        return
              '<site-embed '
            . join( ' ', map { "$_=\"$attrs{$_}\"" } keys %attrs ) . ">"
            . $class->module_content( moduleid => $attrs{id}, journalid => $journal->id )->{content}
            . "<\/site-embed>";
    }
    else {
        @opts{qw /width height/} = @attrs{qw/width height/};
        return $class->module_iframe_tag( $journal, $attrs{id}, %opts );
    }
}

# take a scalarref to a post, parses any lj-embed tags, saves the contents
# of the tags and replaces them with a module tag with the id.
# REPLACE
sub parse_module_embed {
    my ( $class, $journal, $postref, %opts ) = @_;

    return unless $postref && $$postref;

    return unless LJ::is_enabled('embed_module');

    # fast track out if we don't have to expand anything
    return unless $$postref =~ /(lj|site)\-embed|embed|object|iframe/i;

    # do we want to replace with the lj-embed tags or iframes?
    my $expand = $opts{expand};

    # if this is editing mode, then we want to expand embed tags for editing
    my $edit = $opts{edit};

    # previews are a special case (don't want to permanantly save to db)
    my $preview = $opts{preview};

    # deal with old-fashion calls
    if ( ( $edit || $expand ) && !$preview ) {
        return $class->expand_entry( $journal, $postref, %opts );
    }

    # ok, we can safely parse post text
    # machine state
    my $state           = REGULAR;
    my $p               = HTML::TokeParser->new($postref);
    my $newtxt          = '';
    my %embed_attrs     = ();                                # ($eid, $ewidth, $eheight);
    my $embed           = '';
    my @stack           = ();
    my $next_preview_id = 1;

    while ( my $token = $p->get_token ) {
        my ( $type, $tag, $attr ) = @$token;
        $tag = lc $tag;
        my $newstate      = undef;
        my $reconstructed = $class->reconstruct($token);

        if ( $state == REGULAR ) {
            if ( ( $tag eq 'lj-embed' || $tag eq 'site-embed' ) && $type eq 'S' && !$attr->{'/'} ) {

                # <lj-embed ...>, not self-closed
                # switch to EXPLICIT state
                $newstate = EXPLICIT;

                # save embed id, width and height if they do exist in attributes
                $embed_attrs{id}    = $attr->{id} if $attr->{id};
                $embed_attrs{width} = ( $attr->{width} > MAX_WIDTH ? MAX_WIDTH : $attr->{width} )
                    if $attr->{width};
                $embed_attrs{height} =
                    ( $attr->{height} > MAX_HEIGHT ? MAX_HEIGHT : $attr->{height} )
                    if $attr->{height};
            }
            elsif ( $embeddable_tags{$tag} && $type eq 'S' ) {

                # <object> or <embed> or <iframe>
                # switch to IMPLICIT state unless it is a self-closed tag
                unless ( $attr->{'/'} ) {
                    $newstate = IMPLICIT;

                    # tag balance
                    push @stack, $tag;
                }

               # append the tag contents to new embed buffer, so we can convert in to lj-embed later
                $embed .= $reconstructed;
            }
            else {
                # otherwise stay in REGULAR
                $newtxt .= $reconstructed;
            }
        }
        elsif ( $state == IMPLICIT ) {
            if ( $embeddable_tags{$tag} ) {
                if ( $type eq 'E' ) {

                    # </object> or </embed> or </iframe>
                    # update tag balance, but only if we have a valid balance up to this moment
                    pop @stack if $stack[-1] eq $tag;

               # switch to REGULAR if tags are balanced (stack is empty), stay in IMPLICIT otherwise
                    $newstate = REGULAR unless @stack;
                }
                elsif ( $type eq 'S' ) {

                    # <object> or <embed> or <iframe>
                    # mind the tag balance, do not update it in case of a self-closed tag
                    push @stack, $tag unless $attr->{'/'};
                }
            }

            # append to embed buffer
            $embed .= $reconstructed;

        }
        elsif ( $state == EXPLICIT ) {

            if ( ( $tag eq 'lj-embed' || $tag eq 'site-embed' ) && $type eq 'E' ) {

                # </lj-embed> - that's the end of explicit embed block, switch to REGULAR
                $newstate = REGULAR;
            }
            else {
                # continue appending contents to embed buffer
                $embed .= $reconstructed;
            }
        }
        else {
            # let's be paranoid
            die "Invalid state: '$state'";
        }

        # we decided to switch back to REGULAR and have something in embed buffer
        # so let's save buffer as an embed module and start all over again
        if ( defined $newstate && $newstate == REGULAR && $embed ) {
            $embed_attrs{id} = $class->save_module(
                id       => ( $preview ? $next_preview_id++ : $embed_attrs{id} ),
                contents => $embed,
                journal  => $journal,
                preview  => $preview,
            );

            $newtxt .= "<site-embed "
                . join( ' ',
                map { exists $embed_attrs{$_} ? "$_=\"$embed_attrs{$_}\"" : () }
                    qw / id width height / )
                . "/>";

            $embed       = '';
            %embed_attrs = ();
        }

        # switch the state if we have a new one
        $state = $newstate if defined $newstate;

    }

    # update passed text
    $$postref = $newtxt;
}

# only allow percentage as a unit
sub _extract_num_unit {
    my $num = $_[0];

    return ( $num, "" ) unless $num =~ s/%//;
    return ( $num, "%" );
}

# Returns a hash of link text, url
# Provides the fallback link text for when host API has not been contacted for title
# Currently handles: YouTube, Vimeo
sub extract_src_info {
    my ( $class, $args ) = @_;
    my ( $site, $href );

    my ( $contents, $cmptext, $journal, $id, $preview, $vid_id, $host, $linktext, $url ) =
        map { delete $args->{$_} }
        qw( contents cmptext journal id preview vid_id host linktext url );

    my $youtube_uri = qr{    # match...
        src=["']             # src=" or src='
        (?:                  # ...then, as a (non-capturing) group:
            https?:          #     either http: or https:
        )?                   # ...but matching the group is optional
        //.*youtube\.com     # //youtube.com, //www.youtube.com, etc
    }x;

    if ( $contents =~ /$youtube_uri/ ) {

        # YouTube

        my $host   = "https://www.youtube.com/";
        my $prefix = "watch?v=";

        # construct the URL and link text
        $contents =~ /.*src="[^"]*embed\/([^"]*)".*/;
        my $vid_id = $1;
        $url      = LJ::ehtml( $host . $prefix . $vid_id );
        $linktext = LJ::Lang::ml('embedmedia.youtube');

        # Fire off the worker to get the correct title
        my $sclient = LJ::theschwartz()
            or croak "Can't get TheSchwartz client";
        my $job = TheSchwartz::Job->new_from_array(
            "DW::Worker::EmbedWorker",
            {
                vid_id    => $vid_id,
                host      => 'youtube',
                preview   => $preview,
                contents  => $contents,
                cmptext   => $cmptext,
                journalid => $journal->id,
                preview   => $preview,
                id        => $id,
                linktext  => $linktext,
                url       => $url,
            }
        );
        die "Can't create job" unless $job;
        $sclient->insert($job)
            or croak "Can't queue youtube api job: $@";

    }
    elsif ( $contents =~ /src="https?:\/\/.*vimeo\.com/ ) {

        # Vimeo's default c/p embed code contains a link to the
        # video by title. If that's present, don't build a link.
        my $host = "https://vimeo.com/";

        # get the video ID
        $contents =~ /.*src="[^"]*vimeo\.com\/video\/([^"]*)".*/;
        my $vid_id = $1;

        $url      = LJ::ehtml( $host . $vid_id );
        $linktext = LJ::Lang::ml('embedmedia.vimeo');

        # Fire off the worker to get the correct title
        my $sclient = LJ::theschwartz()
            or croak "Can't get TheSchwartz client";
        my $job = TheSchwartz::Job->new_from_array(
            "DW::Worker::EmbedWorker",
            {
                vid_id    => $vid_id,
                host      => 'vimeo',
                preview   => $preview,
                contents  => $contents,
                cmptext   => $cmptext,
                journalid => $journal->id,
                preview   => $preview,
                id        => $id,
                linktext  => $linktext,
                url       => $url,
            }
        );
        die "Can't create job" unless $job;
        $sclient->insert($job)
            or croak "Can't queue vimeo api job: $@";
    }
    else {
        # Not one of our known embed types
        $linktext = "";
        $url      = "";
    }

    return { linktext => $linktext, url => $url };
}

# Used by TheSchwartz to contact external embed site APIs
sub contact_external_sites {
    my ( $class, $args ) = @_;

    my ( $vid_id, $host, $contents, $preview, $journalid, $id, $cmptext, $linktext, $url ) =
        map { delete $args->{$_} }
        qw( vid_id host contents preview journalid id cmptext linktext url );

    my ( $site, $href );
    my $journal = LJ::want_user($journalid);

    if ( $host eq 'youtube' ) {

        # Get our YouTube API variables and set up the variables
        # for constructing a YouTube URL. If we don't have an API
        # key, we shouldn't be here
        if ( $LJ::YOUTUBE_CONFIG{apikey} ) {
            my $api_url = $LJ::YOUTUBE_CONFIG{api_url};
            my $apikey  = $LJ::YOUTUBE_CONFIG{apikey};

            # put together the  GET request to get the video title
            my $ua       = LJ::get_useragent( role => 'youtube', timeout => 60 );
            my $queryurl = $api_url . $vid_id . "&key=" . $apikey . "&part=snippet";

            # Pass request to the user agent and get a response back
            my $request = HTTP::Request->new( GET => $queryurl );
            my $res     = $ua->request($request);

            # Check the outcome of the response
            if ( $res->is_success ) {
                my $obj = from_json( $res->content );
                $linktext = '"'
                    . LJ::ehtml( ${$obj}{items}[0]{snippet}{title} ) . '" ('
                    . LJ::Lang::ml('embedmedia.youtube') . ")";
            }
            else {
                # error getting video info from youtube
                return 'warn';
            }
        }
        else {
            # no API key; use generic text
            return 'fail';
        }
    }
    elsif ( $host eq 'vimeo' ) {

        # put together the  GET request to get the video title
        my $ua      = LJ::get_useragent( role => 'vimeo', timeout => 60 );
        my $api_url = "https://vimeo.com/api/v2/video/" . $vid_id . ".json";

        # Pass request to the user agent and get a response back
        my $request = HTTP::Request->new( GET => $api_url );
        my $res     = $ua->request($request);

        # Check the outcome of the response
        if ( $res->is_success ) {
            my $obj = from_json( $res->content );
            $linktext = '"'
                . LJ::ehtml( ${$obj}[0]{title} ) . '" ('
                . LJ::Lang::ml('embedmedia.vimeo') . ")";
        }
        else {
            # error getting video info from Vimeo
            return 'warn';
        }
    }
    else {
        # Not one of our known embed types
        return 'fail';
    }

    ## embeds for journal entry pre-post preview are stored in a special table,
    ## where new items overwrites old ones
    my $table_name = $preview ? 'embedcontent_preview' : 'embedcontent';
    $journal->do(
        qq{REPLACE INTO $table_name
                (userid, moduleid, content, linktext, url)
           VALUES (?, ?, ?, ?, ?)},
        undef, $journal->userid, $id, $cmptext, $linktext, $url
    );
    die $journal->errstr if $journal->err;

    # save in memcache
    my $memkey = $class->memkey( $journal->userid, $id, $preview );
    my $cref   = {
        content  => $cmptext,
        linktext => $linktext,
        url      => $url,
    };
    LJ::MemCache::set( $memkey, $cref );

}

sub module_iframe_tag {
    my ( $class, $u, $moduleid, %opts ) = @_;

    return '' unless LJ::is_enabled('embed_module');

    my $journalid = $u->userid;
    $moduleid += 0;
    my $preview = defined $opts{preview} ? $opts{preview} : '';

# parse the contents of the module and try to come up with a guess at the width and height of the content
    my $embed_details = $class->module_content(
        moduleid  => $moduleid,
        journalid => $journalid,
        preview   => $preview
    );
    my $content     = $embed_details->{content};
    my $linktext    = $embed_details->{linktext};
    my $url         = $embed_details->{url};
    my $width       = 0;
    my $height      = 0;
    my $width_unit  = "";
    my $height_unit = "";
    my $p           = HTML::TokeParser->new( \$content );
    my $embedcodes;

    # if the content only contains a whitelisted embedded video
    # then we can skip the placeholders (in some cases)
    my $no_whitelist = 0;
    my $found_embed  = 0;

    # we don't need to estimate the dimensions if they are provided in tag attributes
    unless ( $opts{width} && $opts{height} ) {
        while ( my $token = $p->get_token ) {
            my $type = $token->[0];
            my $tag  = $token->[1] ? lc $token->[1] : '';
            my $attr = $token->[2];                         # hashref

            if ( $type eq "S" ) {
                my ( $elewidth, $eleheight, $elewidth_unit, $eleheight_unit );

                if ( $attr->{width} ) {
                    ( $elewidth, $elewidth_unit ) = _extract_num_unit( $attr->{width} );
                    $elewidth += 0;
                    if ( $elewidth > $width ) {
                        $width      = $elewidth;
                        $width_unit = $elewidth_unit;
                    }
                }
                if ( $attr->{height} ) {
                    ( $eleheight, $eleheight_unit ) = _extract_num_unit( $attr->{height} );
                    $eleheight += 0;
                    if ( $eleheight > $height ) {
                        $height      = $eleheight;
                        $height_unit = $eleheight_unit;
                    }
                }

                my $flashvars = $attr->{flashvars};

                if ( $embeddable_tags{$tag} ) {
                    my $src;
                    next unless $src = $attr->{src};

                    # RIP lj-template (#1869)
                    $no_whitelist = 1;

                }
                elsif ( $tag ne 'param' ) {
                    $no_whitelist = 1;
                }
            }
        }
    }

    # use explicit values if we have them
    $width  = $opts{width}  if $opts{width};
    $height = $opts{height} if $opts{height};

    $width  ||= 480;
    $height ||= 400;

    # some dimension min/maxing
    $width  = 50 if $width < 50;
    $height = 50 if $height < 50;

    if ( $width_unit eq "%" ) {
        $width = MAX_WIDTH_PERCENT if $width > MAX_WIDTH_PERCENT;
    }
    else {
        $width = MAX_WIDTH if $width > MAX_WIDTH;
    }

    if ( $height_unit eq "%" ) {
        $height = MAX_HEIGHT_PERCENT if $height > MAX_HEIGHT_PERCENT;
    }
    else {
        $height = MAX_HEIGHT if $height > MAX_HEIGHT;
    }

    my $wrapper_style =
        "max-width: $width" . ( $width_unit || "px" ) . "; max-height: " . MAX_HEIGHT . "px;";

    # this is the ratio between
    my $padding_based_on_aspect_ratio;
    if ( $height_unit eq $width_unit ) {
        $padding_based_on_aspect_ratio = $height / $width * 100;
        $padding_based_on_aspect_ratio .= "%";
    }
    else {
        if ( $height_unit eq "%" ) {
            $padding_based_on_aspect_ratio = $height / 100 * $width;
        }
        else {
            $padding_based_on_aspect_ratio = $width / 100 * $height;
        }
        $padding_based_on_aspect_ratio .= "px";
    }
    my $ratio_style = "padding-top: $padding_based_on_aspect_ratio";

    # safari caches state of sub-resources aggressively, so give
    # each iframe a unique 'name' and 'id' attribute
    # append a random string to the name so it can't be targetted by links
    my $id          = "embed_${journalid}_$moduleid";
    my $name        = "${id}_" . LJ::make_auth_code(5);
    my $direct_link = defined $url ? '<div><a href="' . $url . '">' . $linktext . '</a></div>' : '';
    my $auth_token  = LJ::eurl(
        LJ::Auth->sessionless_auth_token(
            'embedcontent',
            moduleid  => $moduleid,
            journalid => $journalid,
            preview   => $preview,
        )
    );
    my $iframe_link =
qq{//$LJ::EMBED_MODULE_DOMAIN/?journalid=$journalid&moduleid=$moduleid&preview=$preview&auth_token=$auth_token};
    my $iframe_tag =
qq {<div class="lj_embedcontent-wrapper" style="$wrapper_style"><div class="lj_embedcontent-ratio" style="$ratio_style"><iframe src="$iframe_link"}
        . qq{ width="$width$width_unit" height="$height$height_unit" allowtransparency="true" frameborder="0"}
        . qq{ class="lj_embedcontent" id="$id" name="$name"></iframe></div></div>}
        . qq{$direct_link};

    my $remote = LJ::get_remote();
    return $iframe_tag unless $remote;
    return $iframe_tag if $opts{edit};

    # show placeholder instead of iframe?
    my $placeholder_prop = $remote->prop('opt_embedplaceholders');
    my $do_placeholder   = $placeholder_prop && $placeholder_prop ne 'N';

    # if placeholder_prop is not set, then show placeholder on a friends
    # page view UNLESS the embedded content is only one embed/object
    # tag and it's whitelisted video.
    my $r    = DW::Request->get;
    my $view = $r ? $r->note("view") : '';
    if ( !$placeholder_prop && $view eq 'friends' ) {

        # show placeholder if this is not whitelisted video
        $do_placeholder = 1 if $no_whitelist;
    }

    return $iframe_tag unless $do_placeholder;

    # placeholder
    return LJ::placeholder_link(
        placeholder_html => $iframe_tag,
        link             => $iframe_link,
        width            => $width,
        width_unit       => $width_unit,
        height           => $height,
        height           => $height_unit,
        img              => "$LJ::IMGPREFIX/videoplaceholder.png",
        url              => $url,
        linktext         => $linktext,
    );
}

sub module_content {
    my ( $class, %opts ) = @_;

    my $moduleid = $opts{moduleid};
    croak "No moduleid" unless defined $moduleid;
    $moduleid += 0;

    my $journalid = $opts{journalid} + 0
        or croak "No journalid";
    my $journal = LJ::load_userid($journalid) or die "Invalid userid $journalid";
    return { content => '' } if $journal->is_expunged;

    my $preview = $opts{preview};

    # are we displaying the content? (as opposed to processing the text for other reasons)
    my $display = $opts{display_as_content};

    # try memcache
    my $memkey = $class->memkey( $journalid, $moduleid, $preview );
    my ( $content, $linktext, $url );    # for direct linking
    my $cref = LJ::MemCache::get($memkey);
    $content  = $cref->{content};
    $linktext = $cref->{linktext};
    $url      = $cref->{url};
    my ( $dbload, $dbid );               # module id from the database

    unless ( defined $content ) {
        my $table_name = ($preview) ? 'embedcontent_preview' : 'embedcontent';
        ( $content, $dbid, $linktext, $url ) = $journal->selectrow_array(
            "SELECT "
                . "content, moduleid, linktext, url FROM $table_name "
                . "WHERE moduleid=? AND userid=?",
            undef, $moduleid, $journalid
        );
        die $journal->errstr if $journal->err;
        $dbload = 1;
    }

    $content ||= '';

    LJ::text_uncompress( \$content ) if $content =~ s/^C-//;

    # clean js out of content
    LJ::CleanHTML::clean_embed( \$content, { display_as_content => $display } );

    my $return_content;

    # if we got stuff out of database
    if ($dbload) {

        # if we didn't get a moduleid out of the database then this entry is not valid
        $return_content = {
            content  => defined $dbid ? $content : "[Invalid lj-embed id $moduleid]",
            linktext => $linktext,
            url      => $url,
        };

        # save in memcache
        LJ::MemCache::set( $memkey, $return_content );
    }
    else {
        # get rid of whitespace around the content
        $return_content = {
            content  => LJ::trim($content) || '',
            linktext => $linktext,
            url      => $url,
        };
    }

    return $return_content;
}

sub memkey {
    my ( $class, $journalid, $moduleid, $preview ) = @_;
    my $pfx = $preview ? 'embedcontpreview2' : 'embedcont2';
    return [ $journalid, "$pfx:$journalid:$moduleid" ];
}

# create a tag string from HTML::TokeParser token
sub reconstruct {
    my $class = shift;
    my $token = shift;
    my ( $type, $tag, $attr, $attord ) = @$token;
    if ( $type eq 'S' ) {
        my $txt = "<$tag";
        my $selfclose;

        # preserve order of attributes. the original order is
        # in element 4 of $token
        foreach my $name (@$attord) {
            if ( $name eq '/' ) {
                $selfclose = 1;
                next;
            }

            # FIXME: not the right way to do this.
            $attr->{$name} = LJ::no_utf8_flag( $attr->{$name} );

            $txt .= " $name=\"" . LJ::ehtml( $attr->{$name} ) . "\"";
        }
        $txt .= $selfclose ? " />" : ">";

    }
    elsif ( $type eq 'E' ) {
        return "</$tag>";
    }
    else {    # C, T, D or PI
        return $tag;
    }
}

1;

