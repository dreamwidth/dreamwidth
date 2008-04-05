use strict;
package LJ::S2;

sub TagsPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "TagsPage";
    $p->{'view'} = "tags";
    $p->{'tags'} = [];

    my $user = $u->{'user'};
    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    $p->{'head_content'} .= $u->openid_tags;

    if ($u->should_block_robots) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    # get tags for the page to display
    my @taglist;
    my $tags = LJ::Tags::get_usertags($u, { remote => $remote });
    foreach my $kwid (keys %{$tags}) {
        # only show tags for display
        next unless $tags->{$kwid}->{display};
        push @taglist, LJ::S2::TagDetail($u, $kwid => $tags->{$kwid});
    }
    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;
    $p->{'_visible_tag_list'} = $p->{'tags'} = \@taglist;

    return $p;
}

1;
