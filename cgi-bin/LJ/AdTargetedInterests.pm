package LJ::AdTargetedInterests;

use strict;

sub blobcache_key  { 'ad_targeted_interests' }
sub procnotify_key { 'ad_targeted_interests_refresh' }

sub save_string {
    my $class  = shift;
    my $intstr = shift;

    # update blobcache table with new value
    LJ::blobcache_replace($class->blobcache_key, $intstr);

    # issue procnotify request for nodes to reload this data
    LJ::procnotify_add($class->procnotify_key, { instime => time() });

    # and update this process in memory
    $class->set_cache($intstr);

    return 1;
}

sub load_string {
    my $class = shift;

    my $cache_ref = $class->cached_hashref; # hashref
    unless ($cache_ref) {

        # cache miss, reload and return from cache
        $class->reload;

        $cache_ref = $class->cached_hashref;
    }

    return "" unless $cache_ref;
    return join(", ", sort { $a cmp $b } keys %$cache_ref);
}

sub load_hashref {
    my $class = shift;

    my $cache_ref = $class->cached_hashref; # hashref
    return $cache_ref if $cache_ref;

    # cache miss, reload and return from cache
    $class->reload;

    return $class->cached_hashref;
}

sub reload {
    my $class = shift;

    my $intstr = LJ::blobcache_get($class->blobcache_key);

    my @list = LJ::interest_string_to_list($intstr);

    $class->set_cache(\@list);

    return;
}

sub cached_hashref {
    my $class = shift;
    
    return $LJ::CACHE_AD_TARGETED_INTERESTS;
}

sub set_cache {
    my $class = shift;
    my $arg = shift;

    if (ref $arg eq 'ARRAY') {
        return $LJ::CACHE_AD_TARGETED_INTERESTS = { map { $_ => 1 } @$arg };
    }

    if (ref $arg eq 'HASH') {
        return $LJ::CACHE_AD_TARGETED_INTERESTS = $arg;
    }

    if (length $arg) {
        my @list = LJ::interest_string_to_list($arg);
        return $class->set_cache(\@list);
    }

    die "invalid ref to cache: $arg";
}

sub sort_interests {
    my $class = shift;
    my $listref = shift;

    my $hashref = $class->load_hashref;

    @$listref = sort { 

        # prioritized interests will always sort smaller than everything else
        $hashref->{$a} ? -1 : $hashref->{$b} ? 1 

        # the rest gets sorted randomly
        : int(rand(3))-1 

    } @$listref;

    return $listref;
}

1;
