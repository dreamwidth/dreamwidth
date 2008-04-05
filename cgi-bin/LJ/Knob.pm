package LJ::Knob;
use strict;
use String::CRC32 ();

my %singleton;

# fields:
#   name
#   value -- if defined, loaded.  value in range [0,100] (inclusive)

sub instance {
    my ($class, $knobname) = @_;
    return $singleton{$knobname} ||= LJ::Knob->new($knobname);
}

sub new {
    my ($class, $knobname) = @_;
    my $self = {
        name => $knobname,
    };
    return bless $self, $class;
}

sub memkey {
    my $self = shift;
    return "knob:$self->{name}";
}

sub set_value {
    my ($self, $val) = @_;
    $val += 0;

    my $memkey = $self->memkey;
    LJ::MemCache::set($memkey, $val);
    my $dbh = LJ::get_db_writer();
    $dbh->do("REPLACE INTO knob (knobname, val) VALUES (?, ?)", undef,
             $self->{name}, $val);

    # broadcast to other apache nodes to change
    $self->{value} = $val;

    return 1;
}

sub value {
    my $self = shift;
    return $self->{value} if defined $self->{value};
    my $name = $self->{name};

    my $memkey = $self->memkey;
    my $rv = LJ::MemCache::get($memkey);
    if (defined $rv) {
        return $self->{value} = $rv;
    }

    my $dbh = LJ::get_db_writer();
    $rv = $dbh->selectrow_array("SELECT val FROM knob WHERE knobname=?", undef, $name) + 0;
    LJ::MemCache::add($memkey, $rv);
    return $self->{value} = $rv;
}

use constant HUNDREDTH_OF_32BIT => 42949672;
sub check {
    my ($self, $checkon) = @_;
    my $rand = String::CRC32::crc32($checkon);
    my $val  = $self->value;
    return $rand <= ($val * HUNDREDTH_OF_32BIT);
}

1;
