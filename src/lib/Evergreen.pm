# ----------------------------------------------
# Evergreen.pm - Main module for interacting with Evergreen ILS
# ----------------------------------------------

package Evergreen;

use strict;
use warnings;
use XML::Simple;
use Exporter 'import';

our @EXPORT_OK = qw(get_database_configuration);

# ----------------------------------------------
# get_database_configuration - Extracts database config from Evergreen XML config file
# Throws: on file read failure, XML parse failure, or missing required config keys
# ----------------------------------------------

sub get_database_configuration {
    my ($config_file) = @_;
    $config_file ||= '/openils/conf/opensrf.xml';
    
    die "Configuration file not found: $config_file\n" unless -e $config_file;
    
    # Read the XML configuration file (XMLin will die on parse failure)
    my $xml = XML::Simple->new;
    my $config = $xml->XMLin($config_file);
    
    # Validate required database configuration
    die "Missing 'database' section in configuration\n" unless $config->{database};
    
    my @required = qw(host port name user password);
    for my $key (@required) {
        die "Missing required database config key: $key\n" unless defined $config->{database}->{$key};
    }
    
    # Extract database configuration details
    my $db_config = {
        host     => $config->{database}->{host},
        port     => $config->{database}->{port},
        name     => $config->{database}->{name},
        user     => $config->{database}->{user},
        password => $config->{database}->{password},
    };
    
    return $db_config;
}