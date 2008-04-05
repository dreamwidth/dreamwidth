package LJ::Portal::Box::RandomUser; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "RandomUser";
our $_box_description = "See a random user's journal (May contain offensive content)";
our $_box_name = "Random User";

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    my $try = 5;
    my $tries = 0;

    my $done = 0;
    while (!$done && $tries < $try) {
        $tries++;

        my $user = LJ::User->load_random_user();
        next unless $user;

        # get most recent post
        my @items = LJ::get_recent_items({
                'remote' => $u,
                'userid' => $user->{'userid'},
                'clusterid' => $user->{'clusterid'},
                'skip' => 0,
                'itemshow' => 1,
            });

        my $entryinfo = $items[0];
        next unless $entryinfo;

        my $entry;

        if ($entryinfo->{'ditemid'}) {
            $entry = LJ::Entry->new($user,
                                    ditemid => $entryinfo->{'ditemid'});
        } elsif ($entryinfo->{'itemid'} && $entryinfo->{'anum'}) {
            $entry = LJ::Entry->new($user,
                                    jitemid => $entryinfo->{'itemid'},
                                    anum    => $entryinfo->{'anum'});
        } else {
            next;
        }

        next unless $entry;

        my $subject    = $entry->subject_html;
        my $entrylink  = $entry->url;
        my $event      = $entry->event_html( { 'cuturl' => $entrylink  } );
        my $posteru    = $entry->poster;
        my $poster     = $posteru->ljuser_display;
        my $journalid  = $entryinfo->{journalid};
        my $posterid   = $entry->posterid;

        $content .= qq {
            $poster:<br/>
                $event
        };
        $done = 1;
    }

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub can_refresh { 1; }

1;
