# t/plack-manage-profile-location.t
#
# Profile location choices can refresh without saving unrelated edits.
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
use HTML::Entities qw(decode_entities);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'profileLocationTest';

my $u = temp_user();
$u->update_self( { status => 'A', name => 'Profile owner' } );
$u->set_prop( country => 'GB' );
$u->set_prop( state   => 'Old region' );
$u->set_prop( city    => 'Old city' );
$u->set_bio('Old bio');

# An existing find-by-email choice, so an explicit Save can succeed.
$u->set_prop( opt_findbyemail => 'N' );
my $service = DW::External::ProfileServices->list->[0];
die 'Profile regression requires seeded profile services' unless $service;
$u->save_profile_accts( { $service->{service_id} => ['old account'] } );

# Parse real successful controls, including the fallback inside noscript.
# Visibility and native no-JS interaction belong to separate browser proof.
sub fields {
    my ($html) = @_;
    my $p = HTML::TokeParser->new( \$html );
    my %out;
    while ( my $tag = $p->get_tag( 'input', 'select', 'textarea' ) ) {
        my $a = $tag->[1];
        next unless $a->{name};
        if ( $tag->[0] eq 'input' ) {
            my $type = $a->{type} || '';
            next if $type =~ /^(?:submit|button)$/;
            next if $type =~ /^(?:checkbox|radio)$/ && !exists $a->{checked};
            $out{ $a->{name} } = $a->{value} // '';
        }
        elsif ( $tag->[0] eq 'textarea' ) {
            my $text = '';
            while ( my $token = $p->get_token ) {
                last if $token->[0] eq 'E' && $token->[1] eq 'textarea';
                $text .= $token->[1] if $token->[0] eq 'T';
            }
            $out{ $a->{name} } = decode_entities($text);
        }
        else {
            my $name  = $a->{name};
            my $first = 1;
            $out{$name} = '';
            while ( my $option = $p->get_tag( 'option', '/select' ) ) {
                last if $option->[0] eq '/select';
                $out{$name} = $option->[1]{value} // ''
                    if $first || exists $option->[1]{selected};
                $first = 0;
            }
        }
    }
    return \%out;
}

# Start a new request first: the app's cached user object can hold older props.
sub fresh_user {
    LJ::start_request();
    return LJ::load_userid( $u->id, 1 );
}

# Report the rendered form errors when a Save that should succeed does not.
sub saved {
    my ( $res, $name ) = @_;
    return 1 if ok( $res->is_redirect, $name );
    diag("Form error: $_") for $res->content =~ /<div class="alert-box[^"]*">\s*(.*?)\s*<\/div>/gs;
    return 0;
}

sub stored {
    my $fresh = fresh_user();
    return [
        $fresh->name_orig,
        $fresh->bio,
        (
            map { $fresh->prop($_) || '' }
                qw(country state city gender urlname opt_hidefriendofs opt_hidememberofs
                opt_whatemailshow)
        ),
        $fresh->profile_email,
        $fresh->load_profile_accts( force_db => 1 )
    ];
}

my $save_hooks = 0;
my $hooks      = \&LJ::Hooks::run_hooks;
no warnings 'redefine';
local *LJ::Hooks::run_hooks = sub {
    if ( $_[0] eq 'profile_save' || $_[0] eq 'spam_check' ) {
        $save_hooks++;
        return;
    }
    return $hooks->(@_);
};
use warnings 'redefine';

with_fake_memcache {
    test_psgi $app, sub {
        my $cb  = shift;
        my $url = 'http://localhost/manage/profile?as=' . $u->user;
        my $res = $cb->( GET $url );
        is( $res->code, 200, 'real profile form renders' );
        my $form = fields( $res->content );
        ok( $form->{lj_form_auth}, 'real signed form token is present' );

        # The site email control only renders for accounts that can have an alias.
        my $has_site_email = exists $form->{opt_usesite};
        my $before         = stored();
        my $prefix         = 'Widget[Location]_';
        my %attempt        = (
            %$form,
            name                            => 'Unsaved <name> & "quotes"',
            gender                          => 'F',
            bio                             => 'Unsaved <bio> & literal &amp;',
            urlname                         => 'Unsaved <site> & text',
            day                             => '12',
            month                           => '4',
            year                            => '2000',
            opt_showlocation                => 'N',
            opt_hidefriendofs               => 1,
            opt_whatemailshow               => 'N',
            opt_usesite                     => 'N',
            DW__Setting__ProfileEmail_email => 'unsaved@example.invalid',
            extservice_val_1                => 'Unsaved <account> & text',
            extservice_site_26              => $service->{service_id},
            extservice_val_26               => 'new account',
            "${prefix}country"              => 'US',
            "${prefix}stateother"           => 'Texas',
            "${prefix}city"                 => 'Unsaved <city> & text',
            refresh_country                 => 1,
        );
        delete $attempt{opt_showmutualfriends};
        $res = $cb->( POST $url, Content => [%attempt] );
        is( $res->code, 200, 'refresh returns the editable profile' );
        is_deeply( stored(), $before, 'refresh does not save profile or service rows' );
        is( $save_hooks, 0, 'refresh skips profile-save and spam hooks' );
        $form = fields( $res->content );

        for my $key (
            qw(name gender bio urlname day month year opt_showlocation
            opt_hidefriendofs opt_whatemailshow opt_usesite DW__Setting__ProfileEmail_email
            extservice_site_1 extservice_dbid_1 extservice_val_1
            extservice_site_26 extservice_val_26)
            )
        {
            next if $key eq 'opt_usesite' && !$has_site_email;
            is( $form->{$key}, $attempt{$key}, "$key survives refresh and escaping" );
        }
        ok( !exists $form->{opt_showmutualfriends}, 'unchecked checkbox stays unchecked' );
        my $selects = HTML::TokeParser->new( \$res->content );
        my %select_names;
        while ( my $select = $selects->get_tag('select') ) {
            $select_names{ $select->[1]{name} || '' } = 1;
        }
        ok( !$select_names{extservice_site_1}, 'existing service identity stays fixed' );
        ok( $select_names{extservice_site_26}, 'new service row keeps its selector' );
        is( $form->{"${prefix}country"},    'US', 'submitted country is rendered' );
        is( $form->{"${prefix}stateother"}, '',   'transition clears the stale text state' );
        is( $form->{"${prefix}statedrop"},  '',   'new country begins without a state choice' );
        is( $form->{location_country},      'US', 'display marker follows rendered country' );

        $res = $cb->(
            POST $url, Content => [ %$form, "${prefix}statedrop" => 'TX', refresh_country => 1 ]
        );
        $form = fields( $res->content );
        is( $form->{"${prefix}statedrop"}, 'TX', 'same-country refresh retains selection' );
        is_deeply( stored(), $before, 'repeated refresh still saves nothing' );
        $res = $cb->(
            POST $url, Content => [ %$form, "${prefix}country" => 'GB', refresh_country => 1 ]
        );
        $form = fields( $res->content );
        is( $form->{"${prefix}statedrop"}, '', 'reverse transition clears dropdown state' );
        $res = $cb->(
            POST $url,
            Content => [
                %$form,
                "${prefix}stateother" => 'New <region> & text',
                refresh_country       => 1
            ]
        );
        $form = fields( $res->content );
        is(
            $form->{"${prefix}stateother"},
            'New <region> & text',
            'same-country refresh retains free text'
        );

        $res = $cb->(
            POST $url,
            Content => [
                %$form,
                "${prefix}country" => 'US',
                location_country   => 'US'
            ]
        );
        is( $res->code, 200, 'ordinary Save rejects incompatible text' );
        is_deeply( stored(), $before, 'forged display marker cannot authorize saving' );
        $res = $cb->( POST $url, Content => [ %$form, name => '' ] );
        is_deeply( stored(), $before, 'normal name validation still prevents saving' );
        $res = $cb->(
            POST $url, Content => [ %$form, lj_form_auth => 'invalid', refresh_country => 1 ]
        );
        ok( !exists fields( $res->content )->{name}, 'invalid token cannot reach refresh' );
        $res = $cb->(
            POST $url, Content => [ %$form, "${prefix}country" => 'XX', refresh_country => 1 ]
        );
        like(
            $res->content,
            qr/invalid country|widget\.location\.error\.locale\.invalid_country/i,
            'refresh reports invalid country'
        );
        is_deeply( stored(), $before, 'invalid country cannot save' );

        # Invalid interests must not normalize displayed values or allocate service rows.
        $form->{bio}                             = '';
        $form->{DW__Setting__ProfileEmail_email} = '';
        my $too_many = join( ', ', map { "interest$_" } 1 .. $u->count_max_interests + 1 );
        for my $case ( [ 1, $too_many ], [ 0, 'invalid <interest>' ] ) {
            my ( $checked, $interests ) = @$case;
            if ($checked) {
                $form->{opt_hidefriendofs} = 1;
                $form->{opt_hidememberofs} = 1;
            }
            else {
                delete $form->{opt_hidefriendofs};
                delete $form->{opt_hidememberofs};
            }
            my $email = $checked ? 'A' : 'N';
            my $site  = $checked ? 'Y' : 'N';
            $form->{opt_whatemailshow} = $email;
            $form->{opt_usesite}       = $site if $has_site_email;
            $res = $cb->( POST $url, Content => [ %$form, interests => $interests ] );
            is( $res->code, 200, 'invalid interests return the editable form' );
            is_deeply( stored(), $before, 'interests validation precedes profile/service writes' );
            $form = fields( $res->content );
            is( exists $form->{opt_hidefriendofs} ? 1 : 0,
                $checked, 'subscriber visibility retains its submitted state after error' );
            is( exists $form->{opt_hidememberofs} ? 1 : 0,
                $checked, 'community visibility retains its submitted state after error' );
            is( $form->{opt_whatemailshow}, $email, 'email display retains its submitted value' );
            is( $form->{opt_usesite}, $site, 'site email display retains its submitted value' )
                if $has_site_email;
            is( $form->{extservice_val_26}, 'new account', 'unsaved service survives the error' );
            is( $save_hooks, 0, 'invalid interests do not reach save hooks' );
        }

        # Correct only the interests and explicitly Save the same successful controls.
        $form->{interests} = 'valid interest';
        $res = $cb->( POST $url, Content => [%$form] );
        saved( $res, 'explicit valid Save follows normal success redirect' );
        my $fresh = fresh_user();
        is_deeply(
            [ map { $fresh->prop($_) } qw(country state city) ],
            [ 'GB', 'New <region> & text', $attempt{"${prefix}city"} ],
            'explicit Save persists the intended location'
        );
        ok( $save_hooks, 'explicit Save reaches ordinary hooks' );
        my $accounts = $fresh->load_profile_accts( force_db => 1 );
        my @new_accounts =
            grep { $_->[1] eq 'new account' } @{ $accounts->{ $service->{service_id} } || [] };
        is( scalar @new_accounts, 1, 'retry inserts the new service account exactly once' );
        is_deeply(
            [ map { $fresh->prop($_) } qw(opt_hidefriendofs opt_hidememberofs) ],
            [ 1, 1 ],
            'retry saves the unchecked visibility choices'
        );

        $u->set_prop( country => 'US' );
        for my $stored ( 'TX', 'Texas' ) {
            $u->set_prop( state => $stored );
            $res  = $cb->( GET $url );
            $form = fields( $res->content );
            is( $form->{"${prefix}statedrop"}, 'TX', 'stored code or name selects a real option' );
            is( $form->{"${prefix}stateother"},
                '', 'mapped stored region leaves hidden text empty' );
        }
        $u->set_prop( state => 'Unknown <region> & text' );
        $res  = $cb->( GET $url );
        $form = fields( $res->content );
        is( $form->{"${prefix}statedrop"}, '', 'unknown stored state invents no option' );
        is(
            $form->{"${prefix}stateother"},
            'Unknown <region> & text',
            'unrepresentable stored state is retained with escaping'
        );
        $before = stored();
        $res    = $cb->( POST $url, Content => [ %$form, refresh_country => 1 ] );
        $form   = fields( $res->content );
        is(
            $form->{"${prefix}stateother"},
            'Unknown <region> & text',
            'same-country refresh does not silently lose stored state'
        );
        $res = $cb->( POST $url, Content => [%$form] );
        is_deeply( stored(), $before, 'unchanged unknown state cannot be silently erased' );
        $res = $cb->( POST $url, Content => [ %$form, "${prefix}statedrop" => 'ZZ' ] );
        is_deeply( stored(), $before, 'nonexistent canonical state cannot replace stored state' );
        $res = $cb->(
            POST $url,
            Content => [
                %$form,
                "${prefix}statedrop"  => 'TX',
                "${prefix}stateother" => 'Arbitrary typed region'
            ]
        );
        is_deeply( stored(), $before, 'arbitrary incompatible text still rejects' );
        $res = $cb->( POST $url, Content => [ %$form, "${prefix}statedrop" => 'TX', bio => '' ] );
        saved( $res, 'direct explicit canonical choice replaces retained legacy text' );
        $fresh = fresh_user();
        my $expected = $LJ::COUNTRIES_WITH_REGIONS{US}{save_region_code} ? 'TX' : 'Texas';
        is( $fresh->prop('state'), $expected, 'widget still controls code-versus-name storage' );
    };
};

done_testing();
