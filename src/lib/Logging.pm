# ----------------------------------------------
# Logging.pm - A simple logging module for Perl scripts
# ----------------------------------------------

package Logging;

use strict;
use warnings;
use POSIX qw/strftime/;
use Exporter 'import';

our @EXPORT_OK = qw(setup_logger configure_logger log_message log_header DEBUG INFO WARN ERROR FATAL);

use constant LINE_WIDTH => 120;
use constant {
    DEBUG => 'DEBUG',
    INFO  => 'INFO',
    WARN  => 'WARN',
    ERROR => 'ERROR',
    FATAL => 'FATAL',
};

# Level priority for filtering (higher = more severe)
my %LEVEL_PRIORITY = (
    DEBUG => 1,
    INFO  => 2,
    WARN  => 3,
    ERROR => 4,
    FATAL => 5,
);

# Module-level configuration
my $log_file          = undef;
my $console_enabled   = 1;       # Output to console (default: on)
my $file_log_level    = 'DEBUG'; # Minimum level for file logging
my $console_log_level = 'INFO';  # Minimum level for console (DEBUG stays file-only)

# ----------------------------------------------
# setup_logger - Creates a log file if it doesn't exist and sets module log file
# ----------------------------------------------

sub setup_logger {
    my ($path) = @_;
    return unless defined $path;

    $log_file = $path;

    unless (-e $log_file) {
        open my $fh, '>', $log_file or die "Could not create log file '$log_file': $!";
        close $fh;
    }
}

# ----------------------------------------------
# configure_logger - Configure logging behavior
# Options:
#   console       => 0/1 (enable/disable console output, default: 1)
#   file_level    => 'DEBUG'|'INFO'|'WARN'|'ERROR'|'FATAL' (minimum level for file)
#   console_level => 'DEBUG'|'INFO'|'WARN'|'ERROR'|'FATAL' (minimum level for console)
# ----------------------------------------------

sub configure_logger {
    my (%opts) = @_;
    
    $console_enabled   = $opts{console}       if exists $opts{console};
    $file_log_level    = uc($opts{file_level})    if exists $opts{file_level};
    $console_log_level = uc($opts{console_level}) if exists $opts{console_level};
    
    # Validate levels
    $file_log_level    = 'DEBUG' unless exists $LEVEL_PRIORITY{$file_log_level};
    $console_log_level = 'INFO'  unless exists $LEVEL_PRIORITY{$console_log_level};
}

# ----------------------------------------------
# _level_value - Returns numeric priority for a log level
# ----------------------------------------------

sub _level_value {
    my ($level) = @_;
    return $LEVEL_PRIORITY{uc($level // 'INFO')} // $LEVEL_PRIORITY{INFO};
}

# ----------------------------------------------
# log_header - Constructs a log header with timestamp, level, title, and message
# ----------------------------------------------

sub log_header {
    my ($level, $title, $message) = @_;
    my $log_msg = _construct_header($level, $title, $message);
    _write_log($log_msg, $level);
    return $log_msg;
}

# ----------------------------------------------
# log_message - Logs a message with a specified log level and timestamp
# ----------------------------------------------

sub log_message {
    my ($level, $message) = @_;
    my $log_msg = _construct_log_message($level, $message);
    _write_log($log_msg, $level);
    return $log_msg;
}

# ----------------------------------------------
# _center_line - Centers text within a given width, padded with spaces and bordered by '|'
# ----------------------------------------------

sub _center_line {
    my ($text, $inner_width) = @_;
    $text //= '';
    $text =~ s/\R/ /g;
    $text = substr($text, 0, $inner_width) if length($text) > $inner_width;
    my $pad_left  = int(($inner_width - length($text)) / 2);
    my $pad_right = $inner_width - length($text) - $pad_left;
    return '|' . (' ' x $pad_left) . $text . (' ' x $pad_right) . "|\n";
}

# ----------------------------------------------
# _wrap_lines - Wraps text into lines of specified width, bordered by '|'
# ----------------------------------------------

sub _wrap_lines {
    my ($text, $inner_width) = @_;
    $text //= '';
    return () if $inner_width < 1;

    my @out;

    for my $para (split(/\R/, $text)) {
        $para =~ s/\s+/ /g;
        $para =~ s/^\s+|\s+$//g;

        # Pre-split long words into width-sized chunks separated by spaces
        $para =~ s/(\S{$inner_width})(?=\S)/$1 /g;

        my $line = '';
        pos($para) = 0;

        while ($para =~ /\G(\S+)/gc) {
            my $word = $1;

            if ($line eq '') {
                $line = $word;
            } elsif (length($line) + 1 + length($word) <= $inner_width) {
                $line .= " $word";
            } else {
                push @out, '|' . sprintf("%-*s", $inner_width, $line) . "|\n";
                $line = $word;
            }

            $para =~ /\G\s+/gc; # consume spaces
        }

        $line ne '' and push @out, '|' . sprintf("%-*s", $inner_width, $line) . "|\n";
    }

    return @out;
}

# ----------------------------------------------
# _construct_header - Constructs a log header with timestamp, level, title, and message
# ----------------------------------------------

sub _construct_header {
    my ($level, $title, $message) = @_;
    my $timestamp   = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $inner_width = LINE_WIDTH - 2;

    # Normalize and validate level against module constants
    my %VALID = map { $_ => 1 } (DEBUG, INFO, WARN, ERROR, FATAL);
    my $lvl = defined $level ? uc($level) : INFO;
    $lvl = exists $VALID{$lvl} ? $lvl : INFO;

    # Guard bad path first: if inner width is unusable, fall back to a simple header line
    $inner_width > 0
        or return sprintf(
            "[%s] [%s]%s%s\n",
            $timestamp,
            $lvl,
            (defined $title && length $title) ? " $title - " : ' ',
            $message // ''
        );

    my $border  = '+' . ('=' x $inner_width) . "+\n";
    my $divider = '|' . ('-' x $inner_width) . "|\n";
    my $meta    = sprintf("[%s] [%s]", $timestamp, $lvl);

    # Padding for body lines
    my $pad = 1;
    $pad = 0 if $inner_width <= 2 * $pad;
    my $body_width = $inner_width - 2 * $pad;

    my @lines;
    push @lines, $border;
    push @lines, _center_line($meta, $inner_width);

    if (defined $title && $title ne '') {
        push @lines, $divider;
        push @lines, _center_line($title, $inner_width);
    }

    push @lines, $divider;

    # Wrap body and add side padding
    for my $l (_wrap_lines($message // '', $body_width)) {
        my $content = substr($l, 1, $body_width); # extract inner content without borders
        push @lines, '|' . (' ' x $pad) . $content . (' ' x $pad) . "|\n";
    }

    push @lines, $border;

    return join('', @lines);
}

# ----------------------------------------------
# construct_log_message - Logs a message with a specified log level and timestamp
# ----------------------------------------------

sub _construct_log_message {
    my ($level, $message) = @_;
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $prefix    = "[$timestamp] [$level] ";
    my $prefix_len = length($prefix);
    my $line_width = LINE_WIDTH;

    # Guard bad path first: if line width is unusable, fall back to simple log line
    $line_width > $prefix_len
        or return sprintf("%s%s\n", $prefix, $message // '');

    my $inner_width = $line_width - $prefix_len;

    my @lines = _wrap_lines($message // '', $inner_width);
    my $i = 0;
    return join('', map {
        $i++;
        $i == 1
            ? $prefix . substr($_, 1, length($_) - 3) . "\n"
            : ' ' x $prefix_len . substr($_, 1, length($_) - 3) . "\n"
    } @lines);
}

# ----------------------------------------------
# _write_log - Writes the log message to the log file and/or STDOUT
# ----------------------------------------------

sub _write_log {
    my ($log_msg, $level) = @_;
    return unless defined $log_msg;
    
    $level //= 'INFO';
    my $msg_priority = _level_value($level);
    
    # Write to file if log file is set and level meets threshold
    if (defined $log_file && $msg_priority >= _level_value($file_log_level)) {
        open my $fh, '>>', $log_file or die "Could not open log file '$log_file': $!";
        print $fh $log_msg;
        close $fh;
    }
    
    # Write to console if enabled and level meets threshold
    # Also write to console if no log file is set (original behavior)
    if ($console_enabled && $msg_priority >= _level_value($console_log_level)) {
        print $log_msg;
    } elsif (!defined $log_file) {
        # Fallback: if no log file and console disabled, still print (avoid silent failure)
        print $log_msg;
    }
}

1; # End of Logging.pm