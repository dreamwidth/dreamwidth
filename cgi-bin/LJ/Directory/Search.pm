# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Directory::Search;
use strict;
use warnings;

use LJ::Directory::Results;
use LJ::Directory::Constraint;
use LJ::ModuleCheck;
use Gearman::Task;
use Gearman::Taskset;
use Storable;
use Carp qw(croak);
use POSIX ();

sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    $self->{page_size} = int( delete $args{page_size} || 100 );
    $self->{page_size} = 1 if $self->{page_size} < 1;
    $self->{page_size} = 1000 if $self->{page_size} > 1000;

    $self->{page} = int( delete $args{page} || 1 );
    $self->{page} = 1 if $self->{page} < 1;

    $self->{format} = delete $args{format};
    $self->{format} = "pics"
        unless $self->{format} && $self->{format} =~ /^(pics|simple)$/;

    $self->{constraints} = delete $args{constraints} || [];
    croak "constraints not a hashref" unless ref $self->{constraints} eq "ARRAY";
    croak "Unknown parameters" if %args;
    return $self;
}

sub page_size   { $_[0]->{page_size} }
sub page        { $_[0]->{page} }
sub constraints { @{ $_[0]->{constraints} } }
sub format      { $_[0]->{format} }

sub add_constraint {
    my ( $self, $con ) = @_;
    push @{ $self->{constraints} }, $con;
}

# do a synchronous search, blocking until finished
# returns LJ::Directory::Results object of the search results
# %opts gets passed through to gearman
sub search {
    my ( $self, %opts ) = @_;

    return LJ::Directory::Results->empty_set unless @{ $self->{constraints} };

    if (@LJ::GEARMAN_SERVERS) {

        # we'll die if gearman_servers are configured but we can't
        # get to one... this is likely too heavy of an operation to
        # run unknowingly in apache
        my $gc = LJ::gearman_client()
            or die "unable to instantiate Gearman client for search";

        # do with gearman, if avail
        my $results;
        my $arg  = Storable::nfreeze($self);
        my $task = Gearman::Task->new(
            "directory_search",
            \$arg,
            {
                %opts,
                uniq        => "-",
                on_complete => sub {
                    my $res = shift;
                    return unless $res;
                    $results = Storable::thaw($$res);
                }
            }
        );

        my $ts = $gc->new_task_set();
        $ts->add_task($task);
        $ts->wait( timeout => 120 );    # time out after 2 minutes

        return $results || LJ::Directory::Results->empty_set;
    }

    # no gearman, just do in web context
    return $self->search_no_dispatch;
}

# do an asynchronous search with gearman
# returns a gearman task handle of the task doing the search
# %opts gets passed through to gearman
sub search_background {
    my ( $self, %opts ) = @_;

    return undef unless @{ $self->{constraints} };

    # return undef if no gearman
    my $gc = LJ::gearman_client();
    return undef unless @LJ::GEARMAN_SERVERS && $gc;

    # fire off gearman task in background
    return $gc->dispatch_background( 'directory_search', Storable::nfreeze($self), {%opts} );
}

# this does the actual search, should be called from gearman worker
sub search_no_dispatch {
    my ( $self, $job ) = @_;

    my @seth = $self->get_set_handles;

    unless ( LJ::ModuleCheck->have("LJ::UserSearch") ) {
        die "Missing module 'LJ::UserSearch'\n";
    }

    LJ::UserSearch::init_new_search();

    my $progress     = 0;
    my $progress_max = ( scalar @seth ) + 1;
    $job->set_status( $progress, $progress_max ) if $job;

    foreach my $sh (@seth) {
        $sh->filter_search;
        $progress++;
        $job->set_status( $progress, $progress_max ) if $job;
    }

    # arrayref of sorted uids
    my $uids = LJ::UserSearch::get_results();

    # truncate uids to max we are going to filter
    if ( @$uids > $LJ::MAX_DIR_SEARCH_RESULTS ) {
        @$uids = @{$uids}[ 0 .. $LJ::MAX_DIR_SEARCH_RESULTS - 1 ];
    }

    my $psize = $self->page_size;
    my $page  = $self->page;

    my $ditch = ( $page - 1 ) * $psize;

    my $totsize = @$uids;
    my $pages   = POSIX::ceil( $totsize / $psize );

    if ( @$uids >= $ditch ) {

        # remove leading pages
        splice( @$uids, 0, $ditch );
    }
    else {
        # or remove 'em all
        @$uids = ();
    }

    if ( @$uids > $psize ) {
        splice( @$uids, $psize );    # remove the rest.
    }

    my $res = LJ::Directory::Results->new(
        page_size => $psize,
        pages     => $pages,
        page      => $page,
        userids   => $uids,
        format    => $self->format,
    );
    return $res;
}

# we want to return these in the smallest to largest sets.
sub get_set_handles {
    my $self = shift;
    my @seth;
    my $n = 0;
    my @todo;    # subrefs to fetch
    my $failed = '';
    my $ts     = @LJ::GEARMAN_SERVERS ? LJ::gearman_client()->new_task_set : undef;

    foreach my $cs ( sort { $a->cardinality <=> $b->cardinality } $self->constraints ) {
        my $sh = $cs->cached_sethandle;
        if ($sh) {
            $seth[$n] = $sh;
        }
        else {
            if (@LJ::GEARMAN_SERVERS) {
                my $index          = $n;
                my $constraint_str = $cs->serialize;
                my $searcharg      = Storable::nfreeze( [ \$constraint_str ] );
                $ts->add_task(
                    Gearman::Task->new(
                        "directory_search_constraint",
                        \$searcharg,
                        {
                            on_complete => sub {
                                my $shstr = shift;
                                $seth[$index] = LJ::Directory::SetHandle->new_from_string($$shstr),;
                            },
                            on_fail => sub {
                                $failed .= @_;
                            },
                        }
                    )
                );
            }
            else {
                $seth[$n] = $cs->sethandle;
            }
        }
        $n++;
    }

    if ($failed) {
        die "Error in gearman search: $failed";
    }

    # 60 second timeout ... high enough that it'll never impair legit use
    $ts->wait( timeout => 60 ) if $ts;
    return @seth;
}

1;
