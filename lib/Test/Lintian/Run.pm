# Copyright © 2018 Felix Lechner
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA

package Test::Lintian::Run;

=head1 NAME

Test::Lintian::Run -- generic runner for all suites

=head1 SYNOPSIS

  use Test::Lintian::Run qw(runner);

  my $runpath = "test working directory";

  runner($runpath);

=head1 DESCRIPTION

Generic test runner for all Lintian test suites

=cut

use strict;
use warnings;
use autodie;
use v5.10;

use Exporter qw(import);

BEGIN {
    our @EXPORT_OK = qw(
      logged_runner
      runner
      check_result
    );
}

use Capture::Tiny qw(capture_merged);
use Carp qw(confess);
use Cwd qw(getcwd);
use File::Basename qw(basename);
use File::Spec::Functions qw(abs2rel rel2abs splitpath catpath);
use File::Compare;
use File::Copy;
use File::stat;
use List::Util qw(max min any);
use Path::Tiny;
use Try::Tiny;

use Test::Lintian::ConfigFile qw(read_config);
use Test::Lintian::Harness qw(runsystem_ok up_to_date);
use Test::Lintian::Helper qw(rfc822date);
use Test::Lintian::Hooks
  qw(find_missing_prerequisites run_lintian sed_hook sort_lines calibrate);
use Test::Lintian::Prepare qw(early_logpath);

use constant SPACE => q{ };
use constant EMPTY => q{};
use constant YES => q{yes};
use constant NO => q{no};

sub logged_runner {
    my ($test_state, $runpath)= @_;

    my $betterlogpath = "$runpath/log";
    my $log;
    my $error;

    $log = capture_merged {
        try {
            # call runner
            runner($test_state, $runpath)

        }
        catch {
            # catch any error
            $error = $_;
        };
    };

    # delete old runner log
    unlink $betterlogpath if -f $betterlogpath;

    # move the early log for directory preparation to position of runner log
    my $earlylogpath = early_logpath($runpath);
    move($earlylogpath, $betterlogpath) if -f $earlylogpath;

    # append runner log to population log
    path($betterlogpath)->append_utf8($log) if length $log;

    # add error if there was one
    path($betterlogpath)->append_utf8($error) if length $error;

    # print log and die on error
    if ($error) {
        $test_state->dump_log($log)
          if length $log && $ENV{'DUMP_LOGS'}//NO eq YES;
        die "Runner died for $runpath: $error";
    }

    return;
}

# generic_runner
#
# Runs the test called $test assumed to be located in $testset/$dir/$test/.
#
sub runner {
    my ($test_state, $runpath, $outpath)= @_;

    say EMPTY;
    say '------- Runner starts here -------';

    # bail out if runpath does not exist
    die "Cannot find test directory $runpath." unless -d $runpath;

    # announce location
    say "Running test at $runpath.";

    # read dynamic file names
    my $runfiles = "$runpath/files";
    my $files = read_config($runfiles);

    # read dynamic case data
    my $rundescpath = "$runpath/$files->{test_specification}";
    my $testcase = read_config($rundescpath);

    # name of encapsulating directory should be that of test
    my $expected_name = path($runpath)->basename;
    die
"Test in $runpath is called $testcase->{testname} instead of $expected_name"
      if ($testcase->{testname} ne $expected_name);

    my $suite = $testcase->{suite};
    my $testname = $testcase->{testname};

    # skip test if marked
    my $skipfile = "$runpath/skip";
    if (-f $skipfile) {
        my $reason = path($skipfile)->slurp_utf8 || 'No reason given';
        say "Skipping test: $reason";
        $test_state->skip_test("(disabled) $reason");
        return;
    }

    # skip if missing prerequisites
    my $missing = find_missing_prerequisites($testcase);
    if (length $missing) {
        say "Missing prerequisites: $missing";
        $test_state->skip_test("Missing prerequisites: $missing");
        return;
    }

    # check test architectures
    unless (length $ENV{'DEB_HOST_ARCH'}) {
        die 'DEB_HOST_ARCH is not set.';
    }
    my $platforms = $testcase->{test_architectures};
    if ($platforms ne 'any') {
        my @wildcards = split(SPACE, $platforms);
        my @matches= map {
            qx{dpkg-architecture -a $ENV{'DEB_HOST_ARCH'} -i $_; echo -n \$?}
        } @wildcards;
        unless (any { $_ == 0 } @matches) {
            say 'Architecture mismatch';
            $test_state->skip_test('Architecture mismatch');
            return;
        }
    }

    # get lintian subject
    die 'Could not get subject of Lintian examination.'
      unless exists $testcase->{build_product};
    my $subject = "$runpath/$testcase->{build_product}";

    $test_state->progress('building');

    if (exists $testcase->{build_command}) {
        my $command= "cd $runpath; $testcase->{build_command}";
        if (system($command)) {
            die "$command failed.";
        }
    }

    die 'Build was unsuccessful.'
      unless -f $subject;

    my $pkg = $testcase->{source};

    # run lintian
    my $actual = "$runpath/tags.actual";
    my $includepath = "$runpath/lintian-include-dir";
    $ENV{'LINTIAN_COVERAGE'}
      .= ",-db,./cover_db-$testcase->{suite}-$testcase->{testname}"
      if exists $ENV{'LINTIAN_COVERAGE'};
    run_lintian($runpath, $subject, $testcase->{profile}, $includepath,
        $testcase->{options}, $actual);

    # Run a sed-script if it exists, for tests that have slightly variable
    # output
    my $parsed = "$runpath/tags.actual.parsed";
    my $script = "$runpath/post_test";
    if(-f $script) {
        sed_hook($script, $actual, $parsed);
    } else {
        die"Could not copy actual tags $actual to $parsed: $!"
          if(system('cp', '-p', $actual, $parsed));
    }

    # sort tags
    my $sorted = "$runpath/tags.actual.parsed.sorted";
    if($testcase->{sort} eq 'yes') {
        sort_lines($parsed, $sorted);
    } else {
        die"Could not copy parsed tags $actual to $sorted: $!"
          if(system('cp', '-p', $parsed, $sorted));
    }

    my $expected = "$runpath/tags";
    my $origexp = $expected;

    my $calibrated = "$runpath/expected.$pkg.calibrated";
    $test_state->progress('test_calibration hook');
    $expected
      = calibrate("$runpath/test_calibration",$sorted, $expected, $calibrated);

    check_result($test_state, $testcase, $expected,$sorted, $origexp);

    return;
}

sub check_result {
    my ($test_state, $testcase, $expected, $actual, $origexp) = @_;
    # Compare the output to the expected tags.
    my $testok = !system('cmp', '-s', $expected, $actual);

    if (not $testok) {
        if ($testcase->{'todo'} eq 'yes') {
            $test_state->pass_todo_test('failed but marked as TODO');
            return;
        } else {
            $test_state->diff_files("$testcase->{spec_path}/tags", $actual);
            $test_state->fail_test('output differs!');
            return;
        }
    }

    unless ($testcase) {
        $test_state->pass_test;
        return;
    }

    # Check the output for invalid lines.  Also verify that all Test-For tags
    # are seen and all Test-Against tags are not.  Skip this part of the test
    # if neither Test-For nor Test-Against are set and Sort is also not set,
    # since in that case we probably have non-standard output.
    my %test_for = map { $_ => 1 } split(' ', $testcase->{'test_for'}//'');
    my %test_against
      = map { $_ => 1 } split(' ', $testcase->{'test_against'}//'');
    if (    not %test_for
        and not %test_against
        and $testcase->{'output_format'} ne 'EWI') {
        if ($testcase->{'todo'} eq 'yes') {
            $test_state->fail_test('marked as TODO but succeeded');
            return;
        } else {
            $test_state->pass_test;
            return;
        }
    } else {
        my $okay = 1;
        my @msgs;
        open(my $etags, '<', $actual);
        while (<$etags>) {
            next if m/^N: /;
            # Some of the traversal tests creates packages that are
            # skipped; accept that in the output
            next if m/tainted/o && m/skipping/o;
            # Looks for "$code: $package[ $type]: $tag"
            if (not /^.: \S+(?: (?:changes|source|udeb))?: (\S+)/o) {
                chomp;
                push(@msgs, "Invalid line: $_");
                $okay = 0;
                next;
            }
            my $tag = $1;
            if ($test_against{$tag}) {
                push(@msgs, "Tag $tag seen but listed in Test-Against");
                $okay = 0;
                # Warn only once about each "test-against" tag
                delete $test_against{$tag};
            }
            delete $test_for{$tag};
        }
        close($etags);
        if (%test_for) {
            if ($origexp && $origexp ne $expected) {
                # Test has been calibrated, check if some of the
                # "Test-For" has been calibrated out.  (Happens with
                # binaries-hardening on some architectures).
                open(my $oe, '<', $expected);
                my %cp_tf = %test_for;
                while (<$oe>) {
                    next if m/^N: /;
                    # Some of the traversal tests creates packages that are
                    # skipped; accept that in the output
                    next if m/tainted/o && m/skipping/o;
                    if (not /^.: \S+(?: (?:changes|source|udeb))?: (\S+)/o) {
                        chomp;
                        push(@msgs, "Invalid line: $_");
                        $okay = 0;
                        next;
                    }
                    delete $cp_tf{$1};
                }
                close($oe);
                # Remove tags that has been calibrated out.
                foreach my $tag (keys %cp_tf) {
                    delete $test_for{$tag};
                }
            }
            for my $tag (sort keys %test_for) {
                push(@msgs, "Tag $tag listed in Test-For but not found");
                $okay = 0;
            }
        }
        if ($okay) {
            if ($testcase->{'todo'} eq 'yes') {
                $test_state->fail_test('marked as TODO but succeeded');
                return;
            }
            $test_state->pass_test;
            return;
        } elsif ($testcase->{'todo'} eq 'yes') {
            $test_state->pass_todo_test(join("\n", @msgs));
            return;
        } else {
            $test_state->fail_test(join("\n", @msgs));
            return;
        }
    }
    confess("Assertion: This should be unreachable\n");
}

1;
