package CHI::Driver::Paired;
use Carp;
use Carp::Assert;
use CHI::Util qw(dp);
use Hash::MoreUtils qw(slice_exists);
use List::MoreUtils qw(uniq);
use Moose;
use Scalar::Util qw(blessed);
use strict;
use warnings;

has 'chi_root_class' => ( is => 'ro', required => 1 );
has 'no_populate_on_get' => ( is => 'ro' );
has 'primary_subcache'   => ( is => 'ro', required => 1 );
has 'read_order'         => ( is => 'ro', required => 1 );
has 'secondary_subcache' => ( is => 'ro', required => 1 );

my @paired_slots = qw(l1_cache mirror_to_cache);
foreach my $paired_slot (@paired_slots) {
    has $paired_slot => ( is => 'ro' );
}

__PACKAGE__->meta->make_immutable();

our $AUTOLOAD;

# These params are automatically inherited from the primary to the secondary cache,
# unless overriden specifically.
#
my @inherited_param_keys = (
    qw(expires_variance expires_at expires_in namespace on_get_error on_set_error)
);

# TODO: Document which constructor params are automatically inherited by secondary cache

sub BUILD {
    my ( $self, $params ) = @_;

    my $chi_root_class = $params->{chi_root_class};
    my %inherited_params =
      slice_exists( $params->{primary_subcache}, @inherited_param_keys );

    $self->{primary_subcache} =
      $chi_root_class->new( %{ $params->{primary_subcache} } );
    $self->{secondary_subcache} =
      $chi_root_class->new( %inherited_params,
        %{ $params->{secondary_subcache} } );
    $self->{read_order} = [
        map { [ $self->{primary_subcache}, $self->{secondary_subcache} ]->[$_] }
          @{ $params->{read_order} }
    ];
    $self->{write_order} = [
        map { [ $self->{primary_subcache}, $self->{secondary_subcache} ]->[$_] }
          @{ $params->{write_order} }
    ];
    $self->{ $params->{paired_slot} } = $self->{secondary_subcache}
      if defined( $params->{paired_slot} );
}

sub get {
    my $self = shift;
    my $key  = shift;

    my ( $value, $obj );
    my ( $read0, $read1 ) = @{ $self->{read_order} };
    if ( defined( $value = $read0->get( $key, @_ ) ) ) {
        return $value;
    }
    elsif (defined($read1)
        && defined( $value = $read1->get( $key, @_, obj_ref => \$obj ) ) )
    {
        unless ( $self->no_populate_on_get ) {

            # ** Should call store directly if possible - see set comments.
            $read0->set(
                $key, $value,
                {
                    expires_at       => $obj->expires_at,
                    early_expires_at => $obj->early_expires_at
                }
            );
        }
        return $value;
    }
    else {
        return undef;
    }
}

sub set {
    my ( $self, $key, $value, @args ) = @_;

    # ** Inefficient - should call store directly so we share common work of
    # ** serialization, etc. But can't if one of the driver classes has overriden set(),
    # ** or they have differing serializers, or, in general, if anything could cause the
    # ** set objects to be different.
    $self->write_for_each_subcache( sub { $_[0]->set( $key, $value, @args ) } );
    return $value;
}

foreach my $write_method (qw(remove clear set_multi set_object expire)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$write_method" } = sub {
        my ( $self, @args ) = @_;

        $self->write_for_each_subcache( sub { $_[0]->$write_method(@args) } );
    };
}

sub write_for_each_subcache {
    my ( $self, $code ) = @_;

    foreach my $subcache ( @{ $self->{write_order} } ) {
        $code->($subcache);
    }
}

sub isa {
    my $self = shift;

    return $self->SUPER::isa(@_)
      || ( blessed( $self->{primary_subcache} )
        && $self->{primary_subcache}->isa(@_) );
}

sub can {
    my $self = shift;

    return $self->SUPER::can(@_)
      || ( blessed( $self->{primary_subcache} )
        && $self->{primary_subcache}->can(@_) );
}

sub AUTOLOAD {
    my $self = shift;
    my ($method);

    ( $method = $AUTOLOAD ) =~ s/.*:://;
    return if $method eq 'DESTROY';

    return $self->primary_subcache->$method(@_);
}

sub check_for_paired_cache_alias {
    my ( $class, $chi_root_class, $params ) = @_;

    foreach my $paired_slot (@paired_slots) {
        if ( my $secondary_params = delete( $params->{$paired_slot} ) ) {
            my ( $read_order, $write_order );
            if ( $paired_slot eq 'l1_cache' ) {
                $read_order  = [ 1, 0 ];
                $write_order = [ 0, 1 ];
            }
            elsif ( $paired_slot eq 'mirror_to_cache' ) {
                $read_order = [0];
                $write_order = [ 0, 1 ];
            }
            return CHI::Driver::Paired->new(
                primary_subcache   => $params,
                secondary_subcache => $secondary_params,
                chi_root_class     => $chi_root_class,
                paired_slot        => $paired_slot,
                read_order         => $read_order,
                write_order        => $write_order,
            );
        }
    }
    return undef;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Paired

=head1 DESCRIPTION

This is an internal class that pairs two caches together. It is used to implement the
l1_cache and mirror_to_cache options, as a simpler alternative to CHI::Driver::Multilevel.

Eventually, this API may be cleaned up and made public, but for now, it is in flux. Don't
assume that anything here will stay stable.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
