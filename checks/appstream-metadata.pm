# appstream-metadata -- lintian check script -*- perl -*-

# Copyright © 2016 Petter Reinholdtsen
# Copyright © 2017-2018 Chris Lamb <lamby@debian.org>
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

package Lintian::appstream_metadata;

# For .desktop files, the lintian check would be really easy: Check if
# .desktop file is there, check if matching file exists in
# /usr/share/metainfo, if not throw a warning. Maybe while we're at it
# also check for legacy locations (stuff in /usr/share/appdata) and
# legacy data (metainfo files starting with `<application>`).
#
# For modaliases, maybe udev rules could give some hints.
# Check modalias values to ensure hex numbers are using capital A-F.

use v5.20;
use warnings;
use utf8;
use autodie qw(open);

use File::Basename qw(basename);
use XML::LibXML;

use Moo;
use namespace::clean;

with 'Lintian::Check';

sub installable {
    my ($self) = @_;

    my $pkg = $self->package;
    my $type = $self->type;
    my $processable = $self->processable;
    my $group = $self->group;

    my (%desktopfiles, %metainfo, @udevrules);
    my $found_modalias = 0;
    my $modaliases = [];
    if (
        defined(
            my $dir
              = $processable->installed->resolve_path(
                'usr/share/applications/'))
    ) {
        for my $file ($dir->descendants) {
            $desktopfiles{$file} = 1 if ($file->is_file);
        }
    }
    if (
        defined(
            my $dir
              = $processable->installed->resolve_path('usr/share/metainfo/'))
    ) {
        for my $file ($dir->children) {
            if ($file->is_file) {
                $metainfo{$file} = 1;
                $found_modalias|= $self->check_modalias($file, $modaliases);
            }
        }
    }
    if (
        defined(
            my $dir
              = $processable->installed->resolve_path('usr/share/appdata/'))
    ) {
        for my $file ($dir->descendants) {
            if ($file->is_file) {
                $self->tag(('appstream-metadata-in-legacy-location', $file));
                $found_modalias|= $self->check_modalias($file, $modaliases);
            }
        }
    }
    if (
        defined(
            my $dir= $processable->installed->resolve_path('lib/udev/rules.d/')
        )
    ) {
        for my $file ($dir->descendants) {
            push(@udevrules, $file) if ($file->is_file);
        }
    }

    for my $udevrule (@udevrules) {
        if ($self->check_udev_rules($udevrule, $modaliases)
            && !$found_modalias) {
            $self->tag(
                ('appstream-metadata-missing-modalias-provide', $udevrule));
        }
    }
    return;
}

sub check_modalias {
    my ($self, $metadatafile, $modaliases) = @_;

    if (!$metadatafile->is_open_ok) {
        # FIXME report this as an error
        return;
    }

    my $parser = XML::LibXML->new;
    $parser->set_option('no_network', 1);

    my $doc = eval {$parser->parse_file($metadatafile->unpacked_path);};
    if ($@) {
        $self->tag('appstream-metadata-invalid',
            basename($metadatafile->unpacked_path));
        return 0;
    }

    return 0
      unless $doc;

    if ($doc->findnodes('/application')) {
        $self->tag('appstream-metadata-legacy-format', $metadatafile);
        return 0;
    }

    my @provides = $doc->findnodes('/component/provides');
    return 0
      unless @provides;

    # take first one
    my $first = $provides[0];
    return 0
      unless $first;

    my @nodes = $first->getChildrenByTagName('modalias');
    return 0
      unless @nodes;

    for my $node (@nodes) {

        my $alias = $node->firstChild->data;
        next
          unless $alias;

        push(@{$modaliases}, $alias);

        $self->tag('appstream-metadata-malformed-modalias-provide',
            $metadatafile,
            "include non-valid hex digit in USB matching rule '$alias'")
          if $alias =~ /^usb:v[0-9a-f]{4}p[0-9a-f]{4}d/i
          && $alias !~ /^usb:v[0-9A-F]{4}p[0-9A-F]{4}d/;
    }

    return 1;
}

sub provides_user_device {
    my ($self, $udevrulefile, $linenum, $rule, $data) = @_;

    my $retval = 0;

    if (   m/plugdev/
        || m/uaccess/
        || m/MODE=\"0666\"/) {
        $retval = 1;
    }
    if ($rule =~ m/SUBSYSTEM=="usb"/) {
        my ($vmatch, $pmatch);
        if ($rule =~ m/ATTR\{idVendor\}=="([0-9a-fA-F]{4})"/) {
            $vmatch = 'v' . uc($1);
        }
        if ($rule =~ m/ATTR\{idProduct\}=="([0-9a-fA-F]{4})"/) {
            $pmatch = 'p' . uc($1);
        }
        if (defined $vmatch && defined $pmatch) {
            my $match = "usb:${vmatch}${pmatch}d";
            my $foundmatch;
            for my $aliasmatch (@{$data}) {
                if (0 == index($aliasmatch, $match)) {
                    $foundmatch = 1;
                }
            }
            if (!$foundmatch) {
                $self->tag((
                    'appstream-metadata-missing-modalias-provide',
                    $udevrulefile, "match rule $match*"
                ));
            }
        }
    }
    return $retval;
}

sub check_udev_rules {
    my ($self, $file, $data) = @_;

    open(my $fd, '<', $file->unpacked_path);
    my $linenum = 0;
    my $cont;
    my $retval = 0;
    while (<$fd>) {
        chomp;
        $linenum++;
        if (defined $cont) {
            $_ = $cont . $_;
            $cont = undef;
        }
        if (/^(.*)\\$/) {
            $cont = $1;
            next;
        }
        next if /^#.*/; # Skip comments
        $retval |= $self->provides_user_device($file, $linenum, $_, $data);
    }
    close($fd);
    return $retval;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
