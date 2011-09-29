# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Test qw(temp_user memcache_stress);
use LJ::UniqCookie;

sub run_tests {
    my $class = "LJ::UniqCookie";
    my $get_uniq = sub {
        $class->generate_uniq_ident;
    };

    # tell LJ::UniqCookie how to generate unixtimes for uniqmap rows
    my $time_ct = time()-30;
    $LJ::_T_UNIQCOOKIE_MODTIME_CB = sub {
        return $time_ct++;
    };

    # don't lazy clean until we're ready to explicitly test it
    $LJ::_T_UNIQCOOKIE_LAZY_CLEAN_PCT = -1;

    { # one uniq, one user
        my $u = temp_user();
        my $uniq = $get_uniq->();
        ok($class->save_mapping($uniq => $u), "saved mapping");
        
        my $uid = $class->load_mapping( uniq => $uniq );
        ok($uid == $u->id, "loaded by uniq");
        
        my $new_uniq = $class->load_mapping( user => $u );
        ok($new_uniq eq $uniq, "loaded by u ser");
        
        $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = $uniq;
        my $g_remote = $class->guess_remote;
        ok( $u->equals( $g_remote ), "guessed correct remote" );
    }
    
    { # multiple uniqs, same user
        
        my $u = temp_user();
        
        my @added_uniqs;
        foreach (1..5) {
            my $uniq = $get_uniq->();
            $class->save_mapping($uniq => $u);
            push @added_uniqs, $uniq;
        }
        
        my @got_uniqs = $class->load_mapping( user => $u );
        ok(eq_set(\@added_uniqs, \@got_uniqs), "got multiple uniqs for a user");
    }
    
    { # multiple users, same uniq
        
        my $uniq = $get_uniq->();
        
        my @userids;
        foreach (1..5) {
            my $u = temp_user();
            
            $class->save_mapping($uniq => $u);
            push @userids, $u->id;
        }
        
        my @got_userids = $class->load_mapping( uniq => $uniq );
        ok(eq_set(\@got_userids, \@userids), "got multiple users for a uniq");
    }
    
    { # multiple uniqs, multiple users
        my $u = temp_user();
        my $u2 = temp_user();
        
        my @uniq_added;
        my @uniq_added_u2;
        foreach (1..5) {
            my $uniq = $get_uniq->();
            
            $class->save_mapping($uniq => $u);
            push @uniq_added, $uniq;
            
            if (rand() > 0.5) {
                $class->save_mapping($uniq => $u2);
                push @uniq_added_u2, $uniq;
            }
        }
        
        my @uniq_list = $class->load_mapping( user => $u );
        ok(eq_set(\@uniq_added, \@uniq_list), "saved some uniqs, got the same back");
        
        my @uniq_list2 = $class->load_mapping( user => $u2 );
        ok(eq_set(\@uniq_added, \@uniq_list), "saved uniqs to another user, got the same back");
    }
    
    # set up a delete callback which will tell us the number
    # of rows deleted in the last cleaning operation
    
    my $last_delete_ct = 0;
    $LJ::_T_UNIQCOOKIE_DELETE_CB = sub {
        my ($type, $ct) = @_;
        $last_delete_ct = $ct;
    };
    
    { # cleaning per-user
        
        my $u = temp_user();
        
        my @added_uniqs;
        foreach (1..25) {
            my $uniq = $get_uniq->();
            $class->save_mapping($uniq => $u);
            push @added_uniqs, $uniq;
        }
        
        my @got_uniqs = $class->load_mapping( user => $u );
        my @added_trim = (reverse @added_uniqs)[0..9];
        ok(eq_set(\@added_trim, \@got_uniqs), "cleaned multiple uniqs for a user");
        
        ok($last_delete_ct == 15, "deleted correct number of rows by user");
        
        # shouldn't clean this time around
        LJ::DB::no_cache( sub {
            $class->clear_request_cache;
            $class->load_mapping( user => $u );
        } );
        
        ok($last_delete_ct == 0, "loaded by user without redundant cleaning");
        
    }
    
    { # cleaning per-uniq
        
        my $uniq = $get_uniq->();
        
        my @userids;
        foreach (1..25) {
            my $u = temp_user();
            
            $class->save_mapping($uniq => $u);
            push @userids, $u->id;
        }
        
        my @got_userids = $class->load_mapping( uniq => $uniq );
        my @userids_trim = (reverse @userids)[0..9];
        ok(eq_set(\@userids_trim, \@got_userids), "cleaned multiple users for a uniq");
        ok($last_delete_ct == 15, "deleted correct number of rows by uniq");
        
        # shouldn't clean this time around
        LJ::DB::no_cache( sub {
            $class->clear_request_cache;
            $class->load_mapping( uniq => $uniq );
        } );
        
        ok($last_delete_ct == 0, "loaded by uniq without redundant cleaning");
    }
    
    { # lazy cleaning

        my $u = temp_user();

        my $dirty = 0;
        $last_delete_ct = 0; # reset this
        foreach (1..25) {
            my $uniq = $get_uniq->();

            $class->save_mapping($uniq, $u);

            # ... but there should be 0 rows deleted
            $dirty = 1 if $last_delete_ct > 0;
        }
        ok(! $dirty, "lazy cleaning rand-false case works");

        # ready to test this, let's set it on now
        $LJ::_T_UNIQCOOKIE_LAZY_CLEAN_PCT = 1.00;

        my $uniq = $get_uniq->();
        $class->save_mapping($uniq, $u);

        ok($last_delete_ct > 0, "lazy cleaning rand-true case works");
    }
}

memcache_stress {
    run_tests();
};
