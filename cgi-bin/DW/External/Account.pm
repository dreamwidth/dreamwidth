#!/usr/bin/perl
#
# DW::External::Account
#
# Describes an External Account that a user can crosspost to.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::External::Account;
use strict;
use warnings;
use DW::External::XPostProtocol;
use Storable;

##
## Memcache routines
##
use base 'LJ::MemCacheable';

sub _memcache_id {
    return $_[0]->userid . ":" . $_[0]->acctid;
}
sub _memcache_key_prefix { "acct" }

sub _memcache_stored_props {

    # first element of props is a VERSION
    # next - allowed object properties
    return qw/ 4
        userid acctid
        siteid username password servicename servicetype serviceurl xpostbydefault recordlink options active
        /;
}

sub _memcache_hashref_to_object {
    my ( $class, $row ) = @_;
    my $u = LJ::load_userid( $row->{userid} );
    return $class->new_from_row( $u, $row );
}

sub _memcache_expires { 24 * 3600 }

# create a new instance of an ExternalAccount
sub instance {
    my ( $class, $u, $acctid ) = @_;

    my $acct = $class->_skeleton( $u, $acctid );
    return $acct;
}
*new = \&instance;

# populates the basic keys for an ExternalAccount; everything else is
# loaded from absorb_row
sub _skeleton {
    my ( $class, $u, $acctid ) = @_;
    return bless {
        userid => $u->userid,
        acctid => int($acctid),
    };
}

# class method.  returns active External Accounts for a User.
# optional: show_inactive => 1 returns inactive accounts as well
sub get_external_accounts {
    my ( $class, $u, %opts ) = @_;

    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    my $show_inactive = $opts{show_inactive};

    my @accounts;

    # see if we can get it from memcache
    my $acctlist = $class->_load_items($u);
    if ($acctlist) {
        foreach my $acctid (@$acctlist) {
            my $account = $class->get_external_account( $u, $acctid );
            push @accounts, $account if $show_inactive || $account->active;
        }
        return @accounts;
    }

    my $sth = $u->prepare(
"SELECT userid, acctid, siteid, username, password, servicename, servicetype, serviceurl, xpostbydefault, recordlink, options, active FROM externalaccount WHERE userid=?"
    );
    $sth->execute( $u->userid, );
    LJ::throw( $u->errstr ) if $u->err;

    my @acctids;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $account = $class->new_from_row( $u, $row );
        push @accounts, $account if $show_inactive || $account->active;
        $account->_store_to_memcache;
        push @acctids, $account->acctid;
    }
    $class->_store_items( $u, \@acctids );
    return @accounts;
}

# class method.  returns the specified External Accounts for a User if it
# exists.
sub get_external_account {
    my ( $class, $u, $acctid ) = @_;

    # try from memcache first.
    my $cached_value = $class->_load_from_memcache( $u->userid . ":$acctid" );
    if ($cached_value) {
        return $cached_value;
    }

    my $sth = $u->prepare(
"SELECT userid, siteid, acctid, username, password, servicename, servicetype, serviceurl, xpostbydefault, recordlink, options, active FROM externalaccount WHERE userid=? and acctid=?"
    );
    $sth->execute( $u->userid, $acctid );
    LJ::throw( $u->err ) if ( $u->err );

    my $account;
    if ( my $row = $sth->fetchrow_hashref ) {
        $account = $class->new_from_row( $u, $row );
    }
    $account->_store_to_memcache if $account;

    return $account;
}

# creates an new ExternalAccount from a DB row
sub new_from_row {
    my ( $class, $u, $row ) = @_;
    die unless $row && $row->{userid} && $row->{acctid};
    my $self = $class->new( $u, $row->{acctid} );
    $self->absorb_row($row);
    return $self;
}

# records the xpost information on the given entry
sub record_xpost {
    my ( $class, $entry, $xpost_ref ) = @_;

    my $xpost_ref_string = $class->xpost_hash_to_string($xpost_ref);
    $entry->set_prop( 'xpost', $xpost_ref_string );
}

# records the xpost detail information on the given entry
sub record_xpost_detail {
    my ( $class, $entry, $xpost_ref ) = @_;

    my $xpost_ref_string = $class->xpost_hash_to_string($xpost_ref);
    $entry->set_prop( 'xpostdetail', $xpost_ref_string );
}

# saves the xpost information to the entry properties
sub xpost_hash_to_string {
    my ( $class, $xpostmap ) = @_;

    return Storable::nfreeze($xpostmap);
}

# gets the xpost mapping from the entry properties
sub xpost_string_to_hash {
    my ( $class, $propstring ) = @_;

    return Storable::thaw($propstring) if ($propstring);
    return {};

}

# instance methods
sub absorb_row {
    my ( $self, $row ) = @_;
    for my $f (
        qw( username siteid password servicename servicetype serviceurl xpostbydefault recordlink options active )
        )
    {
        $self->{$f} = $row->{$f};
    }
    return $self;
}

# creates a new ExternalAccount for the given user using the values in opts
sub create {
    my ( $class, $u, $opts ) = @_;

    my $acctid = LJ::alloc_user_counter( $u, 'X' );
    LJ::throw("failed to allocate new account ID") unless $acctid;

    my $extsite = $opts->{siteid} ? DW::External::Site->get_site_by_id( $opts->{siteid} ) : undef;

    my $protocol_id = $extsite ? $extsite->{servicetype} : $opts->{servicetype};

    my $protocol          = DW::External::XPostProtocol->get_protocol($protocol_id);
    my $encryptedpassword = $protocol->encrypt_password( $opts->{password} );

    # convert the options hashref to a single field
    my $options_blob = $class->xpost_hash_to_string( $opts->{options} );

    $u->do(
"INSERT INTO externalaccount ( userid, acctid, siteid, username, password, servicename, servicetype, serviceurl, xpostbydefault, recordlink, options, active ) values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1 )",
        undef,
        $u->{userid},
        $acctid,
        $opts->{siteid},
        $opts->{username},
        $encryptedpassword,
        $opts->{servicename},
        $opts->{servicetype},
        $opts->{serviceurl},
        $opts->{xpostbydefault} ? '1' : '0',
        $opts->{recordlink}     ? '1' : '0',
        $options_blob
    );

    LJ::throw( $u->errstr ) if $u->err;

    # now return the account object.
    my $acct = $class->new( $u, $acctid ) or LJ::throw("Error instantiating external account");

    # clear the cache.
    $class->_clear_items($u);

    return $acct;
}

# stores a list of items to memcache
sub _store_items {
    my ( $class, $u, $items ) = @_;

    $u->memc_set( "acct", $items, $class->_memcache_expires );
}

# loads a list of items from memcache
sub _load_items {
    my ( $class, $u ) = @_;

    my $data = $u->memc_get("acct");
    return unless $data && ref $data eq 'ARRAY';

    return $data;
}

# removes the itemlist for the given user from memcache.
sub _clear_items {
    my ( $class, $u ) = @_;

    $u->memc_delete("acct");
}

# marks this external account as deleted
# we keep around the actual row for data integrity
# but get rid of sensitive information (password)
sub delete {
    my ($self) = @_;
    my $u = $self->owner;

    $u->do( "UPDATE externalaccount set active=0, password=NULL WHERE userid=? AND acctid=?",
        undef, $u->{userid}, $self->acctid );

    # clear the cache.
    $self->_clear_items($u);
    $self->_remove_from_memcache( $self->_memcache_id );

    return 1;
}

# does the crosspost.  calls the underlying protocol implementation.
# returns a hashref with success => 1 and message => the success
# message on success, or success => 0 and error => the error message
# on failure.
sub crosspost {
    my ( $self, $auth, $entry ) = @_;

    # get the protocol
    my $xpost_protocol = $self->protocol;

    # make sure we hae a proper protocol
    if ($xpost_protocol) {

        # if given an unencrypted password, encrypt it.
        if ( $auth->{password} ) {
            $auth->{encrypted_password} = $xpost_protocol->encrypt_password( $auth->{password} );
        }
        else {
            # include the (encrypted) current password.
            $auth->{encrypted_password} = $self->password;
        }

        # add the username to the auth object
        $auth->{username} = $self->username;

        # see if we're posting or editing
        my $xpost_mapping = $self->xpost_string_to_hash( $entry->prop('xpost') );
        my $xpost_info    = $xpost_mapping->{ $self->acctid };
        my $action_key    = $xpost_info ? "xpost.edit" : "xpost";

        # call crosspost for either create or edit.
        my $result = $xpost_protocol->crosspost( $self, $auth, $entry, $xpost_info );

        # handle the result
        if ( $result->{success} ) {
            $xpost_mapping->{ $self->acctid } = $result->{reference}->{itemid};
            $self->record_xpost( $entry, $xpost_mapping );

            my $xpost_detail_mapping = $self->xpost_string_to_hash( $entry->prop('xpostdetail') );
            $xpost_detail_mapping->{ $self->acctid } = $result->{reference};
            $self->record_xpost_detail( $entry, $xpost_detail_mapping );

            return {
                success => 1,
                message => LJ::Lang::ml(
                    $action_key . ".success",
                    {
                        username  => $self->username,
                        server    => $self->servername,
                        xpostlink => $result->{url}
                    }
                )
            };
        }
        else {
            my $message = $action_key . ".error";
            if ( $result->{code} eq 'entry_deleted' ) {
                undef( $xpost_mapping->{ $self->acctid } );
                $self->record_xpost( $entry, $xpost_mapping );
                my $xpost_detail_mapping =
                    $self->xpost_string_to_hash( $entry->prop('xpostdetail') );
                undef( $xpost_detail_mapping->{ $self->acctid } );
                $self->record_xpost_detail( $entry, $xpost_detail_mapping );
                $message .= '.deleted';
            }
            return {
                success => 0,
                error   => LJ::Lang::ml(
                    $message,
                    {
                        username => $self->username,
                        server   => $self->servername,
                        error    => $result->{error}
                    }
                )
            };
        }
    }
    else {
        return {
            success => 0,
            error   => LJ::Lang::ml("xpost.error.invalidprotocol")
        };
    }
}

# deletes the entry.  calls the underlying protocol implementation.
# returns a hashref with success => 1 and message => the success
# message on success, or success => 0 and error => the error message
# on failure.
sub delete_entry {
    my ( $self, $auth, $entry ) = @_;

    my %returnvalue;

    # get the protocol
    my $xpost_protocol = $self->protocol;

    if ($xpost_protocol) {

        # if given an unencrypted password, encrypt it.
        if ( $auth->{password} ) {
            $auth->{encrypted_password} = $xpost_protocol->encrypt_password( $auth->{password} );
        }
        else {
            # include the (encrypted) current password.
            $auth->{encrypted_password} = $self->password;
        }

        # add the username to the auth object
        $auth->{username} = $self->username;

        # get the associated post
        my $xpost_mapping = $self->xpost_string_to_hash( $entry->prop('xpost') );
        my $xpost_info    = $xpost_mapping->{ $self->acctid };

        my $result = $xpost_protocol->crosspost( $self, $auth, $entry, $xpost_info, 1 );
        if ( $result->{success} ) {
            $returnvalue{success} = 1;
            $returnvalue{message} = LJ::Lang::ml( "xpost.delete.success",
                { username => $self->username, server => $self->servername } );
            $returnvalue{reference} = $result->{reference};
        }
        else {
            $returnvalue{success} = 0;
            $returnvalue{error}   = LJ::Lang::ml(
                "xpost.delete.error",
                {
                    username => $self->username,
                    server   => $self->servername,
                    error    => $result->{error}
                }
            );
        }
    }
    else {
        $returnvalue{success} = 0;
        $returnvalue{error}   = LJ::Lang::ml("xpost.error.invalidprotocol");
    }

    return \%returnvalue;
}

# get a challenge for this server
# passes this on to the xpost protocol
# returns challenge on success, 0 on failure.
sub challenge {
    my $self = shift;
    return $self->protocol->challenge($self);
}

# checks to see if this account supports challenge/response authentication
sub supports_challenge {
    return $_[0]->protocol->supports_challenge;
}

#accessors

sub siteid {
    return $_[0]->{siteid};
}

sub acctid {
    return $_[0]->{acctid};
}

sub userid {
    return $_[0]->{userid};
}

sub owner {
    return LJ::load_userid( $_[0]->userid );
}

sub username {
    return $_[0]->{username};
}

sub password {
    return $_[0]->{password};
}

sub xpostbydefault {
    return $_[0]->{xpostbydefault};
}

sub recordlink {
    return $_[0]->{recordlink};
}

sub active {
    return $_[0]->{active};
}

# returns the (protocol-specific) options as a hash ref
sub options {
    my $self = $_[0];
    unless ( $self->{options_map} ) {
        my $options_map = DW::External::Account->xpost_string_to_hash( $self->{options} );
        $self->{options_map} = $options_map;
    }

    return $self->{options_map};
}

# if there is an external site configured, returns it; otherwise returns undef
sub externalsite {
    return undef unless $_[0]->{siteid};
    return $_[0]->{_externalsite} ||=
        DW::External::Site->get_site_by_id( $_[0]->{siteid} );
}

# returns a displayable servername for this account
sub servername {
    my $self = shift;
    if ( $self->externalsite ) {
        return $self->externalsite->{sitename};
    }
    else {
        return $self->{servicename};
    }
}

# returns a hostname for this account
sub serverhost {
    my $self = shift;
    if ( $self->externalsite ) {
        return $self->externalsite->{hostname};
    }
    else {
        return $self->{servicename};
    }
}

# returns the serviceurl for this account, if set
sub serviceurl {
    return $_[0]->{serviceurl};
}

# returns a displayname for this account
sub displayname {
    return $_[0]->username . "@" . $_[0]->servername;
}

# returns the protocol for this account, either as set directly or
# from the configured site
sub protocol {
    my $self = shift;
    my $servicetype =
        $self->externalsite ? $self->externalsite->{servicetype} : $self->{servicetype};
    my $protocol = DW::External::XPostProtocol->get_protocol($servicetype);
    return $protocol;
}

# updates the xpostbydefault values for this ExternalAccount.
sub set_xpostbydefault {
    my ( $self, $xpostbydefault ) = @_;

    my $u = $self->owner;

    my $newvalue = $xpostbydefault ? '1' : '0';
    unless ( $newvalue eq $self->xpostbydefault ) {
        $u->do( "UPDATE externalaccount SET xpostbydefault=? WHERE userid=? AND acctid=?",
            undef, $newvalue, $u->{userid}, $self->acctid );
        LJ::throw( $u->errstr ) if $u->err;

        $self->{xpostbydefault} = $xpostbydefault;

        $self->_remove_from_memcache( $self->_memcache_id );
    }
    return 1;
}

# updates the recordlink values for this ExternalAccount.
sub set_recordlink {
    my ( $self, $recordlink ) = @_;

    my $u = $self->owner;

    my $newvalue = $recordlink ? '1' : '0';
    unless ( $newvalue eq $self->recordlink ) {
        $u->do( "UPDATE externalaccount SET recordlink=? WHERE userid=? AND acctid=?",
            undef, $newvalue, $u->{userid}, $self->acctid );
        LJ::throw( $u->errstr ) if $u->err;

        $self->{recordlink} = $recordlink;

        $self->_remove_from_memcache( $self->_memcache_id );
    }
    return 1;
}

# updates the password values for this ExternalAccount.
sub set_password {
    my ( $self, $password ) = @_;

    my $u = $self->owner;

    my $newvalue = $self->protocol->encrypt_password($password);
    unless ( $newvalue eq $self->password ) {
        $u->do( "UPDATE externalaccount SET password=? WHERE userid=? AND acctid=?",
            undef, $newvalue, $u->{userid}, $self->acctid );
        LJ::throw( $u->errstr ) if $u->err;

        $self->{password} = $password;

        $self->_remove_from_memcache( $self->_memcache_id );
    }
    return 1;
}

# sets the (protocol-specific) options.  takes a hashref as the options
# argument.
sub set_options {
    my ( $self, $options ) = @_;

    my $u = $self->owner;

    # convert the hash to a string.
    my $newvalue = DW::External::Account->xpost_hash_to_string($options);

    $u->do( "UPDATE externalaccount SET options=? WHERE userid=? AND acctid=?",
        undef, $newvalue, $u->{userid}, $self->acctid );
    LJ::throw( $u->errstr ) if $u->err;

    # set options to the new value and clear options_map
    $self->{options}     = $newvalue;
    $self->{options_map} = undef;

    $self->_remove_from_memcache( $self->_memcache_id );

    return 1;
}

1;
