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

package LJ::Event::Birthday;

use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ($class, $u) = @_;
    croak "No user" unless $u && LJ::isu($u);

    return $class->SUPER::new($u);
}

sub bdayuser {
    my $self = shift;
    return $self->event_journal;
}

# $self->bday ==> $self->bday($lang) where $lang = $u->prop('browselang');
# formats birthday as "August 1"
sub bday {
    my $self = shift;
    my ($year, $mon, $day) = split(/-/, $self->bdayuser->{bdate});

    my @months = qw(January February March April May June
                    July August September October November December);

    return "$months[$mon-1] $day";
}

sub matches_filter {
    my ($self, $subscr) = @_;

    return $self->bdayuser->can_notify_bday(to => $subscr->owner) ? 1 : 0;
}

sub as_string {
    my $self = shift;

    return sprintf("%s's birthday is on %s!",
                   $self->bdayuser->display_username,
                   $self->bday);
}

sub as_html {
    my $self = shift;

    return sprintf("%s's birthday is on %s!",
                   $self->bdayuser->ljuser_display,
                   $self->bday);
}

sub as_html_actions {
    my ($self) = @_;

    my $gifturl = $self->bdayuser->gift_url;
    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$gifturl'>Send a Gift</a>";
    $ret .= "</div>";

    return $ret;
}

my @_ml_strings = (
    'esn.month.day_jan',    #January [[day]]
    'esn.month.day_feb',    #February [[day]]
    'esn.month.day_mar',    #March [[day]]
    'esn.month.day_apr',    #April [[day]]
    'esn.month.day_may',    #May [[day]]
    'esn.month.day_jun',    #June [[day]]
    'esn.month.day_jul',    #July [[day]]
    'esn.month.day_aug',    #August [[day]]
    'esn.month.day_sep',    #September [[day]]
    'esn.month.day_oct',    #October [[day]]
    'esn.month.day_nov',    #November [[day]]
    'esn.month.day_dec',    #December [[day]]
    'esn.bday.subject',     #[[bdayuser]]'s birthday is coming up!
    'esn.bday.email',       #Hi [[user]],
                            #
                            #[[bdayuser]]'s birthday is coming up on [[bday]]!
                            #
                            #You can:
    'esn.post_happy_bday'   #[[openlink]]Post to wish them a happy birthday[[closelink]]
);

sub as_email_subject {
    my $self = shift;
    my $u    = shift;

    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.bday.subject', undef,
        { bdayuser => $self->bdayuser->display_username } );
}

# This is same method as 'bday', but it use ml-features.
sub email_bday {
    my ($self, $lang) = @_;

    my ($year, $mon, $day) = split(/-/, $self->bdayuser->{bdate});
    return LJ::Lang::get_text($lang,
       'esn.month.day_' . qw(jan feb mar apr may jun jul aug sep oct nov dec)[$mon-1],
       undef, { day => $day } );
}

sub _as_email {
    my ($self, $is_html, $u) = @_;

    my $lang = $u->prop('browselang');

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings);

    return LJ::Lang::get_text($lang,
       'esn.bday.email', undef,
        {
            user        => $is_html ? $u->ljuser_display : $u->display_username,
            bday        => $self->email_bday($lang),
            bdayuser    => $is_html ? $self->bdayuser->ljuser_display : $self->bdayuser->display_username,
        }) .
        $self->format_options($is_html, $lang, undef,
            {
                'esn.post_happy_bday'   => [ 1, "$LJ::SITEROOT/update" ],
            },
            LJ::Hooks::run_hook('birthday_notif_extra_' . ($is_html ? 'html' : 'plaintext'), $u)
        );
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, 0, $u);
}

sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, 1, $u);
}

sub zero_journalid_subs_means { "trusted_or_watched" }

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal;

    return BML::ml('event.birthday.me') # "One of the people on my access or subscription lists has an upcoming birthday"
        unless $journal;

    my $ljuser = $journal->ljuser_display;
    return BML::ml('event.birthday.user', { user => $ljuser } ); # "$ljuser\'s birthday is coming up";
}

sub content {
    my ($self, $target) = @_;

    return $self->as_html_actions;
}

1;
