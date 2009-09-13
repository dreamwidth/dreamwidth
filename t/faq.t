# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";

require 'ljlib.pl';
use LJ::Lang;

use LJ::Faq;
use LJ::Test qw(memcache_stress);

plan tests => 60;
#plan skip_all => 'Fix this test! Is there support for Spanish?';

sub run_tests {
    # constructor tests
    {   
        my %skel = 
            ( faqid         => 123,
              question      => 'some question',
              summary       => 'summary info',
              answer        => 'this is the answer',
              faqcat        => 'category',
              lastmoduserid => 456,
              sortorder     => 789,
              lastmodtime   => scalar(gmtime(time)),
              unixmodtime   => time
              );

        {
            my $f = eval { LJ::Faq->new(%skel, lang => 'xx') };
            is($f->lang, $LJ::DEFAULT_LANG, "unknown language code falls back to default");
        }

        foreach my $lang (qw(en)) {

        # FIXME: maybe test for en_DW as well? en = 'English, not site specific'; en_DW = 'English, site specific.'  So, in 'en', it's NOT OK to mention Dreamwidth, or, 'the red Tropospherical scheme', etc. But en_DW can be all about DW itself.

            my $f;

            $f = eval { LJ::Faq->new(%skel, lang => $lang, foo => 'bar') };
            like($@, qr/unknown parameters/, "$lang: superfluous parameter");

            # FIXME: more failure cases
            $skel{lang} = $lang;
            $f = eval { LJ::Faq->new(%skel) };

            # check members
            is_deeply($f, \%skel, "$lang: members set correctly");

            # check accessors
            {
                my $r = {};
                foreach my $meth (keys %skel) {
                    my $el = $meth;
                    $meth =~ s/^(question|summary|answer)$/${1}_raw/;
                    $r->{$el} = $f->$meth;
                }
                is_deeply($r, $f, "$lang: accessors return correctly");

                # FIXME: test for _html accessors
            }

            # check loaders
            {
                my @faqs = LJ::Faq->load_all;
                is_deeply([ map { LJ::Faq->load($_->{faqid}) } @faqs ], \@faqs,
                          "single and multi loaders okay");
            }

            # TODO: loaders by category
        }

        # check multi-lang support
        SKIP: {
            $LJ::_T_FAQ_SUMMARY_OVERRIDE = "la cabra esta bailando en la biblioteca!!!";

            my @all = LJ::Faq->load_all;
            skip "No FAQs in the database", 1 unless @all;
            my $faqid = $all[0]->{faqid};
            
            my $default = LJ::Faq->load($faqid);
            my $es      = LJ::Faq->load($faqid, lang => 'es');
            ok($default && $es->summary_raw ne $default->summary_raw, 
               "multiple languages with different results")
        }

        # has_summary
        foreach my $sum ('', '-') {
            $skel{summary} = $sum;
            my $f = LJ::Faq->new(%skel);
            ok(!$f->has_summary, "${sum}: summary absent:" . $f->summary_raw);
        }
        foreach my $sum (' -', '- ', ' - ', '--', '-foo', 'foo-', '-foo-',
            'f-o-o', 'f--oo', '-f-oo', 'f-oo-', 'foo') {
            $skel{summary} = $sum;
            my $f = LJ::Faq->new(%skel) ;
            ok($f->has_summary, "${sum}: summary present");
        }
    }

    # TODO: render_in_place (needs FAQs in the database)
    # FIXME: more robust tests

}

memcache_stress {
    run_tests();
};

1;
