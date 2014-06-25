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

package LJ::ParseFeed;
use strict;

use DW::XML::RSS;
use DW::XML::Parser;


# <LJFUNC>
# name: LJ::ParseFeed::parse_feed
# des: Parses an RSS/Atom feed.
# class:
# args: content, type?
# des-content: Feed content.
# des-type: Optional; can be "atom" or "rss".
#           If type isn't supplied, the function will try to guess it
#           based on contents.
# info: items - An arrayref of item hashes, in the same order they were
#       in the feed.
#       Each item contains: link - URL of the item; id - unique identifier (optional);
#        text - text of the item; subject - subject;
#        time - in format 'yyyy-mm-dd hh:mm' (optional).
# returns: Three arguments: $feed, $error, arrayref of items.
#          $feed, which is a hash with the following keys:
#          type - 'atom' or 'rss'; version - version of the feed in its
#          standard; link - URL of the feed; title - title of the feed;
#           description - description of the feed.
#           The second argument returned is $error, which, if defined, is a
#           human-readable error string. The third argument is an
#           arrayref of items, same as $feed->{'items'}.
# </LJFUNC>
sub parse_feed
{
    my ($content, $type) = @_;
    my ($feed, $items, $error);
    my $parser;

    # is it RSS or Atom?
    # Atom feeds are rare for now, so prefer to err in favor of RSS
    # simple heuristic: Atom feeds will have '<feed' somewhere
    # TODO: maybe store the feed's type on creation in a userprop and not guess here

    if ( (defined $type && $type eq 'atom') || $content =~ m!\<feed!) {
        # try treating it as an atom feed
        $parser = new DW::XML::Parser( Style => 'Stream',
                                   Namespaces => 1,
                                   Pkg => 'LJ::ParseFeed::Atom' );
        return ("", "failed to create XML parser") unless $parser;
        eval {
            $parser->parse($content);
        };
        if ($@) {
            $error = "XML parser error: $@";
        } else {
            ($feed, $items, $error) = LJ::ParseFeed::Atom::results();
        };
    
        if ($feed || $type eq 'atom') {
            # there was a top-level <feed> there, or we're forced to treat
            # as an Atom feed, so even if $error is set,
            # don't try RSS
            $feed->{'type'} = 'atom';
            return ($feed, $error, $items);
        }
    }

    # try parsing it as RSS
    $parser = new DW::XML::RSS;
    return ("", "failed to create RSS parser") unless $parser;

    # custom LJ/DW namespaces
    $parser->add_module( prefix => 'nslj',
                         uri => 'http://www.livejournal.org/rss/lj/1.0/' );
    $parser->add_module( prefix => 'atom',
                         uri => 'http://www.w3.org/2005/Atom' );

    eval {
        $parser->parse($content);
    };
    if ($@) {
        $error = "RSS parser error: $@";
        return ("", $error);
    }

    $feed = {};
    $feed->{'type'} = 'rss';
    $feed->{'version'} = $parser->{'version'};

    foreach (qw (link title description)) {
        $feed->{$_} = $parser->{'channel'}->{$_}
            if $parser->{'channel'}->{$_};
    }
    $feed->{'atom:id'} = $parser->{channel}->{atom}->{id} if defined $parser->{channel}->{atom};
    
    $feed->{'items'} = [];

    foreach(@{$parser->{'items'}}) {
        my $item = {};
        $item->{'subject'} = $_->{'title'};
        $item->{'text'} = $_->{'description'};
        $item->{'link'} = $_->{'link'} if $_->{'link'};
        $item->{'id'} = $_->{'guid'} if $_->{'guid'};

        my $nsenc = 'http://purl.org/rss/1.0/modules/content/';
        if ($_->{$nsenc} && ref($_->{$nsenc}) eq "HASH") {
            # prefer content:encoded if present
            $item->{'text'} = $_->{$nsenc}->{'encoded'}
                if defined $_->{$nsenc}->{'encoded'};
        }

        my ( $time, $author );
        $time = time822_to_time( $_->{pubDate} ) if $_->{pubDate};
        $author = $_->{nslj}->{poster}
            if $_->{nslj} && ref $_->{nslj} eq "HASH";

        # Dublin Core
        if ( $_->{dc} && ref $_->{dc} eq "HASH" ) {
            $author = $_->{dc}->{creator} if $_->{dc}->{creator};
            $time = w3cdtf_to_time( $_->{dc}->{date} ) if $_->{dc}->{date};
        }

        $item->{time} = $time if $time;
        $item->{author} = $author if $author;
        push @{ $feed->{items} }, $item;
    }

    return ($feed, undef, $feed->{'items'});
}

# convert rfc822-time in RSS's <pubDate> to our time
# see http://www.faqs.org/rfcs/rfc822.html
# RFC822 specifies 2 digits for year, and RSS2.0 refers to RFC822,
# but real RSS2.0 feeds apparently use 4 digits.
sub time822_to_time {
    my $t822 = shift;
    # remove day name if present
    $t822 =~ s/^\s*\w+\s*,//;
    # remove whitespace
    $t822 =~ s/^\s*//;
    # break it up
    if ($t822 =~ m!(\d?\d)\s+(\w+)\s+(\d\d\d\d)\s+(\d?\d):(\d\d)!) {
        my ($day, $mon, $year, $hour, $min) = ($1,$2,$3,$4,$5);
        $day = "0" . $day if length($day) == 1;
        $hour = "0" . $hour if length($hour) == 1;
        $mon = {'Jan'=>'01', 'Feb'=>'02', 'Mar'=>'03', 'Apr'=>'04',
                'May'=>'05', 'Jun'=>'06', 'Jul'=>'07', 'Aug'=>'08',
                'Sep'=>'09', 'Oct'=>'10', 'Nov'=>'11', 'Dec'=>'12'}->{$mon};
        return undef unless $mon;
        return "$year-$mon-$day $hour:$min";
    } else {
        return undef;
    }
}

# convert W3C-DTF to our internal format
# see http://www.w3.org/TR/NOTE-datetime
# Based very loosely on code from DateTime::Format::W3CDTF,
# which isn't stable yet so we can't use it directly.
sub w3cdtf_to_time {
    my $tw3 = shift;

    # TODO: Should somehow return the timezone offset
    #   so that it can stored... but we don't do timezones
    #   yet anyway. For now, just strip the timezone
    #   portion if it is present, along with the decimal
    #   fractions of a second.
    
    $tw3 =~ s/(?:\.\d+)?(?:[+-]\d{1,2}:\d{1,2}|Z)$//;
    $tw3 =~ s/^\s*//; $tw3 =~ s/\s*$//; # Eat any superflous whitespace

    # We can only use complete times, so anything which
    # doesn't feature the time part is considered invalid.
    
    # This is working around clients that don't implement W3C-DTF
    # correctly, and only send single digit values in the dates.
    # 2004-4-8T16:9:4Z vs 2004-04-08T16:09:44Z
    # If it's more messed up than that, reject it outright.
    $tw3 =~ /^(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$/
        or return undef;

    my %pd; # parsed date
    $pd{Y} = $1; $pd{M} = $2; $pd{D} = $3;
    $pd{h} = $4; $pd{m} = $5; $pd{s} = $6;

    # force double digits
    foreach (qw/ M D h m s /) {
        next unless defined $pd{$_};
        $pd{$_} = sprintf "%02d", $pd{$_};
    }

    return $pd{s} ? "$pd{Y}-$pd{M}-$pd{D} $pd{h}:$pd{m}:$pd{s}" :
                    "$pd{Y}-$pd{M}-$pd{D} $pd{h}:$pd{m}";
}

package LJ::ParseFeed::Atom;

our ($feed, $item, $data);
our ($ddepth, $dholder); # for accumulating;
our @items;
our $error;

sub err {
    $error = shift unless $error;
}

sub results {
    return ($feed, \@items, $error);
}

# $name under which we'll store accumulated data may be different
# from $tag which causes us to store it
# $name may be a scalarref pointing to where we should store
# swallowing is achieved by calling startaccum('');

sub startaccum {
    my $name = shift;

    return err("Tag found under neither <feed> nor <entry>")
        unless $feed || $item;
    $data = ""; # defining $data triggers accumulation
    $ddepth = 1;

    if ( $name ) {
        # if $name is a scalarref, it's actually our $dholder
        if ( ref $name eq 'SCALAR' ) {
            $dholder = $name;
        } else {
            $dholder = $item ? \$item->{$name} : \$feed->{$name};
        }
    } else {
        $dholder = undef;  # no $name
    }
    return;
}

sub swallow {
    return startaccum('');
}

sub StartDocument {
    ($feed, $item, $data) = (undef, undef, undef);
    @items = ();
    undef $error;
}

sub StartTag {
    # $_ carries the unparsed tag
    my ($p, $tag) = @_;
    my $holder;

    # do nothing if there has been an error
    return if $error;

    # are we just accumulating data?
    if (defined $data) {
        $data .= $_;
        $ddepth++;
        return;
    }

    # where we'll usually store info
    $holder = $item ? $item : $feed;

    TAGS: {
        if ($tag eq 'feed') {
            return err("Nested <feed> tags") 
                if $feed;
            $feed = {};
            $feed->{'standard'} = 'atom';
            $feed->{'version'} = $_{'version'};
            return err("Incompatible version specified in <feed>")
                if $feed->{'version'} && $feed->{'version'} < 0.3;
            last TAGS;
        }
        if ($tag eq 'entry') {
            return err("Nested <entry> tags") 
                if $item;
            $item = {};
            last TAGS;
        }
        
        # at this point, we must have a top-level <feed> or <entry>
        # to write into
        return err("Tag found under neither <feed> nor <entry>")
            unless $holder;

        if ($tag eq 'link') {
            # store 'self' and 'hub' rels, for PubSubHubbub support; but only valid
            # for the feed, so make sure $item is undef
            if ( ! $item && $_{rel} && ( $_{rel} eq 'self' || $_{rel} eq 'hub' ) ) {
                return err( 'Feed not yet defined' )
                    unless $feed;

                # allow these to be specified multiple times, the spec allows for multiple
                # hubs.  the self link shouldn't allow multiples but it won't hurt if we let it.
                push @{$feed->{$_{rel}} ||= []}, $_{href};
                last TAGS;
            }

            # ignore links with rel= anything but alternate
            # and treat links as rel=alternate if not explicit
            unless (!$_{'rel'} || $_{'rel'} eq 'alternate') {
                swallow();
                last TAGS;
            }

            # if multiple alternates are specified, prefer the one
            # that doesn't have a type of text/plain.
            # see also t/parsefeed-atom-link2.t
            if ( $holder->{link} && $_{type} && $_{type} eq 'text/plain' ) {
                swallow();
                last TAGS;
            }

            $holder->{'link'} = $_{'href'};
            return err("No href attribute in <link>")
                unless $holder->{'link'};
            last TAGS;
        }

        if ($tag eq 'content') {
            return err("<content> outside <entry>")
                unless $item;
            # if type is multipart/alternative, we continue recursing
            # otherwise we accumulate
            my $type = $_{'type'} || "text/plain";
            unless ($type eq "multipart/alternative") {
                push @{$item->{'contents'}}, [$type, ""];
                startaccum(\$item->{'contents'}->[-1]->[1]);
                last TAGS;
            }
            # it's multipart/alternative, so recurse, but don't swallow
            last TAGS;
        }

        # we want to store the value of the nested <name> element
        # in the author slot, not accumulate the raw value -
        # use temp key "inauth" to detect the nesting

        if ( $tag eq 'author' ) {
            $holder->{inauth} = 1;
            last TAGS;
        }

        if ( $tag eq 'name' ) {
            if ( $holder->{inauth} ) {
                startaccum( 'author' );
            } else {
                swallow();
            }
            last TAGS;
        }

        if ( $tag eq 'poster' ) {
            $holder->{ljposter} = $_{user};
            return err( "No user attribute in <$tag>" )
                unless $holder->{ljposter};
            last TAGS;
        }

        # store tags which should require no further
        # processing as they are, and others under _atom_*, to be processed
        # in EndTag under </entry>
        if ($tag eq 'title') {
            if ($item) { # entry's subject
                startaccum("subject");
            } else { # feed's title
                startaccum($tag);
            }
            last TAGS;
        }
        if ($tag eq 'atom:id' || $tag eq 'id') {
            startaccum($tag);
            last TAGS;
        }

        if ($tag eq 'tagline' && !$item) { # feed's tagline, our "description"
            startaccum("description");
            last TAGS;
        }

        # accumulate and store
        startaccum("_atom_" . $tag);
        last TAGS;
    }
            
    return;
}

sub EndTag {
    # $_ carries the unparsed tag
    my ($p, $tag) = @_;

    # do nothing if there has been an error
    return if $error;

    # are we accumulating data?
    if (defined $data) {
        $ddepth--;
        if ($ddepth == 0) { # stop accumulating
            $$dholder = $data
                if $dholder;
            undef $data;
            return;
        }
        $data .= $_;
        return;
    }

    TAGS: {
        if ($tag eq 'entry') {
            # finalize item...
            # generate suitable text from $item->{'contents'}
            my $content;
            $item->{'contents'} ||= [];
            unless (scalar(@{$item->{'contents'}}) >= 1) {
                # this item had no <content>
                # maybe it has <summary>? if so, use <summary>
                # TODO: type= or encoding issues here? perhaps unite
                # handling of <summary> with that of <content>?
                if ($item->{'_atom_summary'}) {
                    $item->{'text'} = $item->{'_atom_summary'};
                    delete $item->{'contents'};
                } else {
                    # nothing to display, so ignore this entry
                    undef $item;
                    last TAGS;
                }
            }

            unless ($item->{'text'}) { # unless we already have text
                if (scalar(@{$item->{'contents'}}) == 1) {
                    # only one <content> section
                    $content = $item->{'contents'}->[0]; 
                } else {
                    # several <content> section, must choose the best one
                    foreach (@{$item->{'contents'}}) {
                        if ($_->[0] eq "application/xhtml+xml") { # best match
                            $content = $_;
                            last; # don't bother to look at others
                        }
                        if ($_->[0] =~ m!html!) { # some kind of html/xhtml/html+xml, etc.
                            # choose this unless we've already chosen some html
                            $content = $_
                                unless $content->[0] =~ m!html!;
                            next;
                        }
                        if ($_->[0] eq "text/plain") {
                            # choose this unless we have some html already
                            $content = $_
                                unless $content->[0] =~ m!html!;
                            next;
                        }
                    }
                    # if we didn't choose anything, pick the first one
                    $content =  $item->{'contents'}->[0]
                        unless $content;
                }

                # we ignore the 'mode' attribute of <content>. If it's "xml", we've
                # stringified it by accumulation; if it's "escaped", our parser
                # unescaped it
                # TODO: handle mode=base64?

                $item->{'text'} = $content->[1];
                delete $item->{'contents'};
            }

            # generate time
            my $w3time = $item->{'_atom_created'} || $item->{'_atom_published'} ||
                         $item->{'_atom_modified'} || $item->{'_atom_updated'};

            my $time;
            if ($w3time) {
                # see http://www.w3.org/TR/NOTE-datetime for format
                # we insist on having granularity up to a minute,
                # and ignore finer data as well as the timezone, for now
                if ($w3time =~ m!^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d)!) {
                    $time = "$1-$2-$3 $4:$5";
                }
            }
            $item->{time} = $time if $time;

            # if we found ljposter, use that as preferred author
            $item->{author} = $item->{ljposter} if defined $item->{ljposter};
            delete $item->{ljposter};

            # get rid of all other tags we don't need anymore
            foreach ( keys %$item ) {
                delete $item->{$_} if substr($_, 0, 6) eq '_atom_';
            }
            
            push @items, $item;
            undef $item;
            last TAGS;
        }

        if ( $tag eq 'author' ) {
            my $holder = $item ? $item : $feed;
            delete $holder->{inauth};
            last TAGS;
        }

        if ($tag eq 'feed') {
            # finalize feed

            # if feed author exists, all items should default to it
            if ( defined $feed->{author} ) {
                $_->{author} ||= $feed->{author} foreach @items;
            }

            # get rid of all other tags we don't need anymore
            foreach ( keys %$feed ) {
                delete $feed->{$_} if substr($_, 0, 6) eq '_atom_';
            }
            
            # link the feed with its itms
            $feed->{'items'} = \@items 
                if $feed;
            last TAGS;
        }
    }
    return;
}

sub Text {
    my $p = shift;

    # do nothing if there has been an error
    return if $error;

    $data .= $_ if defined $data;
}

sub PI {
    # ignore processing instructions
    return;
}

sub EndDocument {
    # if we parsed a feed, link items to it
    $feed->{'items'} = \@items 
        if $feed;
    return;
}


1;
