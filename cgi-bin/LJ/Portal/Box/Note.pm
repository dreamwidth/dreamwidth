package LJ::Portal::Box::Note; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'Save a little note for yourself';
our $_box_name = "Note To Self";
our $_box_class = "Note";

our $_prop_keys = { 'note' => 1 };
our $_config_props = {
    'note' => { 'type'    => 'hidden',
                'desc'    => 'Note',
                'default' => ''} };

sub generate_content {
    my $self = shift;
    my $pboxid = $self->pboxid;
    my $note = $self->get_prop('note');

    my $saveRequest = qq{portalboxaction=$pboxid};

    return qq {
        <textarea style="width: 90%; height: 100px; margin-left: auto; margin-right: auto;
display: block;" id="note$pboxid">$note</textarea>
        <input type="button" value="Save" onclick="evalXrequest('$saveRequest&note='+encodeURIComponent(xGetElementById('note$pboxid').value));" /> <span style="display: none" id="statusbox$pboxid"></span>
          };
}

sub handle_request {
    my ($self, $GET, $POST) = @_;
    my $pboxid = $self->pboxid;

    my $enote = LJ::ehtml($POST->{'note'});

    # since props have a maximum length of 255 bytes we must truncate before
    # setting the prop because otherwise the full-length string will be stored
    # in memcache and the truncated string stored in the DB
    $enote = LJ::text_trim($enote, 255, 0);

    $self->set_prop('note', $enote);

    return qq {
        var stat = xGetElementById('statusbox$pboxid');
        if (stat) {
            stat.style.display = "inline";
            stat.innerHTML = "Note saved.";
        }
    };
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }


1;
