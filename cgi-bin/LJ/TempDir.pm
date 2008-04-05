package LJ::TempDir;
# little OO-wrapper around File::Temp::tempdir, so when object
# DESTROYs, things get cleaned.

use strict;
use File::Temp ();
use File::Path ();

# returns either $obj or ($obj->dir, $obj), when in list context.
# when $obj goes out of scope, all temp directory contents are wiped.
sub new {
    my ($class) = @_;
    my $dir = File::Temp::tempdir() or
        die "Failed to create temp directory: $!\n";
    my $obj = bless {
        dir => $dir,
    }, $class;
    return wantarray ? ($dir, $obj) : $obj;
}

sub directory { $_[0]{dir} };

sub DESTROY {
    my $self = shift;
    File::Path::rmtree($self->{dir}) if $self->{dir} && -d $self->{dir};
}

1;
