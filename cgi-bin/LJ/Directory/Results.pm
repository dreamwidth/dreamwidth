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

package LJ::Directory::Results;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    $self->{page_size} = int( delete $args{page_size} || 100 );
    $self->{pages}     = int( delete $args{pages}     || 0 );
    $self->{page}      = int( delete $args{page}      || 1 );
    $self->{userids} = delete $args{userids} || [];

    $self->{format} = delete $args{format};
    $self->{format} = "pics"
        unless $self->{format} && $self->{format} =~ /^(pics|simple)$/;

    return $self;
}

sub empty_set {
    my ($pkg) = @_;
    return $pkg->new;
}

sub pages {
    my $self = shift;
    $self->{pages};
}

sub userids {
    my $self = shift;
    return @{ $self->{userids} };
}

sub format {
    my $self = shift;
    return $self->{format};
}

sub users {
    my $self   = shift;
    my $us     = LJ::load_userids( $self->userids );
    my $remote = LJ::get_remote();

    # gotta do this to preserve the ordering we got
    # (userids sorted in order of last update time)
    my @users = grep { $_ } map { $us->{$_} } $self->userids;

    # show only users who the remote user should see
    return grep { $_->should_show_in_search_results( for => $remote ) } @users;
}

sub as_string {
    my $self = shift;
    my @uids = $self->userids;
    return join( ',', @uids );
}

sub render {
    my $self = shift;

    return $self->render_simple if $self->format eq "simple";
    return $self->render_pics   if $self->format eq "pics";
}

sub render_simple {
    my $self  = shift;
    my @users = $self->users;

    my $updated = LJ::get_timeupdate_multi( $self->userids );

    my $ret = "<ul>";
    foreach my $u (@users) {
        $ret .= "<li>";
        $ret .= $u->ljuser_display . " - " . $u->name_html;

        # FIXME: consider replacing this with $u->last_updated
        $ret .= " <small>(Last updated: " . LJ::diff_ago_text( $updated->{ $u->id } ) . ")</small>";
        $ret .= "</li>";
    }
    $ret .= "</ul>";
    return $ret;
}

sub render_pics {
    my $self  = shift;
    my @users = $self->users;

    my $tablecols = 5;
    my $col       = 0;

    my $updated = LJ::get_timeupdate_multi( $self->userids );

    my $ret = "<table summary='' id='SearchResults' cellspacing='1'>";
    foreach my $u (@users) {
        $ret .= "</tr>\n<tr>\n" if ( $col++ % $tablecols == 0 );

        my $userpic = $u->userpic ? $u->userpic->imgtag : '';

        $ret .= qq {
            <td class="SearchResult" width="20%" align="middle">
                <div class="ResultUserpic">$userpic</div>
            };
        $ret .= '<div class="Username">' . $u->ljuser_display . '</div>';

        $ret .= "<small>";

        if ( $updated->{ $u->id } ) {
            $ret .= LJ::Lang::ml( 'search.user.update.last',
                { time => LJ::diff_ago_text( $updated->{ $u->id } ) } );
        }
        else {
            $ret .= LJ::Lang::ml('search.user.update.never');
        }

        $ret .= "</small></td>";
    }
    $ret .= "</tr></table>";

    return $ret;
}

1;
