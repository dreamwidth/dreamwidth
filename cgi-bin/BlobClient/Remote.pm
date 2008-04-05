#!/usr/bin/perl
# vim:ts=4 sw=4 et:

package BlobClient::Remote;

use BlobClient;
use LWP::UserAgent;
use Time::HiRes qw{gettimeofday tv_interval};
use vars qw(@ISA);
@ISA = qw(BlobClient);

use strict;

use constant DEBUG => 0;
use constant DEADTIME => 30;

use BlobClient;

### Time a I<block> and send a report for the specified I<op> with the given
### I<notes> when it finishes.
sub report_blocking_time (&@) {
    my ( $block, $op, $notes, $host ) = ( @_ );

    my $start = [gettimeofday()];
    my $rval = $block->();
    LJ::blocking_report( $host, "blob_$op", tv_interval($start), $notes );

    return $rval;
}

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args);

    $self->{ua} = LWP::UserAgent->new(agent=>'blobclient', timeout => 4);

    bless $self, ref $class || $class;
    return $self;
}

sub get {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $use_backup) = @_;
    my $path = $use_backup ? make_backup_path(@_) : make_path(@_);
    return undef unless $path; # if no path, we fail

    print STDERR "Blob::Remote requesting $path (backup path? $use_backup)\n" if DEBUG;
    my $req = HTTP::Request->new(GET => $path);

    my $res;
    report_blocking_time {
        eval { $res = $self->{ua}->request($req); };
    } "get", $path, $self->{path};
    return $res->content if $res->is_success;

    # two types of failure: server dead, or just a 404.
    # a 404 doesn't mean the server is necessarily bad.

    if ($res->code == 500) {
        # server dead.
        if ($use_backup) {
            # can't reach backup server, we're really dead
            $self->{deaduntil} = time() + DEADTIME;
        } else {
            # try using a backup
            return $self->get($cid, $uid, $domain, $fmt, $bid, 1);
        }
    }
    return undef;
}

sub get_stream {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $callback, $use_backup) = @_;
    my $path = $use_backup ? make_backup_path(@_) : make_path(@_);
    return undef unless $path; # if no path, we fail

    my $req = HTTP::Request->new(GET => $path);

    my $res;
    report_blocking_time {
        eval { $res = $self->{ua}->request($req, $callback, 1024*50); };
    } "get_stream", $path, $self->{path};

    return $res->is_success if $res->is_success;

    # must have failed
    if ($res->code == 500) {
        # server dead.
        if ($use_backup) {
            # can't reach backup server, we're really dead
            $self->{deaduntil} = time() + DEADTIME;
        } else {
            # try using a backup
            return $self->get_stream($cid, $uid, $domain, $fmt, $bid, $callback, 1);
        }
    }
    return undef;
}

sub put {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $content, $errref, $use_backup) = @_;
    my $path = $use_backup ? make_backup_path(@_) : make_path(@_);
    return 0 unless $path; # if no path, we fail

    my $req = HTTP::Request->new(PUT => $path);

    $req->content($content);

    my $res;
    report_blocking_time {
        eval { $res = $self->{ua}->request($req); };
    } "put", $path, $self->{path};

    unless ($res->is_success) {
        if ($use_backup) {
            # total failure
            $$errref = "$path: " . $res->status_line if $errref;
            return 0;
        } else {
            # try backup
            return $self->put($cid, $uid, $domain, $fmt, $bid, $content, $errref, 1);
        }
    }
    return 1;
}

sub delete {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $use_backup) = @_;
    my $path = $use_backup ? make_backup_path(@_) : make_path(@_);
    return 0 unless $path; # if no path, we fail

    my $req = HTTP::Request->new(DELETE => $path);

    my $res;
    report_blocking_time {
        eval { $res = $self->{ua}->request($req); };
    } "delete", $path, $self->{path};

    return 1 if $res && $res->code == 404;
    unless ($res->is_success) {
        if ($res->code == 500) {
            if ($use_backup) {
                # total failure!
                return 0;
            } else {
                # try again
                return $self->delete($cid, $uid, $domain, $fmt, $bid, 1);
            }
        }
        return 0;
    }
    return 1;
}

sub is_dead {
    my $self = shift;
    delete $self->{deaduntil} if $self->{deaduntil} <= time();
    return $self->{deaduntil} > 0;
}

### [MG]: Hmmm... no-op?
sub make_path { my $self = shift; return $self->SUPER::make_path(@_); }
sub make_backup_path { my $self = shift; return $self->SUPER::make_backup_path(@_); }

1;
