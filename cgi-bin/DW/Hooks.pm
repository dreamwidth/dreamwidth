package DW::Hooks;

use strict;

# theoretically these should all be translated, but I am not doing
# that right now because it's easier for the JF team to work with these
# if we don't worry with translation ...

LJ::register_hook( 'name_caps', sub {
    my $caps = shift()+0;

    if ( $caps & 128 ) {
        return "Premium Permanent Account";
    } elsif ( $caps & 64 ) {
        return "Basic Permanent Account";
    } elsif ( $caps & 16 ) {
        return "Premium Paid Account";
    } elsif ( $caps & 8 ) {
        return "Basic Paid Account";;
    } else {
        return "Free Account";
    }
} );

LJ::register_hook( 'name_caps_short', sub {
    my $caps = shift()+0;

    if ( $caps & 128 ) {
        return "Premium Permanent";
    } elsif ( $caps & 64 ) {
        return "Basic Permanent";
    } elsif ( $caps & 16 ) {
        return "Premium Paid";
    } elsif ( $caps & 8 ) {
        return "Basic Paid";;
    } else {
        return "Free";
    }
} );

LJ::register_hook( 'userinfo_rows', sub {
    my $u = $_[0]->{u};
    my $remote = $_[0]->{remote};

    return if $u->is_identity || $u->is_syndicated;

    my $type = LJ::run_hook( 'name_caps', $u->{caps} );

    return ( 'Account Type', $type )
        unless LJ::u_equals( $u, $remote );

    my $ps = DW::Pay::get_paid_status( $u );
    return ( 'Account Type', $type )
        unless $ps && ! $ps->{permanent};

    return ( 'Account Type', "$type<br />Expires: " . LJ::mysql_time( $ps->{expiretime} ) );
} );

1;
