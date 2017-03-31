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

package LJ::Event::OfficialPost;
use strict;
use LJ::Entry;
use Carp qw(croak);
use base 'LJ::Event::JournalNewEntry';

sub content {
    my ( $self, $target, %opts ) = @_;
    # force uncut for certain views (e-mail)
    my $args = $opts{full}
            ? {}
            : { # double negatives, ouch!
                ljcut_disable => ! $target->cut_inbox,
                cuturl => $self->entry->url
              };

    return $self->entry->event_html( $args );
}

sub zero_journalid_subs_means { 'all' }

sub _construct_prefix {
    my $self = shift;
    return $self->{'prefix'} if $self->{'prefix'};
    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return $self->{'prefix'} = 'esn.' . lc($classname);
}

sub matches_filter {
    my ($self, $subscr) = @_;

    return 0 unless $subscr->available_for_user;
    return 1;
}

sub as_email_subject {
    my $self = shift;
    my $u = shift;
    my $label = _construct_prefix($self);

    # construct label

    if ($self->entry->subject_text) {
        $label .= '.subject';
    } else {
        $label .= '.nosubject';
    }

    return LJ::Lang::get_default_text( $label,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $self->entry->journal->display_username,
        });
}

sub as_email_html {
    my $self = shift;
    my $u = shift;

    return sprintf "%s<br />
<br />
%s", $self->as_html($u), $self->content( $u, full => 1 );
}

sub as_email_string {
    my $self = shift;
    my $u = shift;

    my $text = $self->content( $u, full => 1 );
    $text =~ s/\n+/ /g;
    $text =~ s/\s*<\s*br\s*\/?>\s*/\n/g;
    $text = LJ::strip_html($text);

    return sprintf "%s

%s", $self->as_string($u), $text;
}

sub as_html {
    my $self = shift;
    my $u = shift;
    my $entry = $self->entry or return "(Invalid entry)";

    return LJ::Lang::get_default_text( _construct_prefix($self) . '.html2',
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $entry->journal->ljuser_display,
            url             => $entry->url,
            poster          => $self->entry->poster->ljuser_display,
        });
}

sub as_string {
    my $self = shift;
    my $u = shift;
    my $entry = $self->entry or return "(Invalid entry)";

    return LJ::Lang::get_default_text( _construct_prefix($self) . '.string2',
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $self->entry->journal->display_username,
            url             => $entry->url,
            poster          => $self->entry->poster->display_username,
        });
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return BML::ml('event.officialpost', { sitename => $LJ::SITENAME }); # $LJ::SITENAME makes a new announcement
}

sub schwartz_role { 'mass' }

1;
