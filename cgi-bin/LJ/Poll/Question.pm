package LJ::Poll::Question;
use strict;
use Carp qw (croak);

sub new {
    my ($class, $poll, $pollqid) = @_;

    my $self = {
        poll    => $poll,
        pollqid => $pollqid,
    };

    bless $self, $class;
    return $self;
}

sub new_from_row {
    my ($class, $row) = @_;

    my $pollid = $row->{pollid};
    my $pollqid = $row->{pollqid};

    my $poll;
    $poll = LJ::Poll->new($pollid) if $pollid;

    my $question = __PACKAGE__->new($poll, $pollqid);
    $question->absorb_row($row);

    return $question;
}

sub absorb_row {
    my ($self, $row) = @_;

    # items is optional, used for caching
    $self->{$_} = $row->{$_} foreach qw (sortorder type opts qtext items);
    $self->{_loaded} = 1;
}

sub _load {
    my $self = shift;
    return if $self->{_loaded};

    croak "_load called on a LJ::Poll::Question object with no pollid"
        unless $self->pollid;
    croak "_load called on a LJ::Poll::Question object with no pollqid"
        unless $self->pollqid;

    my $sth = $self->poll->journal->prepare( 'SELECT * FROM pollquestion2 WHERE pollid=? AND pollqid=? and journalid=?' );
    $sth->execute( $self->pollid, $self->pollqid, $self->poll->journalid );

    $self->absorb_row( $sth->fetchrow_hashref );
}

# returns the question rendered for previewing
sub preview_as_html {
    my $self = shift;
    my $ret = '';

    my $type = $self->type;
    my $opts = $self->opts;

    my $qtext = $self->qtext;
    if ($qtext) {
        LJ::Poll->clean_poll(\$qtext);
          $ret .= "<p>$qtext</p>\n";
      }
    $ret .= "<div style='margin: 10px 0 10px 40px'>";

    # text questions
    if ($type eq 'text') {
        my ($size, $max) = split(m!/!, $opts);
        $ret .= LJ::html_text({ 'size' => $size, 'maxlength' => $max });

        # scale questions
    } elsif ($type eq 'scale') {
        my ($from, $to, $by) = split(m!/!, $opts);
        $by ||= 1;
        my $count = int(($to-$from)/$by) + 1;
        my $do_radios = ($count <= 11);

        # few opts, display radios
        if ($do_radios) {
            $ret .= "<table><tr valign='top' align='center'>\n";
            for (my $at = $from; $at <= $to; $at += $by) {
                $ret .= "<td>" . LJ::html_check({ 'type' => 'radio' }) . "<br />$at</td>\n";
            }
            $ret .= "</tr></table>\n";

            # many opts, display select
        } else {
            my @optlist = ();
            for (my $at = $from; $at <= $to; $at += $by) {
                push @optlist, ('', $at);
            }
            $ret .= LJ::html_select({}, @optlist);
        }

        # questions with items
    } else {
        # drop-down list
        if ($type eq 'drop') {
            my @optlist = ('', '');
            foreach my $it ($self->items) {
                LJ::Poll->clean_poll(\$it->{item});
                  push @optlist, ('', $it->{item});
              }
            $ret .= LJ::html_select({}, @optlist);

            # radio or checkbox
        } else {
            foreach my $it ($self->items) {
                LJ::Poll->clean_poll(\$it->{item});
                  $ret .= LJ::html_check({ 'type' => $self->type }) . "$it->{item}<br />\n";
              }
        }
    }
    $ret .= "</div>";
    return $ret;
}

sub items {
    my $self = shift;

    return @{$self->{items}} if $self->{items};

    my $sth = $self->poll->journal->prepare( 'SELECT pollid, pollqid, pollitid, sortorder, item ' .
                                             'FROM pollitem2 WHERE pollid=? AND pollqid=? AND journalid=?' );
    $sth->execute( $self->pollid, $self->pollqid, $self->poll->journalid );

    die $sth->errstr if $sth->err;

    my @items;

    while (my $row = $sth->fetchrow_hashref) {
        my $item = {};
        $item->{$_} = $row->{$_} foreach qw(pollitid sortorder item pollid pollqid);
        push @items, $item;
    }

    @items = sort { $a->{sortorder} <=> $b->{sortorder} } @items;

    $self->{items} = \@items;

    return @items;
}

# accessors
sub poll {
    my $self = shift;
    return $self->{poll};
}
sub pollid {
    my $self = shift;
    return $self->poll->pollid;
}
sub pollqid {
    my $self = shift;
    return $self->{pollqid};
}
sub sortorder {
    my $self = shift;
    $self->_load;
    return $self->{sortorder};
}
sub type {
    my $self = shift;
    $self->_load;
    return $self->{type};
}
sub opts {
    my $self = shift;
    $self->_load;
    return $self->{opts};
}
*text = \&qtext;
sub qtext {
    my $self = shift;
    $self->_load;
    return $self->{qtext};
}

# Count answers pages
sub answers_pages {
    my $self = shift;
    my $jid = shift;

    my $pagesize = shift || 2000;

    my $pages = 0;

    # Get results count
    my $sth = $self->poll->journal->prepare(
        "SELECT COUNT(*) as count FROM pollresult2".
        " WHERE pollid=? AND pollqid=? AND journalid=?" );
    $sth->execute( $self->pollid, $self->pollqid, $jid );
    die $sth->errstr if $sth->err;
    $_ = $sth->fetchrow_hashref;
    my $count = $_->{count};
    $pages = 1 + int( ($count - 1) / $pagesize );
    die $sth->errstr if $sth->err;

    return $pages;
}

sub answers_as_html {
    my $self = shift;
    my $jid = shift;

    my $page     =  shift || 1;
    my $pagesize =  shift || 2000;

    my $pages = shift || $self->answers_pages($jid, $pagesize);

    my $ret = '';;

    my $LIMIT = $pagesize * ($page - 1) . "," . $pagesize;

    # Get data
    my $sth = $self->poll->journal->prepare(
            "SELECT pr.value, ps.datesubmit, pr.userid " .
            "FROM pollresult2 pr, pollsubmission2 ps " .
            "WHERE pr.pollid=? AND pollqid=? " .
            "AND ps.pollid=pr.pollid AND ps.userid=pr.userid " .
            "AND ps.journalid=? ".
            "LIMIT $LIMIT" );
    $sth->execute( $self->pollid, $self->pollqid, $jid );
    die $sth->errstr if $sth->err;

    my ( $pollid, $pollqid ) = ( $self->pollid, $self->pollqid );

    my @res;
    push @res, $_ while $_ = $sth->fetchrow_hashref;
    @res = sort { $a->{datesubmit} cmp $b->{datesubmit} } @res;

    foreach my $res (@res) {
        my ($userid, $value) = ($res->{userid}, $res->{value}, $res->{pollqid});
        my @items = $self->items;

        my %it;
        $it{$_->{pollitid}} = $_->{item} foreach @items;

        my $u = LJ::load_userid($userid) or die "Invalid userid $userid";

        ## some question types need translation; type 'text' doesn't.
        if ($self->type eq "radio" || $self->type eq "drop") {
            $value = $it{$value};
        } elsif ($self->type eq "check") {
            $value = join(", ", map { $it{$_} } split(/,/, $value));
        }

        LJ::Poll->clean_poll(\$value);
        $ret .= "<div>" . $u->ljuser_display . " -- $value</div>\n";
    }

    return $ret;
}

sub paging_bar_as_html {
    my $self = shift;

    my $page  =  shift      || 1;
    my $pages =  shift      || 1;
    my $pagesize = shift    || 2000;

    my ($jid, $pollid, $pollqid) = @_;

    my $href_opts = sub {
        my $page = shift;
        return  " class='LJ_PollAnswerLink'".
                " lj_pollid='$pollid'".
                " lj_qid='$pollqid'".
                " lj_posterid='$jid'".
                " lj_page='$page'".
                " lj_pagesize='$pagesize'";
    };

    return LJ::paging_bar($page, $pages, { href_opts => $href_opts });
}

sub answers {
    my $self = shift;

    my $ret = '';
    my $sth = $self->poll->journal->prepare( "SELECT userid, pollqid, value FROM pollresult2 " .
                                             "WHERE pollid=? AND pollqid=?" );
    $sth->execute( $self->pollid, $self->pollqid );
    die $sth->errstr if $sth->err;

    my @res;
    push @res, $_ while $_ = $sth->fetchrow_hashref;

    return @res;
}

1;
