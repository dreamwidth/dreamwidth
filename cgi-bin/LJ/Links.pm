#!/usr/bin/perl

#
# Functions for lists of links created by users for display in their journals
#

use strict;

package LJ::Links;

# linkobj structure:
#
# $linkobj = [
#    { 'title'     => 'link title',
#      'url'       => 'http://www.somesite.com',
#      'children'  => [ ... ],
#    },
#    { ... },
#    { ... },
# ];

sub load_linkobj
{
    my ($u, $use_master) = @_;
    return unless LJ::isu($u);

    # check memcache for linkobj
    my $memkey = [$u->{'userid'}, "linkobj:$u->{'userid'}"];
    my $linkobj = LJ::MemCache::get($memkey);
    return $linkobj if defined $linkobj;

    # didn't find anything in memcache
    $linkobj = [];

    {
        # not in memcache, need to build one from db
        my $db = $use_master ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);

        local $" = ",";
        my $sth = $db->prepare("SELECT ordernum, parentnum, title, url " .
                               "FROM links WHERE journalid=?");
        $sth->execute($u->{'userid'});
        push @$linkobj, $_ while $_ = $sth->fetchrow_hashref;
    }

    # sort in perl-space
    @$linkobj = sort { $a->{'ordernum'} <=> $b->{'ordernum'} } @$linkobj;

    # fix up the data structure
    foreach (@$linkobj) {

        # TODO: build child relationships
        #       and store in $_->{'children'}

        # ordernum/parentnum are only exposed via the 
        # array structure, delete them here
        delete $_->{'ordernum'};
        delete $_->{'parentnum'};
    }

    # set linkobj in memcache
    LJ::MemCache::set($memkey, $linkobj);

    return $linkobj;
}

sub save_linkobj
{
    my ($u, $linkobj) = @_;
    return undef unless LJ::isu($u) && ref $linkobj eq 'ARRAY' && $u->writer;

    # delete old links, we'll rebuild them shortly
    $u->do("DELETE FROM links WHERE journalid=?", undef, $u->{'userid'});

    # only save allowed number of links
    my $numlinks = @$linkobj;
    my $caplinks = $u->count_max_userlinks;
    $numlinks = $caplinks if $numlinks > $caplinks;

    # build insert query
    my (@bind, @vals);
    foreach my $ct (1..$numlinks) {
        my $it = $linkobj->[$ct-1];

        # journalid, ordernum, parentnum, url, title
        push @bind, "(?,?,?,?,?)";
        push @vals, ($u->{'userid'}, $ct, 0, $it->{'url'}, $it->{'title'});
    }

    # invalidate memcache
    my $memkey = [$u->{'userid'}, "linkobj:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);

    # insert into database
    {
        local $" = ",";
        return $u->do("INSERT INTO links (journalid, ordernum, parentnum, url, title) " .
                      "VALUES @bind", undef, @vals);
    }
}

sub make_linkobj_from_form
{
    my ($u, $post) = @_;
    return unless LJ::isu($u) && ref $post eq 'HASH';

    my $linkobj = [];

    # remove leading and trailing spaces
    my $stripspaces = sub {
        my $str = shift;
        $str =~ s/^\s*//;
        $str =~ s/\s*$//;
        return $str;
    };

    # find number of links allowed
    my $numlinks = $post->{'numlinks'};
    my $caplinks = $u->count_max_userlinks;
    $numlinks = $caplinks if $numlinks > $caplinks;

    foreach my $num (sort { $post->{"link_${a}_ordernum"} <=>
                            $post->{"link_${b}_ordernum"} } (1..$numlinks)) {

        # title is required
        my $title = $post->{"link_${num}_title"};
        $title = $stripspaces->($title);
        next unless $title;

        my $url = $post->{"link_${num}_url"};
        $url = $stripspaces->($url);

        # smartly add http:// to url unless they are just inserting a blank line
        if ($url && $title ne '-') {
            $url = LJ::CleanHTML::canonical_url($url);
        }

        # build link object element
        $post->{"link_${num}_url"} = $url;
        push @$linkobj, { 'title' => $title, 'url' => $url };

        # TODO: build child relationships
        #       push @{$linkobj->[$parentnum-1]->{'children'}}, $myself
    }

    return $linkobj;
}

1;
