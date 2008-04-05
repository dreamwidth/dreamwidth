#!/usr/bin/perl
#
#   Perl Makefile for LJ-Test
#   $Id: Makefile.PL 4627 2004-10-30 01:10:21Z deveiant $
#
#   Invoke with 'perl Makefile.PL'
#
#   See ExtUtils::MakeMaker (3) for more information on how to influence
#    the contents of the Makefile that is written
#

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                    => 'LJ-Test',
    VERSION_FROM            => 'lib/LJ/Test/Unit.pm', # finds $VERSION
    AUTHOR                  => 'Michael Granger <ged@danga.com>',
    ABSTRACT                => 'Unit testing for LiveJournal code',
    PREREQ_PM               => {
        Scalar::Util        => 0,
        Time::HiRes         => 0,
        Carp                => 0,
        Data::Compare       => 0,
        Danga::Exceptions   => 1.03,
        overload            => 0,
        Class::Translucent  => 0,
    },
    dist                    => {
        CI                      => "cvs commit",
        RCS_LABEL               => 'cvs tag RELEASE_$(VERSION_SYM)',
        SUFFIX                  => ".gz",
        DIST_DEFAULT            => 'all tardist',
        COMPRESS                => "gzip",
    },

);

