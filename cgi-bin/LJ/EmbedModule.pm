#!/usr/bin/perl
package LJ::EmbedModule;
use strict;
use Carp qw (croak);
use Class::Autouse qw (
                       LJ::Auth
                       HTML::TokeParser
                       );

# states for a finite-state machine we use in parse()
use constant {
    # reading plain html without <object>, <embed> or <lj-embed>
    REGULAR => 1,
    # inside <object> or <embed> tag
    IMPLICIT => 2,
    # inside explicit <lj-embed> tag
    EXPLICIT => 3,
    # maximum embed width and height
    MAX_WIDTH => 800,
    MAX_HEIGHT => 800,
};

# can optionally pass in an id of a module to change its contents
# returns module id
sub save_module {
    my ($class, %opts) = @_;

    my $contents = $opts{contents} || '';
    my $id       = $opts{id};
    my $journal  = $opts{journal}
        or croak "No journal passed to LJ::EmbedModule::save_module";
    my $preview = $opts{preview};

    # are we creating a new entry?
    unless (defined $id) {
        $id = LJ::alloc_user_counter($journal, 'D')
            or die "Could not allocate embed module ID";
    }

    my $cmptext = 'C-' . LJ::text_compress($contents);

    ## embeds for preview are stored in a special table,
    ## where new items overwrites old ones
    my $table_name = ($preview) ? 'embedcontent_preview' : 'embedcontent';
    $journal->do("REPLACE INTO $table_name (userid, moduleid, content) VALUES ".
                "(?, ?, ?)", undef, $journal->userid, $id, $cmptext);
    die $journal->errstr if $journal->err;

    # save in memcache
    my $memkey = $class->memkey($journal->userid, $id, $preview);
    LJ::MemCache::set($memkey, $contents);

    return $id;
}

# changes <div class="ljembed"... tags from the RTE into proper lj-embed tags
sub transform_rte_post {
    my ($class, $txt) = @_;
    return $txt unless $txt && $txt =~ /ljembed/i;
    # ghetto... shouldn't use regexes to parse this
    $txt =~ s/<div\s*class="ljembed"\s*(embedid="(\d+)")?\s*>(((?!<\/div>).)*)<\/div>/<site-embed id="$2">$3<\/site-embed>/ig;
    $txt =~ s/<div\s*(embedid="(\d+)")?\s*class="ljembed"\s*>(((?!<\/div>).)*)<\/div>/<site-embed id="$2">$3<\/site-embed>/ig;
    return $txt;
}

# takes a scalarref to entry text and expands lj-embed tags
# REPLACE
sub expand_entry {
    my ($class, $journal, $entryref, %opts) = @_;

    $$entryref =~ s/(<(?:lj|site)\-embed[^>]+\/>)/$class->_expand_tag($journal, $1, $opts{edit}, %opts)/ge;
}

sub _expand_tag {
    my $class = shift;
    my $journal = shift;
    my $tag = shift;
    my $edit = shift;
    my %opts = @_;

    my %attrs = $tag =~ /(\w+)="?(\-?\d+)"?/g;

    return '[invalid site-embed, id is missing]' unless $attrs{id};

    if ($opts{expand_full}){
        return $class->module_content(moduleid  => $attrs{id}, journalid => $journal->id);
    } elsif ($edit) {
        return '<site-embed ' . join(' ', map {"$_=\"$attrs{$_}\""} keys %attrs) . ">" .
                 $class->module_content(moduleid  => $attrs{id}, journalid => $journal->id) .
                 "<\/site-embed>";
    } else {
        @opts{qw /width height/} = @attrs{qw/width height/};
        return $class->module_iframe_tag($journal, $attrs{id}, %opts)
    }
};


# take a scalarref to a post, parses any lj-embed tags, saves the contents
# of the tags and replaces them with a module tag with the id.
# REPLACE
sub parse_module_embed {
    my ($class, $journal, $postref, %opts) = @_;

    return unless $postref && $$postref;

    return unless LJ::is_enabled('embed_module');

    # fast track out if we don't have to expand anything
    return unless $$postref =~ /(lj|site)\-embed|embed|object/i;

    # do we want to replace with the lj-embed tags or iframes?
    my $expand = $opts{expand};

    # if this is editing mode, then we want to expand embed tags for editing
    my $edit = $opts{edit};

    # previews are a special case (don't want to permanantly save to db)
    my $preview = $opts{preview};

    # deal with old-fashion calls
    if (($edit || $expand) && ! $preview) {
        return $class->expand_entry($journal, $postref, %opts);
    }

    # ok, we can safely parse post text
    # machine state
    my $state = REGULAR;
    my $p = HTML::TokeParser->new($postref);
    my $newtxt = '';
    my %embed_attrs = (); # ($eid, $ewidth, $eheight);
    my $embed = '';
    my @stack = ();
    my $next_preview_id = 1;

    while (my $token = $p->get_token) {
        my ($type, $tag, $attr) = @$token;
        $tag = lc $tag;
        my $newstate = undef;
        my $reconstructed = $class->reconstruct($token);

        if ($state == REGULAR) {
            if (($tag eq 'lj-embed' || $tag eq 'site-embed') && $type eq 'S' && ! $attr->{'/'}) {
                # <lj-embed ...>, not self-closed
                # switch to EXPLICIT state
                $newstate = EXPLICIT;
                # save embed id, width and height if they do exist in attributes
                $embed_attrs{id} = $attr->{id} if $attr->{id};
                $embed_attrs{width} = ($attr->{width} > MAX_WIDTH ? MAX_WIDTH : $attr->{width}) if $attr->{width};
                $embed_attrs{height} = ($attr->{height} > MAX_HEIGHT ? MAX_HEIGHT : $attr->{height}) if $attr->{height};
            } elsif (($tag eq 'object' || $tag eq 'embed') && $type eq 'S') {
                # <object> or <embed>
                # switch to IMPLICIT state unless it is a self-closed tag
                unless ($attr->{'/'}) {
                    $newstate = IMPLICIT;
                    # tag balance
                    push @stack, $tag;
                }
                # append the tag contents to new embed buffer, so we can convert in to lj-embed later
                $embed .= $reconstructed;
            } else {
                # otherwise stay in REGULAR
                $newtxt .= $reconstructed;
            }
        } elsif ($state == IMPLICIT) {
            if ($tag eq 'object' || $tag eq 'embed') {
                if ($type eq 'E') {
                    # </object> or </embed>
                    # update tag balance, but only if we have a valid balance up to this moment
                    pop @stack if $stack[-1] eq $tag;
                    # switch to REGULAR if tags are balanced (stack is empty), stay in IMPLICIT otherwise
                    $newstate = REGULAR unless @stack;
                } elsif ($type eq 'S') {
                    # <object> or <embed>
                    # mind the tag balance, do not update it in case of a self-closed tag
                    push @stack, $tag unless $attr->{'/'};
                }
            }
            # append to embed buffer
            $embed .= $reconstructed;

        } elsif ($state == EXPLICIT) {

            if (($tag eq 'lj-embed' || $tag eq 'site-embed') && $type eq 'E') {
                # </lj-embed> - that's the end of explicit embed block, switch to REGULAR
                $newstate = REGULAR;
            } else {
                # continue appending contents to embed buffer
                $embed .= $reconstructed;
            }
        } else {
            # let's be paranoid
            die "Invalid state: '$state'";
        }

        # we decided to switch back to REGULAR and have something in embed buffer
        # so let's save buffer as an embed module and start all over again
        if ($newstate == REGULAR && $embed) {
            $embed_attrs{id} = $class->save_module(
                id => ($preview ? $next_preview_id++ : $embed_attrs{id}),
                contents => $embed,
                journal  => $journal,
                preview => $preview,
            );

            $newtxt .= "<site-embed " . join(' ', map { exists $embed_attrs{$_} ? "$_=\"$embed_attrs{$_}\"" : () } qw / id width height /) . "/>";

            $embed = '';
            %embed_attrs = ();
        }

        # switch the state if we have a new one
        $state = $newstate if defined $newstate;

    }

    # update passed text
    $$postref = $newtxt;
}

sub module_iframe_tag {
    my ($class, $u, $moduleid, %opts) = @_;

    return '' unless LJ::is_enabled('embed_module');

    my $journalid = $u->userid;
    $moduleid += 0;

    # parse the contents of the module and try to come up with a guess at the width and height of the content
    my $content = $class->module_content(moduleid => $moduleid, journalid => $journalid);
    my $preview = $opts{preview};
    my $width = 0;
    my $height = 0;
    my $p = HTML::TokeParser->new(\$content);
    my $embedcodes;

    # if the content only contains a whitelisted embedded video
    # then we can skip the placeholders (in some cases)
    my $no_whitelist = 0;
    my $found_embed = 0;

    # we don't need to estimate the dimensions if they are provided in tag attributes
    unless ($opts{width} && $opts{height}) {
        while (my $token = $p->get_token) {
            my $type = $token->[0];
            my $tag  = $token->[1] ? lc $token->[1] : '';
            my $attr = $token->[2];  # hashref

            if ($type eq "S") {
                my ($elewidth, $eleheight);

                if ($attr->{width}) {
                    $elewidth = $attr->{width}+0;
                    $width = $elewidth if $elewidth > $width;
                }
                if ($attr->{height}) {
                    $eleheight = $attr->{height}+0;
                    $height = $eleheight if $eleheight > $height;
                }

                my $flashvars = $attr->{flashvars};

                if ($tag eq 'object' || $tag eq 'embed') {
                    my $src;
                    next unless $src = $attr->{src};

                    # we have an object/embed tag with src, make a fake lj-template object
                    my @tags = (
                                ['S', 'lj-template', {
                                    name => 'video',
                                    (defined $elewidth     ? ( width  => $width  ) : ()),
                                    (defined $eleheight    ? ( height => $height ) : ()),
                                    (defined $flashvars ? ( flashvars => $flashvars ) : ()),
                                }],
                                [ 'T', $src, {}],
                                ['E', 'lj-template', {}],
                                );

                    $embedcodes = LJ::run_hook('expand_template_video', \@tags);

                    $found_embed = 1 if $embedcodes;
                    $found_embed &&= $embedcodes !~ /Invalid video/i;

                    $no_whitelist = !$found_embed;
                } elsif ($tag ne 'param') {
                    $no_whitelist = 1;
                }
            }
        }

        # add padding
        $width += 50 if $width;
        $height += 50 if $height;
    }

    # use explicit values if we have them
    $width = $opts{width} if $opts{width};
    $height = $opts{height} if $opts{height};

    $width ||= 480;
    $height ||= 400;

    # some dimension min/maxing
    $width = 50 if $width < 50;
    $width = MAX_WIDTH if $width > MAX_WIDTH;
    $height = 50 if $height < 50;
    $height = MAX_HEIGHT if $height > MAX_HEIGHT;

    # safari caches state of sub-resources aggressively, so give
    # each iframe a unique 'name' attribute
    my $id = qq(name="embed_${journalid}_$moduleid");

    my $auth_token = LJ::eurl(LJ::Auth->sessionless_auth_token('embedcontent', moduleid => $moduleid, journalid => $journalid, preview => $preview,));
    my $iframe_tag = qq {<iframe src="http://$LJ::EMBED_MODULE_DOMAIN/?journalid=$journalid&moduleid=$moduleid&preview=$preview&auth_token=$auth_token" } .
        qq{width="$width" height="$height" allowtransparency="true" frameborder="0" class="lj_embedcontent" $id></iframe>};

    my $remote = LJ::get_remote();
    return $iframe_tag unless $remote;
    return $iframe_tag if $opts{edit};

    # show placeholder instead of iframe?
    my $placeholder_prop = $remote->prop('opt_embedplaceholders');
    my $do_placeholder = $placeholder_prop && $placeholder_prop ne 'N';

    # if placeholder_prop is not set, then show placeholder on a friends
    # page view UNLESS the embedded content is only one embed/object
    # tag and it's whitelisted video.
    my $r = DW::Request->get;
    my $view = $r ? $r->note("view") : '';
    if (! $placeholder_prop && $view eq 'friends') {
        # show placeholder if this is not whitelisted video
        $do_placeholder = 1 if $no_whitelist;
    }

    return $iframe_tag unless $do_placeholder;

    # placeholder
    return LJ::placeholder_link(
                                placeholder_html => $iframe_tag,
                                width            => $width,
                                height           => $height,
                                img              => "$LJ::IMGPREFIX/videoplaceholder.png",
                                );
}

sub module_content {
    my ($class, %opts) = @_;

    my $moduleid  = $opts{moduleid};
    croak "No moduleid" unless defined $moduleid;
    $moduleid += 0;

    my $journalid = $opts{journalid}+0 or croak "No journalid";
    my $journal = LJ::load_userid($journalid) or die "Invalid userid $journalid";
    return '' if ($journal->is_expunged);
    my $preview = $opts{preview};

    # try memcache
    my $memkey = $class->memkey($journalid, $moduleid, $preview);
    my $content = LJ::MemCache::get($memkey);
    my ($dbload, $dbid); # module id from the database
    unless (defined $content) {
        my $table_name = ($preview) ? 'embedcontent_preview' : 'embedcontent';
        ($content, $dbid) = $journal->selectrow_array("SELECT content, moduleid FROM $table_name WHERE " .
                                                      "moduleid=? AND userid=?",
                                                      undef, $moduleid, $journalid);
        die $journal->errstr if $journal->err;
        $dbload = 1;
    }

    $content ||= '';

    LJ::text_uncompress(\$content) if $content =~ s/^C-//;

    # clean js out of content
    if ( LJ::is_enabled('embedmodule-cleancontent') ) {
        LJ::CleanHTML::clean(\$content, {
            addbreaks => 0,
            tablecheck => 0,
            mode => 'allow',
            allow => [qw(object embed)],
            deny => [qw(script iframe)],
            remove => [qw(script iframe)],
            ljcut_disable => 1,
            cleancss => 0,
            extractlinks => 0,
            noautolinks => 1,
            extractimages => 0,
            noexpandembedded => 1,
            transform_embed_nocheck => 1,
        });
    }

    # if we got stuff out of database
    if ($dbload) {
        # save in memcache
        LJ::MemCache::set($memkey, $content);

        # if we didn't get a moduleid out of the database then this entry is not valid
        return defined $dbid ? $content : "[Invalid lj-embed id $moduleid]";
    }

    # get rid of whitespace around the content
    return LJ::trim($content) || '';
}

sub memkey {
    my ($class, $journalid, $moduleid, $preview) = @_;
    my $pfx = $preview ? 'embedcontpreview' : 'embedcont';
    return [$journalid, "$pfx:$journalid:$moduleid"];
}

# create a tag string from HTML::TokeParser token
sub reconstruct {
    my $class = shift;
    my $token = shift;
    my ($type, $tag, $attr, $attord) = @$token;
    if ($type eq 'S') {
        my $txt = "<$tag";
        my $selfclose;

        # preserve order of attributes. the original order is
        # in element 4 of $token
        foreach my $name (@$attord) {
            if ($name eq '/') {
                $selfclose = 1;
                next;
            }

            # FIXME: ultra ghetto.
            $attr->{$name} = LJ::no_utf8_flag($attr->{$name});

            $txt .= " $name=\"" . LJ::ehtml($attr->{$name}) . "\"";
        }
        $txt .= $selfclose ? " />" : ">";

    } elsif ($type eq 'E') {
        return "</$tag>";
    } else { # C, T, D or PI
        return $tag;
    }
}


1;

