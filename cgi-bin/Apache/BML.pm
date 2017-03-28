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
#
# This code was originally imported from:
#
#     http://code.sixapart.com/svn/bml/trunk
#
# We have copied this module locally to modify it for use in the Dreamwidth project.
# Original copyright is presumably owned by Six Apart, Ltd.  Modifications are
# copyright (C) 2008-2012 by Dreamwidth Studios, LLC.


use strict;
no warnings 'uninitialized';

package BML::Request;

use fields qw(
              env blockref lang r blockflags BlockStack
              file scratch IncludeOpen content_type clean_package package
              filechanged scheme scheme_file IncludeStack etag location
              most_recent_mod stop_flag want_last_modified cookies
              );


package Apache::BML;

use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED /;
use Apache2::Log ();
use Apache2::Request;
use Apache2::RequestRec ();
use Apache2::RequestUtil ();
use Apache2::RequestIO ();
use APR::Table;
use APR::Finfo ();
use Digest::MD5;
use File::Spec;
use DW::SiteScheme;
use LJ::Directories;

BEGIN {
    $Apache::BML::HAVE_ZLIB = eval "use Compress::Zlib (); 1;";
}

BEGIN {
    # So we get better reporiting on failures in BML files
    $^P |= 0x100;
}

# set per request:
use vars qw($cur_req);
use vars qw(%CodeBlockOpts);
# scalar hashrefs of versions below, minus the domain part:
my ($SchemeData, $SchemeFlags);

# keyed by domain:
my $ML_SCOPE;              # generally the $apache_r->uri, auto set on each request (unless overridden)
my (%SchemeData, %SchemeFlags); # domain -> scheme -> key -> scalars (data has {s} blocks expanded)

# safely global:
use vars qw(%FileModTime %LookItems);  # LookItems: file -> template -> [ data, flags ]
use vars qw(%LookParent);  # file -> parent file
use vars qw(%LookChild);   # file -> child -> 1

my (%CodeBlockMade);

use vars qw($conf_pl $conf_pl_look);  # hashref, made empty before loading a .pl conf file
my %DenyConfig;      # filename -> 1
my %FileConfig;      # filename -> hashref
my %FileLastStat;    # filename -> time we last looked at its modtime

use vars qw($base_recent_mod);

# the request we're handling (BML::get_request()).  using this way
# instead of just using BML::get_request() because when using
# Apache::FakeRequest and non-mod_perl env, I can't seem to get/set
# the value of BML::get_request()
use vars qw($r);

# regexps to match open and close tokens. (but old syntax (=..=) is deprecated)
my ($TokenOpen, $TokenClose) = ('<\?', '\?>');

tie %BML::ML, 'BML::ML';
tie %BML::COOKIE, 'BML::Cookie';

sub handler
{
    # get request and store for later
    my $apache_r = shift;
    $Apache::BML::r = $apache_r;

    # determine what file we're supposed to work with:
    my $file = Apache::BML::decide_file_and_stat($apache_r);

    # $file was stat'd by decide_file_and_stat above, so use '_'
    # FIXME: ModPerl: this is not true in ModPerl 2.0, so we are using $file.
    unless (-e $file) {
        $apache_r->log_error("File does not exist: $file");
        return NOT_FOUND;
    }

    # second time we can use _ though...
    unless (-r _) {
        $apache_r->log_error("File permissions deny access: $file");
        return FORBIDDEN;
    }

    # load now as this might go away
    my $modtime = (stat _)[9];

    # never serve these
    return FORBIDDEN if $file =~ /\b_config/;

    # create new request
    my $req = Apache::BML::initialize_cur_req($apache_r, $file);

    # setup env
    my $env = $req->{env};

    # walk up directories, looking for _config.bml files, populating env
    my $dir = $file;
    my $docroot = $apache_r->document_root(); $docroot =~ s!/$!!;
    my @dirconfs;
    my %confwant;  # file -> 1, if applicable config

    while ($dir) {
        $dir =~ s!/[^/]*$!!;
        my $conffile = "$dir/_config.bml";
        $confwant{$conffile} = 1;
        push @dirconfs, load_conffile($conffile);
        last if $dir eq $docroot;
    }

    # we now have dirconfs in order from first to apply to last.
    # but a later one may have a subconfig to override, so
    # go through those first, keeping track of which configs
    # are effective
    my %eff_config;

    foreach my $cfile (@dirconfs) {
        my $conf = $FileConfig{$cfile};
        next unless $conf;
        $eff_config{$cfile} = $conf;
        if ($conf->{'SubConfig'}) {
            foreach my $sconf (keys %confwant) {
                my $sc = $conf->{'SubConfig'}{$sconf};
                $eff_config{$cfile} = $sc if $sc;
            }
        }
    }

    foreach my $cfile (@dirconfs) {
        my $conf = $eff_config{$cfile};
        next unless $conf;
        while (my ($k,$v) = each %$conf) {
            next if exists $env->{$k} || $k eq "SubConfig";
            $env->{$k} = $v;
        }
    }

    # check if there are overrides in pnotes
    # wrapped in eval because Apache::FakeRequest doesn't have
    # pnotes support (as of 2004-04-26 at least)
    eval {
        if (my $or = $apache_r->pnotes('BMLEnvOverride')) {
            while (my ($k, $v) = each %$or) {
                $env->{$k} = $v;
            }
        }
    };

    # environment loaded at this point

    if ($env->{'AllowOldSyntax'}) {
        ($TokenOpen, $TokenClose) = ('(?:<\?|\(=)', '(?:\?>|=\))');
    } else {
        ($TokenOpen, $TokenClose) = ('<\?', '\?>');
    }

    if (exists $env->{'HOOK-force_redirect'}) {
        my $redirect_page = eval { $env->{'HOOK-force_redirect'}->($apache_r->uri); };
        if (defined $redirect_page) {
            $apache_r->headers_out->{Location} = $redirect_page;
            $Apache::BML::r = undef;  # no longer valid
            return REDIRECT;
        }
    }

    # mod_rewrite
    if ( exists $env->{'HOOK-rewrite_filename'} ){
        eval {
            my $new_file = $env->{'HOOK-rewrite_filename'}->(req => $req, env => $env);
            $file = $new_file if $new_file;
        };
    }


    # Look for an alternate file, and if it exists, load it instead of the real
    # one.
    if ( exists $env->{TryAltExtension} ) {
        my $ext = $env->{TryAltExtension};

        # Trim a leading dot on the extension to allow '.lj' or 'lj'
        $ext =~ s{^\.}{};

        # If the file already has an extension, put the alt extension between it
        # and the rest of the filename like Apache's content-negotiation.
        if ( $file =~ m{(\.\S+)$} ) {
            my $newfile = $file;
            substr( $newfile, -(length $1), 0 ) = ".$ext";
            if ( -e $newfile ) {
                $modtime = (stat _)[9];
                $file = $newfile;
            }
        }

        elsif ( -e "$file.$ext" ) {
            $modtime = (stat _)[9];
            $file = "$file.$ext";
        }
    }

    # Read the source of the file
    unless (open F, $file) {
        $apache_r->log_error("Couldn't open $file for reading: $!");
        $Apache::BML::r = undef;  # no longer valid
        return SERVER_ERROR;
    }

    my $bmlsource;
    { local $/ = undef; $bmlsource = <F>; }
    close F;

    # consider the file's mod time
    note_mod_time($req, $modtime);

    # and all the config files:
    note_mod_time($req, $Apache::BML::base_recent_mod);

    # if the file changed since we last looked at it, note that
    if (!defined $FileModTime{$file} || $modtime > $FileModTime{$file}) {
        $FileModTime{$file} = $modtime;
        $req->{'filechanged'} = 1;
    }

    # setup cookies
    *BMLCodeBlock::COOKIE = *BML::COOKIE;
    BML::reset_cookies();

    # tied interface to BML::ml();
    *BMLCodeBlock::ML = *BML::ML;

    # parse in data
    parse_inputs( $apache_r );

    %BMLCodeBlock::GET_POTENTIAL_XSS = ();
    if ($env->{MildXSSProtection}) {
        foreach my $k (keys %BMLCodeBlock::GET) {
            next unless $BMLCodeBlock::GET{$k} =~ /\<|\%3C/i;
            $BMLCodeBlock::GET_POTENTIAL_XSS{$k} = $BMLCodeBlock::GET{$k};
            delete $BMLCodeBlock::GET{$k};
            delete $BMLCodeBlock::FORM{$k};
        }
    }

    if ($env->{'HOOK-startup'}) {
        eval {
            $env->{'HOOK-startup'}->();
        };
        return report_error($apache_r, "<b>Error running startup hook:</b><br />\n$@")
            if $@;
    }

    # allow a hook to specify extra perl to be used to bootstrap code
    # blocks... this will be cached here so the hook doesn't need to run
    # at every code block compilation
    $BML::CODE_INIT_PERL = "";
    if ($env->{'HOOK-codeblock_init_perl'}) {
        $BML::CODE_INIT_PERL = eval { $env->{'HOOK-codeblock_init_perl'}->(); };
        return report_error($apache_r, "<b>Error running codeblock_init_perl hook:</b><br />\n$@") if $@;
    }

    my $scheme = $apache_r->notes->{'bml_use_scheme'} ||
        $env->{'ForceScheme'} ||
        $BMLCodeBlock::GET{skin} ||
        $BMLCodeBlock::GET{'usescheme'} ||
        $BML::COOKIE{'BMLschemepref'};

    if (exists $env->{'HOOK-alt_default_scheme'}) {
        $scheme ||= eval { $env->{'HOOK-alt_default_scheme'}->($env); };
    }

    my $default_scheme_override = undef;
    if ($env->{'HOOK-default_scheme_override'}) {
        $default_scheme_override = eval {
            $env->{'HOOK-default_scheme_override'}->( $scheme || DW::SiteScheme->default );
        };
        return report_error($apache_r, "<b>Error running scheme override hook:</b><br />\n$@") if $@;
    }

    $scheme ||= $default_scheme_override || DW::SiteScheme->default;

    # now we've made the decision about what scheme to use
    # -- does a hook want to translate this into another scheme?
    if ($env->{'HOOK-scheme_translation'}) {
        my $newscheme = eval {
            $env->{'HOOK-scheme_translation'}->($scheme);
        };
        $scheme = $newscheme if $newscheme;
    }

    unless (BML::set_scheme($scheme)) {
        $scheme = $env->{'ForceScheme'} ||
            DW::SiteScheme->default;
        BML::set_scheme($scheme);
    }

    my $uri = $apache_r->uri;
    my $path_info = $apache_r->path_info;
    my $lang_scope = $uri;
    $lang_scope =~ s/$path_info$//;
    BML::set_language_scope($lang_scope);
    my $lang = BML::decide_language();
    BML::set_language($lang);

    # print on the HTTP header
    my $html = $env->{'_error'};

    if ($env->{'HOOK-before_decode'}) {
        eval { $env->{'HOOK-before_decode'}->(); };
        return report_error($apache_r, "<b>Error running before_decode hook:</b><br />\n$@") if $@;
    }

    bml_decode($req, \$bmlsource, \$html, { DO_CODE => $env->{'AllowCode'} })
        unless $html;

    # force out any cookies we have set
    BML::send_cookies($req);

    $apache_r->pool->cleanup_register(\&reset_codeblock) if $req->{'clean_package'};

    # internal redirect, if set previously
    if ( $apache_r->notes->{internal_redir} ) {
        my $int_redir = DW::Routing->call( uri => $apache_r->notes->{internal_redir} );
        if ( defined $int_redir ) {
            # we got a match; remove the internal_redir setting, clear the
            # request cache, and return DECLINED.
            $apache_r->notes->{internal_redir} = undef;
            LJ::start_request();
            return DECLINED;
        }
    }

    # redirect, if set previously
    if ($req->{'location'}) {
        $apache_r->headers_out->{Location} = $req->{'location'};
        $Apache::BML::r = undef;  # no longer valid
        return REDIRECT;
    }

    # see if we can save some bandwidth (though we already killed a bunch of CPU)
    my $etag;
    if (exists $req->{'etag'}) {
        $etag = $req->{'etag'} if defined $req->{'etag'};
    } else {
        $etag = Digest::MD5::md5_hex($html);
    }
    $etag = '"' . $etag . '"' if defined $etag;

    my $ifnonematch = $apache_r->headers_in->{"If-None-Match"};
    if (defined $ifnonematch && defined $etag && $etag eq $ifnonematch) {
        $Apache::BML::r = undef;  # no longer valid
        return HTTP_NOT_MODIFIED;
    }

    my $rootlang = substr($req->{'lang'}, 0, 2);
    unless ($env->{'NoHeaders'}) {
        eval {
            # this will fail while using Apache::FakeRequest, but that's okay.
            $apache_r->content_languages([ $rootlang ]);
        };
    }

    my $modtime_http = modified_time($req);

    my $content_type = $req->{'content_type'} ||
        $env->{'DefaultContentType'} ||
        "text/html";

    unless ($env->{'NoHeaders'})
    {
        my $ims = $apache_r->headers_in->{"If-Modified-Since"};
        if ($ims && ! $env->{'NoCache'} &&
            $ims eq $modtime_http)
        {
            $Apache::BML::r = undef;  # no longer valid
            return HTTP_NOT_MODIFIED;
        }

        $apache_r->content_type($content_type);

        if ($env->{'NoCache'}) {
            $apache_r->headers_out->{"Cache-Control"} = "no-cache";
            $apache_r->no_cache(1);
        }

        $apache_r->headers_out->{"Last-Modified"} = $modtime_http
            if $env->{'Static'} || $req->{'want_last_modified'};

        $apache_r->headers_out->{"Cache-Control"} = "private, proxy-revalidate";
        $apache_r->headers_out->{"ETag"} = $etag if defined $etag;

        # gzip encoding
        my $do_gzip = $env->{'DoGZIP'} && $Apache::BML::HAVE_ZLIB;
        $do_gzip = 0 if $do_gzip && $content_type !~ m!^text/html!;
        $do_gzip = 0 if $do_gzip && $apache_r->headers_in->{"Accept-Encoding"} !~ /gzip/;
        my $length = length($html);
        $do_gzip = 0 if $length < 500;
        if ($do_gzip) {
            my $pre_len = $length;
            $apache_r->notes->{"bytes_pregzip"} = $pre_len;
            $html = Compress::Zlib::memGzip($html);
            $length = length($html);
            $apache_r->headers_out->{'Content-Encoding'} = 'gzip';
            $apache_r->headers_out->{'Vary'} = 'Accept-Encoding';
        }
        $apache_r->headers_out->{'Content-length'} = $length;

        # FIXME: removed in ModPerl 2.0 is that okay?  replacement function?
        #$apache_r->send_http_header();
    }

    $apache_r->print($html) unless $env->{'NoContent'} || $apache_r->header_only;

    $Apache::BML::r = undef;  # no longer valid
    return OK;
}

sub decide_file_and_stat
{
    my $apache_r = shift;
    my $file;
    if (ref $apache_r eq "Apache::FakeRequest") {
        # for testing.  FakeRequest's 'notes' method is busted, always returning
        # true.
        $file = $apache_r->filename;
        stat($file);
    } elsif ($file = $apache_r->notes->{"bml_filename"}) {
        # when another handler needs to invoke BML directly
        stat($file);
    } else {
        # normal case - $apache_r->filename is already stat'd
        $file = $apache_r->filename;
        $apache_r->finfo;
    }

    return $file;
}

sub is_initialized
{
    return $Apache::BML::cur_req ? 1 : 0;
}

sub initialize_cur_req
{
    my $apache_r = shift;
    my $file = shift;

    my $req = $cur_req = fields::new('BML::Request');
    $req->{file} = $file || Apache::BML::decide_file_and_stat($apache_r);
    $req->{r}    = $apache_r;
    $req->{BlockStack} = [""];
    $req->{scratch}    = {};  # _CODE blocks can play
    $req->{cookies} = {};
    $req->{env} = {};

    return $req;
}

sub clear_cur_req {
    return $Apache::BML::cur_req = undef;
}

sub report_error
{
    my $apache_r = shift;
    my $err = shift;

    $apache_r->content_type("text/html");
    # FIXME: ModPerl: doesn't seem to be used/required anymore
    #$apache_r->send_http_header();
    $apache_r->print($err);

    return OK;  # TODO: something else?
}

sub file_dontcheck
{
    my $file = shift;
    my $now = time;
    return 1 if $FileLastStat{$file} > $now - 10;
    my $realmod = (stat($file))[9];
    $FileLastStat{$file} = $now;
    return 1 if $FileModTime{$file} && $realmod == $FileModTime{$file};
    $FileModTime{$file} = $realmod;
    return 1 if ! $realmod;
    return 0;
}

sub load_conffile
{
    my ($ffile) = @_;  # abs file to load
    die "can't have dollar signs in filenames" if index($ffile, '$') != -1;
    die "not absolute path" unless File::Spec->file_name_is_absolute($ffile);
    my ($volume,$dirs,$file) = File::Spec->splitpath($ffile);

    # see which configs are denied
    my $apache_r = $Apache::BML::r;
    if ($apache_r->dir_config("BML_denyconfig") && ! %DenyConfig) {
        my $docroot = $apache_r->document_root();
        my $deny = $apache_r->dir_config("BML_denyconfig");
        $deny =~ s/^\s+//; $deny =~ s/\s+$//;
        my @denydir = split(/\s*\,\s*/, $deny);
        foreach $deny (@denydir) {
            $deny = dir_rel2abs($docroot, $deny);
            $deny =~ s!/$!!;
            $DenyConfig{"$deny/_config.bml"} = 1;
        }
    }

    return () if $DenyConfig{$ffile};

    my $conf;
    if (file_dontcheck($ffile) && ($FileConfig{$ffile} || ! $FileModTime{$ffile})) {
        return () unless $FileModTime{$ffile};  # file doesn't exist
        $conf = $FileConfig{$ffile};
    }

    if (!$conf && $file =~ /\.p[lm]$/) {
        return () unless -e $ffile;
        my $conf = $conf_pl = {};
        do $ffile;
        undef $conf_pl;
        $FileConfig{$ffile} = $conf;
        return ($ffile);
    }

    unless ($conf) {
        unless (open (C, $ffile)) {
            Apache->log_error("Can't read config file: $file")
                if -e $file;
            return ();
        }

        my $curr_sub;
        $conf = {};
        my $sconf = $conf;

        my $save_config = sub {
            return unless %$sconf;

            # expand $env vars and make paths absolute
            foreach my $k (qw(LookRoot IncludePath)) {
                next unless exists $sconf->{$k};
                $sconf->{$k} =~ s/\$LJHOME/$LJ::HOME/g;
                $sconf->{$k} =~ s/\$(\w+)/$ENV{$1}/g;
                $sconf->{$k} = dir_rel2abs($dirs, $sconf->{$k});
            }

            # same as above, but these can be multi-valued, and go into an arrayref
            foreach my $k (qw(ExtraConfig)) {
                next unless exists $sconf->{$k};
                $sconf->{$k} =~ s/\$(\w+)/$1 eq "HTTP_HOST" ? clean_http_host() : $ENV{$1}/eg;
                $sconf->{$k} = [ map { LJ::resolve_file( $_ ) } grep { $_ }
                                 split(/\s*,\s*/, $sconf->{$k}) ];
            }

            # if child config, copy it to parent config
            return unless $curr_sub;
            foreach my $subdir (split(/\s*,\s*/, $curr_sub)) {
                my $subfile = dir_rel2abs($dirs, "$subdir/_config.bml");
                $conf->{'SubConfig'}->{$subfile} = $sconf;
            }
        };


        while (<C>) {
            chomp;
            s/\#.*//;
            next unless /(\S+)\s+(.+?)\s*$/;
            my ($k, $v) = ($1, $2);
            if ($k eq "SubConfig:") {
                $save_config->();
                $curr_sub = $v;
                $sconf = {%$sconf};  # clone config seen so far.  SubConfig inherits those.
                next;
            }

            # automatically arrayref-ify certain options
            $v = [ split(/\s*,\s*/, $v) ]
                if $k eq "CookieDomain" && index($v,',') != -1;

            $sconf->{$k} = $v;
        }
        close C;
        $save_config->();
        $FileConfig{$ffile} = $conf;
    }

    my @files = ($ffile);
    foreach my $cfile (@{$conf->{'ExtraConfig'} || []}) {
        unshift @files, load_conffile($cfile);
    }

    return @files;
}

sub compile
{
    eval $_[0];
}

sub reset_codeblock
{
    return undef unless Apache::BML::is_initialized();

    my BML::Request $req = $Apache::BML::cur_req;
    my $to_clean = $req->{clean_package};

    no strict;
    local $^W = 0;
    my $package = "main::${to_clean}::";
    *stab = *{"main::"};
    while ($package =~ /(\w+?::)/g)
    {
        *stab = ${stab}{$1};
    }
    while (my ($key,$val) = each(%stab))
    {
        return if $DB::signal;
        deleteglob ($key, $val, undef, $req->{file});
    }
}

sub deleteglob
{
    no strict;
    return if $DB::signal;
    my ($key, $val, $all, $file) = @_;
    local(*entry) = $val;
    my $fileno;
    if ($key !~ /^_</ and defined $entry)
    {
        undef $entry;
    }
    if ($key !~ /^_</ and @entry)
    {
        undef @entry;
    }

    if ( $key eq "ML" ||
        ( $key ne "main::" && $key ne "DB::" && scalar(keys %entry)
            && $key !~ /::$/
            && $key !~ /^_</ && $val ne "*BML::COOKIE" ) )
    {
        undef %entry;
    }
    if (defined ($fileno = fileno(*entry))) {
        # do nothing to filehandles?
    }
    if ($all) {
        if (defined &entry) {
                # do nothing to subs?
        }
    }
}

# $type - "THINGER" in the case of <?thinger Whatever thinger?>
# $data - "Whatever" in the case of <?thinger Whatever thinger?>
# $option_ref - hash ref to %BMLEnv
sub bml_block
{
    my BML::Request $req = shift;
    my ($type, $data, $option_ref, $elhash) = @_;
    my $realtype = $type;
    my $previous_block = $req->{'BlockStack'}->[-1];
    my $env = $req->{'env'};

    # Bail out if we're over 200 frames deep
    # :TODO: Make the max depth configurable?
    if ( @{$req->{BlockStack}} > 200 ) {
        my $stackSlice = join " -> ", @{$req->{BlockStack}}[0..10];
        return "<b>[Error: Too deep recursion: $stackSlice]</b>";
    }

    if (exists $req->{'blockref'}->{"$type/FOLLOW_${previous_block}"}) {
        $realtype = "$type/FOLLOW_${previous_block}";
    }

    my $blockflags = $req->{'blockflags'}->{$realtype};

    # executable perl code blocks
    if ($type eq "_CODE")
    {
        return inline_error("_CODE block failed to execute by permission settings")
            unless $option_ref->{'DO_CODE'};

        %CodeBlockOpts = ();

        # this will be their package
        my $md5_package = "BMLCodeBlock::" . Digest::MD5::md5_hex($req->{'file'});

        # this will be their handler name
        my $md5_handler = "handler_" . Digest::MD5::md5_hex($data);

        # we cache code blocks (of templates) also in each *.bml file's
        # package, since we're too lazy (at the moment) to trace back
        # each code block to its declaration file.
        my $unique_key = $md5_package . $md5_handler;

        my $need_compile = ! $CodeBlockMade{$unique_key};

        if ($need_compile) {
            # compile (which just calls eval) then check for errors.
            # we put it off to that sub, historically, to make it
            # show up separate in profiling, but now we cache
            # everything, so it pretty much never shows up.
            compile(join('',
                         "# line 1 \"$req->{'file'}\"\n",
                         'package ',
                         $md5_package,
                         ';',
                         "no strict;",
                         'use vars qw(%ML %COOKIE %POST %GET %FORM);',
                         "*ML = *BML::ML;",
                         "*COOKIE = *BML::COOKIE;",
                         "*GET = *BMLCodeBlock::GET;",
                         "*POST = *BMLCodeBlock::POST;",
                         "*FORM = *BMLCodeBlock::FORM;",
                         $BML::CODE_INIT_PERL, # extra from hook
                         'sub ', $md5_handler, ' {',
                         $data,
                         "\n}"));

            return handle_code_error($env, $@) if $@;

            $CodeBlockMade{$unique_key} = 1;
        }

        my $cv = \&{"${md5_package}::${md5_handler}"};
        $req->{clean_package} = $md5_package;
        my $ret = eval { $cv->($req, $req->{'scratch'}, $elhash || {}) };
        return handle_code_error($env, $@) if $@;

        # don't call bml_decode if BML::noparse() told us not to, there's
        # no data, or it looks like there are no BML tags
        return $ret if $CodeBlockOpts{'raw'} or $ret eq "" or
            (index($ret, "<?") == -1 && index($ret, "(=") == -1);

        my $newhtml;
        bml_decode($req, \$ret, \$newhtml, {});  # no opts on purpose: _CODE can't return _CODE
        return $newhtml;
    }

    # trim off space from both sides of text data
    $data =~ s/^\s*(.*?)\s*$/$1/s;

    # load in the properties defined in the data
    my %element = ();
    my @elements = ();
    if (index($blockflags, 'F') != -1)
    {
        load_elements(\%element, $data, { 'declorder' => \@elements });
    }
    elsif (index($blockflags, 'P') != -1)
    {
        my @itm = split(/\s*\|\s*/, $data);
        my $ct = 0;
        foreach (@itm) {
            $ct++;
            $element{"DATA$ct"} = $_;
            push @elements, "DATA$ct";
        }
    }
    else
    {
        # single argument block (goes into DATA element)
        $element{'DATA'} = $data;
        push @elements, 'DATA';
    }

    # check built-in block types (those beginning with an underscore)
    if (rindex($type, '_', 0) == 0) {

        # multi-linguality stuff
        if ($type eq "_ML")
        {
            my $code = $data;
            return $code
                if $req->{'lang'} eq 'debug';
            my $getter = $req->{'env'}->{'HOOK-ml_getter'};
            return "[ml_getter not defined]" unless $getter;
            $code = $req->{'r'}->uri . $code
                if rindex($code, '.', 0) == 0;
            return $getter->($req->{'lang'}, $code);
        }

        # an _INFO block contains special internal information, like which
        # look files to include
        if ($type eq "_INFO")
        {
            if ($element{'PACKAGE'}) { $req->{'package'} = $element{'PACKAGE'}; }
            if ($element{'NOCACHE'}) { $req->{'env'}->{'NoCache'} = 1; }
            if ($element{'STATIC'}) { $req->{'env'}->{'Static'} = 1; }
            if ($element{'NOHEADERS'}) { $req->{'env'}->{'NoHeaders'} = 1; }
            if ($element{'NOCONTENT'}) { $req->{'env'}->{'NoContent'} = 1; }
            if ($element{'LOCALBLOCKS'} && $req->{'env'}->{'AllowCode'}) {
                my (%localblock, %localflags);
                load_elements(\%localblock, $element{'LOCALBLOCKS'});
                # look for template types
                foreach my $k (keys %localblock) {
                    if ($localblock{$k} =~ s/^\{([A-Za-z]+)\}//) {
                        $localflags{$k} = $1;
                    }
                }
                my @expandconstants;
                foreach my $k (keys %localblock) {
                    $req->{'blockref'}->{$k} = \$localblock{$k};
                    $req->{'blockflags'}->{$k} = $localflags{$k};
                    if (index($localflags{$k}, 's') != -1) { push @expandconstants, $k; }
                }
                foreach my $k (@expandconstants) {
                    $localblock{$k} =~ s/$TokenOpen([a-zA-Z0-9\_]+?)$TokenClose/${$req->{'blockref'}->{uc($1)} || \""}/og;
                }
            }
            return "";
        }

        if ($type eq "_INCLUDE")
        {
            my $code = 0;
            $code = 1 if ($element{'CODE'});
            foreach my $sec (qw(CODE BML)) {
                next unless $element{$sec};
                if ($req->{'IncludeStack'} && ! $req->{'IncludeStack'}->[-1]->{$sec}) {
                    return inline_error("Sub-include can't turn on $sec if parent include's $sec was off");
                }
            }
            unless ($element{'FILE'} =~ /^[a-zA-Z0-9-_\.]{1,255}$/) {
                return inline_error("Invalid characters in include file name: $element{'FILE'} (code=$code)");
            }

            if ($req->{'IncludeOpen'}->{$element{'FILE'}}++) {
                return inline_error("Recursion detected in includes");
            }
            push @{$req->{'IncludeStack'}}, \%element;
            my $isource = "";
            my $file = $element{'FILE'};

            # first check if we have a DB-edit hook
            my $hook = $req->{'env'}->{'HOOK-include_getter'};
            unless ($hook && $hook->($file, \$isource)) {
                $file = $req->{'env'}->{'IncludePath'} . "/" . $file;
                open (INCFILE, $file) || return inline_error("Could not open include file.");
                { local $/ = undef; $isource = <INCFILE>; }
                close INCFILE;
            }

            if ($element{'BML'}) {
                my $newhtml;
                bml_decode($req, \$isource, \$newhtml, { DO_CODE => $code });
                $isource = $newhtml;
            }
            $req->{'IncludeOpen'}->{$element{'FILE'}}--;
            pop @{$req->{'IncludeStack'}};
            return $isource;
        }

        if ($type eq "_COMMENT" || $type eq "_C") {
            return "";
        }

        if ($type eq "_EH") {
            return BML::ehtml($element{'DATA'});
        }

        if ($type eq "_EB") {
            return BML::ebml($element{'DATA'});
        }

        if ($type eq "_EU") {
            return BML::eurl($element{'DATA'});
        }

        if ($type eq "_EA") {
            return BML::eall($element{'DATA'});
        }

        return inline_error("Unknown core element '$type'");
    }

    $req->{'BlockStack'}->[-1] = $type;

    # traditional BML Block decoding ... properties of data get inserted
    # into the look definition; then get BMLitized again
    return inline_error("Undefined custom element '$type'")
        unless defined $req->{'blockref'}->{$realtype};

    my $preparsed = (index($blockflags, 'p') != -1);

    if ($preparsed) {
        ## does block request pre-parsing of elements?
        ## this is required for blocks with _CODE and AllowCode set to 0
        foreach my $k (@elements) {
            my $decoded;
            bml_decode($req, \$element{$k}, \$decoded, $option_ref, \%element);
            $element{$k} = $decoded;
        }
    }

    # get the block content to work on; we do this here because it may be a coderef
    # from BML::register_block() in which case we want to execute it before we try
    # to run it through the BML parsers
    my $content = ${$req->{'blockref'}->{$realtype}};
    if (ref $content) {
        return inline_error("Unknown type of element '$type'")
            unless ref $content eq 'CODE';
        $content = $content->(\%element);
        return inline_error("Coderef '$type' returned undef/not a string")
            unless defined $content && ! ref $content;
    }

    # template has no variables or BML tags:
    return $content if index($blockflags, 'S') != -1;

    my $expanded;
    if ($preparsed) {
        $expanded = $content;
    } else {
        $expanded = parsein($content, \%element);
    }

    # {R} flag wants variable interpolation, but no expansion:
    unless (index($blockflags, 'R') != -1)
    {
        my $out;
        push @{$req->{'BlockStack'}}, "";
        my $opts = { %{$option_ref} };
        if ($preparsed) {
            $opts->{'DO_CODE'} = $req->{'env'}->{'AllowTemplateCode'};
        }

        unless (index($expanded, "<?") == -1 && index($expanded, "(=") == -1) {
            bml_decode($req, \$expanded, \$out, $opts, \%element);
            $expanded = $out;
        }

        pop @{$req->{'BlockStack'}};
    }

    # t == no final expand, required in tt-runner
    return $expanded if (index($blockflags, 't') != -1);

    $expanded = parsein($expanded, \%element) if $preparsed;
    return $expanded;
}

######## bml_decode
#
# turns BML source into expanded HTML source
#
#   $inref    scalar reference to BML source.  $$inref gets destroyed.
#   $outref   scalar reference to where output is appended.
#   $opts     security flags
#   $elhash   optional elements hashref

use vars qw(%re_decode);
sub bml_decode
{
    my BML::Request $req = shift;
    my ($inref, $outref, $opts, $elhash) = @_;

    my $block = undef;    # what <?block ... block?> are we in?
    my $data = undef;     # what is inside the current block?
    my $depth = 0;     # how many blocks we are deep of the *SAME* type.
    my $re;            # active regular expression for finding closing tag

    pos($$inref) = 0;

  EAT:
    for (;;)
    {
        # currently not in a BML tag... looking for one!
        if (! defined $block) {
            if ($$inref =~ m/
                 \G                             # start where last match left off
                (?>                             # independent regexp:  won't backtrack the .*? below.
                 (.*?)                          # $1 -> optional non-BML stuff before opening tag
                 $TokenOpen
                 (\w+)                          # $2 -> tag name
                 )
                (?:                             # CASE A: could be 1) immediate tag close, 2) tag close
                                                #         with data, or 3) slow path, below
                 ($TokenClose) |                # A.1: $3 -> immediate tag close (depth 0)
                 (?:                            # A.2: simple close with data (data has no BML start tag of same tag)
                    ((?:.(?!$TokenOpen\2\b))+?) # $4 -> one or more chars without following opening BML tags
                   \b\2$TokenClose              # matching closing tag
                 ) |
                                                # A.3: final case:  nothing, it's not the fast path.  handle below.
                 )                              # end case A
                /gcosx)
            {
                $$outref .= $1;
                $block = uc($2);
                $data = $4 || "";

                # fast path:  immediate close or simple data (no opening BML).
                if (defined $4 || $3) {
                    $$outref .= bml_block($req, $block, $data, $opts, $elhash);
                    return if $req->{'stop_flag'};
                    $data = undef;
                    $block = undef;
                    next EAT;
                }

                # slower (nesting) path.
                # fast path (above)  <?foo ...... foo?>
                # fast:              <?foo ... <?bar?> ... foo?>
                # slow (this path):  <?foo ... <?foo?> ... foo?>

                $depth = 1;

                # prepare/find a cached regexp to continue using below
                # continues below, finding an opening/close of existing tag
                $re = $re_decode{$block} ||=
                    qr/($TokenClose) |              # $1 -> immediate token closing
                          (?:
                           (.+?)                    # $2 -> non-BML part to push onto $data
                           (?:
                            ($TokenOpen$block\b) |  # $3 -> increasing depth
                            (\b$block$TokenClose)   # $4 -> decreasing depth
                            )
                           )/isx;

                # falls through below.

            } else {
                # no BML left? append it all and be done.
                $$outref .= substr($$inref, pos($$inref));
                return;
            }
        }

        # continue with slow path.

        # the regexp prepared above looks out for these cases:  (but not in
        # this order)
        #
        #  * Increasing depth:
        #     - some text, then another opening <?foo, increading our depth
        #       (this will always happen somewhere, as this is what defines a slow path)
        #         <?foo bla blah <?foo
        #  * Decreasing depth: (if depth==0, then we're done)
        #     - immediately closing the tag, empty tag
        #         <?foo?>
        #     - closing the tag (if depth == 0, then we're done)
        #         <?foo blah blah foo?>

        if ($$inref =~ m/\G$re/gc) {
            if ($1) {
                # immediate close
                $depth--;
                $data .= $1 if $depth;  # add closing token if we're still in another tag
            } elsif ($3) {
                # increasing depth of same block
                $data .= $2;            # data before opening bml tag
                $data .= $3;            # the opening tag itself
                $depth++;
            } elsif ($4) {
                # decreasing depth of same block
                $data .= $2;            # data before closing tag
                $depth--;
                $data .= $4 if $depth;  # add closing tag itself, if we're still in another tag
            }
        } else {
            $$outref .= inline_error("BML block '$block' has no close");
            return;
        }

        # handle finished blocks
        if ($depth == 0) {
            $$outref .= bml_block($req, $block, $data, $opts, $elhash);
            return if $req->{'stop_flag'};
            $data = undef;
            $block = undef;
        }
    }
}

# takes a scalar with %%FIELDS%% mixed in and replaces
# them with their correct values from an anonymous hash, given
# by the second argument to this call
sub parsein
{
    my ($data, $hashref) = @_;
    $data =~ s/%%(\w+)%%/$hashref->{uc($1)}/eg;
    return $data;
}

sub inline_error
{
    return "[Error: <b>@_</b>]";
}

# returns lower-cased, trimmed string
sub trim
{
    my $a = $_[0];
    $a =~ s/^\s*(.*?)\s*$/$1/s;
    return $a;
}

sub handle_code_error {
    my ($env, $msg) = @_;
    if ($env->{'HOOK-codeerror'}) {
        my $ret = eval {
            $env->{'HOOK-codeerror'}->($msg);
        };
        return "<b>[Error running codeerror hook]</b>" if $@;
        return $ret;
    } else {
        return "<b>[Error: $msg]</b>";
    }
}

sub load_look_perl
{
    my ($file) = @_;

    $conf_pl_look = {};
    eval { do $file; };
    if ($@) {
        print STDERR "Error evaluating BML block conf file $file: $@\n";
        return 0;
    }
    $LookItems{$file} = $conf_pl_look;
    undef $conf_pl_look;

    return 1;
}

sub load_look
{
    my $file = shift;
    my BML::Request $req = shift;  # optional

    my $dontcheck = file_dontcheck($file);
    if ($dontcheck) {
        return 0 unless $FileModTime{$file};
        note_mod_time($req, $FileModTime{$file}) if $req;
        return 1;
    }
    note_mod_time($req, $FileModTime{$file}) if $req;

    if ($file =~ /\.pl$/) {
        return load_look_perl($file);
    }

    my $target = $LookItems{$file} = {};

    foreach my $look ($file, keys %{$LookChild{$file}||{}}) {
        delete $SchemeData->{$look};
        delete $SchemeFlags->{$look};
    }

    open (LOOK, $file);
    my $look_file;
    { local $/ = undef; $look_file = <LOOK>; }
    close LOOK;
    load_elements($target, $look_file);

    # look for template types
    while (my ($k, $v) = each %$target) {
        if ($v =~ s/^\{([A-Za-z]+)\}//) {
            $v = [ $v, $1 ];
        } else {
            $v = [ $v ];
        }
        $target->{$k} = $v;
    }

    $LookParent{$file} = undef;
    if ($target->{'_PARENT'}) {
        my $parfile = file_rel2abs($file, $target->{'_PARENT'}->[0]);
        if ($parfile && load_look($parfile)) {
            $LookParent{$file} = $parfile;
            $LookChild{$parfile}->{$file} = 1;
        }
    }

    return 1;
}

# given a block of data, loads elements found into
sub load_elements
{
    my ($hashref, $data, $opts) = @_;
    my $ol = $opts->{'declorder'};

    my @lines = split(/\r?\n/, $data);

    while (@lines) {
        my $line = shift @lines;

        # single line declaration:
        # key=>value
        if ($line =~ /^\s*(\w[\w\/]*)=>(.*)/) {
            $hashref->{uc($1)} = $2;
            push @$ol, uc($1);
            next;
        }

        # multi-line declaration:
        # key<=
        # line1
        # line2
        # <=key
        if ($line =~ /^\s*(\w[\w\/]*)<=\s*$/) {
            my $block = uc($1);
            my $endblock = qr/^\s*<=$1\s*$/;
            my $newblock = qr/^\s*$1<=\s*$/;
            my $depth = 1;
            my @out;
            while (@lines) {
                $line = shift @lines;
                if ($line =~ /$newblock/) {
                    $depth++;
                    next;
                } elsif ($line =~ /$endblock/) {
                    $depth--;
                    last unless $depth;
                }
                push @out, $line;
            }
            if ($depth == 0) {
                $hashref->{$block} = join("\n", @out) . "\n";
                push @$ol, $block;
            }
        }

    } # end while (@lines)
}

# given a file, checks it's modification time and sees if it's
# newer than anything else that compiles into what is the document
sub note_file_mod_time
{
    my ($req, $file) = @_;
    note_mod_time($req, (stat($file))[9]);
}

sub note_mod_time
{
    my BML::Request $req = shift;
    my $mod_time = shift;

    if ($req) {
        if ($mod_time > $req->{'most_recent_mod'}) {
            $req->{'most_recent_mod'} = $mod_time;
        }
    } else {
        if ($mod_time > $Apache::BML::base_recent_mod) {
            $Apache::BML::base_recent_mod = $mod_time;
        }
    }
}

sub parse_inputs {
    # only run once
    # FIXME: ModPerl 2.0: make sure this only runs once or this will be buggy as hell

    # we expect as input a typical request object, we will upgrade it to a proper
    # request object
    my $apache_r = Apache2::Request->new( shift );

    # dig out the POST stuff in the new ModPerl 2 way, note that we have to do this
    # to get multiple parameters in the \0 separated way we expect
    # Additionally: certain things (editpics.bml, for one) expect %POST to be empty
    # for multipart POSTs, so don't populate if the content type is 'multipart/form-data'
    my %posts;
    unless ($apache_r->headers_in()->get("Content-Type") =~ m!^multipart/form-data!) {
        foreach my $arg ( $apache_r->body ) {
            $posts{$arg} = join( "\0", $apache_r->body( $arg ) )
                if ! exists $posts{$arg};
        }
    }

    # and now the GET stuff
    my %gets;
    foreach my $pair ( split /&/, $apache_r->args ) {
        my ($name, $value) = split /=/, $pair;

        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

        $gets{$name} .= $gets{$name} ? "\0$value" : $value;
    }

    # let BML code blocks see input
    %BMLCodeBlock::GET = ();
    %BMLCodeBlock::POST = ();
    %BMLCodeBlock::FORM = ();  # whatever request method is
    my %input_target = ( GET  => [ \%BMLCodeBlock::GET  ],
                         POST => [ \%BMLCodeBlock::POST ], );
    push @{$input_target{$apache_r->method}}, \%BMLCodeBlock::FORM;
    foreach my $id ([ [ %gets  ] => $input_target{'GET'}  ],
                    [ [ %posts ] => $input_target{'POST'} ])
    {
        while (my ($k, $v) = splice @{$id->[0]}, 0, 2) {
            foreach my $dest (@{$id->[1]}) {
                $dest->{$k} .= "\0" if exists $dest->{$k};
                $dest->{$k} .= $v;
            }
        }
    }
}

# formatting
sub modified_time
{
    my BML::Request $req = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($req->{'most_recent_mod'});
    my @day = qw{Sun Mon Tue Wed Thu Fri Sat};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    if ($year < 1900) { $year += 1900; }

    return sprintf("$day[$wday], %02d $month[$mon] $year %02d:%02d:%02d GMT",
                   $mday, $hour, $min, $sec);
}

# both Cwd and File::Spec suck.  they're portable, but they suck.
# these suck too (slow), but they do what i want.

sub dir_rel2abs {
    my ($dir, $rel) = @_;
    return $rel if $rel =~ m!^/!;
    my @dir = grep { $_ ne "" } split(m!/!, $dir);
    my @rel = grep { $_ ne "" } split(m!/!, $rel);
    while (@rel) {
        $_ = shift @rel;
        next if $_ eq ".";
        if ($_ eq "..") { pop @dir; next; }
        push @dir, $_;
    }
    return join('/', '', @dir);
}

sub file_rel2abs {
    my ($file, $rel) = @_;
    return $rel if $rel =~ m!^/!;
    $file =~ s!(.+/).*!$1!;
    return dir_rel2abs($file, $rel);
}

package BML;

# returns false if remote browser can't handle the HttpOnly cookie atttribute
# (Microsoft extension to make cookies unavailable to scripts)
# it renders cookies useless on some browsers.  by default, returns true.
sub http_only
{
    my $ua = BML::get_client_header("User-Agent");
    return 0 if $ua =~ /MSIE.+Mac_/;
    return 1;
}

sub fill_template
{
    my ($name, $vars) = @_;
    die "Can't use BML::fill_template($name) in non-BML context" unless $Apache::BML::cur_req;
    return Apache::BML::parsein(${$Apache::BML::cur_req->{'blockref'}->{uc($name)}},
                                $vars);
}

sub get_scheme
{
    return undef unless Apache::BML::is_initialized();
    return $Apache::BML::cur_req->{'scheme'};
}

sub set_scheme
{
    return undef unless Apache::BML::is_initialized();

    my BML::Request $req = $Apache::BML::cur_req;
    my $scheme = shift;
    return 0 if $scheme =~ /[^\w\-]/;
    unless ($scheme) {
        $scheme = $req->{'env'}->{'ForceScheme'} ||
            DW::SiteScheme->default;
    }

    my $dw_scheme = DW::SiteScheme->get($scheme);

    if ( $dw_scheme ) {
        my $engine = $dw_scheme->engine;
        if ( $engine eq 'tt' ) {
            $scheme = 'tt_runner';
            DW::Request->get->pnote( actual_scheme => $dw_scheme );
        } elsif ( ! $dw_scheme->supports_bml ) {
            die "Unknown scheme engine $engine for $scheme";
        }
    }

    my $file = "$req->{env}{LookRoot}/$scheme.look";

    return 0 unless Apache::BML::load_look($file);

    $req->{'scheme'} = $scheme;
    $req->{'scheme_file'} = $file;

    # now we have to combine both of these (along with the VARINIT)
    # and then expand all the static stuff
    unless (exists $SchemeData->{$file}) {
        my $iter = $file;
        my @files;
        while ($iter) {
            unshift @files, $iter;
            $iter = $Apache::BML::LookParent{$iter};
        }

        my $sd = $SchemeData->{$file} = {};
        my $sf = $SchemeFlags->{$file} = {};

        foreach my $file (@files) {
            while (my ($k, $v) = each %{$Apache::BML::LookItems{$file}}) {
                $sd->{$k} = $v->[0];
                $sf->{$k} = $v->[1];
            }
        }
        foreach my $k (keys %$sd) {
            # skip any refs we have, as they aren't processed until run time
            next if ref $sf->{$k};

            # convert <?imgroot?> into http://www.site.com/img/ etc...
            next unless index($sf->{$k}, 's') != -1;
            $sd->{$k} =~ s/$TokenOpen([a-zA-Z0-9\_]+?)$TokenClose/$sd->{uc($1)}/og;
        }
    }

    # now, this request needs a copy of (well, references to) the
    # data above.  can't use that directly, since it might
    # change using _INFO LOCALBLOCKS to declare new file-local blocks
    $req->{'blockflags'} = {
        '_INFO' => 'F', '_INCLUDE' => 'F',
    };
    $req->{'blockref'} = {};
    foreach my $k (keys %{$SchemeData->{$file}}) {
        $req->{'blockflags'}->{$k} = $SchemeFlags->{$file}->{$k};
        $req->{'blockref'}->{$k} = \$SchemeData->{$file}->{$k};
    }

    return 1;
}

sub set_etag
{
    return undef unless Apache::BML::is_initialized();

    my $etag = shift;
    $Apache::BML::cur_req->{'etag'} = $etag;
}

# when CODE blocks need to look-up static values and such
sub get_template_def
{
    return undef unless Apache::BML::is_initialized();

    my $blockname = shift;
    my $schemefile = $Apache::BML::cur_req->{'scheme_file'};
    return $SchemeData->{$schemefile}->{uc($blockname)};
}

sub reset_cookies
{
    %BML::COOKIE_M = ();
    $BML::COOKIES_PARSED = 0;
}

sub set_config
{
    my ($key, $val) = @_;
    die "BML::set_config called from non-conffile context.\n" unless $Apache::BML::conf_pl;
    $Apache::BML::conf_pl->{$key} ||= $val;
    #$Apache::BML::config->{$path}->{$key} = $val;
}

sub noparse
{
    $Apache::BML::CodeBlockOpts{'raw'} = 1;
    return $_[0];
}

sub decide_language
{
    return undef unless Apache::BML::is_initialized();

    my BML::Request $req = $Apache::BML::cur_req;
    my $env = $req->{'env'};

    # GET param 'uselang' takes priority
    my $uselang = $BMLCodeBlock::GET{'uselang'};
    if (exists $env->{"Langs-$uselang"} || $uselang eq "debug") {
        return $uselang;
    }

    # next is their browser's preference
    my %lang_weight = ();
    my @langs = split(/\s*,\s*/, lc($req->{'r'}->headers_in->{"Accept-Language"}));
    my $winner_weight = 0.0;
    my $winner;
    foreach (@langs)
    {
        # do something smarter in future.  for now, ditch country code:
        s/-\w+//;

        if (/(.+);q=(.+)/) {
            $lang_weight{$1} = $2;
        } else {
            $lang_weight{$_} = 1.0;
        }
        if ($lang_weight{$_} > $winner_weight && defined $env->{"ISOCode-$_"}) {
            $winner_weight = $lang_weight{$_};
            $winner = $env->{"ISOCode-$_"};
        }
    }
    return $winner if $winner;

    # next is the default language
    return $LJ::LANGS[0];

    # lastly, english.
    return "en";
}

sub register_language
{
    my ($langcode) = @_;
    die "BML::register_language called from non-conffile context.\n" unless $Apache::BML::conf_pl;
    $Apache::BML::conf_pl->{"Langs-$langcode"} ||= 1;
}

sub register_isocode
{
    my ($isocode, $langcode) = @_;
    next unless $isocode =~ /^\w{2,2}$/;
    die "BML::register_isocode called from non-conffile context.\n" unless $Apache::BML::conf_pl;
    $Apache::BML::conf_pl->{"ISOCode-$isocode"} ||= $langcode;
}

# get/set the flag to send the Last-Modified header
sub want_last_modified
{
    return undef unless Apache::BML::is_initialized();

    $Apache::BML::cur_req->{'want_last_modified'} = $_[0]
        if defined $_[0];
    return $Apache::BML::cur_req->{'want_last_modified'};
}

sub note_mod_time
{
    my $mod_time = shift;
    Apache::BML::note_mod_time($Apache::BML::cur_req, $mod_time);
}

sub redirect
{
    return undef unless Apache::BML::is_initialized();

    my $url = shift;
    $Apache::BML::cur_req->{'location'} = $url;
    finish_suppress_all();
    return;
}

sub do_later
{
    return undef unless Apache::BML::is_initialized();

    my $subref = shift;
    return 0 unless ref $subref eq "CODE";
    $Apache::BML::cur_req->{'r'}->pool->cleanup_register($subref);
    return 1;
}

# $def can be a coderef which will get executed when the template is being
# run against a page; otherwise, it's a string
sub register_block
{
    my ($type, $flags, $def) = @_;
    my $target = $Apache::BML::conf_pl_look;
    die "BML::register_block called from non-lookfile context.\n" unless $target;
    $type = uc($type);

    $target->{$type} = [ $def, $flags ];
    return 1;
}

sub register_hook
{
    my ($name, $code) = @_;
    die "BML::register_hook called from non-conffile context.\n" unless $Apache::BML::conf_pl;
    $Apache::BML::conf_pl->{"HOOK-$name"} = $code;
}

# FIXME: these became necessary with ModPerl 2.0, but it would be great if we could
# review this change and ensure that this is what we want to be doing here...  i.e., if
# we haven't defined these yet, then we should define them here?  confused.
sub get_GET {
    return \%BMLCodeBlock::GET;
}

sub get_POST {
    return \%BMLCodeBlock::POST;
}

sub get_FORM {
    return \%BMLCodeBlock::FORM;
}

sub get_request
{
    # we do this, and not use $Apache::BML::r directly because some non-BML
    # callers sometimes use %BML::COOKIE, so $Apache::BML::r isn't set.
    # the cookie FETCH below calls this function to try and use BML::get_request(),
    # else fall back to the global one (for use in profiling/debugging)
    my $apache_r;
    eval {
        $apache_r = Apache2::RequestUtil->request;
    };
    $apache_r ||= $Apache::BML::r;
    return $apache_r;
}

sub get_query_string
{
    my $apache_r = BML::get_request();
    return scalar($apache_r->args);
}

sub get_uri
{
    my $apache_r = BML::get_request();
    my $uri = $apache_r->uri;
    $uri =~ s/\.bml$//;
    return $uri;
}

sub get_hostname
{
    my $apache_r = BML::get_request();
    return $apache_r->hostname;
}

sub get_method
{
    my $apache_r = BML::get_request();
    return $apache_r->method;
}

sub get_path_info
{
    my $apache_r = BML::get_request();
    return $apache_r->path_info;
}

sub get_remote_ip
{
    my $apache_r = BML::get_request();
    return $apache_r->connection()->client_ip;
}

sub get_remote_host
{
    my $apache_r = BML::get_request();
    return $apache_r->connection()->remote_host;
}

sub get_remote_user
{
    my $apache_r = BML::get_request();
    return $apache_r->connection()->user;
}

sub get_client_header
{
    my $hdr = shift;
    my $apache_r = BML::get_request();
    return $apache_r->headers_in->{$hdr};
}

# <LJFUNC>
# class: web
# name: BML::self_link
# des: Takes the URI of the current page, and adds the current form data
#      to the URL, then adds any additional data to the URL.
# returns: scalar; the full url
# args: newvars
# des-newvars: A hashref of information to add/override to the link.
# </LJFUNC>
sub self_link
{
    my $newvars = shift;
    my $link = $Apache::BML::r->uri;
    my $form = \%BMLCodeBlock::FORM;

    $link .= "?";
    foreach (keys %$newvars) {
        if (! exists $form->{$_}) { $form->{$_} = ""; }
    }
    foreach (sort keys %$form) {
        if (defined $newvars->{$_} && ! $newvars->{$_}) { next; }
        my $val = $newvars->{$_} || $form->{$_};
        next unless $val;
        $link .= BML::eurl($_) . "=" . BML::eurl($val) . "&";
    }
    chop $link;
    return $link;
}

sub http_response
{
    my ($code, $msg) = @_;

    my $apache_r = $Apache::BML::r;
    $apache_r->status($code);
    $apache_r->content_type('text/html');
    $apache_r->print($msg);
    finish_suppress_all();
    return;
}

sub finish_suppress_all
{
    finish();
    suppress_headers();
    suppress_content();
}

sub suppress_headers
{
    return undef unless Apache::BML::is_initialized();

    # set any cookies that we have outstanding
    send_cookies();
    $Apache::BML::cur_req->{'env'}->{'NoHeaders'} = 1;
}

sub suppress_content
{
    return undef unless Apache::BML::is_initialized();
    $Apache::BML::cur_req->{'env'}->{'NoContent'} = 1;
}

sub finish
{
    return undef unless Apache::BML::is_initialized();
    $Apache::BML::cur_req->{'stop_flag'} = 1;
}

sub set_content_type
{
    return undef unless Apache::BML::is_initialized();
    $Apache::BML::cur_req->{'content_type'} = $_[0] if $_[0];
}

# <LJFUNC>
# class: web
# name: BML::set_status
# des: Takes a number to indicate a status (e.g. 404, 403, 410, 500, etc.) and sets
#      that to be returned to the client when the request finishes.
# returns: nothing
# args: status
# des-newvars: A number representing the status to return to the client.
# </LJFUNC>
sub set_status
{
    $Apache::BML::r->status($_[0]+0) if $_[0];
}

sub eall
{
    return ebml(ehtml($_[0]));
}


# escape html
sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

sub ebml
{
    my $a = $_[0];
    my $ra = ref $a ? $a : \$a;
    $$ra =~ s/\(=(\w)/\(= $1/g;  # remove this eventually (old syntax)
    $$ra =~ s/(\w)=\)/$1 =\)/g;  # remove this eventually (old syntax)
    $$ra =~ s/<\?/&lt;?/g;
    $$ra =~ s/\?>/?&gt;/g;
    return if ref $a;
    return $a;
}

sub get_language
{
    return undef unless Apache::BML::is_initialized();
    return $Apache::BML::cur_req->{'lang'};
}

sub get_language_default
{
    return "en" unless Apache::BML::is_initialized();
    return $Apache::BML::cur_req->{'env'}->{'DefaultLanguage'} || "en";
}

sub get_language_scope {
    return $BML::ML_SCOPE;
}

sub set_language_scope {
    $BML::ML_SCOPE = shift;
}

sub set_language
{
    my ($lang, $getter) = @_;  # getter is optional
    my BML::Request $req = $Apache::BML::cur_req;
    my $apache_r = BML::get_request();
    $apache_r->notes->{'langpref'} = $lang;

    # don't rely on $req (the current BML request) being defined, as
    # we allow callers to use this interface directly from non-BML
    # requests.
    if (Apache::BML::is_initialized()) {
        $req->{'lang'} = $lang;
        $getter ||= $req->{'env'}->{'HOOK-ml_getter'};
    }

    no strict 'refs';
    if ($lang eq "debug") {
        no warnings 'redefine';
        *{"BML::ml"} = sub {
            return $_[0];
        };
        *{"BML::ML::FETCH"} = sub {
            return $_[1];
        };
    } elsif ($getter) {
        no warnings 'redefine';
        *{"BML::ml"} = sub {
            my ($code, $vars) = @_;
            $code = $BML::ML_SCOPE . $code
                if rindex($code, '.', 0) == 0;
            return $getter->($lang, $code, undef, $vars);
        };
        *{"BML::ML::FETCH"} = sub {
            my $code = $_[1];
            $code = $BML::ML_SCOPE . $code
                if rindex($code, '.', 0) == 0;
            return $getter->($lang, $code);
        };
    };

}

# multi-lang string
# note: sub is changed when BML::set_language is called
sub ml
{
    return "[ml_getter not defined]";
}

sub eurl
{
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

sub durl
{
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

sub randlist
{
    my @rlist = @_;
    my $size = scalar(@rlist);

    my $i;
    for ($i=0; $i<$size; $i++)
    {
        unshift @rlist, splice(@rlist, $i+int(rand()*($size-$i)), 1);
    }
    return @rlist;
}

sub page_newurl
{
    my $page = $_[0];
    my @pair = ();
    foreach (sort grep { $_ ne "page" } keys %BMLCodeBlock::FORM)
    {
        push @pair, (eurl($_) . "=" . eurl($BMLCodeBlock::FORM{$_}));
    }
    push @pair, "page=$page";
    return $Apache::BML::r->uri . "?" . join("&", @pair);
}

sub paging
{
    my ($listref, $page, $pagesize) = @_;
    $page = 1 unless ($page && $page eq int($page));
    my %self;

    $self{'itemcount'} = scalar(@{$listref});

    $self{'pages'} = $self{'itemcount'} / $pagesize;
    $self{'pages'} = $self{'pages'}==int($self{'pages'}) ? $self{'pages'} : (int($self{'pages'})+1);

    $page = 1 if $page < 1;
    $page = $self{'pages'} if $page > $self{'pages'};
    $self{'page'} = $page;

    $self{'itemfirst'} = $pagesize * ($page-1) + 1;
    $self{'itemlast'} = $self{'pages'}==$page ? $self{'itemcount'} : ($pagesize * $page);

    $self{'items'} = [ @{$listref}[($self{'itemfirst'}-1)..($self{'itemlast'}-1)] ];

    unless ($page==1) { $self{'backlink'} = "<a href=\"" . page_newurl($page-1) . "\">&lt;&lt;&lt;</a>"; }
    unless ($page==$self{'pages'}) { $self{'nextlink'} = "<a href=\"" . page_newurl($page+1) . "\">&gt;&gt;&gt;</a>"; }

    return %self;
}

sub send_cookies {
    my $req = shift();

    unless ($req) {
        return undef unless Apache::BML::is_initialized();
        $req = $Apache::BML::cur_req;
    }

    foreach (values %{$req->{'cookies'}}) {
        $req->{'r'}->err_headers_out->add("Set-Cookie" => $_);
    }
    $req->{'cookies'} = {};
    $req->{'env'}->{'SentCookies'} = 1;
}

# $expires = 0  to expire when browser closes
# $expires = undef to delete cookie
sub set_cookie
{
    return undef unless Apache::BML::is_initialized();

    my ($name, $value, $expires, $path, $domain, $http_only) = @_;

    my BML::Request $req = $Apache::BML::cur_req;
    my $e = $req->{'env'};
    $path = $e->{'CookiePath'} unless defined $path;
    $domain = $e->{'CookieDomain'} unless defined $domain;

    # let the domain argument be an array ref, so callers can set
    # cookies in both .foo.com and foo.com, for some broken old browsers.
    if ($domain && ref $domain eq "ARRAY") {
        foreach (@$domain) {
            set_cookie($name, $value, $expires, $path, $_, $http_only);
        }
        return;
    }

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($expires);
    $year+=1900;

    my @day = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    my $cookie = eurl($name) . "=" . eurl($value);

    # this logic is confusing potentially
    unless (defined $expires && $expires==0) {
        $cookie .= sprintf("; expires=$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
                           $mday, $year, $hour, $min, $sec);
    }
    $cookie .= "; path=$path" if $path;
    $cookie .= "; domain=$domain" if $domain;
    $cookie .= "; HttpOnly" if $http_only && BML::http_only();

    # send a cookie directly or cache it for sending later?
    if ($e->{'SentCookies'}) {
        $req->{'r'}->err_headers_out->add("Set-Cookie" => $cookie);
    } else {
        $req->{'cookies'}->{"$name:$domain"} = $cookie;
    }

    if (defined $expires) {
        $BML::COOKIE_M{$name} = [ $value ];
    } else {
        delete $BML::COOKIE_M{$name};
    }
}

## Usage:
#
#  BML::decl_params( $field => $rule, .... )
#
#  Rationale:  declare all %GET and %POST parameters
#    you expect, and their types, and you then don't
#    see unexpected keys or values.  Also %FORM is wiped
#    by using this, since it's old.
#
#  Where:
#      $field --- %GET/%POST key. or "_default" to match anything else.
#      $rule  --- either a hashref of rule details,
#                 or a type.
#
#       1) if rule is just a type:
#          a) named type:  "word", "digits", "color"
#          b) a regular expression object.
#
#       2) a hashref of keys:
#          'type' -- of type of rule from 1) above
#          'from' -- either "GET" or "POST" to declare
#                    where this rule applies.   you can have
#                    multiple $fields of the same name,
#                    if one is 'from' => GET and one POST.
#                    then their types apply independently.
#
# Example:
#           BML::decl_params(
#                         count    => "digits",
#                         sym      => "word",
#                         onecap   => qr/^[A-Z]$/,
#                         postdata => {
#                             from => 'POST',
#                         },
#                         );
#

sub decl_params {
    my %rules;  # {GET|POST|ANY}-"field" => { type => ..., }
    while (@_) {
        my $sym = shift;
        my $rule = shift;
        unless (ref $rule eq "HASH") {
            $rule = {
                type => $rule,
            };
        }
        $rule->{from} ||= "ANY";

        # convert named types to regexps
        my $types = {
            'digits' => qr/^\d+$/,
            'word' => qr/^\w+$/,
            'color' => qr/^\#[0-9a-f]{3,6}$/i,
        };
        if ($types->{$rule->{type}}) {
            $rule->{type} = $types->{$rule->{type}}
        }
        $rules{"$rule->{from}-$sym"} = $rule;
    }

    # if they declared their parameters, they get potentially
    # unsafe ones back, which we might've otherwise hidden
    # out of paranoia:
    while (my ($k, $v) = each %BMLCodeBlock::GET_POTENTIAL_XSS) {
        $BMLCodeBlock::GET{$k} = $v;
    }

    # using this destroys %FORM.  it's deprecated anyway.
    %BMLCodeBlock::FORM = ();
    my %to_clean = ( GET  => \%BMLCodeBlock::GET ,
                     POST => \%BMLCodeBlock::POST, );
    foreach my $what (keys %to_clean) {
        my $hash = $to_clean{$what};
        foreach my $k (keys %$hash) {
            my $rule = $rules{"$what-$k"} || $rules{"ANY-$k"} || $rules{"$what-_default"} || $rules{"ANY-_default"};
            unless ($rule) {
                delete $hash->{$k};
                next;
            }
            my $rx = $rule->{type};
            if ($rx && $hash->{$k} !~ /$rx/) {
                delete $hash->{$k};
                next;
            }
        }
    }
}

# cookie support
package BML::Cookie;

sub TIEHASH {
    my $class = shift;
    my $self = {};
    bless $self;
    return $self;
}

sub FETCH {
    my ($t, $key) = @_;
    # we do this, and not use $Apache::BML::r directly because some non-BML
    # callers sometimes use %BML::COOKIE.
    my $apache_r = BML::get_request();
    unless ($BML::COOKIES_PARSED) {
        foreach (split(/;\s+/, $apache_r->headers_in->{"Cookie"})) {
            next unless ($_ =~ /(.*)=(.*)/);
            my ($name, $value) = ($1, $2);
            my $dname  = BML::durl($name);
            my $dvalue = BML::durl($value);
            push @{$BML::COOKIE_M{$dname} ||= []}, $dvalue;
        }
        $BML::COOKIES_PARSED = 1;
    }

    # return scalar value, or arrayref if key has [] appende
    return $BML::COOKIE_M{$key} || []  if $key =~ s/\[\]$//;
    return ($BML::COOKIE_M{$key} || [])->[-1];
}

sub STORE {
    my ($t, $key, $val) = @_;
    my $etime = 0;
    my $http_only = 0;
    ($val, $etime, $http_only) = @$val if ref $val eq "ARRAY";
    $etime = undef unless $val ne "";
    BML::set_cookie($key, $val, $etime, undef, undef, $http_only);
}

sub DELETE {
    my ($t, $key) = @_;
    STORE($t, $key, undef);
}

sub CLEAR {
    my ($t) = @_;
    foreach (keys %BML::COOKIE_M) {
        STORE($t, $_, undef);
    }
}

sub EXISTS {
    my ($t, $key) = @_;
    return defined $BML::COOKIE_M{$key};
}

sub FIRSTKEY {
    my ($t) = @_;
    keys %BML::COOKIE_M;
    return each %BML::COOKIE_M;
}

sub NEXTKEY {
    my ($t, $key) = @_;
    return each %BML::COOKIE_M;
}

# provide %BML::ML & %BMLCodeBlock::ML support:
package BML::ML;

sub TIEHASH {
    my $class = shift;
    my $self = {};
    bless $self;
    return $self;
}

# note: sub is changed when BML::set_language is called.
sub FETCH {
    return "[ml_getter not defined]";
}

# do nothing
sub CLEAR { }

1;

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

