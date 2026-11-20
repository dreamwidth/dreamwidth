#!/usr/bin/perl
#
# DW::Importer::Source::LiveJournal
#
# Reads a LiveJournal-compatible site and produces normalized import records.
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

package DW::Importer::Source::LiveJournal;

=head1 NAME

DW::Importer::Source::LiveJournal - Source adapter for LiveJournal-compatible sites

=head1 SYNOPSIS

    my $source = DW::Importer::Source::LiveJournal->new(
        data      => $import_data,       # hostname, username, usejournal, ...
        transport => $transport,         # see DW::Importer::Source::LiveJournal::Transport
    );

    my @tags    = $source->tags;
    my @entries = $source->entries(@remote_ids);

=head1 DESCRIPTION

This owns every request to the remote site and turns what comes back into the records
described in L<DW::Importer::Records>. It writes nothing locally. All network access
goes through the transport it is given, so a test can replay a site from canned
responses.

Failures are raised as L<DW::Importer::Outcome> objects (a C<temp_fail>, or a C<fail>
where retrying can't help) for the job to return or rethrow.

=cut

use strict;
use warnings;

# the XML handlers below take what the remote site sends as it comes, undefined values included
no warnings 'uninitialized';

use Carp qw( carp );
use Encode qw( encode_utf8 );

use DW::External::User;
use DW::Importer::Outcome;
use DW::Importer::Source::LiveJournal::Keys qw( entry_key );
use DW::RenameToken;
use DW::XML::Parser;
use XML::Parser;

# how many comments the export is asked for at a time; these come from LJ
our $FETCH_META = 10000;
our $FETCH_BODY = 500;

# if we add more encoding maps, update this!
our @ENCODINGS = ( 'UTF-8', 'ISO-8859-1', 'UTF-16' );

=head2 C<< DW::Importer::Source::LiveJournal->new( data => $data, transport => $transport ) >>

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless {
        data      => $args{data},
        transport => $args{transport}
            || do {
            require DW::Importer::Source::LiveJournal::Transport;
            DW::Importer::Source::LiveJournal::Transport->new( data => $args{data} );
            },
    }, $class;
}

sub data      { $_[0]->{data} }
sub transport { $_[0]->{transport} }

# the community name when importing into one, else the user: the journal entries live in
sub _journal { return $_[0]->{data}->{usejournal} // $_[0]->{data}->{username} }

sub _community_suffix {
    my ($self) = @_;
    return $self->{data}->{usejournal} ? " (community: $self->{data}->{usejournal})" : '';
}

# a remote answer with a fault, or none, is a temporary failure
sub _xmlrpc {
    my ( $self, $mode, $hash, %opts ) = @_;

    my $r = $self->{transport}->xmlrpc( $mode, $hash );
    return $r if $r && !$r->{fault};

    my $msg = 'XMLRPC failure: ' . ( $r ? $r->{faultString} : '[unknown]' );
    $msg .= $self->_community_suffix unless $opts{no_community};
    die DW::Importer::Outcome->temp_fail($msg);
}

=head1 Account

=head2 C<< $source->login_check >>

Checks the credentials with a harmless call. Dies with a C<fail> if the site rejects
the password, a C<temp_fail> for anything else.

=cut

sub login_check {
    my ($self) = @_;

    my $r = $self->{transport}->xmlrpc('getusertags');

    # now, we have to see if the error contains 'Invalid password' or something else
    if ( $r && $r->{fault} && $r->{faultString} =~ /Invalid password/ ) {

        # this is a permanent failure.  if the password is bad, we're not going to ever
        # bother retrying.  that's life.
        die DW::Importer::Outcome->fail(
"Username or password for $self->{data}->{username} rejected by $self->{data}->{hostname}."
        );
    }

    # if we got any other type of failure, call it temporary...
    die DW::Importer::Outcome->temp_fail( 'XMLRPC failure: ' . $r->{faultString} )
        if !$r || $r->{fault};

    return 1;
}

=head2 C<< $source->community_admin_check >>

For a community import: checks that the user administers the remote community. The best
way to tell is to try to unban the owner, which only works for an admin, so this is a
write on the remote site, which a dry run must not do. Dies with a C<fail> if the user
is not an admin.

=cut

sub community_admin_check {
    my ($self) = @_;
    my $data = $self->{data};

    my $r = $self->{transport}->xmlrpc( 'consolecommand',
        { commands => ["ban_unset $data->{username} from $data->{usejournal}"], } );

    my $xmlrpc_fail = 'XMLRPC failure: ' . ( $r ? $r->{faultString} : '[unknown]' );
    $xmlrpc_fail .= " (community: $data->{usejournal})";
    die DW::Importer::Outcome->temp_fail($xmlrpc_fail) if !$r || $r->{fault};
    die DW::Importer::Outcome->fail( 'You are not an administrator/maintainer of the remote'
            . ' community named '
            . $data->{usejournal}
            . '.' )
        unless $r->{results}->[0]->{output}->[0]->[0] eq 'success';

    return 1;
}

=head1 Small things

=head2 C<< $source->tags >>

A list of tag records.

=cut

sub tags {
    my ($self) = @_;
    my $r = $self->_xmlrpc('getusertags');
    return @{ $r->{tags} || [] };
}

sub _getfriends {
    my ( $self, %opts ) = @_;
    return $self->_xmlrpc( 'getfriends', { includegroups => 1 }, %opts );
}

=head2 C<< $source->trust_groups >>

A list of trust group records.

=cut

sub trust_groups {
    my ($self) = @_;
    my $r = $self->_getfriends;
    return @{ $r->{friendgroups} || [] };
}

=head2 C<< $source->friends >>

A list of friend records, as the site gave them.

=cut

sub friends {
    my ($self) = @_;
    my $r = $self->_getfriends( no_community => 1 );
    return @{ $r->{friends} || [] };
}

=head2 C<< $source->bio >>

A bio record from the journal's FOAF data, or undef if it can't be loaded.

=cut

sub bio {
    my ($self) = @_;

    # FIXME: have to flip this back to using the user_path value instead of hardcoded
    # livejournal.com ... this should probably be part of the import_data structure?
    # abstract out sites?
    my $un = $self->_journal;
    $un =~ s/_/-/g;    # URLs use hyphens, not underscores
    my ( $items, $interests ) = $self->foaf("http://$un.$self->{data}->{hostname}");
    return undef unless $items;

    return { %$items, interests => $interests };
}

=head2 C<< $source->foaf( $url ) >>

Gets the FOAF data of the journal at C<$url> (the C</data/foaf> part is added).
Returns C<( \%items, \@interests, \@schools )>, or nothing if it can't be loaded.

=cut

sub foaf {
    my ( $self, $url ) = @_;

    my %items;
    my @interests;
    my $in_tag;
    my @schools;
    my %wanted_text_items = (
        'foaf:name'          => 'name',
        'foaf:jabberID'      => 'jabber',
        'ya:bio'             => 'bio',
        'lj:journaltitle'    => 'journaltitle',
        'lj:journalsubtitle' => 'journalsubtitle',
    );
    my %wanted_attrib_items = (
        'foaf:homepage' => { _tag => 'homepage', 'rdf:resource' => 'url', 'dc:title' => 'title' },
        'foaf:openid'   => { _tag => 'identity', 'rdf:resource' => 'url' },
    );
    my $foaf_handler = sub {
        my $tag = $_[1];
        shift;
        shift;
        my %temp = (@_);
        if ( $tag eq 'foaf:interest' ) {
            push @interests, encode_utf8( $temp{'dc:title'} || "" );
        }
        elsif ( $tag eq 'ya:school' ) {
            my ( $ctc, $sc, $cc, $sid ) =
                $temp{'rdf:resource'} =~ m/\?ctc=(.+?)&sc=(.+?)&cc=(.+?)&sid=([0-9]+)/;
            push @schools,
                {
                start  => encode_utf8( $temp{'ya:dateStart'}  || "" ),
                finish => encode_utf8( $temp{'ya:dateFinish'} || "" ),
                title  => encode_utf8( $temp{'dc:title'}      || "" ),
                ctc    => encode_utf8( $ctc                   || "" ),
                sc     => encode_utf8( $sc                    || "" ),
                cc     => encode_utf8( $cc                    || "" ),
                };
        }
        elsif ( $wanted_attrib_items{$tag} ) {
            my $item = $wanted_attrib_items{$tag};
            my %hash;
            foreach my $key ( keys %$item ) {
                next if $key eq '_tag';
                $hash{ $item->{$key} } = encode_utf8( $temp{$key} || "" );
            }
            $items{ $item->{_tag} } = \%hash;
        }
        else {
            $in_tag = $tag;
        }
    };
    my $foaf_content = sub {
        my $text = $_[1];
        $text =~ s/\n//g;
        $text =~ s/^ +$//g;
        if ( $wanted_text_items{$in_tag} ) {
            $items{ $wanted_text_items{$in_tag} } .= $text;
        }
    };
    my $foaf_closer = sub {
        my $tag = $_[1];
        if ( $wanted_text_items{$in_tag} ) {
            $items{ $wanted_text_items{$in_tag} } =
                encode_utf8( $items{ $wanted_text_items{$in_tag} } || "" );
        }
        $in_tag = undef;
    };

    my $r = $self->{transport}->get(
        "$url/data/foaf",
        role     => 'userpic',
        max_size => 524288,      #half meg, this should be plenty
        timeout  => 10,
    );
    return unless ( $r && $r->is_success );

    my $parser = XML::Parser->new(
        Handlers => { Start => $foaf_handler, Char => $foaf_content, End => $foaf_closer } );

    # work around a bug in the schools system that can lead to malformed wide characters
    # getting put into the feed, breaking XML::Parser.  we just strip out all of the school
    # entries.  if we ever need that data, we'll have to figure out how to fix the problem
    # in a more sane fashion...
    my $content = $r->content;
    $content =~ s!<ya:school.+</foaf:Person>!</foaf:Person>!s;

    eval { $parser->parse($content); };
    if ($@) {

        # the person above us already knows how to handle blank results,
        # so this is best effort. fail.
        return;
    }

    return ( \%items, \@interests, \@schools );
}

=head2 C<< $source->userpics >>

Returns C<( $default, @pics )> of userpic records. Dies with a C<temp_fail> if the list
can't be fetched. Entries for which the site gave a bad id are as it gave them.

=cut

sub userpics {
    my ( $self, $log ) = @_;
    $log ||= sub { undef };

    # FIXME: URL may not be accurate here for all sites
    my $un  = $self->_journal;
    my $url = "http://$self->{data}->{hostname}/users/$un";

    my $uurl = "$url/data/userpics";
    $log->( 'Fetching: %s', $uurl );

    my $resp = $self->{transport}->get(
        $uurl,
        role     => 'userpic',
        max_size => 524288,      # half meg, this should be plenty
        timeout  => 20,          # 20 seconds might need adjusting for slow sites
    );
    unless ( $resp && $resp->is_success ) {
        my $error_message = 'Failed retrieving page (' . $resp->status_line . ').';
        $log->($error_message);
        die DW::Importer::Outcome->temp_fail("Could not import icons for $un: $error_message");
    }

    my $content = $resp->content;

    my ( @upics, $upic, $default_upic, $text_tag );

    my $cleanup_string = sub {

# FIXME: If LJ ever fixes their /data/userpics feed to double-escape, this will cause issues.
# Probably need to figure out a way to detect that a double-escape happened and only fix in that case.
        return LJ::dhtml( encode_utf8( $_[0] || "" ) );
    };

    my $upic_handler = sub {
        my $tag = $_[1];
        shift;
        shift;
        my %temp = (@_);

        if ( $tag eq 'entry' ) {
            $upic = { keywords => [] };
        }
        elsif ( $tag eq 'content' ) {
            $upic->{src} = $temp{src};
        }
        elsif ( $tag eq 'category' ) {

# keywords get triple-escaped
# DW::XML::Parser handles unescaping it once, $cleanup_string second, and then we have to unescape it a third time.
            push @{ $upic->{keywords} }, LJ::dhtml( $cleanup_string->( $temp{term} ) );
        }
        else {
            $text_tag = $tag;
        }
    };

    my $upic_content = sub {
        my $text = $_[1];

        if ( $text_tag eq 'title' && $text eq 'default userpic' ) {
            $default_upic = $upic;
            $upic->{default} = 1;
        }
        elsif ( $text_tag eq 'summary' ) {
            $text =~ s/\n//g;
            $text =~ s/^ +$//g;
            $upic->{comment} .= $text;
        }
        elsif ( $text_tag eq 'id' ) {
            my @parts = split( /:/, $text );
            $upic->{id} = $parts[-1];
            $text_tag = undef;
        }
    };

    my $upic_closer = sub {
        my $tag = $_[1];

        if ( $tag eq 'entry' ) {
            my @keywords = @{ $upic->{keywords} };
            $upic->{keywords} = \@keywords;
            $upic->{comment}  = $cleanup_string->( $upic->{comment} );

            $log->( '    keywords: %s', join( ', ', @keywords ) );

            push @upics, $upic;
        }
    };

    my $parser = DW::XML::Parser->new(
        Handlers => { Start => $upic_handler, Char => $upic_content, End => $upic_closer } );

    $log->('Parsing XML output.');
    $parser->parse($content);

    return ( $default_upic, @upics );
}

=head1 Entries

=head2 C<< $source->newest_entry_id >>

Asks for the newest entries and returns C<( $maxid, $count )>: the highest item id of an
entry that isn't backdated (the first entry may be a sticky one, so the highest on the
list is taken), or undef if there was none, and how many entries the site returned.
Dies with a C<temp_fail> if the site can't be asked.

=cut

sub newest_entry_id {
    my ( $self, $log ) = @_;
    $log ||= sub { undef };

    $log->('Fetching the most recent entry.');
    my $last = $self->_xmlrpc(
        'getevents',
        {
            ver         => 1,
            selecttype  => 'lastn',
            howmany     => 50,
            lineendings => 'unix',
        }
    );

    # we weren't able to get any data. Maybe weren't able to connect to remote server?
    # we want to try again
    die DW::Importer::Outcome->temp_fail('Failed to fetch the most recent entry.')
        unless ref $last->{events} eq 'ARRAY';

    # look for the latest non-DOOO entry
    # first entry may be a sticky entry (can't tell via props)
    #   so we guess by taking the max non-DOOO entry on this list
    my $maxid;
    foreach my $event ( @{ $last->{events} } ) {
        if ( $event->{props}->{opt_backdated} ) {
            $log->( 'Skipping %d -- backdated', $event->{itemid} );
        }
        else {
            $maxid = $event->{itemid} > $maxid ? $event->{itemid} : $maxid;
        }
    }
    $log->( 'Discovered that the maximum jitemid on the remote is %d.', $maxid ) if $maxid;

    return ( $maxid, scalar @{ $last->{events} } );
}

=head2 C<< $source->entries( @remote_ids ) >>

Fetches these entries and returns entry records. Dies with a C<temp_fail> if the site
can't be asked.

=cut

sub entries {
    my ( $self, @ids ) = @_;
    my $data = $self->{data};

    # try to get it from the remote server
    my $hash = $self->_xmlrpc(
        'getevents',
        {
            ver         => 1,
            itemids     => join( ',', @ids ) . ",",
            selecttype  => 'multiple',
            lineendings => 'unix',
        }
    );

    my $user = $self->_journal;
    my @entries;
    foreach my $evt ( @{ $hash->{events} || [] } ) {

        # Key for entry_map. We know the username and the site, so we set this to
        # something that is dependable.
        $evt->{key}       = entry_key( $data->{hostname}, $user, $evt->{itemid}, $evt->{anum} );
        $evt->{remote_id} = $evt->{itemid};

        # We also need to calculate the remote URL for ESN purposes.
        my $ext_u = DW::External::User->new(
            user => $user,
            site => $data->{hostname}
        );

        # Although I don't think this is likely to ever croak,
        # I'm being extra-cautious and using an eval here to
        # make sure this can't interrupt the import process.
        $evt->{url} = eval { $ext_u->site->entry_url( $ext_u, %$evt ) };

        push @entries, $evt;
    }
    return @entries;
}

=head1 Identity

=head2 C<< $source->identity_for( $username ) >>

Works out who a remote user is here, reading what it needs from the remote site. Writes
nothing. Returns one of

    { local_user => $userid }    # the remote user is really one of ours
    { openid     => $url }       # an OpenID identity should stand for them
    undef                        # they can't be mapped

C<$username> is a LiveJournal name; accounts named C<ext_NNN> are OpenID accounts from
elsewhere.

=cut

sub identity_for {
    my ( $self, $username ) = @_;
    my $data = $self->{data};

    # canonicalize username, in case they gave us a URL version, convert it to
    # the one we know sites use
    $username =~ s/-/_/g;

    if ( $username =~ m/^ext_/ ) {
        my $r = $self->{transport}->get(
            "http://$data->{hostname}/tools/opml.bml?user=$username",
            role     => 'userpic',
            max_size => 524288,      #half meg, this should be plenty
            timeout  => 20,
        );
        my $response = $r->content;

        my $url;
        $url = $1 if $response =~ m!<ownerName>(.+?)</ownerName>!;

        # fall back onto ext_1234.import-site.com, in case we don't have an ownername
        # (external account on LJ that's not openid -- e..g., Google+)
        unless ($url) {
            $username =~ s/_/-/g;    # URL domains have dashes.
            $url = "http://$username.$data->{hostname}/";
        }

        $url = "http://$url/"
            unless $url =~ m/^https?:/;

        if ( $url =~ m!http://(.+)\.$LJ::DOMAIN\/$! ) {

            # this appears to be a local user!
            # Map this to the local userid in feed_map too, as this is a local user.
            if ( my $u = LJ::User->new_from_url($url) ) {
                return { local_user => $u->id };
            }

            # so the OpenID had to return to a valid DW user at some point, this probably
            # means the user renamed
            my $username = LJ::User->username_from_url($url);
            if ( defined $username ) {
                my $tokens = DW::RenameToken->by_username( user => $username );
                return undef
                    unless defined $tokens && ref $tokens eq 'ARRAY';
                foreach my $token (@$tokens) {
                    if ( $token->fromuser eq $username ) {
                        my $u = LJ::load_user( $token->touser );
                        return { local_user => $u->id } if defined $u;

                        # it is technically possible for there to be a second rename and
                        # there to be a chain of renames, but wow. die for now.
                        Carp::confess(
                            "$username was renamed but new name not found, renamed again?");
                    }
                }
            }

            # failed to map this user to something local, make anonymous; we don't want to
            # fall through to creating an OpenID account because then we'll have an OpenID
            # account for an OpenID account, yo dawg
            return undef;
        }

        return { openid => $url };
    }

    my $url_prefix = "http://$data->{hostname}/~" . $username;
    my ($foaf_items) = $self->foaf($url_prefix);

    # if we get an empty hashref, we know that the foaf data failed
    # to load.  probably because the account is suspended or something.
    # in that case, we pretend.
    my $ident = exists $foaf_items->{identity} ? $foaf_items->{identity}->{url} : undef;
    $username =~ s/_/-/g;    # URL domains have dashes.
    $ident ||= "http://$username.$data->{hostname}/";

    return { openid => $ident };
}

=head1 Comments

=head2 C<< $source->comment_meta( %opts ) >>

Fetches the comment export's metadata, window by window. Returns

    { max_id => N, comments => { remote id => { posterid => N, state => 'A' } },
      usermap => { remote posterid => username } }

Options are callbacks: C<before_window> is called with the id the next window starts
at, and C<after_window> with C<( $max_id, \@new_usermap )> (pairs of C<[ posterid, username ]>
in the order the window listed them) once a window has been read, and may die to stop.
If the server gives a maximum id but no next id, an empty window advances by the
requested window size. Dies with a C<temp_fail> if a window can't be fetched.

=cut

sub comment_meta {
    my ( $self, %opts ) = @_;
    my $log = $opts{log} || sub { undef };

    my ( %meta, %usermap, $lasttag );
    my ( $server_max_id, $window_last_id );
    my $server_next_id = 1;
    my @window_usermap;

    # setup our parsing function
    my $meta_handler = sub {

        # this sub actually processes incoming meta information
        $lasttag = $_[1];
        shift;
        shift;    # remove the Expat object and tag name
        my %temp = (@_);    # take the rest into our humble hash

        # if we were last getting a comment, start storing the info
        if ( $lasttag eq 'comment' ) {

            # get some data on a comment
            $meta{ $temp{id} } = { posterid => $temp{posterid} + 0, state => $temp{state} || 'A' };

            $window_last_id = $temp{id} if $temp{id} > $window_last_id;

        }
        elsif ( $lasttag eq 'usermap' && !exists $usermap{ $temp{id} } ) {
            $usermap{ $temp{id} } = $temp{user};
            push @window_usermap, [ $temp{id}, $temp{user} ];
        }
    };
    my $meta_closer = sub {

        # we hit a closing tag so we're not in a tag anymore
        $lasttag = '';
    };
    my $meta_content = sub {

        # if we're in a maxid tag, we want to save that value so we know how much further
        # we have to go in downloading meta info
        return undef
            unless $lasttag eq 'maxid'
            || $lasttag eq 'nextid';

        # save these values for later
        $server_max_id  = $_[1] + 0 if $lasttag eq 'maxid';
        $server_next_id = $_[1] + 0 if $lasttag eq 'nextid';
    };

    # hit up the server for metadata
    while (defined $server_next_id
        && $server_next_id =~ /^\d+$/
        && ( !defined $server_max_id || $server_next_id <= $server_max_id ) )
    {
        my $start_id = $server_next_id;
        $opts{before_window}->($start_id) if $opts{before_window};

        $log->( 'Fetching metadata; max_id = %d, next_id = %d.', $server_max_id || 0, $start_id );

        my $content =
            $self->{transport}->comment_export( 'comment_meta', $start_id, $FETCH_META, $log );
        die DW::Importer::Outcome->temp_fail('Error fetching comment metadata from server.')
            unless $content;

        ( $server_next_id, $window_last_id ) = ( undef, $start_id - 1 );
        @window_usermap = ();

        $self->_parse_xml( { Start => $meta_handler, Char => $meta_content, End => $meta_closer },
            $content );

        $opts{after_window}->( $server_max_id, [@window_usermap] ) if $opts{after_window};

        next if defined $server_next_id && $server_next_id > $start_id;

        if ( $window_last_id >= $start_id ) {
            $server_next_id = $window_last_id + 1;
        }
        elsif ( defined $server_max_id ) {
            $server_next_id = $start_id + $FETCH_META;
        }
        else {
            last;
        }
    }
    $log->('Finished fetching metadata.');

    return { max_id => $server_max_id, comments => \%meta, usermap => \%usermap };
}

# This hideous loop is here because LJ lies and claims to return utf-8 when sometimes
# it's actually Latin-1, so we have to brute-force the encodings.
sub _parse_xml {
    my ( $self, $handlers, $content, $reset ) = @_;

    my $parser = DW::XML::Parser->new( Handlers => $handlers );

    eval {
        # try to run with the encoding the XML gives us
        $parser->parse($content);
    } or do {

        # that didn't work, let's force encodings to see if one of them does.
        my $result;
        foreach my $encoding (@ENCODINGS) {
            eval {
                $reset->() if $reset;
                $result = $parser->parse( $content, ProtocolEncoding => $encoding );
            };
            last if $result;
        }

        # if we couldn't parse it with any encoding, just die with the parser error.
        carp "$@" unless $result;
    };
}

=head2 C<< $source->comment_bodies( %opts ) >>

Fetches the comment bodies window by window and calls C<$opts{window}> with a list of
comment records for each, in ascending id order. Each comment is given once. Needs
C<max_id>, C<comments> and C<usermap> as C<comment_meta> returned them. The server may
cut a window short and say where to resume; if it doesn't, and the window moved on by
less than a full window, the next starts a full window on. Options C<before_window> (the
id the window starts at), C<log>. Dies with a C<temp_fail> if a window can't be fetched.

=cut

sub comment_bodies {
    my ( $self, %opts ) = @_;
    my $log     = $opts{log} || sub { undef };
    my $max_id  = $opts{max_id};
    my $meta    = $opts{comments};
    my $usermap = $opts{usermap};

    my ( $lastid, $curid, $lastprop, $body_nextid, @tags, $lasttag ) = ( 0, 0, undef, '' );
    my ( %window, %complete, %given );

    # setup our handlers for body XML info
    my $body_handler = sub {

        # this sub actually processes incoming body information
        $lasttag = $_[1];
        push @tags, $lasttag;
        shift;
        shift;    # remove the Expat object and tag name
        my %temp = (@_);    # take the rest into our humble hash
        if ( $lasttag eq 'comment' ) {

            # get some data on a comment
            $curid  = $temp{id} + 0;
            $lastid = $curid if $curid > $lastid;
            my $comment = $window{$curid} ||= { props => {} };
            $comment->{parent_id} = $temp{parentid} + 0;
            $comment->{entry_id}  = $temp{jitemid} + 0;
        }
        elsif ( $lasttag eq 'property' ) {
            $lastprop = $temp{name};
        }
    };
    my $body_closer = sub {

        # we hit a closing tag so we're not in a tag anymore
        my $tag = pop @tags;
        $lasttag          = $tags[0];
        $lastprop         = undef;
        $complete{$curid} = 1 if $curid;
    };
    my $body_content = sub {

        # A server may cut a body window short and say where to resume (none
        # does today). It would follow </comments>, so check before $curid.
        if ( $lasttag eq 'nextid' ) {
            $body_nextid .= $_[1];
            return;
        }

        # this grabs data inside of comments: body, subject, date, properties
        return unless $curid;

        # have to append to it, because the parser will split on punctuation such as an apostrophe
        # that may or may not be in the data stream, and we won't know until we've already gotten
        # some data
        if ( $lasttag =~ /^(?:body|subject|date)$/ ) {
            $window{$curid}->{$lasttag} .= $_[1];
        }
        elsif ( $lastprop && $lasttag eq 'property' ) {
            $window{$curid}->{props}->{$lastprop} .= $_[1];
        }
    };

    # start looping to fetch all of the comment bodies
    while ( $lastid < $max_id ) {
        $opts{before_window}->( $lastid + 1 ) if $opts{before_window};

        $log->( 'Fetching bodydata; last_id = %d, max_id = %d.', $lastid || 0, $max_id || 0 );

        my ( $reset_lastid, $reset_curid ) = ( $lastid, $curid );
        $body_nextid = '';
        %window      = ();

        my $content =
            $self->{transport}->comment_export( 'comment_body', $lastid + 1, $FETCH_BODY, $log );
        die DW::Importer::Outcome->temp_fail('Error fetching comment body data from server.')
            unless $content;

        $self->_parse_xml(
            { Start => $body_handler, Char => $body_content, End => $body_closer },
            $content,
            sub {

                # reset for another body pass
                ( $lastid, $curid ) = ( $reset_lastid, $reset_curid );
                @tags        = ();
                $body_nextid = '';

                # reset all text so we don't get it double posted
                $log->('Resetting comment bodies of in-flight data.');
                %window = ();
            }
        );

        # We increment lastid during our fetches so we should walk nicely, but
        # if we didn't move at least N comments forward, then increment by
        # that value so we can keep walking. If the server cut the window short
        # and sent <nextid>, resume there instead; jumping ahead would skip comments.
        $log->(
            'lastid = %d, reset_lastid = %d, nextid = %s',
            $lastid, $reset_lastid, $body_nextid || '-'
        );
        if ( $body_nextid =~ /^\d+$/ && $body_nextid > $reset_lastid + 1 ) {
            $lastid = $body_nextid - 1;
        }
        elsif ( $lastid - $reset_lastid < $FETCH_BODY ) {
            $lastid = $reset_lastid + $FETCH_BODY;
        }

        # the comments of this window, each given once
        my @comments;
        foreach my $id ( sort { $a <=> $b } keys %window ) {
            next unless $complete{$id};
            next if $given{$id}++;
            push @comments, $self->_comment_record( $id, $window{$id}, $meta, $usermap );
        }
        $opts{window}->(@comments) if $opts{window};
    }
}

# a comment as the body gave it, with what the metadata knew about its poster
sub _comment_record {
    my ( $self, $id, $body, $meta, $usermap ) = @_;

    my $info     = $meta->{$id} || {};
    my $posterid = $info->{posterid};
    my $poster   = $posterid ? $usermap->{$posterid} : undef;

    return {
        remote_id => $id,
        entry_id  => $body->{entry_id},
        parent_id => $body->{parent_id},
        poster    => $poster,
        external  => ( defined $poster && $poster =~ m/^ext_/ ) ? 1 : 0,
        state     => $info->{state} || 'A',
        subject   => $body->{subject},
        body      => $body->{body},
        date      => $body->{date},
        props     => $body->{props},
    };
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
