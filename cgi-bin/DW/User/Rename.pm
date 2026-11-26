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
use DW::Cache;
use DW::Task::CommunityRenameNotice;
use Log::Log4perl;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

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
    return _can_rename_to( $self, $tousername, \&LJ::load_user, undef, %opts );
}

sub _can_rename_to {
    my ( $self, $tousername, $load_target, $dbh, %opts ) = @_;

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

        if ( $tou->is_renamed && $tou->is_redirect && ( my $next = $tou->prop('renamedto') ) ) {
            my $target = $tou->get_renamed_user;
            $errors->add(
                'touser',
                'rename.error.redirect',
                {
                    to     => LJ::ehtml( $tou->user ),
                    target => LJ::ehtml( $target && !$target->is_redirect ? $target->user : $next ),
                }
            );
            return { ret => 0 };
        }

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
        my $tou = $load_target->($tousername);

        # check basic stuff that is common for all types of renames
        my $rv = $check_basics->( $self, $tou );
        return $rv->{ret} if $rv;

        # deleted and visible journals have extra safeguards:
        # person-to-person
        return 1 if DW::User::Rename::_are_same_person( $self, $tou );

        # person-to-community (only under restricted circumstances for the community)
        return _can_use_community_name( $self, $tou, $errors, $dbh )
            if $tou->is_community;

        $errors->add( 'touser', 'rename.error.unauthorized2', { to => $tou->ljuser_display } );
        return 0;

    }
    elsif ( $self->is_community && LJ::isu( $opts{user} ) ) {
        my $admin = $opts{user};

        unless ( _is_authorized_for_comm( $admin, $self, $dbh ) ) {
            $errors->add(
                $formid,
                'rename.error.notcommunityadmin',
                { comm => $self->ljuser_display }
            );
            return 0;
        }

        my $tou = $load_target->($tousername);

        # check basic stuff that is common for all renames
        my $rv = $check_basics->( $self, $tou );
        return $rv->{ret} if $rv;

        # community-to-person
        # able to rename to another personal journal under admin's control
        return 1 if $tou->is_person && DW::User::Rename::_are_same_person( $admin, $tou );

        return _can_use_community_name( $admin, $tou, $errors, $dbh )
            if $tou->is_community;
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

    my $errors = $opts{errors} ||= DW::FormErrors->new;

    $errors->add( 'token', 'rename.error.tokeninvalid' )
        unless $opts{token} && $opts{token}->isa("DW::RenameToken");
    $errors->add( 'token', 'rename.error.tokenapplied' )
        if $opts{token} && ( $opts{token}->applied || $opts{token}->revoked );

    return 0 if $errors->exist;

    my $fromusername = $self->user;
    my ( $source, $target, %aside );
    return 0 unless _change_usernames(
        $errors,
        \%aside,
        sub {
            my ($dbh) = @_;
            $source = _lock_username( $dbh, $fromusername );
            return 0 unless $source && $source->id == $self->id;
            my $load_target = sub { $target = _lock_username( $dbh, $_[0] ) };
            return 0 unless _can_rename_to( $source, $tousername, $load_target, $dbh, %opts );

            $tousername = LJ::canonical_username($tousername);
            $target     = $load_target->($tousername) if $opts{force};
            if ($target) {
                $aside{name} = _unused_ex_username( $dbh, $tousername, $errors ) or return 0;
                return 0 unless _write_username( $dbh, $target, $tousername, $aside{name} );
            }
            return 0 unless _write_username( $dbh, $source, $fromusername, $tousername );
            return 0
                if $target
                && !_enqueue_community_rename_notice( $dbh, $target, $tousername, $aside{name} );
            return _enqueue_community_rename_notice( $dbh, $source, $fromusername, $tousername );
        }
    );

    _clear_from_cache( $self,   $fromusername, $tousername );
    _clear_from_cache( $target, $tousername,   $aside{name} ) if $target;
    _apply_customer_tokens( [ $opts{token}, $self, $fromusername, $tousername ] );
    _finish_move_aside( $target, $tousername, \%aside, $errors ) if $target;
    _finish_rename( $self, $fromusername, $tousername, %opts );
    return $errors->exist ? 0 : 1;
}

=head2 C<< $self->swap_usernames( $touser [, %opts ] ) >>

Swap the usernames of these two users.

=cut

sub swap_usernames {
    my ( $u1, $u2, %opts ) = @_;

    my $errors = $opts{errors} ||= DW::FormErrors->new;

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
            if $token && ( $token->applied || $token->revoked );
    }

    return 0 if $errors->exist;
    if ( scalar @tokens >= 2 ) {
        $errors->add( 'token', 'rename.error.tokenduplicate' )
            if ( $tokens[0]->token eq $tokens[1]->token );
    }
    else {
        $errors->add( 'token', 'rename.error.tokentoofew' );
    }

    return 0 if $errors->exist;

    my $u1name = $u1->user;
    my $u2name = $u2->user;
    my ( %aside, %admin_opts );
    return 0 unless _change_usernames(
        $errors,
        \%aside,
        sub {
            my ($dbh) = @_;
            my %locked = map { $_ => _lock_username( $dbh, $_ ) } sort ( $u1name, $u2name );
            my ( $first, $second ) = @locked{ $u1name, $u2name };
            return 0 unless $first && $first->id == $u1->id && $second && $second->id == $u2->id;

            %admin_opts = $second->is_community ? ( user => $admin ) : ();
            my $load_target = sub { $locked{ $_[0] } };
            return 0
                unless _can_rename_to( $first, $u2name, $load_target, $dbh, %opts, %admin_opts )
                && _can_rename_to( $second, $u1name, $load_target, $dbh, %opts, %admin_opts );

            $aside{name} = _unused_ex_username( $dbh, $u2name, $errors ) or return 0;
            return 0
                unless _write_username( $dbh, $second, $u2name, $aside{name} )
                && _write_username( $dbh, $first,  $u1name,      $u2name )
                && _write_username( $dbh, $second, $aside{name}, $u1name );

            return _enqueue_community_rename_notice( $dbh, $first,  $u1name, $u2name )
                && _enqueue_community_rename_notice( $dbh, $second, $u2name, $u1name );
        }
    );

    _clear_from_cache( $u1, $u1name,      $u2name );
    _clear_from_cache( $u2, $aside{name}, $u1name );
    _apply_customer_tokens(
        [ $tokens[0], $u1, $u1name,      $u2name ],
        [ $tokens[1], $u2, $aside{name}, $u1name ],
    );
    _finish_move_aside( $u2, $u2name, \%aside, $errors, $u1name );

    # ugh, but need it to avoid duplicate timestamps in infohistory
    sleep(1);

    _finish_rename( $u1, $u1name, $u2name, %opts, %admin_opts );
    _finish_rename( $u2, $aside{name}, $u1name, %opts, %admin_opts, error_from => $u2name );
    return $errors->exist ? 0 : 1;
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
    delete @LJ::CACHE_USERID{ $fromusername, $tousername };
    DW::Cache->request->remove( 'user_name', $fromusername );
    DW::Cache->request->remove( 'user_name', $tousername );
    DW::Cache->request->remove( 'user_id',   $self->userid );
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
    return 0 unless $p1->is_validated || $p2->is_validated;

    return 1;
}

=head2 C<< $self->_is_authorized_for_comm >>

Internal function to determine whether an account can control / manage another account

=cut

sub _is_authorized_for_comm {
    my ( $admin, $journal, $dbh ) = @_;

    return 0 unless $admin->is_person && $journal->is_community;
    return 0 if $admin->id == $journal->id;
    if ($dbh) {
        return $dbh->selectrow_array(
            "SELECT targetid FROM reluser WHERE userid=? AND type='A' AND targetid=? FOR UPDATE",
            undef, $journal->id, $admin->id );
    }
    return $admin->can_manage_other($journal);
}

sub _can_use_community_name {
    my ( $admin, $journal, $errors, $locked_dbh ) = @_;

    my $allowed = eval {
        my $dbh = $locked_dbh || LJ::get_db_reader();
        if ( $dbh && _is_authorized_for_comm( $admin, $journal, $locked_dbh ) ) {
            my $sql = "SELECT targetid FROM reluser FORCE INDEX (PRIMARY) "
                . "WHERE userid=? AND type='E' AND targetid<>? LIMIT 1";
            $sql .= ' FOR UPDATE' if $locked_dbh;
            my $members = $dbh->selectcol_arrayref( $sql, undef, $journal->id, $admin->id );
            defined $members && !$dbh->err && !@$members;
        }
    };
    return 1 if $allowed;

    $errors->add( 'touser', 'rename.error.communitytarget', { comm => $journal->ljuser_display } );
    return 0;
}

sub _change_usernames {
    my ( $errors, $aside, $change ) = @_;

    my $changed = eval {
        my $dbh = LJ::get_db_writer() or die 'No username writer';
        local $dbh->{RaiseError} = 1;
        local $dbh->{PrintError} = 0;
        $dbh->do('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
        $dbh->begin_work;

        my $committed = eval {
            my ($transactional_tables) = $dbh->selectrow_array(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() "
                    . "AND table_name IN ('user', 'useridmap', 'reluser') AND engine='InnoDB'" );
            if ( $transactional_tables == 3 && $change->($dbh) ) {
                if ( $aside->{name} ) {
                    $aside->{token} = DW::RenameToken->create_token( systemtoken => 1, dbh => $dbh )
                        or die 'No system rename token';
                }
                $dbh->commit;
            }
        };
        unless ($committed) {
            $dbh->rollback unless $dbh->{AutoCommit};
            if ( $aside->{token} ) {
                $dbh->do( "DELETE FROM renames WHERE renid=? AND status='U'",
                    undef, $aside->{token}->id );
            }
        }
        $committed;
    };
    $errors->add( 'touser', 'rename.error.usernamechanged' ) unless $changed || $errors->exist;
    return $changed;
}

sub _lock_username {
    my ( $dbh, $username ) = @_;

    my $row =
        $dbh->selectrow_hashref( 'SELECT * FROM user WHERE user=? FOR UPDATE', undef, $username );
    my ($mapped_id) = $dbh->selectrow_array( 'SELECT userid FROM useridmap WHERE user=? FOR UPDATE',
        undef, $username );
    die 'Inconsistent username mapping' if ( $row ? $row->{userid} : 0 ) != ( $mapped_id || 0 );
    return $row ? LJ::User->new_from_row($row) : undef;
}

sub _write_username {
    my ( $dbh, $user, $fromusername, $tousername ) = @_;

    my $changed = $dbh->do(
        'UPDATE user JOIN useridmap USING (userid) SET user.user=?, useridmap.user=? '
            . 'WHERE user.userid=? AND user.user=? AND useridmap.user=?',
        undef, $tousername, $tousername, $user->id, $fromusername, $fromusername
    );
    return $changed && $changed > 0;
}

sub _enqueue_community_rename_notice {
    my ( $dbh, $user, $fromusername, $tousername ) = @_;
    return 1 unless $user->is_community;

    local $user->{user} = $tousername;
    return DW::Task::CommunityRenameNotice->enqueue( $dbh, $user->id, $fromusername, $tousername,
        $user->profile_url );
}

sub _apply_customer_tokens {
    my @errors;
    foreach my $change (@_) {
        my ( $token, $user, $from, $to ) = @$change;
        my $applied = eval { $token->apply( userid => $user->id, from => $from, to => $to ) };
        push @errors, ( $@ || 'Could not apply customer rename token ' . $token->id )
            unless $applied;
    }
    die $errors[0] if @errors;
}

sub _finish_rename {
    my ( $self, $fromusername, $tousername, %opts ) = @_;

    $self->{user} = $tousername;
    my $options_applied = eval {
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
        1;
    };
    unless ($options_applied) {
        $log->error( 'Could not apply post-rename options for user ' . $self->id . ": $@" );
        $opts{errors}->add(
            '',
            'rename.error.postcommitoptions',
            {
                from => $opts{error_from} // $fromusername,
                to   => $opts{error_to}   // $tousername,
            }
        );
    }

    my $updated = eval {
        $self->update_email_alias;
        $self->infohistory_add( "username", $fromusername );
    };
    $log->error( 'Could not update post-rename records for user ' . $self->id . ": $@" )
        unless $updated;

    # notification
    my $notified = eval {
        LJ::Event::SecurityAttributeChanged->new(
            $self,
            {
                action       => 'account_renamed',
                ip           => LJ::get_remote_ip() || "[unknown]",
                old_username => $fromusername,
            }
        )->fire;
    };
    $log->error('Could not dispatch account rename security event') unless $notified;

    return 1;
}

sub _log_rename_event {
    my ( $user, $event, $details ) = @_;
    my $logged = eval { $user->log_event( $event, $details ) };
    $log->error( "Could not log $event for user " . $user->id . ": $@" ) unless $logged;
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
            die "Could not create rename redirect from $from to $to"
                if $opts{redirect}->{username}
                && !DW::User::Rename->create_redirect_journal( $from, $to );
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
    _log_rename_event(
        $self, 'rename',
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
        $self->set_prop( renamedto => undef ) or die 'Could not remove rename redirect';
        _log_rename_event( $self, 'redirect', { renamedto => $renamedto, action => 'remove' } );
        return 1;
    }
    return;
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

    return 0 unless $fromu && $fromu->set_renamed && $fromu->set_prop( renamedto => $tousername );
    _log_rename_event( $fromu, 'redirect', { renamedto => $tousername, action => 'add' } );

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

    return $from_u->delete_email_alias || die 'Could not remove rename email redirect';
}

=head2 C<< $self->delete_relationships >>

Delete a list of relationships. Returns a string representation of which relationships were deleted.

=cut

sub delete_relationships {
    my ( $self, %opts ) = @_;

    return unless $self->is_personal;

    if ( $opts{del_trusted_by} ) {
        foreach ( $self->trusted_by_users ) {
            $_->remove_edge( $self, trust => {} ) or die 'Could not remove incoming trust';
        }
    }

    if ( $opts{del_watched_by} ) {
        foreach ( $self->watched_by_users ) {
            $_->remove_edge( $self, watch => {} ) or die 'Could not remove incoming watch';
        }
    }

    my @watched_comms;
    if ( $opts{del_watched} ) {
        foreach ( $self->watched_users ) {
            if ( $_->is_community ) {
                push @watched_comms, $_ if $opts{del_communities};
                next;
            }

            $self->remove_edge( $_, watch => {} ) or die 'Could not remove outgoing watch';
        }
    }

    if ( $opts{del_trusted} ) {
        foreach ( $self->trusted_users ) {
            $self->remove_edge( $_, trust => {} ) or die 'Could not remove outgoing trust';
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
            $self->remove_edge( $_, watch => {} ) or die 'Could not remove community watch';
        }

        my @ids         = $self->member_of_userids;
        my $memberships = LJ::load_userids(@ids) || {};
        foreach ( values %$memberships ) {
            $self->leave_community($_) or die 'Could not leave community';
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

sub _unused_ex_username {
    my ( $dbh, $username, $errors ) = @_;

    for ( 1 .. 10 ) {
        my $ex_user = 'ex_' . substr( $username, 0, 19 ) . int( rand(999) );
        return $ex_user unless _lock_username( $dbh, $ex_user );
    }

    $errors->add( '', 'rename.ex.toomanytries', { tousername => $username } );
    return;
}

sub _finish_move_aside {
    my ( $user, $fromusername, $aside, $errors, $finalname ) = @_;

    my $token = $aside->{token};
    my $applied =
        eval { $token->apply( userid => $user->id, from => $fromusername, to => $aside->{name} ); };
    $log->error( 'Could not apply system rename token ' . $token->id . ": $@" ) unless $applied;
    _finish_rename(
        $user, $fromusername, $aside->{name},
        redirect => 0,
        errors   => $errors,
        error_to => $finalname
    );
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
