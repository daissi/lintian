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

package Test::Lintian::Build;

=head1 NAME

Test::Lintian::Build -- routines to prepare the work directories

=head1 SYNOPSIS

  use Test::Lintian::Build qw(build_subject);

=head1 DESCRIPTION

The routines in this module prepare the work directories in which the
tests are run. To do so, they use the specifications in the test set.

=cut

use v5.20;
use warnings;
use utf8;
use autodie;

use Exporter qw(import);

BEGIN {
    our @EXPORT_OK = qw(
      build_subject
    );
}

use Carp;
use Path::Tiny;
use List::MoreUtils qw(any);

use Test::Lintian::ConfigFile qw(read_config);
use Test::Lintian::Hooks qw(find_missing_prerequisites);

use constant EMPTY => q{};
use constant SPACE => q{ };
use constant COMMA => q{,};
use constant NEWLINE => qq{\n};

=head1 FUNCTIONS

=over 4

=item build_subject(PATH)

Populates a work directory RUN_PATH with data from the test located
in SPEC_PATH. The optional parameter REBUILD forces a rebuild if true.

=cut

sub build_subject {
    my ($sourcepath, $buildpath) = @_;

    # check test architectures
    die 'DEB_HOST_ARCH is not set.'
      unless (length $ENV{'DEB_HOST_ARCH'});

    # read dynamic file names
    my $runfiles = "$sourcepath/files";
    my $files = read_config($runfiles);

    # read dynamic case data
    my $rundescpath = "$sourcepath/$files->{fill_values}";
    my $testcase = read_config($rundescpath);

    # skip test if marked
    my $skipfile = "$sourcepath/skip";
    if (-f $skipfile) {
        my $reason = path($skipfile)->slurp_utf8 || 'No reason given';
        say "Skipping test: $reason";
        return;
    }

    # skip if missing prerequisites
    my $missing = find_missing_prerequisites($testcase);
    if (length $missing) {
        say "Missing prerequisites: $missing";
        return;
    }

    path($buildpath)->remove_tree
      if -e $buildpath;

    path($buildpath)->mkpath;

    # get lintian subject
    croak 'Could not get subject of Lintian examination.'
      unless exists $testcase->{build_product};
    my $subject = "$buildpath/$testcase->{build_product}";

    if(exists $testcase->{build_command}) {
        my $command= "cd $buildpath; $testcase->{build_command}";
        croak "$command failed" if system($command);
    }

    croak 'Build was unsuccessful.'
      unless -f $subject;

    die "Cannot link to build product $testcase->{build_product}"
      if system("cd $buildpath; ln -s $testcase->{build_product} subject");

    return;
}

=back

=cut

1;
