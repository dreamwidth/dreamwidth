package LJ::Directory::PackedUserRecord;
use strict;
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    foreach my $f (qw(updatetime age journaltype regionid)) {
        $self->{$f}= delete $args{$f};
    }
    croak("Unknown args") if %args;
    return $self;
}

sub packed {
    my $self = shift;
    return pack("NCCCx",
                $self->{updatetime} || 0,
                $self->{age} || 0,
                # the byte after age is a bunch of packed fields:
                #   u_int8_t  journaltype:2; // 0: person, 1: openid, 2: comm, 3: syn
                ({
                    P => 0,
                    I => 1,
                    C => 2,
                    Y => 3,
                }->{$self->{journaltype}} || 0) << 0 +
                0,
                $self->{regionid} || 0);

}


1;
