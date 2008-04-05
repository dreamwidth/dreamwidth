#!/usr/bin/perl
#

package LJ::Todo;

sub get_permissions
{
    my ($dbh, $perm, $opts) = @_;
    my $sth;
    my $u = $opts->{'user'};
    my $remote = $opts->{'remote'};
    my $it = $opts->{'item'};

    return () unless $remote;

    if ($u->{'userid'} == $remote->{'userid'}) {
        $perm->{'delete'} = 1;
        $perm->{'edit'} = 1;
        $perm->{'add'} = 1;
    } else {
        my $quser = $dbh->quote($u->{'user'});
        
        ## check if you're an admin of that journal 
        my $is_manager = LJ::can_manage($remote, $u);
        if ($is_manager) {
            $perm->{'add'} = 1;
            $perm->{'delete'} = 1;
            $perm->{'edit'} = 1;
        } else {
            # TAG:FR:ljtodo:get_friends_in_group
            foreach my $priv (qw(add edit delete)) {
                my $group = LJ::get_friend_group($u, { name => "priv-todo-$priv" });
                next unless $group;
                my $mask = 1 << $group->{groupnum};
                my $friends = LJ::get_friends($u, $mask);
                $perm->{$priv} = 1 if $friends->{$remote->{userid}};
            }
        }
    }
        
    return %permission;
}


1;
