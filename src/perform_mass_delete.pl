#!/usr/bin/perl
# ----------------------------------------------
# perform_mass_delete.pl - Marks purge-eligible patrons as deleted
# 
# This script identifies patrons eligible for purging based on the criteria
# defined by the ILS Steering Committee, then sets their deleted flag to TRUE.
#
# After running this script, run purge_deleted_patrons.pl to anonymize 
# the personal information of deleted patrons.
# 
# Designed to be run as a scheduled job or manually for mass purge efforts.
# ----------------------------------------------

use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Try::Tiny;
use Getopt::Long;
use POSIX qw(strftime);

use ConfigFile qw(load_config);
use Database qw(setup_database_connection run_sql run_sql_file);
use Email qw(send_email);
use Evergreen;
use Logging qw(setup_logger log_message log_header DEBUG INFO WARN ERROR FATAL);

# ----------------------------------------------
# Configuration - Defaults
# ----------------------------------------------

my $notify_conf    = undef;
my $config_file    = '/openils/conf/opensrf.xml';
my $log_file       = undef;
my $dry_run        = 0;
my $help           = 0;

# Email settings
my $email_enabled        = 0;
my $email_to             = '';
my $email_from           = '';
my $email_subject_prefix = '[Patron Mass Delete]';

GetOptions(
    'notify-conf=s' => \$notify_conf,
    'config=s'      => \$config_file,
    'log=s'         => \$log_file,
    'dry-run'       => \$dry_run,
    'email-to=s'    => \$email_to,
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
    
    log_header(INFO, 'Mass Delete Started', 
        "Config: $config_file | Dry Run: " . ($dry_run ? 'Yes' : 'No'));
    
    initialize_database();
    
    my $eligible_patrons = find_eligible_patrons();
    
    if (scalar(@$eligible_patrons) == 0) {
        log_message(INFO, "No patrons eligible for deletion. Exiting.");
        send_notification(0, 0, 0);
        return 0;
    }
    
    my ($success_count, $error_count) = mark_patrons_deleted($eligible_patrons);
    
    log_header(INFO, 'Mass Delete Complete', 
        "Success: $success_count | Errors: $error_count | Dry Run: " . ($dry_run ? 'Yes' : 'No'));
    
    send_notification(scalar(@$eligible_patrons), $success_count, $error_count);
    
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
    
    # Override subject prefix for this script
    $email_subject_prefix =~ s/Purge/Mass Delete/g if $email_subject_prefix =~ /Purge/;
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
# find_eligible_patrons - Query for patrons eligible for deletion
# ----------------------------------------------

sub find_eligible_patrons {
    my $eligible_patrons;
    try {
        my $sql_file = "$RealBin/sql/find_purge_eligible_patrons.sql";
        $eligible_patrons = run_sql_file($sql_file);
        log_message(INFO, "Found " . scalar(@$eligible_patrons) . " patrons eligible for deletion");
    }
    catch {
        log_message(FATAL, "Failed to find eligible patrons: $_");
        exit 1;
    };
    
    return $eligible_patrons;
}

# ----------------------------------------------
# mark_patrons_deleted - Set deleted flag to TRUE for each patron
# Returns: ($success_count, $error_count)
# ----------------------------------------------

sub mark_patrons_deleted {
    my ($patrons) = @_;
    
    my $success_count = 0;
    my $error_count   = 0;
    
    for my $patron (@$patrons) {
        my $patron_id     = $patron->{patron_id};
        my $library       = $patron->{library_shortname};
        my $years_expired = $patron->{years_expired} // 'N/A';
        
        if ($dry_run) {
            log_message(INFO, "[DRY RUN] Would mark patron $patron_id as deleted ($library, expired $years_expired years)");
            $success_count++;
            next;
        }
        
        try {
            run_sql("UPDATE actor.usr SET deleted = TRUE WHERE id = ?", $patron_id);
            log_message(INFO, "Marked patron $patron_id as deleted ($library, expired $years_expired years)");
            $success_count++;
        }
        catch {
            log_message(ERROR, "Failed to mark patron $patron_id as deleted: $_");
            $error_count++;
        };
    }
    
    return ($success_count, $error_count);
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
Patron Mass Delete Report
=========================
Timestamp: $timestamp
Status: $status$dry_label

Summary
-------
Total patrons eligible: $total
Successfully marked deleted: $success_count
Errors: $error_count

Configuration
-------------
Evergreen config: $config_file

Next Steps
----------
Run purge_deleted_patrons.pl to anonymize the personal information
of the patrons marked as deleted by this script.
EMAIL

    if ($log_file) {
        $body .= "\nLog file: $log_file\n";
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
Usage: perform_mass_delete.pl [OPTIONS]

Finds patrons eligible for purging based on ILS Steering Committee criteria
and marks them as deleted (sets deleted flag to TRUE).

Eligibility Criteria:
    - No bills on their account
    - No lost items associated with their account
    - Expired for > 5 years
    - No activity (checkouts, renewals, holds, etc.) for > 5 years

Options:
    --config=FILE       Path to Evergreen opensrf.xml config file
                        (default: /openils/conf/opensrf.xml)
    --log=FILE          Path to log file (default: STDOUT)
    --dry-run           Show what would be deleted without making changes
    --notify-conf=FILE  Path to email notification config file
    --email-to=ADDR     Override email recipient from config
    --help              Show this help message

Workflow:
    1. Run this script to mark eligible patrons as deleted
    2. Run purge_deleted_patrons.pl to anonymize their data

Examples:
    # Preview what would be marked as deleted
    perform_mass_delete.pl --dry-run

    # Run with logging
    perform_mass_delete.pl --log=/var/log/patron_mass_delete.log

    # Run with logging and notifications
    perform_mass_delete.pl --log=/var/log/patron_mass_delete.log --notify-conf=/etc/notify.conf
USAGE
}

exit main();
