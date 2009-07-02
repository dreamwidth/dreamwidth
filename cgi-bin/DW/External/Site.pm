#!/usr/bin/perl
#
# DW::External::Site
#
# This is a base class used by other classes to define what kind of things an
# external site can do.  This class is actually responsible for instantiating
# the right kind of class.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site;

use strict;
use Carp qw/ croak /;
use DW::External::Site::InsaneJournal;
use DW::External::Site::LiveJournal;
use DW::External::Site::JournalFen;
use DW::External::Site::Inksome;
use DW::External::Site::DeadJournal;
use DW::External::Site::Dreamwidth;
use DW::External::Site::Unknown;

my %domaintosite;
my %idtosite;

# static initializers
$domaintosite{"livejournal.com"} = DW::External::Site->new("2", "www.livejournal.com", "livejournal.com", "LiveJournal", "lj");
$domaintosite{"insanejournal.com"} = DW::External::Site->new("3", "www.insanejournal.com", "insanejournal.com", "InsaneJournal", "lj");
$domaintosite{"deadjournal.com"} = DW::External::Site->new("4", "www.deadjournal.com", "deadjournal.com", "DeadJournal", "lj");
$domaintosite{"inksome.com"} = DW::External::Site->new("5", "www.inksome.com", "inksome.com", "Inksome", "lj");
$domaintosite{"journalfen.net"} = DW::External::Site->new("6", "www.journalfen.net", "journalfen.net", "JournalFen", "lj");
$domaintosite{"dreamwidth.org"} = DW::External::Site->new("7", "www.dreamwidth.org", "dreamwidth.org", "Dreamwidth", "lj");


foreach my $value (values %domaintosite) {
    $idtosite{$value->{siteid}} = $value;
}

# now on to the class definition

# creates a new Site.  should only get called by the static initializer
sub new {
    my ( $class, $siteid, $hostname, $domain, $sitename, $servicetype ) = @_;

    return bless {
        siteid => $siteid,
        hostname => $hostname,
        domain => $domain,
        sitename => $sitename,
        servicetype => $servicetype
    }, $class."::".$sitename
}

# returns the appropriate site for this sitename.
sub get_site {
    my ( $class, %opts) = @_;

    my $site = delete $opts{site}
        or croak 'site argument required';
    croak 'invalid extra parameters'
        if %opts;

    # cleanup
    $site =~ s/\r?\n//s;            # multiple lines is pain
    $site =~ s!^(?:.+)://(.*)!$1!;  # remove proto:// leading
    $site =~ s!^([^/]+)/.*$!$1!;    # remove /foo/bar.html trailing

    # validate each part of the domain based on RFC 1035
    my @parts = grep { /^[a-z][a-z0-9\-]*?[a-z0-9]$/ }
                map { lc $_ }
                split( /\./, $site );

    return $domaintosite{"$parts[-2].$parts[-1]"} || DW::External::Site::Unknown->accepts( \@parts ) || undef;
}


# returns a list of all supported sites
sub get_sites {
    my ($class) = @_;

    return values %domaintosite;
}

# returns the appropriate site by site_id
sub get_site_by_id {
    my ($class, $siteid) = @_;

    return $idtosite{$siteid};
}

# returns this object if we accept the given domain, or 0 if not.
sub accepts {
    my ( $self, $parts ) = @_;

    # allows anything at this sitename
    return 0 unless $parts->[-1] eq $self->{tld} &&
                    $parts->[-2] eq $self->{domain};

    return $self;
}

# returns the journal_url for this user on this site.
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

# FIXME: this should do something like $u->is_person to determine what kind
# of thing to setup...
    return 'http://' . $self->{hostname} . '/users/' . $u->user . '/';
}


# returns the profile_url for this user on this site.
sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

# FIXME: same as above
    return 'http://' . $self->{hostname} . '/users/' . $u->user . '/profile';

}
# returns the badge_image_url for this user on this site.
sub badge_image_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

# FIXME: same as above
    return 'http://' . $self->{hostname} . '/img/userinfo.gif';
}

# adjust the request for any per-site limitations
sub pre_crosspost_hook {
    return $_[1];
}

1;
