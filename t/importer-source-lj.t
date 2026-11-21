# t/importer-source-lj.t
#
# Tests the LiveJournal source adapter against a canned site: it turns what the
# remote sends into normalized records, walks the comment export's windows, and
# reports failures as outcomes. Nothing here touches the network or the database.
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

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use HTTP::Response;

use DW::Importer::Source::LiveJournal;

# the remote: canned answers, and a record of what it was asked
{

    package Test::Site;

    sub new { my ( $class, %args ) = @_; return bless { asked => [], pages => {}, %args }, $class }

    sub xmlrpc {
        my ( $self, $mode, $hash ) = @_;
        push @{ $self->{asked} }, [ $mode, $hash ];
        my $answer = $self->{xmlrpc}->{$mode};
        return ref $answer eq 'CODE' ? $answer->($hash) : $answer;
    }

    sub get {
        my ( $self, $url ) = @_;
        push @{ $self->{asked} }, [ 'get', $url ];
        my $body = $self->{pages}->{$url};
        return HTTP::Response->new( 404, 'Not Found' ) unless defined $body;
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content($body);
        return $r;
    }

    sub comment_export {
        my ( $self, $mode, $startid, $numitems ) = @_;
        push @{ $self->{asked} }, [ $mode, $startid, $numitems ];
        my $answer = $self->{export}->{$mode};
        return ref $answer eq 'CODE' ? $answer->( $startid, $numitems ) : $answer;
    }
}

sub source {
    my ( $site, %data ) = @_;
    return DW::Importer::Source::LiveJournal->new(
        data      => { hostname => 'remote.example', username => 'someone', %data },
        transport => $site,
    );
}

# the outcome a call dies with
sub outcome_of {
    my ($code) = @_;
    eval { $code->(); 1 } and return undef;
    return $@;
}

# small windows, so that a handful of comments needs several
local $DW::Importer::Source::LiveJournal::FETCH_META = 3;
local $DW::Importer::Source::LiveJournal::FETCH_BODY = 2;

# account checks ---------------------------------------------------------------------------
{
    my $site = Test::Site->new( xmlrpc => { getusertags => { tags => [] } } );
    ok( source($site)->login_check, 'a good login passes' );

    $site = Test::Site->new(
        xmlrpc => { getusertags => { fault => 1, faultString => 'Invalid password' } } );
    my $out = outcome_of( sub { source($site)->login_check } );
    is( $out->status, 'fail', 'a rejected password is permanent' );
    like(
        $out->message,
        qr/^Username or password for someone rejected by remote\.example\.$/,
        'and says whose'
    );

    $site = Test::Site->new(
        xmlrpc => { getusertags => { fault => 1, faultString => 'Server busy' } } );
    $out = outcome_of( sub { source($site)->login_check } );
    is( $out->status, 'temp_fail', 'any other failure is temporary' );
    is( $out->message, 'XMLRPC failure: Server busy', 'with the site\'s message' );

    $site = Test::Site->new( xmlrpc => { getusertags => undef } );
    is(
        outcome_of( sub { source($site)->login_check } )->message,
        'XMLRPC failure: ',
        'no answer at all is temporary too'
    ) if 0;
    is( outcome_of( sub { source($site)->login_check } )->status,
        'temp_fail', 'no answer at all is temporary too' );

    my $admin = sub {
        my ($answer) = @_;
        my $s = Test::Site->new( xmlrpc => { consolecommand => $answer } );
        return ( $s,
            outcome_of( sub { source( $s, usejournal => 'thecomm' )->community_admin_check } ) );
    };
    my ( $s, $o ) = $admin->( { results => [ { output => [ ['success'] ] } ] } );
    ok( !$o, 'a community admin passes' );
    is_deeply(
        $s->{asked}->[0]->[1],
        { commands => ['ban_unset someone from thecomm'] },
        'by trying to unban the owner'
    );
    ( $s, $o ) = $admin->( { results => [ { output => [ ['error'] ] } ] } );
    is( $o->status, 'fail', 'anyone else fails for good' );
    like(
        $o->message,
        qr/not an administrator\/maintainer of the remote community named thecomm/,
        'and is told why'
    );
    ( $s, $o ) = $admin->( { fault => 1, faultString => 'nope' } );
    like(
        $o->message,
        qr/^XMLRPC failure: nope \(community: thecomm\)$/,
        'a failure of the call is temporary, naming the community'
    );
}

# small lists ------------------------------------------------------------------------------
{
    my $site = Test::Site->new(
        xmlrpc => {
            getusertags => { tags => [ { name => 'travel', display => 1 } ] },
            getfriends  => {
                friendgroups => [ { id => 1, name => 'Family', sortorder => 10, public => 0 } ],
                friends => [ { username => 'pal', groupmask => 3 } ],
            },
        }
    );
    my $s = source($site);
    is_deeply( [ $s->tags ], [ { name => 'travel', display => 1 } ], 'tags' );
    is( ( $s->trust_groups )[0]->{name}, 'Family', 'trust groups' );
    is( ( $s->friends )[0]->{username},  'pal',    'friends' );
    is_deeply(
        $site->{asked}->[1]->[1],
        { includegroups => 1 },
        'the groups are asked for with the friends'
    );

    $site = Test::Site->new( xmlrpc => { getusertags => { fault => 1, faultString => 'Boom' } } );
    my $out = outcome_of( sub { source( $site, usejournal => 'thecomm' )->tags } );
    is( $out->status, 'temp_fail', 'a fault is temporary' );
    is(
        $out->message,
        'XMLRPC failure: Boom (community: thecomm)',
        'and names the community when there is one'
    );
}

# bio and userpics ----------------------------------------------------------------------------
{
    my $foaf = q{<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:ya="http://blogs.yandex.ru/schema/foaf/">
<foaf:Person><foaf:name>Some One</foaf:name><ya:bio>About me</ya:bio><foaf:interest dc:title="knitting"/><foaf:interest dc:title="cats"/>
<foaf:homepage rdf:resource="http://home.example/" dc:title="Home"/></foaf:Person></rdf:RDF>};
    my $site = Test::Site->new( pages => { 'http://some-one.remote.example/data/foaf' => $foaf } );
    my $bio  = source( $site, username => 'some_one' )->bio;
    is( $bio->{bio}, 'About me', 'the bio' );
    is_deeply( $bio->{interests}, [ 'knitting', 'cats' ], 'its interests' );
    is_deeply( $bio->{homepage}, { url => 'http://home.example/', title => 'Home' },
        'and homepage' );
    is(
        $site->{asked}->[0]->[1],
        'http://some-one.remote.example/data/foaf',
        'asked for a journal named with dashes'
    );

    is( source( Test::Site->new, username => 'nobody' )->bio,
        undef, 'a profile that can\'t be loaded is no bio' );

    my $atom = q{<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><id>urn:lj:remote.example:atom1:someone:100</id><title>default userpic</title><summary>Smiling</summary><category term="happy"/><content src="http://p.example/1.png"/></entry>
<entry><id>urn:lj:remote.example:atom1:someone:101</id><title>other</title><category term="sad"/><category term="blue"/><content src="http://p.example/2.png"/></entry>
</feed>};
    $site = Test::Site->new(
        pages => { 'http://remote.example/users/someone/data/userpics' => $atom } );
    my ( $default, @pics ) = source($site)->userpics;
    is( scalar @pics,   2,        'both icons are listed' );
    is( $default->{id}, 100,      'the default is the one the site calls that' );
    is( $pics[0],       $default, 'and is the same record as in the list' );
    is_deeply( [ map { $_->{id} } @pics ], [ 100, 101 ], 'with their ids' );
    is_deeply( $pics[1]->{keywords}, [ 'sad', 'blue' ], 'keywords' );
    is( $pics[1]->{src}, 'http://p.example/2.png', 'and where to get the picture' );
    is( $pics[0]->{comment}, 'Smiling', 'and comments' );

    my $out = outcome_of( sub { source( Test::Site->new )->userpics } );
    is( $out->status, 'temp_fail', 'a missing list is temporary' );
    like( $out->message, qr/^Could not import icons for someone: Failed retrieving page \(404/,
        'and says why' );
}

# entries --------------------------------------------------------------------------------------
{
    my @events = (
        { itemid => 5, anum => 3, props => {} },
        { itemid => 9, anum => 1, props => { opt_backdated => 1 } },
        { itemid => 7, anum => 2, props => {} },
    );
    my $site = Test::Site->new( xmlrpc => { getevents => { events => \@events } } );
    my ( $max, $count ) = source($site)->newest_entry_id;
    is( $max,   7, 'the newest entry is the highest that is not backdated' );
    is( $count, 3, 'and all that came back are counted' );
    is( $site->{asked}->[0]->[1]->{selecttype}, 'lastn', 'asked for the newest' );

    $site = Test::Site->new( xmlrpc =>
            { getevents => { events => [ { itemid => 1, props => { opt_backdated => 1 } } ] } } );
    ( $max, $count ) = source($site)->newest_entry_id;
    ok( !$max, 'with only backdated entries there is no newest' );
    is( $count, 1, 'but there were entries' );

    $site = Test::Site->new( xmlrpc => { getevents => { foo => 1 } } );
    is(
        outcome_of( sub { source($site)->newest_entry_id } )->message,
        'Failed to fetch the most recent entry.',
        'no list of entries is temporary'
    );

    $site = Test::Site->new(
        xmlrpc => {
            getevents => {
                events => [
                    {
                        itemid   => 1,
                        anum     => 7,
                        subject  => 's',
                        event    => 'e',
                        security => 'public',
                        props    => {}
                    },
                    {
                        itemid    => 2,
                        anum      => 9,
                        subject   => 't',
                        event     => 'f',
                        security  => 'usemask',
                        allowmask => 3,
                        props     => {}
                    },
                ]
            }
        }
    );
    my @entries = source($site)->entries( 1, 2 );
    is_deeply(
        [ map { $_->{key} } @entries ],
        [ 'remote.example/someone/263', 'remote.example/someone/521' ],
        'entries are keyed by site, user and remote id'
    );
    is_deeply( [ map { $_->{remote_id} } @entries ], [ 1, 2 ], 'and carry their remote ids' );
    is( $site->{asked}->[0]->[1]->{itemids}, '1,2,', 'the ids are asked for as a list' );

    @entries = source( $site, usejournal => 'thecomm' )->entries(1);
    like( $entries[0]->{key},
        qr{^remote\.example/thecomm/}, 'a community import keys by the community' );
    is( $site->{asked}->[1]->[1]->{usejournal} // 'none',
        'none', 'which the transport adds to the request, not the adapter' );
}

# identity ------------------------------------------------------------------------------------
{
    my $site = Test::Site->new(
        pages => {
            'http://remote.example/~foafuser/data/foaf' =>
q{<rdf:RDF xmlns:rdf="r" xmlns:foaf="f"><foaf:Person><foaf:openid rdf:resource="http://foafuser.remote.example/"/></foaf:Person></rdf:RDF>},
            'http://remote.example/tools/opml.bml?user=ext_5' =>
                q{<opml><head><ownerName>someone.example.org/blog</ownerName></head></opml>},
        }
    );
    my $s = source($site);
    is_deeply(
        $s->identity_for('foafuser'),
        { openid => 'http://foafuser.remote.example/' },
        'a normal user is their FOAF identity'
    );
    is_deeply(
        $s->identity_for('under-score'),
        { openid => 'http://under-score.remote.example/' },
        'or guessed from the name, dashes for underscores'
    );
    is_deeply(
        $s->identity_for('ext_5'),
        { openid => 'http://someone.example.org/blog/' },
        'an ext_ user is their OPML owner'
    );
    is_deeply(
        $s->identity_for('ext_6'),
        { openid => 'http://ext-6.remote.example/' },
        'or ext-N.site'
    );
}

# comment export ----------------------------------------------------------------------------------

# a metadata window: ids first..last, posters from usermap, the server's max and optionally where to go on
sub meta_window {
    my (%o) = @_;
    my $xml = qq{<?xml version="1.0" encoding="utf-8"?>\n<livejournal>\n};
    $xml .= "<maxid>$o{max}</maxid>\n"    if defined $o{max};
    $xml .= "<nextid>$o{next}</nextid>\n" if defined $o{next};
    $xml .= "<comments>\n";
    $xml .= qq{<comment id="$_" posterid="$o{poster}" state="@{[ $o{state}{$_} // 'A' ]}"/>\n}
        foreach $o{first} .. $o{last};
    $xml .= "</comments>\n<usermaps>\n";
    $xml .= qq{<usermap id="$_->[0]" user="$_->[1]"/>\n} foreach @{ $o{users} || [] };
    return $xml . "</usermaps>\n</livejournal>";
}

{
    my %windows = (
        1 => meta_window(
            first  => 1,
            last   => 3,
            max    => 7,
            next   => 4,
            poster => 10,
            users  => [ [ 10, 'alice' ], [ 11, 'ext_9' ] ],
            state  => { 2 => 'S' }
        ),
        4 => meta_window(
            first  => 4,
            last   => 6,
            max    => 7,
            next   => 7,
            poster => 11,
            users  => [ [ 11, 'ext_9' ], [ 12, 'bob' ] ]
        ),
        7 => meta_window( first => 7, last => 7, max => 7, poster => 0 ),
    );
    my $site = Test::Site->new(
        export => {
            comment_meta => sub { $windows{ $_[0] } }
        }
    );

    my ( @before, @after );
    my $meta = source($site)->comment_meta(
        before_window => sub { push @before, $_[0] },
        after_window  => sub { push @after, [ $_[0], $_[1] ] },
    );
    is( $meta->{max_id}, 7, 'the highest comment id' );
    is_deeply( [ sort { $a <=> $b } keys %{ $meta->{comments} } ], [ 1 .. 7 ], 'all the comments' );
    is( $meta->{comments}->{2}->{state},    'S', 'with their states' );
    is( $meta->{comments}->{1}->{state},    'A', 'defaulting to active' );
    is( $meta->{comments}->{5}->{posterid}, 11,  'and posters' );
    is_deeply( $meta->{usermap}, { 10 => 'alice', 11 => 'ext_9', 12 => 'bob' },
        'the poster names' );
    is_deeply( \@before, [ 1, 4, 7 ], 'the windows start where the site said to go on' );
    is_deeply(
        $after[0],
        [ 7, [ [ 10, 'alice' ], [ 11, 'ext_9' ] ] ],
        'each window reports the posters it listed, in order'
    );
    is_deeply( $after[1]->[1], [ [ 12, 'bob' ] ], 'and only new ones' );
    is_deeply(
        [ map { $_->[2] } grep { $_->[0] eq 'comment_meta' } @{ $site->{asked} } ],
        [ (3) x 3 ],
        'asking for a window at a time'
    );

    # an old site sends no <nextid>: carry on after the highest id seen
    %windows = (
        1 => meta_window(
            first  => 1,
            last   => 3,
            max    => 5,
            poster => 10,
            users  => [ [ 10, 'alice' ] ]
        ),
        4 => meta_window( first => 4, last => 5, poster => 10 ),
    );
    $site = Test::Site->new(
        export => {
            comment_meta => sub { $windows{ $_[0] } }
        }
    );
    @before = ();
    $meta   = source($site)->comment_meta( before_window => sub { push @before, $_[0] } );
    is_deeply( \@before, [ 1, 4 ], 'without nextid the next window starts after the highest id' );
    is( scalar keys %{ $meta->{comments} }, 5, 'and nothing is missed' );

    # a window that can't be fetched stops the import to be tried again
    $site = Test::Site->new(
        export => {
            comment_meta => sub { $_[0] == 1 ? $windows{1} : undef }
        }
    );
    my $out = outcome_of( sub { source($site)->comment_meta } );
    is( $out->status, 'temp_fail', 'a missing window is temporary' );
    is( $out->message, 'Error fetching comment metadata from server.', 'and says what failed' );

    # callbacks can stop it
    $site = Test::Site->new(
        export => {
            comment_meta => sub { $windows{ $_[0] } }
        }
    );
    my $stop = outcome_of(
        sub {
            source($site)
                ->comment_meta( after_window => sub { die DW::Importer::Outcome->fail('too many') }
                );
        }
    );
    is( $stop->message, 'too many', 'a callback can stop the import' );
    is( scalar( () = grep { $_->[0] eq 'comment_meta' } @{ $site->{asked} } ),
        1, 'before more is fetched' );
}

for my $case (
    [ 'empty first metadata window',  1, undef ],
    [ 'empty middle metadata window', 0, undef ],
    [ 'fractional metadata cursor',   1, '1.5' ],
    [ 'malformed metadata cursor',    1, '7oops' ],
    [ 'non-ASCII metadata cursor',    1, '7&#x0662;' ],
    [ 'equal metadata cursor',        0, 4 ],
    [ 'backward metadata cursor',     0, 2 ],
    )
{
    my ( $name, $first_window_empty, $cursor ) = @$case;
    subtest $name => sub {
        my $empty   = meta_window( first => 1, last => 0, max => 7, next => $cursor );
        my %windows = (
            1 => $first_window_empty
            ? $empty
            : meta_window( first => 1, last => 3, max => 7, poster => 0 ),
            4 => $empty,
            7 => meta_window( first => 7, last => 7, max => 7, poster => 0 ),
        );
        my $site = Test::Site->new(
            export => {
                comment_meta => sub { delete $windows{ $_[0] } }
            }
        );

        my $meta;
        my $outcome = outcome_of( sub { $meta = source($site)->comment_meta } );
        is( $outcome, undef, 'an empty window does not stop the import' );
        is_deeply(
            [ map { $_->[1] } @{ $site->{asked} } ],
            [ 1, 4, 7 ],
            'each window is requested once'
        );
        is_deeply(
            [ sort { $a <=> $b } keys %{ $meta->{comments} // {} } ],
            $first_window_empty ? [7] : [ 1, 2, 3, 7 ],
            'later comments are still found'
        );
    };
}

for my $tag (qw( nextid maxid )) {
    subtest "duplicate metadata $tag" => sub {
        my %windows = (
            1 => meta_window(
                first  => 1,
                last   => 1,
                max    => '1&#54;',
                next   => '1&#52;',
                poster => 0
            ),
            14 => meta_window( first => 16, last => 16, poster => 0 ),
        );
        $windows{1} =~ s{(<$tag>[^<]+</$tag>)}{$1$1};
        my $site = Test::Site->new(
            export => {
                comment_meta => sub { delete $windows{ $_[0] } }
            }
        );

        my $meta;
        my $outcome = outcome_of( sub { $meta = source($site)->comment_meta } );
        is( $outcome, undef, 'the metadata import succeeds' );
        is_deeply(
            [ map { $_->[1] } @{ $site->{asked} } ],
            [ 1, 14 ],
            'only the two expected windows are requested'
        );
        is( $meta->{max_id}, 16, 'the maximum is kept as one element value' );
        is_deeply(
            [ sort keys %{ $meta->{comments} // {} } ],
            [ 1, 16 ],
            'the duplicate does not skip the later comment'
        );
    };
}

subtest 'metadata encoding retry' => sub {
    my %windows = (
        1 => meta_window(
            first  => 1,
            last   => 2,
            max    => 4,
            next   => 4,
            poster => 10,
            users  => [ [ 10, 'alice' ], [ 11, "caf\xe9" ] ],
        ),
        4 => meta_window( first => 4, last => 4, poster => 11 ),
    );
    my $site = Test::Site->new(
        export => {
            comment_meta => sub { delete $windows{ $_[0] } }
        }
    );

    my @usermap;
    my $meta = source($site)->comment_meta( after_window => sub { push @usermap, @{ $_[1] } } );
    is_deeply( [ map { $_->[1] } @{ $site->{asked} } ], [ 1, 4 ], 'the cursor survives retry' );
    is_deeply( [ sort keys %{ $meta->{comments} } ], [ 1, 2, 4 ],
        'later comments are still found' );
    is_deeply( \@usermap, [ [ 10, 'alice' ], [ 11, "caf\x{e9}" ] ], 'each user is reported once' );
};

subtest 'unparseable metadata window' => sub {
    my %windows = (
        1 => meta_window( first => 1, last => 3, max => 7, poster => 0 ),
        4 => qq{<?xml version="1.0" encoding="utf-8"?><livejournal><usermap id="10" user="alice"/>},
        7 => meta_window( first => 7, last => 7, poster => 0 ),
    );
    my $site = Test::Site->new(
        export => {
            comment_meta => sub { delete $windows{ $_[0] } }
        }
    );

    my @after;
    my $outcome;
    {
        local $SIG{__WARN__} = sub { };
        $outcome = outcome_of(
            sub {
                source($site)->comment_meta( after_window => sub { push @after, [@_] } );
            }
        );
    }
    is( ref $outcome eq 'DW::Importer::Outcome' ? $outcome->status : $outcome,
        'temp_fail', 'unparseable metadata is a temporary failure' );
    is_deeply( \@after, [ [ 7, [] ] ], 'only the valid window is delivered' );
    is_deeply( [ map { $_->[1] } @{ $site->{asked} } ], [ 1, 4 ], 'no later window is requested' );
};

# bodies
sub body_window {
    my (%o) = @_;
    my $xml = qq{<?xml version="1.0" encoding="utf-8"?>\n<livejournal>\n<comments>\n};
    foreach my $id ( $o{first} .. $o{last} ) {
        my $text = $o{text}->{$id} // "text $id";
        $xml .=
qq{<comment id="$id" jitemid="@{[ $o{entry} // 1 ]}" parentid="@{[ $o{parent}->{$id} // 0 ]}">}
            . "<body>$text</body><subject>subject $id</subject><date>2009-03-06T00:00:0${id}Z</date>"
            . qq{<property name="picture_keyword">kw $id</property></comment>\n};
    }
    $xml .= "</comments>\n";
    $xml .= "<nextid>$o{next}</nextid>\n" if $o{next};
    return $xml . "</livejournal>";
}

{
    my $meta = {
        max_id   => 5,
        comments => {
            map { $_ => { posterid => ( $_ == 3 ? 0 : 10 ), state => ( $_ == 4 ? 'D' : 'A' ) } }
                1 .. 5
        },
        usermap => { 10 => 'alice' },
    };
    my %windows = (
        1 => body_window( first => 1, last => 2 ),
        3 => body_window( first => 3, last => 4, parent => { 4 => 3 } ),
        5 => body_window( first => 5, last => 5, parent => { 5 => 1 } ),
    );
    my $site = Test::Site->new(
        export => {
            comment_body => sub { $windows{ $_[0] } }
        }
    );

    my ( @windows, @before );
    source($site)->comment_bodies(
        max_id        => 5,
        comments      => $meta->{comments},
        usermap       => $meta->{usermap},
        before_window => sub { push @before, $_[0] },
        window        => sub { push @windows, [@_] },
    );
    is_deeply( \@before, [ 1, 3, 5 ], 'windows of the configured size, one after another' );
    is_deeply(
        [
            map {
                [ map { $_->{remote_id} } @$_ ]
            } @windows
        ],
        [ [ 1, 2 ], [ 3, 4 ], [5] ],
        'comments are given a window at a time'
    );

    my ( $one, $three, $four, $five ) =
        ( $windows[0][0], $windows[1][0], $windows[1][1], $windows[2][0] );
    is( $one->{poster},     'alice',                'a comment has its poster\'s name' );
    is( $one->{external},   0,                      'who is not external' );
    is( $three->{poster},   undef,                  'poster 0 is anonymous' );
    is( $four->{state},     'D',                    'states come from the metadata' );
    is( $four->{parent_id}, 3,                      'parents' );
    is( $one->{entry_id},   1,                      'entries' );
    is( $one->{body},       'text 1',               'bodies' );
    is( $one->{subject},    'subject 1',            'subjects' );
    is( $one->{date},       '2009-03-06T00:00:01Z', 'dates' );
    is_deeply( $one->{props}, { picture_keyword => 'kw 1' }, 'and properties' );
    is( $five->{parent_id}, 1, 'a reply to a comment in an earlier window' );

    # a poster named ext_ is flagged
    $meta->{usermap}->{10} = 'ext_77';
    @windows = ();
    source($site)->comment_bodies(
        max_id   => 2,
        comments => $meta->{comments},
        usermap  => $meta->{usermap},
        window   => sub { push @windows, [@_] }
    );
    is( $windows[0][0]->{external}, 1, 'a poster from elsewhere is marked external' );
}

# a server that says where to resume: nothing is skipped
{
    my %windows = (
        1 => body_window( first => 1, last => 1, next => 3 ),  # this window ends early, resume at 3
        3 => body_window( first => 3, last => 4 ),
        5 => body_window( first => 5, last => 5 ),
    );
    my $meta = { map { $_ => { posterid => 0, state => 'A' } } 1 .. 5 };
    my $site = Test::Site->new(
        export => {
            comment_body => sub { $windows{ $_[0] } }
        }
    );

    my ( @before, @ids );
    source($site)->comment_bodies(
        max_id        => 5,
        comments      => $meta,
        usermap       => {},
        before_window => sub { push @before, $_[0] },
        window        => sub {
            push @ids, map { $_->{remote_id} } @_;
        },
    );
    is_deeply( \@before, [ 1, 3, 5 ], 'the next window starts where the site asked' );
    is_deeply( \@ids, [ 1, 3, 4, 5 ], 'and each comment it sent is given' );

    # a window that is missing is temporary
    $site = Test::Site->new(
        export => {
            comment_body => sub { undef }
        }
    );
    my $out = outcome_of(
        sub {
            source($site)->comment_bodies(
                max_id   => 5,
                comments => $meta,
                usermap  => {},
                window   => sub { }
            );
        }
    );
    is(
        $out->message,
        'Error fetching comment body data from server.',
        'a body window that can not be fetched is temporary'
    );

    # a window that overlaps what was given before gives nothing twice
    %windows = (
        1 => body_window( first => 1, last => 2 ),
        3 => body_window( first => 2, last => 3 ),
    );
    $site = Test::Site->new(
        export => {
            comment_body => sub { $windows{ $_[0] } }
        }
    );
    @ids = ();
    source($site)->comment_bodies(
        max_id   => 3,
        comments => $meta,
        usermap  => {},
        window   => sub {
            push @ids, map { $_->{remote_id} } @_;
        }
    );
    is_deeply( \@ids, [ 1, 2, 3 ], 'a comment seen again is not given again' );
}

# LJ claims utf-8 and sometimes sends Latin-1: the adapter tries other encodings, once, without doubling text
{
    my $latin1 = body_window( first => 1, last => 2, text => { 2 => "caf\xe9" } );
    my $site   = Test::Site->new(
        export => {
            comment_body => sub { $_[0] == 1 ? $latin1 : undef }
        }
    );
    my $meta = { 1 => { posterid => 0, state => 'A' }, 2 => { posterid => 0, state => 'A' } };

    my @comments;
    {
        local $SIG{__WARN__} = sub { };
        source($site)->comment_bodies(
            max_id   => 2,
            comments => $meta,
            usermap  => {},
            window   => sub { push @comments, @_ }
        );
    }
    is( scalar @comments,        2,           'both comments are read' );
    is( $comments[0]->{body},    'text 1',    'the first is not repeated' );
    is( $comments[1]->{body},    "caf\x{e9}", 'and the second is decoded as Latin-1' );
    is( $comments[0]->{subject}, 'subject 1', 'nor are its other fields doubled' );
}

done_testing();
