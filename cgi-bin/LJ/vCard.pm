package LJ::vCard;

use strict;

use base 'Text::vCard';
use MIME::Base64;

sub new {
    my $class = shift;

    my $remote = LJ::get_remote();

    return $class->new_remote( $remote, @_ );
}

sub new_remote {
    my $class = shift;

    my $remote = shift;
    my $u = shift;

    my $upic = $u->userpic;
    my $file = $upic ? $upic->imagedata : undef;

    my $vcard = $class->SUPER::new;
    $vcard->UID("$LJ::DOMAIN-uid-$u->{userid}");
    $vcard->add_node({ 'node_type' => 'ADR', });
    $vcard->add_node({ 'node_type' => 'N', });
    $vcard->EMAIL($u->email_visible($remote));
    $vcard->NICKNAME($u->{user});
    $vcard->URL($u->journal_base . "/");

    $u->preload_props(qw(city state zip country
                         aolim icq yahoo msn jabber google_talk skype gizmo));


    my $node;

    if ($file) {
        $node = $vcard->add_node({
            'node_type' => 'PHOTO;BASE64',
        });
        my $photo = encode_base64($file);
        my $enphoto = "\n " . join("\n ", split(/\n/, $photo));
        $node->{value} = $enphoto;
    }

    if ($u->share_contactinfo($remote)) {
        my @chats = qw(aolim icq yahoo msn jabber google_talk skype gizmo);
        foreach my $c (@chats) {
            my $field = uc $c;
            $field =~ s/_//g;
            $field = "AIM" if $c eq "aolim";
            my $value = $u->prop($c)
                or next;
            $node = $vcard->add_node({
                'node_type' => "X-$field;type=WORK;type=pref",
            });
            $node->{value} = $value;
        }
    }

    my $bday = $u->bday_string;
    if ($bday && $u->can_show_full_bday) {
        $bday = "0000-$bday" unless $bday =~ /\d\d\d\d/;
        $node = $vcard->add_node({
            'node_type' => 'BDAY;value=date',
        });
        $node->{value} = $bday;
    }

    $node= $vcard->add_node({
        'node_type' => 'X-RSS',
    });
    $node->{value} = $u->journal_base . "/data/rss";

    # Setting values on an address element
    #$node->[0]->street('123 Fake');
    if ($u->can_show_location) {
        $node = $vcard->get({ 'node_type' => 'addresses' });

        $node->[0]->city($u->prop('city'));
        $node->[0]->region($u->prop('state'));
        $node->[0]->post_code($u->prop('zip'));
        $node->[0]->country($u->prop('country'));
    }

    $node = $vcard->get({ 'node_type' => 'name' });

    #$node->[0]->family('Aker');
    $node->[0]->given($u->{name});

    return $vcard;
}

package LJ::vCard::Addressbook;

use base 'Text::vCard::Addressbook';

sub add {
    my $self = shift;
    my $vcards = $self->vcards;

    push @$vcards, @_;
}

1;
