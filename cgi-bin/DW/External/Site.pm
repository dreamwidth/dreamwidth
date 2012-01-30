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
# Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site;

use strict;
use Carp qw/ croak /;
use DW::External::Userinfo;
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
$domaintosite{"ao3.org"} = $domaintosite{"archiveofourown.org"};
$domaintosite{"twitter.com"} = DW::External::Site->new("9", "twitter.com", "twitter.com", "Twitter", "Twitter");
$domaintosite{"tumblr.com"} = DW::External::Site->new("10", "tumblr.com", "tumblr.com", "Tumblr", "Tumblr");
$domaintosite{"etsy.com"} = DW::External::Site->new("11", "www.etsy.com", "etsy.com", "Etsy", "Etsy");
$domaintosite{"diigo.com"} = DW::External::Site->new("12", "www.diigo.com", "diigo.com", "Diigo", "Diigo");
$domaintosite{"blogspot.com"} = DW::External::Site->new("13", "blogspot.com", "blogspot.com", "Blogspot", "blogspot");
$domaintosite{"delicious.com"} = DW::External::Site->new("14", "delicious.com", "delicious.com", "Delicious", "delicious");
$domaintosite{"deviantart.com"} = DW::External::Site->new("15", "deviantart.com", "deviantart.com", "DeviantArt", "da");
$domaintosite{"last.fm"} = DW::External::Site->new("16", "last.fm", "last.fm", "LastFM", "lastfm");
$domaintosite{"ravelry.com"} = DW::External::Site->new("17", "www.ravelry.com", "ravelry.com", "Ravelry", "ravelry");
$domaintosite{"wordpress.com"} = DW::External::Site->new("18", "wordpress.com", "wordpress.com", "Wordpress", "WP");
$domaintosite{"plurk.com"} = DW::External::Site->new("19", "plurk.com", "plurk.com", "Plurk", "Plurk");
$domaintosite{"pinboard.in"} = DW::External::Site->new("20", "www.pinboard.in", "pinboard.in", "Pinboard", "Pinboard");
$domaintosite{"fanfiction.net"} = DW::External::Site->new("21", "www.fanfiction.net", "fanfiction.net", "FanFiction", "FanFiction");

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

# returns the account type for this user on this site.
sub journaltype {
    my $self = shift;
    return DW::External::Userinfo->lj_journaltype( @_ )
        if $self->{servicetype} eq 'lj';
    return 'P';  # default
}

# returns the journal_url for this user on this site.
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # IF YOU OVERRIDE THIS WITH CODE THAT CHECKS JOURNALTYPE,
    # YOU MUST PASS THE BASE URL TO CHECK EXPLICITLY.
    # OTHERWISE IT WILL CALL BACK HERE FOR THE URL,
    # AND YOU WILL SEE WHAT INFINITE RECURSION LOOKS LIKE.

    # override this on a site-by-site basis if needed
    return "http://$self->{hostname}/users/" . $u->user . '/';
}

# returns the profile_url for this user on this site.
sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # IF YOU OVERRIDE THIS WITH CODE THAT CHECKS JOURNALTYPE,
    # YOU MUST PASS THE BASE URL TO CHECK EXPLICITLY.
    # OTHERWISE IT WILL CALL BACK HERE FOR THE URL,
    # AND YOU WILL SEE WHAT INFINITE RECURSION LOOKS LIKE.

    # override this on a site-by-site basis if needed
    return $self->journal_url( $u ) . 'profile';

}

# returns the feed_url for this user on this site.
sub feed_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # IF YOU OVERRIDE THIS WITH CODE THAT CHECKS JOURNALTYPE,
    # YOU MUST PASS THE BASE URL TO CHECK EXPLICITLY.
    # OTHERWISE IT WILL CALL BACK HERE FOR THE URL,
    # AND YOU WILL SEE WHAT INFINITE RECURSION LOOKS LIKE.

    # override this on a site-by-site basis if needed
    return $self->journal_url( $u ) . 'data/atom';
}

# returns the badge_image info for this user on this site.
sub badge_image {
    my ( $self, $u ) = @_;

    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # override this on a site-by-site basis if needed
    my $type = $self->journaltype( $u ) || 'P';
    my $gif = {
               #      URL,                   width, height
               P => [ '/img/userinfo.gif',   17, 17 ],
               C => [ '/img/community.gif',  16, 16 ],
               Y => [ '/img/syndicated.gif', 16, 16 ],
              };

    my $img = $gif->{$type};
    return {
    # this will do the right thing for an lj-based site,
    # but it's better to override this with cached images
    # to avoid hammering the remote site with image requests.

        url     => "http://$self->{hostname}$img->[0]",
        width   => $img->[1],
        height  => $img->[2],
    }
}

# adjust the request for any per-site limitations
sub pre_crosspost_hook {
    return $_[1];
}

# returns the servicetype
sub servicetype {
    return $_[0]->{servicetype};
}

# returns a cleaned version of the username
sub canonical_username {
    my $input = $_[1];
    my $user = "";

    if ( $input =~ /^\s*([a-zA-Z0-9_\-]+)\s*$/ ) {  # good username
        $user = $1;
    }
    return $user;
}

1;
