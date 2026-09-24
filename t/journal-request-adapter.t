#!/usr/bin/perl
# Characterizes exactly which methods LJ::make_journal, the data_handler:*
# hook invocation, and the s2_head_content_extra hook call on the
# DW::BML::RequestAdapter that DW::Controller::Journal.pm and LJ::S2.pm
# construct and thread through journal rendering. Test-only: no production
# code is changed here. See doc/BML-JOURNAL-ADAPTER.md for the resulting
# method table and native-replacement proposal.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use DW::Controller::Journal;
use DW::Request::Plack;
use DW::BML::RequestAdapter;

# --- Recording proxy: wraps any DW::BML::RequestAdapter (or object it
# returns, e.g. ::Connection/::HeadersIn) and logs every method called on
# it -- name, arg count/types, and return shape -- without changing its
# behavior. Installed by overriding DW::BML::RequestAdapter::new, so every
# construction site in production code (DW/Controller/Journal.pm:285,317)
# is captured transparently. ---
package RecordingAdapterProxy;

our @LOG;

sub _describe {
    my ($val) = @_;
    return 'undef' unless defined $val;
    return ref($val) if ref($val);
    return $val =~ /^-?\d+(?:\.\d+)?$/ ? 'number' : 'string';
}

sub wrap {
    my ( $real, $label ) = @_;
    return $real unless ref $real;
    return bless { real => $real, label => $label || ref($real) }, __PACKAGE__;
}

# AUTOLOAD-based classes don't answer ->can() truthfully by default; delegate
# to the wrapped object so callers that probe with ->can (as a production
# hook reasonably might, to tell an adapter from a plain DW::Request) see
# the same answer they would against the real, unwrapped object.
sub can {
    my ( $self, $method ) = @_;
    return UNIVERSAL::can( $self, $method ) || ( ref($self) && $self->{real}->can($method) );
}

our $AUTOLOAD;

sub AUTOLOAD {
    my $self   = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;
    return if $method eq 'DESTROY';

    my $real = $self->{real};
    my $ctx  = wantarray;
    my @ret  = $ctx ? $real->$method(@_) : ( scalar $real->$method(@_) );

    push @LOG,
        {
        on      => $self->{label},
        method  => $method,
        argc    => scalar(@_),
        argtype => [ map { _describe($_) } @_ ],
        rettype => [ map { _describe($_) } @ret ],
        };

    # Recursively wrap nested method-based adapter objects (Connection, Pool,
    # ErrHeadersOut) so calls made *on those* are captured too. HeadersIn/
    # HeadersOut/Notes overload %{} for tied ->{key} access instead of plain
    # method calls -- wrapping those in a plain-hashref proxy would break
    # that overload, so they're left unwrapped; their accessor call
    # (headers_out, notes, etc.) is still recorded above.
    my %safe_to_wrap = map { $_ => 1 } qw(
        DW::BML::RequestAdapter::Connection
        DW::BML::RequestAdapter::Pool
        DW::BML::RequestAdapter::ErrHeadersOut
    );
    @ret = map { $safe_to_wrap{ ref($_) // '' } ? wrap($_) : $_ } @ret;

    return $ctx ? @ret : $ret[0];
}

package main;

our $ADAPTER_NEW_CALLS = 0;

no warnings 'redefine';
local *DW::BML::RequestAdapter::new = sub {
    my ( $class, $r ) = @_;
    $ADAPTER_NEW_CALLS++;
    return RecordingAdapterProxy::wrap( bless( { r => $r }, 'DW::BML::RequestAdapter' ),
        'DW::BML::RequestAdapter' );
};

# Same harness as t/plack-journal-feeds.t: an HTTP-level controller harness
# that supplies a normal Plack request while bypassing vhost policy and
# DW::Routing, which are outside journal-rendering adapter usage.
sub journal_app {
    my ($user) = @_;
    return sub {
        my ($env) = @_;
        DW::Request->reset;
        my $r = DW::Request::Plack->new($env);
        $r->status(200);
        my $ret = DW::Controller::Journal->render(
            user => $user,
            uri  => $r->uri,
            args => $r->query_string,
        );
        $r->status($ret) if defined $ret && !ref $ret && $ret > 0;
        return $ret if ref $ret;
        return $r->res;
    };
}

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $entry = $u->t_post_fake_entry(
    subject => 'Adapter characterization subject',
    event   => 'Adapter characterization body',
);

local *DW::Routing::call = sub { return undef };
local *LJ::get_cap       = sub { return $_[1] eq 'userdomain' ? 1 : 0 };

subtest 'S2 HTML journal page render (LJ::make_journal now uses DW::Request directly)' => sub {

    # This devcontainer's test DB has no S2 style layers installed (same
    # constraint noted in t/plack-adult-content.t), so LJ::make_journal hits
    # an S2 compile error ("Undefined function modules_init()") before it can
    # produce real page content. Before the W8 conversion, that error path
    # still called OK on an adapter DW::Controller::Journal.pm:317
    # constructed; after it, LJ::S2.pm's $apache_r *is* the plain
    # DW::Request Journal.pm passes as $opts->{r} directly, so no adapter is
    # constructed for this flow at all -- proving :317's removal, not just
    # that OK still resolves the same way (status/content_type/note calls on
    # a plain DW::Request are byte-identical to the adapter's passthroughs
    # to that same object, so there's nothing else to regress here).
    @RecordingAdapterProxy::LOG = ();
    $ADAPTER_NEW_CALLS          = 0;
    test_psgi journal_app( $u->user ), sub {
        my $cb  = shift;
        my $res = $cb->( GET 'http://localhost/' );
        is( $res->code, 200,
'journal recent page responds the same as before (S2 error page, not real content, here)'
        );
    };
    is( $ADAPTER_NEW_CALLS, 0,
        'DW::BML::RequestAdapter::new is never called for the main journal-render path anymore' );
    is( scalar(@RecordingAdapterProxy::LOG),
        0, 'no adapter methods are recorded either, since none is constructed' );
};

subtest 'RSS feed render (still does not touch the adapter, still no adapter at all now)' => sub {
    @RecordingAdapterProxy::LOG = ();
    $ADAPTER_NEW_CALLS          = 0;
    test_psgi journal_app( $u->user ), sub {
        my $cb  = shift;
        my $res = $cb->( GET 'http://localhost/data/rss' );
        is( $res->code, 200, 'RSS feed renders (unchanged)' );
        like( $res->content,                qr/<rss\b/i,  'RSS root element present (unchanged)' );
        like( $res->header('Content-Type'), qr{text/xml}, 'RSS content type unchanged' );
    };

    # Before W8: RSS never called anything on the adapter it was nonetheless
    # given (data_handler:* isn't how rss/atom work; see doc). After W8:
    # there's no adapter construction at all on this path, so both counts
    # are zero, and the response itself (status/content-type/body) is
    # unchanged, exactly as expected since s2_run's status/content_type
    # calls were always pure passthroughs to this same DW::Request object.
    is( $ADAPTER_NEW_CALLS, 0, 'no DW::BML::RequestAdapter is constructed for RSS rendering' );
    is( scalar(@RecordingAdapterProxy::LOG), 0, 'and so zero adapter methods are recorded' );
};

subtest 'FOAF request via a locally-registered data_handler:foaf hook' => sub {

    # Unlike rss/atom, FOAF has no built-in handler anywhere in this tree
    # (grep -rn foaf cgi-bin/LJ/S2.pm cgi-bin/LJ/Feed.pm: no matches) -- it is
    # exactly the kind of request the data_handler:* extension point exists
    # for. Register a disposable hook to exercise Journal.pm's OWN adapter
    # construction (DW/Controller/Journal.pm:285), which W8 explicitly does
    # NOT touch (held external ABI) -- this must still construct an adapter,
    # unlike the main render path above.
    $ADAPTER_NEW_CALLS = 0;
    local $LJ::HOOKS{'data_handler:foaf'};
    my @handler_args;
    LJ::Hooks::register_hook(
        'data_handler:foaf',
        sub {
            my ( $user, $data_path ) = @_;
            push @handler_args, { user => $user, data_path => $data_path };
            return sub {
                my ($adapter) = @_;
                $adapter->content_type('application/rdf+xml');
                $adapter->print('<rdf:RDF></rdf:RDF>');
                return;
            };
        }
    );

    @RecordingAdapterProxy::LOG = ();
    test_psgi journal_app( $u->user ), sub {
        my $cb  = shift;
        my $res = $cb->( GET 'http://localhost/data/foaf' );
        is( $res->code, 200, 'FOAF request handled by the registered data_handler:foaf hook' );
        like( $res->content, qr/<rdf:RDF>/, 'FOAF hook output reaches the response body' );
    };
    is( scalar(@handler_args),    1,        'data_handler:foaf hook fired exactly once' );
    is( $handler_args[0]->{user}, $u->user, 'hook received the journal username' );
    is( $ADAPTER_NEW_CALLS, 1,
        'data_handler:* (Journal.pm:285) still constructs exactly one adapter, untouched by W8' );
    ok( scalar(@RecordingAdapterProxy::LOG) > 0,
        'data_handler hook path called at least one adapter method' );
    diag(
        'data_handler:foaf adapter methods: ' . join(
            ', ',
            do {
                my %seen;
                grep { !$seen{$_}++ } map { $_->{method} } @RecordingAdapterProxy::LOG;
            }
        )
    );
};

subtest 'LJ::S2::Page: adapter on the marked journal path, plain DW::Request on preview' => sub {

    # LJ::S2::Page runs directly in this environment (confirmed by probe: it
    # needs only $u->{_s2styleid}/_journalbase and a minimal $opts, none of
    # the style-layer compilation the full make_journal/s2_run pipeline
    # needs), so drive the *real* production function instead of re-
    # implementing its call convention. DW::Controller::Entry's journal-
    # style preview (Entry.pm ~1806-1813) calls this same LJ::S2::Page with
    # a plain DW::Request in $opts->{r} and no 's2_hook_adapter' marker --
    # that path must keep receiving a plain DW::Request, unchanged from
    # before W8, while DW::Controller::Journal.pm's marked $opts must keep
    # receiving a DW::BML::RequestAdapter, matching what it always got.
    $u->{_s2styleid}   = 0;
    $u->{_journalbase} = $u->journal_base;

    local $LJ::HOOKS{'s2_head_content_extra'};
    my @hook_args;
    LJ::Hooks::register_hook(
        's2_head_content_extra',
        sub {
            my ( $remote, $r ) = @_;
            push @hook_args, $r;
            $r->connection->client_ip if $r->can('connection');    # only the adapter has this
            return '';
        }
    );

    DW::Request->reset;
    my $plack_r = DW::Request::Plack->new(
        { REQUEST_METHOD => 'GET', PATH_INFO => '/', 'psgi.url_scheme' => 'http' } );

    # Journal case: DW::Controller::Journal.pm-shaped opts (marked).
    @RecordingAdapterProxy::LOG = ();
    $ADAPTER_NEW_CALLS          = 0;
    my $journal_opts = { r => $plack_r, getargs => {}, s2_hook_adapter => 1 };
    ok( eval { LJ::S2::Page( $u, $journal_opts ); 1 }, 'LJ::S2::Page runs for journal-shaped opts' )
        or diag("Page died: $@");
    is( scalar(@hook_args), 1, 'hook fired once for the journal case' );
    isa_ok( $hook_args[0]->{real},
        'DW::BML::RequestAdapter',
        'journal case: hook receives a DW::BML::RequestAdapter (via the recording wrapper)' );
    is( $ADAPTER_NEW_CALLS, 1, 'exactly one adapter is constructed for the journal case' );
    ok(
        ( grep { $_->{on} eq 'DW::BML::RequestAdapter::Connection' } @RecordingAdapterProxy::LOG ),
        'and connection->client_ip works on it'
    );

    # Preview case: DW::Controller::Entry-shaped opts (unmarked).
    @hook_args                  = ();
    @RecordingAdapterProxy::LOG = ();
    $ADAPTER_NEW_CALLS          = 0;
    my $preview_opts = { r => $plack_r, getargs => {} };
    ok( eval { LJ::S2::Page( $u, $preview_opts ); 1 }, 'LJ::S2::Page runs for preview-shaped opts' )
        or diag("Page died: $@");
    is( scalar(@hook_args), 1, 'hook fired once for the preview case' );
    isa_ok( $hook_args[0], 'DW::Request::Plack',
        'preview case: hook receives the plain DW::Request, not an adapter' );
    is( $ADAPTER_NEW_CALLS, 0, 'zero adapters are constructed for the preview case' );
};

subtest 'no_control_strip note reaches DW::Hooks::NavStrip via plain DW::Request::note' => sub {

    # LJ::S2.pm:118-119 used to write this via the adapter's tied-hash sugar
    # ($apache_r->notes->{'no_control_strip'} = 1, which itself just forwarded
    # to $self->{r}->note(...) -- see DW::BML::RequestAdapter::Notes::Tie::STORE).
    # W8 changes it to call $apache_r->note('no_control_strip', 1) directly,
    # now that $apache_r is the plain DW::Request. DW::Hooks::NavStrip.pm:44
    # already reads it via $r->note('no_control_strip') on the real request
    # object (DW::Request->get), never through any adapter -- confirm the
    # write/read pair still round-trips through the same object.
    DW::Request->reset;
    my $r = DW::Request::Plack->new(
        { REQUEST_METHOD => 'GET', PATH_INFO => '/', 'psgi.url_scheme' => 'http' } );

    # Self-viewing-own-journal, with LJ::is_enabled forced on, makes
    # DW::Hooks::NavStrip.pm's show_control_strip hook (already registered
    # at module load, not a test double) return a truthy display mask by
    # default (LJ::User::Permissions::control_strip_display defaults to "all
    # options checked" with no explicit prop). This lets the "before" call
    # below be a meaningful sanity check, not a vacuous undef from unrelated
    # missing setup, so the "after" undef is provably caused by the note.
    LJ::set_remote($u);
    LJ::set_active_journal($u);
    local *LJ::is_enabled = sub { return $_[0] eq 'control_strip' ? 1 : 0; };

    ok( !$r->note('no_control_strip'), 'note is unset before LJ::S2.pm:119 runs' );
    ok( LJ::Hooks::run_hook('show_control_strip'),
        'control strip hook returns a truthy display mask before the note is set (sanity check)' );

    $r->note( 'no_control_strip', 1 );    # exactly what LJ::S2.pm:119 now calls
    is( $r->note('no_control_strip'), 1, 'note round-trips through plain DW::Request::note' );
    is( LJ::Hooks::run_hook('show_control_strip'),
        undef, 'DW::Hooks::NavStrip suppresses the control strip once the note is set' );
};

done_testing;
