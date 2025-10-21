#!/usr/bin/perl
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
#
# This program will bring your LiveJournal database schema up-to-date
#

use strict;

BEGIN { $LJ::_T_CONFIG = $ENV{DW_TEST}; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use Getopt::Long;
use File::Path ();
use File::Basename qw/ dirname /;
use File::Copy ();
use Cwd qw/ abs_path /;
use Image::Size ();
use LJ::S2;

my $opt_sql     = 0;
my $opt_drop    = 0;
my $opt_pop     = 0;
my $opt_confirm = "";
my $opt_skip    = "";
my $opt_help    = 0;
my $cluster     = 0;    # by default, upgrade master.
my $opt_listtables;
my $opt_nostyles;
my $opt_forcebuild    = 0;
my $opt_compiletodisk = 0;
my $opt_innodb;
my $opt_poptest = 0;

exit 1
    unless GetOptions(
    "runsql"        => \$opt_sql,
    "drop"          => \$opt_drop,
    "populate"      => \$opt_pop,
    "confirm=s"     => \$opt_confirm,
    "cluster=s"     => \$cluster,
    "skip=s"        => \$opt_skip,
    "help"          => \$opt_help,
    "listtables"    => \$opt_listtables,
    "nostyles"      => \$opt_nostyles,
    "forcebuild|fb" => \$opt_forcebuild,
    "ctd"           => \$opt_compiletodisk,
    "innodb"        => \$opt_innodb,
    );

$opt_nostyles = 1 unless LJ::is_enabled("update_styles");
$opt_nostyles = 1 if $ENV{DW_TEST};
$opt_innodb   = 1;

if ($opt_help) {
    die "Usage: update-db.pl
  -r  --runsql       Actually do the SQL, instead of just showing it.
  -p  --populate     Populate the database with the latest required base data.
  -d  --drop         Drop old unused tables (default is to never)
      --cluster=<n>  Upgrade cluster number <n> (defaut,0 is global cluster)
      --cluster=<n>,<n>,<n>
      --cluster=user Update user clusters
      --cluster=all  Update user clusters, and global
  -l  --listtables   Print used tables, one per line.
      --nostyles     When used in combination with --populate, disables population
                     of style information.
      --innodb       Use InnoDB when creating tables.
";
}

## make sure $LJHOME is set so we can load & run everything
unless ( -d $ENV{'LJHOME'} ) {
    die "LJHOME environment variable is not set, or is not a directory.\n"
        . "You must fix this before you can run this database update script.";
}

die "Can't --populate a cluster" if $opt_pop && ( $cluster && $cluster ne "all" );

my @clusters;
foreach my $cl ( split( /,/, $cluster ) ) {
    die "Invalid cluster spec: $cl\n"
        unless $cl =~ /^\s*((\d+)|all|user)\s*$/;
    if ( $cl eq "all" ) { push @clusters, 0, @LJ::CLUSTERS; }
    elsif ( $cl eq "user" ) { push @clusters, @LJ::CLUSTERS; }
    else                    { push @clusters, $1; }
}
@clusters = (0) unless @clusters;

my $su;                 # system user, not available until populate mode
my %status;             # clusterid -> string
my %clustered_table;    # $table -> 1
my $sth;
my %table_exists;    # $table -> 1
my %table_unknown;   # $table -> 1
my %table_create;    # $table -> $create_sql
my %table_drop;      # $table -> 1
my %table_status;    # $table -> { SHOW TABLE STATUS ... row }
my %post_create;     # $table -> [ [ $action, $what ]* ]
my %coltype;         # $table -> { $col -> $type }
my %indexname;       # $table -> "INDEX"|"UNIQUE" . ":" . "col1-col2-col3" -> "PRIMARY" | index_name
my @alters;
my $dbh;

CLUSTER: foreach my $cluster (@clusters) {
    print "Updating cluster: $cluster\n" unless $opt_listtables;
    ## make sure we can connect
    $dbh = $cluster ? LJ::get_cluster_master($cluster) : LJ::get_db_writer();
    unless ($dbh) {
        $status{$cluster} =
            "ERROR: Can't connect to the database (clust\#$cluster), so I can't update it. ("
            . DBI->errstr . ")";
        next CLUSTER;
    }

    # reset everything
    %clustered_table  = %table_exists = %table_unknown =
        %table_create = %table_drop   = %post_create = %coltype = %indexname = %table_status = ();
    @alters = ();

    ## figure out what tables already exist (but not details of their structure)
    $sth = $dbh->prepare("SHOW TABLES");
    $sth->execute;
    while ( my ($table) = $sth->fetchrow_array ) {
        next if $table =~ /^(access|errors)\d+$/;
        $table_exists{$table} = 1;
    }
    %table_unknown = %table_exists;    # for now, later we'll delete from table_unknown

    ## very important that local is run first!  (it can define tables that
    ## the site-wide would drop if it didn't know about them already)

    my $load_datfile = sub {
        my $file  = shift;
        my $local = shift;
        return if $local && !-e $file;
        open( F, $file ) or die "Can't find database update file at $file\n";
        my $data;
        {
            local $/ = undef;
            $data = <F>;
        }
        close F;
        eval $data;
        die "Can't run $file: $@\n" if $@;
        return 1;
    };

    foreach my $fn ( LJ::get_all_files("bin/upgrading/update-db-local.pl") ) {
        $load_datfile->( $fn, 1 );
    }
    foreach my $fn ( LJ::get_all_files("bin/upgrading/update-db-general.pl") ) {
        $load_datfile->($fn);
    }

    foreach my $t ( sort keys %table_create ) {
        delete $table_drop{$t} if ( $table_drop{$t} );
        print "$t\n" if $opt_listtables;
    }
    exit if $opt_listtables;

    foreach my $t ( keys %table_drop ) {
        delete $table_unknown{$t};
    }

    foreach my $t ( keys %table_unknown ) {
        print "# Warning: unknown live table: $t\n";
    }

    my $run_alter = $table_exists{dbnotes};

    ## create tables
    foreach my $t ( keys %table_create ) {
        next if $table_exists{$t};
        create_table($t);
    }

    ## drop tables
    foreach my $t ( keys %table_drop ) {
        next unless $table_exists{$t};
        drop_table($t);
    }

    if ($run_alter) {
        ## do all the alters
        foreach my $s (@alters) {
            $s->( $dbh, $opt_sql );
        }
    }
    else {
        print "## Skipping alters this pass, please re-run once the 'dbnotes' table exists.";
    }

    $status{$cluster} = "OKAY";
}

print "\ncluster: status\n";
foreach my $clid ( sort { $a <=> $b } keys %status ) {
    printf "%7d: %s\n", $clid, $status{$clid};
}
print "\n";

if ($opt_pop) {
    $dbh = LJ::get_db_writer()
        or die "Couldn't get master handle for population.";
    populate_database();
}

print "# Done.\n";

############################################################################

sub populate_database {
    populate_basedata();
    populate_proplists();

    # system user
    my $made_system;
    ( $su, $made_system ) = vivify_system_user();

    populate_moods();
    populate_external_moods();

    # we have a flag to disable population of s1/s2 if the user requests
    unless ($opt_nostyles) {
        populate_s2();
    }

    print
"\nThe system user was created with a random password.\nRun \$LJHOME/bin/upgrading/make_system.pl to change its password and grant the necessary privileges."
        if $made_system;

    print "\nRemember to also run:\n  bin/upgrading/texttool.pl load\n\n"
        if $LJ::IS_DEV_SERVER;

}

sub vivify_system_user {
    my $freshly_made = 0;
    my $su           = LJ::load_user("system");
    unless ($su) {
        print "System user not found. Creating with random password.\n";
        my $pass = LJ::make_auth_code(10);
        $su = LJ::User->create(
            user     => 'system',
            name     => 'System Account',
            password => $pass
        );
        die "Failed to create system user." unless $su;
        $freshly_made = 1;
    }
    return wantarray ? ( $su, $freshly_made ) : $su;
}

sub populate_s2 {

    # S2
    print "Populating public system styles (S2):\n";
    {
        my $sysid = $su->{'userid'};

        # find existing re-distributed layers that are in the database
        # and their styleids.
        my $existing = LJ::S2::get_public_layers( { force => 1 }, $sysid );

        my %known_id;
        chdir "$ENV{'LJHOME'}/" or die;
        my %layer;    # maps redist_uniq -> { 'type', 'parent' (uniq), 'id' (s2lid) }

        my $has_new_layer = 0;
        my $compile       = sub {
            my ( $base, $type, $parent, $s2source, $LD ) = @_;
            return unless $s2source =~ /\S/;

            my $id = $existing->{$base} ? $existing->{$base}->{'s2lid'} : 0;
            unless ($id) {
                my $parentid = 0;
                $parentid = $layer{$parent}->{'id'} unless $type eq "core";

                # allocate a new one.
                $dbh->do(
                    "INSERT INTO s2layers (s2lid, b2lid, userid, type) "
                        . "VALUES (NULL, $parentid, $sysid, ?)",
                    undef, $type
                );
                die $dbh->errstr if $dbh->err;
                $id = $dbh->{'mysql_insertid'};
                if ($id) {
                    $dbh->do(
                        "INSERT INTO s2info (s2lid, infokey, value) VALUES (?,'redist_uniq',?)",
                        undef, $id, $base );
                }
            }
            die "Can't generate ID for '$base'" unless $id;

            # remember it so we don't delete it later.
            $known_id{$id} = 1;

            $layer{$base} = {
                'type'   => $type,
                'parent' => $parent,
                'id'     => $id,
            };

            my $parid = $layer{$parent}->{'id'};

            # see if source changed
            my $md5_source   = Digest::MD5::md5_hex($s2source);
            my $source_exist = LJ::S2::load_layer_source($id);
            my $md5_exist    = Digest::MD5::md5_hex($source_exist);

            $has_new_layer = 1 unless $source_exist;

            # skip compilation if source is unchanged and parent wasn't rebuilt.
            return if $md5_source eq $md5_exist && !$layer{$parent}->{'built'} && !$opt_forcebuild;

            print "$base($id) is $type";
            if ($parid) { print ", parent = $parent($parid)"; }
            print "\n";

            # we're going to go ahead and build it.
            $layer{$base}->{'built'} = 1;

            # Since we might fork, we disconnect here and then people can get a new one.
            LJ::DB::disconnect_dbs();

            # Fork out a child so it can compile. This saves us the memory usage.
            if ( my $pid = fork ) {
                $dbh = LJ::get_db_writer();
                waitpid $pid, 0;
                die if $? >> 8 != 0;
                return;
            }
            else {
                $dbh = LJ::get_db_writer();
            }

            # compile!
            my $lay = {
                's2lid'  => $id,
                'userid' => $sysid,
                'b2lid'  => $parid,
                'type'   => $type,
            };
            my $error = "";
            my $compiled;
            my $info;

            # do this in an eval, so that if the layer_compile call returns an error,
            # we die and pass it up in $@.  but if layer_compile dies, it should pass up
            # an error itself, which we can get.
            eval {
                die $error
                    unless LJ::S2::layer_compile(
                    $lay,
                    \$error,
                    {
                        's2ref'       => \$s2source,
                        'redist_uniq' => $base,
                        'compiledref' => \$compiled,
                        'layerinfo'   => \$info,
                    }
                    );
            };

            if ($@) {
                print "S2 compilation failed: $@\n";
                exit 1;
            }

            if ($opt_compiletodisk) {
                open( CO, ">$LD/$base.pl" ) or die;
                print CO $compiled;
                close CO;
            }

            # put raw S2 in database.
            LJ::S2::set_layer_source( $id, \$s2source );

            # We are the child, so we can exit here.
            exit;
        };

        my @layerfiles = LJ::get_all_files( "styles/s2layers.dat", home_first => 1 );
        while (@layerfiles) {
            my $file = abs_path( shift @layerfiles );
            next unless -e $file;
            open( SL, $file ) or die;
            my $LD     = dirname($file);
            my $d_file = $file;
            my $d_LD   = $LD;

            $d_file =~ s!^\Q$LJ::HOME\E/*!!;
            $d_LD   =~ s!^\Q$LJ::HOME\E/*!!;

            print "SOURCE: $d_file ( $d_LD )\n";

            while (<SL>) {
                s/\#.*//;
                s/^\s+//;
                s/\s+$//;
                next unless /\S/;
                my ( $base, $type, $parent ) = split;

                if ( $type eq "INCLUDE" ) {
                    unshift @layerfiles, dirname($file) . "/$base";
                    next;
                }

                if ( $type ne "core" && !defined $layer{$parent} ) {
                    die "'$base' references unknown parent '$parent'\n";
                }

                # is the referenced $base file really an aggregation of
                # many smaller layers?  (likely themes, which tend to be small)
                my $multi = ( $type =~ s/\+$// );

                my $s2source;
                open( L, "$LD/$base.s2" ) or die "Can't open file: $base.s2\n";

                unless ($multi) {

      # check if this layer should be mapped to another layer (i.e. exact copy except for layerinfo)
                    if ( $type =~ s/\(([^)]+)\)// )
                    {    # grab the layer in the parentheses and erase it
                        open( my $map_layout, "$LD/$1.s2" ) or die "Can't open file: $1.s2\n";
                        while (<$map_layout>) { $s2source .= $_; }
                    }
                    while (<L>) { $s2source .= $_; }
                    $compile->( $base, $type, $parent, $s2source, $LD );
                }
                else {
                    my $curname;
                    while (<L>) {
                        if (/^\#NEWLAYER:\s*(\S+)/) {
                            my $newname = $1;
                            $compile->( $curname, $type, $parent, $s2source );
                            $curname  = $newname;
                            $s2source = "";
                        }
                        elsif (/^\#NEWLAYER/) {
                            die "Badly formatted \#NEWLAYER line";
                        }
                        elsif ($curname) {
                            $s2source .= $_;
                        }
                        else {
                            # skip any lines before the first #NEWLAYER section
                        }
                    }
                    $compile->( $curname, $type, $parent, $s2source, $LD );
                }
                close L;
            }
            close SL;
        }

        if ($LJ::IS_DEV_SERVER) {

            # now, delete any system layers that don't below (from previous imports?)
            my @del_ids;
            my $sth =
                $dbh->prepare("SELECT s2lid FROM s2layers WHERE userid=? AND NOT type='user'");
            $sth->execute($sysid);
            while ( my $id = $sth->fetchrow_array ) {
                next if $known_id{$id};
                push @del_ids, $id;
            }

            # if we need to delete things, prompt before blowing away system layers
            if (@del_ids) {
                print
"\nWARNING: The following S2 layer ids are known as system layers but are no longer\n"
                    . "present in the import files.  If this is expected and you really want to DELETE\n"
                    . "these layers, type 'YES' (in all capitals).\n\nType YES to delete layers "
                    . join( ', ', @del_ids ) . ": ";
                my $inp = <STDIN>;
                if ( $inp =~ /^YES$/ ) {
                    print "\nOkay, I am PERMANENTLY DELETING the layers.\n";
                    LJ::S2::delete_layer($_) foreach @del_ids;
                }
                else {
                    print "\nOkay, I am NOT deleting the layers.\n";
                }
            }

            if ($has_new_layer) {
                $LJ::CACHED_PUBLIC_LAYERS = undef;
                LJ::MemCache::delete("s2publayers");

                print "\nCleared styles cache.\n";
            }
        }

    }
}

sub populate_basedata {

    # base data
    foreach my $ffile ( LJ::get_all_files( "bin/upgrading/base-data.sql", home_first => 1 ) ) {
        my $d_file = $ffile;
        $d_file =~ s!^\Q$LJ::HOME\E/*!!;

        print "Populating database with $d_file.\n";
        open( BD, $ffile ) or die "Can't open $d_file file\n";
        while ( my $q = <BD> ) {
            chomp $q;    # remove newline
            next unless ( $q =~ /^(REPLACE|INSERT|UPDATE)/ );
            chop $q;     # remove semicolon
            $dbh->do($q);
            if ( $dbh->err ) {
                print "$q\n";
                die "#  ERROR: " . $dbh->errstr . "\n";
            }
        }
        close(BD);
    }
}

sub populate_proplists {
    foreach my $ffile ( LJ::get_all_files( "bin/upgrading/proplists.dat", home_first => 1 ) ) {
        populate_proplist_file( $ffile, "general" );
    }

    foreach my $ffile ( LJ::get_all_files( "bin/upgrading/proplists-local.dat", home_first => 1 ) )
    {
        populate_proplist_file( $ffile, "local" );
    }
}

sub populate_proplist_file {
    my ( $file, $scope ) = @_;
    open( my $fh, $file ) or die "Failed to open $file: $!";

    my %pk = (
        'userproplist'    => 'name',
        'logproplist'     => 'name',
        'media_prop_list' => 'name',
        'talkproplist'    => 'name',
        'usermsgproplist' => 'name',
    );
    my %id = (
        'userproplist'    => 'upropid',
        'logproplist'     => 'propid',
        'media_prop_list' => 'propid',
        'talkproplist'    => 'tpropid',
        'usermsgproplist' => 'propid',
    );

    my $table;    # table
    my $pk;       # table's primary key name
    my $pkv;      # primary key value
    my %vals;     # hash of column -> value, including primary key

    my %current_props;

    foreach $table ( keys %pk ) {
        $pk = $pk{$table};
        my $id = $id{$table};

        $current_props{$table} = $dbh->selectall_hashref( "SELECT `$id`,`$pk` FROM `$table`", $pk );
    }

    my $insert = sub {
        return unless %vals;
        my $sets = join( ", ", map { "$_=" . $dbh->quote( $vals{$_} ) } keys %vals );
        my $idk  = $id{$table};

        my $rv = 0;
        unless ( $current_props{$table}{$pkv} ) {
            $rv = $dbh->do("INSERT INTO $table SET $sets");
            die $dbh->errstr if $dbh->err;
            $current_props{$table}{$pkv} =
                { name => $pkv, $idk => $dbh->last_insert_id( undef, undef, $table, $idk ) };
        }

        # zero-but-true:  see if row didn't exist before, so above did nothing.
        # in that case, update it.
        if ( $rv < 1 ) {
            $rv = $dbh->do( "UPDATE $table SET $sets WHERE $pk=?", undef, $pkv );
            die $dbh->errstr if $dbh->err;
        }

        $table = undef;
        %vals  = ();
    };
    while (<$fh>) {
        next if /^\#/;

        if (/^(\w+)\.(\w+):/) {
            $insert->();
            ( $table, $pkv ) = ( $1, $2 );
            $pk = $pk{$table} or die "Don't know non-numeric primary key for table '$table'";
            $vals{$pk} = $pkv;
            $vals{"scope"} = $scope;
            next;
        }
        if (/^\s+(\w+)\s*:\s*(.*)/) {
            die "Unexpected line: $_ when not in a block" unless $table;
            $vals{$1} = $2;
            next;
        }
        if (/\S/) {
            die "Unxpected line: $_";
        }
    }
    $insert->();
    close($fh);
}

sub populate_external_moods {
    my $moodfile = "$ENV{'LJHOME'}/bin/upgrading/moods-external.dat";

    if ( open MOODFILE, "<$moodfile" ) {
        print "Populating mood data for external sites.\n";

        # $siteid => { $mood => { siteid => $siteid, mood => $mood, moodid => $moodid } }
        my $moods = $dbh->selectall_hashref( "SELECT siteid, mood, moodid FROM external_site_moods",
            [ 'siteid', 'mood' ] );

        foreach my $line (<MOODFILE>) {
            chomp $line;

            if ( $line =~ /^(\d+)\s+(\d+)\s+(.+)$/ ) {
                my ( $siteid, $moodid, $mood ) = ( $1, $2, $3 );

                unless ( $moods->{$siteid}
                    && $moods->{$siteid}->{$mood}
                    && $moods->{$siteid}->{$mood}->{moodid} eq $moodid )
                {
                    $dbh->do(
"REPLACE INTO external_site_moods ( siteid, mood, moodid ) VALUES ( ?, ?, ? )",
                        undef, $siteid, $mood, $moodid
                    );
                }
            }
        }

        close MOODFILE;
    }
}

sub populate_moods {
    foreach my $moodfile ( LJ::get_all_files( "bin/upgrading/moods.dat", home_first => 1 ) ) {
        if ( open( M, $moodfile ) ) {
            my $file = $moodfile;
            $file =~ s!^\Q$LJ::HOME\E/*!!;

            print "Populating mood data [ $file ].\n";

            my %mood;    # id -> [ mood, parent_id ]
            my $sth = $dbh->prepare("SELECT moodid, mood, parentmood, weight FROM moods");
            $sth->execute;
            while ( @_ = $sth->fetchrow_array ) { $mood{ $_[0] } = [ $_[1], $_[2], $_[3] ]; }

            my %moodtheme;    # name -> [ id, des ]
            $sth =
                $dbh->prepare("SELECT moodthemeid, name, des FROM moodthemes WHERE is_public='Y'");
            $sth->execute;
            while ( @_ = $sth->fetchrow_array ) { $moodtheme{ $_[1] } = [ $_[0], $_[2] ]; }

            my $themeid;      # current themeid (from existing db or just made)
            my %data;         # moodid -> "$url$width$height" (for equality test)

            while (<M>) {
                chomp;
                if (/^MOOD\s+(\d+)\s+(.+)\s+(\d+)\s+(\d+)\s*$/) {
                    my ( $id, $mood, $parid, $weight ) = ( $1, $2, $3, $4 );
                    if (  !$mood{$id}
                        || $mood{$id}->[0] ne $mood
                        || $mood{$id}->[1] ne $parid )
                    {
                        $dbh->do(
"REPLACE INTO moods (moodid, mood, parentmood, weight) VALUES (?,?,?,?)",
                            undef, $id, $mood, $parid, $weight
                        );
                    }
                    elsif ( !defined $mood{$id}->[2] ) {
                        $dbh->do( "UPDATE moods SET weight = ? WHERE moodid = ?",
                            undef, $weight, $id );
                    }
                }

                if (/^MOODTHEME\s+(.+?)\s*:\s*(.+)$/) {
                    my ( $name, $des ) = ( $1, $2 );
                    %data = ();
                    if ( $moodtheme{$name} ) {
                        $themeid = $moodtheme{$name}->[0];
                        if ( $moodtheme{$name}->[1] ne $des ) {
                            $dbh->do( "UPDATE moodthemes SET des=? WHERE moodthemeid=?",
                                undef, $des, $themeid );
                        }
                        $sth = $dbh->prepare( "SELECT moodid, picurl, width, height "
                                . "FROM moodthemedata WHERE moodthemeid=?" );
                        $sth->execute($themeid);
                        while ( @_ = $sth->fetchrow_array ) {
                            $data{ $_[0] } = "$_[1]$_[2]$_[3]";
                        }
                    }
                    else {
                        $dbh->do(
                            "INSERT INTO moodthemes (ownerid, name, des, is_public) "
                                . "VALUES (?,?,?,'Y')",
                            undef, $su->{'userid'}, $name, $des
                        );
                        $themeid = $dbh->{'mysql_insertid'};
                        die "Couldn't generate themeid for theme $name\n" unless $themeid;
                    }
                    next;
                }

                if (/^(\d+)\s+(\S+)\s+(\d+)\s+(\d+)\s*$/) {
                    next unless $themeid;
                    my ( $moodid, $url, $w, $h ) = ( $1, $2, $3, $4 );
                    next if $data{$moodid} eq "$url$w$h";
                    $dbh->do(
                        "REPLACE INTO moodthemedata (moodthemeid, moodid, picurl, width, height) "
                            . "VALUES (?,?,?,?,?)",
                        undef, $themeid, $moodid, $url, $w, $h
                    );
                    LJ::MemCache::delete( [ $themeid, "moodthemedata:$themeid" ] );
                }
            }
            close M;
            LJ::MemCache::delete("moods_public");
        }
    }
}

sub skip_opt {
    return $opt_skip;
}

sub do_sql {
    my $sql = shift;
    chomp $sql;
    my $disp_sql = $sql;
    $disp_sql =~ s/\bIN \(.+\)/IN (...)/g;
    print "$disp_sql;\n";
    if ($opt_sql) {
        print "# Running...\n";
        $dbh->do($sql);
        if ( $dbh->err ) {
            die "#  ERROR: " . $dbh->errstr . "\n";
        }
    }
}

sub do_code {
    my ( $what, $code ) = @_;
    print "Code block: $what\n";
    if ($opt_sql) {
        print "# Running...\n";
        $code->();
    }
}

sub try_sql {
    my $sql = shift;
    print "$sql;\n";
    if ($opt_sql) {
        print "# Non-critical SQL (upgrading only... it might fail)...\n";
        $dbh->do($sql);
        if ( $dbh->err ) {
            print "#  Acceptable failure: " . $dbh->errstr . "\n";
        }
    }
}

sub try_alter {
    my ( $table, $sql ) = @_;
    return if $cluster && !defined $clustered_table{$table};

    try_sql($sql);

    # columns will have changed, so clear cache:
    clear_table_info($table);
}

sub do_alter {
    my ( $table, $sql ) = @_;
    return if $cluster && !defined $clustered_table{$table};

    do_sql($sql);

    # columns will have changed, so clear cache:
    clear_table_info($table);
}

sub create_table {
    my $table = shift;
    return if $cluster && !defined $clustered_table{$table};

    my $create_sql = $table_create{$table};
    if ( $opt_innodb && $create_sql !~ /engine=myisam/i ) {
        $create_sql .= " ENGINE=INNODB";
    }
    do_sql($create_sql);

    foreach my $pc ( @{ $post_create{$table} } ) {
        my @args = @{$pc};
        my $ac   = shift @args;
        if ( $ac eq "sql" ) {
            print "# post-create SQL\n";
            do_sql( $args[0] );
        }
        elsif ( $ac eq "sqltry" ) {
            print "# post-create SQL (necessary if upgrading only)\n";
            try_sql( $args[0] );
        }
        elsif ( $ac eq "code" ) {
            print "# post-create code\n";
            $args[0]->( $dbh, $opt_sql );
        }
        else { print "# don't know how to do \$ac = $ac"; }
    }
}

sub drop_table {
    my $table = shift;

    if ($opt_drop) {
        do_sql("DROP TABLE $table");
    }
    else {
        print "# Not dropping table $table to be paranoid (use --drop)\n";
    }
}

sub mark_clustered {
    foreach (@_) {
        $clustered_table{$_} = 1;
    }
}

sub register_tablecreate {
    my ( $table, $create ) = @_;

    # we now know of it
    delete $table_unknown{$table};

    return if $cluster && !defined $clustered_table{$table};

    $table_create{$table} = $create;
}

sub register_tabledrop {
    my ($table) = @_;
    $table_drop{$table} = 1;
}

sub post_create {
    my $table = shift;
    while ( my ( $type, $what ) = splice( @_, 0, 2 ) ) {
        push @{ $post_create{$table} }, [ $type, $what ];
    }
}

sub register_alter {
    my $sub = shift;
    push @alters, $sub;
}

sub clear_table_info {
    my $table = shift;
    delete $coltype{$table};
    delete $indexname{$table};
    delete $table_status{$table};
}

sub load_table_info {
    my $table = shift;

    clear_table_info($table);

    my $sth = $dbh->prepare("DESCRIBE $table");
    $sth->execute;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $type = $row->{'Type'};
        $type .= " $1" if $row->{'Extra'} =~ /(auto_increment)/i;
        $coltype{$table}->{ $row->{'Field'} } = lc($type);
    }

    # current physical table properties
    $table_status{$table} = $dbh->selectrow_hashref("SHOW TABLE STATUS LIKE '$table'");

    $sth = $dbh->prepare("SHOW INDEX FROM $table");
    $sth->execute;
    my %idx_type;     # name -> "UNIQUE"|"INDEX"
    my %idx_parts;    # name -> []
    while ( my $ir = $sth->fetchrow_hashref ) {
        $idx_type{ $ir->{'Key_name'} } = $ir->{'Non_unique'} ? "INDEX" : "UNIQUE";
        push @{ $idx_parts{ $ir->{'Key_name'} } }, $ir->{'Column_name'};
    }

    foreach my $idx ( keys %idx_type ) {
        my $val = "$idx_type{$idx}:" . join( "-", @{ $idx_parts{$idx} } );
        $indexname{$table}->{$val} = $idx;
    }
}

sub index_name {
    my ( $table, $idx ) = @_;    # idx form is:  INDEX:col1-col2-col3
    load_table_info($table) unless $indexname{$table};
    return $indexname{$table}->{$idx} || "";
}

sub table_relevant {
    my $table = shift;
    return 1 unless $cluster;
    return 1 if $clustered_table{$table};
    return 0;
}

sub column_type {
    my ( $table, $col ) = @_;
    load_table_info($table) unless $coltype{$table};
    my $type = $coltype{$table}->{$col};
    $type ||= "";
    return $type;
}

sub table_status {
    my ( $table, $col ) = @_;
    load_table_info($table) unless $table_status{$table};

    return $table_status{$table}->{$col} || "";
}

sub ensure_confirm {
    my $area = shift;

    return 1 if (
        $opt_sql
        && (   $opt_confirm eq "all"
            or $opt_confirm eq $area )
    );

    print STDERR "To proceed with the necessary changes, rerun with -r --confirm=$area\n";
    return 0;
}

sub set_dbnote {
    my ( $key, $value ) = @_;
    return unless $opt_sql && $key && $value;

    return $dbh->do( "REPLACE INTO dbnotes (dbnote, value) VALUES (?,?)", undef, $key, $value );
}

sub check_dbnote {
    my $key = shift;

    return $dbh->selectrow_array( "SELECT value FROM dbnotes WHERE dbnote=?", undef, $key );
}

