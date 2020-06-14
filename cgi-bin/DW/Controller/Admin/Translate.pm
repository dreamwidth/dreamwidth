#!/usr/bin/perl
#
# DW::Controller::Admin::Translate
#
# Frontend for finding and editing strings in the translation system.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::Translate;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use File::Temp qw/tempfile/;

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'translate',
    ml_scope => '/admin/translate/index.tt',
);

DW::Routing->register_string( "/admin/translate/index",         \&index_controller,      app => 1 );
DW::Routing->register_string( "/admin/translate/diff",          \&diff_controller,       app => 1 );
DW::Routing->register_string( "/admin/translate/edit",          \&edit_controller,       app => 1 );
DW::Routing->register_string( "/admin/translate/editpage",      \&editpage_controller,   app => 1 );
DW::Routing->register_string( "/admin/translate/search",        \&search_controller,     app => 1 );
DW::Routing->register_string( "/admin/translate/searchform",    \&searchform_controller, app => 1 );
DW::Routing->register_string( "/admin/translate/help-severity", \&severity_controller,   app => 1 );
DW::Routing->register_string( "/admin/translate/welcome",       \&welcome_controller,    app => 1 );

sub index_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $vars = {};

    my %lang;

    {    # load language info from database into %lang

        my $dbr = LJ::get_db_reader();
        my $sth;

        $sth = $dbr->prepare("SELECT lnid, lncode, lnname, lastupdate FROM ml_langs");
        $sth->execute;
        $lang{ $_->{'lnid'} } = $_ while $_ = $sth->fetchrow_hashref;

        $sth = $dbr->prepare("SELECT lnid, staleness > 1, COUNT(*) FROM ml_latest GROUP by 1, 2");
        $sth->execute;
        while ( my ( $lnid, $stale, $ct ) = $sth->fetchrow_array ) {
            next unless exists $lang{$lnid};
            $lang{$lnid}->{'_total'} += $ct;
            $lang{$lnid}->{'_good'}  += ( 1 - $stale ) * $ct;
            $lang{$lnid}->{'percent'} =
                100 * $lang{$lnid}->{'_good'} / ( $lang{$lnid}->{'_total'} || 1 );
        }
    }

    $vars->{rows} = [ sort { $a->{lnname} cmp $b->{lnname} } values %lang ];

    $vars->{cols} = [
        {
            ln_key => 'lncode',
            ml_key => '.table.code',
            format => sub { $_[0]->{lncode} }
        },
        {
            ln_key => 'lnname',
            ml_key => '.table.langname',
            format => sub {
                my $r = $_[0];
                "<a href='edit?lang=$r->{lncode}'>$r->{lnname}</a>";
            }
        },
        {
            ln_key => 'percent',
            ml_key => '.table.done',
            format => sub {
                my $r   = $_[0];
                my $pct = sprintf( "%.02f%%", $r->{percent} );
                "<b>$pct</b><br />$r->{'_good'}/$r->{'_total'}";
            }
        },
        {
            ln_key => 'lastupdate',
            ml_key => '.table.lastupdate',
            format => sub { $_[0]->{lastupdate} }
        }
    ];

    return DW::Template->render_template( 'admin/translate/index.tt', $vars );
}

sub diff_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;
    my $vars      = { lang => $form_args->{lang} };

    my $l = LJ::Lang::get_lang( $vars->{lang} );

    my $err = sub { DW::Template->render_string( $_[0], { no_sitescheme => 1 } ) };

    return $err->("<b>Invalid language</b>") unless $l;

    my $itkey = $form_args->{it} // '';
    return $err->("<b>Invalid item</b>") unless $itkey =~ /^(\d+):(\d+)$/;
    my ( $dmid, $itid ) = ( $1, $2 );

    my $lnids;
    {    # look for parent languages
        my @lnids = $l->{'lnid'};
        my $il    = $l;

        while ( $il && $il->{'parentlnid'} ) {
            push @lnids, $il->{'parentlnid'};
            $il = LJ::Lang::get_lang_id( $il->{'parentlnid'} );
        }

        $lnids = join( ",", @lnids );
    }

    my @tlist;
    {    # fetch text from database
        my $dbr = LJ::get_db_reader();

        my $sth = $dbr->prepare( "SELECT * FROM ml_text WHERE dmid=$dmid"
                . " AND itid=$itid AND lnid IN ($lnids) ORDER BY txtid" );
        $sth->execute;

        while ( my $t = $sth->fetchrow_hashref ) {
            next if @tlist && $t->{text} eq $tlist[-1]->{text};
            push @tlist, $t;
        }
    }

    $vars->{num_changes} = scalar @tlist - 1;
    return $err->("<b>No changes</b>") unless $vars->{num_changes};

    my $view_change = $form_args->{change} || $vars->{num_changes};
    return $err->("bogus change")
        if $view_change < 1 || $view_change > $vars->{num_changes};

    $vars->{change_link} = sub {
        my $c = $_[0];
        return "<b>[Change $c]</b>" if $c eq $view_change;
        return "<a href='diff?lang=$vars->{lang}&it=$itkey&change=$c'>[Change $c]</a>";
    };

    my $was  = $tlist[ $view_change - 1 ]->{text};
    my $then = $tlist[$view_change]->{text};

    my ( @words, $diff );
    {    # calculate differences
        my ( $was_alt, $then_alt ) = ( $was, $then );

        foreach ( \$was_alt, \$then_alt ) {
            $$_ =~ s/\n/*NEWLINE*/g;
            $$_ =~ s/\s+/\n/g;
            $$_ .= "\n";
        }

        my ( $was_file, $then_file, $fh );

        ( $fh, $was_file ) = tempfile();
        print $fh $was_alt;
        close $fh;

        ( $fh, $then_file ) = tempfile();
        print $fh $then_alt;
        close $fh;

        @words = split( /\n/, $was_alt );
        $diff  = `diff -u $was_file $then_file`;

        unlink( $was_file, $then_file );
    }

    $vars->{words}     = \@words;
    $vars->{difflines} = [ split( /\n/, $diff ) ];

    $was  = LJ::eall($was);
    $then = LJ::eall($then);
    $was  =~ s/\n( *)/"<br \/>" . "&nbsp;"x length($1)/eg;
    $then =~ s/\n( *)/"<br \/>" . "&nbsp;"x length($1)/eg;

    $vars->{was}  = $was;
    $vars->{then} = $then;

    $vars->{format} = sub {
        my $word = LJ::ehtml( $_[0] );
        $word =~ s/\*NEWLINE\*/<br>\n/g;
        return $word;
    };

    return DW::Template->render_template( 'admin/translate/diff.tt', $vars,
        { no_sitescheme => 1 } );
}

sub edit_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;

    return $r->redirect('/admin/translate/') unless $form_args->{lang};

    return DW::Template->render_template( 'admin/translate/edit.tt', $form_args,
        { no_sitescheme => 1 } );
}

sub editpage_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = { lang => $form_args->{lang} };

    my $l = LJ::Lang::get_lang( $vars->{lang} );

    my $err = sub { DW::Template->render_string( $_[0], { no_sitescheme => 1 } ) };

    return $err->("<b>Invalid language</b>") unless $l;

    my $lp = $l->{'parentlnid'} ? LJ::Lang::get_lang_id( $l->{'parentlnid'} ) : undef;

    $vars->{l}  = $l;
    $vars->{lp} = $lp;

    if ( my $remote = $rv->{remote} ) {
        $vars->{can_edit}   = $remote->has_priv( "translate", $l->{'lncode'} );
        $vars->{can_delete} = $remote->has_priv( "translate", "[itemdelete]" );
    }

    # Extra checkboxes for default language and root language (DW: en_DW and en)
    $vars->{extra_checkboxes} = $l->{'lncode'} eq $LJ::DEFAULT_LANG || !defined $lp;

    my $mode = { '' => 'view', 'save' => 'save' }->{ $form_args->{mode} // '' };
    return $err->("<b>Bogus mode</b>") unless $mode;

    my $dbr = LJ::get_db_reader();

    my $MAX_EDIT = 100;

    if ( $mode eq "save" ) {

        my $num = $form_args->{'ict'} + 0;
        $num = $MAX_EDIT if $num > $MAX_EDIT;

        my ( @errors, @info );
        unless ( $vars->{can_edit} ) {
            push @errors, "You don't have access to edit text for this language.";
            $num = 0;
        }

        unless ( LJ::text_in($form_args) ) {
            push @errors, "Your browser's encoding seems to be something other"
                . " than UTF-8.  It needs to be in UTF-8.";
            push @errors, "Nothing saved.";
            $num = 0;
        }

        my $saved = 0;    # do any saves?

        my $dbh;

        for ( my $i = 1 ; $i <= $num ; $i++ ) {
            next unless $form_args->{"ed_$i"};

            my ( $dom, $itid, $oldtxtid, $oldptxtid, $sev, $proofed, $updated ) =
                map { int( $form_args->{"${_}_$i"} // 0 ) + 0 }
                qw(dom itid oldtxtid oldptxtid sev pr up);

            my $itcode =
                $dbr->selectrow_array("SELECT itcode FROM ml_items WHERE dmid=$dom AND itid=$itid");
            unless ( defined $itcode ) {
                push @errors, "Bogus dmid/itid: $dom/$itid";
                next;
            }

            $dbh ||= LJ::get_db_writer();
            my $lat = $dbh->selectrow_hashref( "SELECT * FROM ml_latest"
                    . " WHERE lnid=$l->{'lnid'} AND dmid=$dom AND itid=$itid" );
            unless ($lat) {
                push @errors, "No existing mapping for $itcode";
                next;
            }

            unless ( $lat->{'txtid'} == $oldtxtid ) {
                push @errors, "Another translator updated '$itcode' before you saved,"
                    . " so your edit has been ignored.";
                next;
            }

            my $plat;
            if ($lp) {
                $plat = $dbh->selectrow_hashref( "SELECT * FROM ml_latest"
                        . " WHERE lnid=$lp->{'lnid'} AND dmid=$dom AND itid=$itid" );

                my $ptid = $plat ? $plat->{'txtid'} : 0;
                unless ( $ptid == $oldptxtid ) {
                    push @errors, "The source text of item '$itcode' changed while"
                        . " you were editing, so your edit has been ignored.";
                    next;
                }
            }

            # did they type anything?
            my $text = $form_args->{"newtext_$i"};
            next unless defined $text && $text =~ /\S/;

            # delete
            if ( $text eq "XXDELXX" ) {
                if ( $vars->{can_delete} ) {
                    $dbh->do("DELETE FROM ml_latest WHERE dmid=$dom AND itid=$itid");
                    push @info, "Deleted: '$itcode'";
                }
                else {
                    push @errors, "You don't have access to delete items.";
                }
                next;
            }

            # did anything even change, though?
            my $oldtext = $dbr->selectrow_array(
                "SELECT text FROM ml_text WHERE dmid=$dom AND txtid=$lat->{'txtid'}");

            if ( $oldtext eq $text && $lat->{'staleness'} == 2 ) {
                push @errors, "Severity of source language change requires"
                    . " change in text for item '$itcode'";
                next;
            }

            # keep old txtid if text didn't change.
            my $opts = {};
            if ( $oldtext eq $text ) {
                $opts->{txtid} = $lat->{'txtid'};
                $text          = undef;
                $sev           = 0;
            }

            # if setting text for first time, push down to children langs
            if ( $lat->{'staleness'} == 4 ) {
                $opts->{childrenlatest} = 1;
            }

            # severity of change:
            $opts->{changeseverity} = $sev;

            # set userid of writer
            $opts->{userid} = $rv->{remote}->id;

            my ( $res, $msg ) =
                LJ::Lang::web_set_text( $dom, $l->{'lncode'}, $itcode, $text, $opts );

            if ($res) {
                push @info, "OK: $itcode";
                $saved = 1;

                if ( $vars->{extra_checkboxes} ) {

                    # Not gonna bother to refactor to LJ::Lang as the whole
                    # translation system will get thrown away and redone later.
                    # TODO: make sure my words don't come back to haunt me.
                    # (Controller author's note: good luck with that.)
                    $dbh->do(
                        "UPDATE ml_items SET proofed = ?, updated = ? "
                            . "WHERE dmid = ? AND itid = ?",
                        undef, $proofed ? 1 : 0, $updated ? 1 : 0, $dom, $itid
                    );

                    if ( $dbh->err ) {
                        push @errors, $dbh->errstr;
                    }
                    else {
                        push @info, "OK: $itcode (flags)";
                    }
                }
            }
            else {    # no $res
                push @errors, $msg;
            }

        }    # end for

        $dbh ||= LJ::get_db_writer();
        $dbh->do("UPDATE ml_langs SET lastupdate=NOW() WHERE lnid=$l->{'lnid'}")
            if $saved;

        my $ret = '';

        if (@errors) {
            $ret .= "<b>ERRORS:</b><ul>";
            $ret .= "<li>$_</li>" foreach @errors;
            $ret .= "</ul>";
        }

        if (@info) {
            $ret .= "<b>Results:</b><ul>";
            $ret .= "<li>$_</li>" foreach @info;
            $ret .= "</ul>";
        }

        if ( !@errors && !@info ) {
            $ret .= "<i>No errors & nothing saved.</i>";
        }

        return $err->($ret);
    }

    if ( $mode eq "view" ) {

        my $sth;
        my @load;

        foreach ( split /,/, $form_args->{items} ) {
            next unless /^(\d+):(\d+)$/;
            last if @load >= $MAX_EDIT;
            push @load, { 'dmid' => $1, 'itid' => $2 };
        }

        return $err->("Nothing to show.") unless @load;

        $vars->{load} = \@load;

        my $itwhere = join( " OR ", map { "(dmid=$_->{dmid} AND itid=$_->{itid})" } @load );

        # load item info
        my %ml_items;
        {
            $sth = $dbr->prepare( "SELECT dmid, itid, itcode, proofed, updated, notes"
                    . " FROM ml_items WHERE $itwhere" );
            $sth->execute;

            while ( my ( $dmid, $itid, $itcode, $proofed, $updated, $notes ) =
                $sth->fetchrow_array )
            {
                $ml_items{"$dmid-$itid"} = {
                    'itcode'  => $itcode,
                    'proofed' => $proofed,
                    'updated' => $updated,
                    'notes'   => $notes
                };
            }
        }

        # getting latest mappings for this lang and parent
        my %ml_text;
        my %ml_latest;
        {
            $sth =
                $dbr->prepare( "SELECT lnid, dmid, itid, txtid, chgtime, staleness FROM ml_latest"
                    . " WHERE ($itwhere) AND lnid IN ($l->{'lnid'}, $l->{'parentlnid'})" );
            $sth->execute;
            return $err->( $dbr->errstr ) if $dbr->err;

            while ( $_ = $sth->fetchrow_hashref ) {
                $ml_latest{"$_->{'dmid'}-$_->{'itid'}"}->{ $_->{'lnid'} } = $_;
                $ml_text{"$_->{'dmid'}-$_->{'txtid'}"} = undef;    # mark to load later
            }

            # load text
            $sth = $dbr->prepare(
                "SELECT dmid, txtid, lnid, itid, text FROM ml_text WHERE "
                    . join( " OR ",
                    map { "(dmid=$_->[0] AND txtid=$_->[1])" }
                    map { [ split( /-/, $_ ) ] } keys %ml_text )
            );
            $sth->execute;

            while ( $_ = $sth->fetchrow_hashref ) {
                $ml_text{"$_->{'dmid'}-$_->{'txtid'}"} = $_;
            }
        }

        $vars->{ml_items}  = \%ml_items;
        $vars->{ml_text}   = \%ml_text;
        $vars->{ml_latest} = \%ml_latest;
    }

    $vars->{get_dom_id} = sub { LJ::Lang::get_dom_id( $_[0] ) };

    $vars->{html_newlines} = sub { LJ::html_newlines( $_[0] ) };

    $vars->{clean_text} = sub {
        my $t = LJ::ehtml( $_[0] );
        $t =~ s/\n( *)/"<br \/>" . "&nbsp;"x length($1)/eg;
        return $t;
    };

    return DW::Template->render_template( 'admin/translate/editpage.tt',
        $vars, { no_sitescheme => 1 } );
}

sub search_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;
    my $vars      = { lang => $form_args->{lang} };

    my $l = LJ::Lang::get_lang( $vars->{lang} );

    my $err = sub { DW::Template->render_string( $_[0], { no_sitescheme => 1 } ) };

    return $err->("<b>Invalid language</b>") unless $l;

    my $dbr = LJ::get_db_reader();
    my $sql;

    # construct database query
    {
        # all queries in production use the visible flag
        my $vis_flag = $LJ::IS_DEV_SERVER ? '' : 'AND i.visible = 1';

        if ( $form_args->{search} eq 'sev' ) {
            my $what = ">= 1";
            if ( $form_args->{stale} =~ /^(\d+)(\+?)$/ ) {
                $what = ( $2 ? ">=" : "=" ) . $1;
            }
            $sql = qq(
                SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l
                WHERE l.lnid=$l->{'lnid'} AND l.staleness $what AND l.dmid=i.dmid
                AND l.itid=i.itid $vis_flag ORDER BY i.dmid, i.itcode
            );
        }

        if ( $form_args->{search} eq 'txt' ) {
            my $remote = $rv->{remote};
            return $err->("This search type is restricted to $l->{'lnname'} translators.")
                unless $remote
                && ( $remote->has_priv( "translate", $l->{'lncode'} )
                || $remote->has_priv( "faqedit", "*" ) );    # FAQ admins can search too

            my $qtext     = $dbr->quote( $form_args->{searchtext} );
            my $dmid      = $form_args->{searchdomain} + 0;
            my $dmidwhere = $dmid ? "AND i.dmid=$dmid" : "";

            if ( $form_args->{searchwhat} eq "code" ) {
                $sql = qq{
                    SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l
                    WHERE l.lnid=$l->{'lnid'} AND l.dmid=i.dmid AND i.itid=l.itid $vis_flag
                    $dmidwhere AND LOCATE($qtext, i.itcode)
                };
            }
            else {
                my $lnid = $l->{'lnid'};
                $lnid = $l->{'parentlnid'} if $form_args->{searchwhat} eq "parent";

                $sql = qq{
                    SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l, ml_text t
                    WHERE l.lnid=$lnid AND l.dmid=i.dmid AND i.itid=l.itid
                    $dmidwhere AND t.dmid=l.dmid AND t.txtid=l.txtid
                    AND LOCATE($qtext, t.text) $vis_flag ORDER BY i.itcode
                };
            }
        }

        if ( $form_args->{search} eq 'flg' ) {
            return $err->("This type of search isn't available for this language.")
                unless $l->{'lncode'} eq $LJ::DEFAULT_LANG || !$l->{'parentlnid'};

            my $whereflags = join ' AND ',
                map  { $form_args->{"searchflag$_"} eq 'yes' ? "$_ = 1" : "$_ = 0" }
                grep { $form_args->{"searchflag$_"} ne 'whatev' } qw(proofed updated);
            $whereflags = "AND $whereflags" if $whereflags ne '';

            $sql = qq(
                SELECT i.dmid, i.itid, i.itcode FROM ml_items i, ml_latest l
                WHERE l.lnid=$l->{lnid} AND l.dmid=i.dmid AND l.itid=i.itid $whereflags $vis_flag
                ORDER BY i.dmid, i.itcode
            );
        }

        return $err->("Bogus or unimplemented query type.") unless $sql;
    }

    # each row contains 3 elements: (dmid, itid, itcode)
    $vars->{rows} = $dbr->selectall_arrayref($sql);

    # helper function for constructing links in template
    $vars->{join} = sub {
        my $pages = $_[0];
        return LJ::eurl( join( ",", map { "$_->[0]:$_->[1]" } @$pages ) );
    };

    return DW::Template->render_template( 'admin/translate/search.tt',
        $vars, { no_sitescheme => 1 } );
}

sub searchform_controller {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->get_args;
    my $vars      = { lang => $form_args->{lang} };

    $vars->{l} = LJ::Lang::get_lang( $vars->{lang} );

    return $r->redirect('/admin/translate/') unless $vars->{l};

    $vars->{pl} = LJ::Lang::get_lang_id( $vars->{l}->{parentlnid} );

    $vars->{domains} = [ sort { $a->{dmid} <=> $b->{dmid} } LJ::Lang::get_domains() ];

    $vars->{def_lang} = $LJ::DEFAULT_LANG;

    return DW::Template->render_template( 'admin/translate/searchform.tt',
        $vars, { no_sitescheme => 1 } );
}

sub severity_controller {

    # this could be a static page if register_static supported no_sitescheme

    return DW::Template->render_template( 'admin/translate/help-severity.tt',
        {}, { no_sitescheme => 1 } );
}

sub welcome_controller {

    # this could be a static page if register_static supported no_sitescheme

    return DW::Template->render_template( 'admin/translate/welcome.tt', {},
        { no_sitescheme => 1 } );
}

1;
