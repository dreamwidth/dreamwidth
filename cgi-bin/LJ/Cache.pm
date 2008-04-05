#!/usr/bin/perl
#
# LJ::Cache class
# See perldoc documentation at the end of this file.
#
# -------------------------------------------------------------------------
#
# This package is released under the LGPL (GNU Library General Public License)
#
# A copy of the license has been included with the software as LGPL.txt.  
# If not, the license is available at:
#      http://www.gnu.org/copyleft/library.txt
#
# -------------------------------------------------------------------------
#

package LJ::Cache;

use strict;
use fields qw(items size tail head bytes maxsize maxbytes);

use vars qw($VERSION);
use constant PREVKEY => 0;
use constant VALUE => 1;
use constant NEXTKEY => 2;
use constant BYTES => 3;
use constant INSTIME => 4;
use constant FLAGS => 5;     # caller-defined metadata

$VERSION = '1.0';

sub new {
    my ($class, $args) = @_;
    my $self = fields::new($class);
    
    $self->init($args);
    return $self;
}

sub walk_items {
    my LJ::Cache $self = shift;
    my $code = shift;

    my $iter = $self->{'head'};
    while ($iter) {
        my $it = $self->{'items'}->{$iter};
        $code->($iter, $it->[BYTES], $it->[INSTIME]);
        $iter = $it->[NEXTKEY];
    }
}

sub init {
    my LJ::Cache $self = shift;
    my $args = shift;

    $self->{'head'} = 0;
    $self->{'tail'} = 0;
    $self->{'items'} = {}; # key -> arrayref, indexed by constants above
    $self->{'size'} = 0;
    $self->{'bytes'} = 0;
    $self->{'maxsize'} = $args->{'maxsize'}+0;
    $self->{'maxbytes'} = $args->{'maxbytes'}+0;
}

sub get_item_count {
    my LJ::Cache $self = shift;
    $self->{'size'};
}

sub get_byte_count {
    my LJ::Cache $self = shift;
    $self->{'bytes'};
}

sub get_max_age {
    my LJ::Cache $self = shift;
    return undef unless $self->{'tail'};
    return $self->{'items'}->{$self->{'tail'}}->[INSTIME];
}

sub validate_list
{
    my ($self, $source) = @_;
    print "Validate list: $self->{'size'} (max: $self->{'maxsize'})\n";
    
    my $count = 1;
    if ($self->{'size'} && ! defined $self->{'head'}) {
	die "$source: no head pointer\n";
    }
    if ($self->{'size'} && ! defined $self->{'tail'}) {
	die "$source: no tail pointer\n";
    }
    if ($self->{'size'}) {
	print "  head: $self->{'head'}\n";
	print "  tail: $self->{'tail'}\n";
    }

    my $iter = $self->{'head'};
    my $last = undef;
    while ($count <= $self->{'size'}) {
	if (! defined $iter) {
	    die "$source: undefined iterator\n";
	}
	my $item = $self->{'items'}->{$iter};
	unless (defined $item) {
	    die "$source: item '$iter' isn't in items\n";
	}
	my $prevtext = $item->[PREVKEY] || "--";
	my $nexttext = $item->[NEXTKEY] || "--";
	print "  #$count ($iter): [$prevtext, $item->[VALUE], $nexttext]\n";
	if ($count == 1 && defined($item->[0])) {
	    die "$source: Head element shouldn't have previous pointer!\n";
	}
	if ($count == $self->{'size'} && defined($item->[NEXTKEY])) {
	    die "$source: Last element shouldn't have next pointer!\n";
	}
	if (defined $last && ! defined $item->[PREVKEY]) {
	    die "$source: defined \$last but not defined previous pointer.\n";
	}
	if (! defined $last && defined $item->[PREVKEY]) {
	    die "$source: not defined \$last but previous pointer defined.\n";
	}
	if (defined $item->[PREVKEY] && defined $last && $item->[PREVKEY] ne $last)
	{
	    die "$source: Previous pointer is wrong.\n";
	}

	$last = $iter;
	$iter = defined $item->[NEXTKEY] ? $item->[NEXTKEY] : undef;
	$count++;
    }
}

sub drop_tail
{
    my LJ::Cache $self = shift;

    ## who's going to die?
    my $to_die = $self->{'tail'};

    ## set the tail to the item before the one dying.
    $self->{'tail'} = $self->{'items'}->{$to_die}->[PREVKEY];

    ## adjust the forward pointer on the tail to be undef
    if (defined $self->{'tail'}) {
	undef $self->{'items'}->{$self->{'tail'}}->[NEXTKEY];
    }

    ## kill the item
    my $bytes = $self->{'items'}->{$to_die}->[BYTES];
    delete $self->{'items'}->{$to_die};

    ## shrink the overall size
    $self->{'size'}--;
    $self->{'bytes'} -= $bytes;
}

sub print_list {
    my LJ::Cache $self = shift;

    print "Size: $self->{'size'} (max: $self->{'maxsize'})\n";

    my $count = 1;
    my $iter = $self->{'head'};
    while (defined $iter) { #$count <= $self->{'size'}) {
	my $item = $self->{'items'}->{$iter};
	print "$count: $iter = $item->[VALUE]\n";
	$iter = $item->[NEXTKEY];
 	$count++;
    }
}

sub get {
    my LJ::Cache $self = shift;
    my ($key, $out_flags) = @_;

    if (exists $self->{'items'}->{$key}) 
    {
	my $item = $self->{'items'}->{$key};

	# promote this to the head
	unless ($self->{'head'} eq $key)
	{
	    if ($self->{'tail'} eq $key) {
		$self->{'tail'} = $item->[PREVKEY];
	    }
	    # remove this element from the linked list.
	    my $next = $item->[NEXTKEY];
	    my $prev = $item->[PREVKEY];
	    if (defined $next) { $self->{'items'}->{$next}->[PREVKEY] = $prev; }
	    if (defined $prev) { $self->{'items'}->{$prev}->[NEXTKEY] = $next; }
	    
	    # make current head point backwards to this item
	    $self->{'items'}->{$self->{'head'}}->[PREVKEY] = $key;
	    
	    # make this item point forwards to current head, and backwards nowhere
	    $item->[NEXTKEY] = $self->{'head'};
	    undef $item->[PREVKEY];
	    
	    # make this the new head
	    $self->{'head'} = $key;
	}
	
        $$out_flags = $item->[FLAGS] if $out_flags;
	return $item->[VALUE];
    }
    return undef;
}

# bytes is optional
sub set {
    my LJ::Cache $self = shift;
    my ($key, $value, $bytes, $flags) = @_;
    
    $self->drop_tail() while ($self->{'maxsize'} && 
                              $self->{'size'} >= $self->{'maxsize'} &&
                              ! exists $self->{'items'}->{$key}) ||
                              ($self->{'maxbytes'} && $self->{'size'} &&
                               $self->{'bytes'} + $bytes >= $self->{'maxbytes'} &&
                               ! exists $self->{'items'}->{$key});
    
    
    if (exists $self->{'items'}->{$key}) {
	# update the value
	my $it = $self->{'items'}->{$key};
	$it->[VALUE] = $value;
        my $bytedelta = $bytes - $it->[BYTES];
        $self->{'bytes'} += $bytedelta;
        $it->[BYTES] = $bytes;
        $it->[FLAGS] = $flags;
    } else {
	# stick it at the end, for now
	my $it = $self->{'items'}->{$key} = [];
        $it->[PREVKEY] = undef;
        $it->[NEXTKEY] = undef;
        $it->[VALUE] = $value;
        $it->[BYTES] = $bytes;
        $it->[INSTIME] = time();
        $it->[FLAGS] = $flags;
	if ($self->{'size'}) {
	    $self->{'items'}->{$self->{'tail'}}->[NEXTKEY] = $key;
	    $self->{'items'}->{$key}->[PREVKEY] = $self->{'tail'};
	} else {
	    $self->{'head'} = $key;
	}
	$self->{'tail'} = $key;
	$self->{'size'}++;
	$self->{'bytes'} += $bytes;
    }

    # this will promote it to the top:
    $self->get($key);
}

1;
__END__

=head1 NAME

LJ::Cache - LRU Cache

=head1 SYNOPSIS

  use LJ::Cache;
  my $cache = new LJ::Cache { 'maxsize' => 20 };
  my $value = $cache->get($key);
  unless (defined $value) {
      $val = "load some value";
      $cache->set($key, $value);
  }

=head1 DESCRIPTION

This class implements an LRU dictionary cache.  The two operations on it
are get() and set(), both of which promote the key being referenced to
the "top" of the cache, so it will stay alive longest.

When the cache is full and and a new item needs to be added, the oldest
one is thrown away.

You should be able to regenerate the data at any time, if get() 
returns undef.

This class is useful for caching information from a slower data source
while also keeping a bound on memory usage.

=head1 AUTHOR

Brad Fitzpatrick, bradfitz@bradfitz.com

=cut
