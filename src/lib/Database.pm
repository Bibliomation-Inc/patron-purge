package Database;

use strict;
use warnings;
use DBI;
use Exporter 'import';

our @EXPORT_OK = qw(
    setup_database_connection 
    create_table_if_not_exists 
    create_schema_if_not_exists
    run_sql
    run_sql_file
);

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
# run_sql - executes SQL text with optional bind parameters
# Arguments:
#   $sql    - SQL statement to execute
#   @params - optional bind parameters for placeholders
# Returns: arrayref of hashrefs for SELECT, rows affected for other statements
# Throws: on missing database connection, DBI errors
# ----------------------------------------------

sub run_sql {
    my ($sql, @params) = @_;
    
    die "No database connection established\n" unless defined $database_handle;
    die "No SQL provided\n" unless defined $sql && $sql =~ /\S/;
    
    my $sth = $database_handle->prepare($sql);
    $sth->execute(@params);
    
    # Check if this is a SELECT query by looking for SELECT as a standalone word
    # This handles cases where SQL has leading comments
    my $is_select = ($sql =~ /\bSELECT\b/i && $sql !~ /\b(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER)\b/i);
    
    # If it's a SELECT, return results as arrayref of hashrefs
    if ($is_select) {
        my $results = $sth->fetchall_arrayref({});
        $sth->finish();
        return $results;
    }
    
    # For non-SELECT, return number of rows affected
    my $rows = $sth->rows;
    $sth->finish();
    return $rows;
}

# ----------------------------------------------
# run_sql_file - reads SQL from a file and executes it with optional bind parameters
# Arguments:
#   $file_path - path to the SQL file
#   @params    - optional bind parameters for placeholders
# Returns: arrayref of hashrefs for SELECT, rows affected for other statements
# Throws: on file read failure, missing database connection, DBI errors
# ----------------------------------------------

sub run_sql_file {
    my ($file_path, @params) = @_;
    
    die "No SQL file path provided\n" unless defined $file_path;
    die "SQL file not found: $file_path\n" unless -e $file_path;
    
    open my $fh, '<', $file_path or die "Cannot open SQL file '$file_path': $!\n";
    my $sql = do { local $/; <$fh> };
    close $fh;
    
    # Strip transaction wrappers (BEGIN/COMMIT/ROLLBACK) that are meant for manual psql use
    # These can appear anywhere in the file, not just at absolute start/end
    $sql =~ s/^\s*BEGIN\s*;\s*$//im;      # Remove standalone BEGIN; line
    $sql =~ s/^\s*(COMMIT|ROLLBACK)\s*;\s*$//im;  # Remove standalone COMMIT/ROLLBACK; line
    
    # Also remove any remaining whitespace-only lines at start/end
    $sql =~ s/^\s+//;
    $sql =~ s/\s+$//;
    
    return run_sql($sql, @params);
}

# ----------------------------------------------
# create_table_if_not_exists - creates a table if it does not already exist given a table name and schema
# Throws: on missing database connection, DBI errors
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
# Throws: on missing database connection, DBI errors
# ----------------------------------------------

sub create_schema_if_not_exists {
    my ($schema_name) = @_;
    
    return unless defined $database_handle;
    
    my $sth = $database_handle->prepare("CREATE SCHEMA IF NOT EXISTS $schema_name");
    $sth->execute();
    $sth->finish();
}

1; # End of Database.pm