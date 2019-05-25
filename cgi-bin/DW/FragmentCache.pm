#!/usr/bin/perl
#
# DW::FragmentCache
#
# This module allows for caching the text return of a sub.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::FragmentCache;
use strict;

=head1 NAME

DW::FragmentCache - memcached fragment cache, with locks.

=head1 SYNOPSIS

=head1 API

=head2 C<< $class->get( $key, $opts, $extra ) >>

Valid $opts:

=over

=item B< lock_failed > - The text returned by this subref is returned if the lock is failed and the grace period is up.

=item B< render > - This subref is only called if the cache is invalid, to regenerate the data

=item B< expire > - Number of seconds the fragment is valid for

=item B< grace_period > - Number of seconds that an expired fragment could still be served if the lock is in place

=back

extra is a hashref that'll be merged with whatever is stored.

=cut

sub get {
    my ( $class, $key, $opts, $extra ) = @_;

    $opts->{expire}       ||= 60;
    $opts->{grace_period} ||= 20;

    my $page = LJ::MemCache::get($key);

    # return from the cache
    if ( $page && $page->[0] > time ) {
        LJ::text_uncompress( \$page->[1] );
        $extra->{$_} = $page->[2]->{$_} foreach keys %{ $page->[2] };
        return $page->[1];
    }

    my $lock = LJ::locker()->trylock($key);
    unless ($lock) {

        # no lock, someone else is updating this.  let's try to print out the stale memcache
        # page if possible, we know that next time it will be updated
        if ( $page && $page->[1] > 0 ) {
            LJ::text_uncompress( \$page->[1] );
            $extra->{$_} = $page->[2]->{$_} foreach keys %{ $page->[2] };
            return $page->[1];
        }

        # if we get here, we don't have any data, and we don't have the lock so we can't
        # construct any data.  this should only happen in the rare case of a memcache
        # flush when multiple people are hitting the page.
        return $opts->{lock_failed}
            ? $opts->{lock_failed}->($extra)
            : "Sorry, something happened.  Please refresh and try again!";
    }

    my $res = $opts->{render}->($extra);
    return $res if $extra->{abort_cache};
    my $out = $res;
    LJ::text_compress( \$out );
    LJ::MemCache::set(
        $key,
        [ time + $opts->{expire}, $out, $extra ],
        $opts->{expire} + $opts->{grace_period}
    );
    return $res;
}

=head1 AUTHOR

=over

=item Mark Smith <mark@dreamwidth.org>

=item Andrea Nall <anall@andreanall.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
