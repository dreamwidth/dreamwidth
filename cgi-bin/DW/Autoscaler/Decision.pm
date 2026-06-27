#!/usr/bin/perl
#
# DW::Autoscaler::Decision
#
# Pure scaling decision for one service. Proportional target
# (desired = ceil(N * O / target)) with asymmetric, hysteretic guards:
# scale out fast (short window) but step- and cooldown-limited; scale in only
# below in_threshold, slowly. The band between in_threshold and target is a
# dead zone (no action) so the controller cannot oscillate.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.

package DW::Autoscaler::Decision;

use strict;
use warnings;
use POSIX qw( ceil floor );

# decide(\%in) -> { desired, action ('out'|'in'|'hold'), reason }
sub decide {
    my ($in) = @_;
    my $n    = $in->{n};
    my $cap  = $in->{cap};
    my $flr  = $in->{floor};

    # Refuse to act on a malformed config rather than misbehaving: target is a
    # divisor (zero/undef => div-by-zero), and a missing floor/cap would let the
    # clamp below coerce desired to undef and potentially drain the service.
    return { desired => $n, action => 'hold', reason => 'config_error' }
        unless $in->{target}
        && $in->{target} > 0
        && defined $cap
        && defined $flr;

    my $clamp = sub {
        my $x = shift;
        $x = $cap if defined $cap && $x > $cap;
        $x = $flr if defined $flr && $x < $flr;
        return $x;
    };

    # ----- scale out? -----
    if ( defined $in->{o_out} && $in->{o_out} >= $in->{target} ) {
        my $raw = ceil( $n * $in->{o_out} / $in->{target} );
        if ( $raw > $n ) {
            return { desired => $n, action => 'hold', reason => 'out_cooldown' }
                if $in->{now} - $in->{last_out} < $in->{out_cooldown};

            my $step = $in->{out_step_min};
            my $pct  = ceil( $n * $in->{out_step_pct} );
            $step = $pct if $pct > $step;

            my $stepped = $n + $step;
            my $desired = $clamp->( $stepped < $raw ? $stepped : $raw );
            my $reason =
                  $desired >= $cap    ? 'out_capped'
                : ( $stepped < $raw ) ? 'out_step_limited'
                :                       'out';
            return {
                desired => $desired,
                action  => $desired > $n ? 'out' : 'hold',
                reason  => $reason,
            };
        }
    }

    # ----- scale in? -----
    if ( defined $in->{o_in} && $in->{o_in} <= $in->{in_threshold} ) {
        my $raw = ceil( $n * $in->{o_in} / $in->{target} );
        if ( $raw < $n ) {
            return { desired => $n, action => 'hold', reason => 'in_cooldown' }
                if $in->{now} - $in->{last_in} < $in->{in_cooldown};

            my $step = $in->{in_step_min};
            my $pct  = floor( $n * $in->{in_step_pct} );
            $step = $pct if $pct > $step;

            my $stepped = $n - $step;
            my $desired = $clamp->( $stepped > $raw ? $stepped : $raw );
            my $reason =
                  $desired <= $flr    ? 'in_floored'
                : ( $stepped > $raw ) ? 'in_step_limited'
                :                       'in';
            return {
                desired => $desired,
                action  => $desired < $n ? 'in' : 'hold',
                reason  => $reason,
            };
        }
    }

    return { desired => $n, action => 'hold', reason => 'deadzone' };
}

1;
