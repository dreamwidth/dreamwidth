############################################################################
package LJ::NavTag;
use strict;

sub valid_types {
    return qw(LJUSER FAQ PAGE SSL);
}

sub is_valid_type {
    my $class = shift;
    my $type = shift;
    return grep { $_ eq $type } valid_types();
}

sub canonical_tag {
    shift @_ if $_[0] eq __PACKAGE__;
    my $tag = shift;
    die if @_;

    $tag =~ s/^\s+//;
    $tag =~ s/\s+$//;
    $tag =~ tr/A-Z/a-z/;
    return $tag;
}

sub tags_of_url {
    my ($type, $url) = @_;
    my $dest = LJ::NavTag::Dest->new_from_url($url);
    return undef unless $dest;
    return LJ::NavTag->tags_of_dest($dest);
}

sub tags_of_dest {
    my ($class, $dest) = @_;
    my @tags = ();
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT tag FROM navtag WHERE dest_type=? AND dest=?");
    $sth->execute($dest->type, $dest->dest);
    while (my ($tag) = $sth->fetchrow_array) {
        push @tags, $tag;
    }

    return @tags;
}

# returns hashref of { $tag => $count }
sub tags_with_count {
    shift @_ if $_[0] eq __PACKAGE__;
    die if @_;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT tag, count(*) FROM navtag GROUP BY tag");
    $sth->execute;
    my $tags = {};
    while (my ($tag, $count) = $sth->fetchrow_array) {
        $tags->{$tag} = $count;
    }
    return $tags;
}

# given a tag (scalar), returns an array of destination objects
sub dests_of_tag {
    shift @_ if $_[0] eq __PACKAGE__;
    my $tag = shift;
    $tag = LJ::NavTag->canonical_tag($tag);
    die if @_;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT dest_type, dest FROM navtag WHERE tag=?");
    $sth->execute($tag);
    my @dests;
    while (my $rec = $sth->fetchrow_hashref) {
        my $dest = LJ::NavTag::Dest->new(type  => $rec->{dest_type},
                                         dest  => $rec->{dest});
        push @dests, $dest;
    }

    return @dests;
}

############################################################################
package LJ::NavTag::Dest;
use strict;

sub new {
    my ($class, %opts) = @_;
    my $self = {};
    $self->{type}  = delete $opts{'type'};
    $self->{dest}  = delete $opts{'dest'};
    die "Unknown arguments to constructor: " . join(", ", keys %opts) if %opts;
    die "Unknown type" unless LJ::NavTag->is_valid_type($self->{type});
    bless $self, "LJ::NavTag::Dest::$self->{type}";
    return $self;
}

# $destobj = LJ::NavTag::Dest->new_from_url("http://www.livejournal.com/userinfo.bml?user=brad");
sub new_from_url {
    my ($class, $url) = @_;
    foreach my $type (LJ::NavTag->valid_types) {
        my $dest = "LJ::NavTag::Dest::$type"->dest_from_url($url);
        return $dest if $dest;
    }
    return undef;
}

sub dest_from_url { undef; }

sub type { my $self = shift; return $self->{type}; }
sub dest { my $self = shift; return $self->{dest}; }

sub add_tag {
    my ($self, $tag) = @_;
    $tag = LJ::NavTag->canonical_tag($tag);
    my $dbh = LJ::get_db_writer();
    return $dbh->do("INSERT INTO navtag SET tag=?, dest_type=?, dest=?",
                    undef, $tag, $self->type, $self->dest);
}

sub remove_tag {
    my ($self, $tag) = @_;
    $tag = LJ::NavTag->canonical_tag($tag);
    my $dbh = LJ::get_db_writer();
    return $dbh->do("DELETE FROM navtag WHERE tag=? AND dest_type=? AND dest=?",
                    undef, $tag, $self->type, $self->dest);
}

sub title {
    my $self = shift;
    return "$self->{type} -- $self->{dest}";
}

sub ljuser { undef; }

sub url { "about:"; }

############################################################################
package LJ::NavTag::Dest::LJUSER;
use base "LJ::NavTag::Dest";

sub ljuser {
    my $self = shift;
    return LJ::load_user($self->{dest});
}

sub title {
    my $self = shift;
    my $u = $self->ljuser;
    return $u ? $u->{name} : $self->SUPER::title;
}

sub url {
    my $self = shift;
    my $user = $self->{dest};
    my $u = LJ::load_user($user);
    return $u->profile_url if $u;
    return "$LJ::SITEROOT/userinfo.bml?user=$user";
}

sub dest_from_url {
    my ($class, $url) = @_;
    # FIXME: broken.  wrong URL type
    return undef unless $url =~ m!/userinfo.bml\?user=(\w+)!;
    return LJ::NavTag::Dest->new(type  => "LJUSER",
                                 dest  => $1);
}

############################################################################
package LJ::NavTag::Dest::PAGE;
use base "LJ::NavTag::Dest";

sub url { my $self = shift; "$LJ::SITEROOT" . $self->{dest} }

sub dest_from_url {
    my ($class, $url) = @_;
    return undef unless $url =~ s!^\Q$LJ::SITEROOT\E!!;
    return LJ::NavTag::Dest->new(type  => "PAGE",
                                 dest  => $url || "/");
}

sub title {
    my $self = shift;
    my $curlang = BML::get_language();
    my $mld = LJ::Lang::get_dom("general");
    my $dest = $self->{dest};
    $dest .= "index.bml" unless $dest =~ /\.bml$/;
    return LJ::Lang::get_text($curlang, $dest . ".title", $mld->{'dmid'}) ||
        $self->{dest};
}

############################################################################
package LJ::NavTag::Dest::SSL;
use base "LJ::NavTag::Dest::PAGE";

sub url { my $self = shift; "$LJ::SSLROOT" . $self->{dest} }

sub dest_from_url {
    my ($class, $url) = @_;
    return undef unless $url =~ s!^\Q$LJ::SSLROOT\E!!;
    return LJ::NavTag::Dest->new(type  => "PAGE",
                                 dest  => $url || "/");
}

############################################################################
package LJ::NavTag::Dest::FAQ;
use base "LJ::NavTag::Dest";

sub dest_from_url {
    my ($class, $url) = @_;
    return undef unless $url =~ m!/support/faqbrowse.bml\?faqid=(\d+)!;
    return LJ::NavTag::Dest->new(type  => "FAQ",
                                 dest  => $1);
}

sub _faqid { int($_[0]->{dest}) };

sub url {
    my $self = shift;
    return "$LJ::SITEROOT/support/faqbrowse.bml?faqid=" . $self->_faqid;
}

sub title {
    my $self = shift;
    my $curlang = BML::get_language();
    my $deflang = BML::get_language_default();
    my $altlang = $curlang ne $deflang;
    my $mld = LJ::Lang::get_dom("faq");
    if ($altlang) {
        return LJ::Lang::get_text($curlang, $self->_faqid . ".1question", $mld->{'dmid'});
    }

    my $dbr = LJ::get_db_reader();
    return $dbr->selectrow_array("SELECT question FROM faq WHERE faqid=?", undef, $self->_faqid);
}

1;
