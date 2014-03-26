package App::CreateSelfSignedSSL;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Expect;
#use File::chdir;
use File::Temp;
use Log::Any::For::Builtins qw(system);
use Perinci::CmdLine;
use SHARYANTO::Proc::ChildError qw(explain_child_error);
use String::ShellQuote;

sub sq { shell_quote($_[0]) }

# VERSION

our %SPEC;

$SPEC{create_self_signed_ssl_cert} = {
    v => 1.1,
    args => {
        hostname => {
            schema => ['str*' => match => qr/\A\w+(\.\w+)*\z/],
            req => 1,
            pos => 0,
        },
        ca => {
            summary => 'path to CA cert file',
            schema => ['str*'],
        },
        ca_key => {
            summary => 'path to CA key file',
            schema => ['str*'],
        },
        interactive => {
            schema => [bool => default => 0],
            cmdline_aliases => {
                i => {},
            },
        },
        wildcard => {
            schema => [bool => default => 0],
            summary => 'If set to 1 then Common Name is set to *.hostname',
            description => 'Only when non-interactive',
        },
    },
    deps => {
        exec => 'openssl',
    },
};
sub create_self_signed_ssl_cert {
    my %args = @_;

    my $h = $args{hostname};

    system("openssl genrsa 2048 > ".sq("$h.key"));
    return [500, "Can't generate key: ".explain_child_error()] if $?;

    my $cmd = "openssl req -new -key ".sq("$h.key")." -out ".sq("$h.csr");
    if ($args{interactive}) {
        system $cmd;
        return [500, "Can't generate csr: ".explain_child_error()] if $?;
    } else {
        my $exp = Expect->spawn($cmd);
        return [500, "Can't spawn openssl req"] unless $exp;
        $exp->expect(
            30,
            [ qr!^.+\[[^\]]*\]:!m ,=> sub {
                  my $exp = shift;
                  my $prompt = $exp->exp_match;
                  if ($prompt =~ /common name/i) {
                      $exp->send("$h\n");
                  } else {
                      $exp->send("\n");
                  }
                  exp_continue;
              } ],
        );
        $exp->soft_close;
    }

    # we can provide options later, but for now let's
    system(join(
        "",
        "openssl x509 -req -days 3650 -in ", sq("$h.csr"),
        " -signkey ", sq("$h.key"),
        ($args{ca} ? " -CA ".sq($args{ca}) : ""),
        ($args{ca_key} ? " -CAkey ".sq($args{ca_key}) : ""),
        ($args{ca} ? " -CAcreateserial" : ""),
        " -out ", sq("$h.crt"),
    ));
    return [500, "Can't generate crt: ".explain_child_error()] if $?;

    system("openssl x509 -noout -fingerprint -text < ".sq("$h.crt").
               "> ".sq("$h.info"));
    return [500, "Can't generate info: ".explain_child_error()] if $?;

    system("cat ".sq("$h.crt")." ".sq("$h.key")." > ".sq("$h.pem"));
    return [500, "Can't generate pem: ".explain_child_error()] if $?;

    system("chmod 400 ".sq("$h.pem"));

    $log->info("Your certificate has been created at $h.pem");

    [200];
}

1;
# ABSTRACT: Create self-signed SSL certificate

=head1 SYNOPSIS

This distribution provides command-line utility called
L<create-self-signed-ssl-cert>.

=cut
