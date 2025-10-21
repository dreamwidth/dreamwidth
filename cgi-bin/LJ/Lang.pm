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

package LJ::Lang;
use strict;
use LJ::LangDatFile;

use constant MAXIMUM_ITCODE_LENGTH => 120;

my @day_short   = (qw[Sun Mon Tue Wed Thu Fri Sat]);
my @day_long    = (qw[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]);
my @month_short = (qw[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]);
my @month_long =
    (qw[January February March April May June July August September October November December]);

# get entire array of days and months
sub day_list_short   { return @LJ::Lang::day_short; }
sub day_list_long    { return @LJ::Lang::day_long; }
sub month_list_short { return @LJ::Lang::month_short; }
sub month_list_long  { return @LJ::Lang::month_long; }

# access individual day or month given integer
sub day_short   { return $day_short[ $_[0] - 1 ]; }
sub day_long    { return $day_long[ $_[0] - 1 ]; }
sub month_short { return $month_short[ $_[0] - 1 ]; }
sub month_long  { return $month_long[ $_[0] - 1 ]; }

# lang codes for individual day or month given integer
sub day_short_langcode   { return "date.day." . lc( LJ::Lang::day_long(@_) ) . ".short"; }
sub day_long_langcode    { return "date.day." . lc( LJ::Lang::day_long(@_) ) . ".long"; }
sub month_short_langcode { return "date.month." . lc( LJ::Lang::month_long(@_) ) . ".short"; }
sub month_long_langcode  { return "date.month." . lc( LJ::Lang::month_long(@_) ) . ".long"; }

# Translated names for individual day or month given integer. You probably want
# these, not the ones above.
sub day_short_ml   { return LJ::Lang::ml( LJ::Lang::day_short_langcode(@_) ); }
sub day_long_ml    { return LJ::Lang::ml( LJ::Lang::day_long_langcode(@_) ); }
sub month_short_ml { return LJ::Lang::ml( LJ::Lang::month_short_langcode(@_) ); }
sub month_long_ml  { return LJ::Lang::ml( LJ::Lang::month_long_langcode(@_) ); }

## ordinal suffix
sub day_ord {
    my $day = shift;

    # teens all end in 'th'
    if ( $day =~ /1\d$/ ) { return "th"; }

    # otherwise endings in 1, 2, 3 are special
    if ( $day % 10 == 1 ) { return "st"; }
    if ( $day % 10 == 2 ) { return "nd"; }
    if ( $day % 10 == 3 ) { return "rd"; }

    # everything else (0,4-9) end in "th"
    return "th";
}

sub time_format {
    my ( $hours, $h, $m, $formatstring ) = @_;

    if ( $formatstring eq "short" ) {
        if ( $hours == 12 ) {
            my $ret;
            my $ap = "a";
            if    ( $h == 0 )  { $ret .= "12"; }
            elsif ( $h < 12 )  { $ret .= ( $h + 0 ); }
            elsif ( $h == 12 ) { $ret .= ( $h + 0 ); $ap = "p"; }
            else               { $ret .= ( $h - 12 ); $ap = "p"; }
            $ret .= sprintf( ":%02d$ap", $m );
            return $ret;
        }
        elsif ( $hours == 24 ) {
            return sprintf( "%02d:%02d", $h, $m );
        }
    }
    return "";
}

# args: secondsold - The number of seconds ago something happened.
# returns: approximate English time span - "2 weeks", "20 hours", etc.

sub ago_text {
    my $secondsold = $_[0] || 0;
    return LJ::Lang::ml('time.ago.never') unless $secondsold > 0;

    my $num;
    if ( $secondsold >= 60 * 60 * 24 * 7 ) {
        $num = int( $secondsold / ( 60 * 60 * 24 * 7 ) );
        return LJ::Lang::ml( 'time.ago.week', { num => $num } );
    }
    elsif ( $secondsold >= 60 * 60 * 24 ) {
        $num = int( $secondsold / ( 60 * 60 * 24 ) );
        return LJ::Lang::ml( 'time.ago.day', { num => $num } );
    }
    elsif ( $secondsold >= 60 * 60 ) {
        $num = int( $secondsold / ( 60 * 60 ) );
        return LJ::Lang::ml( 'time.ago.hour', { num => $num } );
    }
    elsif ( $secondsold >= 60 ) {
        $num = int( $secondsold / 60 );
        return LJ::Lang::ml( 'time.ago.minute', { num => $num } );
    }
    else {
        $num = $secondsold;
        return LJ::Lang::ml( 'time.ago.second', { num => $num } );
    }
}
*LJ::ago_text = \&ago_text;

# args: time in seconds of last activity; "current" time in seconds.
# returns: result of ago_text for the difference.

sub diff_ago_text {
    my ( $last, $time ) = @_;
    return ago_text(0) unless $last;
    $time = time() unless defined $time;

    my $diff = ( $time - $last ) || 1;
    return ago_text($diff);
}
*LJ::diff_ago_text = \&diff_ago_text;

#### ml_ stuff:
my $LS_CACHED = 0;
my %DM_ID     = ();    # id -> { type, args, dmid, langs => { => 1, => 0, => 1 } }
my %DM_UNIQ   = ();    # "$type/$args" => ^^^
my %LN_ID     = ();    # id -> { ..., ..., 'children' => [ $ids, .. ] }
my %LN_CODE   = ();    # $code -> ^^^^
my $LAST_ERROR;
my %TXT_CACHE;

sub last_error {
    return $LAST_ERROR;
}

sub set_error {
    $LAST_ERROR = $_[0];
    return 0;
}

sub get_lang {
    my $code = $_[0];
    return unless defined $code;
    load_lang_struct() unless $LS_CACHED;
    return $LN_CODE{$code};
}

sub get_lang_id {
    my $id = $_[0];
    return unless defined $id;
    load_lang_struct() unless $LS_CACHED;
    return $LN_ID{$id};
}

sub get_dom {
    my $dmcode = $_[0];
    return unless defined $dmcode;
    load_lang_struct() unless $LS_CACHED;
    return $DM_UNIQ{$dmcode};
}

sub get_dom_id {
    my $dmid = $_[0];
    return unless defined $dmid;
    load_lang_struct() unless $LS_CACHED;
    return $DM_ID{$dmid};
}

sub get_domains {
    load_lang_struct() unless $LS_CACHED;
    return values %DM_ID;
}

sub get_root_lang {
    my $dom = shift;    # from, say, get_dom
    return undef unless ref $dom eq "HASH";

    my $lang_override = LJ::Hooks::run_hook( "root_lang_override", $dom );
    return get_lang($lang_override) if $lang_override;

    foreach ( keys %{ $dom->{'langs'} } ) {
        if ( $dom->{'langs'}->{$_} ) {
            return get_lang_id($_);
        }
    }
    return undef;
}

sub load_lang_struct {
    return 1 if $LS_CACHED;
    my $dbr = LJ::get_db_reader();
    return set_error("No database available") unless $dbr;
    my $sth;

    $sth = $dbr->prepare("SELECT dmid, type, args FROM ml_domains");
    $sth->execute;
    while ( my ( $dmid, $type, $args ) = $sth->fetchrow_array ) {
        my $uniq = $args ? "$type/$args" : $type;
        $DM_UNIQ{$uniq} = $DM_ID{$dmid} = {
            'type' => $type,
            'args' => $args,
            'dmid' => $dmid,
            'uniq' => $uniq,
        };
    }

    $sth = $dbr->prepare("SELECT lnid, lncode, lnname, parenttype, parentlnid FROM ml_langs");
    $sth->execute;
    while ( my ( $id, $code, $name, $ptype, $pid ) = $sth->fetchrow_array ) {
        $LN_ID{$id} = $LN_CODE{$code} = {
            'lnid'       => $id,
            'lncode'     => $code,
            'lnname'     => $name,
            'parenttype' => $ptype,
            'parentlnid' => $pid,
        };
    }
    foreach ( values %LN_CODE ) {
        next unless $_->{'parentlnid'};
        push @{ $LN_ID{ $_->{'parentlnid'} }->{'children'} }, $_->{'lnid'};
    }

    $sth = $dbr->prepare("SELECT lnid, dmid, dmmaster FROM ml_langdomains");
    $sth->execute;
    while ( my ( $lnid, $dmid, $dmmaster ) = $sth->fetchrow_array ) {
        $DM_ID{$dmid}->{'langs'}->{$lnid} = $dmmaster;
    }

    $LS_CACHED = 1;
}

sub relative_langdat_file_of_lang_itcode {
    my ( $lang, $itcode ) = @_;

    my $root_lang       = "en";
    my $root_lang_local = $LJ::DEFAULT_LANG;

    my $base_file = "bin/upgrading/$lang\.dat";

    # not a root or root_local lang, just return base file location
    unless ( $lang eq $root_lang || $lang eq $root_lang_local ) {
        return $base_file;
    }

    my $is_local = $lang eq $root_lang_local && $lang ne $root_lang;

    # is this a filename-based itcode?
    if ( $itcode =~ m!^(/.+\.bml)! ) {
        my $file = $1;

        # given the filename of this itcode and the current
        # source, what langdat file should we use?
        my $langdat_file = "htdocs$file\.text";
        $langdat_file .= $is_local ? ".local" : "";
        return $langdat_file;
    }

    if ( $itcode =~ m!^(/.+\.tt)! ) {
        my $file = $1;

        my $langdat_file = "views$file\.text";
        $langdat_file .= $is_local ? ".local" : "";
        return $langdat_file;
    }

    # not a bml file, goes into base .dat file
    return $base_file;
}

sub itcode_for_langdat_file {
    my ( $langdat_file, $itcode ) = @_;

    # non-bml itcode, return full itcode path
    unless ( $langdat_file =~ m!^.+\.(?:bml|tt)\.text(?:\.local)?$! ) {
        return $itcode;
    }

    # bml itcode, strip filename and return
    if ( $itcode =~ m!^/.+\.(?:bml|tt)(\..+)! ) {
        return $1;
    }

    # fallback -- full $itcode
    return $itcode;
}

sub get_chgtime_unix {
    my ( $lncode, $dmid, $itcode ) = @_;
    load_lang_struct() unless $LS_CACHED;

    $dmid = int( $dmid || 1 );

    my $l = get_lang($lncode);
    unless ($l) {
        warn "No lang info for lang $lncode. Make sure you've run\n"
            . "    bin/upgrading/texttool.pl load";
        return 0;
    }

    my $lnid = $l->{'lnid'}
        or die "Could not get lang_id for lang $lncode";

    my $itid = LJ::Lang::get_itemid( $dmid, $itcode )
        or return 0;

    my $dbr = LJ::get_db_reader();
    $dmid += 0;
    my $chgtime =
        $dbr->selectrow_array( "SELECT chgtime FROM ml_latest WHERE dmid=? AND itid=? AND lnid=?",
        undef, $dmid, $itid, $lnid );
    die $dbr->errstr if $dbr->err;
    return $chgtime ? LJ::mysqldate_to_time($chgtime) : 0;
}

sub get_itemid {
    my ( $dmid, $itcode, $opts ) = @_;
    load_lang_struct() unless $LS_CACHED;

    if ( length $itcode > MAXIMUM_ITCODE_LENGTH ) {
        warn "'$itcode' exceeds maximum code length, truncating to "
            . MAXIMUM_ITCODE_LENGTH
            . " symbols";
        $itcode = substr( $itcode, 0, MAXIMUM_ITCODE_LENGTH );
    }

    my $dbr = LJ::get_db_reader();
    $dmid += 0;
    my $itid = $dbr->selectrow_array( "SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=?",
        undef, $itcode );
    return $itid if defined $itid;

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    # allocate a new id
    LJ::DB::get_lock( $dbh, 'global', 'mlitem_dmid' ) || return 0;
    $itid = $dbh->selectrow_array( "SELECT MAX(itid)+1 FROM ml_items WHERE dmid=?", undef, $dmid );
    $itid ||= 1;    # if the table is empty, NULL+1 == NULL
    $dbh->do( "INSERT INTO ml_items (dmid, itid, itcode, notes) " . "VALUES (?, ?, ?, ?)",
        undef, $dmid, $itid, $itcode, $opts->{'notes'} );
    LJ::DB::release_lock( $dbh, 'global', 'mlitem_dmid' );

    if ( $dbh->err ) {
        return $dbh->selectrow_array( "SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=?",
            undef, $itcode );
    }
    return $itid;
}

# this is called when editing text from a web UI.
# first try and run a local hook to save the text,
# if that fails then just call set_text

# returns ($success, $responsemsg) where responsemsg can be output
# from whatever saves the text
sub web_set_text {
    my ( $dmid, $lncode, $itcode, $text, $opts ) = @_;

    my $resp     = '';
    my $hook_ran = 0;

    if ( LJ::Hooks::are_hooks('web_set_text') ) {
        $hook_ran = LJ::Hooks::run_hook( 'web_set_text', $dmid, $lncode, $itcode, $text, $opts );
    }

    # save in the db
    my $save_success = LJ::Lang::set_text( $dmid, $lncode, $itcode, $text, $opts );
    $resp = LJ::Lang::last_error() unless $save_success;
    warn $resp if !$save_success && $LJ::IS_DEV_SERVER;

    return ( $save_success, $resp );
}

sub set_text {
    my ( $dmid, $lncode, $itcode, $text, $opts ) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $l    = $LN_CODE{$lncode} or return set_error("Language not defined.");
    my $lnid = $l->{'lnid'};
    $dmid += 0;

    # is this domain/language request even possible?
    return set_error("Bogus domain")
        unless exists $DM_ID{$dmid};
    return set_error("Bogus lang for that domain")
        unless exists $DM_ID{$dmid}->{'langs'}->{$lnid};

    my $itid = get_itemid( $dmid, $itcode, { 'notes' => $opts->{'notes'} } );
    return set_error("Couldn't allocate itid.") unless $itid;

    my $dbh   = LJ::get_db_writer();
    my $txtid = 0;

    my $oldtextid =
        $dbh->selectrow_array( "SELECT txtid FROM ml_text WHERE lnid=? AND dmid=? AND itid=?",
        undef, $lnid, $dmid, $itid );

    if ( defined $text ) {
        my $userid = ( $opts->{userid} // 0 ) + 0;

        # Strip bad characters
        $text =~ s/\r//;
        my $qtext = $dbh->quote($text);
        LJ::DB::get_lock( $dbh, 'global', 'ml_text_txtid' ) || return 0;
        $txtid =
            $dbh->selectrow_array( "SELECT MAX(txtid)+1 FROM ml_text WHERE dmid=?", undef, $dmid );
        $txtid ||= 1;
        $dbh->do( "INSERT INTO ml_text (dmid, txtid, lnid, itid, text, userid) "
                . "VALUES ($dmid, $txtid, $lnid, $itid, $qtext, $userid)" );
        LJ::DB::release_lock( $dbh, 'global', 'ml_text_txtid' );
        return set_error( "Error inserting ml_text: " . $dbh->errstr ) if $dbh->err;
    }
    if ( $opts->{'txtid'} ) {
        $txtid = $opts->{'txtid'} + 0;
    }

    my $staleness = ( $opts->{staleness} // 0 ) + 0;
    $dbh->do( "REPLACE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) "
            . "VALUES ($lnid, $dmid, $itid, $txtid, NOW(), $staleness)" );
    return set_error( "Error inserting ml_latest: " . $dbh->errstr ) if $dbh->err;
    LJ::MemCache::set( "ml.${lncode}.${dmid}.${itcode}", $text ) if defined $text;

    my $langids;
    {
        my $vals;
        my $rec = sub {
            my $l   = shift;
            my $rec = shift;
            foreach my $cid ( @{ $l->{'children'} } ) {
                my $clid = $LN_ID{$cid};
                if ( $opts->{'childrenlatest'} ) {
                    my $stale = $clid->{'parenttype'} eq "diff" ? 3 : 0;
                    $vals .= "," if $vals;
                    $vals .= "($cid, $dmid, $itid, $txtid, NOW(), $stale)";
                }
                $langids .= "," if $langids;
                $langids .= $cid + 0;
                LJ::MemCache::delete("ml.$clid->{'lncode'}.${dmid}.${itcode}");
                $rec->( $clid, $rec );
            }
        };
        $rec->( $l, $rec );

        # set descendants to use this mapping
        $dbh->do( "INSERT IGNORE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) "
                . "VALUES $vals" )
            if $vals;

        # update languages that have no translation yet
        if ($oldtextid) {
            $dbh->do( "UPDATE ml_latest SET txtid=$txtid WHERE dmid=$dmid "
                    . "AND lnid IN ($langids) AND itid=$itid AND txtid=$oldtextid" )
                if $langids;
        }
        else {
            $dbh->do( "UPDATE ml_latest SET txtid=$txtid WHERE dmid=$dmid "
                    . "AND lnid IN ($langids) AND itid=$itid AND staleness >= 3" )
                if $langids;
        }
    }

    if ( $opts->{'changeseverity'} && $langids ) {
        my $newstale = $opts->{'changeseverity'} == 2 ? 2 : 1;
        $dbh->do( "UPDATE ml_latest SET staleness=$newstale WHERE lnid IN ($langids) AND "
                . "dmid=$dmid AND itid=$itid AND txtid<>$txtid AND staleness < $newstale" );
    }

    return 1;
}

sub remove_text {
    my ( $dmid, $itcode, $lncode ) = @_;

    my $dbh = LJ::get_db_writer();

    my $itid = $dbh->selectrow_array( "SELECT itid FROM ml_items WHERE dmid=? AND itcode=?",
        undef, $dmid, $itcode );
    die "Unknown item code $itcode." unless $itid;

    # need to delete everything from: ml_items ml_latest ml_text

    $dbh->do( "DELETE FROM ml_items WHERE dmid=? AND itid=?", undef, $dmid, $itid );

    my @txtids = ();
    my $sth    = $dbh->prepare("SELECT txtid FROM ml_latest WHERE dmid=? AND itid=?");
    $sth->execute( $dmid, $itid );
    while ( my $txtid = $sth->fetchrow_array ) {
        push @txtids, $txtid;
    }

    $dbh->do( "DELETE FROM ml_latest WHERE dmid=? AND itid=?", undef, $dmid, $itid );

    my $txtid_bind = join( ",", map { "?" } @txtids );
    $dbh->do( "DELETE FROM ml_text WHERE dmid=? AND txtid IN ($txtid_bind)",
        undef, $dmid, @txtids );

    # delete from memcache if lncode is defined
    LJ::MemCache::delete("ml.${lncode}.${dmid}.${itcode}") if $lncode;

    return 1;
}

sub get_effective_lang {

    my $lang;
    if ( LJ::is_web_context() ) {
        $lang = BML::get_language();
    }

    # did we get a valid language code?
    if ( $lang && $LN_CODE{$lang} ) {
        return $lang;
    }

    # had no language code, or invalid.  return default
    return $LJ::DEFAULT_LANG;
}

sub ml {
    my ( $code, $vars ) = @_;

    if ( LJ::is_web_context() ) {

        # this means we should use BML::ml and not do our own handling
        my $text = BML::ml( $code, $vars );
        $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;
        return $text;
    }

    my $lang = LJ::Lang::get_effective_lang();
    return get_text( $lang, $code, undef, $vars );
}

sub string_exists {
    my ( $code, $vars ) = @_;

    my $string = LJ::Lang::ml( $code, $vars );
    return LJ::Lang::is_missing_string($string) ? 0 : 1;
}

# LJ::Lang::ml will return a number of values for "invalid string"
# -- this function will tell you if the value is one of
#    those values.  gross.
sub is_missing_string {
    my $string = $_[0];
    return 1 unless defined $string;

    return ( $string eq "" || $string =~ /^\[missing string/ || $string =~ /^\[uhhh:/ )
        ? 1
        : 0;
}

sub get_text {
    my ( $lang, $code, $dmid, $vars ) = @_;
    $lang ||= $LJ::DEFAULT_LANG;

    my $from_db = sub {
        my $text = get_text_multi( $lang, $dmid, [$code] );
        return $text->{$code};
    };

    my $from_files = sub {
        my ( $localcode, @files );
        if ( $code =~ m!^(/.+\.bml)(\..+)! ) {
            my $file;
            ( $file, $localcode ) = ( "htdocs$1", $2 );
            @files = ( "$file.text.local", "$file.text" );
        }
        elsif ( $code =~ m!^(/.+\.tt)(\..+)! ) {
            my $file;
            ( $file, $localcode ) = ( "views$1", $2 );
            @files = ( "$file.text.local", "$file.text" );
        }
        else {
            $localcode = $code;
            @files     = ( "bin/upgrading/$LJ::DEFAULT_LANG.dat", "bin/upgrading/en.dat" );
        }

        foreach my $tf (@files) {
            $tf = LJ::resolve_file($tf);
            next unless defined $tf && -e $tf;

            # compare file modtime to when the string was updated in the DB.
            # whichever is newer is authoritative
            my $fmodtime  = ( stat $tf )[9];
            my $dbmodtime = LJ::Lang::get_chgtime_unix( $lang, $dmid, $code );
            return $from_db->() if !$fmodtime || $dbmodtime > $fmodtime;

            my $ldf = $LJ::REQ_LANGDATFILE{$tf} ||= LJ::LangDatFile->new($tf);
            my $val = $ldf->value($localcode);
            return $val if $val;
        }
        return "[missing string $code]";
    };

    my $gen_mld     = LJ::Lang::get_dom('general');
    my $is_gen_dmid = defined $dmid ? $dmid == $gen_mld->{dmid} : 1;
    my $text =
        (
        $LJ::IS_DEV_SERVER && $is_gen_dmid && ( $lang eq "en"
            || $lang eq $LJ::DEFAULT_LANG )
        )
        ? $from_files->()
        : $from_db->();

    if ($vars) {
        $text =~ s/\[\[\?([\w\-]+)\|(.+?)\]\]/resolve_plural($lang, $vars, $1, $2)/eg;
        $text =~ s/\[\[([^\[]+?)\]\]/$vars->{$1}/g;
    }

    $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;

    return $text || ( $LJ::IS_DEV_SERVER ? "[uhhh: $code]" : "" );
}

# Sometimes we want to force $lang to be the default, because the user
# generating the text display isn't the same user who will receive the
# rendered text.  These helper functions make that easier.

sub get_default_text {
    my ( $code, $vars ) = @_;
    return LJ::Lang::get_text( undef, $code, undef, $vars );
}

sub get_default_text_multi {
    my ($codes) = @_;
    return LJ::Lang::get_text_multi( undef, undef, $codes );
}

# Loads multiple language strings at once.  These strings
# cannot however contain variables, if you have variables
# you wouldn't be calling this anyway!
# args: $lang, $dmid, array ref of lang codes
sub get_text_multi {
    my ( $lang, $dmid, $codes ) = @_;

    return {} unless $codes;

    $dmid = int( $dmid || 1 );
    $lang ||= $LJ::DEFAULT_LANG;
    load_lang_struct() unless $LS_CACHED;
    ## %strings: code --> text
    my %strings;

    ## normalize the codes: all chars must be in lower case
    ## MySQL string comparison isn't case-sensitive, but memcaches keys are.
    ## Caller will get %strings with keys in original case.
    ##
    ## Final note about case:
    ##  Codes in disk .text files, mysql and bml files may be mixed-cased
    ##  Codes in memcache and %TXT_CACHE are lower-case
    ##  Codes are not case-sensitive

    ## %lc_code: lower-case code --> original code
    my %lc_codes = map { lc($_) => $_ } @$codes;

    ## %memkeys: lower-case code --> memcache key
    my %memkeys;
    foreach my $code ( keys %lc_codes ) {
        my $cache_key = "ml.${lang}.${dmid}.${code}";
        my $text      = $LJ::NO_ML_CACHE ? undef : $TXT_CACHE{$cache_key};

        if ( defined $text ) {
            $strings{ $lc_codes{$code} } = $text;
            $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;
        }
        else {
            $memkeys{$cache_key} = $code;
        }
    }

    return \%strings unless %memkeys;

    my $mem = LJ::MemCache::get_multi( keys %memkeys ) || {};

    ## %dbload: lower-case key --> text; text may be empty (but defined) string
    my %dbload;
    foreach my $cache_key ( keys %memkeys ) {
        my $code = $memkeys{$cache_key};
        my $text = $mem->{$cache_key};

        if ( defined $text ) {
            $strings{ $lc_codes{$code} } = $text;
            $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;
            $TXT_CACHE{$cache_key}       = $text;
        }
        else {
# we need to cache nonexistant/empty strings because otherwise we're running a lot of queries all the time
# to cache nonexistant strings, value of %dbload must be defined
            $dbload{$code} = '';
        }
    }

    return \%strings unless %dbload;

    my $l = $LN_CODE{$lang};

    # This shouldn't happen!
    die("Unable to load language code: $lang") unless $l;

    my $dbr  = LJ::get_db_reader();
    my $bind = join( ',', map { '?' } keys %dbload );
    my $sth =
        $dbr->prepare( "SELECT i.itcode, t.text, i.visible"
            . " FROM ml_text t, ml_latest l, ml_items i"
            . " WHERE t.dmid=? AND t.txtid=l.txtid"
            . " AND l.dmid=? AND l.lnid=? AND l.itid=i.itid"
            . " AND i.dmid=? AND i.itcode IN ($bind)" );
    $sth->execute( $dmid, $dmid, $l->{lnid}, $dmid, keys %dbload );

    # now replace the empty strings with the defined ones that we got back from the database
    while ( my ( $code, $text, $vis ) = $sth->fetchrow_array ) {

        # some MySQL codes might be mixed-case
        $dbload{ lc($code) } = $text;

        # if not currently visible, then set it
        unless ($vis) {
            my $dbh = LJ::get_db_writer();
            $dbh->do( 'UPDATE ml_items SET visible = 1 WHERE itcode = ?', undef, $code );
        }
    }

    while ( my ( $code, $text ) = each %dbload ) {
        $strings{ $lc_codes{$code} } = $text;
        $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;

        my $cache_key = "ml.${lang}.${dmid}.${code}";
        $TXT_CACHE{$cache_key} = $text;
        LJ::MemCache::set( $cache_key, $text );
    }

    return \%strings;
}

sub get_lang_names {
    my @langs = @_;
    push @langs, @LJ::LANGS unless @langs;

    my @list;

    foreach my $code (@langs) {
        my $l = LJ::Lang::get_lang($code);
        next unless $l;

        my $item         = "langname.$code";
        my $namethislang = BML::ml($item);
        my $namenative   = LJ::Lang::get_text( $l->{'lncode'}, $item );

        push @list, $code, $namenative;
    }

    return \@list;
}

# FIXME: this isn't used anywhere; just falls through to BML::set_language,
# which only affects the BML code package in the active process. Keeping this
# as a stub to assist with the gradual transition to non-BML functions.
sub set_lang {
    my $lang = shift;

    my $l = LJ::Lang::get_lang($lang);

    # set language through BML so it will apply immediately
    BML::set_language( $l->{lncode} );

    return;
}

# The translation system now supports the ability to add multiple plural forms of the word
# given different rules in a languge.  This functionality is much like the plural support
# in the S2 styles code.  To use this code you must use the BML::ml function and pass
# the number of items as one of the variables.  To make sure that you are allowing the
# utmost compatibility for each language you should not hardcode the placement of the
# number of items in relation to the noun.  Let the translation string do this for you.
# A translation string is in the format of, with num being the variable storing the
# number of items.
# =[[num]] [[?num|singular|plural1|plural2|pluralx]]

sub resolve_plural {
    my ( $lang, $vars, $varname, $wordlist ) = @_;
    my $count       = $vars->{$varname};
    my @wlist       = split( /\|/, $wordlist );
    my $plural_form = plural_form( $lang, $count );
    return $wlist[$plural_form];
}

# TODO: make this faster, using AUTOLOAD and symbol tables pointing to dynamically
# generated subs which only use $_[0] for $count.
sub plural_form {
    my ( $lang, $count ) = @_;
    return plural_form_en($count) if $lang =~ /^en/;
    return plural_form_ru($count) if $lang =~ /^ru/ || $lang =~ /^uk/ || $lang =~ /^be/;
    return plural_form_fr($count) if $lang =~ /^fr/ || $lang =~ /^pt_BR/;
    return plural_form_lt($count) if $lang =~ /^lt/;
    return plural_form_pl($count) if $lang =~ /^pl/;
    return plural_form_singular() if $lang =~ /^hu/ || $lang =~ /^ja/ || $lang =~ /^tr/;
    return plural_form_lv($count) if $lang =~ /^lv/;
    return plural_form_is($count) if $lang =~ /^is/;
    return plural_form_en($count);    # default
}

# English, Danish, German, Norwegian, Swedish, Estonian, Finnish, Greek, Hebrew, Italian, Portugese, Spanish, Esperanto
sub plural_form_en {
    my $count = $_[0] || 0;
    return 0 if $count == 1;
    return 1;
}

# French, Brazilian Portuguese
sub plural_form_fr {
    my $count = $_[0] || 0;
    return 1 if $count > 1;
    return 0;
}

# Croatian, Czech, Russian, Slovak, Ukrainian, Belarusian
sub plural_form_ru {
    my $count = $_[0] || 0;
    return 0 if ( $count % 10 == 1 and $count % 100 != 11 );
    return 1
        if ($count % 10 >= 2
        and $count % 10 <= 4
        and ( $count % 100 < 10 or $count % 100 >= 20 ) );
    return 2;
}

# Polish
sub plural_form_pl {
    my $count = $_[0] || 0;
    return 0 if ( $count == 1 );
    return 1
        if ( $count % 10 >= 2 && $count % 10 <= 4 && ( $count % 100 < 10 || $count % 100 >= 20 ) );
    return 2;
}

# Lithuanian
sub plural_form_lt {
    my $count = $_[0] || 0;
    return 0 if ( $count % 10 == 1 && $count % 100 != 11 );
    return 1 if ( $count % 10 >= 2 && ( $count % 100 < 10 || $count % 100 >= 20 ) );
    return 2;
}

# Hungarian, Japanese, Korean (not supported), Turkish
sub plural_form_singular {
    return 0;
}

# Latvian
sub plural_form_lv {
    my $count = $_[0] || 0;
    return 0 if ( $count % 10 == 1 && $count % 100 != 11 );
    return 1 if ( $count != 0 );
    return 2;
}

# Icelandic
sub plural_form_is {
    my $count = $_[0] || 0;
    return 0 if ( $count % 10 == 1 and $count % 100 != 11 );
    return 1;
}

1;
