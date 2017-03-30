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

package LJ::NotificationMethod::Email;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';

use LJ::Web;

sub can_digest { 1 };

# takes a $u
sub new {
    my $class = shift;

    croak "no args passed"
        unless @_;

    my $u = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    my $self = { u => $u };

    return bless $self, $class;
}

sub title { BML::ml('notification_method.email.title') }

sub new_from_subscription {
    my $class = shift;
    my $subs = shift;

    return $class->new($subs->owner);
}

sub u {
    my $self = shift;
    croak "'u' is an object method"
        unless ref $self eq __PACKAGE__;

    if (my $u = shift) {
        croak "invalid 'u' passed to setter"
            unless LJ::isu($u);

        $self->{u} = $u;
    }
    croak "superfluous extra parameters"
        if @_;

    return $self->{u};
}

# send emails for events passed in
sub notify {
    my $self = shift;
    croak "'notify' is an object method"
        unless ref $self eq __PACKAGE__;

    # use https:// for system-generated links in notification emails
    local $LJ::IS_SSL;
    local ${$LJ::{$_}} foreach LJ::site_variables_list();
    if ( $LJ::USE_HTTPS_EVERYWHERE ) {
        $LJ::IS_SSL = 1;
        LJ::use_ssl_site_variables();
    }

    my $u = $self->u;
    my $vars = { sitenameshort => $LJ::SITENAMESHORT, sitename => $LJ::SITENAME, siteroot => $LJ::SITEROOT };

    my @events = @_;
    croak "'notify' requires one or more events"
        unless @events;

    foreach my $ev (@events) {
        croak "invalid event passed" unless ref $ev;

        $vars->{'hook'} = LJ::Hooks::run_hook("esn_email_footer", $ev, $u);
        my $footer = LJ::Lang::get_default_text( 'esn.footer.text2', $vars );

        my $plain_body = LJ::Hooks::run_hook("esn_email_plaintext", $ev, $u);
        unless ($plain_body) {
            $plain_body = $ev->as_email_string($u) or next;

            # only append the footer if we can see this event on the subscription interface
            $plain_body .= $footer if $ev->is_visible;
        }

        # run transform hook on plain body
        LJ::Hooks::run_hook("esn_email_text_transform", event => $ev, rcpt_u => $u, bodyref => \$plain_body);

        my %headers = (
                       "X-LJ-Recipient" => $u->user,
                       %{$ev->as_email_headers($u) || {}},
                       %{$self->{_debug_headers}   || {}}
                       );

        my $email_subject =
            LJ::Hooks::run_hook("esn_email_subject", $ev, $u) ||
            $ev->as_email_subject($u);

        if ($LJ::_T_EMAIL_NOTIFICATION) {
            $LJ::_T_EMAIL_NOTIFICATION->($u, $plain_body);
         } elsif ($u->{opt_htmlemail} eq 'N') {
            LJ::send_mail({
                to       => $u->email_raw,
                from     => $LJ::BOGUS_EMAIL,
                fromname => scalar($ev->as_email_from_name($u)),
                wrap     => 1,
                subject  => $email_subject,
                headers  => \%headers,
                body     => $plain_body,
            }) or die "unable to send notification email";
         } else {

             my $html_body = LJ::Hooks::run_hook("esn_email_html", $ev, $u);
             unless ($html_body) {
                 $html_body = $ev->as_email_html($u) or next;
                 $html_body =~ s/\n/\n<br\/>/g unless $html_body =~ m!<br!i;

                 my $html_footer = LJ::Hooks::run_hook('esn_email_html_footer', event => $ev, rcpt_u => $u );
                 unless ($html_footer) {
                     $html_footer = LJ::auto_linkify($footer);
                     $html_footer =~ s/\n/\n<br\/>/g;
                 }

                 # convert newlines in HTML mail
                 $html_body =~ s/\n/\n<br\/>/g unless $html_body =~ m!<br!i;

                 # only append the footer if we can see this event on the subscription interface
                 $html_body .= $html_footer if $ev->is_visible;

                 # run transform hook on html body
                 LJ::Hooks::run_hook("esn_email_html_transform", event => $ev, rcpt_u => $u, bodyref => \$html_body);
             }

            LJ::send_mail({
                to       => $u->email_raw,
                from     => $LJ::BOGUS_EMAIL,
                fromname => scalar($ev->as_email_from_name($u)),
                wrap     => 1,
                subject  => $email_subject,
                headers  => \%headers,
                html     => $html_body,
                body     => $plain_body,
            }) or die "unable to send notification email";
        }
    }

    return 1;
}

sub configured {
    my $class = shift;

    # FIXME: should probably have more checks
    return $LJ::BOGUS_EMAIL && $LJ::SITENAMESHORT ? 1 : 0;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    # override requiring user to have an email specified and be active if testing
    return 1 if $LJ::_T_EMAIL_NOTIFICATION;

    return 0 unless length $u->email_raw;

    # don't send out emails unless the user's email address is active
    return $u->{status} eq "A" ? 1 : 0;
}

1;
