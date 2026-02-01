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

# Provide BML::* package functions for the Plack environment. Under mod_perl these
# are defined by Apache::BML, but that module can't be loaded without Apache2::*.
# Many non-BML callers (LJ::Lang::ml, LJ::Web, etc.) rely on these existing in any
# web context, so we define them here at load time.
#
# If Apache::BML is already loaded (mod_perl), we skip all of this.
unless ( defined &BML::ml ) {

    # BML::ml stub — gets redefined by BML::set_language()
    *BML::ml = sub { return "[ml_getter not defined]"; };

    # BML::ML tied hash support — must be defined before tie calls
    *BML::ML::TIEHASH = sub { return bless {}, $_[0]; };
    *BML::ML::FETCH   = sub { return "[ml_getter not defined]"; };
    *BML::ML::CLEAR   = sub { };

    # BML::Cookie tied hash support — must be defined before tie calls
    *BML::Cookie::TIEHASH = sub { return bless {}, $_[0]; };
    *BML::Cookie::FETCH   = sub {
        my ( $t, $key ) = @_;
        my $r = BML::get_request();
        unless ($BML::COOKIES_PARSED) {
            my $cookie_header = eval { $r->headers_in->{"Cookie"} } // '';
            foreach ( split( /;\s+/, $cookie_header ) ) {
                next unless /(.*)=(.*)/;
                my ( $name, $value ) = ( $1, $2 );
                push @{ $BML::COOKIE_M{ BML::durl($name) } ||= [] }, BML::durl($value);
            }
            $BML::COOKIES_PARSED = 1;
        }
        return $BML::COOKIE_M{$key} || [] if $key =~ s/\[\]$//;
        return ( $BML::COOKIE_M{$key} || [] )->[-1];
    };
    *BML::Cookie::STORE = sub {
        my ( $t, $key, $val ) = @_;
        my $etime     = 0;
        my $http_only = 0;
        ( $val, $etime, $http_only ) = @$val if ref $val eq "ARRAY";
        $etime = undef unless $val ne "";
        BML::set_cookie( $key, $val, $etime, undef, undef, $http_only );
    };
    *BML::Cookie::DELETE = sub { BML::Cookie::STORE( $_[0], $_[1], undef ); };
    *BML::Cookie::CLEAR  = sub {
        foreach ( keys %BML::COOKIE_M ) { BML::Cookie::STORE( $_[0], $_, undef ); }
    };
    *BML::Cookie::EXISTS   = sub { return defined $BML::COOKIE_M{ $_[1] }; };
    *BML::Cookie::FIRSTKEY = sub { keys %BML::COOKIE_M; return each %BML::COOKIE_M; };
    *BML::Cookie::NEXTKEY  = sub { return each %BML::COOKIE_M; };

    # Now tie the hashes
    tie %BML::ML,     'BML::ML'     unless tied %BML::ML;
    tie %BML::COOKIE, 'BML::Cookie' unless tied %BML::COOKIE;

    # Language scope
    $BML::ML_SCOPE = '' unless defined $BML::ML_SCOPE;

    # The BML::set_language function — redefines BML::ml and BML::ML::FETCH
    *BML::set_language = sub {
        my ( $lang, $getter ) = @_;
        my $apache_r = BML::get_request();
        if ($apache_r) {
            eval { $apache_r->notes->set( 'langpref', $lang ); };
        }

        if ( Apache::BML::is_initialized() ) {
            my $req = $Apache::BML::cur_req;
            $req->{'lang'} = $lang;
            $getter ||= $req->{'env'}->{'HOOK-ml_getter'};
        }

        no strict 'refs';
        if ( $lang eq "debug" ) {
            no warnings 'redefine';
            *{"BML::ml"} = sub {
                return $_[0];
            };
            *{"BML::ML::FETCH"} = sub {
                return $_[1];
            };
        }
        elsif ($getter) {
            no warnings 'redefine';
            *{"BML::ml"} = sub {
                my ( $code, $vars ) = @_;
                $code = $BML::ML_SCOPE . $code
                    if rindex( $code, '.', 0 ) == 0;
                return $getter->( $lang, $code, undef, $vars );
            };
            *{"BML::ML::FETCH"} = sub {
                my $code = $_[1];
                $code = $BML::ML_SCOPE . $code
                    if rindex( $code, '.', 0 ) == 0;
                return $getter->( $lang, $code );
            };
        }
    };

    *BML::set_language_scope = sub {
        $BML::ML_SCOPE = $_[0];
    };

    *BML::get_language_scope = sub {
        return $BML::ML_SCOPE;
    };

    *BML::get_language = sub {
        return undef unless Apache::BML::is_initialized();
        return $Apache::BML::cur_req->{'lang'};
    };

    *BML::get_language_default = sub {
        return "en" unless Apache::BML::is_initialized();
        return $Apache::BML::cur_req->{'env'}->{'DefaultLanguage'} || "en";
    };

    *BML::get_request = sub {
        return $Apache::BML::r if $Apache::BML::r;
        my $r = DW::Request->get;
        return unless $r;
        return DW::BML::RequestAdapter->new($r);
    };

    *BML::get_uri = sub {
        my $r   = BML::get_request() or return '';
        my $uri = $r->uri;
        $uri =~ s/\.bml$//;
        return $uri;
    };

    *BML::get_hostname = sub {
        my $r = BML::get_request() or return '';
        return $r->hostname;
    };

    *BML::get_method = sub {
        my $r = BML::get_request() or return '';
        return $r->method;
    };

    *BML::get_query_string = sub {
        my $r = BML::get_request() or return '';
        return scalar( $r->args );
    };

    *BML::get_path_info = sub {
        my $r = BML::get_request() or return '';
        return $r->path_info;
    };

    *BML::get_remote_ip = sub {
        my $r = BML::get_request() or return '';
        return $r->connection->client_ip;
    };

    *BML::get_remote_host = sub {
        my $r = BML::get_request() or return '';
        return $r->connection->remote_host;
    };

    *BML::get_client_header = sub {
        my $hdr = shift;
        my $r   = BML::get_request() or return '';
        return $r->headers_in->{$hdr};
    };

    *BML::ehtml = sub {
        my $a = $_[0];
        $a =~ s/\&/&amp;/g;
        $a =~ s/\"/&quot;/g;
        $a =~ s/\'/&\#39;/g;
        $a =~ s/</&lt;/g;
        $a =~ s/>/&gt;/g;
        return $a;
    };

    *BML::eurl = sub {
        my $a = $_[0];
        $a =~ s/([^a-zA-Z0-9_\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
        $a =~ tr/ /+/;
        return $a;
    };

    *BML::durl = sub {
        my ($a) = @_;
        $a =~ tr/+/ /;
        $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        return $a;
    };

    *BML::ebml = sub {
        my $a  = $_[0];
        my $ra = ref $a ? $a : \$a;
        $$ra =~ s/\(=(\w)/\(= $1/g;
        $$ra =~ s/(\w)=\)/$1 =\)/g;
        $$ra =~ s/<\?/&lt;?/g;
        $$ra =~ s/\?>/?&gt;/g;
        return if ref $a;
        return $a;
    };

    *BML::eall = sub {
        return BML::ebml( BML::ehtml( $_[0] ) );
    };

    *BML::noparse = sub {
        $Apache::BML::CodeBlockOpts{'raw'} = 1;
        return $_[0];
    };

    *BML::set_content_type = sub {
        return undef unless Apache::BML::is_initialized();
        $Apache::BML::cur_req->{'content_type'} = $_[0] if $_[0];
    };

    *BML::set_status = sub {
        my $r = $Apache::BML::r or return;
        $r->status( $_[0] + 0 ) if $_[0];
    };

    *BML::redirect = sub {
        return undef unless Apache::BML::is_initialized();
        $Apache::BML::cur_req->{'location'} = $_[0];
        BML::finish_suppress_all();
    };

    *BML::finish = sub {
        return undef unless Apache::BML::is_initialized();
        $Apache::BML::cur_req->{'stop_flag'} = 1;
    };

    *BML::suppress_headers = sub {
        return undef unless Apache::BML::is_initialized();
        BML::send_cookies();
        $Apache::BML::cur_req->{'env'}->{'NoHeaders'} = 1;
    };

    *BML::suppress_content = sub {
        return undef unless Apache::BML::is_initialized();
        $Apache::BML::cur_req->{'env'}->{'NoContent'} = 1;
    };

    *BML::finish_suppress_all = sub {
        BML::finish();
        BML::suppress_headers();
        BML::suppress_content();
    };

    *BML::http_response = sub {
        my ( $code, $msg ) = @_;
        my $r = $Apache::BML::r or return;
        $r->status($code);
        $r->content_type('text/html');
        $r->print($msg);
        BML::finish_suppress_all();
    };

    *BML::http_only = sub {
        my $ua = BML::get_client_header("User-Agent") // '';
        return 0 if $ua =~ /MSIE.+Mac_/;
        return 1;
    };

    *BML::get_scheme = sub {
        return undef unless Apache::BML::is_initialized();
        return $Apache::BML::cur_req->{'scheme'};
    };

    *BML::set_etag = sub {
        return undef unless Apache::BML::is_initialized();
        $Apache::BML::cur_req->{'etag'} = $_[0];
    };

    *BML::want_last_modified = sub {
        return undef unless Apache::BML::is_initialized();
        $Apache::BML::cur_req->{'want_last_modified'} = $_[0] if defined $_[0];
        return $Apache::BML::cur_req->{'want_last_modified'};
    };

    *BML::note_mod_time = sub {
        Apache::BML::note_mod_time( $Apache::BML::cur_req, $_[0] );
    };

    *BML::self_link = sub {
        my $newvars = shift;
        my $r       = $Apache::BML::r or return '';
        my $link    = $r->uri;
        my $form    = \%BMLCodeBlock::FORM;
        $link .= "?";
        foreach ( keys %$newvars ) {
            if ( !exists $form->{$_} ) { $form->{$_} = ""; }
        }
        foreach ( sort keys %$form ) {
            if ( defined $newvars->{$_} && !$newvars->{$_} ) { next; }
            my $val = $newvars->{$_} || $form->{$_};
            next unless $val;
            $link .= BML::eurl($_) . "=" . BML::eurl($val) . "&";
        }
        chop $link;
        return $link;
    };

    *BML::page_newurl = sub {
        my $page = $_[0];
        my @pair = ();
        foreach ( sort grep { $_ ne "page" } keys %BMLCodeBlock::FORM ) {
            push @pair, ( BML::eurl($_) . "=" . BML::eurl( $BMLCodeBlock::FORM{$_} ) );
        }
        push @pair, "page=$page";
        my $r = $Apache::BML::r or return '';
        return $r->uri . "?" . join( "&", @pair );
    };

    *BML::reset_cookies = sub {
        %BML::COOKIE_M       = ();
        $BML::COOKIES_PARSED = 0;
    };

    *BML::send_cookies = sub {
        my $req = shift();
        unless ($req) {
            return undef unless Apache::BML::is_initialized();
            $req = $Apache::BML::cur_req;
        }
        foreach ( values %{ $req->{'cookies'} } ) {
            $req->{'r'}->err_headers_out->add( "Set-Cookie" => $_ );
        }
        $req->{'cookies'} = {};
        $req->{'env'}->{'SentCookies'} = 1;
    };

    *BML::set_cookie = sub {
        return undef unless Apache::BML::is_initialized();
        my ( $name, $value, $expires, $path, $domain, $http_only ) = @_;
        my $req = $Apache::BML::cur_req;
        my $e   = $req->{'env'};
        $path   = $e->{'CookiePath'}   unless defined $path;
        $domain = $e->{'CookieDomain'} unless defined $domain;

        if ( $domain && ref $domain eq "ARRAY" ) {
            foreach (@$domain) {
                BML::set_cookie( $name, $value, $expires, $path, $_, $http_only );
            }
            return;
        }

        my ( $sec, $min, $hour, $mday, $mon, $year, $wday ) = gmtime($expires);
        $year += 1900;
        my @day    = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
        my @month  = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
        my $cookie = BML::eurl($name) . "=" . BML::eurl($value);

        unless ( defined $expires && $expires == 0 ) {
            $cookie .= sprintf( "; expires=$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
                $mday, $year, $hour, $min, $sec );
        }
        $cookie .= "; path=$path"     if $path;
        $cookie .= "; domain=$domain" if $domain;
        $cookie .= "; HttpOnly"       if $http_only && BML::http_only();

        if ( $e->{'SentCookies'} ) {
            $req->{'r'}->err_headers_out->add( "Set-Cookie" => $cookie );
        }
        else {
            $req->{'cookies'}->{"$name:$domain"} = $cookie;
        }

        if ( defined $expires ) {
            $BML::COOKIE_M{$name} = [$value];
        }
        else {
            delete $BML::COOKIE_M{$name};
        }
    };

    *BML::get_GET  = sub { return \%BMLCodeBlock::GET; };
    *BML::get_POST = sub { return \%BMLCodeBlock::POST; };
    *BML::get_FORM = sub { return \%BMLCodeBlock::FORM; };

    *BML::fill_template = sub {
        my ( $name, $vars ) = @_;
        die "Can't use BML::fill_template in non-BML context" unless $Apache::BML::cur_req;
        return Apache::BML::parsein( ${ $Apache::BML::cur_req->{'blockref'}->{ uc($name) } },
            $vars );
    };

    *BML::decl_params = sub { };    # stub — full impl only needed in BML pages

    *BML::register_block    = sub { };    # stub — only valid in look file context
    *BML::register_hook     = sub { };    # stub — only valid in conf file context
    *BML::set_config        = sub { };    # stub — only valid in conf file context
    *BML::register_language = sub { };    # stub
    *BML::register_isocode  = sub { };    # stub

    *BML::do_later = sub { return 0; };   # no-op under Plack

    *BML::paging      = sub { };              # stub
    *BML::page_newurl = sub { return ''; };
    *BML::randlist    = sub { return @_; };

    *BML::decide_language = sub {
        return undef unless Apache::BML::is_initialized();
        my $req = $Apache::BML::cur_req;
        my $env = $req->{'env'};

        my $uselang = $BMLCodeBlock::GET{'uselang'};
        if ( exists $env->{"Langs-$uselang"} || ( $uselang && $uselang eq "debug" ) ) {
            return $uselang;
        }

        my $r = $req->{'r'};
        my %lang_weight;
        my @langs =
            split( /\s*,\s*/, lc( eval { $r->headers_in->{"Accept-Language"} } // '' ) );
        my $winner_weight = 0.0;
        my $winner;
        foreach (@langs) {
            s/-\w+//;
            if (/(.+);q=(.+)/) {
                $lang_weight{$1} = $2;
            }
            else {
                $lang_weight{$_} = 1.0;
            }
            if ( $lang_weight{$_} > $winner_weight && defined $env->{"ISOCode-$_"} ) {
                $winner_weight = $lang_weight{$_};
                $winner        = $env->{"ISOCode-$_"};
            }
        }
        return $winner if $winner;
        return $LJ::LANGS[0] if @LJ::LANGS;
        return "en";
    };

    # Apache::BML package stubs needed by the BML:: functions above
    $Apache::BML::cur_req         = undef unless defined $Apache::BML::cur_req;
    $Apache::BML::r               = undef unless defined $Apache::BML::r;
    %Apache::BML::CodeBlockOpts   = ()    unless %Apache::BML::CodeBlockOpts;
    $Apache::BML::base_recent_mod = 0     unless $Apache::BML::base_recent_mod;
    %Apache::BML::FileModTime     = ()    unless %Apache::BML::FileModTime;

    *Apache::BML::is_initialized = sub {
        return $Apache::BML::cur_req ? 1 : 0;
    };

    *Apache::BML::note_mod_time = sub {
        my ( $req, $mod_time ) = @_;
        if ($req) {
            $req->{'most_recent_mod'} = $mod_time
                if $mod_time
                && ( !$req->{'most_recent_mod'} || $mod_time > $req->{'most_recent_mod'} );
        }
        else {
            $Apache::BML::base_recent_mod = $mod_time
                if $mod_time && $mod_time > $Apache::BML::base_recent_mod;
        }
    };

}

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

sub new {
    my ( $class, $r ) = @_;
    tie my %h, 'DW::BML::RequestAdapter::HeadersIn::Tie', $r;
    return bless [ $r, \%h ], $class;
}

use overload '%{}' => sub { return $_[0]->[1]; }, fallback => 1;

package DW::BML::RequestAdapter::HeadersIn::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH  { return $_[0]->{r}->header_in( $_[1] ) }
sub EXISTS { return defined $_[0]->{r}->header_in( $_[1] ) }
sub STORE  { }                                                 # read-only

###########################################################################
# HeadersOut: hash-like access to response headers
###########################################################################

package DW::BML::RequestAdapter::HeadersOut;

sub new {
    my ( $class, $r ) = @_;
    tie my %h, 'DW::BML::RequestAdapter::HeadersOut::Tie', $r;
    return bless [ $r, \%h ], $class;
}

use overload '%{}' => sub { return $_[0]->[1]; }, fallback => 1;

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

sub new {
    my ( $class, $r ) = @_;
    tie my %h, 'DW::BML::RequestAdapter::Notes::Tie', $r;

    # Use array-based object to avoid hash dereference triggering overload
    return bless [ $r, \%h ], $class;
}

sub set {
    my ( $self, $key, $value ) = @_;
    $self->[0]->note( $key, $value );
}

use overload '%{}' => sub { return $_[0]->[1]; }, fallback => 1;

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
