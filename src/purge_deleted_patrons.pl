#!/usr/bin/perl
# ----------------------------------------------
# purge_deleted_patrons.pl - Finds deleted patrons and purges their data
# 
# This script identifies patrons who have been marked as deleted but not yet
# purged, then runs actor.usr_delete() to anonymize their personal information.
#
# Users can be identified for deletion in the staff client via user buckets and 
# their batch delete feature.
# 
# Designed to be run as a scheduled job.
# ----------------------------------------------

use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Try::Tiny;
use Getopt::Long;
use POSIX qw(strftime);

use ConfigFile qw(load_config);
use Database qw(setup_database_connection run_sql run_sql_file begin_transaction commit_transaction rollback_transaction prepare_sql execute_prepared);
use Email qw(send_email);
use Evergreen;
use Logging qw(setup_logger configure_logger log_message log_header DEBUG INFO WARN ERROR FATAL);

# ----------------------------------------------
# Configuration - Defaults
# ----------------------------------------------

my $notify_conf    = undef;
my $config_file    = '/openils/conf/opensrf.xml';
my $log_file       = undef;
my $dry_run        = 0;
my $quiet          = 0;
my $dest_user_id   = 1;  # Default destination user for reassigning data
my $help           = 0;
my $batch_size     = 1000;  # Number of patrons per transaction batch
my $workers        = 1;     # Number of parallel worker processes

# Email settings
my $email_enabled        = 0;
my $email_to             = '';
my $email_from           = '';
my $email_subject_prefix = '[Patron Purge]';

GetOptions(
    'notify-conf=s' => \$notify_conf,
    'config=s'      => \$config_file,
    'log=s'         => \$log_file,
    'dry-run'       => \$dry_run,
    'quiet'         => \$quiet,
    'dest-user=i'   => \$dest_user_id,
    'email-to=s'    => \$email_to,
    'batch-size=i'  => \$batch_size,
    'workers=i'     => \$workers,
    'help'          => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print_usage();
    exit 0;
}

# Load notification config if specified (CLI --email-to overrides config)
load_notification_config();

# ----------------------------------------------
# Main
# ----------------------------------------------

sub main {
    setup_logger($log_file) if defined $log_file;
    configure_logger(console => 0) if $quiet;
    
    log_header(INFO, 'Patron Purge Started', 
        "Config: $config_file | Dry Run: " . ($dry_run ? 'Yes' : 'No') . " | Dest User: $dest_user_id" .
        " | Batch Size: $batch_size | Workers: $workers");
    
    initialize_database();
    
    my $deleted_patrons = find_deleted_patrons();
    
    if (scalar(@$deleted_patrons) == 0) {
        log_message(INFO, "No patrons to purge. Exiting.");
        send_notification(0, 0, 0);
        return 0;
    }
    
    my ($success_count, $error_count);
    
    if ($workers > 1 && !$dry_run) {
        ($success_count, $error_count) = purge_patrons_parallel($deleted_patrons);
    } else {
        ($success_count, $error_count) = purge_patrons($deleted_patrons);
    }
    
    log_header(INFO, 'Patron Purge Complete', 
        "Success: $success_count | Errors: $error_count | Dry Run: " . ($dry_run ? 'Yes' : 'No'));
    
    send_notification(scalar(@$deleted_patrons), $success_count, $error_count);
    
    return $error_count > 0 ? 1 : 0;
}

# ----------------------------------------------
# load_notification_config - Load email settings from config file
# ----------------------------------------------

sub load_notification_config {
    return unless defined $notify_conf;
    
    my $conf = load_config($notify_conf);
    
    # Email settings from config (CLI --email-to takes precedence)
    $email_enabled        = $conf->{email_enabled}        if exists $conf->{email_enabled};
    $email_to             = $conf->{email_to}             if exists $conf->{email_to} && $email_to eq '';
    $email_from           = $conf->{email_from}           if exists $conf->{email_from};
    $email_subject_prefix = $conf->{email_subject_prefix} if exists $conf->{email_subject_prefix};
}

# ----------------------------------------------
# initialize_database - Connect to the Evergreen database
# ----------------------------------------------

sub initialize_database {
    my $db_config;
    try {
        $db_config = Evergreen::get_database_configuration($config_file);
    }
    catch {
        log_message(FATAL, "Failed to read database configuration: $_");
        exit 1;
    };
    
    try {
        setup_database_connection($db_config);
        log_message(INFO, "Connected to database: $db_config->{name} on $db_config->{host}");
    }
    catch {
        log_message(FATAL, "Failed to connect to database: $_");
        exit 1;
    };
}

# ----------------------------------------------
# find_deleted_patrons - Query for patrons needing purge
# ----------------------------------------------

sub find_deleted_patrons {
    my $deleted_patrons;
    try {
        my $sql_file = "$RealBin/sql/find_deleted_patrons.sql";
        $deleted_patrons = run_sql_file($sql_file);
        log_message(INFO, "Found " . scalar(@$deleted_patrons) . " deleted patrons to purge");
    }
    catch {
        log_message(FATAL, "Failed to find deleted patrons: $_");
        exit 1;
    };
    
    return $deleted_patrons;
}

# ----------------------------------------------
# purge_patrons - Process and purge each patron
# Returns: ($success_count, $error_count)
# ----------------------------------------------

sub purge_patrons {
    my ($patrons) = @_;
    
    my $success_count = 0;
    my $error_count   = 0;
    my $batch_count   = 0;
    my $total         = scalar(@$patrons);
    
    # Prepare the statement once, execute many times
    my $sth = prepare_sql("SELECT actor.usr_delete(?, ?)") unless $dry_run;
    
    begin_transaction() unless $dry_run;
    
    for my $patron (@$patrons) {
        my $patron_id     = $patron->{patron_id};
        my $library       = $patron->{library_shortname};
        my $years_expired = $patron->{years_expired} // 'N/A';
        
        if ($dry_run) {
            log_message(INFO, "[DRY RUN] Would purge patron $patron_id ($library, expired $years_expired years)");
            $success_count++;
            next;
        }
        
        try {
            execute_prepared($sth, $patron_id, $dest_user_id);
            $success_count++;
            $batch_count++;
            
            # Commit and start new transaction at batch boundaries
            if ($batch_count >= $batch_size) {
                commit_transaction();
                log_message(INFO, "Committed batch ($success_count/$total purged so far)");
                $batch_count = 0;
                begin_transaction();
            }
        }
        catch {
            log_message(ERROR, "Failed to purge patron $patron_id: $_");
            $error_count++;
        };
    }
    
    # Commit any remaining
    if (!$dry_run && $batch_count > 0) {
        commit_transaction();
        log_message(INFO, "Committed final batch ($success_count/$total purged)");
    }
    
    return ($success_count, $error_count);
}

# ----------------------------------------------
# purge_patrons_parallel - Fork worker processes to purge in parallel
# Each worker gets its own database connection and processes a slice of the list.
# Returns: ($success_count, $error_count)
# ----------------------------------------------

sub purge_patrons_parallel {
    my ($patrons) = @_;
    
    my $total = scalar(@$patrons);
    log_message(INFO, "Starting parallel purge with $workers workers for $total patrons");
    
    # Split patron list into contiguous slices for each worker
    # (patrons are sorted by library, so contiguous slices minimize
    # cross-worker overlap on shared circulation data)
    my @slices;
    my $slice_size = int($total / $workers);
    my $remainder  = $total % $workers;
    my $offset     = 0;
    
    for my $i (0 .. $workers - 1) {
        my $count = $slice_size + ($i < $remainder ? 1 : 0);
        $slices[$i] = [ @{$patrons}[$offset .. $offset + $count - 1] ];
        $offset += $count;
    }
    
    # Create a temp file per worker to report results back
    my @result_files;
    for my $i (0 .. $workers - 1) {
        my $file = "/tmp/patron_purge_worker_${$}_${i}.result";
        push @result_files, $file;
    }
    
    # Fork workers
    my @child_pids;
    my $db_config = Evergreen::get_database_configuration($config_file);
    
    for my $worker_id (0 .. $workers - 1) {
        my $pid = fork();
        
        if (!defined $pid) {
            log_message(FATAL, "Failed to fork worker $worker_id: $!");
            exit 1;
        }
        
        if ($pid == 0) {
            # Child process - establish own database connection
            setup_database_connection($db_config);
            
            my $slice = $slices[$worker_id];
            my $slice_size = scalar(@$slice);
            my $success = 0;
            my $errors  = 0;
            my $batch_count = 0;
            
            my $sth = prepare_sql("SELECT actor.usr_delete(?, ?)");
            begin_transaction();
            
            for my $patron (@$slice) {
                my $patron_id = $patron->{patron_id};
                
                try {
                    execute_prepared($sth, $patron_id, $dest_user_id);
                    $success++;
                    $batch_count++;
                    
                    if ($batch_count >= $batch_size) {
                        commit_transaction();
                        log_message(INFO, "Worker $worker_id: committed batch ($success/$slice_size purged)");
                        $batch_count = 0;
                        begin_transaction();
                    }
                }
                catch {
                    log_message(ERROR, "Worker $worker_id: failed to purge patron $patron_id: $_");
                    $errors++;
                    
                    # Recover from aborted transaction (e.g. deadlock)
                    try {
                        rollback_transaction();
                    } catch {};
                    $batch_count = 0;
                    $sth = prepare_sql("SELECT actor.usr_delete(?, ?)");
                    begin_transaction();
                };
            }
            
            if ($batch_count > 0) {
                commit_transaction();
                log_message(INFO, "Worker $worker_id: committed final batch ($success/$slice_size purged)");
            }
            
            # Write results to temp file
            open my $fh, '>', $result_files[$worker_id];
            print $fh "$success $errors\n";
            close $fh;
            
            exit 0;
        }
        
        push @child_pids, $pid;
        log_message(INFO, "Forked worker $worker_id (PID $pid) with " . scalar(@{$slices[$worker_id]}) . " patrons");
    }
    
    # Parent: wait for all children
    for my $pid (@child_pids) {
        waitpid($pid, 0);
        if ($? != 0) {
            log_message(WARN, "Worker PID $pid exited with status $?");
        }
    }
    
    # Collect results from temp files
    my $total_success = 0;
    my $total_errors  = 0;
    
    for my $i (0 .. $workers - 1) {
        if (open my $fh, '<', $result_files[$i]) {
            my $line = <$fh>;
            close $fh;
            if ($line && $line =~ /^(\d+)\s+(\d+)/) {
                $total_success += $1;
                $total_errors  += $2;
            }
            unlink $result_files[$i];
        } else {
            log_message(WARN, "Could not read results for worker $i");
            $total_errors++;
        }
    }
    
    return ($total_success, $total_errors);
}

# ----------------------------------------------
# send_notification - Send email summary if enabled
# ----------------------------------------------

sub send_notification {
    my ($total, $success_count, $error_count) = @_;
    
    return unless $email_enabled && $email_to && $email_from;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $status    = $error_count > 0 ? 'Completed with Errors' : 'Completed Successfully';
    my $dry_label = $dry_run ? ' (DRY RUN)' : '';
    
    my $subject = "$email_subject_prefix $status$dry_label";
    
    my $body = <<"EMAIL";
Patron Purge Report
===================
Timestamp: $timestamp
Status: $status$dry_label

Summary
-------
Total patrons found: $total
Successfully purged: $success_count
Errors: $error_count

Configuration
-------------
Evergreen config: $config_file
Destination user: $dest_user_id
EMAIL

    if ($log_file) {
        $body .= "Log file: $log_file\n";
    }
    
    try {
        send_email(
            to      => $email_to,
            from    => $email_from,
            subject => $subject,
            body    => $body,
        );
        log_message(INFO, "Notification email sent to $email_to");
    }
    catch {
        log_message(WARN, "Failed to send notification email: $_");
    };
}

# ----------------------------------------------
# print_usage - Display help information
# ----------------------------------------------

sub print_usage {
    print <<'USAGE';
Usage: purge_deleted_patrons.pl [OPTIONS]

Finds patrons marked as deleted and purges their personal information
by calling actor.usr_delete().

Options:
    --config=FILE       Path to Evergreen opensrf.xml config file
                        (default: /openils/conf/opensrf.xml)
    --log=FILE          Path to log file (default: STDOUT)
    --dry-run           Show what would be purged without making changes
    --quiet             Suppress console output (for cron jobs)
    --dest-user=ID      User ID to reassign data to (default: 1)
    --batch-size=N      Number of patrons per transaction batch (default: 1000)
    --workers=N         Number of parallel worker processes (default: 1)
    --notify-conf=FILE  Path to email notification config file
    --email-to=ADDR     Override email recipient from config
    --help              Show this help message

Performance:
    The --batch-size option controls how many patrons are purged per
    transaction. Larger batches are faster but use more memory.

    Use --workers=N to run N parallel processes, each with its own
    database connection. This scales nearly linearly — e.g. --workers=4
    should be roughly 4x faster. Start conservatively to avoid
    overloading the database server.

Notification Config:
    Use --notify-conf to specify an email notification config file.
    Staff can toggle notifications by editing email_enabled in the file.
    See conf/example.conf for available options.

Examples:
    # Basic dry run
    purge_deleted_patrons.pl --dry-run

    # Run with larger batch size for speed
    purge_deleted_patrons.pl --batch-size=5000 --log=/var/log/patron_purge.log

    # Run with 4 parallel workers
    purge_deleted_patrons.pl --workers=4 --log=/var/log/patron_purge.log

    # Run with logging and notifications
    purge_deleted_patrons.pl --log=/var/log/patron_purge.log --notify-conf=/etc/notify.conf

    # Override email recipient
    purge_deleted_patrons.pl --notify-conf=/etc/notify.conf --email-to=other@example.org
USAGE
}

exit main();
