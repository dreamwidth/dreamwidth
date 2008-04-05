#!/usr/bin/perl
# vim:ts=4 sw=4 et:

use strict;
package BlobClient::Local;

use IO::File;
use File::Path;
use Time::HiRes qw{gettimeofday tv_interval};

use constant DEBUG => 0;

use BlobClient;
our @ISA = ("BlobClient");

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args);
    bless $self, ref $class || $class;
    return $self;
}

### Time a I<block> and send a report for the specified I<op> with the given
### I<notes> when it finishes.
sub report_blocking_time (&@) {
    my ( $block, $op, $notes, $host ) = ( @_ );

    my $start = [gettimeofday()];
    my $rval = $block->();
    LJ::blocking_report( $host, "blob_$op", tv_interval($start), $notes );

    return $rval;
}

sub get {
    my ($self, $cid, $uid, $domain, $fmt, $bid) = @_;
    my $fh = new IO::File;
    local $/ = undef;
    my $path = make_path(@_);
    print STDERR "Blob::Local: requesting $path\n" if DEBUG;

    my $data;
    report_blocking_time {
        unless (open($fh, '<', $path)) {
            return undef;
        }
        print STDERR "Blob::Local: serving $path\n" if DEBUG;
        $data = <$fh>;
        close($fh);
    } "get", $path, $self->{path};

    return $data;
}

sub get_stream {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $callback, $errref) = @_;

    my $fh = new IO::File;
    my $path = make_path(@_);

    my $data;
    report_blocking_time {
        unless (open($fh, '<', $path)) {
            $$errref = "Error opening '$path'";
            return undef;
        }
        while (read($fh, $data, 1024*50)) {
            $callback->($data);
        }
        close($fh);
    } "get_stream", $path, $self->{path};

    return 1;
}

sub put {
    my ($self, $cid, $uid, $fmt, $domain, $bid, $content) = @_;

    my $filename = make_path(@_);

    my $dir = File::Basename::dirname($filename);
    eval { File::Path::mkpath($dir, 0, 0775); };
    return undef if $@;

    report_blocking_time {
        my $fh = new IO::File;
        unless (open($fh, '>', $filename)) {
            return undef;
        }
        print $fh $content;
        close $fh;
    } "put", $filename, $self->{path};

    return 1;
}

sub delete {
    my ($self, $cid, $uid, $fmt, $domain, $bid) = @_;

    my $filename = make_path(@_);

    return 0 unless -e $filename;
    my $rval;
    report_blocking_time {
        # FIXME: rmdir up the tree
        $rval = unlink($filename);
    } "delete", $filename, $self->{path};

    return $rval;
}

sub make_path { my $self = shift; return $self->SUPER::make_path(@_); }

1;
