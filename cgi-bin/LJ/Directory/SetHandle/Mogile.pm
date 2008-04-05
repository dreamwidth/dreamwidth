package LJ::Directory::SetHandle::Mogile;
use strict;
use base 'LJ::Directory::SetHandle';
use Class::Autouse qw (LWP::UserAgent);

sub new {
    my ($class, $conskey) = @_;

    my $self = {
        conskey => $conskey,
    };

    return bless $self, $class;
}

sub new_from_string {
    my ($class, $str) = @_;
    $str =~ s/^Mogile:// or die;
    return $class->new($str);
}

sub as_string {
    my $self = shift;
    return "Mogile:" . $self->{conskey};
}

sub mogpaths {
    my $self = shift;
    return @{ $self->{mogpaths} } if $self->{mogpaths};
    my $client = LJ::mogclient() or die "No mogile client";
    my @paths = $client->get_paths($self->mogkey);
    $self->{mogpaths} = \@paths;
    return @paths;
}

sub pack_size {
    my $self = shift;
    return $self->{pack_size} if $self->{pack_size};

    # TODO: do this in the same request as load_matching_uids for fewer round-trips

    my @paths = $self->mogpaths;
    die "can't find it FIXME: calculate it again" unless @paths;

    # do a HEAD reqest
    while (@paths) {
        my $path = shift @paths;
        my $ua = LWP::UserAgent->new;
        my $resp = $ua->head($path);
        next unless $resp->code == 200;
        return $self->{pack_size} = $resp->header("Content-Length");
    }
    die "FIXME: couldn't load it... go recalculate set for $self";
}

sub load_pack_data {
    my ($self, $cb) = @_;
    my @paths = $self->mogpaths;
    die "FIXME: couldn't load it... go recalculate set for $self" unless @paths;

    # stream data with LWP and call callback func with
    # streamed data
    my $ua = LWP::UserAgent->new;
    my $elen = $self->pack_size;  # our expected length
    while (@paths) {
        my $path = shift @paths;

        my $success = 0;   # bool, if this file was a success
        my $readdata = 0;  # counter of bytes read and pushed into callback.

        my $prevfrag = "";
        $ua->get(
                 $path,
                 ':content_cb' => sub {
                     my ($data, $res) = @_;
                     if (! $success && $res->code == 200) {
                         $success = 1;
                         die "Bogus length returned!" unless $res->header("Content-Length") == $elen;
                     }

                     # round down to 4 byte interval, reusing 1-3 bytes from last request
                     $data = $prevfrag . $data;
                     my $len = length($data);
                     my $overflow = $len % 4;
                     $len -= $overflow;
                     $prevfrag = substr($data, $len, $overflow, '');

                     return unless $success;
                     $readdata += $len;
                     eval { $cb->($data) };
                     if ($@) {
                         warn "Error running callback: $@\n";
                         $success = 0;
                         die $@;
                         return 0;
                     }
                     return 1;
                 },
                 );

        next unless $success;
        die "We only read $readdata, not expected amount of $elen" unless $elen == $readdata;
        return;
    }
    die "FIXME: couldn't load it... go recalculate set for $self";
}

sub mogkey {
    my $self = shift;
    return "dsh:" . $self->{conskey};
}

1;
