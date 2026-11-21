# t/plack-create-setup-location.t
#
# Account setup can refresh country-dependent choices without saving the form.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::TokeParser;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'setupLocationTest';

my $u       = temp_user();
my $inviter = temp_user();
my $comm    = temp_comm();
$_->update_self( { status => 'A' } ) for ( $u, $inviter, $comm );
$u->set_prop( country => 'GB' );
$u->set_prop( state   => 'Northshire' );
$u->set_prop( city    => 'Original city' );
$u->set_bio('Original bio');

# Read the actual rendered fields, including hidden fields and selected options.
# Browser coverage separately checks visibility and native no-JS submission.
sub fields {
    my ($html) = @_;
    my $p = HTML::TokeParser->new( \$html );
    my %out;
    while ( my $tag = $p->get_tag( 'input', 'select', 'textarea' ) ) {
        my $a = $tag->[1];
        next unless $a->{name};
        if ( $tag->[0] eq 'input' ) {
            next if ( $a->{type} || '' ) =~ /^(?:submit|checkbox|radio)$/;
            $out{ $a->{name} } = $a->{value} || '';
        }
        elsif ( $tag->[0] eq 'textarea' ) {
            $out{ $a->{name} } = $p->get_text('/textarea');
        }
        else {
            my $name = $a->{name};
            $out{$name} = '';
            while ( my $option = $p->get_tag( 'option', '/select' ) ) {
                last if $option->[0] eq '/select';
                $out{$name} = $option->[1]{value} || ''
                    if exists $option->[1]{selected};
            }
        }
    }
    return \%out;
}

# Start a new request first: the app's cached user object can hold older props.
sub stored {
    LJ::start_request();
    my $fresh = LJ::load_userid( $u->id, 1 );
    return [ $fresh->name_orig, map { $fresh->prop($_) || '' } qw(gender country state city) ];
}

my $spam_checks = 0;
my $hooks       = \&LJ::Hooks::run_hooks;
no warnings 'redefine';
local *LJ::Hooks::run_hooks = sub {
    if ( $_[0] eq 'spam_check' ) { $spam_checks++; return; }
    return $hooks->(@_);
};
use warnings 'redefine';

# A baseline may save and redirect when it mistakes Refresh for Save. Record
# that failure, then stop that scenario before submitting absent form controls.
sub refreshed_fields {
    my ($res) = @_;
    diag( 'Refresh response Location: ' . ( $res->header('Location') // '(none)' ) )
        if $res->is_redirect;
    return unless is( $res->code, 200, 'refresh returns the editable form' );
    my $form = fields( $res->content );
    return unless ok( $form->{lj_form_auth}, 'refresh retains a signed form token' );
    return $form;
}

my $storage_mode;
my $reload_config = \&LJ::Config::start_request_reload;
no warnings 'redefine';
local *LJ::Config::start_request_reload = sub {
    $reload_config->(@_);

    # Keep real reloads, but install the test mode before request dispatch.
    if ( defined $storage_mode ) {
        $LJ::COUNTRIES_WITH_REGIONS{US} =
            { %{ $LJ::COUNTRIES_WITH_REGIONS{US} }, save_region_code => $storage_mode, };
    }
};
use warnings 'redefine';

with_fake_memcache {
    test_psgi $app, sub {
        my $client = shift;
        my $cb     = sub {
            my $res = $client->(@_);
            is( $LJ::COUNTRIES_WITH_REGIONS{US}{save_region_code},
                $storage_mode, 'request retains intended storage mode' )
                if defined $storage_mode;
            return $res;
        };
        my $url = 'http://localhost/create/setup?as=' . $u->user;
        subtest 'country refresh and explicit Save' => sub {
            my $res = $cb->( GET $url );
            is( $res->code, 200, 'real setup form renders' );
            my $form = fields( $res->content );
            ok( $form->{lj_form_auth}, 'form has a signed token' );
            my $before  = stored();
            my $bio     = 'Unsaved <iframe src="https://example.invalid/"></iframe> & text';
            my %attempt = (
                %$form,
                name            => 'Unsaved <name> & "quotes"',
                gender          => 'F',
                bio             => $bio,
                country         => 'US',
                stateother      => 'Texas',
                city            => 'Unsaved <city> & text',
                interests_other => 'unsaved interest',
                inviter_trust   => $inviter->id,
                inviter_watch   => $inviter->id,
                inviter_join    => $comm->id,
                refresh_country => 'Update state choices',
            );

            my $embed_calls = 0;
            {
                no warnings 'redefine';
                local *LJ::EmbedModule::parse_module_embed = sub { $embed_calls++; };
                $res = $cb->( POST $url, Content => [%attempt] );
            }
            is( $res->code,   200, 'refresh stays on setup' );
            is( $spam_checks, 0,   'refresh does not invoke spam hooks' );
            is( $embed_calls, 0,   'refresh does not process embeds' );
            is_deeply( stored(), $before, 'refresh leaves stored name, gender and location alone' );
            is( LJ::load_userid( $u->id, 1 )->bio, 'Original bio', 'bio is not saved' );
            ok( !$u->trusts($inviter),  'refresh does not trust inviter' );
            ok( !$u->watches($inviter), 'refresh does not watch inviter' );
            ok( !$u->member_of($comm),  'refresh does not join community' );
            return unless $form = refreshed_fields($res);
            is( $form->{country},    'US', 'submitted country is redisplayed' );
            is( $form->{stateother}, '',   'old text state is cleared for new country' );
            is( $form->{statedrop},  '',   'new country starts without a selected state' );
            is( $form->{name},            $attempt{name},     'name survives as text' );
            is( $form->{bio},             $bio,               'unprocessed bio survives as text' );
            is( $form->{city},            $attempt{city},     'city survives as text' );
            is( $form->{interests_other}, 'unsaved interest', 'interests survive refresh' );

            # Repeating a refresh must preserve a choice for the same country.
            $res =
                $cb->( POST $url, Content => [ %$form, statedrop => 'TX', refresh_country => 1 ] );
            return unless $form = refreshed_fields($res);
            is( $form->{statedrop},  'TX', 'same-country refresh preserves state choice' );
            is( $form->{stateother}, '',   'inactive field remains empty' );
            is_deeply( stored(), $before, 'repeated refresh still does not save' );

            $res = $cb->( POST $url, Content => [ %$form, country => 'GB', refresh_country => 1 ] );
            return unless $form = refreshed_fields($res);
            is( $form->{statedrop}, '', 'switch to free text clears old dropdown' );
            $res = $cb->(
                POST $url,
                Content => [ %$form, stateother => 'New <region> & text', refresh_country => 1 ]
            );
            return unless $form = refreshed_fields($res);
            is( $form->{stateother}, 'New <region> & text', 'same-country text survives refresh' );

            # A refresh marker must not relax the ordinary save validator.
            $res = $cb->(
                POST $url,
                Content => [ %$form, country => 'US', location_country => 'US', bio => '' ]
            );
            is( $res->code, 200, 'incompatible state still rejects ordinary Save' );
            is_deeply( stored(), $before, 'rejected Save does not change location' );

            # Tokens and countries are validated before even a non-saving refresh.
            $res = $cb->(
                POST $url, Content => [ %$form, lj_form_auth => 'invalid', refresh_country => 1 ]
            );
            ok( !exists fields( $res->content )->{country}, 'invalid token never reaches setup' );
            $res = $cb->( POST $url, Content => [ %$form, country => 'XX', refresh_country => 1 ] );
            like(
                $res->content,
                qr/invalid country|widget\.location\.error\.locale\.invalid_country/,
                'invalid country is reported on refresh'
            );
            is_deeply( stored(), $before, 'invalid-country refresh cannot save' );

            # An explicit Save, after the refresh, is the only persistence step.
            $res = $cb->(
                POST $url,
                Content => [ %$form, name => 'Saved name', bio => '', interests_other => '' ]
            );
            ok( $res->is_redirect, 'explicit Save advances setup' );
            is_deeply(
                [ @{ stored() }[ 2 .. 4 ] ],
                [ 'GB', 'New <region> & text', $attempt{city} ],
                'Save persists intended location'
            );

        };

        $u->set_prop( country => 'US' );
        $u->set_prop( state   => 'TX' );
        my $res  = $cb->( GET $url );
        my $form = fields( $res->content );
        is( $form->{statedrop},  'TX', 'stored configured state is redisplayed' );
        is( $form->{stateother}, '',   'setup revisit leaves inactive text empty' );

        for my $save_code ( 0, 1 ) {
            $storage_mode = $save_code;
            local $LJ::COUNTRIES_WITH_REGIONS{US} =
                { %{ $LJ::COUNTRIES_WITH_REGIONS{US} }, save_region_code => $save_code, };

            # Exercise a real reload while the nondefault mode is requested.
            local $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = 0;
            local $LJ::CACHE_CONFIG_MODTIME           = 0;
            for my $stored_state ( 'TX', 'Texas' ) {
                subtest "stored $stored_state with save_region_code=$save_code" => sub {
                    $u->set_prop( state => $stored_state );
                    my $original = stored();
                    my $res      = $cb->( GET $url );
                    my $form     = fields( $res->content );
                    is( $form->{statedrop},  'TX', 'stored code or name selects canonical option' );
                    is( $form->{stateother}, '',   'mapped state leaves inactive field empty' );
                    $res = $cb->( POST $url, Content => [ %$form, refresh_country => 1 ] );
                    return unless $form = refreshed_fields($res);
                    is( $form->{statedrop}, 'TX', 'same-country refresh preserves mapped option' );
                    is_deeply( stored(), $original, 'redisplay and refresh leave storage alone' );
                    $res = $cb->( POST $url, Content => [ %$form, bio => '' ] );
                    ok( $res->is_redirect, 'ordinary Save accepts canonical option' );
                    is( stored()->[3], $save_code ? 'TX' : 'Texas', 'Save respects storage mode' );
                };
            }

            for my $legacy_state ( 'Retained legacy region', 'Shared legacy region' ) {
                subtest "$legacy_state with save_region_code=$save_code" => sub {
                    my $load_codes  = \&LJ::load_codes;
                    my $region_type = $LJ::COUNTRIES_WITH_REGIONS{US}{type};
                    no warnings 'redefine';
                    local *LJ::load_codes = sub {
                        my ($opts) = @_;
                        return $load_codes->(@_)
                            unless $legacy_state eq 'Shared legacy region'
                            && exists $opts->{$region_type};
                        my $ret = $load_codes->(@_);

                        # Duplicate code-table labels exercise an ambiguous saved name.
                        $opts->{$region_type}{TX} = $opts->{$region_type}{CA} = $legacy_state;
                        return $ret;
                    };
                    use warnings 'redefine';
                    $u->set_prop( state => $legacy_state );
                    my $original = stored();
                    my $res      = $cb->( GET $url );
                    my $form     = fields( $res->content );
                    is( $form->{statedrop}, '', 'unknown stored region does not invent an option' );
                    is( $form->{stateother}, $legacy_state, 'legacy region remains in form' );
                    $res = $cb->( POST $url, Content => [ %$form, refresh_country => 1 ] );
                    return unless $form = refreshed_fields($res);
                    is( $form->{stateother}, $legacy_state,
                        'same-country refresh retains legacy state' );
                    $res = $cb->( POST $url, Content => [ %$form, bio => '' ] );
                    is( $res->code, 200, 'ordinary Save rejects unrepresentable stored state' );
                    is_deeply( stored(), $original,
                        'rejected Save cannot silently clear legacy region' );
                    $res = $cb->( POST $url, Content => [ %$form, statedrop => 'ZZ', bio => '' ] );
                    is( $res->code, 200, 'invalid replacement cannot clear legacy state' );
                    is_deeply( stored(), $original,
                        'invalid replacement leaves stored location alone' );
                    $res = $cb->(
                        POST $url,
                        Content => [
                            %$form,
                            statedrop  => 'TX',
                            stateother => 'Arbitrary typed region',
                            bio        => ''
                        ]
                    );
                    is( $res->code, 200, 'arbitrary conflicting input is still rejected' );
                    is_deeply( stored(), $original,
                        'arbitrary conflicting input cannot replace stored region' );
                    $res  = $cb->( GET $url );
                    $form = fields( $res->content );
                    $res  = $cb->( POST $url, Content => [ %$form, statedrop => 'TX', bio => '' ] );
                    ok( $res->is_redirect,
                        'direct Save accepts explicit replacement without another refresh' );
                    my $label = $legacy_state eq 'Shared legacy region' ? $legacy_state : 'Texas';
                    is(
                        stored()->[3],
                        $save_code ? 'TX' : $label,
                        'explicit replacement uses configured storage mode'
                    );
                };
            }
        }
        $storage_mode = undef;
    };
};

done_testing;
