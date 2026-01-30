# Bibliomation Patron Purge

This repository contains scripts and documentation for purging patron records from the Evergreen integrated library system. The scripts are designed to help server administrators efficiently remove inactive or outdated patron accounts while ensuring data integrity and compliance with privacy regulations.

## Criteria for Purging Patrons

The criteria for purging patrons was decided by the Bibliomation ILS Steering Committee.

Patrons are eligible for purging if they meet the following conditions:

- No bills on their account
- No lost items associated with their account
- Expired for > 5 years
- No activity (checkouts, renewals, holds, etc.) for > 5 years

## Scripts

### perform_mass_delete.pl

Finds patrons eligible for purging based on the ILS Steering Committee criteria and marks them as deleted (sets `deleted = TRUE`). This is typically run manually as part of a mass purge effort, though it can be scheduled if desired.

After running this script, run `purge_deleted_patrons.pl` to anonymize the personal information of the deleted patrons.

**Usage:**

```bash
perform_mass_delete.pl [OPTIONS]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--config=FILE` | Path to Evergreen opensrf.xml config file (default: `/openils/conf/opensrf.xml`) |
| `--log=FILE` | Path to log file (default: STDOUT) |
| `--dry-run` | Show what would be deleted without making changes |
| `--notify-conf=FILE` | Path to email notification config file |
| `--email-to=ADDR` | Override email recipient from config |
| `--help` | Show help message |

**Examples:**

```bash
# Preview what would be marked as deleted (recommended first step)
./perform_mass_delete.pl --dry-run --log=/var/log/mass_delete_preview.log

# Run with logging
./perform_mass_delete.pl --log=/var/log/patron_mass_delete.log

# Run with logging and email notifications
./perform_mass_delete.pl --log=/var/log/patron_mass_delete.log --notify-conf=/etc/patron_purge/notify.conf
```

### purge_deleted_patrons.pl

Identifies patrons who have been marked as deleted (via staff client user buckets batch delete or `perform_mass_delete.pl`) but not yet had their personal information purged, then runs `actor.usr_delete()` to anonymize their data.

**Usage:**

```bash
purge_deleted_patrons.pl [OPTIONS]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--config=FILE` | Path to Evergreen opensrf.xml config file (default: `/openils/conf/opensrf.xml`) |
| `--log=FILE` | Path to log file (default: STDOUT) |
| `--dry-run` | Show what would be purged without making changes |
| `--dest-user=ID` | User ID to reassign data to (default: 1) |
| `--notify-conf=FILE` | Path to email notification config file |
| `--email-to=ADDR` | Override email recipient from config |
| `--help` | Show help message |

**Examples:**

```bash
# Preview what would be purged (no changes made)
./purge_deleted_patrons.pl --dry-run

# Run with logging
./purge_deleted_patrons.pl --log=/var/log/patron_purge.log

# Run with logging and email notifications
./purge_deleted_patrons.pl --log=/var/log/patron_purge.log --notify-conf=/etc/patron_purge/notify.conf

# Use a custom Evergreen config
./purge_deleted_patrons.pl --config=/path/to/opensrf.xml
```

## Workflow

### Mass Purge (Manual)

For large-scale purge efforts:

```bash
# Step 1: Preview eligible patrons
./perform_mass_delete.pl --dry-run --log=/var/log/mass_delete_preview.log

# Step 2: Review the log, then mark them as deleted
./perform_mass_delete.pl --log=/var/log/mass_delete.log

# Step 3: Purge the deleted patrons' personal information
./purge_deleted_patrons.pl --log=/var/log/patron_purge.log
```

### Ongoing Maintenance (Scheduled)

For regular cleanup of patrons deleted via staff client:

## Email Notifications

Email notifications can be configured via a simple config file. This allows staff to opt in/out of notifications without modifying cron jobs.

Copy `conf/example.conf` and edit the settings:

```conf
# Enable email notifications (1 = enabled, 0 = disabled)
email_enabled = 1

# Email recipient for notifications
email_to = "admin@example.org"

# Email sender address  
email_from = "noreply@example.org"

# Email subject prefix
email_subject_prefix = "[Patron Purge]"
```

Then pass it to the script with `--notify-conf=/path/to/notify.conf`.

## Modules

The `src/lib/` directory contains reusable Perl modules:

| Module | Description |
|--------|-------------|
| `Config.pm` | Simple key=value configuration file parser |
| `Database.pm` | Database connection and SQL execution utilities |
| `Email.pm` | Email sending functionality |
| `Evergreen.pm` | Evergreen ILS configuration utilities |
| `Logging.pm` | Logging with formatted headers and messages |

These modules are designed to be standalone and loosely coupled. They throw exceptions on errors, allowing the calling code to handle them as needed.

## SQL Files

| File | Description |
|------|-------------|
| `find_deleted_patrons.sql` | Finds patrons marked deleted but not yet purged |
| `find_purge_eligible_patrons.sql` | Finds patrons eligible for purging based on criteria |

## Scheduled Execution

Example cron entry to run `purge_deleted_patrons.pl` weekly on Sunday at 2 AM:

```cron
0 2 * * 0 /openils/bin/purge_deleted_patrons.pl --log=/var/log/patron_purge.log --notify-conf=/etc/patron_purge/notify.conf
```

## Requirements

- DBI and DBD::Pg
- Email::MIME and Email::Sender::Simple
- Try::Tiny
- XML::Simple
- Access to Evergreen's opensrf.xml configuration