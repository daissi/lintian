# files/init -- lintian check script -*- perl -*-

# Copyright © 1998 Christian Schwarz and Richard Braakman
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

package Lintian::files::init;

use v5.20;
use warnings;
use utf8;
use autodie;

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub files {
    my ($self, $file) = @_;

    # /etc/init
    $self->tag('package-installs-deprecated-upstart-configuration',$file->name)
      if $file->name =~ m,^etc/init/\S,;

    # /etc/init.d
    $self->tag(
        'non-standard-file-permissions-for-etc-init.d-script',
        sprintf('%s %04o != 0755', $file->name, $file->operm))
      if $file->name =~ m,^etc/init\.d/\S,
      && $file->name !~ m,^etc/init\.d/(?:README|skeleton)$,
      && $file->operm != 0755
      && $file->is_file;

    # /etc/rc.d && /etc/rc?.d
    $self->tag('package-installs-into-etc-rc.d', $file->name)
      if $file->name =~ m,^etc/rc(?:\d|S)?\.d/\S,
      && $self->package !~ /^(?:sysvinit|file-rc)$/
      && $self->type ne 'udeb';

    # /etc/rc.boot
    $self->tag('package-installs-into-etc-rc.boot', $file->name)
      if $file->name =~ m,^etc/rc\.boot/\S,;

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
