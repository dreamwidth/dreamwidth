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
use DW::External::XPostProtocol;

use LJ::ModuleLoader;
LJ::ModuleLoader->require_subclasses( "DW::External::Site" );

my %domaintosite;
my %idtosite;

# static initializers
$domaintosite{"livejournal.com"} = DW::External::Site->new("2", "www.livejournal.com", "livejournal.com", "LiveJournal", "lj");
$domaintosite{"insanejournal.com"} = DW::External::Site->new("3", "www.insanejournal.com", "insanejournal.com", "InsaneJournal", "lj");
$domaintosite{"deadjournal.com"} = DW::External::Site->new("4", "www.deadjournal.com", "deadjournal.com", "DeadJournal", "lj");
$domaintosite{"inksome.com"} = DW::External::Site->new("5", "www.inksome.com", "inksome.com", "Inksome", "lj");
$domaintosite{"journalfen.net"} = DW::External::Site->new("6", "www.journalfen.net", "journalfen.net", "JournalFen", "lj");
$domaintosite{"dreamwidth.org"} = DW::External::Site->new("7", "www.dreamwidth.org", "dreamwidth.org", "Dreamwidth", "lj");
$domaintosite{"archiveofourown.org"} = DW::External::Site->new("8", "www.archiveofourown.org", "archiveofourown.org", "ArchiveofOurOwn", "AO3");
$domaintosite{"twitter.com"} = DW::External::Site->new("9", "twitter.com", "twitter.com", "Twitter", "Twitter");

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


# returns a list of all supported sites for linking
sub get_sites { return values %domaintosite; }

# returns a list of all supported sites for crossposting
sub get_xpost_sites {
    my %protocols = DW::External::XPostProtocol->get_all_protocols;
    return grep { exists $protocols{ $_->{servicetype} } && LJ::is_enabled( "external_sites", $_ ) }
           values %domaintosite;
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

# returns the servicetype
sub servicetype {
    return $_[0]->{servicetype};
}


1;
