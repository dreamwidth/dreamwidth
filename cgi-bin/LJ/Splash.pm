package LJ::Splash;

use strict;
use warnings;

use base 'Splash::Server';

use Digest::SHA1;
use DateTime;

use Splash;
use Splash::User;
use Splash::Blog;
use Splash::Album;
use Splash::Entry;
use Splash::Comment;

sub new {
    my $class = shift;
    my $self = bless {}, (ref $class || $class);
    return $self;
}

sub user {
    my $self = shift;

    my $u = $self->{u};

    my $userid = $u->{userid};
    my $jtype = $u->{journaltype};
    my $type = ($jtype eq 'P') ? 'paid' : 'free';
    
    return Splash::User->new( {
        id  => $userid,
        type => $type,
        quota   => 100,
        subscriptions   => [ $self->subscriptions ],
        remotes => [ $self->remotes ],
    } );
}

sub changes {
    my $self = shift;
    my ($blog, $max, $timestamp, $viewpassword) = @_;

    my $ts = DateTime->now;
    my @blogs = $self->blogs();
    my @albums = $self->albums();
    my @entries = $self->entries();
    my @comments = $self->comments();
    return "${ts}Z", \@blogs, \@albums, \@entries, \@comments;
}

sub subscriptions {
    my $self = shift;
    my $u = $self->{u};
    return $u->{user};
}

sub remotes {
    my $self = shift;
    my $u = $self->{u};
    return ();
}

sub blogs {
    my $self = shift;
    my $blogs = $self->{blogs} = {};
    my @return;
    foreach my $sub ($self->subscriptions) {
        my $subusr = LJ::load_user( $sub );
        $blogs->{$sub} = $subusr;
        push @return, Splash::Blog->new( {
            name        => $subusr->{user},
            lastmod     => '2005-03-21T17:08:15Z',
            title       => "Long title $subusr->{user}",
            subtitle    => "Subtitle $subusr->{user}",
            type        => 'normal',
            visibility  => 'normal',
            writable    => 'yes',
            commentable => 'yes',
            ownerid     => $subusr->{userid},
        } );
    }
    return @return;
}

sub albums {
    my $self = shift;
    my $blogs = $self->{blogs};
    my $albums = $self->{albums} = {};
    my @return;
    while (my ($blogname, $blog) = each %$blogs) {
        $albums->{$blogname} = $blog;
        push @return, Splash::Album->new( {
            id      => $blog->{userid},
            lastmod => '2005-03-21T17:08:15Z',
            name    => $blog->{user},
            uri     => $blog->journal_base,
        } );
    }
    return @return;
}

sub entries {
    my $self = shift;
    # This is horribly inefficient, but I'd rather just get it over with.
    my @options = ( $self->{maxentries} ? ( count => $self->{maxentries} ) : () );
    my $entries = $self->{entries} = [];
    my $albums = $self->{albums};
    my @return;
    while( my ($albumname, $album) = each %$albums) {
        foreach my $entry ($album->recent_entries( @options )) {
            push @$entries, $entry;
            push @return, Splash::Entry->new( {
                deleted     => 0,
                id          => $entry->ditemid,
                albumid     => $entry->journalid,
                userid      => $entry->posterid,
                lastmod     => '2005-03-21T17:08:15Z',
                title       => $entry->subject_text,
                caption     => 'Caption',
                byline      => 'Byline',
                original    => $album->userpic->url,
                medium      => $album->userpic->url,
                thumbnail   => $album->userpic->url,
                postdate    => '2005-03-21T17:08:15Z',
                photodate   => '2005-03-21T17:08:15Z',
            } );
        }
    }
    return @return;
}

sub comments {
    my $self = shift;

    my $entries = $self->{entries};
    my @return;

    foreach my $entry (@$entries) {
        foreach my $comment (LJ::Talk::load_comments( LJ::load_user( $entry->journalid ), $self->{u}, 'L', $entry->jitemid, { flat => 1 } )) {
            push @return, Splash::Comment->new( {
                deleted     => 0,
                id          => $comment->{talkid},
                lastmod     => $comment->{datepost},
                entryid     => $entry->ditemid,
                userid      => $comment->{posterid},
                byline      => $comment->{posterid},
                timestamp   => $comment->{datepost},
                text        => $comment->{body},
            } );
        }
    }
    return @return;
}

sub checkauth {
    my $self = shift;
    my ($user, $ctime, $nonce, $digest) = @_;

    die "No username passed in\n" unless $user;
    die "No creation timestamp passed in\n" unless $ctime;
    die "No nonce passed in\n" unless $nonce;
    die "No digest passed in\n" unless $digest;

    my $cdigest = Digest::SHA1::sha1( $nonce . $ctime . $self->getpassword( $user ) );
    die "Login failure" unless $digest eq $cdigest;

    LJ::User->set_remote( $self->{u} );
    return;
}

sub getpassword {
    my $self = shift;
    my $user = shift;

    my ($ljusername) = $user =~ m/^(\S+)\@livejournal\.com$/i;
    die "Not an LJ user" unless $ljusername;
    die "Improper LJ username" unless LJ::canonical_username( $ljusername );

    my $dbr = LJ::get_db_reader()
        or die "LJ database system failure";

    my $u = $self->{u} = LJ::load_user( $ljusername );

    die "Nonexistant user" unless( $u );

    die "Login IP banned" if (LJ::login_ip_banned( $u ));

    return $u->password;
}

sub delete_category {
    my $self = shift;
    return;
}

sub add_photo {
    my $self = shift;
    my ($blogid, $categoryid, $title, $caption, $postdate, $picturedate, $jpegdata) = @_;

    my $u = $self->{u};
    my $errstr;
    
    my $fb_result = LJ::FBUpload::do_upload(
        $u, \$errstr,
        {
            path    => '/foo/img.jpg',
            rawdata => \$jpegdata,
            imgsec  => '',
            galname => '',
            caption => $caption,
            title   => $title,
        },
    );

    my $fb_html = LJ::FBUpload::make_html( $u,
        [{
            url => $fb_result->{URL},
            width   => $fb_result->{Width},
            height  => $fb_result->{Height},
            title   => $title,
            caption => $caption,
        }],
        {}
    ); # hashref should be sec options and whatnot.

    my $req = {
        'username'  => $u->{user},
        'ver'       => $LJ::PROTOCOL_VER,
        'subject'   => $title,
        'event'     => $fb_html,
        'tz'        => 'guess',
    };

    my $flags = {
        nopassword => 1,
    };

    my $err;
    my $res = LJ::Protocol::do_request( 'postevent', $req, \$err, $flags );

    my $entry = LJ::Entry->new( $u,
        jitemid => $res->{itemid},
        anum    => $res->{anum},
    );
    
    return Splash::Entry->new( {
        deleted     => 0,
        id          => $entry->ditemid,
        albumid     => 234,
        userid      => $u->{userid},
        lastmod     => '2005-03-21T17:08:15Z',
        title       => $title,
        caption     => $caption,
        byline      => $u->{user},
        original    => 'nowhere',
        medium      => 'nowhere',
        thumbnail   => 'nowhere',
        postdate    => '2005-03-21T17:08:15Z',
        photodate   => '2005-03-21T17:08:15Z',
    } );
}

sub delete_photo {
    my $self = shift;
            return;
}

sub delete_comment {
    my $self = shift;
    return;
}

# This subroutine should be used to check and see if the timestamp on the auth request is out of line or not.
sub checkauthtime {
    my $self = shift;
    my $ctime = shift;
    # die "Please check the time on your handheld device" unless $ctimeisgood;
    return;
}

1;
