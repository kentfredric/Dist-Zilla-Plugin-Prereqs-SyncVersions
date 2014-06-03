use 5.008;    # pragma utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Prereqs::SyncVersions;

# ABSTRACT: Homogenize prerequisites so dependency versions are consistent

our $VERSION = '0.002000';

# AUTHORITY

use Moose qw( has with around );
use MooseX::Types::Moose qw( HashRef ArrayRef Str );
with 'Dist::Zilla::Role::PrereqSource';

=begin MetaPOD::JSON v1.1.0

{
    "namespace":"Dist::Zilla::Plugin::Prereqs::SyncVersions",
    "interface":"class",
    "inherits":"Moose::Object",
    "does":"Dist::Zilla::Role::PrereqSource"
}

=end MetaPOD::JSON

=cut

=head1 SYNOPSIS

    ; <bunch of metaprereq providing modules>

    [Prereqs::SyncVersions]

Note: This must come B<after> packages that add their own prerequisites in order to work as intended.

=head1 DESCRIPTION

This module exists to pose mostly as a workaround for potential bugs in downstream tool-chains.

Namely, C<CPAN.pm> is confused when it sees:

    runtime.requires : Foo >= 5.0
    test.requires    : Foo >= 6.0

It doesn't know what to do.

This is an easy enough problem to solve if you're using C<[Prereqs]> directly,
and C<[AutoPrereqs]> already does the right thing, but it gets messier
when you're working with L<< plugins that inject their own prerequisites|https://github.com/dagolden/Path-Tiny/commit/c620171db96597456a182ea6088a24d8de5debf6 >>

So this plugin will homogenize dependencies to be the same version in all phases
which infer the dependency, matching the largest one found, so the above becomes:

    runtime.requires : Foo >= 6.0
    test.requires    : Foo >= 6.0

=cut

=attr C<applyto_phase>

A multi-value attribute that specifies which phases to iterate and homogenize.

By default, this is:

    applyto_phase = build
    applyto_phase = test
    applyto_phase = runtime
    applyto_phase = configure

However, you could extend it further to include C<develop> if you wanted to.

    applyto_phase = build
    applyto_phase = test
    applyto_phase = runtime
    applyto_phase = configure
    appyyto_phase = develop

=cut

has applyto_phase => (
  is => ro =>,
  isa => ArrayRef [Str] =>,
  lazy    => 1,
  default => sub { [qw(build test runtime configure)] },
);

=attr C<applyto_relation>

A multi-value attribute that specifies which relations to iterate and homogenize.

By default, this is:

    applyto_relation = requires

However, you could extend it further to include C<suggests> and C<recommends> if you wanted to.
You could even add C<conflicts> ... but you really shouldn't.

    applyto_relation = requires
    applyto_relation = suggests
    applyto_relation = recommends
    applyto_relation = conflicts ; Danger will robinson.

=cut

has applyto_relation => (
  is => ro =>,
  isa => ArrayRef [Str],
  lazy    => 1,
  default => sub { [qw(requires)] },
);

=attr C<applyto>

A multi-value attribute that by default composites the values of

C<applyto_relation> and C<applyto_phase>.

This is if you want to be granular about how you specify phase/relations to process.

    applyto = runtime.requires
    applyto = develop.requires
    applyto = test.suggests

=cut

has applyto => (
  is => ro =>,
  isa => ArrayRef [Str] =>,
  lazy    => 1,
  builder => _build_applyto =>,
);

has _applyto_list => (
  is => ro =>,
  isa => ArrayRef [ ArrayRef [Str] ],
  lazy    => 1,
  builder => _build__applyto_list =>,
);

has _max_versions => (
  is      => ro  =>,
  isa     => HashRef,
  lazy    => 1,
  default => sub { {} },
);

sub _versionify {
  my ( undef, $version ) = @_;
  return $version if ref $version;
  require version;
  return version->parse($version);
}

sub _set_module_version {
  my ( $self, $module, $version ) = @_;
  if ( not exists $self->_max_versions->{$module} ) {
    $self->_max_versions->{$module} = $self->_versionify($version);
    return;
  }
  my $comparator = $self->_versionify($version);
  my $current    = $self->_max_versions->{$module};
  if ( $current < $comparator ) {
    $self->log_debug( [ 'Version upgrade on : %s', $module ] );
    $self->_max_versions->{$module} = $comparator;
  }
  return;
}

sub _get_module_version {
  my ( $self, $module ) = @_;
  return $self->_max_versions->{$module};
}

sub _build_applyto {
  my $self = shift;
  my @out;
  for my $phase ( @{ $self->applyto_phase } ) {
    for my $relation ( @{ $self->applyto_relation } ) {
      push @out, $phase . q[.] . $relation;
    }
  }
  return \@out;
}

sub _build__applyto_list {
  my $self = shift;
  my @out;
  for my $type ( @{ $self->applyto } ) {
    if ( $type =~ /^ ([^.]+) [.] ([^.]+) $/msx ) {
      push @out, [ "$1", "$2" ];
      next;
    }
    return $self->log_fatal( [ q[<<%s>> does not match << <phase>.<relation> >>], $type ] );
  }
  return \@out;
}

=method C<mvp_multivalue_args>

The following attributes exist, and may be specified more than once:

    applyto
    applyto_relation
    applyto_phase

=cut

sub mvp_multivalue_args { return qw( applyto applyto_relation applyto_phase ) }

around dump_config => sub {
  my ( $orig, $self ) = @_;
  my $config      = $self->$orig;
  my $this_config = {
    applyto_phase    => $self->applyto_phase,
    applyto_relation => $self->applyto_relation,
    applyto          => $self->applyto,
  };
  $config->{ q{} . __PACKAGE__ } = $this_config;
  return $config;
};

sub _foreach_phase_rel {
  my ( $self, $prereqs, $callback ) = @_;
  for my $applyto ( @{ $self->_applyto_list } ) {
    my ( $phase, $rel ) = @{$applyto};
    next if not exists $prereqs->{$phase};
    next if not exists $prereqs->{$phase}->{$rel};
    $callback->( $phase, $rel, $prereqs->{$phase}->{$rel}->as_string_hash );
  }
  return;
}

=method C<register_prereqs>

This method is called during C<Dist::Zilla> prerequisite generation,
and it injects supplementary prerequisites to make things match up.

=cut

sub register_prereqs {
  my ($self)  = @_;
  my $zilla   = $self->zilla;
  my $prereqs = $zilla->prereqs;
  my $guts = $prereqs->cpan_meta_prereqs->{prereqs} || {};

  $self->_foreach_phase_rel(
    $guts => sub {
      my ( undef, undef, $reqs ) = @_;
      for my $module ( keys %{$reqs} ) {
        $self->_set_module_version( $module, $reqs->{$module} );
      }
    },
  );
  $self->_foreach_phase_rel(
    $guts => sub {
      my ( $phase, $rel, $reqs ) = @_;
      for my $module ( keys %{$reqs} ) {
        my $v = $self->_get_module_version( $module, $reqs->{$module} );
        $zilla->register_prereqs( { phase => $phase, type => $rel }, $module, $v );
      }
    },
  );
  return $prereqs;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
