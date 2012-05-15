use strict;


unless ( $LJ::INC_PATCHED ) {
    push @INC, map { $LJ::HOME . "/lib/" . $_ } (
        'gearman/api/perl/Gearman/lib',
        'TheSchwartz/lib',
        'TheSchwartz-Worker-SendEmail/lib',

        'memcached/api/perl/lib',

        'ddlockd/api/perl',
        'LJ-UserSearch',
    );

    push @INC, ( 'src/DSMS/lib' );

    $LJ::INC_PATCHED = 1;
}

