package TheSchwartz::Worker::NotifyPingbackServer;
use strict;
use base 'TheSchwartz::Worker';
use LWP::UserAgent qw();
use HTTP::Request  qw();
use JSON;


sub work {
    my ($class, $job) = @_;
    my $args = $job->arg;
    my $client = $job->handle->client;
    my $res = eval {
        send_ping(uri  => $args->{uri},
                  text => $args->{text},
                  mode => $args->{mode},
                  );
    };
    $job->completed if $res;

}

sub send_ping {
    my %args = @_;

    my $uri  = $args{uri};
    my $text = $args{text};
    my $mode = $args{mode};
    
    my $pb_server_uri = $LJ::PINGBACK->{uri};
    my $content = JSON::objToJson({ uri => $uri, text => $text, mode => $mode }) . "\r\n";

    my $headers = HTTP::Headers->new;
       $headers->header('Content-Length' => length $content);

    my $req = HTTP::Request->new('POST', $pb_server_uri, $headers, $content );
    my $ua  = LWP::UserAgent->new;
    my $res = $ua->request($req);

    return 1 if $res->content eq 'OK';
    return 0;

}




1;
