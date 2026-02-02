# ----------------------------------------------
# Email.pm - A simple email sending module for Perl scripts
# ----------------------------------------------

package Email;

use strict;
use warnings;
use Email::MIME;
use Email::Sender::Simple 'sendmail';
use Exporter 'import';

our @EXPORT_OK = qw(send_email);

# ----------------------------------------------
# send_email - Sends an email with the specified parameters
# Throws: Email::Sender exception on failure
# ----------------------------------------------

sub send_email {
    my (%params) = @_;
    
    my $to      = $params{to}      || '';
    my $from    = $params{from}    || '';
    my $subject = $params{subject} || 'No Subject';
    my $body    = $params{body}    || '';

    my $email = Email::MIME->create(
        header_str => [
            From    => $from,
            To      => $to,
            Subject => $subject,
        ],
        attributes => {
            content_type => 'text/plain',
            charset      => 'UTF-8',
            encoding     => 'quoted-printable',
        },
        body_str => $body,
    );

    sendmail($email);
}

1; # End of Email.pm