# languages/fortran/gfortran -- lintian check script -*- perl -*-

# Copyright © 2020 Felix Lechner
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

package Lintian::languages::fortran::gfortran;

use v5.20;
use warnings;
use utf8;

use Lintian::Util qw(open_gz);

use constant EMPTY => q{};

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub files {
    my ($self, $file) = @_;

    # file-info would be great, but files are zipped
    return
      unless $file->name =~ m{\.mod$};

    return
      unless $file->name =~ m{^usr/lib/};

    # do not look at flang, grub or libreoffice modules
    return
         if $file->name =~ m{/flang-\d+/}
      || $file->name =~ m{^usr/lib/grub}
      || $file->name =~ m{^usr/lib/libreoffice};

    return
         unless $file->is_file
      && $file->is_open_ok
      && $file->file_info =~ /\bgzip compressed\b/;

    my $module_version;

    my $fd = open_gz($file->unpacked_path);
    while (<$fd>) {
        next
          if /^\s*$/;

        ($module_version) = ($_ =~ /^GFORTRAN module version '(\d+)'/);
        last;
    }

    close($fd);

    unless (length $module_version) {
        $self->tag('gfortran-module-does-not-declare-version', $file->name);
        return;
    }

    my $depends = $self->processable->field('depends') // EMPTY;
    $self->tag('missing-prerequisite-for-gfortran-module', $file->name)
      unless $depends =~ /\bgfortran-mod-$module_version\b/;

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
