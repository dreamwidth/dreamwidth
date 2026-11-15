#!/usr/bin/perl
#
# DW::Importer::Registry
#
# The single description of what the content importer can import: the sources
# data comes from, and the items (jobs) that make up an import from each.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::Registry;

=head1 NAME

DW::Importer::Registry - Sources and items known to the content importer

=head1 SYNOPSIS

    my $item = DW::Importer::Registry->item('lj_entries');
    my $class = $item->{class};

    my @deps = DW::Importer::Registry->depends_on( 'lj_entries', 'community' );

    my @names = DW::Importer::Registry->expand_selection( 'livejournal',
        [ 'lj_comments' ], 'person' );

=head1 DESCRIPTION

Everything that used to be repeated across the scheduler, controllers, workers and
admin tools (which worker class runs an item, which items need which, what the
status events are called) is defined here once.

A I<source> is a place content can be imported from. Its C<kind> is C<remote>
(logged into with the user's credentials) or C<file> (uploaded by the user). A
remote source lists the C<sites> it can talk to.

An I<item> is one job within an import, such as importing entries. Item names are
stored in the database (C<import_items.item>), so they never change.

=head2 Source fields

=over

=item name

Unique name of the source.

=item display_name

Human readable name.

=item kind

C<remote> or C<file>.

=item sites

Remote sources only: an arrayref of hashrefs with C<name>, C<hostname>,
C<display_name> and optionally C<dev_only>, which the user can pick between.

=item site_enabled

Optional coderef, given a site hashref, true if that site is currently offered.

=item enabled

Optional coderef, given a hostname (which is undefined for sources without one),
true if jobs for this source should run. Defaults to the C<importing> site switch.

=back

=head2 Item fields

=over

=item name, source, class, typeid

The item name (e.g. C<lj_entries>), the source it belongs to, the
C<TheSchwartz> worker class that runs it, and the number that identifies it in
C<LJ::Event::ImportStatus>. Worker classes are the C<TheSchwartz> function names
of queued jobs and typeids are stored in notifications, so neither may change
or be reused.

=item depends_on

What must succeed before this item can start: an arrayref of item names, or a
hashref with C<person> and C<community> arrayrefs when the answer depends on the
type of journal being imported into. A dependency that is not part of the import is
ignored. When a dependency fails permanently, items waiting for it are aborted.

=item initial_status

C<ready> for items that start immediately, C<init> for items that wait for their
dependencies.

=item implies

Items that are automatically selected along with this one. This is a selection
rule for the choose-data page, separate from C<depends_on>, which is scheduling.

=item suboptions

Names of extra options (checkboxes) that belong to this item. Choosing one selects
the item.

=item comm_okay

True if the item can be imported into a community.

=item selectable

True if users can pick this item. Items that are not selectable are only ever
added through C<always> or C<implies>.

=item always

True if every import includes this item.

=item queue

Which worker processes run this item: C<lite> items run in C<content-importer> and
C<content-importer-lite>, C<heavy> items only in C<content-importer>, C<verify>
items only in C<content-importer-verify>.

=item notify_on_success

False for items that should not notify the user when they succeed.

=item short_name

What the item is called in process titles and logs; defaults to the name without
its source prefix (C<entries> for C<lj_entries>).

=item display_order

Position on the choose-data page.

=item event_noun

How the item is named in the "your ... have been imported" notification.

=item reports_posts

True for items whose status notifications describe a single post.

=back

=cut

use strict;
use warnings;
use v5.10;

use Carp qw/ croak /;

my ( %SOURCES, @SOURCE_ORDER, %ITEMS, @ITEM_ORDER, %BY_CLASS, %BY_TYPEID );

my %PROCESS_QUEUES = (
    'content-importer'        => [qw( heavy lite )],
    'content-importer-lite'   => [qw( lite )],
    'content-importer-verify' => [qw( verify )],
);

my %ITEM_DEFAULTS = (
    depends_on        => [],
    implies           => [],
    suboptions        => [],
    initial_status    => 'init',
    comm_okay         => 1,
    selectable        => 1,
    always            => 0,
    queue             => 'lite',
    notify_on_success => 1,
    display_order     => 100,
    reports_posts     => 0,
);

=head1 Defining sources and items

=head2 C<< DW::Importer::Registry->register_source( %fields ) >>

Adds a source. Tests use this (and C<unregister_source>) to add their own.

=cut

sub register_source {
    my ( $class, %def ) = @_;

    my $name = $def{name} or croak 'source needs a name';
    croak "source $name is already registered" if $SOURCES{$name};
    croak "source $name has an invalid kind"
        unless ( $def{kind} // '' ) =~ /^(?:remote|file)$/;

    $def{sites} ||= [];
    $SOURCES{$name} = \%def;
    push @SOURCE_ORDER, $name;
    return \%def;
}

=head2 C<< DW::Importer::Registry->register_item( %fields ) >>

Adds an item to a source that is already registered.

=cut

sub register_item {
    my ( $class, %def ) = @_;

    foreach my $field (qw( name source class typeid )) {
        croak "item needs a $field" unless defined $def{$field};
    }
    my $name = $def{name};

    croak "item $name belongs to unknown source $def{source}" unless $SOURCES{ $def{source} };
    croak "item $name is already registered"          if $ITEMS{$name};
    croak "class $def{class} is already registered"   if $BY_CLASS{ $def{class} };
    croak "typeid $def{typeid} is already registered" if $BY_TYPEID{ $def{typeid} };

    my %item = ( %ITEM_DEFAULTS, short_name => $name =~ s/^[a-z]+_//r, %def );
    $ITEMS{$name}               = \%item;
    $BY_CLASS{ $item{class} }   = \%item;
    $BY_TYPEID{ $item{typeid} } = \%item;
    push @ITEM_ORDER, $name;
    return \%item;
}

=head2 C<< DW::Importer::Registry->unregister_source( $name ) >>

Removes a source and its items.

=cut

sub unregister_source {
    my ( $class, $name ) = @_;

    foreach my $item ( $class->items($name) ) {
        delete $ITEMS{ $item->{name} };
        delete $BY_CLASS{ $item->{class} };
        delete $BY_TYPEID{ $item->{typeid} };
    }
    @ITEM_ORDER   = grep { $ITEMS{$_} } @ITEM_ORDER;
    @SOURCE_ORDER = grep { $_ ne $name } @SOURCE_ORDER;
    delete $SOURCES{$name};
}

=head1 Looking things up

=head2 C<< DW::Importer::Registry->sources >>

All sources, in registration order.

=cut

sub sources {
    return map { $SOURCES{$_} } @SOURCE_ORDER;
}

=head2 C<< DW::Importer::Registry->source( $name ) >>

One source by name, or undef.

=cut

sub source {
    my ( $class, $name ) = @_;
    return $name ? $SOURCES{$name} : undef;
}

=head2 C<< DW::Importer::Registry->source_for_hostname( $hostname ) >>

The source that has a site with this hostname, or undef.

=cut

sub source_for_hostname {
    my ( $class, $hostname ) = @_;
    return undef unless defined $hostname;

    foreach my $source ( $class->sources ) {
        return $source if grep { $_->{hostname} eq $hostname } @{ $source->{sites} };
    }
    return undef;
}

=head2 C<< DW::Importer::Registry->enabled_sites >>

The sites users can choose to import from right now, as a list of hashrefs with
C<source>, C<name>, C<hostname> and C<display_name>.

=cut

sub enabled_sites {
    my ($class) = @_;

    my @sites;
    foreach my $source ( $class->sources ) {
        foreach my $site ( @{ $source->{sites} } ) {
            next if $site->{dev_only} && !$LJ::IS_DEV_SERVER;
            next if $source->{site_enabled} && !$source->{site_enabled}->($site);
            push @sites, { %$site, source => $source->{name} };
        }
    }
    return @sites;
}

=head2 C<< DW::Importer::Registry->source_enabled( $source_name, $hostname ) >>

True if jobs for the source should run.

=cut

sub source_enabled {
    my ( $class, $name, $hostname ) = @_;

    my $source = $SOURCES{ $name // '' };
    return $source->{enabled}->($hostname) if $source && $source->{enabled};
    return LJ::is_enabled( 'importing', $hostname );
}

=head2 C<< DW::Importer::Registry->items( [ $source_name ] ) >>

The items of one source (or all sources) in the order they are created.

=cut

sub items {
    my ( $class, $source ) = @_;
    return grep { !defined $source || $_->{source} eq $source } map { $ITEMS{$_} } @ITEM_ORDER;
}

=head2 C<< DW::Importer::Registry->item( $name ) >>

One item by name, or undef.

=cut

sub item {
    my ( $class, $name ) = @_;
    return defined $name ? $ITEMS{$name} : undef;
}

=head2 C<< DW::Importer::Registry->item_for_class( $worker_class ) >>

=head2 C<< DW::Importer::Registry->item_for_typeid( $typeid ) >>

The item run by a worker class, or identified by a notification typeid.

=cut

sub item_for_class {
    my ( $class, $worker ) = @_;
    return defined $worker ? $BY_CLASS{$worker} : undef;
}

sub item_for_typeid {
    my ( $class, $typeid ) = @_;
    return defined $typeid ? $BY_TYPEID{$typeid} : undef;
}

=head2 C<< DW::Importer::Registry->classes( [ $source_name ] ) >>

The worker classes of the items of one source (or all of them).

=cut

sub classes {
    my ( $class, $source ) = @_;
    return map { $_->{class} } $class->items($source);
}

=head2 C<< DW::Importer::Registry->classes_for_process( $process ) >>

The worker classes a worker process (C<content-importer>, C<content-importer-lite>
or C<content-importer-verify>) should run.

=cut

sub classes_for_process {
    my ( $class, $process ) = @_;

    my $queues = $PROCESS_QUEUES{$process}
        or croak "unknown importer worker process $process";
    my %want = map { $_ => 1 } @$queues;
    return map { $_->{class} } grep { $want{ $_->{queue} } } $class->items;
}

=head2 C<< DW::Importer::Registry->journaltype( $u ) >>

C<community> or C<person>, the two kinds of journal an import can target.

=cut

sub journaltype {
    my ( $class, $u ) = @_;
    return $u && $u->is_community ? 'community' : 'person';
}

=head1 Dependencies

=head2 C<< DW::Importer::Registry->depends_on( $item_name, $journaltype ) >>

The names of the items that have to succeed before this one can start.

=cut

sub depends_on {
    my ( $class, $name, $journaltype ) = @_;

    my $item = $ITEMS{$name}
        or croak "unknown importer item $name";
    my $deps = $item->{depends_on};
    $deps = $deps->{ $journaltype || 'person' } || [] if ref $deps eq 'HASH';
    return @$deps;
}

=head2 C<< DW::Importer::Registry->dependents( $item_name, $journaltype ) >>

The names of the items that wait for this one.

=cut

sub dependents {
    my ( $class, $name, $journaltype ) = @_;

    return map { $_->{name} }
        grep {
        my $n = $_->{name};
        grep { $_ eq $name } $class->depends_on( $n, $journaltype )
        } $class->items( $ITEMS{$name}->{source} );
}

=head2 C<< DW::Importer::Registry->expand_selection( $source, \@chosen, $journaltype ) >>

Turns what the user ticked into the items to import. C<@chosen> holds item names and
suboption names. Suboptions select their item, items select what they imply, items
that are always imported are added and items that make no sense for the journal type
are dropped. Returns item names in creation order; suboptions are not included.

=cut

sub expand_selection {
    my ( $class, $source, $chosen, $journaltype ) = @_;

    my %parent;
    foreach my $item ( $class->items($source) ) {
        $parent{$_} = $item->{name} foreach @{ $item->{suboptions} };
    }

    my %selected;
    my @todo = grep { defined } map { $parent{$_} || ( $ITEMS{$_} ? $_ : undef ) } @$chosen;
    push @todo, map { $_->{name} } grep { $_->{always} } $class->items($source);

    while ( defined( my $name = shift @todo ) ) {
        next if $selected{$name}++;
        push @todo, @{ $ITEMS{$name}->{implies} };
    }

    return map { $_->{name} }
        grep {
        my $item = $_;
        $selected{ $item->{name} } && ( $journaltype ne 'community' || $item->{comm_okay} )
        } $class->items($source);
}

=head2 C<< DW::Importer::Registry->dependency_map( $source ) >>

A hashref of item or suboption name to the names that get selected with it, for the
choose-data page to apply in the browser the same rules C<expand_selection> applies
on the server.

=cut

sub dependency_map {
    my ( $class, $source ) = @_;

    my %map;
    foreach my $item ( $class->items($source) ) {
        $map{ $item->{name} } = [ @{ $item->{implies} } ] if @{ $item->{implies} };
        $map{$_} = [ $item->{name} ] foreach @{ $item->{suboptions} };
    }
    return \%map;
}

=head2 C<< DW::Importer::Registry->validate >>

Checks the registered items for mistakes that would leave an import stuck: items
that depend on unknown items, or on an item that selecting them does not import, or
that depend on each other in a circle. Returns a list of problems, empty when all is
well.

=cut

sub validate {
    my ($class) = @_;

    my @problems;
    my @journaltypes = qw( person community );

    foreach my $item ( $class->items ) {
        my $name = $item->{name};

        # references must point at registered items before anything else can be checked
        my @refs =
            ( @{ $item->{implies} }, map { $class->_raw_depends_on( $item, $_ ) } @journaltypes );
        my @unknown = grep { !$ITEMS{$_} } @refs;
        if (@unknown) {
            push @problems, "$name refers to unknown items: " . join( ', ', sort @unknown );
            next;
        }

        foreach my $jt (@journaltypes) {
            next if $jt eq 'community' && !$item->{comm_okay};

            # whatever it waits for has to be imported along with it, or it would wait forever
            my %imported =
                map { $_ => 1 } $class->expand_selection( $item->{source}, [$name], $jt );
            foreach my $dep ( $class->depends_on( $name, $jt ) ) {
                push @problems, "$name depends on $dep, which is not imported with it for a $jt"
                    unless $imported{$dep};
            }

            # and it must not (indirectly) wait for itself
            my ( %seen, @queue );
            @queue = $class->depends_on( $name, $jt );
            while ( defined( my $dep = shift @queue ) ) {
                if ( $dep eq $name ) {
                    push @problems, "$name has a circular dependency for a $jt";
                    last;
                }
                next if $seen{$dep}++;
                push @queue, $class->depends_on( $dep, $jt );
            }
        }
    }
    return @problems;
}

sub _raw_depends_on {
    my ( $class, $item, $journaltype ) = @_;
    my $deps = $item->{depends_on};
    return @{ ref $deps eq 'HASH' ? $deps->{$journaltype} || [] : $deps };
}

# the sources and items that come with the importer
{
    my $prefix = 'DW::Worker::ContentImporter::LiveJournal';

    __PACKAGE__->register_source(
        name         => 'livejournal',
        display_name => 'LiveJournal-compatible sites',
        kind         => 'remote',
        sites        => [
            { name => 'livejournal', hostname => 'livejournal.com', display_name => 'LiveJournal' },
            {
                name         => 'insanejournal',
                hostname     => 'insanejournal.com',
                display_name => 'InsaneJournal'
            },
            {
                name         => 'dreamwidth',
                hostname     => 'dreamwidth.org',
                display_name => 'Dreamwidth',
                dev_only     => 1
            },
        ],
        site_enabled => sub {
            my ($site) = @_;
            return LJ::is_enabled( 'external_sites',
                { sitename => $site->{display_name}, domain => $site->{hostname} } );
        },
    );

    __PACKAGE__->register_item(
        name              => 'lj_verify',
        source            => 'livejournal',
        class             => "$prefix\::Verify",
        typeid            => 7,
        initial_status    => 'ready',
        queue             => 'verify',
        always            => 1,
        selectable        => 0,
        notify_on_success => 0,
        event_noun        => 'import has',
    );
    __PACKAGE__->register_item(
        name          => 'lj_userpics',
        source        => 'livejournal',
        class         => "$prefix\::Userpics",
        typeid        => 6,
        depends_on    => ['lj_verify'],
        display_order => 70,
        event_noun    => 'usericons have',
    );
    __PACKAGE__->register_item(
        name          => 'lj_bio',
        source        => 'livejournal',
        class         => "$prefix\::Bio",
        typeid        => 2,
        depends_on    => ['lj_verify'],
        display_order => 10,
        event_noun    => 'bio has',
    );
    __PACKAGE__->register_item(
        name          => 'lj_tags',
        source        => 'livejournal',
        class         => "$prefix\::Tags",
        typeid        => 1,
        depends_on    => ['lj_verify'],
        display_order => 60,
        event_noun    => 'tags have',
    );
    __PACKAGE__->register_item(
        name          => 'lj_friendgroups',
        source        => 'livejournal',
        class         => "$prefix\::FriendGroups",
        typeid        => 5,
        depends_on    => ['lj_verify'],
        comm_okay     => 0,
        display_order => 30,
        event_noun    => 'friend groups have',
    );
    __PACKAGE__->register_item(
        name          => 'lj_friends',
        source        => 'livejournal',
        class         => "$prefix\::Friends",
        typeid        => 4,
        depends_on    => ['lj_friendgroups'],
        implies       => ['lj_friendgroups'],
        comm_okay     => 0,
        display_order => 20,
        event_noun    => 'friends have',
    );

    # communities have no friend groups, so their entries wait for tags instead
    __PACKAGE__->register_item(
        name   => 'lj_entries',
        source => 'livejournal',
        class  => "$prefix\::Entries",
        typeid => 0,
        depends_on => { person => ['lj_friendgroups'], community => ['lj_tags'] },
        implies    => [ 'lj_tags',                     'lj_friendgroups' ],
        suboptions    => ['lj_entries_remap_icon'],
        queue         => 'heavy',
        display_order => 40,
        event_noun    => 'entries have',
        reports_posts => 1,
    );
    __PACKAGE__->register_item(
        name          => 'lj_comments',
        source        => 'livejournal',
        class         => "$prefix\::Comments",
        typeid        => 3,
        depends_on    => ['lj_entries'],
        implies       => ['lj_entries'],
        queue         => 'heavy',
        display_order => 50,
        event_noun    => 'comments have',
    );
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
