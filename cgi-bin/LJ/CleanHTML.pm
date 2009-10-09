package LJ::CleanHTML;
use strict;

use URI;
use HTMLCleaner;
use LJ::CSS::Cleaner;
use HTML::TokeParser;
use LJ::EmbedModule;
use LJ::Config;

LJ::Config->load;


# attempt to mangle an email address for printing out to HTML.  this is
# kind of futile, but we try anyway.
sub mangle_email_address {
     my $email = $_[0];
     $email =~ s!^(.+)@(.+)$!<span>$1</span><span><em>&#64;</em></span>$2!;
     return $email;
}

#     LJ::CleanHTML::clean(\$u->{'bio'}, {
#        'wordlength' => 100, # maximum length of an unbroken "word"
#        'addbreaks' => 1,    # insert <br/> after newlines where appropriate
#        'tablecheck' => 1,   # make sure they aren't closing </td> that weren't opened.
#        'eat' => [qw(head title style layer iframe)],
#        'mode' => 'allow',
#        'deny' => [qw(marquee)],
#        'remove' => [qw()],
#        'maximgwidth' => 100,
#        'maximgheight' => 100,
#        'keepcomments' => 1,
#        'cuturl' => 'http://www.domain.com/full_item_view.ext',
#        'ljcut_disable' => 1, # stops the cleaner from using the lj-cut tag
#        'cleancss' => 1,
#        'extractlinks' => 1, # remove a hrefs; implies noautolinks
#        'noautolinks' => 1, # do not auto linkify
#        'extractimages' => 1, # placeholder images
#        'transform_embed_nocheck' => 1, # do not do checks on object/embed tag transforming
#        'transform_embed_wmode' => <value>, # define a wmode value for videos (usually 'transparent' is the value you want)
#        'blocked_links' => [ qr/evil\.com/, qw/spammer\.com/ ], # list of sites which URL's will be blocked
#        'blocked_link_substitute' => 'http://domain.com/error.html' # blocked links will be replaced by this URL
#        'to_external_site' => 0, # flag for when the content is going to be fed to external sites, so it can be special-cased. e.g., feeds
#     });

sub helper_preload
{
    my $p = HTML::TokeParser->new("");
    eval {$p->DESTROY(); };
}


# this treats normal characters and &entities; as single characters
# also treats UTF-8 chars as single characters if $LJ::UNICODE
my $onechar;
{
    my $utf_longchar = '[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xef][\x80-\xbf][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]';
    my $match;
    if (not $LJ::UNICODE) {
        $match = '[^&\s]|(&\#?\w{1,7};)';
    } else {
        $match = $utf_longchar . '|[^&\s\x80-\xff]|(?:&\#?\w{1,7};)';
    }
    $onechar = qr/$match/o;
}

# Some browsers, such as Internet Explorer, have decided to alllow
# certain HTML tags to be an alias of another.  This has manifested
# itself into a problem, as these aliases act in the browser in the
# same manner as the original tag, but are not treated the same by
# the HTML cleaner.
# 'alias' => 'real'
my %tag_substitute = (
                      'image' => 'img',
                      );

# In XHTML you can close a tag in the same opening tag like <br />,
# but some browsers still will interpret it as an opening only tag.
# This is a list of tags which you can actually close with a trailing
# slash and get the proper behavior from a browser.
my $slashclose_tags = qr/^(?:area|base|basefont|br|col|embed|frame|hr|img|input|isindex|link|meta|param|lj-embed|site-embed)$/i;

# <LJFUNC>
# name: LJ::CleanHTML::clean
# class: text
# des: Multi-faceted HTML parse function
# info:
# args: data, opts
# des-data: A reference to HTML to parse to output, or HTML if modified in-place.
# des-opts: An hash of options to pass to the parser.
# returns: Nothing.
# </LJFUNC>
sub clean
{
    my $data = shift;
    return undef unless defined $$data;

    my $opts = shift;

    # this has to be an empty string because otherwise we might never actually append
    # anything to it if $$data contains only invalid content
    my $newdata = '';

    # remove the auth portion of any see_request.bml links
    $$data =~ s/(see_request\.bml\S+?)auth=\w+/$1/ig;

    my $p = HTML::TokeParser->new($data);

    my $wordlength = $opts->{'wordlength'};
    my $addbreaks = $opts->{'addbreaks'};
    my $keepcomments = $opts->{'keepcomments'};
    my $mode = $opts->{'mode'};
    my $cut = $opts->{'cuturl'} || $opts->{'cutpreview'};
    my $ljcut_disable = $opts->{'ljcut_disable'};
    my $extractlinks = 0 || $opts->{'extractlinks'};
    my $noautolinks = $extractlinks || $opts->{'noautolinks'};
    my $noexpand_embedded = $opts->{'noexpandembedded'} || $opts->{'textonly'} || 0;
    my $transform_embed_nocheck = $opts->{'transform_embed_nocheck'} || 0;
    my $transform_embed_wmode = $opts->{'transform_embed_wmode'};
    my $remove_colors = $opts->{'remove_colors'} || 0;
    my $remove_sizes = $opts->{'remove_sizes'} || 0;
    my $remove_fonts = $opts->{'remove_fonts'} || 0;
    my $blocked_links = (exists $opts->{'blocked_links'}) ? $opts->{'blocked_links'} : \@LJ::BLOCKED_LINKS;
    my $blocked_link_substitute = 
        (exists $opts->{'blocked_link_substitute'}) ? $opts->{'blocked_link_substitute'} :
        ($LJ::BLOCKED_LINK_SUBSTITUTE) ? $LJ::BLOCKED_LINK_SUBSTITUTE : '#';
    my $suspend_msg = $opts->{'suspend_msg'} || 0;
    my $unsuspend_supportid = $opts->{'unsuspend_supportid'} || 0;
    my $to_external_site = $opts->{to_external_site} || 0;
    my $remove_positioning = $opts->{'remove_positioning'} || 0;

    my @canonical_urls; # extracted links
    my %action = ();
    my %remove = ();
    if (ref $opts->{'eat'} eq "ARRAY") {
        foreach (@{$opts->{'eat'}}) { $action{$_} = "eat"; }
    }
    if (ref $opts->{'allow'} eq "ARRAY") {
        foreach (@{$opts->{'allow'}}) { $action{$_} = "allow"; }
    }
    if (ref $opts->{'deny'} eq "ARRAY") {
        foreach (@{$opts->{'deny'}}) { $action{$_} = "deny"; }
    }
    if (ref $opts->{'remove'} eq "ARRAY") {
        foreach (@{$opts->{'remove'}}) { $action{$_} = "deny"; $remove{$_} = 1; }
    }

    $action{'script'} = "eat";

    # if removing sizes, remove heading tags
    if ($remove_sizes) {
        foreach my $tag (qw( h1 h2 h3 h4 h5 h6 )) {
            $action{$tag} = "deny";
            $remove{$tag} = 1;
        }
    }

    if ($opts->{'strongcleancss'}) {
        $opts->{'cleancss'} = 1;
    }

    my @attrstrip = qw();
    # cleancss means clean annoying css
    # clean_js_css means clean javascript from css
    if ($opts->{'cleancss'}) {
        push @attrstrip, 'id';
        $opts->{'clean_js_css'} = 1;
    }

    if ($opts->{'nocss'}) {
        push @attrstrip, 'style';
    }

    if (ref $opts->{'attrstrip'} eq "ARRAY") {
        foreach (@{$opts->{'attrstrip'}}) { push @attrstrip, $_; }
    }

    my %opencount = map {$_ => 0} qw(td th);
    my @tablescope = ();

    my $cutcount = 0;

    # bytes known good.  set this BEFORE we start parsing any new
    # start tag, where most evil is (because where attributes can be)
    # then, if we have to totally fail, we can cut stuff off after this.
    my $good_until = 0;

    # then, if we decide that part of an entry has invalid content, we'll
    # escape that part and stuff it in here. this lets us finish cleaning
    # the "good" part of the entry (since some tags might not get closed
    # till after $good_until bytes into the text).
    my $extra_text;
    my $total_fail = sub {
        my ( $cuturl, $tag ) = @_;
        $tag = LJ::ehtml( $tag );

        my $edata = LJ::ehtml($$data);
        $edata =~ s/\r?\n/<br \/>/g if $addbreaks;

        if ( $cuturl ) {
            $extra_text = "<b>&nbsp;(<a href=\"" . LJ::ehtml( $cuturl ) . "\">Error: Irreparable invalid markup in entry. Raw contents behind the cut.</a>&nbsp;)</b>";
        }
        else {
            $extra_text = "[<b>Error:</b> Irreparable invalid markup ('&lt;$tag&gt;') in entry.  ".
                      "Owner must fix manually.  Raw contents below.]<br /><br />" .
                      '<div style="width: 95%; overflow: auto">' . $edata . '</div>';
        }

        $extra_text = "<div class='ljparseerror'>$extra_text</div>";
    };

    my $htmlcleaner = HTMLCleaner->new(valid_stylesheet => \&LJ::valid_stylesheet_url);

    my $eating_ljuser_span = 0;  # bool, if we're eating an ljuser span
    my $ljuser_text_node   = ""; # the last text node we saw while eating ljuser tags
    my @eatuntil = ();  # if non-empty, we're eating everything.  thing at end is thing
                        # we're looking to open again or close again.

    my $capturing_during_eat;  # if we save all tokens that happen inside the eating.
    my @capture = ();  # if so, they go here

    my $form_tag = {
        input => 1,
        select => 1,
        option => 1,
    };

    my $start_capture = sub {
        next if $capturing_during_eat;

        my ($tag, $first_token, $cb) = @_;
        push @eatuntil, $tag;
        @capture = ($first_token);
        $capturing_during_eat = $cb || sub {};
    };

    my $finish_capture = sub {
        @capture = ();
        $capturing_during_eat = undef;
    };

    # we now allow users to use new tags that aren't "lj" tags.  this short
    # stub allows us to "upgrade" the tag.
    my $update_tag = sub {
        return {
            'cut'           => 'lj-cut',
            'poll'          => 'lj-poll',
            'poll-item'     => 'lj-pi',
            'poll-question' => 'lj-pq',
            'raw-code'      => 'lj-raw',
            'site-embed'    => 'lj-embed',
            'site-template' => 'lj-template',
            'user'          => 'lj',
        }->{$_[0]} || $_[0];
    };

  TOKEN:
    while (my $token = $p->get_token)
    {
        my $type = $token->[0];

        # See if this tag should be treated as an alias

        $token->[1] = $tag_substitute{$token->[1]} if defined $tag_substitute{$token->[1]} &&
            ($type eq 'S' || $type eq 'E');

        if ($type eq "S")     # start tag
        {
            my $tag  = $update_tag->( $token->[1] );
            my $attr = $token->[2];  # hashref

            $good_until = length $newdata;

            if (@eatuntil) {
                push @capture, $token if $capturing_during_eat;
                if ($tag eq $eatuntil[-1]) {
                    push @eatuntil, $tag;
                }
                next TOKEN;
            }

            if ($tag eq "lj-template" && ! $noexpand_embedded) {
                my $name = $attr->{name} || "";
                $name =~ s/-/_/g;

                my $run_template_hook = sub {
                    # can pass in tokens to override passing the hook the @capture array
                    my ($token, $override_capture) = @_;
                    my $capture = $override_capture ? [$token] : \@capture;
                    my $expanded = ($name =~ /^\w+$/) ? LJ::run_hook("expand_template_$name", $capture) : "";
                    $newdata .= $expanded || "<b>[Error: unknown template '" . LJ::ehtml($name) . "']</b>";
                };

                if ($attr->{'/'}) {
                    # template is self-closing, no need to do capture
                    $run_template_hook->($token, 1);
                } else {
                    # capture and send content to hook
                    $start_capture->("lj-template", $token, $run_template_hook);
                }
                next TOKEN;
            }

            # Capture object and embed tags to possibly transform them into something else.
            if ($tag eq "object" || $tag eq "embed") {
                if (LJ::are_hooks("transform_embed") && !$noexpand_embedded) {
                    # XHTML style open/close tags done as a singleton shouldn't actually
                    # start a capture loop, because there won't be a close tag.
                    if ($attr->{'/'}) {
                        $newdata .= LJ::run_hook("transform_embed", [$token],
                                                 nocheck => $transform_embed_nocheck, wmode => $transform_embed_wmode) || "";
                        next TOKEN;
                    }

                    $start_capture->($tag, $token, sub {
                        my $expanded = LJ::run_hook("transform_embed", \@capture,
                                                    nocheck => $transform_embed_nocheck, wmode => $transform_embed_wmode);
                        $newdata .= $expanded || "";
                    });
                    next TOKEN;
                }
            }

            if ($tag eq "span" && lc $attr->{class} eq "ljuser" && ! $noexpand_embedded) {
                $eating_ljuser_span = 1;
                $ljuser_text_node = "";
            }

            if ($eating_ljuser_span) {
                next TOKEN;
            }

            if (($tag eq "div" || $tag eq "span") && lc $attr->{class} eq "ljvideo") {
                $start_capture->($tag, $token, sub {
                    my $expanded = LJ::run_hook("expand_template_video", \@capture);
                    $newdata .= $expanded || "<b>[Error: unknown template 'video']</b>";
                });
                next TOKEN;
            }

            # do some quick checking to see if this is an email address/URL, and if so, just
            # escape it and ignore it
            if ($tag =~ m!(?:\@|://)!) {
                $newdata .= LJ::ehtml("<$tag>");
                next;
            }

            if ($form_tag->{$tag}) {
                if (! $opencount{form}) {
                    $newdata .= "&lt;$tag ... &gt;";
                    next;
                }

                if ($tag eq "input") {
                    if ($attr->{type} !~ /^\w+$/ || lc $attr->{type} eq "password") {
                        delete $attr->{type};
                    }
                }
            }

            my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
            # for tags like <name/>, pretend it's <name> and reinsert the slash later
            $slashclose = 1 if ($tag =~ s!/$!!);

            unless ($tag =~ /^\w([\w\-:_]*\w)?$/) {
                $total_fail->($cut, $tag);
                last TOKEN;
            }

            # for incorrect tags like <name/attrib=val> (note the lack of a space)
            # delete everything after 'name' to prevent a security loophole which happens
            # because IE understands them.
            $tag =~ s!/.+$!!;

            if (defined $action{$tag} and $action{$tag} eq "eat") {
                $p->unget_token($token);
                $p->get_tag("/$tag");
                next;
            }

            # try to call HTMLCleaner's element-specific cleaner on this open tag
            my $clean_res = eval {
                my $cleantag = $tag;
                $cleantag =~ s/^.*://s;
                $cleantag =~ s/[^\w]//g;
                no strict 'subs';
                my $meth = "CLEAN_$cleantag";
                my $seq   = $token->[3];  # attribute names, listref
                my $code = $htmlcleaner->can($meth)
                    or return 1;
                return $code->($htmlcleaner, $seq, $attr);
            };
            next if !$@ && !$clean_res;

            # this is so the rte converts its source to the standard ljuser html
            my $ljuser_div = $tag eq "div" && $attr->{class} eq "ljuser";
            if ($ljuser_div) {
                my $ljuser_text = $p->get_text("/b");
                $p->get_tag("/div");
                $ljuser_text =~ s/\[info\]//;
                $tag = "lj";
                $attr->{'user'} = $ljuser_text;
            }
            # stupid hack to remove the class='ljcut' from divs when we're
            # disabling them, so we account for the open div normally later.
            my $ljcut_div = $tag eq "div" && lc $attr->{class} eq "ljcut";
            if ($ljcut_div && $ljcut_disable) {
                $ljcut_div = 0;
            }

            # no cut URL, record the anchor, but then fall through
            if (0 && $ljcut_div && !$cut) {
                $cutcount++;
                $newdata .= "<a name=\"cutid$cutcount\"></a>";
                $ljcut_div = 0;
            }

            if (($tag eq "lj-cut" || $ljcut_div)) {
                next TOKEN if $ljcut_disable;
                $cutcount++;
                my $link_text = sub {
                    my $text = "Read more...";
                    if ($attr->{'text'}) {
                        $text = $attr->{'text'};
                        if ($text =~ /[^\x01-\x7f]/) {
                            $text = LJ::no_utf8_flag ( $text );
                        }
                        $text =~ s/</&lt;/g;
                        $text =~ s/>/&gt;/g;
                    }
                    return $text;
                };
                if ($cut) {
                    my $etext = $link_text->();
                    my $url = LJ::ehtml($cut);
                    $newdata .= "<div>" if $tag eq "div";
                    $newdata .= "<b>(&nbsp;<a href=\"$url#cutid$cutcount\">$etext</a>&nbsp;)</b>";
                    $newdata .= "</div>" if $tag eq "div";
                    unless ($opts->{'cutpreview'}) {
                        push @eatuntil, $tag;
                        next TOKEN;
                    }
                } else {
                    $newdata .= "<a name=\"cutid$cutcount\"></a>" unless $opts->{'textonly'};
                    if ($tag eq "div" && !$opts->{'textonly'}) {
                        $opencount{"div"}++;
                        my $etext = $link_text->();
                        $newdata .= "<div class=\"ljcut\" text=\"$etext\">";
                    }
                    next;
                }
            }
            elsif ($tag eq "style") {
                my $style = $p->get_text("/style");
                $p->get_tag("/style");
                if ( LJ::is_enabled('css_cleaner') ) {
                    my $cleaner = LJ::CSS::Cleaner->new;
                    $style = $cleaner->clean($style);
                    LJ::run_hook('css_cleaner_transform', \$style);
                    if ($LJ::IS_DEV_SERVER) {
                        $style = "/* cleaned */\n" . $style;
                    }
                }
                $newdata .= "\n<style>\n$style</style>\n";
                next;
            }
            elsif ($tag eq "lj")
            {
                # keep <lj comm> working for backwards compatibility, but pretend
                # it was <lj user> so we don't have to account for it below.
                my $user = $attr->{user} = exists $attr->{name} ? $attr->{name} :
                                           exists $attr->{user} ? $attr->{user} :
                                           exists $attr->{comm} ? $attr->{comm} : undef;

                # allow external sites
                # do not use link to an external site if site attribute is current domain
                if ( (my $site = $attr->{site}) && ($attr->{site} ne $LJ::DOMAIN) ) {

                    # try to load this user@site combination
                    if ( my $ext_u = DW::External::User->new( user => $user, site => $site ) ) {

                        # looks good, render
                        if ( $opts->{textonly} ) {
                            # FIXME: need a textonly way of identifying users better?  "user@LJ"?
                            $newdata .= $user;
                        } else {
                            $newdata .= $ext_u->ljuser_display( no_ljuser_class => $to_external_site );
                        }

                    # if we hit the else, then we know that this user doesn't appear
                    # to be valid at the requested site
                    } else {
                        $newdata .= "<b>[Bad username or site: " .
                                    LJ::ehtml( LJ::no_utf8_flag( $user ) ) . " @ " .
                                    LJ::ehtml( LJ::no_utf8_flag( $site ) ) . "]</b>";
                    }

                # failing that, no site or local site, use the local behavior
                } elsif ( length $user ) {
                    if ( my $u = LJ::load_user_or_identity( $user ) ) {
                        if ( $opts->{textonly} ) {
                            $newdata .= $u->display_name;
                        } else {
                            $newdata .= $u->ljuser_display( { no_ljuser_class => $to_external_site } );
                        }
                    } elsif ( my $username = LJ::canonical_username( $user ) ) {
                        $newdata .= LJ::ljuser( $user, { no_ljuser_class => $to_external_site } );
                    } else {
                        $user = LJ::no_utf8_flag( $user );
                        $newdata .= "<b>[Bad username or unknown identity: " . LJ::ehtml( $user ) . "]</b>";
                    }
                } else {
                    $newdata .= "<b>[Unknown site tag]</b>";
                }
            }
            elsif ($tag eq "lj-raw")
            {
                # Strip it out, but still register it as being open
                $opencount{$tag}++;
            }

            # Don't allow any tag with the "set" attribute
            elsif ($tag =~ m/:set$/) {
                next;
            }
            else
            {
                my $alt_output = 0;

                my $hash  = $token->[2];
                my $attrs = $token->[3]; # attribute names, in original order

                $slashclose = 1 if delete $hash->{'/'};

                foreach (@attrstrip) {
                    # maybe there's a better place for this?
                    next if (lc $tag eq 'lj-embed' && lc $_ eq 'id');
                    delete $hash->{$_};
                }

                if ($tag eq "form") {
                    my $action = lc($hash->{'action'});
                    my $deny = 0;
                    if ($action =~ m!^https?://?([^/]+)!) {
                        my $host = $1;
                        $deny = 1 if
                            $host =~ /[%\@\s]/ ||
                            $LJ::FORM_DOMAIN_BANNED{$host};
                    } else {
                        $deny = 1;
                    }
                    delete $hash->{'action'} if $deny;
                }

              ATTR:
                foreach my $attr (keys %$hash)
                {
                    if ($attr =~ /^(?:on|dynsrc)/) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr eq "data") {
                        delete $hash->{$attr} unless $tag eq "object";
                        next;
                    }

                    if ($attr eq "href" && $hash->{$attr} =~ /^data/) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr =~ /(?:^=)|[\x0b\x0d]/) {
                        # Cleaner attack:  <p ='>' onmouseover="javascript:alert(document/**/.cookie)" >
                        # is returned by HTML::Parser as P_tag("='" => "='") Text( onmouseover...)
                        # which leads to reconstruction of valid HTML.  Clever!
                        # detect this, and fail.
                        $total_fail->($cut, "$tag $attr");
                        last TOKEN;
                    }

                    # ignore attributes that do not fit this strict scheme
                    unless ($attr =~ /^[\w_:-]+$/) {
                        $total_fail->($cut, "$tag " . (%$hash > 1 ? "[...] " : "") . "$attr");
                        last TOKEN;
                    }

                    $hash->{$attr} =~ s/[\t\n]//g;

                    # IE ignores the null character, so strip it out
                    $hash->{$attr} =~ s/\x0//g;

                    # IE sucks:
                    my $nowhite = $hash->{$attr};
                    $nowhite =~ s/[\s\x0b]+//g;
                    if ($nowhite =~ /(?:jscript|livescript|javascript|vbscript|about):/ix) {
                        delete $hash->{$attr};
                        next;
                    }

                    if ($attr eq 'style') {
                        if ($opts->{'cleancss'}) {
                            # css2 spec, section 4.1.3
                            # position === p\osition  :(
                            # strip all slashes no matter what.
                            $hash->{style} =~ s/\\//g;

                            # and catch the obvious ones ("[" is for things like document["coo"+"kie"]
                            foreach my $css ("/*", "[", qw(absolute fixed expression eval behavior cookie document window javascript -moz-binding)) {
                                if ($hash->{style} =~ /\Q$css\E/i) {
                                    delete $hash->{style};
                                    next ATTR;
                                }
                            }
                            
                            if ($opts->{'strongcleancss'}) {
                                if ($hash->{style} =~ /-moz-|absolute|relative|outline|z-index|(?<!-)(?:top|left|right|bottom)\s*:|filter|-webkit-/io) {
                                    delete $hash->{style};
                                    next ATTR;
                                }
                            }

                            # remove specific CSS definitions
                            if ($remove_colors) {
                                $hash->{style} =~ s/(?:background-)?color:.*?(?:;|$)//gi;
                            }
                            if ($remove_sizes) {
                                $hash->{style} =~ s/font-size:.*?(?:;|$)//gi;
                            }
                            if ($remove_fonts) {
                                $hash->{style} =~ s/font-family:.*?(?:;|$)//gi;
                            }
                            if ($remove_positioning) {
                                $hash->{style} =~ s/margin.*?(?:;|$)//gi;
                                $hash->{style} =~ s/height\s*?:.*?(?:;|$)//gi;
                            }
                        }

                        if ( $opts->{'clean_js_css'} && LJ::is_enabled('css_cleaner') ) {
                            # and then run it through a harder CSS cleaner that does a full parse
                            my $css = LJ::CSS::Cleaner->new;
                            $hash->{style} = $css->clean_property($hash->{style});
                        }
                    }

                    if (($attr eq 'class' || $attr eq 'id') && $opts->{'strongcleancss'}) {
                        delete $hash->{$attr};
                        next;
		    }
		    
                    # reserve ljs_* ids for divs, etc so users can't override them to replace content
                    if ($attr eq 'id' && $hash->{$attr} =~ /^ljs_/i) {
                        delete $hash->{$attr};
                        next;
                    }

                    # remove specific attributes
                    if (($remove_colors && ($attr eq "color" || $attr eq "bgcolor" || $attr eq "fgcolor" || $attr eq "text")) ||
                        ($remove_sizes && $attr eq "size") ||
                        ($remove_fonts && $attr eq "face")) {
                        delete $hash->{$attr};
                        next ATTR;
                    }
                }
                if (exists $hash->{href}) {
                    ## links to some resources will be completely blocked
                    ## and replaced by value of 'blocked_link_substitute' param
                    if ($blocked_links) {
                        foreach my $re (@$blocked_links) {
                            if ($hash->{href} =~ $re) {
                                $hash->{href} = sprintf($blocked_link_substitute, LJ::eurl($hash->{href}));
                                last;
                            }
                        }
                    }
                    
                    unless ($hash->{href} =~ s/^(?:lj|site):(?:\/\/)?(.*)$/ExpandLJURL($1)/ei) {
                        $hash->{href} = canonical_url($hash->{href}, 1);
                    }
                }

                if ($tag eq "img")
                {
                    my $img_bad = 0;

                    if (defined $opts->{'maximgwidth'} &&
                         $hash->{width} > $opts->{maximgwidth}) { $img_bad = 1; }
                    if (defined $opts->{'maximgheight'} &&
                         $hash->{height} > $opts->{maximgheight}) { $img_bad = 1; }
                    if (! defined $hash->{width} ||
                        ! defined $hash->{height}) { $img_bad ||= $opts->{imageplaceundef}; }
                    if ($opts->{'extractimages'}) { $img_bad = 1; }

                    $hash->{src} = canonical_url($hash->{src}, 1);

                    if ($img_bad) {
                        $newdata .= "<a class=\"ljimgplaceholder\" href=\"" .
                            LJ::ehtml($hash->{'src'}) . "\">" .
                            LJ::img('placeholder') . '</a>';
                        $alt_output = 1;
                        $opencount{"img"}++;
                    }
                }

                if ($tag eq "a" && $extractlinks)
                {
                    push @canonical_urls, canonical_url($token->[2]->{href}, 1);
                    $newdata .= "<b>";
                    next;
                }

                # Through the xsl namespace in XML, it is possible to embed scripting lanaguages
                # as elements which will then be executed by the browser.  Combining this with
                # customview.cgi makes it very easy for someone to replace their entire journal
                # in S1 with a page that embeds scripting as well.  An example being an AJAX
                # six degrees tool, while cool it should not be allowed.
                #
                # Example syntax:
                # <xsl:element name="script">
                # <xsl:attribute name="type">text/javascript</xsl:attribute>
                if ($tag eq 'xsl:attribute')
                {
                    $alt_output = 1; # We'll always deal with output for this token

                    my $orig_value = $p->get_text; # Get the value of this element
                    my $value = $orig_value; # Make a copy if this turns out to be alright
                    $value =~ s/\s+//g; # Remove any whitespace

                    # See if they are trying to output scripting, if so eat the xsl:attribute
                    # container and its value
                    if ($value =~ /(javascript|vbscript)/i) {

                        # Remove the closing tag from the tree
                        $p->get_token;

                        # Remove the value itself from the tree
                        $p->get_text;

                    # No harm, no foul...Write back out the original
                    } else {
                        $newdata .= "$token->[4]$orig_value";
                    }
                }

                unless ($alt_output)
                {
                    my $allow;
                    if ($mode eq "allow") {
                        $allow = 1;
                        if (defined $action{$tag} and $action{$tag} eq "deny") { $allow = 0; }
                    } else {
                        $allow = 0;
                        if (defined $action{$tag} and $action{$tag} eq "allow") { $allow = 1; }
                    }

                    if ($allow && ! $remove{$tag})
                    {
                        if ($opts->{'tablecheck'}) {

                            $allow = 0 if

                                # can't open table elements from outside a table
                                ($tag =~ /^(?:tbody|thead|tfoot|tr|td|th|caption|colgroup|col)$/ && ! @tablescope) ||

                                # can't open td or th if not inside tr
                                ($tag =~ /^(?:td|th)$/ && ! $tablescope[-1]->{'tr'}) ||

                                # can't open a table unless inside a td or th
                                ($tag eq 'table' && @tablescope && ! grep { $tablescope[-1]->{$_} } qw(td th));
                        }

                        if ($allow) { $newdata .= "<$tag"; }
                        else { $newdata .= "&lt;$tag"; }

                        # output attributes in original order, but only those
                        # that are allowed (by still being in %$hash after cleaning)
                        foreach (@$attrs) {
                            unless (LJ::is_ascii($hash->{$_})) {
                                # FIXME: this is so ghetto.  make faster.  make generic.
                                # HTML::Parser decodes entities for us (which is good)
                                # but in Perl 5.8 also includes the "poison" SvUTF8
                                # flag on the scalar it returns, thus poisoning the
                                # rest of the content this scalar is appended with.
                                # we need to remove that poison at this point.  *sigh*
                                $hash->{$_} = LJ::no_utf8_flag($hash->{$_});
                            }
                            $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\""
                                if exists $hash->{$_};
                        }

                        # ignore the effects of slashclose unless we're dealing with a tag that can
                        # actually close itself. Otherwise, a tag like <em /> can pass through as valid
                        # even though some browsers just render it as an opening tag
                        if ($slashclose && $tag =~ $slashclose_tags) {
                            $newdata .= " /";
                            $opencount{$tag}--;
                            $tablescope[-1]->{$tag}-- if $opts->{'tablecheck'} && @tablescope;
                        }
                        if ($allow) {
                            $newdata .= ">";
                            $opencount{$tag}++;

                            # maintain current table scope
                            if ($opts->{'tablecheck'}) {

                                # open table
                                if ($tag eq 'table') {
                                    push @tablescope, {};

                                # new tag within current table
                                } elsif (@tablescope) {
                                    $tablescope[-1]->{$tag}++;
                                }
                            }

                        }
                        else { $newdata .= "&gt;"; }
                    }
                }
            }
        }
        # end tag
        elsif ($type eq "E")
        {
            my $tag = $update_tag->( $token->[1] );
            next TOKEN if $tag =~ /[^\w\-:]/;

            if (@eatuntil) {
                push @capture, $token if $capturing_during_eat;

                if ($eatuntil[-1] eq $tag) {
                    pop @eatuntil;
                    if (my $cb = $capturing_during_eat) {
                        $cb->();
                        $finish_capture->();
                    }
                    next TOKEN;
                }

                next TOKEN if @eatuntil;
            }

            if ( $eating_ljuser_span ) {
                if ( $tag eq "span" ) {
                    $eating_ljuser_span = 0;
                    
                    if ( $opts->{textonly} ) {
                        $newdata .= $ljuser_text_node;
                    } else {
                        $newdata .= LJ::ljuser( $ljuser_text_node, { no_ljuser_class => $to_external_site } );
                    }
                }

                next TOKEN;
            }

            my $allow;
            if ($tag eq "lj-raw") {
                $opencount{$tag}--;
                $tablescope[-1]->{$tag}-- if $opts->{'tablecheck'} && @tablescope;
            }
            elsif ($tag eq "lj-cut") {
                if ($opts->{'cutpreview'}) {
                    $newdata .= "<b>&lt;/lj-cut&gt;</b>";
                }
            } else {
                if ($mode eq "allow") {
                    $allow = 1;
                    if (defined $action{$tag} and $action{$tag} eq "deny") { $allow = 0; }
                } else {
                    $allow = 0;
                    if (defined $action{$tag} and $action{$tag} eq "allow") { $allow = 1; }
                }

                if ($extractlinks && $tag eq "a") {
                    if (@canonical_urls) {
                        my $url = LJ::ehtml(pop @canonical_urls);
                        $newdata .= "</b> ($url)";
                        next;
                    }
                }

                if ($allow && ! $remove{$tag})
                {

                    if ($opts->{'tablecheck'}) {

                        $allow = 0 if

                            # can't close table elements from outside a table
                            ($tag =~ /^(?:table|tbody|thead|tfoot|tr|td|th|caption|colgroup|col)$/ && ! @tablescope) ||

                            # can't close td or th unless open tr
                            ($tag =~ /^(?:td|th)$/ && ! $tablescope[-1]->{'tr'});
                    }

                    if ($allow && ! ($opts->{'noearlyclose'} && ! $opencount{$tag})) {

                        # maintain current table scope
                        if ($opts->{'tablecheck'}) {

                            # open table
                            if ($tag eq 'table') {
                                pop @tablescope;

                            # closing tag within current table
                            } elsif (@tablescope) {
                                $tablescope[-1]->{$tag}--;
                            }
                        }

                        $newdata .= "</$tag>";
                        $opencount{$tag}--;
                    } else {
                        $newdata .= "&lt;/$tag&gt;";
                    }
                }
            }
        }
        elsif ($type eq "D") {
            # remove everything past first closing tag
            $token->[1] =~ s/>.+/>/s;
            # kill any opening tag except the starting one
            $token->[1] =~ s/.<//sg;
            $newdata .= $token->[1];
        }
        elsif ($type eq "T") {
            my %url = ();
            my $urlcount = 0;

            if (@eatuntil) {
                push @capture, $token if $capturing_during_eat;
                next TOKEN;
            }

            if ($eating_ljuser_span) {
                $ljuser_text_node = $token->[1];
                next TOKEN;
            }

            my $auto_format = $addbreaks &&
                ($opencount{'table'} <= ($opencount{'td'} + $opencount{'th'})) &&
                 ! $opencount{'pre'} &&
                 ! $opencount{'lj-raw'};

            if ($auto_format && ! $noautolinks && ! $opencount{'a'} && ! $opencount{'textarea'}) {
                my $match = sub {
                    my $str = shift;
                    if ($str =~ /^(.*?)(&(#39|quot|lt|gt)(;.*)?)$/) {
                        $url{++$urlcount} = $1;
                        return "&url$urlcount;$1&urlend;$2";
                    } else {
                        $url{++$urlcount} = $str;
                        return "&url$urlcount;$str&urlend;";
                    }
                };
                $token->[1] =~ s!https?://[^\s\'\"\<\>]+[a-zA-Z0-9_/&=\-]! $match->($&); !ge;
            }

            # escape tags in text tokens.  shouldn't belong here!
            # especially because the parser returns things it's
            # confused about (broken, ill-formed HTML) as text.
            $token->[1] =~ s/</&lt;/g;
            $token->[1] =~ s/>/&gt;/g;

            # put <wbr> tags into long words, except inside <pre> and <textarea>.
            if ($wordlength && !$opencount{'pre'} && !$opencount{'textarea'}) {
                $token->[1] =~ s/\S{$wordlength,}/break_word($&,$wordlength)/eg;
            }

            # auto-format things, unless we're in a textarea, when it doesn't make sense
            if ($auto_format && !$opencount{'textarea'}) {
                $token->[1] =~ s/\r?\n/<br \/>/g;
                if (! $opencount{'a'}) {
                    $token->[1] =~ s/&url(\d+);(.*?)&urlend;/<a href=\"$url{$1}\">$2<\/a>/g;
                }
            }

            $newdata .= $token->[1];
        }
        elsif ($type eq "C") {

            # probably a malformed tag rather than a comment, so escape it
            # -- ehtml things like "<3", "<--->", "<>", etc
            # -- comments must start with <! to be eaten
            if ($token->[1] =~ /^<[^!]/) {
                $newdata .= LJ::ehtml($token->[1]);

            # by default, ditch comments
            } elsif ($keepcomments) {
                my $com = $token->[1];
                $com =~ s/^<!--\s*//;
                $com =~ s/\s*--!>$//;
                $com =~ s/<!--//;
                $com =~ s/-->//;
                $newdata .= "<!-- $com -->";
            }
        }
        elsif ($type eq "PI") {
            my $tok = $token->[1];
            $tok =~ s/</&lt;/g;
            $tok =~ s/>/&gt;/g;
            $newdata .= "<?$tok>";
        }
        else {
            $newdata .= "<!-- OTHER: " . $type . "-->\n";
        }
    } # end while

    # finish up open links if we're extracting them
    if ($extractlinks && @canonical_urls) {
        while (my $url = LJ::ehtml(pop @canonical_urls)) {
            $newdata .= "</b> ($url)";
            $opencount{'a'}--;
        }
    }

    # close any tags that were opened and not closed
    # don't close tags that don't need a closing tag -- otherwise,
    # we output the closing tags in the wrong place (eg, a </td>
    # after the <table> was closed) causing unnecessary problems
    if (ref $opts->{'autoclose'} eq "ARRAY") {
        foreach my $tag (@{$opts->{'autoclose'}}) {
            next if $tag =~ /^(?:tr|td|th|tbody|thead|tfoot|li)$/;
            if ($opencount{$tag}) {
                $newdata .= "</$tag>" x $opencount{$tag};
            }
        }
    }

    # extra-paranoid check
    1 while $newdata =~ s/<script\b//ig;

    $$data = $newdata;
    $$data .= $extra_text if $extra_text; # invalid markup error

    if ($suspend_msg) {
        my $msg = qq{<div style="color: #000; font: 12px Verdana, Arial, Sans-Serif; background-color: #ffeeee; background-repeat: repeat-x; border: 1px solid #ff9999; padding: 8px; margin: 5px auto; width: auto; text-align: left; background-image: url('$LJ::IMGPREFIX/message-error.gif');">};
        my $link_style = "color: #00c; text-decoration: underline; background: transparent; border: 0;";

        if ($unsuspend_supportid) {
            $msg .= LJ::Lang::ml('cleanhtml.suspend_msg_with_supportid', { aopts => "href='$LJ::SITEROOT/support/see_request?id=$unsuspend_supportid' style='$link_style'" });
        } else {
            $msg .= LJ::Lang::ml('cleanhtml.suspend_msg', { aopts => "href='$LJ::SITEROOT/abuse/report' style='$link_style'" });
        }

        $msg .= "</div>";

        $$data = $msg . $$data;
    }

    return 0;
}


# takes a reference to HTML and a base URL, and modifies HTML in place to use absolute URLs from the given base
sub resolve_relative_urls
{
    my ($data, $base) = @_;
    my $p = HTML::TokeParser->new($data);

    # where we look for relative URLs
    my $rel_source = {
        'a' => {
            'href' => 1,
        },
        'img' => {
            'src' => 1,
        },
    };

    my $global_did_mod = 0;
    my $base_uri = undef;  # until needed
    my $newdata = "";

  TOKEN:
    while (my $token = $p->get_token)
    {
        my $type = $token->[0];

        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];
            my $hash  = $token->[2]; # attribute hashref
            my $attrs = $token->[3]; # attribute names, in original order

            my $did_mod = 0;
            # see if this is a tag that could contain relative URLs we fix up.
            if (my $relats = $rel_source->{$tag}) {
                while (my $k = each %$relats) {
                    next unless defined $hash->{$k} && $hash->{$k} !~ /^[a-z]+:/;
                    my $rel_url = $hash->{$k};
                    $global_did_mod = $did_mod = 1;

                    $base_uri ||= URI->new($base);
                    $hash->{$k} = URI->new_abs($rel_url, $base_uri)->as_string;
                }
            }

            # if no change was necessary
            unless ($did_mod) {
                $newdata .= $token->[4];
                next TOKEN;
            }

            # otherwise, rebuild the opening tag

            # for tags like <name/>, pretend it's <name> and reinsert the slash later
            my $slashclose = 0;   # If set to 1, use XML-style empty tag marker
            $slashclose = 1 if $tag =~ s!/$!!;
            $slashclose = 1 if delete $hash->{'/'};

            # spit it back out
            $newdata .= "<$tag";
            # output attributes in original order
            foreach (@$attrs) {
                $newdata .= " $_=\"" . LJ::ehtml($hash->{$_}) . "\""
                    if exists $hash->{$_};
            }
            $newdata .= " /" if $slashclose;
            $newdata .= ">";
        }
        elsif ($type eq "E") {
            $newdata .= $token->[2];
        }
        elsif ($type eq "D") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "T") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "C") {
            $newdata .= $token->[1];
        }
        elsif ($type eq "PI") {
            $newdata .= $token->[2];
        }
    } # end while

    $$data = $newdata if $global_did_mod;
    return undef;
}

sub ExpandLJURL
{
    my @args = grep { $_ } split(/\//, $_[0]);
    my $mode = shift @args;

    my %modes =
        (
         'faq' => sub {
             my $id = shift()+0;
             if ($id) {
                 return "support/faqbrowse?faqid=$id";
             } else {
                 return "support/faq";
             }
         },
         'memories' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "memories?user=$user";
             } else {
                 return "memories";
             }
         },
         'pubkey' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "pubkey?user=$user";
             } else {
                 return "pubkey";
             }
         },
         'support' => sub {
             my $id = shift()+0;
             if ($id) {
                 return "support/see_request?id=$id";
             } else {
                 return "support/";
             }
         },
         'user' => sub {
             my $user = LJ::canonical_username(shift);
             return "" if grep { /[\"\'\<\>\n\&]/ } @_;
             return $_[0] eq 'profile' ?
                 "userinfo?user=$user" :
                 "users/$user/" . join("", map { "$_/" } @_ );
         },
         'userinfo' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "userinfo?user=$user";
             } else {
                 return "userinfo";
             }
         },
         'userpics' => sub {
             my $user = LJ::canonical_username(shift);
             if ($user) {
                 return "allpics?user=$user";
             } else {
                 return "allpics";
             }
         },
        );

    my $uri = $modes{$mode} ? $modes{$mode}->(@args) : "error:bogus-lj-url";

    return "$LJ::SITEROOT/$uri";
}

my $subject_eat = [qw[head title style layer iframe applet object param]];
my $subject_allow = [qw[a b i u em strong cite]];
my $subject_remove = [qw[bgsound embed object caption link font noscript]];
sub clean_subject
{
    my $ref = shift;
    return unless $$ref =~ /[\<\>]/;
    clean($ref, {
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => $subject_eat,
        'mode' => 'deny',
        'allow' => $subject_allow,
        'remove' => $subject_remove,
        'autoclose' => $subject_allow,
        'noearlyclose' => 1,
    });
}

## returns a pure text subject (needed in links, email headers, etc...)
my $subjectall_eat = [qw[head title style layer iframe applet object]];
sub clean_subject_all
{
    my $ref = shift;
    return unless $$ref =~ /[\<\>]/;
    clean($ref, {
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => $subjectall_eat,
        'mode' => 'deny',
        'textonly' => 1,
        'autoclose' => $subject_allow,
        'noearlyclose' => 1,
    });
}

# wrapper around clean_subject_all; this also trims the subject to the given length
sub clean_and_trim_subject {
    my $ref = shift;
    my $length = shift || 40;

    LJ::CleanHTML::clean_subject_all($ref);
    $$ref =~ s/\n.*//s;
    $$ref = LJ::text_trim($$ref, 0, $length);
}

my $event_eat = [qw[head title style layer iframe applet object xml param]];
my $event_remove = [qw[bgsound embed object link body meta noscript plaintext noframes]];

my @comment_close = qw(
    a sub sup xmp bdo q span
    b i u tt s strike big small font
    abbr acronym cite code dfn em kbd samp strong var del ins
    h1 h2 h3 h4 h5 h6 div blockquote address pre center
    ul ol li dl dt dd
    table tr td th tbody tfoot thead colgroup caption
    marquee area map form textarea blink
);
my @comment_all = (@comment_close, "img", "br", "hr", "p", "col");

my $userbio_eat = $event_eat;
my $userbio_remove = $event_remove;
my @userbio_close = @comment_close;

sub clean_event
{
    my ($ref, $opts) = @_;

    # old prototype was passing in the ref and preformatted flag.
    # now the second argument is a hashref of options, so convert it to support the old way.
    unless (ref $opts eq "HASH") {
        $opts = { 'preformatted' => $opts };
    }

    my $wordlength = defined $opts->{'wordlength'} ? $opts->{'wordlength'} : 40;

    # fast path:  no markup or URLs to linkify, and no suspend message needed
    if ($$ref !~ /\<|\>|http/ && ! $opts->{preformatted} && !$opts->{suspend_msg}) {
        $$ref =~ s/\S{$wordlength,}/break_word($&,$wordlength)/eg if $wordlength;
        $$ref =~ s/\r?\n/<br \/>/g;
        return;
    }

    # slow path: need to be run it through the cleaner
    clean($ref, {
        'linkify' => 1,
        'wordlength' => $wordlength,
        'addbreaks' => $opts->{'preformatted'} ? 0 : 1,
        'cuturl' => $opts->{'cuturl'},
        'cutpreview' => $opts->{'cutpreview'},
        'eat' => $event_eat,
        'mode' => 'allow',
        'remove' => $event_remove,
        'autoclose' => \@comment_close,
        'cleancss' => 1,
        'maximgwidth' => $opts->{'maximgwidth'},
        'maximgheight' => $opts->{'maximgheight'},
        'imageplaceundef' => $opts->{'imageplaceundef'},
        'ljcut_disable' => $opts->{'ljcut_disable'},
        'noearlyclose' => 1,
        'tablecheck' => 1,
        'extractimages' => $opts->{'extractimages'} ? 1 : 0,
        'noexpandembedded' => $opts->{'noexpandembedded'} ? 1 : 0,
        'textonly' => $opts->{'textonly'} ? 1 : 0,
        'remove_colors' => $opts->{'remove_colors'} ? 1 : 0,
        'remove_sizes' => $opts->{'remove_sizes'} ? 1 : 0,
        'remove_fonts' => $opts->{'remove_fonts'} ? 1 : 0,
        'transform_embed_nocheck' => $opts->{'transform_embed_nocheck'} ? 1 : 0,
        'transform_embed_wmode' => $opts->{'transform_embed_wmode'},
        'suspend_msg' => $opts->{'suspend_msg'} ? 1 : 0,
        'unsuspend_supportid' => $opts->{'unsuspend_supportid'},
        to_external_site => $opts->{to_external_site} ? 1 : 0,
    });
}

sub get_okay_comment_tags
{
    return @comment_all;
}


# ref: scalarref of text to clean, gets cleaned in-place
# opts:  either a hashref of opts:
#         - preformatted:  if true, don't insert breaks and auto-linkify
#         - anon_comment:  don't linkify things, and prevent <a> tags
#       or, opts can just be a boolean scalar, which implies the performatted tag
sub clean_comment
{
    my ($ref, $opts) = @_;

    unless (ref $opts) {
        $opts = { 'preformatted' => $opts };
    }

    # fast path:  no markup or URLs to linkify
    if ($$ref !~ /\<|\>|http/ && ! $opts->{preformatted}) {
        $$ref =~ s/\S{40,}/break_word($&,40)/eg;
        $$ref =~ s/\r?\n/<br \/>/g;
        return 0;
    }

    # slow path: need to be run it through the cleaner
    return clean($ref, {
        'linkify' => 1,
        'wordlength' => 40,
        'addbreaks' => $opts->{preformatted} ? 0 : 1,
        'eat' => [qw[head title style layer iframe applet object]],
        'mode' => 'deny',
        'allow' => \@comment_all,
        'autoclose' => \@comment_close,
        'cleancss' => 1,
        'strongcleancss' => 1,
        'extractlinks' => $opts->{'anon_comment'},
        'extractimages' => $opts->{'anon_comment'},
        'noearlyclose' => 1,
        'tablecheck' => 1,
        'nocss' => $opts->{'nocss'},
        'textonly' => $opts->{'textonly'} ? 1 : 0,
        'remove_positioning' => 1,
    });
}

sub clean_userbio {
    my $ref = shift;
    return undef unless ref $ref;

    clean($ref, {
        'wordlength' => 100,
        'addbreaks' => 1,
        'attrstrip' => [qw[style]],
        'mode' => 'allow',
        'noearlyclose' => 1,
        'tablecheck' => 1,
        'eat' => $userbio_eat,
        'remove' => $userbio_remove,
        'autoclose' => \@userbio_close,
        'cleancss' => 1,
    });
}

sub canonical_url {
    my $url = shift;
    my $allow_all = shift;

    # strip leading and trailing spaces
    $url =~ s/^\s*//;
    $url =~ s/\s*$//;

    return '' unless $url;

    unless ($allow_all) {
        # see what protocol they want, default to http
        my $pref = "http";
        $pref = $1 if $url =~ /^(https?|ftp|webcal):/;

        # strip out the protocol section
        $url =~ s!^.*?:/*!!;

        return '' unless $url;

        # rebuild safe url
        $url = "$pref://$url";
    }

    if ($LJ::DEBUG{'aol_http_to_ftp'}) {
        # aol blocks http referred from lj, but ftp has no referer header.
        if ($url =~ m!^http://(?:www\.)?(?:members|hometown|users)\.aol\.com/!) {
            $url =~ s!^http!ftp!;
        }
    }

    return $url;
}

sub break_word {
    my ($word, $at) = @_;
    return $word unless $at;

    $word =~ s/((?:$onechar){$at})\B/$1<wbr \/>/g;
    return $word;
}

1;
