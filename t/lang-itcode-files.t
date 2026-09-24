#!/usr/bin/perl
# Characterizes LJ::Lang::relative_langdat_file_of_lang_itcode and
# itcode_for_langdat_file after removing their '.bml' branches: .tt and
# base-.dat itcodes map exactly as before; a '.bml.'-prefixed itcode is no
# longer special-cased at all, so it now maps to the base .dat file under its
# own full, unstripped name -- the same as any other plain global key.
#
# Also exercises texttool.pl's deadphrases file-parsing rules (the same
# comment-stripping/split logic as its sub deadphrases, cited verbatim below)
# against the real deadphrases.dat/deadphrases-local.dat, with the DB-mutating
# step (texttool.pl's remove()) replaced by an inert recorder: texttool.pl is
# a top-level-dispatch script (GetOptions/mode dispatch runs immediately on
# load, and deadphrases() itself reaches a real $dbh writer), not a
# requireable module, and no t/*texttool*.t exists in this tree to follow a
# safer pattern from (grepped) -- this is the closest safe equivalent to
# "run the real code path" without either modifying the script or risking an
# uncontrolled real delete.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Lang;

subtest 'a .tt itcode maps the same as before, in the root language' => sub {
    my $itcode = '/entry/preview.tt.title';
    is( LJ::Lang::relative_langdat_file_of_lang_itcode( 'en', $itcode ),
        'views/entry/preview.tt.text',
        'root lang: .tt itcode maps to its own views/*.tt.text file' );
    is( LJ::Lang::itcode_for_langdat_file( 'views/entry/preview.tt.text', $itcode ),
        '.title', 'root lang: itcode is stripped to its relative key inside that file' );
};

subtest 'a .tt itcode maps to the base .dat file in a non-root language' => sub {
    my $itcode = '/entry/preview.tt.title';

    # relative_langdat_file_of_lang_itcode returns the base file immediately
    # for any lang that is neither "en" nor $LJ::DEFAULT_LANG, before ever
    # looking at the itcode's shape -- unaffected by this change.
    is( LJ::Lang::relative_langdat_file_of_lang_itcode( 'fr', $itcode ),
        'bin/upgrading/fr.dat', 'non-root lang: .tt itcode maps to the base .dat file' );
    is( LJ::Lang::itcode_for_langdat_file( 'bin/upgrading/fr.dat', $itcode ),
        $itcode, 'non-root lang: itcode is returned in full, unstripped' );
};

subtest 'a base .dat itcode maps the same as before, in en and a non-root language' => sub {
    my $itcode = 'error.procrequest';
    for my $lang (qw(en fr)) {
        is( LJ::Lang::relative_langdat_file_of_lang_itcode( $lang, $itcode ),
            "bin/upgrading/$lang.dat", "$lang: base itcode maps to bin/upgrading/$lang.dat" );
        is( LJ::Lang::itcode_for_langdat_file( "bin/upgrading/$lang.dat", $itcode ),
            $itcode, "$lang: itcode is returned in full, unstripped" );
    }
};

subtest 'a .bml.-prefixed itcode now maps to the base .dat file, in full, in en and fr' => sub {
    my $itcode = '/x.bml.key';
    for my $lang (qw(en fr)) {

        # Before this change: relative_langdat_file_of_lang_itcode('en', ...)
        # matched the (now-removed) .bml branch and returned
        # "htdocs/x.bml.text"; itcode_for_langdat_file then stripped the
        # itcode to ".key". After: '.bml.' is not special-cased at all, so it
        # falls through to the same base-.dat handling as any other plain key
        # -- identical to the 'error.procrequest' case above, just with a
        # itcode string that happens to contain ".bml.".
        is(
            LJ::Lang::relative_langdat_file_of_lang_itcode( $lang, $itcode ),
            "bin/upgrading/$lang.dat",
            "$lang: .bml. itcode now maps to bin/upgrading/$lang.dat, not htdocs/x.bml.text"
        );
        is( LJ::Lang::itcode_for_langdat_file( "bin/upgrading/$lang.dat", $itcode ),
            $itcode,
            "$lang: itcode is now returned in full ('/x.bml.key'), not stripped to '.key'" );
    }
};

subtest 'texttool.pl deadphrases file-parsing still recognizes .bml.-style entries' => sub {
    my @recorded;
    my $remove = sub { push @recorded, [ $_[0], $_[1] ] };    # stands in for texttool.pl's remove()

    for my $file (
        "$ENV{LJHOME}/bin/upgrading/deadphrases.dat",
        "$ENV{LJHOME}/ext/dw-nonfree/bin/upgrading/deadphrases-local.dat",
        )
    {
        next unless -e $file;
        open my $dp, '<', $file or die "can't open $file: $!";

        # Same parsing rules as bin/upgrading/texttool.pl's sub deadphrases:
        # strip comments, skip blank lines, trim trailing whitespace, split
        # "$dom $itcode" on whitespace. The '*' wildcard-expansion branch (a
        # live SQL LIKE lookup) is intentionally not exercised here -- none
        # of the entries this test cares about use it.
        while ( my $li = <$dp> ) {
            $li =~ s/\#.*//;
            next unless $li =~ /\S/;
            $li =~ s/\s+$//;
            my ( $dom, $it ) = split( /\s+/, $li );

            # Mirrors deadphrases()'s own "next unless exists $dom_code{$dom}"
            # guard: a handful of entries are bare one-token lines with no
            # recognized domain prefix, which the real code silently skips
            # the same way.
            next unless defined $it;
            next if $it =~ /\*$/;
            $remove->( $dom, $it );
        }
        close $dp;
    }

    my %seen = map { $_->[1] => $_->[0] } @recorded;

    is( $seen{'/allpics.bml.edit'},
        'general', 'a pre-existing .bml.-style deadphrase entry still parses correctly' );

    for my $key (
        qw(
        /manage/profile/index.bml.gender.female
        /manage/profile/index.bml.show.birthday.nothing
        /poll/create.bml.error.accttype2
        /manage/circle/edit.bml.title3
        )
        )
    {
        is( $seen{$key}, 'general',
            "W14's relocated-key deadphrase entry '$key' still parses correctly" );
    }
};

done_testing;
