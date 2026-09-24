# Native settings unsaved-change confirmation language contract.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use DW::Controller::SettingsHub;

DW::Request->reset;
open my $input, '<', \( my $body = '' ) or die $!;
DW::Request->get(
    plack_env => {
        REQUEST_METHOD    => 'GET',
        PATH_INFO         => '/',
        QUERY_STRING      => '',
        SERVER_NAME       => 'localhost',
        SERVER_PORT       => 80,
        HTTP_HOST         => 'localhost',
        'psgi.version'    => [ 1, 1 ],
        'psgi.url_scheme' => 'http',
        'psgi.input'      => $input,
        'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
    },
);
my @calls;
LJ::Lang::set_request_context(
    lang   => 'fr',
    getter => sub {
        my ( $lang, $code ) = @_;
        push @calls, [ $lang, $code ];
        return q{Enregistrer "maintenant" </script>};
    },
);
my $message = DW::Controller::SettingsHub::_settings_confirm_message();
is_deeply(
    \@calls,
    [ [ 'fr', '/settings/index.tt.form.confirm1' ] ],
    'confirmation uses the physical native settings template key and request language'
);
like(
    $message,
    qr/^"Enregistrer \\"maintenant\\" /,
    'translation is emitted as a quoted JavaScript string'
);
unlike( $message, qr!</script!i, 'translation cannot close the inline script element' );
like(
    $message,
    qr!scri" \+ "pt!i,
    'script terminator is split using the established ejs_string contract'
);
DW::Request->reset;
done_testing;
