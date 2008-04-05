package LJ::Widget::ContentFlagSummary;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::ContentFlag;

sub need_res {
    return qw(
              js/ippu.js
              js/lj_ippu.js
              js/httpreq.js
              stc/contentflag.css
              js/ljwidget_ippu.js
              js/widget_ippu/contentflagreporters.js
              js/widget_ippu/entrysummary.js
              );
}

sub ajax { 1 }

sub should_render {
    my $remote = LJ::get_remote();
    return $remote && $remote->can_admin_content_flagging ? 1 : 0;
}


my %catnames    = (%LJ::ContentFlag::CAT_NAMES);
my %statusnames = (%LJ::ContentFlag::STATUS_NAMES);

my @actions = (
               LJ::ContentFlag::NEW             => 'New',
               LJ::ContentFlag::CLOSED          => 'Bogus Report (No Action)',
               '', '',
               LJ::ContentFlag::FLAG_EXPLICIT_ADULT => 'Flag > Explicit Adult Content',
               LJ::ContentFlag::FLAG_HATRED         => 'Flag > Hate Speech',
               LJ::ContentFlag::FLAG_ILLEGAL        => 'Flag > Illegal Activity',
               LJ::ContentFlag::FLAG_CHILD_PORN     => 'Flag > Nude Images of Minors',
               LJ::ContentFlag::FLAG_SELF_HARM      => 'Flag > Self Harm',
               LJ::ContentFlag::FLAG_SEXUAL         => 'Flag > Sexual Content',
               LJ::ContentFlag::FLAG_OTHER          => 'Flag > Other',
               );

my %fieldnames = (
                  instime    => 'Reported',
                  journalid  => 'Reported User',
                  catid      => 'Most Frequent Type',
                  reporterid => 'Reporters',
                  status     => 'Status',
                  modtime    => 'Touched Time',
                  itemid     => 'Report Type',
                  action     => 'Resolve',
                  open_request => 'Open Abuse Request?',
                  _count     => 'Freq',
                  );

my %sortopts = (
                count   => "Frequency",
                instime => "Time",
                );

# creates the form that allows the user to filter to various states
sub filter_switcher {
    my $class = shift;
    my %opts = @_;

    my $ret;
    $ret .= '<p><form action="">';
    $ret .= "<b>Type</b>: ";
    $ret .= LJ::html_select({ name => 'catid', selected => $opts{catid} },
                            ( "" => "All Types", %catnames));

    $ret .= " <b>Status</b>: ";
    $ret .= LJ::html_select({ name => 'status', selected => $opts{status} }, %statusnames);

    $ret .= " <b>Sort by</b>: ";
    $ret .= LJ::html_select({ name => 'sort', selected => $opts{sort} }, %sortopts);

    $ret .= LJ::html_submit();

    my $num = LJ::ContentFlag->locked_flags;
    $ret .= " <small>($num reports locked)</small>";
    $ret .= '</form></p>';

    return $ret;
};

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret = $class->filter_switcher(%opts);

    my $sort = $opts{sort} || 'count';
    $sort =~ s/\W//g;
    my @flags = LJ::ContentFlag->load(status => $opts{status}, catid => $opts{catid}, group => 1, sort => $sort, lock => 1, limit => 25);

    unless (@flags) {
        $ret .= "<?standout No matches! :) standout?>";
        return $ret;
    }

    $ret .= $class->start_form;
    $ret .= "<div>";
    $ret .= $class->html_hidden('status' => $opts{status}, catid => $opts{catid});

    # format fields for display
    my $remote = LJ::get_remote();
    my %fields = (
                  instime => sub {
                      LJ::ago_text(time() - shift());
                    },
                  modtime => sub {
                      my $time = shift;
                      return $time ? LJ::ago_text(time() - $time) : "Never";
                    },
                  journalid => sub {
                      LJ::ljuser(LJ::load_userid(shift()));
                    },
                  itemid => sub {
                      my ($id, $flag) = @_;
                      my $typeid = $flag->{typeid};

                      my ($popup, $text, $jsclass);

                      if ($typeid == LJ::ContentFlag::ENTRY) {
                          my $entry = $flag->item;
                          return "Deleted" unless $entry && $entry->valid;
                          $jsclass = "ctflag_item";
                          $text = "Entry [" . ($entry->subject_text || 'no subject') . "]";
                          $popup = $entry->visible_to($remote) ? $entry->event_text : "[Private entry]";
                      }

                      if ($typeid == LJ::ContentFlag::COMMENT) {
                          my $cmt = $flag->item;
                          return "Deleted" unless $cmt && $cmt->valid;
                          $text = "Comment [" . ($cmt->subject_text || 'no subject') . "]";
                          $popup = $cmt->visible_to($remote) ? $cmt->body_text : "[Private comment]";
                      }

                      if ($typeid == LJ::ContentFlag::PROFILE) {
                          $text = "Profile";
                      }

                      if ($typeid == LJ::ContentFlag::JOURNAL) {
                          $text = "Journal";
                      }

                      my $url = $flag->url;
                      my $journalid = $flag->journalid;

                      return qq {
                          <div class="standout-border standout-background $jsclass" style="cursor: pointer;"
                            lj_itemid="$id" lj_journalid="$journalid">
                                <a href="$url"><img src="$LJ::IMGPREFIX/link.png" /></a>
                                $text
                          </div>
                      };
                  },
                  reporterid => sub {
                      my ($reporter, $flag) = @_;

                      my $journalid = $flag->journalid;
                      my $typeid = $flag->typeid;
                      my $itemid = $flag->itemid;
                      my $catid = $flag->catid;

                      return "<div class='standout-border standout-background ctflag_reporterlist' style='cursor: pointer;' " .
                          "lj_itemid='$itemid' lj_catid='$catid' lj_journalid='$journalid' lj_typeid='$typeid'>View reporters and requests...</div>";
                    },
                  catid => sub {
                      my ($cat, $flag) = @_;

                      my $journalid = $flag->journalid;
                      my $typeid = $flag->typeid;
                      my $itemid = $flag->itemid;

                      my $catid = LJ::ContentFlag->get_most_common_cat_for_flag( journalid => $journalid, typeid => $typeid, itemid => $itemid );
                      return $catnames{$catid} || "??";
                    },
                  status => sub {
                      my $stat = shift;
                      return $statusnames{$stat} || "??";
                    },
                  action => sub {
                      my (undef, $flag) = @_;
                      my $flagid = $flag->flagid;
                      my $actions = $class->html_select(class => "ctflag_action",
                                                        name => "action_$flagid",
                                                        id => "action_$flagid",
                                                        selected => $flag->status,
                                                        lj_itemid => $flagid,
                                                        list => [@actions]);
                      return $actions;
                  },
                  _count => sub {
                      my (undef, $flag) = @_;
                      return $flag->count;
                  },
                  open_request => sub {
                      my (undef, $flag) = @_;
                      my $flagid = $flag->flagid;

                      if (LJ::ContentFlag->requests_exist_for_flag($flag)) {
                          return "<em>(one or more requests exist)</em>";
                      } else {
                          return $class->html_check(
                              name => "openreq_$flagid",
                              id => "openreq_$flagid",
                          );
                      }
                  },
                  );

    my @fields = qw (_count itemid journalid instime reporterid catid);
    my @cols = (@fields, qw(action open_request));
    my $fieldheaders = (join '', (map { "<th>$fieldnames{$_}</th>" } @cols));

    $ret .= qq {
        <table class="alternating-rows ctflag">
            <tr>
            $fieldheaders
            </tr>
    };

    my $i = 1;
    foreach my $flag (@flags) {
        my $n = $i++ % 2 + 1;
        $ret .= "<tr class='altrow$n'>";
        foreach my $field (@cols) {
            my $field_val = (grep { $_ eq $field } @fields) ? $flag->{$field} : '';
            $ret .= "<td>" . $fields{$field}->($field_val, $flag) . '</td>';
        }
        $ret .= '</tr>';
    }

    $ret .= '</table>';
    $ret .= '</div>';

    $ret .= $class->html_hidden('flagids', join(',', map { $_->flagid } @flags));
    $ret .= $class->html_hidden('mode', 'admin');
    $ret .= '<?standout ' . $class->html_submit('Submit Resolutions') . ' standout?>';
    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    die "This feature is disabled"
        if LJ::conf_test($LJ::DISABLED{content_flag});

    my $remote = LJ::get_remote()
        or die "You must be logged in to use this";

    my $getopt = sub {
        my $field = shift;
        my $val = $post->{$field} or die "Required field $field missing";
        return $val;
    };

    my $mode = $getopt->('mode');
    die "Unknown mode: $mode"
        unless $mode eq 'flag' || $mode eq 'admin';

    my $success = 0;
    my %ret = ();

    if ($mode eq 'flag') {
        my @fields = qw (itemid type cat journalid);
        my %opts;
        foreach my $field (@fields) {
            my $val = $getopt->($field);
        }

        $opts{reporter} = $remote;
        my $flag = LJ::ContentFlag->create(%opts);

        $success = $flag ? 1 : 0;
    } elsif ($mode eq 'admin') {
        die "You are not authorized to do this"
            unless $remote->can_admin_content_flagging;

        my $flagids = $getopt->('flagids');
        my @flagids = split(',', $flagids);

        foreach my $flagid (@flagids) {
            die "invalid flagid" unless $flagid+0;

            my $action = $post->{"action_$flagid"} or next;

            my ($flag) = LJ::ContentFlag->load_by_flagid($flagid)
                or die "Could not load flag $flagid";

            # get the other flags for this item
            my @flags = $flag->find_similar_flags(catid => $post->{catid}, status => $post->{status});

            # set the status of the flags
            $_->set_status($action) foreach @flags;

            # mark the journal or entry with the appropriate admin flag (including undef if un-flagging)
            my $admin_flag = LJ::ContentFlag->get_admin_flag_from_status($action);
            my $u = LJ::load_userid($flag->journalid);
            if ($flag->typeid == 3) { # journal
                $u->set_prop( admin_content_flag => $admin_flag );
            } elsif ($flag->typeid == 1) { # entry
                my $entry = LJ::Entry->new($u, ditemid => $flag->itemid);
                $entry->set_prop( admin_content_flag => $admin_flag );
            }

            # open an abuse request if the admin requested one
            if ($post->{"openreq_$flagid"}) {
                LJ::ContentFlag->move_to_abuse($action, @flags);
            }
        }

        LJ::ContentFlag->unlock(@flagids);
    }
}

sub js {

    qq[

    initWidget: function () {
         LiveJournal.addClickHandlerToElementsWithClassName(this.contentFlagItemClicked.bindEventListener(this), "ctflag_item");
         LiveJournal.addClickHandlerToElementsWithClassName(this.reporterListClicked.bindEventListener(this), "ctflag_reporterlist");
    },
    reporterListClicked: function (evt) {
        var target = evt.target;
        if (! target) return true;
        var item = target;

        var itemid = item.getAttribute("lj_itemid");
        var journalid = item.getAttribute("lj_journalid");
        var typeid = item.getAttribute("lj_typeid");
        var catid = item.getAttribute("lj_catid");

        if (! itemid || ! journalid || ! typeid || ! catid) return true;

        var reporterList = new LJWidgetIPPU_ContentFlagReporters({
          title: "Reporters",
          nearElement: target
        }, {
          journalid: journalid,
          typeid: typeid,
          catid : catid,
          itemid: itemid
        });
    },
    contentFlagItemClicked: function (evt) {
         var target = evt.target;
         if (! target) return true;

         if (target.tagName.toLowerCase() == "img") return true; // don't capture events on the link img '

         var item = target;
         var itemid = item.getAttribute("lj_itemid");
         var journalid = item.getAttribute("lj_journalid");
         if (! itemid || ! journalid) return true;

         var reporterList = new LJWidgetIPPU_EntrySummary({
           title: "Entry Summary",
           nearElement: target
           }, {
             journalid: journalid,
             ditemid: itemid
           });

         Event.stop(evt);
         return false;
     },
     onData: function (data) {

     },
     onError: function (err) {

     },
     onRefresh: function (data) {
         this.initWidget();
     }
    ];
}

1;
