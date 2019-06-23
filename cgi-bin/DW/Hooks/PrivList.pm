#!/usr/bin/perl
#
# DW::Hooks::PrivList
#
# This module implements the listing of valid arguments for each
# known user privilege in dw-free.  Any site that defines a different
# set of privs or privargs must create additional hooks to supplement
# this list.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2011-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::PrivList;

use strict;
use LJ::Hooks;

use LJ::DB;
use LJ::Lang;
use LJ::Support;

LJ::Hooks::register_hook(
    'privlist-add',
    sub {
        my ($priv) = @_;
        return unless defined $priv;
        my $hr = {};

        # valid admin privargs are the same as defined DB privs
        if ( $priv eq 'admin' ) {
            my $dbr = LJ::get_db_reader();
            $hr = $dbr->selectall_hashref( 'SELECT privcode, privname FROM priv_list', 'privcode' );

            # unfold result
            $hr->{$_} = $hr->{$_}->{privname} foreach keys %$hr;

            # add subprivs for supporthelp
            my $cats = LJ::Support::load_cats();
            $hr->{"supporthelp/$_"} = "$hr->{supporthelp} for $_"
                foreach map { $_->{catkey} } values %$cats;
        }

        # valid support* privargs are the same as support cats
        if ( my ($sup) = ( $priv =~ /^support(.*)$/ ) ) {
            my $cats    = LJ::Support::load_cats();
            my @catkeys = map { $_->{catkey} } values %$cats;
            if ( $priv eq 'supportread' ) {
                $hr->{"$_+"} = "Extended $sup privs for $_ category" foreach @catkeys;
            }
            $sup      = $priv eq 'supporthelp' ? 'All' : ucfirst $sup;
            $hr->{$_} = "$sup privs for $_ category" foreach @catkeys;
            $hr->{''} = "$sup privs for public categories";
        }

        # valid faqadd/faqedit privargs are the same as faqcats
        if ( $priv eq 'faqadd' or $priv eq 'faqedit' ) {
            my $dbr = LJ::get_db_reader();
            $hr = $dbr->selectall_hashref( 'SELECT faqcat, faqcatname FROM faqcat', 'faqcat' );

            # unfold result
            $hr->{$_} = $hr->{$_}->{faqcatname} foreach keys %$hr;
        }

        # valid translate privargs are the same as defined languages
        if ( $priv eq 'translate' ) {
            my %langs = @{ LJ::Lang::get_lang_names() };
            $hr->{$_} = "Can translate $langs{$_}" foreach keys %langs;

            # plus a couple of extras
            $hr->{'[itemdelete]'} = "Can delete translation strings";
            $hr->{'[itemrename]'} = "Can rename translation strings";
        }

        # have to manually maintain the other lists
        $hr = {
            entryprops    => "Access to /admin/entryprops",
            sessions      => "Access to admin mode on /manage/logins",
            subscriptions => "Access to admin mode on notification settings",
            suspended     => "Access to suspended journal content",
            userlog       => "Access to /admin/userlog",
            userprops     => "Access to /admin/propedit",
            }
            if $priv eq 'canview';

        $hr = {
            codetrace   => "Access to /admin/invites/codetrace",
            infohistory => "Access to infohistory console command",
            }
            if $priv eq 'finduser';

        # extracted from grep -r statushistory_add
        if ( $priv eq 'historyview' ) {
            my @shtypes = qw/ account_level_change b2lid_remap capedit
                change_journal_type comment_action communityxfer
                create_from_invite create_from_promo
                entry_action email_changed expunge_userpic
                impersonate journal_status logout_user
                mass_privacy paid_from_invite paidstatus
                privadd privdel rename_token reset_email
                reset_password s2lid_remap shop_points
                suspend sysban_add sysban_mod synd_create
                synd_edit synd_merge sysban_add sysban_modify
                sysban_trig unsuspend vgifts viewall /;

            $hr->{$_} = "Access to statushistory for $_ logs" foreach @shtypes;
        }

        $hr = {
            commentview   => "Access to /admin/recent_comments",
            emailqueue    => "Access to /tools/recent_email",
            invites       => "Access to some invites functionality under /admin/invites",
            largefeedsize => "Overrides synsuck_max_size for a feed",
            memcacheclear => "Access to /admin/memcache_clear",
            memcacheview  => "Access to /admin/memcache",
            mysqlstatus   => "Access to /admin/mysql_status",
            propedit      => "Allow to change userprops for other users",
            rename        => "Access to rename_opts console command",
            sendmail      => "Access to /admin/sendmail",
            spamreports   => "Access to /admin/spamreports",
            styleview     => "Access to private styles on /customize/advanced",
            support       => "Access to /admin/supportcat",
            themes        => "Access to /admin/themes",
            theschwartz   => "Access to /admin/theschwartz",
            usernames     => "Bypasses is_protected_username check",
            userpics      => "Access to expunge_userpic console command",
            users         => "Access to change_journal_status console command",
            vgifts        => "Access to approval functions on /admin/vgifts",
            oauth         => "Modify some settings on OAuth consumers",
            }
            if $priv eq 'siteadmin';

        $hr = { openid => "Only allowed to suspend OpenID accounts", }
            if $priv eq 'suspend';

        # extracted from LJ::Sysban::validate
        $hr = {
            email          => "Can ban specific email addresses",
            email_domain   => "Can ban entire email domains",
            invite_email   => "Can ban invites for email addresses",
            invite_user    => "Can ban invites for users",
            ip             => "Can ban connections from specific IPs",
            lostpassword   => "Can ban requests for lost passwords",
            noanon_ip      => "Can ban anonymous comments from specific IPs",
            oauth_consumer => "Can ban specific users from having OAuth consumers",
            pay_cc         => "Can ban payments from specific credit cards",
            pay_email      => "Can ban payments from specific emails",
            pay_uniq       => "Can ban payments from specific sessions",
            pay_user       => "Can ban payments from specific users",
            spamreport     => "Can ban spam reports from specific users",
            support_email  => "Can ban support requests from emails",
            support_uniq   => "Can ban support requests from sessions",
            support_user   => "Can ban support requests from users",
            talk_ip_test   => "Can force IPs to complete CAPTCHA to leave comments",
            uniq           => "Can ban specific browser sessions",
            user           => "Can ban specific users",
            }
            if $priv eq 'sysban';

        return $hr;
    }
);

1;
