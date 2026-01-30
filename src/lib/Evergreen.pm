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
# Looks in open-ils.cstore app_settings by default (the main Evergreen database)
# Throws: on file read failure, XML parse failure, or missing required config keys
# ----------------------------------------------

sub get_database_configuration {
    my ($config_file) = @_;
    $config_file ||= '/openils/conf/opensrf.xml';
    
    die "Configuration file not found: $config_file\n" unless -e $config_file;
    
    # Read the XML configuration file (XMLin will die on parse failure)
    my $xml = XML::Simple->new(ForceArray => 0, KeyAttr => []);
    my $config = $xml->XMLin($config_file);
    
    # Navigate to database config - try cstore first, then storage
    my $db_section = _find_database_section($config);
    
    die "Could not find database configuration in opensrf.xml\n" unless $db_section;
    
    # Validate required keys (opensrf.xml uses 'db' and 'pw')
    my @required = qw(host port db user pw);
    for my $key (@required) {
        die "Missing required database config key: $key\n" unless defined $db_section->{$key};
    }
    
    # Extract and normalize database configuration details
    my $db_config = {
        host     => $db_section->{host},
        port     => $db_section->{port},
        name     => $db_section->{db},       # normalize 'db' to 'name'
        user     => $db_section->{user},
        password => $db_section->{pw},       # normalize 'pw' to 'password'
    };
    
    return $db_config;
}

# ----------------------------------------------
# _find_database_section - Locates database config in various possible locations
# ----------------------------------------------

sub _find_database_section {
    my ($config) = @_;
    
    # Try open-ils.cstore (primary database for most operations)
    if ($config->{default} && 
        $config->{default}{apps} && 
        $config->{default}{apps}{'open-ils.cstore'} &&
        $config->{default}{apps}{'open-ils.cstore'}{app_settings} &&
        $config->{default}{apps}{'open-ils.cstore'}{app_settings}{database}) {
        return $config->{default}{apps}{'open-ils.cstore'}{app_settings}{database};
    }
    
    # Try open-ils.storage as fallback
    if ($config->{default} && 
        $config->{default}{apps} && 
        $config->{default}{apps}{'open-ils.storage'} &&
        $config->{default}{apps}{'open-ils.storage'}{app_settings} &&
        $config->{default}{apps}{'open-ils.storage'}{app_settings}{databases} &&
        $config->{default}{apps}{'open-ils.storage'}{app_settings}{databases}{database}) {
        return $config->{default}{apps}{'open-ils.storage'}{app_settings}{databases}{database};
    }
    
    # Try reporter database as another fallback
    if ($config->{default} && 
        $config->{default}{reporter} && 
        $config->{default}{reporter}{setup} &&
        $config->{default}{reporter}{setup}{database}) {
        return $config->{default}{reporter}{setup}{database};
    }
    
    return undef;
}

1; # End of Evergreen.pm