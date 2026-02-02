# ----------------------------------------------
# ConfigFile.pm - A simple configuration file parser for Perl scripts
# ----------------------------------------------

package ConfigFile;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(load_config);

# ----------------------------------------------
# load_config - Loads configuration from a simple key=value file
# Arguments:
#   $file_path - path to the configuration file
# Returns: hashref of configuration values
# Throws: on file read failure or parse errors
# ----------------------------------------------

sub load_config {
    my ($file_path) = @_;
    
    die "No configuration file path provided\n" unless defined $file_path;
    die "Configuration file not found: $file_path\n" unless -e $file_path;
    
    open my $fh, '<', $file_path or die "Cannot open config file '$file_path': $!\n";
    
    my %config;
    my $line_num = 0;
    
    while (my $line = <$fh>) {
        $line_num++;
        chomp $line;
        
        # Skip comments and blank lines
        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;
        
        # Parse key = value (value can be quoted or unquoted)
        if ($line =~ /^\s*(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|(\S+))\s*$/) {
            my ($key, $val) = ($1, defined $2 ? $2 : defined $3 ? $3 : $4);
            $config{$key} = $val;
        }
        else {
            die "Invalid configuration at line $line_num: $line\n";
        }
    }
    
    close $fh;
    return \%config;
}

1; # End of ConfigFile.pm
