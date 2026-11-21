#!/usr/bin/perl
# Native controller for the settings hub formerly served by index.bml.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found in the LICENSE file included as part of this distribution.
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.

package DW::Controller::SettingsHub;

use strict;
use warnings;

use URI;

use DW::Controller qw(error_ml);
use DW::Request;
use DW::Routing;
use DW::Template;
use LJ::Setting;

for my $path (
    qw(/manage/settings /manage/settings/ /manage/settings/index /manage/settings/index.bml))
{
    DW::Routing->register_string( $path, \&settings_handler, app => 1, no_redirects => 1 );
}

my @CATS_ORDER =
    qw(account display community notifications mobile shortcuts privacy history othersites);

sub _categories {
    my ($u) = @_;
    my $scope = '/settings/index.tt';

    return (
        account => {
            name     => LJ::Lang::ml("$scope.cat.account"),
            visible  => 1,
            disabled => !$u,
            form     => 0,
            desc     => LJ::Lang::ml("$scope.cat.account.desc"),
            settings => [
                qw(
                    DW::Setting::Display::AccountLevel LJ::Setting::Display::AccountStatus
                    LJ::Setting::Display::Email LJ::Setting::Display::Password DW::Setting::Display::Manage2FA
                    )
            ],
        },
        display => {
            name     => LJ::Lang::ml("$scope.cat.display"),
            visible  => 1,
            disabled => 0,
            form     => 1,
            desc     => LJ::Lang::ml("$scope.cat.display.desc"),
            settings => [
                qw(
                    LJ::Setting::TimeZone DW::Setting::TimeFormat LJ::Setting::ImagePlaceholders
                    LJ::Setting::EmbedPlaceholders DW::Setting::CutDisable DW::Setting::CutInbox
                    LJ::Setting::EmailFormat LJ::Setting::EntryEditor DW::Setting::JournalEntryStyle
                    DW::Setting::JournalIconsStyle DW::Setting::ViewEntryStyle DW::Setting::ViewIconsStyle
                    DW::Setting::ViewJournalStyle LJ::Setting::NavStrip LJ::Setting::NCTalkLinks
                    LJ::Setting::StyleMine DW::Setting::DisplayEchi LJ::Setting::CtxPopup
                    LJ::Setting::AdultContent DW::Setting::AdultContentReason LJ::Setting::ViewingAdultContent
                    LJ::Setting::SafeSearch DW::Setting::GoogleAnalytics DW::Setting::GoogleAnalytics4
                    DW::Setting::ExcludeOwnStats DW::Setting::StickyEntry DW::Setting::MobileView
                    DW::Setting::RPAccount LJ::Setting::SiteScheme
                    )
            ],
        },
        shortcuts => {
            name     => LJ::Lang::ml("$scope.cat.shortcuts"),
            visible  => 1,
            disabled => !$u || $u->is_community,
            form     => 1,
            desc     => LJ::Lang::ml("$scope.cat.shortcuts.desc2"),
            settings => [
                qw(
                    DW::Setting::Shortcuts DW::Setting::ShortcutsNext DW::Setting::ShortcutsPrev
                    DW::Setting::ShortcutsTouch DW::Setting::ShortcutsTouchNext DW::Setting::ShortcutsTouchPrev
                    )
            ],
        },
        notifications => {
            name     => LJ::Lang::ml("$scope.cat.notifications"),
            visible  => 1,
            disabled => !$u || $u->is_community,
            form     => 0,
            desc     => LJ::Lang::ml(
                "$scope.cat.notifications.desc",
                {
                    aopts => "href='$LJ::SITEROOT/manage/circle/edit'"
                }
            ),
            settings => [],
        },
        mobile => {
            name     => LJ::Lang::ml("$scope.cat.mobile"),
            visible  => 1,
            disabled => !$u || $u->is_community,
            form     => 1,
            desc     => LJ::Lang::ml("$scope.cat.mobile.desc2"),
            settings => [
                qw(
                    LJ::Setting::EmailPosting DW::Setting::ResetReplyEmail DW::Setting::ApiKeyDelete
                    DW::Setting::ApiKeyGenerate
                    )
            ],
        },
        privacy => {
            name     => LJ::Lang::ml("$scope.cat.privacy"),
            visible  => 1,
            disabled => !$u,
            form     => 1,
            desc     => LJ::Lang::ml("$scope.cat.privacy.desc"),
            settings => [
                qw(
                    DW::Setting::EmailAlias DW::Setting::ContactInfo LJ::Setting::UserMessaging
                    LJ::Setting::MinSecurity DW::Setting::SynLevel LJ::Setting::SearchInclusion
                    LJ::Setting::EnableComments LJ::Setting::CommentScreening LJ::Setting::CommentCaptcha
                    LJ::Setting::CommentIP LJ::Setting::Display::BanUsers DW::Setting::AllowVgiftsFrom
                    DW::Setting::RandomPaidGifts DW::Setting::GlobalSearch DW::Setting::AllowSearchBy
                    DW::Setting::CommunityPromo
                    )
            ],
        },
        history => {
            name     => LJ::Lang::ml("$scope.cat.history"),
            visible  => 1,
            disabled => !$u || $u->is_community,
            form     => 0,
            desc     => LJ::Lang::ml("$scope.cat.history.desc"),
            settings => [
                qw(
                    LJ::Setting::Display::Logins LJ::Setting::Display::Emails LJ::Setting::Display::EmailPosts
                    LJ::Setting::Display::Orders DW::Setting::Display::CommunityInvites
                    DW::Setting::Display::OpenIDClaim
                    )
            ],
        },
        othersites => {
            name     => LJ::Lang::ml("$scope.cat.othersites"),
            visible  => 1,
            disabled => !$u || $u->is_community,
            form     => 1,
            desc     => LJ::Lang::ml("$scope.cat.othersites.desc"),
            settings => [qw(DW::Setting::XPostAccounts)],
        },
        community => {
            name     => LJ::Lang::ml("$scope.cat.community"),
            visible  => $u && $u->is_community,
            disabled => 0,
            form     => 1,
            desc     => LJ::Lang::ml("$scope.cat.community.desc"),
            settings => [
                qw(
                    DW::Setting::CommunityMembership DW::Setting::CommunityPostLevel
                    DW::Setting::CommunityPostLevelNew DW::Setting::CommunityEntryModeration
                    DW::Setting::CommunityJoinLinks DW::Setting::CommunityGuidelinesLocation
                    DW::Setting::CommunityGuidelinesEntry
                    )
            ],
        },
    );
}

sub _settings_for_category {
    my ( $u, $category ) = @_;
    my @settings;
    for my $class ( @{ $category->{settings} } ) {
        next unless eval "use $class; 1";
        push @settings, $class if $class->should_render($u);
    }
    return @settings;
}

sub _origin {
    my ($r) = @_;
    my $host = $r->host || return;
    my $scheme =
          $r->isa('DW::Request::Plack')
        ? $r->{env}->{'psgi.url_scheme'}
        : $LJ::PROTOCOL;
    return unless defined $scheme && $scheme =~ /\Ahttps?\z/i;

    my $origin = eval { URI->new( lc($scheme) . '://' . $host ) } or return;
    return unless $origin->host;
    return $origin;
}

# Receiver-only policy.  Do not use DW::Controller::validate_redirect_url here:
# $LJ::DOMAIN is intentionally empty in development, making its suffix check too broad.
sub _notification_return_url {
    my ( $r, $raw ) = @_;
    return unless defined $raw && length $raw;
    return if $raw =~ /[\x00-\x20\\]/ || $raw =~ /%5c/i;

    my $origin = _origin($r)             or return;
    my $uri    = eval { URI->new($raw) } or return;
    return if $uri->can('userinfo') && $uri->userinfo;

    if ( !defined $uri->scheme || $uri->scheme eq '' ) {
        return unless $raw =~ m{\A/(?!/)};
        my $absolute = URI->new_abs( $uri, $origin );
        return unless lc( $absolute->scheme || '' ) eq lc( $origin->scheme || '' );
        return unless lc( $absolute->host   || '' ) eq lc( $origin->host   || '' );
        return unless $absolute->port == $origin->port;
        return $uri->as_string;
    }

    return unless $uri->scheme =~ /\Ahttps?\z/i;
    return unless lc( $uri->scheme ) eq lc( $origin->scheme || '' );
    return unless lc( $uri->host || '' ) eq lc( $origin->host || '' );
    return unless $uri->port == $origin->port;
    return $uri->as_string;
}

sub _settings_redirect {
    my ( $r, $location, $status ) = @_;

    if ( $r->isa('DW::Request::Plack') ) {
        $r->status($status);
        $r->header_out( Location => $location );
        return $r->res;
    }
    return $r->redirect($location);
}

sub _delete_confirmation_id {
    my ($get) = @_;
    return $get->{delete_subscription} if defined $get->{delete_subscription};
    for my $key ( keys %$get ) {
        return $1 if $key =~ /\Adeletesub_(\d+)\z/ && $get->{$key};
    }
    return;
}

sub _owned_subscription {
    my ( $u, $id ) = @_;
    return unless $id && $id =~ /\A\d+\z/;
    for my $sub ( $u->subscriptions ) {
        return $sub if $sub->id && $sub->id == $id;
    }
    return;
}

sub _settings_confirm_message {
    return LJ::ejs_string( LJ::Lang::ml('/settings/index.tt.form.confirm1') );
}

sub _resource_setup {

    # The settings hub keeps the legacy (non-Foundation) chrome. res_includes
    # only emits resources in the active group (plus 'all'), so every page
    # resource is declared in the jquery group that is made active here; the
    # legacy sitescheme supplies the core JS (and the LiveJournal global).
    LJ::set_active_resource_group('jquery');
    LJ::need_res(
        { group => 'jquery' }, 'stc/tabs.css', 'stc/settings.css', 'js/settings.js',
        'js/jquery.settings.js'
    );
}

sub settings_handler {
    my ($opts) = @_;
    my $r = DW::Request->get;
    my $get  = $r->get_args  || {};
    my $post = $r->post_args || {};
    my $remote         = LJ::get_remote();
    my $authas         = $remote ? ( $get->{authas} || $remote->user ) : undef;
    my $can_view_other = $remote && $remote->has_priv( 'canview', 'subscriptions' );
    my $u;

    if ( $can_view_other && $get->{user} && ( $get->{cat} || '' ) eq 'notifications' ) {
        $u = LJ::load_user( $get->{user} );
    }
    if ( $remote && !$u ) {
        $u = LJ::get_authas_user($authas);
        return error_ml('error.invalidauth') unless $u;
    }

    my (%categories) = _categories($u);
    my @cats_order = @CATS_ORDER;

    my $given_cat = $get->{cat};
    if ($u) {
        $given_cat = 'account'
            unless defined $categories{$given_cat}
            && $categories{$given_cat}{visible}
            && !$categories{$given_cat}{disabled};
    }
    else {
        $given_cat = 'display';
    }
    my $inspection = $u && $u->user ne ( $authas || '' );
    return error_ml('error.invalidauth') if $inspection && $given_cat ne 'notifications';

    my $delete_id = _delete_confirmation_id($get);
    my $delete_sub;
    if ( $given_cat eq 'notifications' ) {
        my $viewing_self = !$inspection && $remote->equals($u);
        my $url =
            LJ::create_url( '/manage/settings/notifications', keep_args => [qw(authas user page)] );

        if ( $r->did_post && !$viewing_self ) {
            return error_ml('error.invalidform')
                unless LJ::check_form_auth( $post->{lj_form_auth} );
            return error_ml('error.invalidauth');
        }
        if ( $r->did_post && $post->{delete_subscription_confirm} ) {
            return error_ml('error.invalidform')
                unless LJ::check_form_auth( $post->{lj_form_auth} );
            my $sub = _owned_subscription( $u, $post->{delete_subscription_id} );
            return error_ml('error.invalidform') unless $sub;
            $sub->delete;
            return $r->redirect($url);
        }
        if ( !$r->did_post && $viewing_self && $delete_id ) {
            $delete_sub = _owned_subscription( $u, $delete_id );
            return error_ml('error.invalidform') unless $delete_sub;
        }
        else {
            return _settings_redirect( $r, $url, $r->did_post ? 307 : 302 );
        }
    }

    my $category = $categories{$given_cat};
    my @settings = _settings_for_category( $u, $category );
    _resource_setup();

    my ( @messages, @errors );
    my $save_rv;
    if ( $r->did_post ) {
        return error_ml('error.invalidform') unless LJ::check_form_auth( $post->{lj_form_auth} );
        return error_ml('error.invalidauth') if $inspection;

        $save_rv = LJ::Setting->save_all( $u, $post, \@settings );
        if ( LJ::Setting->save_had_errors($save_rv) ) {
            push @errors, LJ::Lang::ml('/settings/index.tt.errors');
        }
        else {
            push @messages, LJ::Lang::ml('/settings/index.tt.success');
        }
    }

    my @rows;
    my $setting_count = 0;
    my $total         = scalar @settings;
    for my $setting (@settings) {
        $setting_count++ unless $setting->is_conditional_setting;
        my $setting_errors = $setting->errors_from_save($save_rv);
        my $args           = $setting->args_from_save($save_rv);
        push @rows,
            {
            id          => $setting->pkgkey,
            label       => $setting->label,
            option      => $setting->option( $u, $setting_errors, $args, getargs => $get ),
            actionlink  => $setting->actionlink($u),
            helpicon    => LJ::help_icon( $setting->helpurl($u) ),
            conditional => $setting->is_conditional_setting,
            row_class   => $setting_count % 2 == 0 ? 'even' : 'odd',
            last        => $setting_count == $total ? 1 : 0,
            };
    }

    my %authas_arg = $u && $remote && $u->user ne $remote->user ? ( authas => $authas ) : ();
    my $query      = sub {
        my (%args) = @_;
        return LJ::create_url( '/manage/settings/', args => \%args );
    };
    my @tabs;
    for my $tab_key (@cats_order) {
        my $tab = $categories{$tab_key};
        next unless $tab->{visible};
        push @tabs,
            {
            key      => $tab_key,
            name     => $tab->{name},
            disabled => $tab->{disabled},
            active   => $tab_key eq $given_cat,
            url      => $tab_key eq 'notifications'
            ? LJ::create_url( '/manage/settings/notifications', args => \%authas_arg )
            : $query->( %authas_arg, cat => $tab_key ),
            };
    }

    my $form_args = { cat => $given_cat };
    $form_args->{authas} = $authas if $u && $remote && $u->user ne $remote->user;
    $form_args->{page} = int( $get->{page} ) if $given_cat eq 'notifications' && $get->{page};
    my $post_action = $query->(%$form_args);

    my $vars = {
        u           => $u,
        remote      => $remote,
        authas      => $authas,
        authas_form => $remote
        ? LJ::make_authas_select( $remote,
            { authas => $get->{authas}, showall => $given_cat eq 'account' } )
        : undef,
        title => $u ? LJ::Lang::ml( '/settings/index.tt.title.page',
            { user => $u->ljuser_display( { head_size => '24x24' } ) } )
        : LJ::Lang::ml('/settings/index.tt.title.anon'),
        windowtitle => $u
        ? LJ::Lang::ml( '/settings/index.tt.title.page', { user => $u->display_username } )
        : LJ::Lang::ml('/settings/index.tt.title.anon'),
        category          => $given_cat,
        category_data     => $category,
        tabs              => \@tabs,
        rows              => \@rows,
        form_action       => $post_action,
        form_enabled      => $category->{form} && !$inspection,
        messages          => \@messages,
        errors            => \@errors,
        delete_sub        => $delete_sub,
        confirm_msg       => _settings_confirm_message(),
        community_linkbar => $u
            && $u->is_community ? $u->maintainer_linkbar('settingsaccount') : undef,
        intro => $u ? LJ::Lang::ml(
            '/settings/index.tt.intro3',
            {
                aopts1 => "href='"
                    . LJ::create_url( '/manage/profile/', args => \%authas_arg ) . "'",
                aopts2 => "href='" . LJ::create_url( '/customize/', args => \%authas_arg ) . "'"
            }
        ) : undef,
    };
    return DW::Template->render_template( 'settings/index.tt', $vars );
}

1;
