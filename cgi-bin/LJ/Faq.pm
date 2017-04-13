#!/usr/bin/perl
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


package LJ::Faq;

use strict;
use Carp;

# Initially built in a hackathon, so this is only moderately awesome
# -- whitaker 2006/06/23

# FIXME: singletons?

# <LJFUNC>
# name: LJ::Faq::new
# class: general
# des: Creates a LJ::Faq object from supplied information.
# args: opts
# des-opts: Hash of initial field values for the new Faq. Allowed keys are:
#           faqid, question, summary, answer, faqcat, lastmoduserid, sortorder,
#           lastmodtime, unixmodtime, and lang. Default for lang is
#           $LJ::DEFAULT_LANG, all others undef.
# returns: The new LJ::Faq object.
# </LJFUNC>
sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    my %opts = @_;

    $self->{$_} = delete $opts{$_}
        foreach qw(faqid question summary answer faqcat lastmoduserid sortorder lastmodtime unixmodtime);
    # FIXME: shouldn't that be the root language of the faq domain instead?
    $self->{lang} = delete $opts{lang} || $LJ::DEFAULT_LANG;

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    return $self;
}

# <LJFUNC>
# name: LJ::Faq::load
# class: general
# des: Creates a LJ::Faq object and populates it from the database.
# args: faqid, opts?
# des-faqid: The integer id of the FAQ to load.
# des-opts: Hash of option key => value.
#           lang => language, xx or xx_YY. Defaults to $LJ::DEFAULT_LANG.
# returns: The newly populated LJ::Faq object.
# </LJFUNC>
sub load {
    my $class = shift;
    my $faqid = int(shift);
    croak ("invalid faqid: $faqid")
        unless $faqid > 0;

    my %opts = @_;
    my $lang = delete $opts{lang} || $LJ::DEFAULT_LANG;
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";

    my $faq;
    # FIXME: shouldn't that be the root language of the faq domain instead?
    if ($lang eq $LJ::DEFAULT_LANG) {
        my $f = $dbr->selectrow_hashref
            ("SELECT faqid, question, summary, answer, faqcat, lastmoduserid, ".
             "DATE_FORMAT(lastmodtime, '%M %D, %Y') AS lastmodtime, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq WHERE faqid=?",
             undef, $faqid);
        die $dbr->errstr if $dbr->err;
        return undef unless $f;
        $faq = $class->new(%$f, lang => $lang);

    } else { # Don't load fields that lang_update_in_place will overwrite.
        my $f = $dbr->selectrow_hashref
            ("SELECT faqid, faqcat, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq WHERE faqid=?",
             undef, $faqid);
        die $dbr->errstr if $dbr->err;
        return undef unless $f;
        $faq = $class->new(%$f, lang => $lang);
        $faq->lang_update_in_place;
    }

    return $faq;
}

# <LJFUNC>
# name: LJ::Faq::load_all
# class: general
# des: Creates LJ::Faq objects from all FAQs in the database.
# args: opts?
# des-opts: Hash of option key => value.
#           lang => language, xx or xx_YY. Defaults to $LJ::DEFAULT_LANG.
#           cat => category to load (loads FAQs in all cats if absent).
# returns: Array of populated LJ::Faq objects, one per FAQ loaded.
# </LJFUNC>
sub load_all {
    my $class = shift;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";

    my %opts = @_;
    my $lang = delete $opts{lang} || $LJ::DEFAULT_LANG;
    my $faqcat = delete $opts{cat};
    my $allow_no_cat = delete $opts{allow_no_cat} || 0;

    my $wherecat = "";
    if ( $allow_no_cat ) {
        $wherecat = "WHERE faqcat = " . $dbr->quote($faqcat) if defined $faqcat;
    } else {
        $wherecat = "WHERE faqcat "
            . (defined $faqcat && length $faqcat ? "= " . $dbr->quote($faqcat) : "!= ''");
    }

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $sth;
    if ($lang eq $LJ::DEFAULT_LANG) {
        $sth = $dbr->prepare
            ("SELECT faqid, question, summary, answer, faqcat, lastmoduserid, ".
             "DATE_FORMAT(lastmodtime, '%M %D, %Y') AS lastmodtime, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq $wherecat");

    } else { # Don't load fields that lang_update_in_place will overwrite.
        $sth = $dbr->prepare
            ("SELECT faqid, faqcat, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq $wherecat");
    }
    $sth->execute;
    die $sth->errstr if $sth->err;

    my @faqs;
    while (my $f = $sth->fetchrow_hashref) {
        push @faqs, $class->new(%$f);
    }

    # FIXME: shouldn't that be the root language of the faq domain instead?
    if ($lang ne $LJ::DEFAULT_LANG) {
        $class->lang_update_in_place($lang => @faqs);
    }

    return @faqs;
}

sub faqid {
    my $self = shift;
    return $self->{faqid};
}
*id = \&faqid;

sub lang {
    my $self = shift;
    return LJ::Lang::get_lang($self->{lang}) ? $self->{lang} : $LJ::DEFAULT_LANG;
}

sub question_raw {
    my $self = shift;
    return $self->{question};
}

sub question_html {
    my $self = shift;
    return LJ::ehtml($self->{question});
}

sub summary_raw {
    my $self = shift;
    return $self->{summary};
}

sub summary_html {
    my $self = shift;
    return LJ::ehtml($self->{summary});
}

sub answer_raw {
    my $self = shift;
    return $self->{answer};
}

sub answer_html {
    my $self = shift;
    return LJ::ehtml($self->{answer});
}

sub faqcat {
    my $self = shift;
    return $self->{faqcat};
}

sub lastmoduserid {
    my $self = shift;
    return $self->{lastmoduserid};
}

sub lastmodtime {
    my $self = shift;
    return $self->{lastmodtime};
}

sub unixmodtime {
    my $self = shift;
    return $self->{unixmodtime};
}

sub sortorder {
    my $self = shift;
    return $self->{sortorder};
}

sub url {
    my ($class, $faqid) = @_;
    $faqid = $class->{faqid} if ref $class;
    return "$LJ::SITEROOT/support/faqbrowse?faqid=$faqid";
}

sub url_full {
    my ($class, $faqid) = @_;
    $faqid = $class->{faqid} if ref $class;
    return "$LJ::SITEROOT/support/faqbrowse?faqid=$faqid&view=full";
}

# <LJFUNC>
# name: LJ::Faq::has_summary
# class: general
# des: Tests whether instance has a summary
# args:
# returns: True value if instance has a summary, false value otherwise
# </LJFUNC>
sub has_summary {
    my $self = shift;
    # Translators can't save empty strings, so "-" means "empty" too.
    return !($self->summary_raw eq "" || $self->summary_raw eq "-");
}

# <LJFUNC>
# name: LJ::Faq::lang_update_in_place
# class: general
# des: Fill in question, summary and answer from database for one or more FAQs.
# info: May be called either as a class method or an object method, ie:
#       - $self->lang_update_in_place;
#       - LJ::Faq->lang_update_in_place($lang, @faqs);
# args: lang?, faqs?
# des-lang: Language to fetch strings for (as a class method).
# des-faqs: Array of LJ::Faq objects to fetch strings for (as a class method).
# returns: True value if successful.
# </LJFUNC>
sub lang_update_in_place {
    my $class = shift;

    my ($lang, @faqs);
    if (ref $class) {
        $lang = $class->{lang};
        @faqs = ($class);
        croak ("superfluous parameters") if @_;
    } else {
        $lang = shift;
        @faqs = @_;
        croak ("invalid parameters") if grep { ref $_ ne 'LJ::Faq' } @faqs;
    }

    my $faqd = LJ::Lang::get_dom("faq");
    my $l = LJ::Lang::get_lang($lang) || LJ::Lang::get_lang($LJ::DEFAULT_LANG);
    croak ("missing domain") unless $faqd;
    croak ("invalid language: $lang") unless $l;

    my @load;
    foreach (@faqs) {
        push @load, "$_->{faqid}.1question";
        push @load, "$_->{faqid}.3summary";
        push @load, "$_->{faqid}.2answer";
    }

    my $res = LJ::Lang::get_text_multi($l->{'lncode'}, $faqd->{'dmid'}, \@load);
    foreach (@faqs) {
        my $id = $_->{faqid};
        $_->{question} = $res->{"$id.1question"} if $res->{"$id.1question"};
        $_->{summary}  = $res->{"$id.3summary"}  if $res->{"$id.3summary"};
        $_->{answer}   = $res->{"$id.2answer"}   if $res->{"$id.2answer"};

        $_->{summary}  = $LJ::_T_FAQ_SUMMARY_OVERRIDE if $LJ::_T_FAQ_SUMMARY_OVERRIDE;

        # FIXME?: the join can probably be avoided, eg by using something like
        # LJ::Lang::get_chgtime_unix for time of last change and a single-table
        # "SELECT userid FROM ml_text WHERE t.lnid=? AND t.dmid=? AND t.itid=?
        # ORDER BY t.txtid DESC LIMIT 1" for userid.
        my $itid = LJ::Lang::get_itemid($faqd->{'dmid'}, "$id.2answer");
        if ($itid) {
            my $sql = "SELECT DATE_FORMAT(l.chgtime, '%Y-%m-%d'), t.userid " .
                "FROM ml_latest AS l, ml_text AS t WHERE l.dmid = t.dmid AND l.lnid = t.lnid AND l.itid = t.itid " .
                "AND l.lnid=? AND l.dmid=? AND l.itid=? ORDER BY t.txtid DESC LIMIT 1";

            my $dbr = LJ::get_db_reader()
                or die "Unable to contact global reader";
            my $sth = $dbr->prepare($sql);
            $sth->execute($l->{'lnid'}, $faqd->{'dmid'}, $itid);
            die $sth->errstr if $sth->err;
            @{$_}{'lastmodtime', 'lastmoduserid'} = $sth->fetchrow_array;
        }
    }

    return 1;
}

# <LJFUNC>
# name: LJ::Faq::render_in_place
# class: general
# des: Render one or more FAQs by expanding FAQ-specific mark-up.
# info: May be called either as a class method or an object method, ie:
#       - $self->render_in_place;
#       - LJ::Faq->render_in_place($lang, @faqs);
#       Note that username, journalurl, and journalurl:* aren't expanded here.
# args: opts, faqs?
# des-opts: Hashref (not hash) of options:
#           - lang => language to render FAQs in (as a class method).
#           - skipfaqs => true to skip [[faqtitle:#]] markup.
#           - user => what to expand [[username]] to.
#           - url => what to expand [[journalurl]] to.
# des-faqs: Array of LJ::Faq objects to render (as a class method).
# returns: True value if successful.
# </LJFUNC>
sub render_in_place {
    my ($class, $opts, @faqs) = @_;

    my $lang;
    if (ref $class) {
        $lang = $class->{lang};
        croak ("superfluous parameters") if @faqs;
        @faqs = ($class);
    } else {
        $lang = delete $opts->{"lang"};
        croak ("invalid parameters") if grep { ref $_ ne 'LJ::Faq' } @faqs;
    }
    my $user = delete $opts->{"user"};
    my $user_url = delete $opts->{"url"};
    my $skipfaqs = delete $opts->{"skipfaqs"};
    croak("unknown parameters: " . join(", ", keys %$opts))
        if %$opts;

    # (letter => ["name", mandatory])
    my %dom_data = (g => ["general", 1], f => ["faq", 1], w => ["widget", 0]);
    my %dom = ();
    my %load = ();
    while (my ($k, $d) = each %dom_data) {
        my ($n, $m) = @$d;
        $dom{$k} = LJ::Lang::get_dom($n) or $m && croak("missing $n domain");
        $load{$k} = [];
    }

    my $l = LJ::Lang::get_lang($lang) || LJ::Lang::get_lang($LJ::DEFAULT_LANG);
    croak ("invalid language: $lang") unless $l;

    my %seen;
    # Collect item codes: \[\[faqtitle:\d+\]\], \[\[[gfw]mlitem:[\w/.-]+\]\]
    my $collect_item_codes = sub {
        my $text = shift;

        unless ($skipfaqs) {
            while ($text =~ /\[\[faqtitle:(\d+)\]\]/g) {
                push @{$load{"f"}}, "${1}.1question"
                    unless $seen{"f:${1}.1question"}++;
            }
        }

        while ($text =~ m!\[\[([gfw])mlitem:([\w/.-]+)\]\]!g) {
            push @{$load{$1}}, $2 unless $seen{"$1:$2"}++;
        }
    };

    foreach my $faq (@faqs) {
        $collect_item_codes->($faq->question_raw);
        $collect_item_codes->($faq->summary_raw) if $faq->has_summary;
        $collect_item_codes->($faq->answer_raw);
    }

    my %res;
    foreach my $k (keys %dom) {
        $res{$k} = LJ::Lang::get_text_multi($l->{'lncode'},
                                            $dom{$k}->{'dmid'},
                                            $load{$k});
    }

    my $err_bad_variable = sub {
        my $var = LJ::ehtml(shift);
        return "<b>[Unknown or improper variable: $var]</b>";
    };

    # Replace a variable like [[var]] or [[var:arg]] with the correct text
    my $replace_var = sub {
        my ($var, $arg, $skipfaqs) = @_;
        if ($var eq "journalurl") {
            return $user_url unless $arg;
            my $u_arg = LJ::load_user($arg)
                or return "<b>[Unknown username: " . LJ::ehtml($arg) . "]</b>";
            return $u_arg->journal_base || $err_bad_variable->("${var}:${arg}");
        } elsif ($var eq "username") {
            return $user unless $arg;
            my $u_arg = LJ::load_user($arg)
                or return "<b>[Unknown username: " . LJ::ehtml($arg) . "]</b>";
            return $u_arg->user || $err_bad_variable->("${var}:${arg}");
        } elsif ($arg && $var eq "faqtitle") {
            return $skipfaqs ? "[[faqtitle:$arg]]"
                : (LJ::ehtml($res{"f"}->{"${arg}.1question"})
                    || "<b>[Unknown FAQ id: " . LJ::ehtml($arg) . "]</b>");
        } elsif ($arg && $var =~ /^([gfw])mlitem$/) {
            # ML item (gfw = general/FAQ/widget)
            return $res{$1}->{$arg}
                || "<b>[Unknown item code: " . LJ::ehtml($arg)
                    . " in domain " . LJ::ehtml($dom_data{$1}->[0]) . "]</b>";
        } else {
            # Error
            return $err_bad_variable->($arg ? "${var}:${arg}" : $var);
        }
    };

    # Change [[faqtitle:id]] to the FAQ id's title/question unless $skipfaqs
    # Change [[(g|f|w)mlitem:code]] to that item's text in general/faq/widget
    my $replace_all_vars = sub {
        my ($text, $skipfaqs) = @_;
        $text =~ s!\[\[(\w+)(?::([\w/.-]+?))?\]\]!$replace_var->($1, $2, $skipfaqs)!eg;
        return $text;
    };

    foreach my $faq (@faqs) {
        $faq->{question} = $replace_all_vars->($faq->question_raw, 1);
        $faq->{summary} = $replace_all_vars->($faq->summary_raw, $skipfaqs)
            if $faq->has_summary;
        $faq->{answer} = $replace_all_vars->($faq->answer_raw, $skipfaqs);
    }

    return 1;
}

# <LJFUNC>
# name: LJ::Faq::load_matching
# class: general
# des: Finds all FAQs containing a search term and ranks them by relevance.
# args: term, opts?
# des-term: The string to search for (case-insensitive).
# des-opts: Hash of option key => value.
#           - lang => language to render FAQs in.
#           - user => what to expand [[username]] to.
#           - url => what to expand [[journalurl]] to.
# returns: A list of LJ::Faq objects matching the search term, sorted by
#          decreasing relevance.
# </LJFUNC>
sub load_matching {
    my $class = shift;
    my $term = shift;
    croak ("search term required") unless length($term . "");

    my %opts = @_;
    my $lang = delete $opts{"lang"} || $LJ::DEFAULT_LANG;
    my $user = delete $opts{"user"};
    my $user_url = delete $opts{"url"};
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my @faqs = $class->load_all( lang => $lang, allow_no_cat => 0 );
    die "unable to load faqs" unless @faqs;

    my %scores  = (); # faqid => score
    my @results = (); # array of faq objects

    # Render FAQs, leaving [[faqtitle:#]] intact. This is to let users search
    # for user interface strings without FAQ titles getting in the way.
    # FIXME: This also expands [[username(:foo)?]] and [[journalurl(:bar)?]].
    # Should it?
    $class->render_in_place({skipfaqs => 1, lang => $lang, user => $user, url => $user_url}, @faqs)
        or die "initial FAQ rendering failed";

    foreach my $f (@faqs) {
        my $score = 0;

        $score += 3 if $f->question_raw =~ /\Q$term\E/i;
        $score += 5 if $f->question_raw =~ /\b\Q$term\E\b/i;

        $score += 2 if $f->summary_raw =~ /\Q$term\E/i;
        $score += 4 if $f->summary_raw =~ /\b\Q$term\E\b/i;

        $score += 1 if $f->answer_raw =~ /\Q$term\E/i;
        $score += 3 if $f->answer_raw =~ /\b\Q$term\E\b/i;

        next unless $score;

        $scores{$f->{faqid}} = $score;

        push @results, $f;
    }

    return sort { $scores{$b->{faqid}} <=> $scores{$a->{faqid}} } @results;
}

1;
