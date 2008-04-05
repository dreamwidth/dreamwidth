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
        $error = LJ::Widget::CreateAccount->ml('widget.createaccount.error.username.mustenter');
    }
    if ($given_username && !$user) {
        $error = LJ::Lang::ml('error.usernameinvalid');
    }
    if (length $given_username > 15) {
        $error = LJ::Lang::ml('error.usernamelong');
    }

    my $u = LJ::load_user($user);
    my $in_use = 0;

    # because these error messages overwrite each other, do these in a specific order
    # -- rename to a purged journal
    # -- username in use, unless it's reserved.

    # do not create if this account name is purged
    if ($u && $u->is_expunged) {
        $error = LJ::Widget::CreateAccount->ml('widget.createaccount.error.username.purged', { aopts => "href='$LJ::SITEROOT/rename/'" });
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

    foreach my $re ("^system\$", @LJ::PROTECTED_USERNAMES) {
        next unless ($user =~ /$re/);

        # you can give people sharedjournal priv ahead of time to create
        # reserved communities:
        next if LJ::check_priv(LJ::get_remote(), "sharedjournal", $user);
        $error = LJ::Widget::CreateAccount->ml('widget.createaccount.error.username.reserved');
    }

    $error = LJ::Widget::CreateAccount->ml('widget.createaccount.error.username.inuse') if $in_use;

    return $error;
}

1;
