package LJ::Event::OfficialPost;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak "No entry" unless $entry;

    return $class->SUPER::new($entry->journal, $entry->ditemid);
}

sub entry {
    my $self = shift;
    my $ditemid = $self->arg1;
    return LJ::Entry->new($self->event_journal, ditemid => $ditemid);
}

sub content {
    my $self = shift;
    return $self->entry->event_html;
}

sub content_summary {
    my $entry = $_[0]->entry;
    my $entry_summary = $entry->event_html_summary( 300 );

    my $ret = $entry_summary;
    $ret .= "..." if $entry->event_html ne $entry_summary;

    return $ret;
}

sub is_common { 1 }

sub zero_journalid_subs_means { 'all' }

sub _construct_prefix {
    my $self = shift;
    return $self->{'prefix'} if $self->{'prefix'};
    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return $self->{'prefix'} = 'esn.' . lc($classname);
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

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        $label,
        undef,
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
%s", $self->as_html($u), $self->content;
}

sub as_email_string {
    my $self = shift;
    my $u = shift;

    my $text = $self->content;
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

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        _construct_prefix($self) . '.html',
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $entry->journal->ljuser_display,
            url             => $entry->url,
        });
}

sub as_string {
    my $self = shift;
    my $u = shift;
    my $entry = $self->entry or return "(Invalid entry)";

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        _construct_prefix($self) . '.string',
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $self->entry->journal->display_username,
            url             => $entry->url,
        });
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return BML::ml('event.officialpost', { sitename => $LJ::SITENAME }); # $LJ::SITENAME makes a new announcement
}

sub schwartz_role { 'mass' }

1;
