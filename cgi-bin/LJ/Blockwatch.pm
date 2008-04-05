package LJ::Blockwatch;

use strict;
use warnings;

# We have to depend on these, so all the subroutines we wrap up are already defined
# by the time we actually do that.
use DBI;
use DDLockClient;
use Gearman::Client;
use MogileFS::Client;

my $er;

our $no_trace;

my %event_by_id;
my %event_by_name;

sub get_eventring {
    return $er if $er;

    my $root = $LJ::BLOCKWATCH_ROOT || return;

    return unless LJ::ModuleCheck->have("Devel::EventRing");

    if (-d $root || mkdir $root) {
        return $er = Devel::EventRing->new("$root/$$", auto_unlink => 1);
    }

    # $root isn't dir, and mkdir failed.
    warn "Unable to create blockwatch path '$root': $!";
    return;
}

sub get_event_id {
    my ($pkg, $name) = @_;

    return $event_by_name{$name} if exists $event_by_name{$name};

    local $no_trace = 1; # so no instrumentation can recurse.

    update_from_memcache();
    return $event_by_name{$name} if exists $event_by_name{$name};

    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT IGNORE INTO blockwatch_events (name) VALUES (?)",
             undef, $name);

    update_from_dbh();
    return $event_by_name{$name} if exists $event_by_name{$name};

    warn "Unable to allocate event ID for '$name'";
    return;
}

sub get_event_name {
    my ($pkg, $id) = @_;

    return $event_by_id{$id} if exists $event_by_id{$id};

    local $no_trace = 1; # so no instrumentation can recurse.

    update_from_memcache();
    return $event_by_id{$id} if exists $event_by_id{$id};


    update_from_dbh();

    return $event_by_id{$id} if exists $event_by_id{$id};

    warn "No event named for id:$id";
    return;
}

sub update_from_memcache {
    my ($ids_from_memcache, $names_from_memcache) = LJ::MemCache::get_multi('blockwatch_ids', 'blockwatch_names');

    eval {
        %event_by_id = %{Storable::thaw($ids_from_memcache)};
    };

    eval {
        %event_by_name = %{Storable::thaw($names_from_memcache)};
    };
}

sub update_from_dbh {
    my $dbh = LJ::get_db_reader();
    my $sth = $dbh->prepare("SELECT id, name FROM blockwatch_events");
    $sth->execute;

    # TODO Catch dbi errors here and return.

    %event_by_id   = ();
    %event_by_name = ();

    while (my ($id, $name) = $sth->fetchrow_array) {
        $event_by_id{$id}     = $name;
        $event_by_name{$name} = $id;
    }

    LJ::MemCache::set('blockwatch_ids', Storable::nfreeze(\%event_by_id));
    LJ::MemCache::set('blockwatch_names', Storable::nfreeze(\%event_by_name));
}

sub start {
    my ($pkg, @parts) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->have("Devel::EventRing");

    my $event_name = join ":", @parts;
    my $event_id = LJ::Blockwatch->get_event_id($event_name) || return;
    my $er = get_eventring();
    $er->start_operation($event_id);
}

sub end {
    my ($pkg, @parts) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->have("Devel::EventRing");

    my $event_name = join ":", @parts;
    my $event_id = LJ::Blockwatch->get_event_id($event_name) || return;
    my $er = get_eventring();
    $er->end_operation($event_id);
}

sub operation {
    my ($pkg, @parts) = @_;
    return 0 if $no_trace;
    return 0 unless LJ::ModuleCheck->have("Devel::EventRing");

    my $event_name = join ":", @parts;
    my $event_id = LJ::Blockwatch->get_event_id($event_name) || return;
    my $er = get_eventring();
    my $op = $er->operation($event_id); # returns handle which, when DESTROYed, closes operation
    return $op;
}

sub wrap_sub {
    my ($name, %args) = @_;
    no strict 'refs';
    no warnings 'redefine';
    my $oldcv = *{$name}{CODE};

    warn "Attempting to wrap a subroutine ('$name') which doesn't exist yet." unless $oldcv;
    *{$name} = sub {
        my @toafter;
        if ($args{before}) {
            @toafter = eval { $args{before}->(@_) };
            warn "before $name caused error: $@\n" if $@;
        }
        my $wa = wantarray;
        my @rv;
        if ($wa) {
            @rv = $oldcv->(@_);
        } else {
            $rv[0] = $oldcv->(@_);
        }
        if ($args{after}) {
            eval { $args{after}->(\@rv, @toafter) };
            warn "after $name caused error: $@\n" if $@;
        }
        return $wa ? @rv : $rv[0];
    };
}

# DBI Hooks

wrap_sub("DBI::connect",
         before => sub {
             my ($class, $dsn) = @_;
             return $dsn;
         },
         after => sub {
             my ($resarray, $dsn) = @_;
             my $dbi = $resarray->[0] || return;

             my %attrs;
             $attrs{dsn} = $dsn;

             my ($dbname, $options) = $dsn =~ m/^DBI:mysql:([^;]+)(?:;(.*))?$/;

             $options ||= '';

             $attrs{dbname} = $dbname;

             my %options = map { split /=/, $_, 2 }
                           split /;/, $options;

             $attrs{host} = $options{host};
             $attrs{port} = $options{port};

             $dbi->{private_blockwatch} = \%attrs;
         });

foreach my $towrap (qw(selectrow_array do selectall_hashref selectrow_hashref commit rollback begin_work)) {
    wrap_sub("DBI::db::$towrap",
             before => sub {
                 my ($db) = @_;
                 my $conninfo = $db->{private_blockwatch} || {};

                 return LJ::Blockwatch->operation("dbi", $towrap,
                                                  $conninfo->{dbname} || "",
                                                  $db->{private_role}   || "",
                                                  $conninfo->{host}   || "",
                                                  $conninfo->{port}   || "",);
             });
}

wrap_sub("DBI::db::prepare",
         before => sub {
             my ($db) = @_;
             my $conninfo = $db->{private_blockwatch} || {};

             return $db, LJ::Blockwatch->operation("dbi", "prepare",
                                                   $conninfo->{dbname} || "",
                                                   $db->{private_role}   || "",
                                                   $conninfo->{host}   || "",
                                                   $conninfo->{port}   || "",);
         },
         after => sub {
             my ($resarray, $db) = @_;
             my $st = $resarray->[0];
             if ($db) {
                 $st->{private_blockwatch} = $db->{private_blockwatch};
                 $st->{private_role} = $db->{private_role};
             }
         });

foreach my $towrap (qw(execute)) {# fetchrow_array fetchrow_arrayref fetchrow_hashref fetchall_arrayref fetchall_hashref)) {
    wrap_sub("DBI::st::$towrap",
             before => sub {
                 my ($sth) = @_;
                 my $conninfo = $sth->{private_blockwatch} || {};

                 return LJ::Blockwatch->operation("dbi", $towrap,
                                                  $conninfo->{dbname} || "",
                                                  $sth->{private_role}   || "",
                                                  $conninfo->{host}   || "",
                                                  $conninfo->{port}   || "",);
             });
}

# Gearman hooks
sub setup_gearman_hooks {
    my $class = shift;
    my $gearclient = shift;

    $gearclient->add_hook('new_task_set', \&gearman_new_task_set);
    # do_background
}

sub gearman_new_task_set {
    my ($gearclient, $taskset) = @_;

    $taskset->add_hook('add_task', \&taskset_add_task);
}

sub taskset_add_task {
    # Build the closure first, so it doesn't capture anything extra.
    my $done = 0;
    my $hook = sub {
        return if $done;
        my $task = shift;
        LJ::Blockwatch->end("gearman", $task->func);
        $done = 1;
    };

    my ($taskset, $task) = @_;
    LJ::Blockwatch->start("gearman", $task->func);

    $task->add_hook('complete', $hook);
    $task->add_hook('final_fail', $hook);
}

# MogileFS Hooks

sub setup_mogilefs_hooks {
    my %hooks;

    # Create the coderefs first, before we pull our arguments in, so that we don't capture things.
    # Capturing the mogclient object in this subroutine would cause it to never be destroyed.

    foreach my $name (qw(new_file store_file store_content get_paths get_file_data delete rename)) {
        $hooks{"${name}_start"} = sub { LJ::Blockwatch->start("mogilefs", $name); };
        $hooks{"${name}_end"}   = sub { LJ::Blockwatch->end("mogilefs", $name);   };
    }

    my $class = shift;
    my $mogclient = shift;

    while (my ($name, $coderef) = each %hooks) {
        $mogclient->add_hook($name, $coderef);
    }

    $mogclient->add_backend_hook(do_request_start           => \&do_request_start);
    $mogclient->add_backend_hook(do_request_send_error      => \&do_request_end);
    $mogclient->add_backend_hook(do_request_length_mismatch => \&do_request_end);
    $mogclient->add_backend_hook(do_request_read_timeout    => \&do_request_end);
    $mogclient->add_backend_hook(do_request_finished        => \&do_request_end);
}

sub do_request_start {
    my ($cmd, $host) = @_;
    LJ::Blockwatch->start("mogilefs", "do_request", $cmd, $host);
}

sub do_request_end {
    my ($cmd, $host) = @_;
    LJ::Blockwatch->end("mogilefs", "do_request", $cmd, $host);
}

# DDLock Hooks

sub setup_ddlock_hooks {
    my $class = shift;
    my $locker = shift;
    $locker->set_hook('trylock',         \&ddlock_trylock);
    $locker->set_hook('trylock_success', \&ddlock_trylock_success);
    $locker->set_hook('trylock_failure', \&ddlock_trylock_failure);
}

sub ddlock_trylock {
    LJ::Blockwatch->start("ddlock");
}

sub ddlock_trylock_success {
    LJ::Blockwatch->end("ddlock");
}

sub ddlock_trylock_failure {
    LJ::Blockwatch->end("ddlock");
}

# Memcache Hooks

sub setup_memcache_hooks {
    my $class = shift;
    my $memcache = shift;

    # There are no memcache hooks anymore, but mark my words... someday they will come back.

    return;
}

1;
