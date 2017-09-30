# python -- lintian check script -*- perl -*-
#
# Copyright (C) 2016 Chris Lamb
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
# MA 02110-1301, USA.

package Lintian::python;
use strict;
use warnings;
use autodie;

use List::MoreUtils qw(any);

use Lintian::Tags qw(tag);

my @PYTHON2 = qw(python python2.7 python-dev);

sub run {
    my ($pkg, $type, $info) = @_;

    if ($type eq 'source') {
        _run_source($pkg, $info);
    } else {
        _run_binary($pkg, $info);
    }

    return;
}

sub _run_source {
    my ($pkg, $info) = @_;

    my @package_names = $info->binaries;
    foreach my $bin (@package_names) {
        # Python 2 modules
        if ($bin =~ /^python2?-(.*(?<!-doc))$/) {
            my $suffix = $1;
            tag 'python-foo-but-no-python3-foo', $bin
              unless any { $_ eq "python3-${suffix}" } @package_names;
        }
    }

    my $build_all = $info->relation('build-depends-all');
    tag 'build-depends-on-python-sphinx-only'
      if $build_all->implies('python-sphinx')
      and not $build_all->implies('python3-sphinx');

    tag 'alternatively-build-depends-on-python-sphinx-and-python3-sphinx'
      if $info->field('build-depends', '')
      =~ m,\bpython-sphinx\s+\|\s+python3-sphinx\b,g;

    return;
}

sub _run_binary {
    my ($pkg, $info) = @_;

    my @entries = $info->changelog ? $info->changelog->data : ();

    # Python 2 modules
    if ($pkg =~ /^python2?-.*(?<!-doc)$/) {
        tag 'new-package-should-not-package-python2-module'
          if @entries == 1;
    }

    # Python applications
    if ($pkg !~ /^python[23]?-/ and not any { $_ eq $pkg } @PYTHON2) {
        for my $field (qw(Depends Pre-Depends Recommends Suggests)) {
            for my $dep (@PYTHON2) {
                tag 'dependency-on-python-version-marked-for-end-of-life',
                  "($field: $dep)"
                  if $info->relation($field)->implies($dep);
            }
        }
    }

    # Django modules
    if ($pkg =~ /^(python[23]?-django)-.*(?<!-doc)$/) {
        my $version = $1;
        tag 'django-package-does-not-depend-on-django', $version
          if not $info->relation('strong')->implies($version);
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
