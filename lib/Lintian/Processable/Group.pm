# Copyright © 2011 Niels Thykier <niels@thykier.net>
# Copyright © 2019 Felix Lechner
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

package Lintian::Processable::Group;

use strict;
use warnings;

use Moo;

use Carp;
use Time::HiRes qw(gettimeofday tv_interval);

use Lintian::Collect::Group;
use Lintian::Output qw(:messages);
use Lintian::Processable;
use Lintian::Util qw(internal_error get_dsc_info strip);

use constant EMPTY => q{};

has lab => (is => 'rw');
has name => (is => 'rw', default => EMPTY);

has source => (is => 'rw');
has changes => (is => 'rw');
has buildinfo => (is => 'rw');
has binary => (is => 'rw', default => sub{ {} });
has udeb => (is => 'rw', default => sub{ {} });

=head1 NAME

Lintian::Processable::Group -- A group of objects that Lintian can process

=head1 SYNOPSIS

 use Lintian::Processable::Group;

 my $group = Lintian::Processable::Group->new('lintian_2.5.0_i386.changes');
 foreach my $proc ($group->get_processables){
     printf "%s %s (%s)\n", $proc->pkg_name,
            $proc->pkg_version, $proc->pkg_type;
 }
 # etc.

=head1 DESCRIPTION

Instances of this perl class are sets of
L<processables|Lintian::Processable>.  It allows at most one source
and one changes or buildinfo package per set, but multiple binary packages
(provided that the binary is not already in the set).

=head1 METHODS

=over 4

=item Lintian::Processable::Group->init_from_file (FILE)

Add all processables from .changes or .buildinfo file FILE.

=cut

#  populates $self from a buildinfo or changes file.
sub init_from_file {
    my ($self, $path) = @_;

    return
      unless defined $path;

    my $processable = Lintian::Processable::Package->new($path);
    $self->add_processable($processable);

    my ($type) = $path =~ m/\.(buildinfo|changes)$/;
    return
      unless defined $type;

    my $info = get_dsc_info($path)
      or internal_error("$path is not a valid $type file");

    my $dir = $path;
    if ($path =~ m,^/+[^/]++$,o){
        # it is "/files.changes?"
        #  - In case you were wondering, we were told not to ask :)
        #   See #624149
        $dir = '/';
    } else {
        # it is "<something>/files.changes"
        $dir =~ s,(.+)/[^/]+$,$1,;
    }
    my $key = $type eq 'buildinfo' ? 'checksums-sha256' : 'files';
    for my $line (split(/\n/o, $info->{$key}//'')) {

        next
          unless defined $line;

        strip($line);

        next
          if $line eq '';

        # Ignore files that may lead to path traversal issues.

        # We do not need (eg.) md5sum, size, section or priority
        # - just the file name please.
        my $file = (split(/\s+/o, $line))[-1];

        # If the field is malformed, $file may be undefined; we also
        # skip it, if it contains a "/" since that is most likely a
        # traversal attempt
        next
          if !$file || $file =~ m,/,o;

        unless (-f "$dir/$file") {
            print STDERR "$dir/$file does not exist, exiting\n";
            exit 2;
        }

        if (    $file !~ /\.u?deb$/o
            and $file !~ m/\.dsc$/o
            and $file !~ m/\.buildinfo$/o) {

            # Some file we do not care about (at least not here).
            next;
        }

        my $payload = Lintian::Processable::Package->new("$dir/$file");
        $self->add_processable($payload);
    }

    return 1;
}

=item prep_unpack_error

Error handler.

=cut

sub prep_unpack_error {
    my ($self, $action, $exit_code_ref, $lpkg) = @_;
    my $err = $!;
    my $pkg_type = $lpkg->pkg_type;
    my $pkg_name = $lpkg->pkg_name;
    warning(
        "could not create the package entry in the lab: $err",
        "skipping $action of $pkg_type package $pkg_name"
    );
    $$exit_code_ref = 2;
    $self->remove_processable($lpkg);
    return;
}

=item unpack

Unpack this group.

=cut

sub unpack {
    my ($self, $unpacker, $action, $exit_code_ref)= @_;
    my $all_ok = 1;
    my $errhandler = sub {
        $all_ok = 0;
        $self->prep_unpack_error($action, $exit_code_ref, @_);
    };

    # Kill pending jobs, if any
    $unpacker->kill_jobs;
    $unpacker->reset_worklist;

    # Stop here if there is nothing list for us to do
    return
      unless $unpacker->prepare_tasks($errhandler, $self->get_processables);

    v_msg('Unpacking packages in group ' . $self->name);

    my (%timers, %hooks);
    $hooks{'coll-hook'}= sub {
        $self->coll_hook($action, $exit_code_ref, \%timers, @_)
          or $all_ok = 0;
    };

    $unpacker->process_tasks(\%hooks);
    return $all_ok;
}

=item coll_hook

Collection hook.

=cut

sub coll_hook {
    my (
        $self, $action, $exit_code_ref,$timers, $lpkg,
        $event, $cs, $task_id, $exitval
    )= @_;
    my $coll = $cs->name;
    my $procid = $lpkg->identifier;
    my $ok = 1;

    if ($event eq 'start') {
        $timers->{$task_id} = [gettimeofday];
        debug_msg(1, "Collecting info: $coll for $procid ...");
    } elsif ($event eq 'start-failed') {
        # failed
        my $pkg_name = $lpkg->pkg_name;
        my $pkg_type = $lpkg->pkg_type;
        warning(
            "collect info $coll about package $pkg_name failed",
            "skipping $action of $pkg_type package $pkg_name",
            "error: $exitval"
        );
        $$exit_code_ref = 2;
        $ok = 0;
        $self->remove_processable($lpkg);
    } elsif ($event eq 'finish') {
        if ($exitval) {
            # Failed
            my $pkg_name  = $lpkg->pkg_name;
            my $pkg_type = $lpkg->pkg_type;
            warning(
                "collect info $coll about package $pkg_name failed ($exitval)"
            );
            warning("skipping $action of $pkg_type package $pkg_name");
            $$exit_code_ref = 2;
            $ok = 0;
            $self->remove_processable($lpkg);
        } else {
            # success
            my $raw_res = tv_interval($timers->{$task_id});
            my $tres = sprintf('%.3fs', $raw_res);
            debug_msg(1, "Collection script $coll for $procid done ($tres)");
            perf_log("$procid,coll/$coll,${raw_res}");
        }
    }
    return $ok;
}

=item post_pkg_process_overrides

Process overrides.

=cut

sub post_pkg_process_overrides{
    my ($lpkg, $TAGS, $overrides, $opt) = @_;

    # Report override statistics.
    unless ($opt->{'no-override'} || $opt->{'show-overrides'}) {

        my $stats = $TAGS->statistics($lpkg);

        my $errors = $stats->{overrides}{types}{E} || 0;
        my $warnings = $stats->{overrides}{types}{W} || 0;
        my $info = $stats->{overrides}{types}{I} || 0;

        $overrides->{errors} += $errors;
        $overrides->{warnings} += $warnings;
        $overrides->{info} += $info;
    }

    return;
}

=item process

Process group.

=cut

sub process {
    my ($self, $PROFILE, $TAGS,$collmap, $exit_code_ref, $overrides,
        $opt, $memory_usage)
      = @_;

    my $all_ok = 1;

    my $timer = [gettimeofday];

  PROC:
    foreach my $lpkg ($self->get_processables){
        my $pkg_type = $lpkg->pkg_type;
        my $procid = $lpkg->identifier;

        $TAGS->file_start($lpkg);

        debug_msg(1, 'Base directory in lab: ' . $lpkg->base_dir);

        if (not $opt->{'no-override'} and $collmap->getp('override-file')) {
            debug_msg(1, 'Loading overrides file (if any) ...');
            $TAGS->load_overrides;
        }

        # Filter out the "lintian" check if present - it does no real harm,
        # but it adds a bit of noise in the debug output.
        my @scripts = sort $PROFILE->scripts;
        @scripts = grep { $_ ne 'lintian' } @scripts;

        foreach my $script (@scripts) {
            my $cs = $PROFILE->get_script($script);
            my $check = $cs->name;
            my $timer = [gettimeofday];

            # The lintian check is done by this frontend and we
            # also skip the check if it is not for this type of
            # package.
            next
              if !$cs->is_check_type($pkg_type);

            debug_msg(1, "Running check: $check on $procid  ...");
            eval {$cs->run_check($lpkg, $self);};
            my $err = $@;
            my $raw_res = tv_interval($timer);

            if ($err) {
                print STDERR $err;
                print STDERR "internal error: cannot run $check check",
                  " on package $procid\n";
                warning("skipping check of $procid");
                $$exit_code_ref = 2;
                $all_ok = 0;
                next PROC;
            }
            my $tres = sprintf('%.3fs', $raw_res);
            debug_msg(1, "Check script $check for $procid done ($tres)");
            perf_log("$procid,check/$check,${raw_res}");
        }

        unless ($$exit_code_ref) {
            my $stats = $TAGS->statistics($lpkg);
            if ($stats->{types}{E}) {
                $$exit_code_ref = 1;
            }
        }
        post_pkg_process_overrides($lpkg, $TAGS, $overrides);
    } # end foreach my $lpkg ($self->get_processable)

    $TAGS->file_end;

    my $raw_res = tv_interval($timer);
    my $tres = sprintf('%.3fs', $raw_res);
    debug_msg(1, 'Checking all of group ' . $self->name . " done ($tres)");
    perf_log($self->name . ",total-group-check,${raw_res}");

    if ($opt->{'debug'} > 2) {
        my $pivot = ($self->get_processables)[0];
        my $group_id = $pivot->pkg_src . '/' . $pivot->pkg_src_version;
        my $group_usage
          = $memory_usage->([map { $_->info } $self->get_processables]);
        debug_msg(3, "Memory usage [$group_id]: $group_usage");
        for my $lpkg ($self->get_processables) {
            my $id = $lpkg->identifier;
            my $usage = $memory_usage->($lpkg->info);
            my $breakdown = $lpkg->info->_memory_usage($memory_usage);
            debug_msg(3, "Memory usage [$id]: $usage");
            for my $field (sort(keys(%{$breakdown}))) {
                debug_msg(4, "  -- $field: $breakdown->{$field}");
            }
        }
    }

    return $all_ok;
}

=item clean_lab

Removes the lab files to conserve disk space. Global destruction will
also get these unless we are keeping the lab.

=cut

sub clean_lab {
    my ($self) = @_;

    my $total = [gettimeofday];

    for my $processable ($self->get_processables) {

        my $proc_id = $processable->identifier;
        debug_msg(1, "Auto removing: ${proc_id} ...");
        my $each = [gettimeofday];

        $processable->remove;

        my $raw_res = tv_interval($each);
        debug_msg(1, "Auto removing: ${proc_id} done (${raw_res}s)");
        perf_log("$proc_id,auto-remove entry,${raw_res}");
    }

    my $raw_res = tv_interval($total);
    my $tres = sprintf('%.3fs', $raw_res);
    debug_msg(1,'Auto-removal all for group ' . $self->name . " done ($tres)");
    perf_log($self->name . ",total-group-auto-remove,${raw_res}");

    return;
}

=item $group->add_processable($proc)

Adds $proc to $group.  At most one source and one changes $proc can be
in a $group.  There can be multiple binary $proc's, as long as they
are all unique.  Successive buildinfo $proc's are silently ignored.

This will error out if an additional source or changes $proc is added
to the group. Otherwise it will return a truth value if $proc was
added.

=cut

sub add_processable{
    my ($self, $processable) = @_;

    my $pkg_type = $processable->pkg_type;

    if ($processable->tainted) {
        warn(
            sprintf(
                "warning: tainted %1\$s package '%2\$s', skipping\n",
                $pkg_type, $processable->pkg_name
            ));
        return 0;
    }

    return 0
      if length $self->name
      && $self->name ne $processable->get_group_id;

    $self->name($processable->get_group_id)
      unless length $self->name;

    croak 'Please set lab first.'
      unless $self->lab;

    my $mapped = $self->lab->get_package($processable);

    if ($pkg_type eq 'changes') {
        internal_error("Cannot add another $pkg_type file")
          if $self->changes;
        $self->changes($mapped);

    } elsif ($pkg_type eq 'buildinfo') {
        # Ignore multiple .buildinfo files; use the first one
        $self->buildinfo($mapped)
          unless $self->buildinfo;

    } elsif ($pkg_type eq 'source'){
        internal_error('Cannot add another source package')
          if $self->source;
        $self->source($mapped);

    } else {
        my $phash;
        my $id = $processable->identifier;
        internal_error("Unknown type $pkg_type")
          unless ($pkg_type eq 'binary' or $pkg_type eq 'udeb');
        $phash = $self->$pkg_type;

        # duplicate ?
        return 0
          if exists $phash->{$id};

        $phash->{$id} = $mapped;
    }
    $processable->group($self);
    return 1;
}

=item $group->get_processables([$type])

Returns an array of all processables in $group.  The processables are
returned in the following order: changes (if any), source (if any),
all binaries (if any) and all udebs (if any).

This order is based on the original order that Lintian processed
packages in and some parts of the code relies on this order.

Note if $type is given, then only processables of that type is
returned.

=cut

sub get_processables {
    my ($self, $type) = @_;
    my @result;
    if (defined $type){
        # We only want $type
        if ($type eq 'changes' or $type eq 'source' or $type eq 'buildinfo'){
            return $self->$type;
        }
        return values %{$self->$type}
          if $type eq 'binary'
          or $type eq 'udeb';
        internal_error("Unknown type of processable: $type");
    }
    # We return changes, dsc, buildinfo, debs and udebs in that order,
    # because that is the order lintian used to process a changes
    # file (modulo debs<->udebs ordering).
    #
    # Also correctness of other parts rely on this order.
    foreach my $type (qw(changes source buildinfo)){
        push @result, $self->$type if $self->$type;
    }
    foreach my $type (qw(binary udeb)){
        push @result, values %{$self->$type};
    }
    return @result;
}

=item $group->remove_processable($proc)

Removes $proc from $group

=cut

sub remove_processable {
    my ($self, $proc) = @_;
    my $pkg_type = $proc->pkg_type;
    if (   $pkg_type eq 'source'
        or $pkg_type eq 'changes'
        or $pkg_type eq 'buildinfo'){

        $self->$pkg_type(undef);

    } else {
        my $phash = $self->$pkg_type;
        my $id = $proc->identifier;

        delete $phash->{$id};
    }
    return 1;
}

=item $group->get_binary_processables

Returns all binary (and udeb) processables in $group.

If $group does not have any binary processables then an empty list is
returned.

=cut

sub get_binary_processables {
    my ($self) = @_;
    my @result;
    foreach my $type (qw(binary udeb)){
        push @result, values %{$self->$type};
    }
    return @result;
}

=item $group->info

Returns L<$info|Lintian::Collect::Group> element for this group.

=cut

sub info {
    my ($self) = @_;
    my $info = $self->{info};
    if (!defined $info) {
        $info = Lintian::Collect::Group->new($self);
        $self->{info} = $info;
    }
    return $info;
}

=item $group->init_shared_cache

Prepare a shared memory cache for all current members of the group.
This is solely a memory saving optimization and is not required for
correct performance.

=cut

sub init_shared_cache {
    my ($self) = @_;
    $self->info; # Side-effect of creating the info object.
    return;
}

=item $group->clear_cache

Discard the info element of all members of this group, so the memory
used by it can be reclaimed.  Mostly useful when checking a lot of
packages (e.g. on lintian.d.o).

=cut

sub clear_cache {
    my ($self) = @_;
    for my $proc ($self->get_processables) {
        $proc->clear_cache;
    }
    delete $self->{info};
    return;
}

=back

=head1 AUTHOR

Originally written by Niels Thykier <niels@thykier.net> for Lintian.

=head1 SEE ALSO

lintian(1)

L<Lintian::Processable>

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et