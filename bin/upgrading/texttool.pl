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
# This program deals with inserting/extracting text/language data
# from the database.
#

use strict;

BEGIN { $LJ::_T_CONFIG = $ENV{DW_TEST}; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use File::Basename ();
use File::Path ();
use File::Find ();
use Getopt::Long;
use LJ::Config; LJ::Config->load;
use LJ::LangDatFile;
use LJ::Lang;
use LJ::Web;

my $DATA_DIR = "bin/upgrading";

my $opt_help = 0;
my $opt_local_lang;
my $opt_only;
my $opt_verbose;
exit 1
    unless GetOptions( "help" => \$opt_help, "local-lang=s" => \$opt_local_lang,
        "verbose" => \$opt_verbose, "only=s" => \$opt_only );

my $mode = shift @ARGV;

help() if $opt_help or not defined $mode;

sub help {
    die 'Usage: texttool.pl <command>

Where <command> is one of:
  load         Runs the following five commands in order:
    popstruct  Populate lang data from text[-local].dat into db
    poptext    Populate text from en.dat, etc into database. This will also
               delete any text items listed in deadphrases[-local].dat. If
               texttool.pl is run on a production server ($LJ::IS_DEV_SERVER is
               false), the text items will be dumped first (as if by dumptext)
               for all languages except en and the local root language
               ($LJ::DEFAULT_LANG or $LJ::LANGS[0]), but existing text files
               will be appended, not overwritten.
    copyfaq    If site is translating FAQ, copy FAQ data into trans area
    makeusable Setup internal indexes necessary after loading text
  dumptext     Dump lang text based on text[-local].dat information
               Optionally:
                  [lang...] list of languages to dump (default is all)
  check        Check validity of text[-local].dat files
  wipedb       Remove all language/text data from database.
  remove       takes two extra arguments: domain name and code, and removes
               that code and its text in all languages

';
}

my %dom_id;     # number -> {}
my %dom_code;   # name   -> {}
my %lang_id;    # number -> {}
my %lang_code;  # name   -> {}
my @lang_domains;

my $set = sub {
    my ($hash, $key, $val, $errmsg) = @_;
    die "$errmsg$key\n" if exists $hash->{$key};
    $hash->{$key} = $val;
};

my %lang_dir_map;

foreach my $scope ( "general", "local" ) {
    my $file = $scope eq "general" ? "text.dat" : "text-local.dat";
    my @files = LJ::get_all_files( "$DATA_DIR/$file", home_first => 1);
    if ( $scope eq 'general' && ! @files ) {
        die "$file file not found; odd: did you delete it?\n";
    }
    foreach my $ffile ( @files ) {
        my $dir = File::Basename::dirname($ffile);
        $dir =~ s!/\Q$DATA_DIR\E$!!;

        open (F, $ffile) or die "Can't open file: $file: $!\n";
        while (<F>) {
            s/\s+$//; s/^\#.+//;
            next unless /\S/;
            my @vals = split(/:/, $_);
            my $what = shift @vals;

            # language declaration
            if ($what eq "lang") {
                $lang_dir_map{$vals[1]} = $dir;

                my $lang = {
                    scope  => $scope,
                    lnid   => $vals[0],
                    lncode => $vals[1],
                    lnname => $vals[2],
                    parentlnid => 0,   # default.  changed later.
                    parenttype => 'diff',
                };
                $lang->{'parenttype'} = $vals[3] if defined $vals[3];
                if (defined $vals[4]) {
                    unless (exists $lang_code{$vals[4]}) {
                        die "Can't declare language $lang->{'lncode'} with missing parent language $vals[4].\n";
                    }
                    $lang->{'parentlnid'} = $lang_code{$vals[4]}->{'lnid'};
                }
                $set->(\%lang_id,   $lang->{'lnid'},   $lang, "Language already defined with ID: ");
                $set->(\%lang_code, $lang->{'lncode'}, $lang, "Language already defined with code: ");
            }

            # domain declaration
            if ($what eq "domain") {
                my $dcode = $vals[1];
                my ($type, $args) = split(m!/!, $dcode);
                my $dom = {
                    scope => $scope,
                    dmid => $vals[0],
                    type => $type,
                    args => $args || "",
                };
                $set->(\%dom_id,   $dom->{'dmid'}, $dom,
                    "Domain already defined with ID: ");
                $set->(\%dom_code, $dcode, $dom,
                    "Domain already defined with parameters: ");
            }

            # langdomain declaration
            if ($what eq "langdomain") {
                my $ld = {
                    lnid =>
                        (exists $lang_code{$vals[0]}
                            ? $lang_code{$vals[0]}->{'lnid'}
                            : die "Undefined language: $vals[0]\n"),
                    dmid =>
                        (exists $dom_code{$vals[1]}
                            ? $dom_code{$vals[1]}->{'dmid'}
                            : die "Undefined domain: $vals[1]\n"),
                    dmmaster => $vals[2] ? "1" : "0",
                    };
                push @lang_domains, $ld;
            }
        }
        close F;
    }
}

if ($mode eq "check") {
    print "all good.\n";
    exit 0;
}

## make sure we can connect
my $dbh = LJ::get_dbh("master");
my $sth;
unless ($dbh) {
    die "Can't connect to the database.\n";
}
$dbh->{RaiseError} = 1;

# indenter
my $idlev = 0;
my $out = sub {
    my @args = @_;
    while (@args) {
        my $a = shift @args;
        if ($a eq "+") { $idlev++; }
        elsif ($a eq "-") { $idlev--; }
        elsif ($a eq "x") { $a = shift @args; die "  "x$idlev . $a . "\n"; }
        else { print "  "x$idlev, $a, "\n"; }
    }
};

my @good = qw(load popstruct poptext dumptext dumptextcvs wipedb
    makeusable copyfaq remove);

popstruct() if $mode eq "popstruct" or $mode eq "load";
poptext(@ARGV) if $mode eq "poptext" or $mode eq "load";
copyfaq() if $mode eq "copyfaq" or $mode eq "load";
makeusable() if $mode eq "makeusable" or $mode eq "load";
dumptext(0, @ARGV) if $mode =~ /^dumptext?$/;
wipedb() if $mode eq "wipedb";
remove(@ARGV) if $mode eq "remove" and scalar(@ARGV) == 2;
help() unless grep { $mode eq $_ } @good;
exit 0;

sub makeusable {
    $out->("Making usable...", '+');
    my $rec = sub {
        my ($lang, $rec) = @_;
        my $l = $lang_code{$lang};
        $out->("x", "Bogus language: $lang") unless $l;
        my @children = grep { $_->{'parentlnid'} == $l->{'lnid'} } values %lang_code;
        foreach my $cl (@children) {
            $out->("$l->{'lncode'} -- $cl->{'lncode'}");

            my %need;
            # push downwards everything that has some valid text in some language (< 4)
            $sth = $dbh->prepare("SELECT dmid, itid, txtid FROM ml_latest WHERE lnid=$l->{'lnid'} AND staleness < 4");
            $sth->execute;
            while (my ($dmid, $itid, $txtid) = $sth->fetchrow_array) {
                $need{"$dmid:$itid"} = $txtid;
            }
            $sth = $dbh->prepare("SELECT dmid, itid, txtid FROM ml_latest WHERE lnid=$cl->{'lnid'}");
            $sth->execute;
            while (my ($dmid, $itid, $txtid) = $sth->fetchrow_array) {
                delete $need{"$dmid:$itid"};
            }
            while (my $k = each %need) {
                my ($dmid, $itid) = split(/:/, $k);
                my $txtid = $need{$k};
                my $stale = $cl->{'parenttype'} eq "diff" ? 3 : 0;
                $dbh->do("INSERT INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) VALUES ".
                         "($cl->{'lnid'}, $dmid, $itid, $txtid, NOW(), $stale)");
                die $dbh->errstr if $dbh->err;
            }
            $rec->($cl->{'lncode'}, $rec);
        }
    };
    $rec->("en", $rec);
    $out->("-", "done.");
}

sub copyfaq {
    my $faqd = LJ::Lang::get_dom("faq");
    my $ll = LJ::Lang::get_root_lang($faqd);
    unless ($ll) { return; }

    my $domid = $faqd->{'dmid'};

    $out->("Copying FAQ...", '+');

    my %existing;
    $sth = $dbh->prepare("SELECT i.itcode FROM ml_items i, ml_latest l ".
                         "WHERE l.lnid=$ll->{'lnid'} AND l.dmid=$domid AND l.itid=i.itid AND i.dmid=$domid");
    $sth->execute;
    $existing{$_} = 1 while $_ = $sth->fetchrow_array;

    # faq category
    $sth = $dbh->prepare("SELECT faqcat, faqcatname FROM faqcat");
    $sth->execute;
    while (my ($cat, $name) = $sth->fetchrow_array) {
        next if exists $existing{"cat.$cat"};
        my $opts = { childrenlatest => 1 };
        LJ::Lang::set_text( $domid, $ll->{'lncode'}, "cat.$cat", $name, $opts );
    }

    # faq items
    $sth = $dbh->prepare("SELECT faqid, question, answer, summary FROM faq");
    $sth->execute;
    while (my ($faqid, $q, $a, $s) = $sth->fetchrow_array) {
        next if
            exists $existing{"$faqid.1question"} and
            exists $existing{"$faqid.2answer"} and
            exists $existing{"$faqid.3summary"};
        my $opts = { childrenlatest => 1 };
        LJ::Lang::set_text( $domid, $ll->{'lncode'}, "$faqid.1question", $q, $opts );
        LJ::Lang::set_text( $domid, $ll->{'lncode'}, "$faqid.2answer", $a, $opts );
        LJ::Lang::set_text( $domid, $ll->{'lncode'}, "$faqid.3summary", $s, $opts );
    }

    $out->('-', "done.");
}

sub wipedb {
    $out->("Wiping DB...", '+');
    foreach (qw(domains items langdomains langs latest text)) {
        $out->("deleting from $_");
        $dbh->do("DELETE FROM ml_$_");
    }
    $out->("-", "done.");
}

sub popstruct {
    $out->("Populating structure...", '+');
    foreach my $l (values %lang_id) {
        $out->("Inserting language: $l->{'lnname'}");
        $dbh->do("REPLACE INTO ml_langs (lnid, lncode, lnname, parenttype, parentlnid) ".
                 "VALUES (" . join(",", map { $dbh->quote($l->{$_}) } qw(lnid lncode lnname parenttype parentlnid)) . ")");
    }

    foreach my $d (values %dom_id) {
        $out->("Inserting domain: $d->{'type'}\[$d->{'args'}\]");
        $dbh->do("REPLACE INTO ml_domains (dmid, type, args) ".
                 "VALUES (" . join(",", map { $dbh->quote($d->{$_}) } qw(dmid type args)) . ")");
    }

    $out->("Inserting language domains ...");
    foreach my $ld (@lang_domains) {
        $dbh->do("INSERT IGNORE INTO ml_langdomains (lnid, dmid, dmmaster) VALUES ".
                 "(" . join(",", map { $dbh->quote($ld->{$_}) } qw(lnid dmid dmmaster)) . ")");
    }
    $out->("-", "done.");
}

sub poptext {
    my @langs = @_;
    push @langs, (keys %lang_code) unless @langs;

    $out->("Populating text...", '+');

    # learn about base files
    my %source;   # langcode -> absfilepath
    foreach my $lang (@langs) {
        my $file = $lang_dir_map{$lang} . "/$DATA_DIR/${lang}.dat";
        next if $opt_only && $lang ne $opt_only;
        next unless -e $file;
        $source{$file} = [$lang, ''];
    }

    my $wanted = sub {
        print join(" ", ( $_, $File::Find::Dir, $File::Find::name) ) . "\n";
        return $_ =~ m/\.text(\.local)?$/;
    };

    # learn about local files

    my $lang;
    my $current_dir;

    my $process_file = sub {
        my $tf = $File::Find::name;
        return unless $tf =~ m/\.text(\.local)?$/;

        my $is_local = $tf =~ /\.local$/;

        if ($is_local) {
            die "uh, what is this .local file?" unless $lang ne "en";
        }

        my $pfx = $tf;
        $pfx =~ s!^htdocs/!!;
        $pfx =~ s!^views/!!;
        $pfx =~ s!\.text(\.local)?$!!;
        $pfx = "/$pfx";
        $source{$current_dir . '/' . $tf} = [$lang, $pfx];
    };

    my $original_dir = Cwd::getcwd();

    # Only going over these directories and not all directories
    # This can be revisited if we have .text(.local) files
    #  outside of these
    foreach my $the_lang ( keys %lang_dir_map ) {
        $lang = $the_lang;
        $current_dir = $lang_dir_map{$lang};
        next unless -d $current_dir;
        chdir $current_dir;
        File::Find::find( $process_file, 'htdocs', 'views' );
    }

    chdir $original_dir;

    my %existing_item;  # langid -> code -> 1

    foreach my $file (keys %source) {
        my ($lang, $pfx) = @{$source{$file}};

        $out->("$lang", '+');
        my $ldf = LJ::LangDatFile->new($file);

        my $l = $lang_code{$lang} or die "unknown language '$lang'";

        my $addcount = 0;
        $ldf->foreach_key(sub {
            my $code = shift;

            my %metadata = $ldf->meta($code);
            my $text = $ldf->value($code);

            $code = "$pfx$code";
            die "Code in file $file can't start with a dot: $code"
                if $code =~ /^\./;

            # load existing items for target language
            unless (exists $existing_item{$l->{'lnid'}}) {
                $existing_item{$l->{'lnid'}} = {};
                my $sth = $dbh->prepare(qq{
                    SELECT i.itcode, t.text
                    FROM ml_latest l, ml_items i, ml_text t
                    WHERE i.dmid=1 AND l.dmid=1 AND i.itid=l.itid AND l.lnid=?
                      AND t.lnid=l.lnid and t.txtid = l.txtid
                      AND i.dmid=i.dmid and t.dmid=i.dmid
                    });
                $sth->execute($l->{lnid});
                die $sth->errstr if $sth->err;
                while (my ($code, $oldtext) = $sth->fetchrow_array) {
                    $existing_item{$l->{'lnid'}}->{ lc($code) } = $oldtext;
                }
            }

            # if this is the local/default language (which means people are likely to
            # be translating it live on the site) then don't overwrite...
            return if $lang eq $LJ::DEFAULT_LANG &&
                      $existing_item{$l->{lnid}}->{$code};

            # Remove last '\r' char from loaded from files text before compare.
            # In database text stored without this '\r', LJ::Lang::set_text remove it
            # before update database.
            $text =~ s/\r//;
            unless ($existing_item{$l->{'lnid'}}->{$code} eq $text) {
                $addcount++;
                # if the text is changing, the staleness is at least 1
                my $staleness = $metadata{'staleness'}+0 || 1;

                my $res = LJ::Lang::set_text(1, $l->{'lncode'}, $code, $text,
                                             { 'staleness' => $staleness,
                                               'notes' => $metadata{'notes'},
                                               'changeseverity' => 2, });
                $out->("set: $code") if $opt_verbose;
                unless ($res) {
                    $out->('x', "ERROR: " . LJ::Lang::last_error());
                }
            }
        });
        $out->("added: $addcount", '-');
    }
    $out->("-", "done.");

    # dead phrase removal
    unless ($LJ::IS_DEV_SERVER) {
        my @trans = grep { $_ ne "en" && $_ ne $LJ::DEFAULT_LANG } @LJ::LANGS;
        if (@trans) {
            $out->('Dumping text (with append) before removing deadphrases');
            dumptext(0, 1, @trans);
        } else {
            $out->('No translated languages, skipping dumptext');
        }
    }
    $out->("Removing dead phrases...", '+');
    my @dp_files;
    foreach my $file ("deadphrases.dat", "deadphrases-local.dat") {
        foreach my $lang (@langs) {
            my $fn = $lang_dir_map{$lang} . "/$DATA_DIR/$file";
            next unless -e $fn;
            push @dp_files, $fn;
        }
    }
    foreach my $ffile ( @dp_files ) {
        next unless -s $ffile;
        my ($fn) = ( $ffile =~ /^\Q$ENV{LJHOME}\E\/(.*)$/ );
        $out->("File: $fn");
        open (DP, $ffile) or die;
        while (my $li = <DP>) {
            $li =~ s/\#.*//;
            next unless $li =~ /\S/;
            $li =~ s/\s+$//;
            my ($dom, $it) = split(/\s+/, $li);
            next unless exists $dom_code{$dom};
            my $dmid = $dom_code{$dom}->{'dmid'};

            my @items;
            if ($it =~ s/\*$/\%/) {
                my $sth = $dbh->prepare("SELECT itcode FROM ml_items WHERE dmid=? AND itcode LIKE ?");
                $sth->execute($dmid, $it);
                push @items, $_ while $_ = $sth->fetchrow_array;
            } else {
                @items = ($it);
            }
            foreach (@items) {
                remove($dom, $_, 1);
            }
        }
        close DP;
    }
    $out->('-', "Done.");
}

# TODO: use LJ::LangDatFile->save
sub dumptext {
    my $append = shift;
    my @langs = @_;
    unless (@langs) { @langs = keys %lang_code; }

    $out->('Dumping text...', '+');
    foreach my $lang (@langs) {
        my $lang_dir = $lang_dir_map{$lang};
        my $d_langdir = $lang_dir;
        $d_langdir =~ s!^\Q$LJ::HOME\E/!!;

        $out->("$lang ( $d_langdir )");

        my $l = $lang_code{$lang};

        my %fh_map = (); # filename => filehandle

        my $sth = $dbh->prepare("SELECT i.itcode, t.text, l.staleness, i.notes FROM ".
                                "ml_items i, ml_latest l, ml_text t ".
                                "WHERE l.lnid=$l->{'lnid'} AND l.dmid=1 ".
                                "AND i.dmid=1 AND l.itid=i.itid AND ".
                                "t.dmid=1 AND t.txtid=l.txtid AND ".
                                # only export mappings that aren't inherited:
                                "t.lnid=$l->{'lnid'} ".
                                "ORDER BY i.itcode");
        $sth->execute;
        die $dbh->errstr if $dbh->err;

        my $writeline = sub {
            my ($fh, $k, $v) = @_;

            # kill any \r since they shouldn't be there anyway
            $v =~ s/\r//g;

            # print to .dat file
            if ($v =~ /\n/) {
                $v =~ s/\n\./\n\.\./g;
                print $fh "$k<<\n$v\n.\n";
            } else {
                print $fh "$k=$v\n";
            }
        };

        while (my ($itcode, $text, $staleness, $notes) = $sth->fetchrow_array) {

            my $langdat_file = LJ::Lang::relative_langdat_file_of_lang_itcode($lang, $itcode);

            $itcode = LJ::Lang::itcode_for_langdat_file($langdat_file, $itcode);

            my $fh = $fh_map{$langdat_file};
            unless ($fh) {
                my $langdat_path = $lang_dir . '/' . $langdat_file;

                # the dir might not exist in some cases
                my $d = File::Basename::dirname($langdat_file);
                File::Path::mkpath($d) unless -e $d;

                open ($fh, $append ? ">>$langdat_path" : ">$langdat_path")
                    or die "unable to open langdat file: $langdat_path ($!)";

                $fh_map{$langdat_file} = $fh;

                # print utf-8 encoding header
                $fh->print(";; -*- coding: utf-8 -*-\n");
            }

            $writeline->($fh, "$itcode|staleness", $staleness)
                if $staleness;
            $writeline->($fh, "$itcode|notes", $notes)
                if $notes =~ /\S/;
            $writeline->($fh, $itcode, $text);

            # newline between record sets
            print $fh "\n";
        }

        # close filehandles now
        foreach my $file (keys %fh_map) {
            close $fh_map{$file} or die "unable to close: $file ($!)";
        }
    }
    $out->('-', 'done.');
}

sub remove {
    my ($dmcode, $itcode, $no_error) = @_;
    my $dmid;
    if (exists $dom_code{$dmcode}) {
        $dmid = $dom_code{$dmcode}->{'dmid'};
    } else {
        $out->("x", "Unknown domain code $dmcode.");
    }

    my $qcode = $dbh->quote($itcode);
    my $itid = $dbh->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=$qcode");
    return if $no_error && !$itid;
    $out->("x", "Unknown item code $itcode.") unless $itid;

    $out->("Removing item $itcode from domain $dmcode ($itid)...", "+");

    # need to delete everything from: ml_items ml_latest ml_text

    $dbh->do("DELETE FROM ml_items WHERE dmid=$dmid AND itid=$itid");

    my $txtids = "";
    my $sth = $dbh->prepare("SELECT txtid FROM ml_latest WHERE dmid=$dmid AND itid=$itid");
    $sth->execute;
    while (my $txtid = $sth->fetchrow_array) {
        $txtids .= "," if $txtids;
        $txtids .= $txtid;
    }
    $dbh->do("DELETE FROM ml_latest WHERE dmid=$dmid AND itid=$itid");
    $dbh->do("DELETE FROM ml_text WHERE dmid=$dmid AND txtid IN ($txtids)") if $txtids;

    $out->("-","done.");
}
