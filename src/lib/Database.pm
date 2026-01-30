package Database;

use strict;
use warnings;
use DBI;
use Exporter 'import';

our @EXPORT_OK = qw(setup_database_connection create_table_if_not_exists create_schema_if_not_exists);

my $database_handle = undef;

# ----------------------------------------------
# setup_database_connection - creates a DBI database connection using provided database configuration
# and sets the module's database handle
# Throws: DBI exception on connection failure
# ----------------------------------------------

sub setup_database_connection {
    my ($db_config) = @_;
    
    my $dsn = "DBI:Pg:dbname=$db_config->{name};host=$db_config->{host};port=$db_config->{port}";
    $database_handle = DBI->connect($dsn, $db_config->{user}, $db_config->{password}, { RaiseError => 1, AutoCommit => 1 });
    
    return $database_handle;
}

# ----------------------------------------------
# create_table_if_not_exists - creates a table if it does not already exist given a table name and schema
# ----------------------------------------------

sub create_table_if_not_exists {
    my ($table_name, $schema_name) = @_;
    
    return unless defined $database_handle;

    create_schema_if_not_exists($schema_name);
    my $sth = $database_handle->prepare("CREATE TABLE IF NOT EXISTS $schema_name.$table_name (id SERIAL PRIMARY KEY)");
    $sth->execute();
    $sth->finish();
}


# ----------------------------------------------
# create_schema_if_not_exists - creates a schema if it does not already exist given a schema name
# ----------------------------------------------

sub create_schema_if_not_exists {
    my ($schema_name) = @_;
    
    return unless defined $database_handle;
    
    my $sth = $database_handle->prepare("CREATE SCHEMA IF NOT EXISTS $schema_name");
    $sth->execute();
    $sth->finish();
}

1; # End of Database.pm