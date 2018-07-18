#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal
#
# Importer worker for LiveJournal-based sites.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
# The entry and comment fetching code have been copied and modified from jbackup.pl

package DW::Worker::ContentImporter::LiveJournal;

=head1 NAME

DW::Worker::ContentImporter::LiveJournal - Importer worker for LiveJournal-based sites.

=head1 API

=cut

use strict;
use base 'DW::Worker::ContentImporter';

use Carp qw/ croak confess /;
use Encode qw/ encode_utf8 /;
use Storable qw/ thaw /;
use LWP::UserAgent;
use XMLRPC::Lite;
use Digest::MD5 qw/ md5_hex /;
use DW::External::Account;
use DW::RenameToken;

# storage for import related stuff
our %MAPS;

sub keep_exit_status_for { 0 }
sub grab_for { 600 }
sub max_retries { 5 }
sub retry_delay {
    my ( $class, $fails ) = @_;
    return ( 10, 30, 60, 300, 600 )[$fails];
}

=head2 C<< $class->remap_groupmask( $data, $allowmask ) >>

Converts a remote groupmask into a local groupmask.

=cut

sub remap_groupmask {
    my ( $class, $data, $allowmask ) = @_;

    my $newmask = 0;

    unless ( $MAPS{fg_map} ) {
        my $dbh = LJ::get_db_writer()
            or croak 'unable to get global database handle';
        my $row = $dbh->selectrow_array(
            'SELECT groupmap FROM import_data WHERE userid = ? AND import_data_id = ?',
            undef, $data->{userid}, $data->{import_data_id}
        );
        $MAPS{fg_map} = $row ? thaw( $row ) : {};
    }

    # trust/friends hasn't changed bits so just copy that over
    $newmask = 1
        if $allowmask & 1 == 1;

    foreach my $oid ( keys %{$MAPS{fg_map}} ) {
        my $nid = $MAPS{fg_map}->{$oid};
        my $old_bit = ( 2 ** $oid );

        if ( ( $allowmask & $old_bit ) == $old_bit ) {
            $newmask |= ( 2 ** $nid );
        }
    }

    return $newmask;
}

=head2 C<< $class->get_feed_account_from_url( $data, $url, $acct ) >>
=cut

sub get_feed_account_from_url {
    my ( $class, $data, $url, $acct ) = @_;
    return undef unless $acct;

# FIXME: have to do something to pass the errors up
    my $errors = [];

    # canonicalize url
    $url =~ s!^feed://!http://!;  # eg, feed://www.example.com/
    $url =~ s/^feed://;           # eg, feed:http://www.example.com/
    return undef unless $url;

    # check for validity here
    if ( $acct ne '' ) {
        # canonicalize the username
        $acct = LJ::canonical_username( $acct );
        $acct = substr( $acct, 0, 20 );
        return undef unless $acct;

        # since we're creating, let's validate this against the deny list
        # FIXME: probably need to error nicely here, as we're not creating
        # the feed that the user is expecting...
        return undef
            if LJ::User->is_protected_username( $acct );

        # append _feed here, username should be valid by this point.
        $acct .= "_feed";
    }

    # see if it looks like a valid URL
    return undef
        unless $url =~ m!^https?://([^:/]+)(?::(\d+))?!;

    # Try to figure out if this is a local user.
    my ( $hostname, $port ) = ( $1, $2 );
    if ( $hostname =~ /\Q$LJ::DOMAIN\E/i ) {
        # TODO: have to map this.. :(
        # FIXME: why submit a patch that has incomplete code? :|
    }

    # disallow ports (do we ever see this in the wild and care to support it?)
    return undef
        if defined $port;

    # see if we already know about this account
    my $dbh = LJ::get_db_writer();
    my $su = $dbh->selectrow_hashref(
        'SELECT userid FROM syndicated WHERE synurl = ?',
        undef, $url
    );
    return $su->{userid} if $su;

    # we assume that it's safe to create accounts that exist on other services.  if they
    # don't work, we won't care, the syndication system should handle that ok
    my $u = LJ::User->create_syndicated( user => $acct, feedurl => $url );
    return $u->id if $u;

    # failed somehow...
    return undef;
}

=head2 C<< $class->get_remapped_userids( $data, $user ) >>

Remaps a remote user to local userids.

( $access_uid, $read_uid )

=cut

sub get_remapped_userids {
    my ( $class, $data, $user, $log ) = @_;

    $log ||= sub {
        warn @_;
    };

    # some users we can't map, because the process of loading their FOAF data or journal
    # does really weird things (DNS!)
    return ( undef, undef )
        if $user eq 'status';

    return @{ $MAPS{$data->{hostname}}->{$user} }
        if exists $MAPS{$data->{hostname}}->{$user};

    my $dbh = LJ::get_db_writer()
        or return;
    my ( $oid, $fid ) = $dbh->selectrow_array(
        'SELECT identity_userid, feed_userid FROM import_usermap WHERE hostname = ? AND username = ?',
        undef, $data->{hostname}, $user
    );

    unless ( $oid ) {
        $log->( "[$$] Remapping identity userid of $data->{hostname}:$user" );
        $oid = $class->remap_username_friend( $data, $user );
        $log->( "     IDENTITY USERID STILL DOESN'T EXIST" )
            unless $oid;
    }

# FIXME: this is temporarily disabled while we hash out exactly how we want
# this functionality to work.
#    unless ( $fid ) {
#        $log->( "[$$] Remapping feed userid of $data->{hostname}:$user" );
#        $fid = $class->remap_username_feed( $data, $user );
#        $log->( "     FEED USERID STILL DOESN'T EXIST" )
#            unless $fid;
#    }

    $dbh->do( 'REPLACE INTO import_usermap (hostname, username, identity_userid, feed_userid) VALUES (?, ?, ?, ?)',
              undef, $data->{hostname}, $user, $oid, $fid );

    # load this user and determine if they've been claimed. if so, we want to post
    # all content as from the claimant.
    my $ou = LJ::load_userid( $oid );
    if ( defined $ou ) {
        if ( my $cu = $ou->claimed_by ) {
            $oid = $cu->id;
        }
    }

    $MAPS{$data->{hostname}}->{$user} = [ $oid, $fid ];
    return ( $oid, $fid );
}

=head2 C<< $class->remap_username_feed( $data, $username ) >>

Remaps a remote user to a local feed.

=cut

sub remap_username_feed {
    my ( $class, $data, $username ) = @_;

    # canonicalize username and try to return
    $username =~ s/-/_/g;

    # don't allow identity accounts (they're not feeds by default)
    return undef
        if $username =~ m/^ext_/;

    # fall back to getting it from the ATOM data
    my $url = "http://www.$data->{hostname}/~$username/data/atom";
    my $acct = $class->get_feed_account_from_url( $data, $url, $username )
        or return undef;

    return $acct;
}

=head2 C<< $class->remap_username_friend( $data, $username ) >>

Remaps a remote user to a local OpenID user.

=cut

sub remap_username_friend {
    my ( $class, $data, $username ) = @_;

    # canonicalize username, in case they gave us a URL version, convert it to
    # the one we know sites use
    $username =~ s/-/_/g;

    if ( $username =~ m/^ext_/ ) {
        my $ua = LJ::get_useragent(
            role     => 'userpic',
            max_size => 524288, #half meg, this should be plenty
            timeout  => 20,
        );

        my $r = $ua->get( "http://$data->{hostname}/tools/opml.bml?user=$username" );
        my $response = $r->content;

        my $url;
        $url = $1 if $response =~ m!<ownerName>(.+?)</ownerName>!;

        # fall back onto ext_1234.import-site.com, in case we don't have an ownername
        # (external account on LJ that's not openid -- e..g., Google+)
        unless ( $url ) {
            $username =~ s/_/-/g; # URL domains have dashes.
            $url = "http://$username.$data->{hostname}/";
        }

        $url = "http://$url/"
            unless $url =~ m/^https?:/;

        if ( $url =~ m!http://(.+)\.$LJ::DOMAIN\/$! ) {
            # this appears to be a local user!
            # Map this to the local userid in feed_map too, as this is a local user.
            if ( my $u = LJ::User->new_from_url( $url ) ) {
                return $u->id;
            }

            # so the OpenID had to return to a valid DW user at some point, this probably
            # means the user renamed
            my $username = LJ::User->username_from_url( $url );
            if ( defined $username ) {
                my $tokens = DW::RenameToken->by_username( user => $username );
                return undef
                    unless defined $tokens && ref $tokens eq 'ARRAY';
                foreach my $token ( @$tokens ) {
                    if ( $token->fromuser eq $username ) {
                        my $u = LJ::load_user( $token->touser );
                        return $u if defined $u;

                        # it is technically possible for there to be a second rename and
                        # there to be a chain of renames, but wow. die for now.
                        confess "$username was renamed but new name not found, renamed again?";
                    }
                }
            }

            # failed to map this user to something local, make anonymous; we don't want to
            # fall through to creating an OpenID account because then we'll have an OpenID
            # account for an OpenID account, yo dawg
            return undef;
        }

        my $iu = LJ::User::load_identity_user( 'O', $url, undef )
            or return undef;
        return $iu->id;

    } else {
        my $url_prefix = "http://$data->{hostname}/~" . $username;
        my ( $foaf_items ) = $class->get_foaf_from( $url_prefix );

        # if we get an empty hashref, we know that the foaf data failed
        # to load.  probably because the account is suspended or something.
        # in that case, we pretend.
        my $ident =
            exists $foaf_items->{identity} ? $foaf_items->{identity}->{url} : undef;
        $username =~ s/_/-/g; # URL domains have dashes.
        $ident ||= "http://$username.$data->{hostname}/";

        # build the identity account (or return it if it exists)
        my $iu = LJ::User::load_identity_user( 'O', $ident, undef )
            or return undef;
        return $iu->id;
    }

    return undef;
}

=head2 C<< $class->remap_lj_user( $data, $event ) >>

Remaps lj user tags to point to the remote site.

=cut

sub remap_lj_user {
    my ( $class, $data, $event ) = @_;
    $event =~ s/(<lj[^>]+?(user|comm|syn)=["']?(.+?)["' ]?(?:\s*\/\s*)?>)/<user site="$data->{hostname}" $2="$3">/gi;
    return $event;
}

=head2 C<< $class->get_lj_session( $opts ) >>

Returns a LJ session cookie.

=cut

sub get_lj_session {
    my ( $class, $imp ) = @_;

    my $r = $class->call_xmlrpc( $imp, 'sessiongenerate', { expiration => 'short' } );
    return undef
        unless $r && ! $r->{fault};

    return $r->{ljsession};
}

=head2 C<< $class->get_xpost_map( $user, $hashref ) >>

Returns a hashref mapping jitemids to crossposted entries.

=cut

sub get_xpost_map {
    my ( $class, $u, $data ) = @_;

    # see if the account we're importing from is configured to crosspost
    my $acct = $class->find_matching_acct( $u, $data );
    return {} unless $acct;

    # connect to the database and ready the sql
    my $p = LJ::get_prop( log => 'xpost' )
        or croak 'unable to get xpost logprop';
    my $dbcr = LJ::get_cluster_reader( $u )
        or croak 'unable to get user cluster reader';
    my $sth = $dbcr->prepare( "SELECT jitemid, value FROM logprop2 WHERE journalid = ? AND propid = ?" )
        or croak 'unable to prepare statement';

    # now look up the values we need
    $sth->execute( $u->id, $p->{id} );
    croak 'database error: ' . $sth->errstr
        if $sth->err;

    # ( remote jitemid => local ditemid )
    my %map;

    # put together the mapping above
    while ( my ( $jitemid, $value ) = $sth->fetchrow_array ) {
        # decompose the xposter data
        my $data = DW::External::Account->xpost_string_to_hash( $value );
        my $xpost = $data->{$acct->acctid}
            or next;

        # this item was crossposted, record it
        $map{$xpost} = $jitemid;
    }

    return \%map;
}

=head2 C<< $class->find_matching_acct( $u, $data ) >>

Finds the External Account ID, if this user is set up to xpost.

=cut

sub find_matching_acct {
    my ( $class, $u, $data ) = @_;

    my @accts = DW::External::Account->get_external_accounts($u);

    my $dh = lc( $data->{hostname} );
    $dh =~ s/^www\.//;

    my $duser = lc( $data->{username} );
    $duser =~ s/-/_/g;


    foreach my $acct (@accts) {
        my $sh = lc( $acct->serverhost );
        $sh =~ s/^www\.//;

        my $suser = lc( $acct->username );
        $suser =~ s/-/_/g;

        next unless $sh eq $dh;
        next unless $suser eq $duser;
        return $acct;
    }

    return undef;
}

sub xmlrpc_call_helper {
    # helper function that makes life easier on folks that call xmlrpc stuff.  this handles
    # running the actual request and checking for errors, as well as handling the cases where
    # we hit a problem and need to do something about it.  (abort or retry.)
    my ( $class, $opts, $xmlrpc, $method, $req, $mode, $hash, $depth ) = @_;

    # bail if depth is 4, obviously something is going terribly wrong
    if ( $depth >= 4 ) {
        return
            {
                fault => 1,
                faultString => 'Failed to connect to the server too many times.',
            };
    }

    # call out
    my $res;
    eval { $res = $xmlrpc->call($method, $req); };
    if ( $res && $res->fault ) {
        return
            {
                fault => 1,
                faultString => $res->fault->{faultString} || 'Unknown error.',
            };
    }

    # Typically this is timeouts; but since we probably need a new challenge we have to
    # call the call_xmlrpc method to do the retry. However, if we're actually trying to
    # get a challenge we should call ourselves.
    unless ( $res ) {
        if ( $method eq 'LJ.XMLRPC.getchallenge' ) {
            return $class->xmlrpc_call_helper( $opts, $xmlrpc, $method, $req, $mode, $hash, $depth+1 );
        } else {
            return $class->call_xmlrpc( $opts, $mode, $hash, $depth+1 );
        }
    }

    return $res->result;
}

=head2 C<< $class->call_xmlrpc( $opts, $mode, $hash ) >>

Call XMLRPC request.

=cut

sub call_xmlrpc {
    # also a way to help people do xmlrpc stuff easily.  this method actually does the
    # challenge response stuff so we never send the user's password or md5 digest over
    # the internet.
    my ( $class, $opts, $mode, $hash, $depth ) = @_;

    my $xmlrpc = XMLRPC::Lite->new;
    $xmlrpc->proxy( "http://" . ( $opts->{server} || $opts->{hostname} ) . "/interface/xmlrpc",
                    agent => "$LJ::SITENAME Content Importer ($LJ::ADMIN_EMAIL)" );

    my $chal;
    while ( ! $chal ) {
        my $res = $class->xmlrpc_call_helper(
                $opts, $xmlrpc, 'LJ.XMLRPC.getchallenge', undef, undef, undef, $depth );
        if ( $res && $res->{fault} ) {
            return $res;
        }
        $chal = $res->{challenge};
    }

    my $response = md5_hex( $chal . ( $opts->{md5password} || $opts->{password_md5} || md5_hex( $opts->{password} ) ) );

    # we have to do this like this so that we don't send the argument if it's not valid
    my %usejournal;
    $usejournal{usejournal} = $opts->{usejournal} if $opts->{usejournal};

    my $res = $class->xmlrpc_call_helper( $opts, $xmlrpc, "LJ.XMLRPC.$mode", {
        username       => $opts->{user} || $opts->{username},
        auth_method    => 'challenge',
        auth_challenge => $chal,
        auth_response  => $response,
        %usejournal,
        %{ $hash || {} },
    }, $mode, $hash, $depth );

    return $res;
}

=head2 C<< $class->get_foaf_from( $url ) >>

Get FOAF data.

Returns ( \%items, \@interests, \@schools ).

=cut

sub get_foaf_from {
    my ( $class, $url ) = @_;

    my %items;
    my @interests;
    my $in_tag;
    my @schools;
    my %wanted_text_items = (
        'foaf:name' => 'name',
        'foaf:icqChatID' => 'icq',
        'foaf:jabberID' => 'jabber',
        'foaf:yahooChatID' => 'yahoo',
        'ya:bio' => 'bio',
        'lj:journaltitle' => 'journaltitle',
        'lj:journalsubtitle' => 'journalsubtitle',
    );
    my %wanted_attrib_items = (
        'foaf:homepage' => { _tag => 'homepage', 'rdf:resource' => 'url', 'dc:title' => 'title'  },
        'foaf:openid' => { _tag => 'identity', 'rdf:resource' => 'url' },
    );
    my $foaf_handler = sub {
        my $tag = $_[1];
        shift; shift;
        my %temp = ( @_ );
        if ( $tag eq 'foaf:interest' ) {
            push @interests, encode_utf8( $temp{'dc:title'} || "" );
        } elsif ( $tag eq 'ya:school' ) {
            my ( $ctc, $sc, $cc, $sid ) = $temp{'rdf:resource'} =~ m/\?ctc=(.+?)&sc=(.+?)&cc=(.+?)&sid=([0-9]+)/;
            push @schools, {
                start => encode_utf8( $temp{'ya:dateStart'} || "" ),
                finish => encode_utf8( $temp{'ya:dateFinish'} || "" ),
                title => encode_utf8( $temp{'dc:title'} || "" ),
                ctc => encode_utf8( $ctc || "" ),
                sc => encode_utf8( $sc || "" ),
                cc => encode_utf8( $cc || "" ),
            };
        } elsif ( $wanted_attrib_items{$tag} ) {
            my $item = $wanted_attrib_items{$tag};
            my %hash;
            foreach my $key ( keys %$item ) {
                next if $key eq '_tag';
                $hash{$item->{$key}} = encode_utf8( $temp{$key} || "" );
            }
            $items{$item->{_tag}} = \%hash;
        } else {
            $in_tag = $tag;
        }
    };
    my $foaf_content = sub {
        my $text = $_[1];
        $text =~ s/\n//g;
        $text =~ s/^ +$//g;
        if ( $wanted_text_items{$in_tag} ) {
            $items{$wanted_text_items{$in_tag}} .= $text;
        }
    };
    my $foaf_closer = sub {
        my $tag = $_[1];
        if ( $wanted_text_items{$in_tag} ) {
            $items{$wanted_text_items{$in_tag}} = encode_utf8( $items{$wanted_text_items{$in_tag}} || "" );
        }
        $in_tag = undef;
    };

    my $ua = LJ::get_useragent(
                               role     => 'userpic',
                               max_size => 524288, #half meg, this should be plenty
                               timeout  => 10,
                               );

    my $r = $ua->get( "$url/data/foaf" );
    return undef unless ( $r && $r->is_success );

    my $parser = new XML::Parser( Handlers => { Start => $foaf_handler, Char => $foaf_content, End => $foaf_closer } );

    # work around a bug in the schools system that can lead to malformed wide characters
    # getting put into the feed, breaking XML::Parser.  we just strip out all of the school
    # entries.  if we ever need that data, we'll have to figure out how to fix the problem
    # in a more sane fashion...
    my $content = $r->content;
    $content =~ s!<ya:school.+</foaf:Person>!</foaf:Person>!s;

    eval {
        $parser->parse( $content );
    };
    if ($@) {
        # the person above us already knows how to handle blank results,
        # so this is best effort. fail.
        return undef;
    }

    return ( \%items, \@interests, \@schools );
}

sub start_log {
    my ( $class, $import_type, %opts ) = @_;

    my $userid = $opts{userid};
    my $import_data_id = $opts{import_data_id};

    my $logfile;

    mkdir "$LJ::HOME/logs/imports";
    mkdir "$LJ::HOME/logs/imports/$userid";
    open $logfile, ">>$LJ::HOME/logs/imports/$userid/$import_data_id.$import_type.$$"
        or return undef;
    print $logfile "[0.00s 0.00s] Log started at " . LJ::mysql_time(undef, 1) . ".\n";

    return $logfile;
}

=head1 AUTHORS

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
