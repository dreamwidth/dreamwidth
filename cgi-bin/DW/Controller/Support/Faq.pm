#!/usr/bin/perl
#
# DW::Controller::Support::Faq
#
# This controller is for the Support FAQ page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Faq;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/faq',       \&faq_handler,       app => 1 );
DW::Routing->register_string( '/support/faqpop',    \&faqpop_handler,    app => 1 );
DW::Routing->register_string( '/support/faqbrowse', \&faqbrowse_handler, app => 1 );
DW::Routing->register_string( '/support/faqsearch', \&faqsearch_handler, app => 1 );

sub faq_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    my $vars = {};

    my $dbr = LJ::get_db_reader();
    my $sth;
    my %faqcat;
    my %faqq;
    my $ret = "";

    $sth = $dbr->prepare(
        "SELECT faqcat, faqcatname, catorder FROM faqcat " . "WHERE faqcat<>'int-abuse'" );

    $sth->execute;

    while ( $_ = $sth->fetchrow_hashref ) {
        $faqcat{ $_->{faqcat} } = $_;
    }

    # Get remote username and journal URL, or example user's username and journal URL
    if ($remote) {
        $user     = $remote->user;
        $user_url = $remote->journal_base;
    }
    else {
        my $u = LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
        $user     = $u ? $u->user         : "<b>[Unknown or undefined example username]</b>";
        $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
    }

    foreach my $f ( LJ::Faq->load_all ) {
        $f->render_in_place( { user => $user, url => $user_url } );
        $faqq{ $f->faqid } = $f;
    }

    foreach my $faqcat ( sort { $faqcat{$a}->{catorder} <=> $faqcat{$b}->{catorder} } keys %faqcat )
    {
        my $countfaqs = 0;
        foreach ( grep { $faqq{$_}->faqcat eq $faqcat } keys %faqq ) {
            $countfaqs++;
        }
        next unless $countfaqs;
        push @{ $vars->{faqcats} },
            {
            faqcat     => $faqcat,
            faqcatname => $faqcat{$faqcat}->{faqcatname},
            };
        foreach my $faqid (
            sort { $faqq{$a}->sortorder <=> $faqq{$b}->sortorder }
            grep { $faqq{$_}->faqcat eq $faqcat } keys %faqq
            )
        {
            my $q = $faqq{$faqid}->question_html;
            next unless $q;
            $q =~ s/^\s+//;
            $q =~ s/\s+$//;
            $q =~ s!\n!<br />!g;
            push @{ $vars->{questions}->{$faqcat}->{faqqs} },
                {
                q     => $q,
                faqid => $faqid
                };
        }
    }

    return DW::Template->render_template( 'support/faq.tt', $vars );

}

sub faqpop_handler {
    my $r   = DW::Request->get;
    my $get = $r->get_args;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $vars = {};

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    # Get remote username and journal URL, or example user's username and journal URL
    if ($remote) {
        $user     = $remote->user;
        $user_url = $remote->journal_base;
    }
    else {
        my $u = LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
        $user     = $u ? $u->user         : "<b>[Unknown or undefined example username]</b>";
        $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
    }

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare(
        "SELECT statkey, statval FROM stats WHERE statcat='pop_faq' ORDER BY statval DESC LIMIT 50"
    );
    $sth->execute;

    while ( my $s = $sth->fetchrow_hashref ) {
        my $f = LJ::Faq->load( $s->{statkey} );
        $f->render_in_place( { user => $user, url => $user_url } );
        my $q = $f->question_html;
        $q =~ s/^\s+//;
        $q =~ s/\s+$//;
        $q =~ s!\n!<br />!g;
        push @{ $vars->{faqs} },
            {
            question => $q,
            statval  => $s->{statval},
            faqid    => $f->faqid
            };
    }

    return DW::Template->render_template( 'support/faqpop.tt', $vars );

}

sub faqbrowse_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $user;
    my $user_url;
    my $vars = {};

    if ($remote) {
        $vars->{remote} = $remote;

        $user     = $remote->user;
        $user_url = $remote->journal_base;
    }
    else {
        my $u = LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
        $user     = $u ? $u->user         : "<b>[Unknown or undefined example username]</b>";
        $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
    }

    # get faqid and redirect to faq.bml if none
    my $faqidarg = $GET->{'faqid'} ? $GET->{'faqid'} + 0 : 0;

    # FIXME: disallow both faqid and faqcat (or ignore one)
    my $faqcatarg = $GET->{'faqcat'};

    unless ( $faqidarg || $faqcatarg ) {
        return $r->redirect("faq");
    }

    # get language settings
    my $curlang = $GET->{'lang'} || LJ::Lang::get_effective_lang();
    my $deflang = BML::get_language_default();
    my $altlang = $curlang ne $deflang;
    my $mll     = LJ::Lang::get_lang($curlang);
    my $mld     = LJ::Lang::get_dom("faq");
    $altlang = 0 unless $mll && $mld;
    my $lang = $altlang ? $curlang : $deflang;
    $vars->{altlang} = $altlang;
    $vars->{curlang} = $curlang;

    my $view = $GET->{'view'} // '';
    my $mode = ( $view eq 'full' || $faqidarg ) ? 'answer' : 'summary';

    my @faqs;
    my $title;
    my $body;
    my $dbr = LJ::get_db_reader();
    if ($faqidarg) {

        # loading single faqid
        @faqs = ( LJ::Faq->load( $faqidarg, lang => $lang ) );
        unless ( $faqs[0] ) {
            $title =
                LJ::Lang::ml( '/support/faqbrowse.tt.error.title_nofaq', { faqid => $faqidarg } );
            $vars->{title} = $title;
            return DW::Template->render_template( 'support/faqbrowse.tt', $vars );
        }
        $faqs[0]->render_in_place( { user => $user, url => $user_url } );
        $title = $faqs[0]->question_html;
    }
    elsif ($faqcatarg) {

        # loading entire faqcat
        my $catname;
        if ($altlang) {
            $catname = LJ::Lang::get_text( $curlang, "cat.$faqcatarg", $mld->{dmid} );
        }
        else {
            $catname = $dbr->selectrow_array( "SELECT faqcatname FROM faqcat WHERE faqcat=?",
                undef, $faqcatarg );
            die $dbr->errstr if $dbr->err;
        }
        $title =
            LJ::Lang::ml( '/support/faqbrowse.tt.title_cat', { catname => LJ::ehtml($catname) } );
        @faqs = sort { $a->sortorder <=> $b->sortorder }
            LJ::Faq->load_all( lang => $lang, cat => $faqcatarg );
        LJ::Faq->render_in_place(
            {
                lang => $lang,
                user => $user,
                url  => $user_url
            },
            @faqs
        );
        $vars->{faqcatarg} = 1;

    }

    my $dbh;
    my $categoryname;
    my @cleanfaqs;
    my $qterm = $GET->{'q'};
    $vars->{q} = $qterm ? "&q=" . LJ::eurl($qterm) : "";

    foreach my $f (@faqs) {
        my $cleanf;
        my $faqid = $f->faqid;    # Used throughout, including in interpolations
        $dbh ||= LJ::get_db_writer();

        # log this faq view
        if ( $remote && LJ::is_enabled('faquses') ) {
            $dbh->do( "REPLACE INTO faquses (faqid, userid, dateview) " . "VALUES (?, ?, NOW())",
                undef, $faqid, $remote->{'userid'} );
        }

        BML::note_mod_time( $f->unixmodtime );

        my $summary = $f->summary_raw;
        my $answer  = $f->answer_raw;

        # What to display?
        my $display_summary;
        my $display_answer;
        if ( $mode eq 'answer' ) {    # answer, summary if present
            $display_answer  = 1;
            $display_summary = $f->has_summary;
        }
        else {                        # summary if there's one, answer if there's no summary
            $display_summary = $f->has_summary;
            $display_answer  = !$display_summary;
        }

        # If summaries are disabled, pretend the FAQ doesn't have one.
        unless ( LJ::is_enabled('faq_summaries') ) {
            $display_answer ||= $display_summary;
            $display_summary = 0;
        }

        # escape question
        my $question = $f->question_html;
        $question =~ s/^\s+//;
        $question =~ s/\s+$//;
        $question =~ s/\n/<br \/>/g;

        # Clean this as if it were an entry, but don't allow lj-cuts
        LJ::CleanHTML::clean_event( \$summary, { 'ljcut_disable' => 1 } )
            if $display_summary;
        LJ::CleanHTML::clean_event( \$answer, { 'ljcut_disable' => 1 } )
            if $display_answer;

        # Highlight search terms
        my $term = sub {
            my $xterm = shift;
            return $xterm if $xterm =~ m!^https?://!;
            return "<span class='searchhighlight'>" . LJ::ehtml($xterm) . "</span>";
        };

        if ($qterm) {
            $question =~ s/(\Q$qterm\E)/$term->($1)/ige;
            $summary //= '';    # no undefined string warnings

            # don't highlight terms in URLs or HTML tags
            # FIXME: if the search term is present in a tag, should still
            # highlight occurences outside tags.
            $summary =~ s!((?:https?://[^>]+)?\Q$qterm\E)!$term->($1)!ige
                unless $summary =~ m!<[^>]*\Q$qterm\E[^>]*>!;

            $answer =~ s!((?:https?://[^>]+)?\Q$qterm\E)!$term->($1)!ige
                unless $answer =~ m!<[^>]*\Q$qterm\E[^>]*>!;
        }

        my $lastmodwho = LJ::get_username( $f->lastmoduserid );

        $cleanf = {
            'faqid'           => $faqid,
            'question'        => $question,
            'answer'          => $answer,
            'summary'         => $summary,
            'display_summary' => $display_summary,
            'display_answer'  => $display_answer,
            'lastmodwho'      => $lastmodwho,
            'lastmodtime'     => $f->lastmodtime
        };

        # this is incredibly ugly. i'm sorry.
        if ( $altlang && $remote && $remote->has_priv( "translate", $curlang ) ) {
            my @itids;
            push @itids, LJ::Lang::get_itemid( $mld->{'dmid'}, "$faqid.$_" )
                foreach qw(1question 3summary 2answer);
            my $items = join( ",", map { $mld->{'dmid'} . ":" . $_ } @itids );
            $cleanf->{t_items} = $items;
        }

        my $backfaqcat = $f->faqcat // '';

        # get the name of this faq's category, if loading a single faqid
        if ($faqidarg) {
            if ($altlang) {
                $categoryname = LJ::Lang::get_text( $curlang, "cat.$backfaqcat", $mld->{'dmid'} );
            }
            else {
                $categoryname =
                    $dbr->selectrow_array( "SELECT faqcatname FROM faqcat WHERE faqcat=?",
                    undef, $backfaqcat );
            }
            $cleanf->{categoryname} = $categoryname;
        }
        push @cleanfaqs, $cleanf;
    }

    $vars->{title} = $title;
    $vars->{faqs}  = \@cleanfaqs;

    return DW::Template->render_template( 'support/faqbrowse.tt', $vars );
}

sub faqsearch_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $vars;

    my @langs;
    foreach my $code (@LJ::LANGS) {
        my $l = LJ::Lang::get_lang($code);
        next unless $l;

        my $item         = "langname.$code";
        my $namethislang = BML::ml($item);
        my $namenative   = LJ::Lang::get_text( $l->{'lncode'}, $item );

        push @langs, $code;

        my $s = $namenative;
        $s .= " ($namethislang)" if $namethislang ne $namenative;
        push @langs, $s;
    }

    my $curr = BML::get_language();
    my $sel  = $GET->{'lang'} || $curr;
    my $q    = $GET->{'q'};

    $vars->{langs} = \@langs;
    $vars->{sel}   = $sel;
    $vars->{q}     = $q;

    if ( $q && length($q) > 2 ) {
        my $lang = $GET->{lang} || $curr || $LJ::DEFAULT_LANG;
        my $user;
        my $user_url;

        # Get remote username and journal URL, or example user's username and journal URL
        if ($remote) {
            $user     = $remote->user;
            $user_url = $remote->journal_base;
        }
        else {
            my $u = LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
            $user     = $u ? $u->user         : "<b>[Unknown or undefined example username]</b>";
            $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
        }

        my @results = LJ::Faq->load_matching( $q, lang => $lang, user => $user, url => $user_url );
        if ( @results > 25 ) { @results = @results[ 0 .. 24 ]; }

        my $term = sub {
            my $term = shift;
            return "<span class='searchhighlight'>" . LJ::ehtml($term) . "</span>";
        };

        my @clean_results;
        foreach my $f (@results) {
            my $dq = $f->question_html;
            $dq =~ s/(\Q$q\E)/$term->($1) /ige;
            my $ueq   = LJ::eurl($q);
            my $ul    = $GET->{'lang'} ne $curr ? "&amp;lang=" . $GET->{'lang'} : '';
            my $clean = { dq => $dq, ueq => $ueq, ul => $ul, id => $f->faqid };
            push @clean_results, $clean;
        }
        $vars->{results} = \@clean_results;
    }
    return DW::Template->render_template( 'support/faqsearch.tt', $vars );
}

1;
