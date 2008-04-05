#!/usr/bin/perl
package LJ::EmbedModule;
use strict;
use Carp qw (croak);
use Class::Autouse qw (
                       LJ::Auth
                       HTML::TokeParser
                       );

# can optionally pass in an id of a module to change its contents
# returns module id
sub save_module {
    my ($class, %opts) = @_;

    my $contents = $opts{contents} || '';
    my $id       = $opts{id};
    my $journal  = $opts{journal}
        or croak "No journal passed to LJ::EmbedModule::save_module";

    # are we creating a new entry?
    unless ($id || $opts{preview}) {
        $id = LJ::alloc_user_counter($journal, 'D')
            or die "Could not allocate embed module ID";
    }

    my $cmptext = 'C-' . LJ::text_compress($contents);

    $journal->do("REPLACE INTO embedcontent (userid, moduleid, content) VALUES ".
                 "(?, ?, ?)", undef, $journal->userid, $id, $cmptext);
    die $journal->errstr if $journal->err;

    # save in memcache
    my $memkey = $class->memkey($journal->userid, $id);
    LJ::MemCache::set($memkey, $contents);

    return $id;
}

# changes <div class="ljembed"... tags from the RTE into proper lj-embed tags
sub transform_rte_post {
    my ($class, $txt) = @_;
    return $txt unless $txt && $txt =~ /ljembed/i;
    # ghetto... shouldn't use regexes to parse this
    $txt =~ s/<div\s*class="ljembed"\s*(embedid="(\d+)")?\s*>(((?!<\/div>).)*)<\/div>/<lj-embed id="$2">$3<\/lj-embed>/ig;
    $txt =~ s/<div\s*(embedid="(\d+)")?\s*class="ljembed"\s*>(((?!<\/div>).)*)<\/div>/<lj-embed id="$2">$3<\/lj-embed>/ig;
    return $txt;
}

# takes a scalarref to entry text and expands lj-embed tags
sub expand_entry {
    my ($class, $journal, $entryref, %opts) = @_;

    $opts{expand} = 1;

    $class->parse_module_embed($journal, $entryref, %opts);
}

# take a scalarref to a post, parses any lj-embed tags, saves the contents
# of the tags and replaces them with a module tag with the id.
sub parse_module_embed {
    my ($class, $journal, $postref, %opts) = @_;

    return unless $postref && $$postref;

    return if LJ::conf_test($LJ::DISABLED{embed_module});

    # fast track out if we don't have to expand anything
    return unless $$postref =~ /lj\-embed|embed|object/i;

    # do we want to replace with the lj-embed tags or iframes?
    my $expand = $opts{expand};

    # if this is editing mode, then we want to expand embed tags for editing
    my $edit = $opts{edit};

    # previews are a special case (don't want to permanantly save to db)
    my $preview = $opts{preview};

    my $p = HTML::TokeParser->new($postref);
    my $newdata = '';
    my $embedopen = 0;
    my $embedcontents = '';
    my $embedid;
    my $embed_depth;
    my $depth = 0;

  TOKEN:
    while (my $token = $p->get_token) {
        my $type = $token->[0];
        my $tag  = $token->[1];
        my $attr = $token->[2];  # hashref

        if ($type eq "S") {
            # start tag
            if (lc $tag eq "lj-embed") {
                if ($attr->{'/'}) {
                    # this is an already-existing lj-embed tag.
                    if ($expand) {
                        if (defined $attr->{id}) {
                            $newdata .= $class->module_iframe_tag($journal, $attr->{id}+0, %opts);
                        } else {
                            $newdata .= "[Error: lj-embed tag with no id]";
                        }
                     } elsif ($edit) {
                        my $content = $class->module_content(moduleid  => $attr->{id},
                                                             journalid => $journal->id);
                        $newdata .= qq{<lj-embed id="$attr->{id}">\n$content\n</lj-embed>};
                    } else {
                        $newdata .= qq(<lj-embed id="$attr->{id}" />);
                    }
                    next TOKEN;
                } else {
                    $embedopen = 1;
                    $embedcontents = '';
                    $embedid = $attr->{id};
                }

                next TOKEN;
            } else {
                my $tagcontent = "<$tag";
                my $selfclose;

                # preserve order of attributes. the original order is
                # in element 4 of $token
                foreach my $attrname (@{$token->[3]}) {
                    if ($attrname eq '/') {
                        $selfclose = 1;
                        next;
                    }

                    # FIXME: ultra ghetto.
                    $attr->{$attrname} = LJ::no_utf8_flag($attr->{$attrname});

                    $tagcontent .= " $attrname=\"" . LJ::ehtml($attr->{$attrname}) . "\"";
                }
                $tagcontent .= $selfclose ? " />" : ">";

                $depth++ unless $selfclose;

                if ($embedopen) {
                    # capture this in the embed contents cuz we're in an lj-embed tag
                    $embedcontents .= $tagcontent;
                } else {
                    # this is outside an lj-embed tag

                    if ((lc $tag eq 'object' || lc $tag eq 'embed')
                        && (! $edit && ! $expand) && ! $embed_depth) {
                        # object/embed tag and not inside a lj-embed tag

                        # wrap object/embeds in <lj-embed> tag
                        # get an id
                        $embedid = LJ::EmbedModule->save_module(
                                                                contents => '',
                                                                journal  => $journal,
                                                                preview  => $preview,
                                                                );

                        # eat this tag
                        $embedcontents .= $tagcontent;
                        $tagcontent = '';

                        unless ($selfclose) {
                            $embedopen = 1;
                            $embed_depth = $depth;
                        }
                    }

                    $newdata .= $tagcontent;
                }
            }
        } elsif ($type eq "T" || $type eq "D") {
            # tag contents
            if ($embedopen) {
                # we're in a lj-embed tag, capture the contents
                $embedcontents .= $token->[1];
            } else {
                # whatever, we don't care about this
                $newdata .= $token->[1];
            }
        } elsif ($type eq 'C') {
            # <!-- comments -->. keep these, let cleanhtml deal with it.
            $newdata .= $token->[1];
        } elsif ($type eq 'E') {
            # end tag
            if ($embed_depth && $embed_depth == $depth && (! $edit && ! $expand)
                && (lc $tag eq 'embed' || lc $tag eq 'object')) {
                # end wrapped object/embed tag
                $embedopen = 0;
                $embed_depth = 0;
                $embedcontents .= "</$tag>";

                # save embed contents
                LJ::EmbedModule->save_module(
                                             id       => $embedid,
                                             contents => $embedcontents,
                                             journal  => $journal,
                                             preview  => $preview,
                                             );
                # and then start over, in case there are multiple embeds
                $embedcontents = "";

                $newdata .= "<lj-embed id=\"$embedid\" />";
            } elsif (lc $tag eq 'lj-embed') {
                if ($embedopen) {
                    $embedopen = 0;
                    if ($embedcontents) {
                        # if this is a preview, save the module as id 0 and expand it
                        if ($preview) {
                            $embedid = 0;
                            $expand = 0;
                        }

                        # ok, we have a lj-embed tag with stuff in it.
                        # save it and replace it with a tag with the id
                        $embedid = LJ::EmbedModule->save_module(
                                                                contents => $embedcontents,
                                                                id       => $embedid,
                                                                journal  => $journal,
                                                                preview  => $preview,
                                                                );

                        if ($embedid || $preview) {
                            if ($expand) {
                                $newdata .= $class->module_iframe_tag($journal, $embedid, %opts);
                            } elsif ($edit) {
                                my $content = $class->module_content(moduleid  => $embedid,
                                                                     journalid => $journal->id);
                                $newdata .= qq{<lj-embed id="$embedid">\n$content\n</lj-embed>};
                            } else {
                                $newdata .= qq(<lj-embed id="$embedid" />);
                            }
                        }
                    }
                    $embedid = undef;
                } else {
                    $newdata .= "[Error: close lj-embed tag without open tag]";
                }
            } else {
                if ($embedopen) {
                    $embedcontents .= "</$tag>";
                } else {
                    $newdata .= "</$tag>";
                }
            }

            $depth--;
        }
    }

    $$postref = $newdata;
}

sub module_iframe_tag {
    my ($class, $u, $moduleid, %opts) = @_;

    return '' if $LJ::DISABLED{embed_module};

    my $journalid = $u->userid;
    $moduleid += 0;

    # parse the contents of the module and try to come up with a guess at the width and height of the content
    my $content = $class->module_content(moduleid => $moduleid, journalid => $journalid);
    my $width = 0;
    my $height = 0;
    my $p = HTML::TokeParser->new(\$content);
    my $embedcodes;

    # if the content only contains a whitelisted embedded video
    # then we can skip the placeholders (in some cases)
    my $no_whitelist = 0;
    my $found_embed = 0;

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

    $width ||= 480;
    $height ||= 400;

    # some dimension min/maxing
    $width = 50 if $width < 50;
    $width = 800 if $width > 800;
    $height = 50 if $height < 50;
    $height = 800 if $height > 800;

    # safari caches state of sub-resources aggressively, so give
    # each iframe a unique 'name' attribute
    my $id = qq(name="embed_${journalid}_$moduleid");

    my $auth_token = LJ::eurl(LJ::Auth->sessionless_auth_token('embedcontent', moduleid => $moduleid, journalid => $journalid));
    my $iframe_tag = qq {<iframe src="http://$LJ::EMBED_MODULE_DOMAIN/?journalid=$journalid&moduleid=$moduleid&auth_token=$auth_token" } .
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
    my $r = eval { Apache->request };
    my $view = $r ? $r->notes("view") : '';
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

    # try memcache
    my $memkey = $class->memkey($journalid, $moduleid);
    my $content = LJ::MemCache::get($memkey);

    my ($dbload, $dbid); # module id from the database
    unless (defined $content) {
        ($content, $dbid) = $journal->selectrow_array("SELECT content, moduleid FROM embedcontent WHERE " .
                                                      "moduleid=? AND userid=?",
                                                      undef, $moduleid, $journalid);
        die $journal->errstr if $journal->err;
        $dbload = 1;
    }

    $content ||= '';

    LJ::text_uncompress(\$content) if $content =~ s/^C-//;

    # clean js out of content
    unless ($LJ::DISABLED{'embedmodule-cleancontent'}) {
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
    my ($class, $journalid, $moduleid) = @_;
    return [$journalid, "embedcont:$journalid:$moduleid"];
}

1;
