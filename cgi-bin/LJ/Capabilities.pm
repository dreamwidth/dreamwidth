# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Capabilities;
use strict;

sub class_bit {
    my ($class) = @_;
    foreach my $bit (0..15) {
        my $def = $LJ::CAP{$bit};
        next unless $def->{_key} && $def->{_key} eq $class;
        return $bit;
    }
    return undef;
}

# what class name does a given bit number represent?
sub class_of_bit {
    my $bit = shift;
    return $LJ::CAP{$bit}->{_key};
}

sub classes_from_mask {
    my $caps = shift;

    my @classes = ();
    foreach my $bit (0..15) {
        my $class = class_of_bit( $bit );
        next unless $class && caps_in_group( $caps, $class );
        push @classes, $class;
    }

    return @classes;
}

sub mask_from_classes {
    my @classes = @_;

    my $mask = 0;
    foreach my $class (@classes) {
        my $bit = class_bit( $class );
        $mask |= (1 << $bit);
    }

    return $mask;
}

sub mask_from_bits {
    my @bits = @_;

    my $mask = 0;
    foreach my $bit (@bits) {
        $mask |= (1 << $bit);
    }

    return $mask;
}

sub caps_in_group {
    my ($caps, $class) = @_;
    $caps = $caps ? $caps + 0 : 0;
    my $bit = class_bit( $class );
    die "unknown class '$class'" unless defined $bit;
    return ( $caps & ( 1 << $bit ) ) ? 1 : 0;
}

# <LJFUNC>
# name: LJ::Capabilities::name_caps
# des: Given a user's capability class bit mask, returns a
#      site-specific string representing the capability class(es) name.
# args: caps
# des-caps: 16 bit capability bitmask
# </LJFUNC>
sub name_caps
{
    my $bit = shift;
    my @caps = caps_string( $bit, '_visible_name' );
    if ( @caps ) {
        return join( ', ', @caps );
    } else {
        return name_caps_short( $bit );
    }
}

# <LJFUNC>
# name: LJ::Capabilities::name_caps_short
# des: Given a user's capability class bit mask, returns a
#      site-specific string representing the capability class(es) short name.
# args: caps
# des-caps: 16 bit capability bitmask
# </LJFUNC>
sub name_caps_short
{
    my $bit = shift;
    return join( ', ', caps_string( $bit, '_name' ) );
}

# <LJFUNC>
# name: LJ::Capabilities::caps_string
# des: Given a user's capability class bitfield and a name field key,
#      returns an array of all the account class names.
# args: caps, name_value
# des-caps: bitfield
# des-name_value: string (_name for short name, _visible_name for long)
sub caps_string {
    my ($caps, $name_value) = @_;

    my @classes = ();
    foreach my $bit (0..15) {
        my $class = class_of_bit( $bit );
        next unless $class && caps_in_group( $caps, $class );
        my $name = $LJ::CAP{$bit}->{$name_value} // "";
        push @classes, $name if $name ne "";
    }

    return @classes;
}

# <LJFUNC>
# name: LJ::Capabilities::user_caps_icon
# des: Given a user's capability class bit mask, returns
#      site-specific HTML with the capability class icon.
# args: caps
# des-caps: 16 bit capability bitmask
# </LJFUNC>
sub user_caps_icon
{
    return undef unless LJ::Hooks::are_hooks("user_caps_icon");
    my $caps = shift;
    return LJ::Hooks::run_hook("user_caps_icon", $caps);
}

# <LJFUNC>
# name: LJ::get_cap
# des: Given a user object, capability class key or capability class bit mask
#      and a capability/limit name,
#      returns the maximum value allowed for given user or class, considering
#      all the limits in each class the user is a part of.
# args: u_cap, capname
# des-u_cap: 16 bit capability bitmask or a user object from which the
#            bitmask could be obtained
# des-capname: the name of a limit, defined in [special[caps]].
# </LJFUNC>
sub get_cap
{
    my $caps = shift;   # capability bitmask (16 bits), cap key or user object
    my $cname = shift;  # capability limit name
    my $opts  = shift;  # { no_hook => 1/0 }
    $opts ||= {};

    # If caps is a reference
    my $u = ref $caps ? $caps : undef;

    # If caps is a reference get caps from User object
    if ($u) {
        $caps = $u->{'caps'};
    # If it is not all digits assume it is a key
    } elsif ($caps && $caps !~ /^\d+$/) {
        my $bit = class_bit( $caps ) || 0;
        $caps = 1 << $bit;
    }
    # The caps is the cap mask already or undef, force it to be a number
    $caps += 0;

    my $max = undef;

    # allow a way for admins to force-set the read-only cap
    # to lower writes on a cluster.
    if ($cname eq "readonly" && $u &&
        ($LJ::READONLY_CLUSTER{$u->{clusterid}} ||
         $LJ::READONLY_CLUSTER_ADVISORY{$u->{clusterid}} &&
         ! LJ::get_cap($u, "avoid_readonly"))) {

        # HACK for desperate moments.  in when_needed mode, see if
        # database is locky first
        my $cid = $u->{clusterid};
        if ($LJ::READONLY_CLUSTER_ADVISORY{$cid} eq "when_needed") {
            my $now = time();
            return 1 if $LJ::LOCKY_CACHE{$cid} > $now - 15;

            my $dbcm = LJ::get_cluster_master($u->{clusterid});
            return 1 unless $dbcm;
            my $sth = $dbcm->prepare("SHOW PROCESSLIST");
            $sth->execute;
            return 1 if $dbcm->err;
            my $busy = 0;
            my $too_busy = $LJ::WHEN_NEEDED_THRES || 300;
            while (my $r = $sth->fetchrow_hashref) {
                $busy++ if $r->{Command} ne "Sleep";
            }
            if ($busy > $too_busy) {
                $LJ::LOCKY_CACHE{$cid} = $now;
                return 1;
            }
        } else {
            return 1;
        }
    }

    # is there a hook for this cap name?
    if (! $opts->{no_hook} && LJ::Hooks::are_hooks("check_cap_$cname")) {
        die "Hook 'check_cap_$cname' requires full user object"
            unless LJ::isu($u);

        my $val = LJ::Hooks::run_hook("check_cap_$cname", $u);
        return $val if defined $val;

        # otherwise fall back to standard means
    }

    # otherwise check via other means
    foreach my $bit (keys %LJ::CAP) {
        next unless ($caps & (1 << $bit));
        my $v = $LJ::CAP{$bit}->{$cname};
        next unless (defined $v);
        next if (defined $max && $max > $v);
        $max = $v;
    }
    return defined $max ? $max : $LJ::CAP_DEF{$cname};
}
*LJ::get_cap = \&get_cap;

# <LJFUNC>
# name: LJ::Capabilities::get_cap_min
# des: Just like [func[LJ::get_cap]], but returns the minimum value.
#      Although it might not make sense at first, some things are
#      better when they're low, like the minimum amount of time
#      a user might have to wait between getting updates or being
#      allowed to refresh a page.
# args: u_cap, capname
# des-u_cap: 16 bit capability bitmask or a user object from which the
#            bitmask could be obtained
# des-capname: the name of a limit, defined in [special[caps]].
# </LJFUNC>
sub get_cap_min
{
    my $caps = shift;   # capability bitmask (16 bits), or user object
    my $cname = shift;  # capability name
    if (! defined $caps) { $caps = 0; }
    elsif ( LJ::isu( $caps ) ) { $caps = $caps->{'caps'}; }
    my $min = undef;
    foreach my $bit (keys %LJ::CAP) {
        next unless ($caps & (1 << $bit));
        my $v = $LJ::CAP{$bit}->{$cname};
        next unless (defined $v);
        next if (defined $min && $min < $v);
        $min = $v;
    }
    return defined $min ? $min : $LJ::CAP_DEF{$cname};
}

1;
