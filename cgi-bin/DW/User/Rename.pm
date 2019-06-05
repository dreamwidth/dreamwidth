#!/usr/bin/perl
#
# DW::User::Rename - Contains logic to handle account renaming.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::User::Rename;

=head1 NAME

DW::User::Rename - Contains logic to handle account renaming. Based on bin/renameuser.pl, from the LiveJournal code

=head1 SYNOPSIS

  use DW::User::Rename;

  # on a user object
  my $u = LJ::load_user( "exampleusername" );
  if ( $u->can_rename_to( "to_username" ) ) {
    # print message, whatever...

    # do rename
    $u->rename( "to_username", token => $token_object );

    # this user object retains old name
    # but all caches should have been cleared after the rename, so you can get
    # an updated copy of the user when you do LJ::load_userid
    $u = LJ::load_userid( $u->userid );
  }

  my $user_a = LJ::load_user( "swap_a" );
  my $user_b = LJ::load_user( "swap_b" );
  $user_a->swap_usernames( $user_b ) if $user_a->can_rename_to( $user_b->user );

  # can also force a rename, which doesn't take into consideration any of the
  # safeguards. Only call this from an admin page:
  $u->rename( "to_username", token => $token, force => 1 )
=cut

use strict;
use warnings;

use DW::RenameToken;
use DW::FormErrors;

=head1 API

=head2 C<< $self->can_rename_to( $tousername [, %opts ] ) >>

Return true if this user can be renamed to the given username

Optional arguments are:
=item force     => bool, default false
=item errors    => DW::FormErrors object
=item form_from => id of form label used for fromuser (for error association)

=cut

sub can_rename_to {
    my ( $self, $tousername, %opts ) = @_;

    my $errors = $opts{errors}    || DW::FormErrors->new;
    my $formid = $opts{form_from} || 'authas';

    unless ($tousername) {
        $errors->add( 'touser', 'rename.error.noto' );
        return 0;
    }

    # make sure both from and to are present and, the to is a valid username form
    $tousername = LJ::canonical_username($tousername);
    unless ($tousername) {
        $errors->add( 'touser', 'rename.error.invalidto' );
        return 0;
    }

    unless ( LJ::isu($self) ) {
        $errors->add( $formid, 'rename.error.invalidfrom' );
        return 0;
    }

    # make sure we don't try to rename to ourself
    if ( $self->user eq $tousername ) {
        $errors->add( 'touser', 'rename.error.isself' );
        return 0;
    }

    # force, but only if to and from are valid
    return 1 if $opts{force};

    # can't rename to a reserved username
    if ( LJ::User->is_protected_username($tousername) ) {
        $errors->add( 'touser', 'rename.error.reserved', { to => LJ::ehtml($tousername) } );
        return 0;
    }

    # suspended journals can't be renamed. So can't these other ones.
    if (   $self->is_suspended
        || $self->is_readonly
        || $self->is_locked
        || $self->is_memorial
        || $self->is_renamed )
    {
        $errors->add( $formid, 'rename.error.invalidstatusfrom',
            { from => $self->ljuser_display } );
        return 0;
    }

    my $check_basics = sub {
        my ( $fromu, $tou ) = @_;

        # able to rename to unregistered accounts
        return { ret => 1 } unless $tou;

        # some journals can not be renamed to
        if (   $tou->is_suspended
            || $tou->is_readonly
            || $tou->is_locked
            || $tou->is_memorial
            || $tou->is_renamed )
        {
            $errors->add( 'touser', 'rename.error.invalidstatusto',
                { to => $tou->ljuser_display } );
            return { ret => 0 };
        }

        # expunged users can always be renamed to
        return { ret => 1 } if $tou->is_expunged;

        # only personal journals and communities can be renamed
        if ( !( $tou->is_personal || $tou->is_community ) ) {
            $errors->add( 'touser', 'rename.error.invalidjournaltypeto' );
            return { ret => 0 };
        }
    };

    # only personal and community accounts can be renamed
    if ( $self->is_personal ) {

        # able to rename to unregistered accounts
        my $tou = LJ::load_user($tousername);

        # check basic stuff that is common for all types of renames
        my $rv = $check_basics->( $self, $tou );
        return $rv->{ret} if $rv;

        # deleted and visible journals have extra safeguards:
        # person-to-person
        return 1 if DW::User::Rename::_are_same_person( $self, $tou );

        # person-to-community (only under restricted circumstances for the community)
        return 1 if DW::User::Rename::_is_authorized_for_comm( $self, $tou );

        $errors->add( 'touser', 'rename.error.unauthorized2', { to => $tou->ljuser_display } );
        return 0;

    }
    elsif ( $self->is_community && LJ::isu( $opts{user} ) ) {
        my $admin = $opts{user};

        # make sure that the community journal is under the admin's control
        # and satisfies all other conditions that ensure we don't leave members hanging
        unless ( DW::User::Rename::_is_authorized_for_comm( $admin, $self ) ) {
            $errors->add(
                $formid,
                'rename.error.unauthorized.forcomm',
                { comm => $self->ljuser_display }
            );
            return 0;
        }

        my $tou = LJ::load_user($tousername);

        # check basic stuff that is common for all renames
        my $rv = $check_basics->( $self, $tou );
        return $rv->{ret} if $rv;

        # community-to-person
        # able to rename to another personal journal under admin's control
        return 1 if $tou->is_person && DW::User::Rename::_are_same_person( $admin, $tou );

        # community-to-community
        # we checked early on that the admin is authorized to rename this community
        # so we don't need to check again here
        return 1 if $tou->is_community;
    }

    # be strict in what we accept
    $errors->add( 'touser', 'rename.error.unknown', { to => LJ::ehtml($tousername) } );
    return 0;
}

=head2 C<< $self->rename( $tousername, token => $rename_token_obj [, %opts] ) >>

Rename the given user to the provided username. Requires a user name to rename to, and a token object to store the rename action data. If the username we're returning to is of an existing user then it shall be moved aside to a username of the form "ex_oldusernam123". Returns 1 on success, 0 on failure

Optional arguments are:
=item force     => bool, default false (passed to ->can_rename_to)
=item redirect  => bool, default false
=item errors    => DW::FormErrors object
=item del_watched_by/del_trusted_by/del_trusted/del_watched/del_communities => bool, default false
=item redirect_email => bool, default false (also forced to false if redirect is false)

=cut

sub rename {
    my ( $self, $tousername, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;

    my $remote = LJ::isu( $opts{user} ) ? $opts{user} : $self;
    $errors->add( 'token', 'rename.error.tokeninvalid' )
        unless $opts{token} && $opts{token}->isa("DW::RenameToken");
    $errors->add( 'token', 'rename.error.tokenapplied' )
        if $opts{token} && ( $opts{token}->applied || $opts{token}->revoked );

    my $can_rename_to = $self->can_rename_to( $tousername, %opts );

    return 0 if $errors->exist || !$can_rename_to;

    $tousername = LJ::canonical_username($tousername);
    if ( my $tou = LJ::load_user($tousername) ) {
        return 0 unless DW::User::Rename::_rename_to_ex( $tou, errors => $opts{errors} );
    }

    return DW::User::Rename::_rename( $self, $tousername, %opts );
}

=head2 C<< $self->swap_usernames( $touser [, %opts ] ) >>

Swap the usernames of these two users.

=cut

sub swap_usernames {
    my ( $u1, $u2, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;

    my $admin  = LJ::isu( $opts{user} ) ? $opts{user} : $u1;
    my @tokens = @{ $opts{tokens} || [] };

    # tokens can be owned by $admin (remote user),
    # $u1 (authas user), or $u2 (intended target)
    my $check_uids = { $admin->id => 1, $u1->id => 1, $u2->id => 1 };

    foreach my $token (@tokens) {
        $errors->add( 'token', 'rename.error.tokeninvalid' )
            unless $token
            && $token->isa("DW::RenameToken")
            && $check_uids->{ $token->ownerid };

        $errors->add( 'token', 'rename.error.tokenapplied' )
            if $token->applied || $token->revoked;
    }

    if ( scalar @tokens >= 2 ) {
        $errors->add( 'token', 'rename.error.tokeninvalid' )
            if ( $tokens[0]->token eq $tokens[1]->token );
    }
    else {
        $errors->add( 'token', 'rename.error.tokentoofew' );
    }

    my %admin_opts = $u2->is_community ? ( user => $admin ) : ();

    my $can_rename = $u1->can_rename_to( $u2->username, %opts, %admin_opts )
        && $u2->can_rename_to( $u1->username, %opts, %admin_opts );
    return 0 if $errors->exist || !$can_rename;

    my $u1name = $u1->user;
    my $u2name = $u2->user;

    my $did_rename = 1;
    $did_rename &&= DW::User::Rename::_rename_to_ex( $u2, errors => $opts{errors} );
    return 0 unless $did_rename;

    # ugh, but need it to avoid duplicate timestamps in infohistory
    sleep(1);

    $did_rename &&=
        DW::User::Rename::_rename( $u1, $u2name, %opts, %admin_opts, token => $tokens[0] );
    return 0 unless $did_rename;

    $did_rename &&=
        DW::User::Rename::_rename( $u2, $u1name, %opts, %admin_opts, token => $tokens[1] );
    return $did_rename;
}

=head2 C<< $self->_clear_from_cache >>

Internal function to clear a user from various caches.

=cut

sub _clear_from_cache {
    my ( $self, $fromusername, $tousername ) = @_;

    # $fromusername should be the same as $self->user, but we use the passed in value
    # to be safe, since $self has been renamed at this point.
    LJ::MemCache::delete("uidof:$fromusername");
    LJ::MemCache::delete("uidof:$tousername");
    LJ::memcache_kill( $self->userid, "userid" );

    delete $LJ::CACHE_USERNAME{ $self->userid };
    delete $LJ::REQ_CACHE_USER_NAME{$fromusername};
    delete $LJ::REQ_CACHE_USER_ID{ $self->userid };
}

=head2 C<< $self->_are_same_person >>

Internal function to determine whether two personal accounts are controlled by the same person

=cut

sub _are_same_person {
    my ( $p1, $p2 ) = @_;

    return 0 unless $p1->is_person && $p2->is_person;

# able to rename to registered accounts, where both accounts can be identified as the same person
# may be able to do this more elegantly once we are able to associate accounts
# right now: two valid accounts, same email address, same password, and at least one must be validated
    return 0 unless $p1->has_same_email_as($p2);
    return 0 unless $p1->password eq $p2->password;
    return 0 unless $p1->is_validated || $p2->is_validated;

    return 1;
}

=head2 C<< $self->_is_authorized_for_comm >>

Internal function to determine whether an account can control / manage another account

=cut

sub _is_authorized_for_comm {
    my ( $admin, $journal ) = @_;

    return 0 unless $admin->is_person && $journal->is_community;
    return 0 unless $admin->can_manage_other($journal);

    # community must have no users, to avoid confusion
    my @member_userids = $journal->member_userids;
    return 0 if scalar @member_userids > 1;
    return 0 if scalar @member_userids == 1 && $member_userids[0] != $admin->userid;

    return 1;
}

=head2 C<< $self->_rename( $tousername, %opts ) >>

Internal function to do renames. Low-level, no error-checking on inputs. Only call
this when you are sure that all conditions for a rename are satisfied. Returns 1 on
success, 0 on failure.

=cut

sub _rename {
    my ( $self, $tousername, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;
    my $token  = $opts{token};

    my $fromusername = $self->user;

    my $dbh = LJ::get_db_writer() or die "Could not get DB handle";

    # FIXME: transactions possible?
    foreach my $table (qw( user useridmap )) {
        $dbh->do( "UPDATE $table SET user=? WHERE user=?", undef, $tousername, $fromusername );

        if ( $dbh->err ) {
            $errors->add_string( '', $dbh->errstr );
            return 0;
        }
    }

    # invalidate
    DW::User::Rename::_clear_from_cache( $self, $fromusername, $tousername );

    # tell everything else that we renamed
    LJ::Procnotify::add(
        "rename_user",
        {
            user   => $fromusername,
            userid => $self->userid
        }
    );

    $token->apply( userid => $self->userid, from => $fromusername, to => $tousername );

    $self->apply_rename_opts(
        from     => $fromusername,
        to       => $tousername,
        redirect => {
            username => $opts{redirect},
            email    => $opts{redirect_email},
        },
        del => {
            map { $_ => $opts{$_} }
                qw( del_trusted_by del_watched_by del_trusted del_watched del_communities ),
        },
        user => $opts{user},
    );

    # update current object to new username, and update the email under the new username
    $self->{user} = $tousername;
    $self->update_email_alias;

    # infohistory
    $self->infohistory_add( "username", $fromusername );

    # notification
    LJ::Event::SecurityAttributeChanged->new(
        $self,
        {
            action       => 'account_renamed',
            ip           => eval { BML::get_remote_ip() } || "[unknown]",
            old_username => $fromusername,
        }
    )->fire;

    return 1;
}

=head2 C<< $self->apply_rename_opts >>

Apply the stated rename options. Will log.


Arguments are:
=item from, original username (required)
=item to, new username (required)
=item user, user doing the work if separate from user being renamed, e.g., admin of a community (optional)
=item redirect => hashref. (optional) If provided, will handle initial redirect information. If false, will leave as-is.
=item del      => hashref. (optional) If provided, will delete all relationships of the provided types.
=item break_redirect => hashref. (optional) If provided, will break existing redirects

redirect/break_redirect hashref:
=item username, bool, forward or disconnect username. Default disconnect
=item email, bool, forward or disconnect email. Default disconnect

del hashref:
=item del_trusted_by
=item del_watched_by
=item del_trusted
=item del_watched
=item del_communities

=cut

sub apply_rename_opts {
    my ( $self, %opts ) = @_;

    my $from = delete $opts{from};
    my $to   = delete $opts{to};

    my $user = delete $opts{user};

    my %extra_args;

    if ( exists $opts{redirect} && $from && $to ) {
        if ( exists $opts{redirect}->{username} ) {

         # break outgoing redirects
         # we don't want this journal pointing anywhere else, to avoid long chains or possible loops
            $self->break_redirects;
            DW::User::Rename->create_redirect_journal( $from, $to )
                if $opts{redirect}->{username};
        }

        # this deletes the email under the old username
        DW::User::Rename->break_email_redirection( $from, $to )
            unless $opts{redirect}->{username} && $opts{redirect}->{email};

        my @redir;
        push @redir, "J" if $opts{redirect}->{username};
        push @redir, "E" if $opts{redirect}->{username} && $opts{redirect}->{email};

        $extra_args{redir} = join( ":", @redir );
    }

    if ( exists $opts{break_redirect} ) {

        # break incoming redirects
        if ( $opts{break_redirect}->{username} ) {
            my $redirect_u = LJ::load_user($from);
            $redirect_u->break_redirects;
            $redirect_u->set_statusvis("D");
        }

        DW::User::Rename->break_email_redirection( $from, $to )
            if $opts{break_redirect}->{email};

        my @break;
        push @break, "J" if $opts{break_redirect}->{username};
        push @break, "E" if $opts{break_redirect}->{email};

        $extra_args{break} = join( ":", @break );
    }

    $extra_args{del} = $self->delete_relationships( %{ $opts{del} } )
        if %{ $opts{del} || {} };

    $extra_args{from} = $from if $from;
    $extra_args{to}   = $to   if $to;

    my $remote = LJ::isu($user) ? $user : $self;
    $self->log_event(
        'rename',
        {
            remote => $remote,
            %extra_args,
        }
    ) unless $self->is_expunged;    # if expunged, we don't need this info anymore
                                    # also, would error; don't have a cluster 0
}

=head2 C<< $self->break_redirects >>

Break outgoing redirects.

=cut

sub break_redirects {
    my $self = $_[0];

    if ( my $renamedto = $self->prop("renamedto") ) {
        $self->set_prop( renamedto => undef );
        $self->log_event( 'redirect', { renamedto => $renamedto, action => 'remove' } );
    }
}

=head2 C<< DW::User::Rename->create_redirect_journal >>

Set up a new user which will redirect to an existing one. Don't allow to set redirects for existing users.

=cut

sub create_redirect_journal {
    my ( $class, $fromusername, $tousername ) = @_;

    # we can only create a redirect journal for a nonexistent, a purged user, or a redirecting user
    my $fromu = LJ::load_user($fromusername);
    return 0 if $fromu && !( $fromu->is_expunged || $fromu->is_redirect );

    return 0 unless LJ::load_user($tousername);

    # unable to login as this user, because they have an empty password, which is just fine
    $fromu = LJ::User->create(
        user        => $fromusername,
        journaltype => "R",             # redirect
    ) unless $fromu;

    $fromu->set_renamed;
    $fromu->set_prop( renamedto => $tousername );
    $fromu->log_event( 'redirect', { renamedto => $tousername, action => "add" } );

    return 1;

}

=head2 C<< DW::User::Rename->break_email_redirection( $from_user, $to_user ) >>

Break email redirection from one user which redirects to another user

=cut

sub break_email_redirection {
    my ( $class, $from_user, $to_user ) = @_;

    my $to_u   = LJ::load_user($to_user);
    my $from_u = LJ::load_user($from_user);
    return unless $to_u && $from_u;

    return unless $from_u->is_redirect && $from_u->prop("renamedto") eq $to_u->user;

    return $from_u->delete_email_alias;
}

=head2 C<< $self->delete_relationships >>

Delete a list of relationships. Returns a string representation of which relationships were deleted.

=cut

sub delete_relationships {
    my ( $self, %opts ) = @_;

    return unless $self->is_personal;

    if ( $opts{del_trusted_by} ) {
        foreach ( $self->trusted_by_users ) {
            $_->remove_edge( $self, trust => {} );
        }
    }

    if ( $opts{del_watched_by} ) {
        foreach ( $self->watched_by_users ) {
            $_->remove_edge( $self, watch => {} );
        }
    }

    my @watched_comms;
    if ( $opts{del_watched} ) {
        foreach ( $self->watched_users ) {
            if ( $_->is_community ) {
                push @watched_comms, $_ if $opts{del_communities};
                next;
            }

            $self->remove_edge( $_, watch => {} );
        }
    }

    if ( $opts{del_trusted} ) {
        foreach ( $self->trusted_users ) {
            $self->remove_edge( $_, trust => {} );
        }
    }

    # remove admin and community membership edges
    if ( $opts{del_communities} ) {

       # we already have a list of watched communities if we'd fetched the list of journals we watch
        unless ( $opts{del_watched} ) {
            foreach ( $self->watched_users ) {
                push @watched_comms, $_ if $_->is_community;
            }
        }

        foreach (@watched_comms) {
            $self->remove_edge( $_, watch => {} );
        }

        my @ids         = $self->member_of_userids;
        my $memberships = LJ::load_userids(@ids) || {};
        foreach ( values %$memberships ) {
            $self->leave_community($_);
        }
    }

    my @del;
    push @del, "TB" if $opts{del_trusted_by};
    push @del, "WB" if $opts{del_watched_by};
    push @del, "T"  if $opts{del_trusted};
    push @del, "W"  if $opts{del_watched};
    push @del, "C"  if $opts{del_communities};

    return join ":", @del;
}

=head2 C<< $self->_rename_to_ex( $tousername ) >>

Internal function to do renames away from the current username. Low-level, no error-checking on inputs. Accepts a username, renames the user to a form of ex_oldusernam123.

=cut

sub _rename_to_ex {
    my ( $u, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;

    my $dbh = LJ::get_db_writer() or die "Could not get DB handle";

    # move the current username out of the way, if it's an existing user
    my $tries = 0;

    while ( $tries < 10 ) {

        # take the first nineteen characters of the old username + a random number
        my $ex_user = substr( $u->user, 0, 19 ) . int( rand(999) );

        # do the rename if the user doesn't already exist
        return DW::User::Rename::_rename(
            $u, "ex_$ex_user",
            redirect => 0,
            token    => DW::RenameToken->create_token( systemtoken => 1 )
            )
            unless $dbh->selectrow_array( "SELECT COUNT(*) from user WHERE user=?", undef,
            $ex_user );

        $tries++;
    }

    $errors->add( '', "rename.ex.toomanytries", { tousername => $u->user } );
    return 0;
}

*LJ::User::can_rename_to  = \&can_rename_to;
*LJ::User::rename         = \&rename;
*LJ::User::swap_usernames = \&swap_usernames;

*LJ::User::apply_rename_opts    = \&apply_rename_opts;
*LJ::User::break_redirects      = \&break_redirects;
*LJ::User::delete_relationships = \&delete_relationships;

=head1 BUGS

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
