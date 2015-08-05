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

package LJ::Poll::Question;
use strict;
use Carp qw (croak);


### I don't quite see why I should need to do the use here, but it does
### seem to be necessary - asb
use LJ::Poll::Question::CheckBox;
use LJ::Poll::Question::RadioButton;
use LJ::Poll::Question::MultiChoice;
use LJ::Poll::Question::Scale;
use LJ::Poll::Question::DropDown;
use LJ::Poll::Question::Text;


our %ALLOWED_TYPES = (
    check => "LJ::Poll::Question::CheckBox",
    text  => "LJ::Poll::Question::Text",
    radio => "LJ::Poll::Question::RadioButton",
    drop  => "LJ::Poll::Question::DropDown",
    scale => "LJ::Poll::Question::Scale",
);


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
    $self->blessme;
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


sub blessme {
    my $self = shift;
    my $class = ref($self);
    my $type = $self->{type} or warn "No type found! Defaulting to 'text'"; $type ||= "text";
    my $newclass = $ALLOWED_TYPES{$type} or die "Unknown type '$type'!";

    bless $self, $newclass;
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
    $ret .= $self->previewing_snippet_preamble(); # handled by subclasses!
    $ret .= "<div style='margin: 10px 0 10px 40px'>";
    $ret .= $self->previewing_snippet(); # handled by subclasses!
    $ret .= "</div>";
    return $ret;
}

sub show_individual_result{
    

    
    my ($self, $preval) = @_;
    my $ret = '';
    my $qid = $self->pollqid;

    my $usersvoted = 0;
    my %itvotes;
    my $maxitvotes = 1;


               ### but, if this is a non-text item, and we're showing results, need to load the answers:
    my $sth = $self->poll->journal->prepare( "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?" );
    $sth->execute( $self->pollid, $qid, $self->poll->journalid );
    while (my ($val) = $sth->fetchrow_array) {
        $usersvoted++;
        for ($self->decompose_votes($val)) {
                $itvotes{$_}++;
        }
    }

    foreach (values %itvotes) {
        $maxitvotes = $_ if ($_ > $maxitvotes);
    }
    return $ret;
}

################# MAINLY STUBS #####################
sub dotable_flag{0}
sub decompose_votes{my ($self,$val) = @_; return $val }
sub has_sub_items {0}
sub previewing_snippet_preamble { return '' } # not needed in most cases.
sub process_tag_options {     # subclassed in some cases
    my ($opts, $qopts,$err) = @_; 
    return $qopts 
}
sub get_summary_stats{ #Subclassed in Scale
    return(undef,undef,undef,undef)
}
sub is_valid_answer {1}
sub display_result {croak("This needs to be subclassed in package " , ref(shift)) }

############END STUBS#################

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
    return $self->{opts} || '';
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
    my $isanon = shift;

    my $page     =  shift || 1;
    my $pagesize =  shift || 2000;

    my $pages = shift || $self->answers_pages($jid, $pagesize);

    my $ret = '';;

    my $LIMIT = $pagesize * ($page - 1) . "," . $pagesize;

    my $uid_map = {};
    if ( $isanon eq "yes" ) {
        if ( $self->{_uids} ) {
            $uid_map = $self->{_uids};
        } else {
            # get user list
            my $uids = $self->poll->journal->selectcol_arrayref(
                "SELECT userid from pollsubmission2 WHERE pollid=? AND journalid=?",
                undef, $self->pollid, $jid
            );
            my $i = 0;
            $uid_map = { map { $_ => ++$i } @{$uids || [] } };
            $self->{_uids} = $uid_map;
        }
    }

    # Get data
    my $sth = $self->poll->journal->prepare(
            "SELECT pr.value, ps.datesubmit, pr.userid " .
            "FROM pollresult2 pr, pollsubmission2 ps " .
            "WHERE pr.pollid=? AND pollqid=? " .
            "AND ps.pollid=pr.pollid AND ps.userid=pr.userid " .
            "AND ps.journalid=? ".
            "ORDER BY ps.datesubmit " .
            "LIMIT $LIMIT" );
    $sth->execute( $self->pollid, $self->pollqid, $jid );
    die $sth->errstr if $sth->err;

    my ( $pollid, $pollqid ) = ( $self->pollid, $self->pollqid );

    my @res;
    push @res, $_ while $_ = $sth->fetchrow_hashref;
    @res = sort { $a->{datesubmit} cmp $b->{datesubmit} } @res;
    
    for my $res (@res) {
        my ($userid, $value) = ($res->{userid}, $res->{value}, $res->{pollqid});
        my @items = $self->items;

        my %it;
        $it{$_->{pollitid}} = $_->{item} for @items;

        my $u = LJ::load_userid($userid) or die "Invalid userid $userid";

        ## some question types need translation; type 'text' doesn't.
        $value = $self->translate_individual_answer($value, \%it);
        LJ::Poll->clean_poll(\$value);
        my $user_display = $isanon eq "yes" ? "User <b>#" . $uid_map->{$userid} . "</b>" : $u->ljuser_display;

        $ret .= "<div>" . $user_display . " -- $value</div>\n";
    }

    return $ret;
}
        
sub translate_individual_answer {
    my ($self, $value, $items) = @_;
    return ref($self) . $value; # this is subclassed for anything more complicated.
}








#returns how a user answered this question
sub user_answer_as_html {
    my $self = shift;
    my $userid = shift;
    my $isanon = shift;

    my $ret = '';

    # Get data
    my $sth = $self->poll->journal->prepare(
        "SELECT value FROM pollresult2 " .
        "WHERE pollid=? AND pollqid=? AND userid=? " );

    $sth->execute( $self->pollid, $self->pollqid, $userid );
    die $sth->errstr if $sth->err;

    my ( $pollid, $pollqid ) = ( $self->pollid, $self->pollqid );

    my $qtext = $self->qtext;
    my @res;
    push @res, $_ while $_ = $sth->fetchrow_hashref;

    foreach my $res ( @res ) {
        my $value = $res->{value};
        my @items = $self->items;

        my %it;
        $it{$_->{pollitid}} = $_->{item} foreach @items;

        # some question types need translation; type 'text' doesn't.
        $value = $self->translate_individual_answer($value, \%it);

        LJ::Poll->clean_poll( \$value );
        LJ::Poll->clean_poll( \$qtext );

        $ret .= '<b>' . $qtext . "</b> -- " . $value . "<br/>\n";
    }

    return $ret;
}

sub paging_bar_as_html {
    my $self = shift;

    my $page  =  shift      || 1;
    my $pages =  shift      || 1;
    my $pagesize = shift    || 2000;

    my ($jid, $pollid, $pollqid, %opts) = @_;

    my $href_opts = sub {
        my $page = shift;
        # FIXME: this is a quick hack to disable the paging JS on /poll/index since it doesn't work
        # better fix will await another look at that whole area
        return  ( $opts{no_class} ? "" : " class='LJ_PollAnswerLink'" ) .
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
