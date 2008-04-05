use strict;

package LJ::Widget::IPPU::EntrySummary;
use base "LJ::Widget::IPPU";

sub render_body {
    my ($class, %opts) = @_;

    my $remote = LJ::get_remote();

    my $u = LJ::load_userid($opts{journalid});
    my $ditemid = $opts{ditemid};
    my $jitemid = $opts{jitemid};

    return "No entry specified" unless $u && ($ditemid xor $jitemid);

    my $entry = LJ::Entry->new($u, jitemid => $jitemid, ditemid => $ditemid);

    return "Invalid entry" unless $entry->valid;
    return "You do not have permission to view this entry" unless $entry->visible_to($remote);

    my $poster = $entry->poster;
    my $ljuser = $poster->ljuser_display;
    my $name = $poster->name_html;

    my $journaltext = ! LJ::u_equals($poster, $entry->journal) ? " in " . $entry->journal->ljuser_display : '';

    my $time = LJ::ago_text(time() - $entry->logtime_unix);
    my $entrytext = LJ::ehtml($entry->event_text);
    my $subject = $entry->subject_html;

    my $ret = qq {
        <div style="width: 95%; margin-left: auto; margin-right: auto; padding: 3px;">
          <div style="font-weight: bold; font-size: 1.1em;">$subject</div>
          <div style="margin: 3px;">$ljuser ($name)$journaltext @ $time</div>
          <div>
            <textarea readOnly="true" style="width: 95%; height: 10em; margin-left: auto; margin-right: auto;">$entrytext</textarea>
          </div>
          <div style="padding: 5px;">
            <input type="button" id="entrysummary_cancel" value="Close" />
          </div>
        </div>
    };

    return $ret;
}

1;
