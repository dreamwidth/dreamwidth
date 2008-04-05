package LJ::Portal::Box::FAQ; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = "Frequently asked questions";
our $_box_name = "FAQs";
our $_box_class = "FAQ";

our $_prop_keys = {
    'show_top_ten' => 1,
    'show_faq_of_day' => 2,
};

our $_config_props = {
    'show_top_ten' => {
        'type'      => 'checkbox',
        'desc'      => 'Display the top ten frequently asked questions',
        'default'   => 1,
    },
    'show_faq_of_day' => {
        'type'      => 'checkbox',
        'desc'      => 'Display FAQ of the day',
        'default'   => 1,
    },
};

sub generate_content {
    my $self = shift;
    my $pboxid = $self->{'pboxid'};
    my $u = $self->{'u'};
    my $content;

    my $showtopten = $self->get_prop('show_top_ten');
    my $showFOD = $self->get_prop('show_faq_of_day');

    my $dbr = LJ::get_db_reader();
    return "Could not load DB reader." unless $dbr;

    if ($showtopten) {
        my $sth = $dbr->prepare("SELECT f.faqid, f.question, s.statval AS 'uses' ".
                                "FROM faq f, stats s WHERE f.faqcat<>'int-abuse' ".
                                "AND f.faqcat<>'' AND s.statcat='pop_faq' ".
                                "AND s.statkey=f.faqid ORDER BY s.statval DESC LIMIT 10");
        $sth->execute;

        $content .= qq {
            <b>Most popular FAQs:</b>
            <ul>
            };

        while (my $f = $sth->fetchrow_hashref)
        {
            my $q = LJ::ehtml($f->{'question'});
            $q =~ s/^\s+//; $q =~ s/\s+$//;
            $q =~ s/\n/<BR>/g;
            $content .= "<li><a href=\"/support/faqbrowse.bml?faqid=$f->{'faqid'}\">$q</a> <i>($f->{'uses'})</i></li>\n";
        }
        $content .= "</ul>\n";
    }

    if ($showFOD) {
        # pick a random FAQ.
        my $sth = $dbr->prepare( qq {
            SELECT faqid, question, faqcat FROM faq f WHERE f.faqcat<>'int-abuse' AND f.faqcat<>''
            } );
        $sth->execute;

        my $faqs = $sth->fetchall_arrayref;
        return 'Could not load FAQs' unless $faqs;

        my $randfaqindex = int(rand(scalar @$faqs));
        my $randfaq = $faqs->[$randfaqindex];
        my $faqid = $randfaq->[0];
        my $question = $randfaq->[1];

        $content .= qq {
            <b>FAQ of the Day:</b>
            <ul>
                <li>
                <a href="/support/faqbrowse.bml?faqid=$faqid">$question</a>
                </li>
            </ul>
        };
    }

    my $currlang = BML::get_language()|| $LJ::DEFAULT_LANG;

    $content .= qq {
            <b>FAQ Search:</b>
            <form action="$LJ::SITEROOT/support/faqsearch.bml" method="GET">
            <input type="hidden" name="lang" value="$currlang" />
            <div style="padding: 5px;">
              } . LJ::html_text({ name => 'q' }) . qq {
                  &nbsp;<input type='submit' value='Search' /><br/>
            </div>
            </form>
        };

    return $content;
}

# caching options
sub cache_global { 0; } # cache per-user
sub cache_time { 60 * 60; } # check etag every hour
sub etag {
    my $self = shift;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    return "$year-$mon-$mday"; # recalculate contents every day (with new random FAQ and stats)
}

#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

1;
