#!/usr/bin/perl
#
# DW::BML
#
# BML rendering for Plack via DW::Request. This module implements the BML
# handler logic using the DW::Request abstraction layer instead of Apache APIs,
# allowing BML pages to render under Plack.
#
# The existing Apache::BML module continues to work unchanged for mod_perl.
# This module reuses the core BML engine (bml_decode, bml_block, config loading,
# scheme/look system) and only replaces the handler and request adapter layers.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BML;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Cwd qw(abs_path);
use Digest::MD5;
use DW::Request;
use DW::SiteScheme;
use LJ::Directories;

# Cache for file lookups, mirrors Apache::LiveJournal's %FILE_LOOKUP_CACHE
my %FILE_LOOKUP_CACHE;

# resolve_path: given a URI, find the .bml file on disk
# Returns ($redirect_url, $uri, $filepath)
#   - If redirect needed: ($url, undef, undef)
#   - If file found: (undef, $uri, $filepath)
#   - If nothing found: (undef, undef, undef)
sub resolve_path {
    my ( $class, $uri ) = @_;

    return ( undef, undef, undef ) if $uri =~ m!(\.\.|\%|\.\/)!;

    if ( exists $FILE_LOOKUP_CACHE{$uri} ) {
        my $cached = $FILE_LOOKUP_CACHE{$uri};
        return ( undef, $cached->[0], $cached->[1] );
    }

    foreach my $dir ( LJ::get_all_directories('htdocs') ) {
        my $file = "$dir/$uri";

        # main page: / => /index.bml
        my $resolved_uri = $uri;
        if ( -e "$file/index.bml" && $uri eq '/' ) {
            $file         .= "index.bml";
            $resolved_uri .= "index.bml";
        }

        # /blah/file => /blah/file.bml
        if ( -e "$file.bml" ) {
            $file         .= ".bml";
            $resolved_uri .= ".bml";
        }

        # /foo => /foo/ (redirect), /foo/ => /foo/index.bml
        if ( -d $file && -e "$file/index.bml" ) {
            unless ( $uri =~ m!/$! ) {
                my $redirect_url = LJ::create_url( $uri . "/" );
                return ( $redirect_url, undef, undef );
            }
            $file         .= "index.bml";
            $resolved_uri .= "index.bml";
        }

        next unless -f $file;

        $file = abs_path($file);
        if ($file) {
            $resolved_uri =~ s!^/+!/!;
            $FILE_LOOKUP_CACHE{$uri} = [ $resolved_uri, $file ];
            return ( undef, $resolved_uri, $file );
        }
    }

    return ( undef, undef, undef );
}

# render: render a BML file and send the response via DW::Request
# Arguments: $file (absolute path), $uri (request URI)
# Returns: 1 on success, 0 on failure (status already set on $r)
sub render {
    my ( $class, $file, $uri ) = @_;

    my $r = DW::Request->get;

    # Stat the file
    unless ( -e $file ) {
        $log->warn("BML file does not exist: $file");
        $r->status(404);
        $r->content_type('text/html');
        $r->print('Not Found');
        return 0;
    }

    unless ( -r $file ) {
        $log->warn("BML file not readable: $file");
        $r->status(403);
        $r->content_type('text/html');
        $r->print('Forbidden');
        return 0;
    }

    my $modtime = ( stat($file) )[9];

    # Never serve _config files
    if ( $file =~ /\b_config/ ) {
        $r->status(403);
        $r->content_type('text/html');
        $r->print('Forbidden');
        return 0;
    }

    # Install the request adapter so BML::get_request() etc. work
    my $adapter = DW::BML::RequestAdapter->new($r);
    local $Apache::BML::r = $adapter;

    # Create new BML request
    my $req = Apache::BML::initialize_cur_req( $adapter, $file );

    # Setup env: walk up directories loading _config.bml files
    my $env     = $req->{env};
    my $dir     = $file;
    my $docroot = $LJ::HTDOCS;
    $docroot =~ s!/$!!;
    my @dirconfs;
    my %confwant;

    while ($dir) {
        $dir =~ s!/[^/]*$!!;
        my $conffile = "$dir/_config.bml";
        $confwant{$conffile} = 1;
        push @dirconfs, Apache::BML::load_conffile($conffile);
        last if $dir eq $docroot;
    }

    # Process config chain with SubConfig overrides
    my %eff_config;
    foreach my $cfile (@dirconfs) {
        my $conf = $Apache::BML::FileConfig{$cfile};
        next unless $conf;
        $eff_config{$cfile} = $conf;
        if ( $conf->{'SubConfig'} ) {
            foreach my $sconf ( keys %confwant ) {
                my $sc = $conf->{'SubConfig'}{$sconf};
                $eff_config{$cfile} = $sc if $sc;
            }
        }
    }

    foreach my $cfile (@dirconfs) {
        my $conf = $eff_config{$cfile};
        next unless $conf;
        while ( my ( $k, $v ) = each %$conf ) {
            next if exists $env->{$k} || $k eq "SubConfig";
            $env->{$k} = $v;
        }
    }

    # Token syntax
    my ( $TokenOpen, $TokenClose );
    if ( $env->{'AllowOldSyntax'} ) {
        ( $TokenOpen, $TokenClose ) = ( '(?:<\?|\(=)', '(?:\?>|=\))' );
    }
    else {
        ( $TokenOpen, $TokenClose ) = ( '<\?', '\?>' );
    }

    # Force redirect hook
    if ( exists $env->{'HOOK-force_redirect'} ) {
        my $redirect_page = eval { $env->{'HOOK-force_redirect'}->($uri); };
        if ( defined $redirect_page ) {
            $r->status(302);
            $r->header_out( 'Location' => $redirect_page );
            $Apache::BML::r = undef;
            return 1;
        }
    }

    # Rewrite filename hook
    if ( exists $env->{'HOOK-rewrite_filename'} ) {
        eval {
            my $new_file = $env->{'HOOK-rewrite_filename'}->( req => $req, env => $env );
            $file = $new_file if $new_file;
        };
    }

    # Read the BML source
    unless ( open my $fh, '<', $file ) {
        $log->error("Couldn't open $file for reading: $!");
        $r->status(500);
        $r->content_type('text/html');
        $r->print('Internal Server Error');
        $Apache::BML::r = undef;
        return 0;
    }
    else {
        my $bmlsource;
        { local $/ = undef; $bmlsource = <$fh>; }
        close $fh;

        # Track modification times
        Apache::BML::note_mod_time( $req, $modtime );
        Apache::BML::note_mod_time( $req, $Apache::BML::base_recent_mod );

        if ( !defined $Apache::BML::FileModTime{$file}
            || $modtime > $Apache::BML::FileModTime{$file} )
        {
            $Apache::BML::FileModTime{$file} = $modtime;
            $req->{'filechanged'} = 1;
        }

        # Setup cookies and ML
        *BMLCodeBlock::COOKIE = *BML::COOKIE;
        BML::reset_cookies();
        *BMLCodeBlock::ML = *BML::ML;

        # Parse form inputs from DW::Request
        _parse_inputs( $r, $req );

        # XSS protection
        %BMLCodeBlock::GET_POTENTIAL_XSS = ();
        if ( $env->{MildXSSProtection} ) {
            foreach my $k ( keys %BMLCodeBlock::GET ) {
                next unless $BMLCodeBlock::GET{$k} =~ /\<|\%3C/i;
                $BMLCodeBlock::GET_POTENTIAL_XSS{$k} = $BMLCodeBlock::GET{$k};
                delete $BMLCodeBlock::GET{$k};
                delete $BMLCodeBlock::FORM{$k};
            }
        }

        # Startup hook
        if ( $env->{'HOOK-startup'} ) {
            eval { $env->{'HOOK-startup'}->(); };
            if ($@) {
                $r->status(500);
                $r->content_type('text/html');
                $r->print("<b>Error running startup hook:</b><br />\n$@");
                return 1;
            }
        }

        # Code block init perl hook
        $BML::CODE_INIT_PERL = "";
        if ( $env->{'HOOK-codeblock_init_perl'} ) {
            $BML::CODE_INIT_PERL = eval { $env->{'HOOK-codeblock_init_perl'}->(); };
            if ($@) {
                $r->status(500);
                $r->content_type('text/html');
                $r->print("<b>Error running codeblock_init_perl hook:</b><br />\n$@");
                return 1;
            }
        }

        # Determine scheme
        my $scheme =
               $r->note('bml_use_scheme')
            || $env->{'ForceScheme'}
            || $BMLCodeBlock::GET{skin}
            || $BMLCodeBlock::GET{'usescheme'}
            || $BML::COOKIE{'BMLschemepref'};

        if ( exists $env->{'HOOK-alt_default_scheme'} ) {
            $scheme ||= eval { $env->{'HOOK-alt_default_scheme'}->($env); };
        }

        my $default_scheme_override = undef;
        if ( $env->{'HOOK-default_scheme_override'} ) {
            $default_scheme_override = eval {
                $env->{'HOOK-default_scheme_override'}->( $scheme || DW::SiteScheme->default );
            };
            if ($@) {
                $r->status(500);
                $r->content_type('text/html');
                $r->print("<b>Error running scheme override hook:</b><br />\n$@");
                return 1;
            }
        }

        $scheme ||= $default_scheme_override || DW::SiteScheme->default;

        # Scheme translation hook
        if ( $env->{'HOOK-scheme_translation'} ) {
            my $newscheme = eval { $env->{'HOOK-scheme_translation'}->($scheme); };
            $scheme = $newscheme if $newscheme;
        }

        unless ( BML::set_scheme($scheme) ) {
            $scheme = $env->{'ForceScheme'}
                || DW::SiteScheme->default;
            BML::set_scheme($scheme);
        }

        # Language setup
        my $path_info  = '';     # Plack doesn't separate path_info for BML
        my $lang_scope = $uri;
        $lang_scope =~ s/\.bml$//;
        BML::set_language_scope($lang_scope);
        my $lang = BML::decide_language();
        BML::set_language($lang);

        # Run the BML decoder
        my $html = $env->{'_error'};

        if ( $env->{'HOOK-before_decode'} ) {
            eval { $env->{'HOOK-before_decode'}->(); };
            if ($@) {
                $r->status(500);
                $r->content_type('text/html');
                $r->print("<b>Error running before_decode hook:</b><br />\n$@");
                return 1;
            }
        }

        Apache::BML::bml_decode( $req, \$bmlsource, \$html, { DO_CODE => $env->{'AllowCode'} } )
            unless $html;

        # Send cookies
        BML::send_cookies($req);

        # Handle internal redirect
        if ( $r->note('internal_redir') ) {
            my $int_redir = DW::Routing->call( uri => $r->note('internal_redir') );
            if ( defined $int_redir ) {
                $r->note( 'internal_redir', undef );
                LJ::start_request();
                return 1;
            }
        }

        # Handle redirect
        if ( $req->{'location'} ) {
            $r->status(302);
            $r->header_out( 'Location' => $req->{'location'} );
            $Apache::BML::r = undef;
            return 1;
        }

        # ETag handling
        my $etag;
        if ( exists $req->{'etag'} ) {
            $etag = $req->{'etag'} if defined $req->{'etag'};
        }
        else {
            $etag = Digest::MD5::md5_hex($html);
        }
        $etag = '"' . $etag . '"' if defined $etag;

        my $ifnonematch = $r->header_in("If-None-Match");
        if ( defined $ifnonematch && defined $etag && $etag eq $ifnonematch ) {
            $r->status(304);
            $Apache::BML::r = undef;
            return 1;
        }

        my $content_type =
               $req->{'content_type'}
            || $env->{'DefaultContentType'}
            || "text/html";

        unless ( $env->{'NoHeaders'} ) {
            my $ims          = $r->header_in("If-Modified-Since");
            my $modtime_http = Apache::BML::modified_time($req);

            if ( $ims && !$env->{'NoCache'} && $ims eq $modtime_http ) {
                $r->status(304);
                $Apache::BML::r = undef;
                return 1;
            }

            $r->content_type($content_type);

            if ( $env->{'NoCache'} ) {
                $r->header_out( "Cache-Control" => "no-cache" );
                $r->no_cache;
            }

            $r->header_out( "Last-Modified" => $modtime_http )
                if $env->{'Static'} || $req->{'want_last_modified'};

            $r->header_out( "Cache-Control" => "private, proxy-revalidate" );
            $r->header_out( "ETag"          => $etag ) if defined $etag;

            my $length = length( $html // '' );
            $r->header_out( 'Content-length' => $length );
        }

        # Output the content
        unless ( $env->{'NoContent'} || $r->method eq 'HEAD' ) {
            $r->print( $html // '' );
        }

        $r->status(200) unless $r->status;
        $Apache::BML::r = undef;
        return 1;
    }
}

# _parse_inputs: populate %BMLCodeBlock::GET, POST, FORM from DW::Request
sub _parse_inputs {
    my ( $r, $req ) = @_;

    %BMLCodeBlock::GET  = ();
    %BMLCodeBlock::POST = ();
    %BMLCodeBlock::FORM = ();

    # GET parameters — use preserve_case to match Apache::BML behavior
    # which doesn't lowercase GET args
    my $get_args = $r->get_args( preserve_case => 1 );
    if ($get_args) {
        $get_args->each(
            sub {
                my ( $k, $v ) = @_;
                $BMLCodeBlock::GET{$k} .= "\0" if exists $BMLCodeBlock::GET{$k};
                $BMLCodeBlock::GET{$k} .= $v;
            }
        );
    }

    # POST parameters (only for url-encoded, not multipart)
    my $ct = $r->header_in('Content-Type') // '';
    unless ( $ct =~ m!^multipart/form-data! ) {
        my $post_args = $r->post_args;
        if ($post_args) {
            $post_args->each(
                sub {
                    my ( $k, $v ) = @_;
                    $BMLCodeBlock::POST{$k} .= "\0" if exists $BMLCodeBlock::POST{$k};
                    $BMLCodeBlock::POST{$k} .= $v;
                }
            );
        }
    }

    # FORM gets whichever method was used
    if ( $r->method eq 'POST' ) {
        %BMLCodeBlock::FORM = %BMLCodeBlock::POST;
    }
    else {
        %BMLCodeBlock::FORM = %BMLCodeBlock::GET;
    }
}

###########################################################################
# DW::BML::RequestAdapter
#
# Minimal adapter that makes DW::Request look enough like an Apache2 request
# object for BML's public API functions (BML::get_request(), etc.) to work.
###########################################################################

package DW::BML::RequestAdapter;

sub new {
    my ( $class, $dw_request ) = @_;
    return bless { r => $dw_request }, $class;
}

sub uri {
    return $_[0]->{r}->uri;
}

sub method {
    return $_[0]->{r}->method;
}

sub args {
    return $_[0]->{r}->query_string;
}

sub path_info {
    return '';    # BML pages don't use path_info in Plack context
}

sub hostname {
    return $_[0]->{r}->host;
}

sub header_only {
    return $_[0]->{r}->method eq 'HEAD' ? 1 : 0;
}

sub status {
    my ( $self, $val ) = @_;
    if ( defined $val ) {
        return $self->{r}->status($val);
    }
    return $self->{r}->status;
}

sub content_type {
    my ( $self, $val ) = @_;
    if ( defined $val ) {
        return $self->{r}->content_type($val);
    }
    return $self->{r}->content_type;
}

sub print {
    my ( $self, @args ) = @_;
    $self->{r}->print($_) for @args;
}

sub no_cache {
    return $_[0]->{r}->no_cache;
}

# headers_in: returns a tied hash-like object for reading request headers
sub headers_in {
    return DW::BML::RequestAdapter::HeadersIn->new( $_[0]->{r} );
}

# headers_out / err_headers_out: returns an object for setting response headers
sub headers_out {
    return DW::BML::RequestAdapter::HeadersOut->new( $_[0]->{r} );
}

sub err_headers_out {
    return DW::BML::RequestAdapter::ErrHeadersOut->new( $_[0]->{r} );
}

# notes: returns a tied hash-like object backed by DW::Request->note()
sub notes {
    return DW::BML::RequestAdapter::Notes->new( $_[0]->{r} );
}

# connection: returns an object with client_ip, remote_host, user
sub connection {
    return DW::BML::RequestAdapter::Connection->new( $_[0]->{r} );
}

# document_root: return $LJ::HTDOCS
sub document_root {
    return $LJ::HTDOCS;
}

# pool: stub for cleanup_register (no-op under Plack)
sub pool {
    return DW::BML::RequestAdapter::Pool->new;
}

# dir_config: stub, returns undef (no Apache dir config under Plack)
sub dir_config {
    return undef;
}

# finfo: no-op
sub finfo { }

# filename
sub filename {
    return $_[0]->{_filename};
}

###########################################################################
# HeadersIn: read-only hash-like access to request headers
###########################################################################

package DW::BML::RequestAdapter::HeadersIn;

use overload '%{}' => \&_as_hash, fallback => 1;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub _as_hash {
    my $self = shift;
    tie my %h, 'DW::BML::RequestAdapter::HeadersIn::Tie', $self->{r};
    return \%h;
}

package DW::BML::RequestAdapter::HeadersIn::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH  { return $_[0]->{r}->header_in( $_[1] ) }
sub EXISTS { return defined $_[0]->{r}->header_in( $_[1] ) }
sub STORE  { }                                                 # read-only

###########################################################################
# HeadersOut: hash-like access to response headers
###########################################################################

package DW::BML::RequestAdapter::HeadersOut;

use overload '%{}' => \&_as_hash, fallback => 1;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub _as_hash {
    my $self = shift;
    tie my %h, 'DW::BML::RequestAdapter::HeadersOut::Tie', $self->{r};
    return \%h;
}

package DW::BML::RequestAdapter::HeadersOut::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH { return $_[0]->{r}->header_out( $_[1] ) }
sub STORE { $_[0]->{r}->header_out( $_[1], $_[2] ) }

###########################################################################
# ErrHeadersOut: for Set-Cookie via ->add()
###########################################################################

package DW::BML::RequestAdapter::ErrHeadersOut;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub add {
    my ( $self, $name, $value ) = @_;
    $self->{r}->err_header_out_add( $name, $value );
}

###########################################################################
# Notes: hash-like access to per-request notes
###########################################################################

package DW::BML::RequestAdapter::Notes;

use overload '%{}' => \&_as_hash, fallback => 1;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub _as_hash {
    my $self = shift;
    tie my %h, 'DW::BML::RequestAdapter::Notes::Tie', $self->{r};
    return \%h;
}

package DW::BML::RequestAdapter::Notes::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH { return $_[0]->{r}->note( $_[1] ) }
sub STORE { $_[0]->{r}->note( $_[1], $_[2] ) }

###########################################################################
# Connection: client_ip, remote_host, user
###########################################################################

package DW::BML::RequestAdapter::Connection;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub client_ip {
    return $_[0]->{r}->get_remote_ip;
}

sub remote_host {
    return $_[0]->{r}->get_remote_ip;
}

sub user {
    return undef;
}

###########################################################################
# Pool: stub for cleanup_register
###########################################################################

package DW::BML::RequestAdapter::Pool;

sub new {
    return bless {}, $_[0];
}

sub cleanup_register {

    # No-op under Plack — cleanup happens at end of request naturally
}

1;
