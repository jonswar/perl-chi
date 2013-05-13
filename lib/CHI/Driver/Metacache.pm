package CHI::Driver::Metacache;
use CHI::Constants qw(CHI_Meta_Namespace);
use Moo;
use strict;
use warnings;

has 'meta_cache'      => ( is => 'lazy', clearer => 'clear_meta_cache', predicate => 'has_meta_cache');
has 'owner_cache'     => ( is => 'ro', weak_ref => 1 );
has 'owner_namespace' => ( is => 'lazy', clearer => 'clear_owner_namespace', predicate => 'has_owner_namespace');

sub _build_meta_cache {
    my ($self) = @_;

    my $owner_cache = $self->owner_cache;
    my %params      = %{ $owner_cache->constructor_params };
    delete( @params{qw(l1_cache mirror_cache parent_cache chi_root_class)} );
    $params{label}     = $owner_cache->label . " (meta)";
    $params{namespace} = CHI_Meta_Namespace;
    return $owner_cache->chi_root_class->new(%params);
}

sub _build_owner_namespace {
    my ($self) = @_;

    return $self->owner_cache->namespace;
}

sub get {
    my ( $self, $key ) = @_;

    return $self->meta_cache->fetch( $self->_prefixed_key($key) );
}

sub set {
    my ( $self, $key, $value ) = @_;

    return $self->meta_cache->store( $self->_prefixed_key($key), $value );
}

sub remove {
    my ( $self, $key, $value ) = @_;

    return $self->meta_cache->remove( $self->_prefixed_key($key) );
}

sub _prefixed_key {
    my ( $self, $key ) = @_;

    return $self->owner_namespace . ":" . $key;
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Metacache - Metacache for internal CHI use

=head1 SYNOPSIS

    $cache->metacache->get($meta_key);
    $cache->metacache->set($meta_key => $value);

=cut
