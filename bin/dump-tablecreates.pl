#!/usr/bin/perl

use strict;

BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

my $dbr = LJ::get_db_reader();

foreach my $table ( @{ $dbr->selectcol_arrayref('SHOW TABLES') } ) {
    my ( $table, $table_def ) = $dbr->selectrow_array(qq{SHOW CREATE TABLE $table});
    print qq{
register_tablecreate( "$table", <<'EOC' );
$table_def
EOC
};
}

