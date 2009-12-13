#!/usr/bin/perl
#
# This program deals with inserting/extracting text/language data
# from the database.
#

use strict;
use File::Basename ();
use File::Path ();
use Getopt::Long;
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::Config; LJ::Config->load;
use LJ::LangDatFile;

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
    loadcrumbs Load crumbs from crumbs.pl and crumbs-local.pl.
    makeusable Setup internal indexes necessary after loading text
  dumptext     Dump lang text based on text[-local].dat information
               Optionally:
                  [lang...] list of languages to dump (default is all)
  dumptextcvs  Same as dumptext, but dumps to the CVS area, not the live area
  check        Check validity of text[-local].dat files
  wipedb       Remove all language/text data from database, including crumbs.
  wipecrumbs   Remove all crumbs from the database, leaving other text alone.
  remove       takes two extra arguments: domain name and code, and removes
               that code and its text in all languages

';
}

## make sure $LJHOME is set so we can load & run everything
unless (-d $ENV{'LJHOME'}) {
    die "LJHOME environment variable is not set, or is not a directory.\n".
        "You must fix this before you can run this database update script.";
}
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
use LJ::Lang;
require "$ENV{'LJHOME'}/cgi-bin/weblib.pl";

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

foreach my $scope ("general", "local") {
    my $file = $scope eq "general" ? "text.dat" : "text-local.dat";
    my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
    unless (-e $ffile) {
        next if $scope eq "local";
        die "$file file not found; odd: did you delete it?\n";
    }
    open (F, $ffile) or die "Can't open file: $file: $!\n";
    while (<F>) {
        s/\s+$//; s/^\#.+//;
        next unless /\S/;
        my @vals = split(/:/, $_);
        my $what = shift @vals;

        # language declaration
        if ($what eq "lang") {
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
    makeusable copyfaq remove wipecrumbs loadcrumbs);

popstruct() if $mode eq "popstruct" or $mode eq "load";
poptext(@ARGV) if $mode eq "poptext" or $mode eq "load";
copyfaq() if $mode eq "copyfaq" or $mode eq "load";
loadcrumbs() if $mode eq "loadcrumbs" or $mode eq "load";
makeusable() if $mode eq "makeusable" or $mode eq "load";
dumptext($1, 0, @ARGV) if $mode =~ /^dumptext(cvs)?$/;
wipedb() if $mode eq "wipedb";
wipecrumbs() if $mode eq "wipecrumbs";
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
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "cat.$cat", $name, $opts);
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
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "$faqid.1question", $q, $opts);
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "$faqid.2answer", $a, $opts);
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "$faqid.3summary", $s, $opts);
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

sub wipecrumbs {
    $out->('Wiping DB of all crumbs...', '+');

    # step 1: get all items that are crumbs. [from ml_items]
    my $genid = $dom_code{'general'}->{'dmid'};
    my @crumbs;
    my $sth = $dbh->prepare("SELECT itcode FROM ml_items
                             WHERE dmid = $genid AND itcode LIKE 'crumb.\%'");
    $sth->execute;
    while (my ($itcode) = $sth->fetchrow_array) {
        # push onto list
        push @crumbs, $itcode;
    }

    # step 2: remove the items that have these unique dmid/itids
    foreach my $code (@crumbs) {
        $out->("deleting $code");
        remove("general", $code);
    }

    # done
    $out->('-', 'done.');
}

sub loadcrumbs {
    $out->('Loading all crumbs into DB...', '+');

    # get domain id of 'general' and language id of default language
    my $genid = $dom_code{'general'}->{'dmid'};
    my $loclang = $LJ::DEFAULT_LANG;

    # list of crumbs
    my @crumbs;
    foreach (keys %LJ::CRUMBS_LOCAL) { push @crumbs, $_; }
    foreach (keys %LJ::CRUMBS) { push @crumbs, $_; }

    # begin iterating, order doesn't matter...
    foreach my $crumbkey (@crumbs) {
        $out->("inserting crumb.$crumbkey");
        my $crumb = LJ::get_crumb($crumbkey);
        my $local = $LJ::CRUMBS_LOCAL{$crumbkey} ? 1 : 0;

        # see if it exists
        my $itid = $dbh->selectrow_array("SELECT itid FROM ml_items
                                          WHERE dmid = $genid AND itcode = 'crumb.$crumbkey'")+0;
        LJ::Lang::set_text($genid, $local ? $loclang : 'en', "crumb.$crumbkey", $crumb->[0])
            unless $itid;
    }

    # done
    $out->('-', 'done.');
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
        my $file = "$ENV{'LJHOME'}/bin/upgrading/${lang}.dat";
        next if $opt_only && $lang ne $opt_only;
        next unless -e $file;
        $source{$file} = [$lang, ''];
    }

    # learn about local files
    chdir "$ENV{LJHOME}" or die "Failed to chdir to \$LJHOME.\n";
    my @textfiles = `find htdocs/ views/ -name '*.text' -or -name '*.text.local'`;
    chomp @textfiles;
    foreach my $tf (@textfiles) {
        my $is_local = $tf =~ /\.local$/;
        my $lang = "en";
        if ($is_local) {
            $lang = $LJ::DEFAULT_LANG;
            die "uh, what is this .local file?" unless $lang ne "en";
        }
        my $pfx = $tf;
        $pfx =~ s!^htdocs/!!;
        $pfx =~ s!^views/!!;
        $pfx =~ s!\.text(\.local)?$!!;
        $pfx = "/$pfx";
        $source{"$ENV{'LJHOME'}/$tf"} = [$lang, $pfx];
    }

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

                my $res = LJ::Lang::set_text($dbh, 1, $l->{'lncode'}, $code, $text,
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
    foreach my $file ("deadphrases.dat", "deadphrases-local.dat") {
        my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
        next unless -s $ffile;
        $out->("File: $file");
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
    my $to_cvs = shift;
    my $append = shift;
    my @langs = @_;
    unless (@langs) { @langs = keys %lang_code; }

    $out->('Dumping text...', '+');
    foreach my $lang (@langs) {
        $out->("$lang");
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

            my $langdat_file = LJ::Lang::langdat_file_of_lang_itcode($lang, $itcode, $to_cvs);

            $itcode = LJ::Lang::itcode_for_langdat_file($langdat_file, $itcode);

            my $fh = $fh_map{$langdat_file};
            unless ($fh) {

                # the dir might not exist in some cases
                my $d = File::Basename::dirname($langdat_file);
                File::Path::mkpath($d) unless -e $d;

                open ($fh, $append ? ">>$langdat_file" : ">$langdat_file")
                    or die "unable to open langdat file: $langdat_file ($!)";

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
