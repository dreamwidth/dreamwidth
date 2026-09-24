# Characterize the read-only entry picker before separating the legacy editor.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use URI;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use Plack::Middleware::DW::RequestWrapper;
use LJ::Test qw(temp_user temp_comm);
plan skip_all => 'Picker integration requires a development server' unless $LJ::IS_DEV_SERVER;
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $owner    = temp_user();
my $outsider = temp_user();
my $groupid  = $owner->create_trust_group( groupname => 'Picker custom security' );
$owner->update_self( { status => "A" } );
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryPickerBaseline';

# Use distinct event dates so latest/default-five assertions cannot pass on
# arbitrary entries tied to the same second.
my @entries = map {
    my %result;
    LJ::do_request(
        {
            mode      => 'postevent',
            ver       => $LJ::PROTOCOL_VER,
            user      => $owner->user,
            subject   => "Picker subject $_",
            event     => "Picker body $_",
            year      => 2020,
            mon       => 1,
            day       => $_,
            hour      => 12,
            min       => 0,
            security  => $_ == 1 ? 'private' : $_ == 2 || $_ == 3 ? 'usemask' : 'public',
            allowmask => $_ == 2 ? 1 : $_ == 3 ? 1 << $groupid : undef,
        },
        \%result,
        { noauth => 1, nomod => 1 }
    );
    die "Picker fixture post failed: $result{errmsg}" unless $result{success} eq 'OK';
    LJ::Entry->new( $owner, jitemid => $result{itemid} );
} 1 .. 6;
my %ids             = map { $_->ditemid => 1 } @entries;
my %original_bodies = map { $_->ditemid => $_->event_raw } @entries;

sub picker_forms {
    return HTML::Form->parse( $_[0], 'http://localhost/editjournal' );
}

sub entry_ids {
    my @ids = sort { $a <=> $b } map { $_->value('itemid') }
        grep { $_->find_input('itemid') } picker_forms( $_[0] );
    return @ids;
}
test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    for my $path ( '/editjournal', '/editjournal.bml' ) {
        my $res = $cb->( GET $path);
        is( $res->code, 200, "$path renders directly" );
        unlike(
            $res->content,
            qr/undef error|DieObject=|BML ERROR/,
            'picker is not an exception response'
        );
        like( $res->content, qr/class="entry-picker"/, 'native picker form renders' );
        my ($form) = grep { $_->find_input('selecttype') } picker_forms( $res->content );
        ok( $form, 'actual selector form exists' ) or next;
        is( $form->value('selecttype'), 'last', 'selector defaults to latest entry' );
        is( $form->value('howmany'),    20,     'recent selector defaults to twenty' );
        my @listed = entry_ids( $res->content );
        is( scalar @listed, 5, 'initial page lists five entries' );
        is_deeply(
            \@listed,
            [ sort { $a <=> $b } map { $_->ditemid } @entries[ 1 .. 5 ] ],
            'initial page contains exactly the five newest dated entries'
        );

        # Exercise the alias as a receiver too; rendered legacy actions point to
        # the extensionless route regardless of the incoming URL.
        $form->action( 'http://localhost' . $path );
        $form->value( 'selecttype', 'lastn' );
        $form->value( 'howmany',    6 );
        $res = $cb->( $form->click );
        is( $res->code, 200, 'read-only selector POST renders multiple matches' );
        is_deeply(
            [ entry_ids( $res->content ) ],
            [ sort { $a <=> $b } keys %ids ],
            'recent selector returns all exact personal entry IDs, including private'
        );
        like( $res->content, qr/Picker body 1/,    'owner sees private entry summary' );
        like( $res->content, qr/Picker subject 6/, 'result retains subject' );
        like(
            $res->content,
            qr/entry-picker-security-private/,
            'private entries retain the private icon'
        );
        like(
            $res->content,
            qr/<img\b[^>]*\balt=["']Private entry["'][^>]*\btitle=["']Private entry["'][^>]*>/,
            'private icon renders meaningful image alt and title labels'
        );
        like(
            $res->content,
qr/<img\b[^>]*\balt=["']Friends-only entry["'][^>]*\btitle=["']Friends-only entry["'][^>]*>/,
            'friends icon renders meaningful image alt and title labels'
        );
        like(
            $res->content,
qr/<img\b[^>]*\balt=["']Custom access entry["'][^>]*\btitle=["']Custom access entry["'][^>]*>/,
            'custom icon renders meaningful image alt and title labels'
        );
        unlike( $res->content, qr/<b>XXX<\/b>/,
            'security icons never render an invalid image type' );
        like(
            $res->content,
            qr/entry-picker-security-protected/,
            'friends entries retain the protected icon'
        );
        like(
            $res->content,
            qr/entry-picker-security-groups/,
            'custom entries retain the groups icon'
        );
        unlike(
            $res->content,
            qr/entry-picker-security-public/,
            'public entries have no security marker'
        );
        $res = $cb->(
            POST $path . '?usejournal=',
            Content =>
                [ mode => 'edit', selecttype => 'lastn', howmany => 6, usejournal => $owner->user ]
        );
        is_deeply(
            [ entry_ids( $res->content ) ],
            [ sort { $a <=> $b } keys %ids ],
            'empty GET usejournal falls through to the nonempty POST context'
        );
        $res = $cb->( GET $path . '?mode=edit&usejournal=' . $owner->user );
        is( $res->code, 302, 'no-item edit-mode GET preserves the legacy picker redirect' );
        is( $res->header('Location'),
            '/editjournal', 'legacy edit-mode redirect drops selection context' );
        $form->value( 'selecttype', 'last' );
        $res = $cb->( $form->click );
        is( $res->code, 302, 'single match redirects to editor entry point' );
        my $location = URI->new_abs( $res->header('Location') || '', 'http://localhost' );
        is( $location->path, '/editjournal', 'single match retains existing edit URL' );
        my %query = $location->query_form;
        is(
            $query{itemid},
            $entries[-1]->ditemid,
            'last selector redirects to the exact newest dated entry'
        );
        $form->value( 'selecttype', 'day' );
        $form->value( 'year',       1970 );
        $form->value( 'month',      1 );
        $form->value( 'day',        1 );
        $res = $cb->( $form->click );
        like(
            $res->content,
            qr/No entries match the criteria/,
            'empty date has criteria-specific message'
        );
        is( scalar entry_ids( $res->content ), 0, 'empty date renders no edit forms' );
    }
    my $res = $cb->( GET '/editjournal?authas=' . $outsider->user );
    like(
        $res->content,
        qr/You couldn.t be authenticated as the specified account/,
        'unauthorized authas is denied'
    );
    is( scalar entry_ids( $res->content ), 0, 'unauthorized authas exposes no entry forms' );
    $res = $send->( GET '/editjournal' );
    is( scalar entry_ids( $res->content ), 0, 'logged-out visitor sees no entry forms' );
    unlike( $res->content, qr/Picker body/, 'logged-out visitor sees no entry summaries' );
    LJ::Entry::reset_singletons();

    for my $entry (@entries) {
        my $fresh = LJ::Entry->new( $owner, ditemid => $entry->ditemid );
        ok( $fresh->valid, 'read-only selection leaves entry present' );
        is(
            $fresh->event_raw,
            $original_bodies{ $entry->ditemid },
            'selection leaves persisted body unchanged'
        );
    }
};

test_psgi $app, sub {
    my $send  = shift;
    my $cb    = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    my $comm  = temp_comm();
    my $empty = temp_comm();
    LJ::set_rel( $comm,  $owner, 'A' );
    LJ::set_rel( $empty, $owner, 'A' );
    $outsider->update_self( { status => 'A' } );
    my $own_entry = $owner->t_post_fake_comm_entry( $comm, body => 'Manager community body' );
    my $other_entry =
        $outsider->t_post_fake_comm_entry( $comm, body => 'Other poster community body' );
    my @expected = sort { $a <=> $b } ( $own_entry->ditemid, $other_entry->ditemid );
    my $modern   = $cb->( GET '/entry/' . $comm->user . '/' . $other_entry->ditemid . '/edit' );
    is( $modern->code, 200, 'modern maintainer response status characterized' );
    like( $modern->content, qr/entry-maintainer-form/,
        'modern route renders restricted maintainer form' );
    like(
        $modern->content,
        qr/name=["']action:savemaintainer/,
        'modern route has maintainer save control'
    );
    my $legacy = $cb->(
        GET '/editjournal.bml?usejournal=' . $comm->user . '&itemid=' . $other_entry->ditemid );
    is( $legacy->code, 302, 'legacy route redirects instead of rendering inline' );
    is(
        URI->new( $legacy->header('Location') )->path,
        '/entry/' . $comm->user . '/' . $other_entry->ditemid . '/edit',
        'legacy route redirects to the native maintainer edit URL'
    );

    LJ::set_logprop( $comm, $other_entry->jitemid, { opt_preformatted => 1 } );
    LJ::Entry::reset_singletons();
    my $seeded_entry     = LJ::Entry->new( $comm, ditemid => $other_entry->ditemid );
    my $original_body    = $seeded_entry->event_raw;
    my $original_subject = $seeded_entry->subject_raw;
    my $unrelated        = $seeded_entry->prop('opt_preformatted') || '';
    is( $unrelated, 1, 'fixture seeds a nondefault unrelated property' );

    # A stale-tab-style old-schema POST to the legacy itemid URL must never
    # silently save: it renders the subject/body recovery page instead.
    my $legacy_post_res = $cb->(
        POST '/editjournal.bml?usejournal=' . $comm->user . '&itemid=' . $other_entry->ditemid,
        Content => [
            'action:savemaintainer'              => 1,
            prop_adult_content_maintainer_reason => 'legacy carryover reason attempt',
            prop_adult_content_maintainer        => 1,
        ]
    );
    is( $legacy_post_res->code, 200,
        'legacy itemid POST returns the recovery page, not a redirect' );
    like(
        $legacy_post_res->content,
        qr/Nothing here was posted or saved/i,
        'legacy itemid POST renders the explicit recovery notice'
    );
    LJ::Entry::reset_singletons();
    my $unsaved_entry = LJ::Entry->new( $comm, ditemid => $other_entry->ditemid );
    is( $unsaved_entry->prop('adult_content_maintainer_reason') || '',
        '', 'legacy itemid POST does not actually save maintainer properties' );

    LJ::set_logprop(
        $comm,
        $other_entry->jitemid,
        {
            adult_content_maintainer  => 'concepts',
            opt_nocomments_maintainer => 1,
            adult_content             => 'explicit',
            opt_nocomments            => 0,
        }
    );
    LJ::Entry::reset_singletons();
    my $native_url = '/entry/' . $comm->user . '/' . $other_entry->ditemid . '/edit';
    my $native_get = $cb->( GET $native_url );
    is( $native_get->code, 200, 'authorized manager receives native maintainer form' );
    like( $native_get->content, qr/entry-maintainer-form/, 'native form is property-only surface' );
    is( scalar( () = $native_get->content =~ m{<h1(?:\s[^>]*)?>Administrator Override</h1>}g ),
        1, 'native maintainer form has one accessible page heading' );
    like(
        $native_get->content,
        qr/<option value="concepts" selected>/,
        'native form selects an existing nondefault adult override'
    );
    like(
        $native_get->content,
        qr/<input(?=[^>]*name="prop_opt_nocomments_maintainer")(?=[^>]*checked="1")[^>]*>/,
        'native form checks an existing nondefault comments override'
    );
    like(
        $native_get->content,
        qr/Poster's Setting \(Age 18\+\)/,
        "native form reports the poster’s exact inherited age rating"
    );
    my ($native_form) = grep { $_->find_input('action:savemaintainer') }
        HTML::Form->parse( $native_get->content, 'http://localhost' . $native_url );
    ok( $native_form, 'native rendered maintainer save form exists' );
    my $explicit_action =
          '/entry/'
        . $comm->user . '/'
        . $other_entry->ditemid
        . '/edit?encoded=one%2Ftwo&repeated=first&repeated=second';
    my $explicit_app = Plack::Middleware::DW::RequestWrapper->wrap(
        sub {
            my $r = DW::Request->get;
            DW::Controller::Entry::_render_maintainer_form( $other_entry, $comm, $owner,
                action => $explicit_action );
            $r->status(200);
            return $r->res;
        }
    );
    test_psgi $explicit_app, sub {
        my $request  = shift;
        my $response = $request->( GET '/__test_maintainer_action' );
        is( $response->code, 200, 'extracted maintainer renderer returns a real response' );
        my ($explicit_form) = grep { $_->find_input('action:savemaintainer') }
            HTML::Form->parse( $response->content, 'http://localhost' . $native_url );
        ok( $explicit_form, 'extracted maintainer renderer returns the real property-only form' );
        is(
            $explicit_form->action,
            'http://localhost' . $explicit_action,
            'extracted renderer preserves an explicit canonical action and raw query'
        );
        ok( !$explicit_form->find_input('subject') && !$explicit_form->find_input('event'),
            'extracted renderer remains property-only' );
    };
    $native_form->value( 'prop_adult_content_maintainer_reason', 'native reason marker' );
    $native_form->value( 'prop_adult_content_maintainer',        'concepts' );
    $native_form->value( 'prop_opt_nocomments_maintainer',       1 );
    $native_form->action( 'http://localhost' . $native_url );
    my $native_save = $cb->( $native_form->click('action:savemaintainer') );
    is( $native_save->code, 302, 'native property-only save redirects after success' );
    LJ::Entry::reset_singletons();
    my $native_saved = LJ::Entry->new( $comm, ditemid => $other_entry->ditemid );
    is(
        $native_saved->prop('adult_content_maintainer_reason'),
        'native reason marker',
        'native save persists reason'
    );
    is( $native_saved->prop('adult_content_maintainer'), 'concepts', 'native save persists level' );
    is( $native_saved->prop('opt_nocomments_maintainer') || 0,
        1, 'native save persists comments override' );
    is( $native_saved->event_raw,   $original_body,    'native save preserves foreign body' );
    is( $native_saved->subject_raw, $original_subject, 'native save preserves foreign subject' );
    is( $native_saved->prop('opt_preformatted') || '',
        $unrelated, 'native save preserves unrelated property' );
    my $native_reload = $cb->( GET $native_url );
    like(
        $native_reload->content,
        qr/native reason marker/,
        'fresh native GET reloads saved reason'
    );
    like(
        $native_reload->content,
        qr/<option value="concepts" selected>/,
        'fresh native GET retains selected adult override'
    );
    like(
        $native_reload->content,
        qr/<input(?=[^>]*name="prop_opt_nocomments_maintainer")(?=[^>]*checked="1")[^>]*>/,
        'fresh native GET retains checked comments override'
    );
    LJ::set_logprop( $comm, $other_entry->jitemid, { opt_nocomments => 1 } );
    LJ::Entry::reset_singletons();
    my $poster_disabled = $cb->( GET $native_url );
    unlike(
        $poster_disabled->content,
        qr/name="prop_opt_nocomments_maintainer"/,
        'native form omits the comments override when the poster disabled comments'
    );
    LJ::Entry::reset_singletons();
    is(
        LJ::Entry->new( $comm, ditemid => $other_entry->ditemid )->event_raw,
        'Other poster community body',
        'read-only comparison preserves persisted body'
    );

    for my $key ( 'usejournal', 'journal' ) {
        my $res = $cb->( GET '/editjournal?' . $key . '=' . $comm->user );
        is_deeply( [ entry_ids( $res->content ) ],
            \@expected, "maintainer sees both posters through $key context" );
        unlike(
            $res->content,
            qr/<option value=['"]\Q@{[ $comm->user ]}\E/,
            'personal authas selector omits managed communities'
        );
        like(
            $res->content,
            qr/Other poster community body/,
            'visible other-poster summary is retained'
        );
        like(
            $res->content,
            qr/entry-picker-poster.*lj:user=['"]\Q@{[ $outsider->user ]}\E/s,
            'community poster uses a linked journal identity'
        );
        like(
            $res->content,
            qr/entry-picker-poster">Poster:/,
            'community poster has the legacy translated label'
        );
        for my $form ( grep { $_->find_input('itemid') } picker_forms( $res->content ) ) {
            my %query = $form->action->query_form;
            is( $query{usejournal}, $comm->user, 'entry form preserves community context' );
        }
    }
    my $res = $cb->(
        POST '/editjournal?usejournal=' . $comm->user,
        Content => [
            mode       => 'edit',
            selecttype => 'lastn',
            howmany    => 20,
            usejournal => $empty->user
        ]
    );
    is_deeply( [ entry_ids( $res->content ) ],
        \@expected, 'GET usejournal takes precedence over POST' );
    $res = $cb->(
        POST '/editjournal?journal=' . $empty->user,
        Content => [
            mode       => 'edit',
            selecttype => 'lastn',
            howmany    => 20,
            usejournal => $comm->user
        ]
    );
    is_deeply( [ entry_ids( $res->content ) ],
        \@expected, 'POST usejournal takes precedence over journal alias' );
    $res = $cb->(
        POST '/editjournal',
        Content => [
            mode       => 'edit',
            selecttype => 'lastn',
            howmany    => 20,
            usejournal => $empty->user
        ]
    );
    like(
        $res->content,
        qr/The selected journal has no entries/,
        'empty recent selection has journal-specific message'
    );
    $res = $cb->( GET '/editjournal?authas=' . $comm->user );
    is( scalar entry_ids( $res->content ),
        0, 'managed community cannot impersonate individual picker actor' );
    $comm->update_self( { statusvis => 'O' } );
    $res = $cb->(
        POST '/editjournal',
        Content => [
            mode       => 'edit',
            selecttype => 'lastn',
            howmany    => 20,
            usejournal => $comm->user
        ]
    );
    is_deeply( [ entry_ids( $res->content ) ],
        \@expected, 'read-only community remains selectable by manager' );
    $comm->update_self( { statusvis => 'V' } );
    $res =
        $cb->( GET '/editjournal?usejournal=' . $comm->user . '&itemid=' . $other_entry->ditemid );
    is( $res->code, 302,
        'manager other-poster editor now redirects to the native maintainer edit URL' );
    is(
        URI->new( $res->header('Location') )->path,
        '/entry/' . $comm->user . '/' . $other_entry->ditemid . '/edit',
        'manager other-poster editor redirect targets the native maintainer edit URL'
    );

    # itemid must override picker mode even when the action comes from the
    # editor's JavaScript submit_value field. This POST never saves
    # regardless of form-auth token, so this no longer reaches an "Invalid
    # form" CSRF rejection: it renders the same recovery page every other
    # old-schema itemid POST does.
    LJ::Entry::reset_singletons();
    my $before_maintainer =
        LJ::Entry->new( $comm, ditemid => $other_entry->ditemid )->prop('opt_nocomments_maintainer')
        || 0;
    for my $token ( undef, 'invalid' ) {
        for my $action ( 'action:delete', 'action:savemaintainer' ) {
            my @payload = (
                mode                           => 'init',
                itemid                         => $other_entry->ditemid,
                submit_value                   => $action,
                prop_opt_nocomments_maintainer => 0
            );
            push @payload, lj_form_auth => $token if defined $token;
            for my $path ( '/editjournal', '/editjournal.bml' ) {
                $res = $cb->( POST $path . '?usejournal=' . $comm->user, Content => \@payload );
                is( $res->code, 200,
"$path itemid $action POST returns the recovery page regardless of the form-auth token"
                );
                like(
                    $res->content,
                    qr/Nothing here was posted or saved/i,
                    "$path itemid $action POST renders the explicit recovery notice"
                );
                ok( !$res->header('Location'),
                    'recovery response does not redirect away its body' );
                LJ::Entry::reset_singletons();
                my $fresh_entry = LJ::Entry->new( $comm, ditemid => $other_entry->ditemid );
                ok( $fresh_entry->valid, 'recovery POST cannot delete another poster entry' );
                is( $fresh_entry->prop('opt_nocomments_maintainer') || 0,
                    $before_maintainer, 'recovery POST cannot change maintainer properties' );
            }
        }
    }
};

subtest 'picker resolves its relocated language keys with a request getter' => sub {
    no warnings 'redefine';
    local *LJ::Lang::get_text = sub {
        my ( $lang, $code ) = @_;
        return "picker-key:$code";
    };
    test_psgi $app, sub {
        my $send = shift;
        my $cb  = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
        my $res = $cb->( GET '/editjournal' );
        like(
            $res->content,
            qr/picker-key:\/editjournal\.tt\.title/,
            'normal picker render resolves its title through the template key'
        );
        $res = $cb->( GET '/editjournal?usejournal=' . $outsider->user );
        like(
            $res->content,
            qr/picker-key:\/editjournal\.tt\.error\.nocomm/,
            'picker error response resolves through the template error key'
        );
        unlike( $res->content, qr/editjournal\.bml\./,
            'picker never asks the getter for a retired BML page key' );
    };
};

done_testing;
