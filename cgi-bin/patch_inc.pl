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

    {
        my @dirs = ();
        my $ext_path = $LJ::HOME . "/ext/*";

        foreach ( glob( $ext_path ) ) {
            next unless -d $_;
            push @dirs, $_;
            unshift @INC, "$_/cgi-bin" if -d "$_/cgi-bin";
        }
        $LJ::EXT_DIRS = \@dirs;
    }

    $LJ::INC_PATCHED = 1;
}

