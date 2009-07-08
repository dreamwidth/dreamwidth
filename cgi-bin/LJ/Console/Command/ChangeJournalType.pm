package LJ::Console::Command::ChangeJournalType;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_journal_type" }

sub desc { "Change a journal's type." }

sub args_desc { [
                 'journal' => "The username of the journal that type is changing.",
                 'type' => "Either 'person' or 'community'.",
                 'owner' => "The person to become the maintainer of the community journal. If changing to type 'person', the account will adopt the email address and password of the owner.",
                 'force' => "Specify this to create a community from a non-empty journal. The maintainer of the community will be the owner of the journal's entries."
                 ] }

sub usage { '<journal> <type> <owner> [force]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "changejournaltype") || $LJ::IS_DEV_SERVER;
}

sub execute {
    my ($self, $user, $type, $owner, @args) = @_;
    my $remote = LJ::get_remote();

    return $self->error("This command takes from three to four arguments. Consult the reference.")
        unless $user && $type && $owner && (@args==0 || @args==1 && $args[0] eq 'force' && $type eq 'community');

    return $self->error("Type argument must be 'person' or 'community'.")
        unless $type =~ /^(?:person|community)$/;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user: $user")
        unless $u;

    return $self->error("Account cannot be converted while not active.")
        unless $u->is_visible;

    return $self->error("Account is not a personal or community journal.")
        unless $u->journaltype =~ /[PC]/;

    return $self->error("You cannot convert your own account.")
        if LJ::u_equals($remote, $u);

    my $typemap = { 'community' => 'C', 'person' => 'P' };
    return $self->error("This account is already a $type account")
        if $u->journaltype eq $typemap->{$type};

    my $ou = LJ::load_user($owner);
    return $self->error("Invalid username '$owner' specified as owner.")
        unless $ou;
    return $self->error("Owner must be a personal journal.")
        unless $ou->is_person;
    return $self->error("Owner must be an active account.")
        unless $ou->is_visible;
    return $self->error("Owner email address isn't validated.")
        unless $ou->is_validated;

    my $dbh = LJ::get_db_writer();

    #############################
    # going to a personal journal. do they have any entries posted by other users?
    if ($type eq "person") {
        my $dbcr = LJ::get_cluster_def_reader($u);
        my $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM log2 WHERE journalid = ? AND posterid <> journalid',
                                           undef, $u->id);

        return $self->error("Account contains $count entries posted by other users and cannot be converted.")
            if $count;

    # going to a community. do they have any entries posted by themselves?
    # if so, make the new owner of the community to be the owner of these entries
    } else {
        my $dbcr = LJ::get_cluster_def_reader($u);
        my $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM log2 WHERE journalid = ? AND posterid = journalid',
                                           undef, $u->id);
        if ($count) {
            if ($args[0] eq 'force') {
                $u->do("UPDATE log2 SET posterid = ? WHERE journalid = ? AND posterid = journalid", undef, $ou->id, $u->id) 
                    or return $self->error($DBI::errstr);
                $self->info("$count entries of user '$u->{user}' belong to '$ou->{user}' now");
            } else {
                return $self->error("Account contains $count entries posted by the account itself. Use 'force' option if you want to convert it anyway.");
            }
        }
    }

    #############################
    # update the 'community' row, as necessary.
    if ($type eq "community") {
        $dbh->do("INSERT INTO community VALUES (?, 'open', 'members')", undef, $u->id);
    } else {
        $dbh->do("DELETE FROM community WHERE userid = ?", undef, $u->id);
    }

    #############################
    # delete friend-ofs if we're changing to a person account. otherwise
    # the owner can log in and read those users' entries.
    if ($type eq "person") {
        my @ids = $u->friendof_uids;
        $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $u->id);

        LJ::memcache_kill($_, "friends") foreach @ids;
        LJ::memcache_kill($u, "friendofs");
    }

    #############################
    # clear out relations as necessary
    if ($type eq "person") {
        LJ::clear_rel($u, '*', $_) foreach qw(N M A P);

    # give the owner access
    } else {
        LJ::set_rel_multi( [$u->id, $ou->id, 'A'], [$u->id, $ou->id, 'P'] );
    }

    LJ::run_hook("change_journal_type", $u);

    #############################
    # update the user info
    my %extra = ();  # aggregates all the changes we're making


    # update the password
    if ($type eq "community") {
        $extra{password} = '';
    } else {
        $extra{password} = $ou->password;
    }

    LJ::infohistory_add($u, 'password', Digest::MD5::md5_hex($u->password . 'change'))
        if $extra{password} ne $u->password;

    # reset the email address
    $extra{email} = $ou->email_raw;
    $extra{status} = 'A';
    $dbh->do("UPDATE infohistory SET what='emailreset' WHERE userid=? AND what='email'", undef, $u->id)
        or $self->error("Error updating infohistory for emailreset: " . $dbh->errstr);
    LJ::infohistory_add($u, 'emailreset', $u->email_raw, $u->email_status)
        unless $ou->email_raw eq $u->email_raw; # record only if it changed

    # get the new journaltype
    $extra{journaltype} = $typemap->{$type};

    # we haev update!
    LJ::update_user($u, { %extra });

    # journaltype, birthday changed
    $u->invalidate_directory_record;
    $u->set_next_birthday;
    $u->lazy_interests_cleanup;

    #############################
    # register this action in statushistory
    my $msg = "account '" . $u->user . "' converted to $type";
    $msg .= " (owner/parent is '" . $ou->user . "')";
    LJ::statushistory_add($u, $remote, "change_journal_type", $msg);

    return $self->print("User " . $u->user . " converted to a $type account.");
}

1;
