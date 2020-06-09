#!/usr/bin/perl
#
# DW::Controller::Admin::FAQ
#
# For adding, organizing, and maintaining FAQs.
# Requires faqadd, faqedit, and/or faqcat privileges.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::FAQ;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use LJ::Faq;

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'faq',
    ml_scope => '/admin/faq/index.tt',
    privs    => [ 'faqadd', 'faqedit', 'faqcat' ]
);

DW::Routing->register_string( '/admin/faq/index',   \&index_handler, app => 1, no_cache => 1 );
DW::Routing->register_string( '/admin/faq/faqedit', \&edit_handler,  app => 1, no_cache => 1 );
DW::Routing->register_string( '/admin/faq/faqcat',  \&cat_handler,   app => 1, no_cache => 1 );

sub _page_setup {
    my ($rv) = @_;

    my $vars   = {};
    my $remote = $rv->{remote};

    my %ac_add  = $remote->priv_args("faqadd");
    my %ac_edit = $remote->priv_args("faqedit");

    $vars->{can_add_any}  = %ac_add  ? 1 : 0;
    $vars->{can_edit_any} = %ac_edit ? 1 : 0;

    $vars->{can_add}  = sub { $ac_add{ $_[0] } };
    $vars->{can_edit} = sub { $ac_edit{ $_[0] } };

    $vars->{can_manage} = $remote->has_priv("faqcat");

    $vars->{display_faq} = sub {    # to display FAQ content properly
        return LJ::html_newlines( LJ::trim( $_[0] ) );
    };

    return $vars;
}

sub index_handler {
    my ( $ok, $rv ) = controller( privcheck => [ 'faqadd', 'faqedit', 'faqcat' ] );
    return $rv unless $ok;

    my $vars   = _page_setup($rv);
    my $remote = $rv->{remote};

    {    # load FAQ categories

        my $dbh = LJ::get_db_writer();

        my $faqcat =
            $dbh->selectall_hashref( "SELECT faqcat, faqcatname, catorder FROM faqcat", 'faqcat' );

        my @sorted_cats = sort { $faqcat->{$a}->{catorder} <=> $faqcat->{$b}->{catorder} }
            keys %$faqcat;

        # Ensure 'no category' is last.

        $faqcat->{''} = { faqcat => '', faqcatname => '<No Category>' };

        push @sorted_cats, '';

        $vars->{faqcat}  = $faqcat;
        $vars->{catlist} = \@sorted_cats;
    }

    {    # load FAQ questions

        my $dom  = LJ::Lang::get_dom("faq");
        my $lang = LJ::Lang::get_root_lang($dom);
        my @faqs = LJ::Faq->load_all( lang => $lang->{lncode}, allow_no_cat => 1 );

        my $user     = $remote->user;
        my $user_url = $remote->journal_base;

        LJ::Faq->render_in_place( { lang => $lang, user => $user, url => $user_url }, @faqs );

        # build hash of FAQs keyed by category
        $vars->{faq} = {};
        push( @{ $vars->{faq}->{ $_->faqcat // '' } }, $_ ) foreach @faqs;

        # in each category, produce a sorted list of FAQs in that category
        $vars->{faqlist} = sub {
            [ sort { $a->sortorder <=> $b->sortorder } @{ $vars->{faq}->{ $_[0] } } ]
        };
    }

    return DW::Template->render_template( 'admin/faq/index.tt', $vars );
}

sub edit_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => [ 'faqadd', 'faqedit' ] );
    return $rv unless $ok;

    my $scope = '/admin/faq/faqedit.tt';

    my $r         = $rv->{r};
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = _page_setup($rv);

    {    # translation setup

        my $faqd  = LJ::Lang::get_dom("faq");
        my $rlang = LJ::Lang::get_root_lang($faqd);

        $vars->{dmid} = $faqd->{dmid} if $faqd;
        $vars->{lang} = $rlang->{lncode};
    }

    # setup for add vs. edit

    if ( !$form_args->{id} ) {

        return error_ml("$scope.error.noaccess.add")
            unless $vars->{can_add_any};
    }
    else {
        my $faqid = $form_args->{id} + 0;
        my $faq   = LJ::Faq->load( $faqid, lang => $vars->{lang} );

        return error_ml( "$scope.error.notfound", { id => $faqid } ) unless $faq;

        my $can_edit = $vars->{can_edit};

        return error_ml( "$scope.error.noaccess" . $vars->{can_edit_any} ? '.editcat' : '.edit',
            { cat => $faq->faqcat } )
            unless $can_edit->('*') || $can_edit->('') || $can_edit->( $faq->faqcat );

        # initialize data variables with previously saved FAQ data

        $vars->{id}          = $faq->id;
        $vars->{faqcat}      = $faq->faqcat // '';
        $vars->{sortorder}   = $faq->sortorder + 0;
        $vars->{question}    = $faq->question_raw;
        $vars->{summary}     = $faq->summary_raw;
        $vars->{answer}      = $faq->answer_raw;
        $vars->{has_summary} = $faq->has_summary;
    }

    $vars->{sortorder} ||= 50;

    if ( $r->did_post ) {    # overwrite with form data

        $vars->{faqcat}    = $form_args->{'faqcat'};
        $vars->{sortorder} = $form_args->{'sortorder'} + 0 || 50;
        $vars->{question}  = $form_args->{'q'};
        $vars->{answer}    = $form_args->{'a'};

        # If summary is disabled or not present, pretend it was unchanged
        $vars->{summary} = $form_args->{'s'}
            if LJ::is_enabled('faq_summaries') && defined $form_args->{'s'};
    }

    my $dbh    = LJ::get_db_writer();
    my $remote = $rv->{remote};

    if ( $r->post_args->{'action:save'} ) {

        # severity options are deprecated - always use 0
        my $text_opts = { changeseverity => 0 };

        my $do_trans = sub {
            my $id = $_[0];
            return unless $vars->{dmid};
            my @lang = ( $vars->{dmid}, $vars->{lang} );

            LJ::Lang::set_text( @lang, "$id.1question", $vars->{question}, $text_opts );
            LJ::Lang::set_text( @lang, "$id.2answer",   $vars->{answer},   $text_opts );
            LJ::Lang::set_text( @lang, "$id.3summary",  $vars->{summary},  $text_opts )
                if LJ::is_enabled('faq_summaries');
        };

        if ( !$vars->{id} ) {    # create new FAQ

            $dbh->do(
                qq{ INSERT INTO faq
                          ( faqid, question, summary, answer, faqcat,
                            sortorder, lastmoduserid, lastmodtime )
                          VALUES ( NULL, ?, ?, ?, ?, ?, ?, NOW() ) },
                undef,           $vars->{question},  $vars->{summary}, $vars->{answer},
                $vars->{faqcat}, $vars->{sortorder}, $remote->id
            );

            return error_ml( "$scope.error.db", { err => $dbh->errstr } )
                if $dbh->err;

            $vars->{id} = $dbh->{mysql_insertid};

            $text_opts->{childrenlatest} = 1;

            if ( $vars->{id} ) {
                $do_trans->( $vars->{id} );

                $vars->{success} = LJ::Lang::ml( "$scope.success.add",
                    { id => $vars->{id}, url => LJ::Faq->url( $vars->{id} ) } );
            }
        }
        elsif ( $vars->{question} =~ /\S/ ) {    # edit existing FAQ

            $dbh->do(
                qq{ UPDATE faq SET question=?, summary=?, answer=?,
                     faqcat=?, sortorder=?, lastmoduserid=?,
                     lastmodtime=NOW() WHERE faqid=? },
                undef,           $vars->{question},  $vars->{summary}, $vars->{answer},
                $vars->{faqcat}, $vars->{sortorder}, $remote->id,      $vars->{id}
            );

            return error_ml( "$scope.error.db", { err => $dbh->errstr } )
                if $dbh->err;

            $do_trans->( $vars->{id} );

            $vars->{success} = LJ::Lang::ml( "$scope.success.edit",
                { id => $vars->{id}, url => LJ::Faq->url( $vars->{id} ) } );
        }
        else {    # delete this FAQ

            $dbh->do( "DELETE FROM faq WHERE faqid=?", undef, $vars->{id} );
            $vars->{success} = LJ::Lang::ml("$scope.success.del");

            # TODO: delete translation from ml_* ?
        }

        return DW::Template->render_template( 'admin/faq/faqedit.tt', $vars );

    }    # end action:save

    if ( $r->post_args->{'action:preview'} ) {

        # TODO: make lastmodtime look more like in LJ::Faq->load

        my %faq_args = (
            faqid         => $vars->{id},
            lastmoduserid => $remote->id,
            lastmodtime   => scalar gmtime,
            unixmodtime   => time,
        );
        $faq_args{$_} = $vars->{$_} foreach qw( faqcat question summary answer sortorder lang );

        my $fake_faq = LJ::Faq->new(%faq_args);

        $fake_faq->render_in_place( { user => $remote->user, url => $remote->journal_base } );

        $vars->{preview_faq} = $fake_faq;
        $vars->{remote}      = $remote;

        # Display summary if enabled and present.
        $vars->{preview_summary} = $fake_faq->has_summary && LJ::is_enabled('faq_summaries');

        # Clean this as if it were an entry, but don't allow lj-cuts
        my $s_html = $fake_faq->summary_html;
        LJ::CleanHTML::clean_event( \$s_html, { ljcut_disable => 1 } )
            if $vars->{preview_summary};
        my $a_html = $fake_faq->answer_raw;
        LJ::CleanHTML::clean_event( \$a_html, { ljcut_disable => 1 } );

        $vars->{s_html} = $s_html;
        $vars->{a_html} = $a_html;

    }    # end action:preview

    {    # load FAQ categories that remote has permission to use

        my $faqcat =
            $dbh->selectall_arrayref("SELECT faqcat, faqcatname FROM faqcat ORDER BY catorder");

        my @catmenu = ( '', '' );

        foreach my $cat (@$faqcat) {
            push( @catmenu, @$cat )
                if $vars->{can_add}->('*')
                || $vars->{can_add}->( $cat->[0] )
                || $cat->[0] eq $vars->{faqcat};
        }

        if ( scalar @catmenu == 2 ) {
            push( @catmenu, '', LJ::Lang::ml("$scope.error.nocats") );
        }

        $vars->{catmenu} = \@catmenu;
    }

    # If FAQ has summary and summaries are disabled, leave field in,
    # but make it read-only to let FAQ editors copy from it.
    $vars->{show_summary}     = LJ::is_enabled('faq_summaries') || $vars->{has_summary};
    $vars->{readonly_summary} = LJ::is_enabled('faq_summaries') ? 0 : 1;

    return DW::Template->render_template( 'admin/faq/faqedit.tt', $vars );
}

sub cat_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['faqcat'] );
    return $rv unless $ok;

    my $scope = '/admin/faq/faqcat.tt';

    my $r         = $rv->{r};
    my $form_args = $r->post_args;
    my $vars      = {};

    my $dbh = LJ::get_db_writer();

    # helper function for reordering categories

    my $move_cat = sub {
        my ( $direction, $faqcat ) = @_;

        my %pre;         # catkey -> key before
        my %post;        # catkey -> key after
        my %catorder;    # catkey -> order

        my $sth = $dbh->prepare("SELECT faqcat, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        my $last;

        while ( my ( $key, $order ) = $sth->fetchrow_array ) {
            if ( defined $last ) {
                $post{$last} = $key;
                $pre{$key}   = $last;
            }
            $catorder{$key} = $order;
            $last = $key;
        }

        my %new;    # catkey -> new order

        if ( $direction eq "up" ) {
            $new{$faqcat} = $catorder{ $pre{$faqcat} };
            $new{ $pre{$faqcat} } = $catorder{$faqcat};
        }
        elsif ( $direction eq "down" ) {
            $new{$faqcat} = $catorder{ $post{$faqcat} };
            $new{ $post{$faqcat} } = $catorder{$faqcat};
        }

        foreach my $n ( keys %new ) {
            $dbh->do( "UPDATE faqcat SET catorder=? WHERE faqcat=?", undef, $new{$n}, $n );
        }
    };

    if ( $r->did_post ) {

        my $faqcat = $form_args->{'faqcat'};

        # If coming from the cat list, see if we're editing/sorting/deleting
        foreach ( split( ",", $form_args->{'faqcats'} // '' ) ) {
            $faqcat = $_ if ( $form_args->{"edit:$_"} );
            $faqcat = $_ if ( $form_args->{"sortup:$_"} );
            $faqcat = $_ if ( $form_args->{"sortdown:$_"} );
            $faqcat = $_ if ( $form_args->{"delete:$_"} );
        }

        if ($faqcat) {

            my $action_setup = sub {
                my $faqcatname = $_[0];
                my $faqd       = LJ::Lang::get_dom("faq");
                my $rlang      = LJ::Lang::get_root_lang($faqd);
                undef $faqd unless $rlang;

                LJ::Lang::set_text( $faqd->{dmid}, $rlang->{lncode},
                    "cat.$faqcatname", $faqcatname, { changeseverity => 1 } )
                    if $faqd;
            };

            # See if we're adding a new FAQ from the cat list
            if ( $form_args->{'action'} && $form_args->{'action'} eq "add" ) {

                my $faqcatname  = LJ::trim( $form_args->{faqcatname} );
                my $faqcatorder = $form_args->{faqcatorder} // 0;

                $action_setup->($faqcatname);

                $dbh->do(
                    "REPLACE INTO faqcat
                              ( faqcat, faqcatname, catorder )
                               VALUES ( ?, ?, ? )",
                    undef, $faqcat, $faqcatname, $faqcatorder
                );

                $vars->{success} = LJ::Lang::ml("$scope.addcat.success");
            }

            # See if we're saving an edited FAQ from the edit form
            elsif ( $form_args->{'action'} && $form_args->{'action'} eq "save" ) {

                $faqcat = $form_args->{faqcat};
                my $faqcatname  = LJ::trim( $form_args->{faqcatname} );
                my $faqcatorder = $form_args->{faqcatorder} // 0;

                $action_setup->($faqcatname);

                $dbh->do(
                    "UPDATE faqcat
                              SET faqcatname=?, catorder=?
                              WHERE faqcat=?",
                    undef, $faqcatname, $faqcatorder, $faqcat
                );

                $vars->{success} = LJ::Lang::ml("$scope.editcat.success");
            }

            # See if we're loading the edit form for a cat
            elsif ( $form_args->{"edit:$faqcat"} ) {

                my $sth = $dbh->prepare(
                    "SELECT faqcat, faqcatname, catorder
                                          FROM faqcat WHERE faqcat=?"
                );
                $sth->execute($faqcat);
                my ($faqcatdata) = $sth->fetchrow_hashref;

                $vars->{faqcatdata} = $faqcatdata;

                return DW::Template->render_template( 'admin/faq/editcat.tt', $vars );
            }

            # See if we're sorting a category up the order
            elsif ( $form_args->{"sortup:$faqcat"} ) {

                $move_cat->( "up", $faqcat );

                $vars->{success} =
                    LJ::Lang::ml( "$scope.catsort.success", { direction => "up" } );
            }

            # See if we're sorting a category down the order
            elsif ( $form_args->{"sortdown:$faqcat"} ) {

                $move_cat->( "down", $faqcat );

                $vars->{success} =
                    LJ::Lang::ml( "$scope.catsort.success", { direction => "down" } );
            }

            # See if we're deleting a FAQ category
            elsif ( $form_args->{"delete:$faqcat"} ) {

                my $ct = $dbh->do( "DELETE FROM faqcat WHERE faqcat=?", undef, $faqcat );

                $vars->{success} = LJ::Lang::ml(
                    $ct
                    ? "$scope.deletecat.success"
                    : "$scope.error.unknowncatkey"
                );
            }
        }
    }

    # Show category list and add form
    {
        my %faqcat;
        my $sth = $dbh->prepare("SELECT faqcat, faqcatname, catorder FROM faqcat");
        $sth->execute;
        $faqcat{ $_->{faqcat} } = $_ while $_ = $sth->fetchrow_hashref;

        $vars->{faqcat}  = \%faqcat;
        $vars->{faqcats} = join( ",", map { $_->{faqcat} } values %faqcat );
        $vars->{catlist} = [
            sort { $faqcat{$a}->{catorder} <=> $faqcat{$b}->{catorder} }
                keys %faqcat
        ];
    }

    $vars->{confirm_delete} = LJ::ejs( LJ::Lang::ml("$scope.deletecat.confirm") );

    return DW::Template->render_template( 'admin/faq/faqcat.tt', $vars );
}

1;
