use strict;
use warnings;

package Dist::Zilla::Plugin::Prereqs::SyncVersions;
BEGIN {
  $Dist::Zilla::Plugin::Prereqs::SyncVersions::AUTHORITY = 'cpan:KENTNL';
}
{
  $Dist::Zilla::Plugin::Prereqs::SyncVersions::VERSION = '0.1.0';
}

# ABSTRACT: Homogenise prerequisites so dependent versions are consistent

use Moose;
use MooseX::Types::Moose qw( HashRef ArrayRef Str );
with 'Dist::Zilla::Role::PrereqSource';


has applyto_phase => (
  is => ro =>,
  isa => ArrayRef [Str] =>,
  lazy    => 1,
  default => sub { [qw(build test runtime configure)] },
);
 
 
has applyto_relation => (
  is => ro => isa => ArrayRef [Str],
  lazy    => 1,
  default => sub { [qw(requires recommends suggests)] },
);
 
 
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
    is => ro =>,
    isa => HashRef,
    lazy => 1, 
    default => sub {  {} },
);

sub _versionify {
    my ( $self, $version ) = @_;
    return $version if ref $version;
    require version;
    return version->parse($version);
}

sub _set_module_version { 
    my ( $self, $module, $version ) = @_;
    if ( not exists $self->_max_versions->{ $module } ) { 
        $self->_max_versions->{ $module } = $self->_versionify( $version );
    }
    my $comparator = $self->_versionify( $version );
    my $current    = $self->_max_versions->{ $module };
    if ( $current < $comparator ) {
        $self->log("Version upgrade on : " . $module );
        $self->_max_version->{$module} = $comparator;
    }
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

sub mvp_multivalue_args { return qw( applyto applyto_relation applyto_phase ) }
 
sub mvp_aliases { return { 'module' => 'modules' } }

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

sub foreach_phase_rel {
    my ( $self, $prereqs, $callback ) = @_;
    for my $applyto ( @{ $self->_applyto_list } ) {
        my ( $phase, $rel ) = @{$applyto};
        next if not exists $prereqs->{$phase};
        next if not exists $prereqs->{$phase}->{$rel};
        $callback->( $phase, $rel , $prereqs->{$phase}->{$rel}->as_string_hash );
    }
    return;
}

sub register_prereqs {
  my ($self)  = @_;
  my $zilla   = $self->zilla;
  my $prereqs = $zilla->prereqs;
  my $guts = $prereqs->cpan_meta_prereqs->{prereqs} || {};
 
  $self->foreach_phase_rel( $guts => sub {
    my ( $phase, $rel, $reqs ) = @_;
    for my $module ( keys %{$reqs} ) {
      $self->_set_module_version( $module, $reqs->{$module} );
    }
  });
  $self->foreach_phase_rel( $guts => sub {
    my ( $phase, $rel, $reqs ) = @_;
    for my $module ( keys %{$reqs} ) {
      my $v = $self->_get_module_version( $module, $reqs->{$module} );
      $zilla->register_prereqs( { phase => $phase, type => $rel }, $module, $v  );
    }
  });
  return $prereqs;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Dist::Zilla::Plugin::Prereqs::SyncVersions - Homogenise prerequisites so dependent versions are consistent

=head1 VERSION

version 0.1.0

=head1 SYNOPSIS

This module exists to pose mostly as a workaround for potential bugs in downstream toolchains.

Namely, CPAN.pm is confused when it sees:

    runtime.requires : Foo >= 5.0
    test.requires    : Foo >= 6.0

It doesn't know what to do.

This is an easy enough problem to solve if you're using C<[Prereqs]> directly,
and C<[AutoPrereqs]> already does the right thing, but it gets messier
when you're working with L<< plugins that inject their own prereqs|https://github.com/dagolden/Path-Tiny/commit/c620171db96597456a182ea6088a24d8de5debf6 >>

So this plugin will homogenise dependencies to be the same version in all phases
which infer the dependency, matching the largest one found, so the above becomes:

    runtime.requires : Foo >= 6.0
    test.requires    : Foo >= 6.0

=head1 AUTHOR

Kent Fredric <kentfredric@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
