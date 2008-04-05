# -*-perl-*-

use strict;
use Test::More 'no_plan';

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Vertical;
use LJ::Test qw(memcache_stress temp_user);

my $u = temp_user();

# when determining if content should be in verticals, don't look at timecreate, friend of count, or entry count
$LJ::_T_VERTICAL_IGNORE_TIMECREATE = 1;
$LJ::_T_VERTICAL_IGNORE_NUMFRIENDOFS = 1;
$LJ::_T_VERTICAL_IGNORE_NUMENTRIES = 1;
$LJ::_T_VERTICAL_IGNORE_NUMRECEIVEDCOMMENTS = 1;
$LJ::_T_VERTICAL_IGNORE_RATECHECK = 1;
$LJ::_T_VERTICAL_IGNORE_IMAGERESTRICTIONS = 1;

sub gen_name {
    join(":", "t", time(), LJ::rand_chars(20));
}

sub run_tests {

    # constructor tests
    {
        my $v;

        $v = eval { LJ::Vertical->new };
        like($@, qr/wrong number of arguments/, "new: no arguments");

        $v = eval { LJ::Vertical->new( undef ) };
        like($@, qr/wrong number of arguments/, "new: wrong number of arguments");

        $v = eval { LJ::Vertical->new( vertid => undef ) };
        like($@, qr/need to supply/, "new: need to supply vertical id");

        $v = eval { LJ::Vertical->new( vertid => 1, foo => 'bar' ) };
        like($@, qr/unknown parameters/, "new: unknown parameters");

        $v = eval { LJ::Vertical->new( vertid => 1 ) };
        isa_ok($v, "LJ::Vertical", "new: successful instantiation");

        $v = eval { LJ::Vertical->load_by_name("music") };
        isa_ok($v, "LJ::Vertical", "load_by_name: successful instantiation");

        # reset singletons so we don't try to lazily load vertid 1 later
        LJ::Vertical->reset_singletons;
    }

    # creating a vertical
    {
        my $v;

        my $name = gen_name();
        
        $v = eval { LJ::Vertical->create };
        like($@, qr/wrong number of arguments/, "create: no arguments");

        $v = eval { LJ::Vertical->create( undef ) };
        like($@, qr/wrong number of arguments/, "create: wrong number of arguments");

        $v = eval { LJ::Vertical->create( name => undef ) };
        like($@, qr/need to supply/, "create: need to supply vertical name");

        $v = eval { LJ::Vertical->create( name => 'baz', foo => 'bar' ) };
        like($@, qr/unknown parameters/, "create: unknown parameters");

        $v = LJ::Vertical->create( name => $name );
        isa_ok($v, "LJ::Vertical", "create: successful creation");

        my $created_vertid = $v->vertid;
        $v = eval { LJ::Vertical->load_by_id( $created_vertid ) };
        isa_ok($v, "LJ::Vertical", "load_by_id: successful instantiation");

        # reset singletons then load the one we just created
        {
            my $old_vertid = $v->{vertid};
            LJ::Vertical->reset_singletons();

            $v = LJ::Vertical->new( vertid => $old_vertid );
            ok(ref $v && $v->isa("LJ::Vertical") && $v->{vertid} == $old_vertid, "new: successful load");

            $v->delete_and_purge;
            ok (! LJ::MemCache::get([ $old_vertid, "vert:$old_vertid" ]), "delete: deleted vertical from db and memcache" );

            # create by same name and see if we're able to create and load by different id
            $v = eval { LJ::Vertical->create( name => $name ) };
            isa_ok($v, "LJ::Vertical", "create: new vertical created");
            ok($v->{vertid} != $old_vertid, "create: new vertical has different vertid: $v->{vertid}");

            # try some getters / setters
            ok($v->name eq $name, "name matches creation  name");

            { # test name, set_name
                my $new_name = gen_name();
                my $rv = $v->set_name($new_name);
                ok($rv eq $new_name && $v->name eq $new_name, "set new name okay");
            }
            
            { # createtime, set_create_time
                my $old_createtime = $v->createtime;
                ok(time() - $old_createtime < 30, "got original createtime: ");

                my $new_time = time() - 86400;
                $v->set_createtime($new_time);
                ok($v->createtime == $new_time, "new createtime okay");
            }

            # clean up after ourselves
            $v->delete_and_purge;
        }
    }

    # add entries and retrieve them in chunks
    {
        my $v = LJ::Vertical->create( name => gen_name() );

        # post some entries
        my @entry_objs = ();
        foreach (1..10) {
            push @entry_objs, $u->t_post_fake_entry;
        }

        # not the best set of tests, but we'll verify that the various accessor methods yield
        # the same results in the simple case
        my $rv = $v->add_entries(@entry_objs);
        ok($rv, "added entries to LJ::Vertical");

        my @recent_entries = $v->recent_entries; # moves iterator
        ok(@recent_entries > 0 && $v->{_iter_idx} >= @recent_entries, "iterator moved on recent_entries call");
 
        my @entry_chunk    = $v->entries( limit => scalar(@recent_entries) );
        is(scalar @recent_entries, scalar @entry_chunk, "Chunk yielded same as recent_entries");

        # reset iterator
        $v->{_iter_idx} = 0;
        my @entry_list     = map { $v->next_entry } @recent_entries;
        is(scalar @recent_entries, scalar @entry_list, "Repeated next calls yielded same as recent_entries");

        ok($v->next_entry == undef, "No more entries to retrieve");

        # clean up
        $v->delete_and_purge;
    }

    # add entries, mark some invalid, and retrieve them in chunks
    {
        my $v = LJ::Vertical->create( name => gen_name() );

        # post some entries
        my @entry_objs = ();
        my $public_ct = 0;
        foreach (1..50) {

            # 50% will be invalid for verticals
            my $security = 'private';
            if (rand(2) % 2 == 0) {
                $public_ct++;
                $security = 'public';
            }

            unshift @entry_objs, $u->t_post_fake_entry( security => $security );
        }
        $v->add_entries(@entry_objs);

        # call ->next repeatedly until we get undef
        my $got = grep { defined $v->next_entry } @entry_objs;
        ok($got == $public_ct, "got only public");
        ok($v->next_entry == undef, "next entry is undef");
    }

    # test setting, parsing, and retrieval of rules
    {
        my $v = LJ::Vertical->create( name => gen_name() );

        ok(eq_hash($v->rules, { whitelist => [], blacklist => [] }), "rules initialized properly");
        ok(eq_array([ $v->rules_whitelist ], []),  "rules whitelist initialized");
        ok(eq_array([ $v->rules_blacklist ], []),  "rules blacklist initialized");

        my $rv = eval { $v->set_rules({}) };
        ok(! $rv && $@ =~ /invalid/, "can't set bogus hashref");

        $rv = eval { $v->set_rules( whitelist => "5.3 bar") };
        ok(! $rv && $@ =~ /invalid/, "can't set bogus whitelist line");

        $rv = eval { $v->set_rules( whitelist => "0.01 Term::SomeTerm\n0.02 Term::SomeTerm\nLang::EN",
                                    blacklist => "0.30 Term::BadTerm" ) };
        ok($rv && eq_array([ $v->rules_whitelist ], [ [ "0.01", "Term::SomeTerm" ], [ "0.02", "Term::SomeTerm" ], [ undef, "Lang::EN" ] ]),
           "set valid whitelist");
        ok($rv && eq_array([ $v->rules_blacklist ], [ [ "0.30", "Term::BadTerm" ] ]), 
           "set valid blacklist");
    }
}

memcache_stress {
    run_tests();
};

1;

