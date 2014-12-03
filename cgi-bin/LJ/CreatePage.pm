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

package LJ::CreatePage;
use strict;
use Carp qw(croak);

sub verify_username {
    my $class = shift;
    my $given_username = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $second_submit_ref = $opts{second_submit_ref};
    my $error;

    $given_username = LJ::trim($given_username);
    my $user = LJ::canonical_username($given_username);

    unless ($given_username) {
        $error = LJ::Lang::ml('widget.createaccount.error.username.mustenter');
    }
    if ($given_username && !$user) {
        $error = LJ::Lang::ml('error.usernameinvalid');
    }
    if (length $given_username > 25) {
        $error = LJ::Lang::ml('error.usernamelong');
    }

    my $u = LJ::load_user($user);
    my $in_use = 0;

    # because these error messages overwrite each other, do these in a specific order
    # -- rename to a purged journal
    # -- username in use, unless it's reserved.

    # do not create if this account name is purged
    if ($u && $u->is_expunged) {
        $error = LJ::Lang::ml('widget.createaccount.error.username.purged', { aopts => "href='$LJ::SITEROOT/rename/'" });
    } elsif ($u) {
        $in_use = 1;

        # only do these checks on POST
        if ($post->{email} && $post->{password1}) {
            if ($u->email_raw eq $post->{email}) {
                if (LJ::login_ip_banned($u)) {
                    # brute-force possibly going on
                } else {
                    if ($u->password eq $post->{password1}) {
                        # okay either they double-clicked the submit button
                        # or somebody entered an account name that already exists
                        # with the existing password
                        $$second_submit_ref = 1 if $second_submit_ref;
                        $in_use = 0;
                    } else {
                        LJ::handle_bad_login($u);
                    }
                }
            }
        }
    }

    # don't allow protected usernames
    $error = LJ::Lang::ml('widget.createaccount.error.username.invalid')
        if LJ::User->is_protected_username( $user );

    $error = LJ::Lang::ml('widget.createaccount.error.username.inuse') if $in_use;

    return $error;
}

sub verify_password {
    my $class = shift;
    my %opts = @_;

    return undef unless LJ::is_enabled( 'password_check' );

    my ( $password, $username, $email, $name );
    my $u = $opts{u};
    if ( LJ::isu( $u ) ) {
        $password = $u->password;
        $username = $u->user;
        $email = $u->email_raw;
        $name = $u->name_raw;
    }

    $password = $opts{password} if $opts{password};
    $username = $opts{username} if $opts{username};
    $email = $opts{email} if $opts{email};
    $name = $opts{name} if $opts{name};

    # password must exist
    return LJ::Lang::ml( 'widget.createaccount.error.password.blank' )
        unless $password;

    # at least 6 characters
    return LJ::Lang::ml( 'widget.createaccount.error.password.tooshort' )
        if length $password < 6;

    # no more than 30 characters
    return LJ::Lang::ml( 'widget.createaccount.error.password.toolong' )
        if length $password > 30;

    # only ascii characters
    return LJ::Lang::ml( 'widget.createaccount.error.password.asciionly' )
        unless LJ::is_ascii( $password );

    # not the same as the username or the reversed username
    if ( $username ) {
        return LJ::Lang::ml( 'widget.createaccount.error.password.likeusername' )
            if lc $password eq lc $username || lc $password eq lc reverse $username;
    }

    # not the same as either part of the email address
    if ( $email ) {
        $email =~ /^(.+)@(.+)\./;
        return LJ::Lang::ml( 'widget.createaccount.error.password.likeemail' )
            if lc $password eq lc $1 || lc $password eq lc $2;
    }

    # not the same as the displayed name or the reversed displayed name
    if ( $name ) {
        return LJ::Lang::ml( 'widget.createaccount.error.password.likename' )
            if lc $password eq lc $name || lc $password eq lc reverse $name;
    }

    # at least 4 unique characters
    my %unique_chars = map { $_ => 1 } split( //, $password );
    return LJ::Lang::ml( 'widget.createaccount.error.password.needsmoreuniquechars' )
        unless scalar keys %unique_chars >= 4;

    # contains at least one digit or symbol
    return LJ::Lang::ml( 'widget.createaccount.error.password.needsnonletter' )
        if $password =~ /^[A-Za-z]+$/;

    # isn't similar to a common password
    my @common_passwords = grep { $_ } split( /\r?\n/, LJ::load_include( 'common-passwords' ) );
    foreach my $comm_pass ( $LJ::SITENAMESHORT, @common_passwords ) {
        # you can have a common password in your password if your password is greater in length
        # than the sum of the common password's length plus the ceiling of half of its length
        next if length $password > ( ( length $comm_pass ) + POSIX::ceil( ( length $comm_pass ) / 2 ) );

        return LJ::Lang::ml( 'widget.createaccount.error.password.common' )
            if $password =~ /$comm_pass/i;
    }

    return undef;
}

1;
