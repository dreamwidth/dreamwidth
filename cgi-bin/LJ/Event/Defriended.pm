package LJ::Event::Defriended;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu) = @_;
    foreach ($u, $fromu) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $fromu->{userid});
}

sub is_common { 0 }

my @_ml_strings_en = (
    'esn.public',                   # 'public',
    'esn.defriended.subject',       # '[[who]] removed you from their Friends list',
    'esn.remove_friend',            # '[[openlink]]Remove [[postername]] from your Friends list[[closelink]]',
    'esn.post_entry',               # '[[openlink]]Post an entry[[closelink]]',
    'esn.edit_friends',             # '[[openlink]]Edit Friends[[closelink]]',
    'esn.edit_groups',              # '[[openlink]]Edit Friends groups[[closelink]]',
    'esn.defriended.email_text',    # 'Hi [[user]],
                                    #
                                    #[[poster]] has removed you from their Friends list.
                                    #
                                    #You can:',
);

sub as_email_subject {
    my ($self, $u) = @_;

    return LJ::Lang::get_text($u->prop('browselang'), 'esn.defriended.subject', undef, { who => $self->friend->display_username } );
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang        = $u->prop('browselang');
    my $user        = $is_html ? ($u->ljuser_display) : ($u->user);
    my $poster      = $is_html ? ($self->friend->ljuser_display) : ($self->friend->user);
    my $postername  = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $journal_profile = $self->friend->profile_url;

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    my $entries = LJ::is_friend($u, $self->friend) ? "" : " " . LJ::Lang::get_text($lang, 'esn.public', undef);

    my $vars = {
        who         => $self->friend->display_username,
        poster      => $poster,
        postername  => $postername,
        user        => $user,
        entries     => $entries,
    };

    return LJ::Lang::get_text($lang, 'esn.defriended.email_text', undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.remove_friend' => [ LJ::is_friend($u, $self->friend) ? 1 : 0,
                                            "$LJ::SITEROOT/friends/add.bml?user=$postername" ],
            'esn.post_entry'    => [ 3, "$LJ::SITEROOT/update.bml" ],
            'esn.edit_friends'  => [ 4, "$LJ::SITEROOT/friends/edit.bml" ],
            'esn.edit_groups'   => [ 5, "$LJ::SITEROOT/friends/editgroups.bml" ],
        }
    );
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, $u, 1);
}

# technically "former friend-of", but who's keeping track.
sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("%s has removed you from their Friends list.",
                   $self->friend->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $u = $self->u;
    my $friend = $self->friend;
    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $friend->addfriend_url . "'>Remove friend</a>"
        if LJ::is_friend($u, $friend);
    $ret .= " <a href='" . $friend->profile_url . "'>View profile</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;
    return sprintf("%s has removed you from their Friends list.",
                   $self->friend->{user});
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal or croak "No user";
    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);
    # "Someone removes $user from their Friends list"
    # where $user may be also 'me'.
    return BML::ml('event.defriended.' . ($journal_is_owner ? 'me' : 'user'), { user => $journal->ljuser_display });
}

# only users with the track_defriended cap can use this
sub available_for_user  {
    my ($class, $u, $subscr) = @_;
    return $u->get_cap("track_defriended") ? 1 : 0;
}

sub content {
    my ($self) = @_;

    return $self->as_html_actions;
}

1;
