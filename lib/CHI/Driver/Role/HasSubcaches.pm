package CHI::Driver::Role::HasSubcaches;
use Moose::Role;
use Hash::MoreUtils qw(slice_exists);
use Log::Any qw($log);
use Scalar::Util qw(weaken);
use strict;
use warnings;

has 'l1_cache'     => ( is => 'ro', isa     => 'CHI::Types::UnblessedHashRef' );
has 'mirror_cache' => ( is => 'ro', isa     => 'CHI::Types::UnblessedHashRef' );
has 'subcaches'    => ( is => 'ro', default => sub { [] }, init_arg => undef );

# List of parameter keys that initialize a subcache
#
my @subcache_types = qw(l1_cache mirror_cache);

after 'BUILD_roles' => sub {
    my ( $self, $params ) = @_;

    $self->{has_subcaches} = 1;

    # Create subcaches as necessary (l1_cache, mirror_cache)
    # Eventually might allow existing caches to be passed
    #
    foreach my $subcache_type (@subcache_types) {
        if ( my $subcache_params = $params->{$subcache_type} ) {
            $self->add_subcache( $params, $subcache_type, $subcache_params );
        }
    }
};

# List of parameters that are automatically inherited by a subcache
#
my @subcache_inherited_param_keys = (
    qw(expires_at expires_in expires_variance namespace on_get_error on_set_error serializer)
);

# List of parameters that cannot be overriden in a subcache
#
my @subcache_nonoverride_param_keys =
  (qw(expires_at expires_in expires_variance serializer));

# Add a subcache with the specified type and params - called from BUILD
#
sub add_subcache {
    my ( $self, $params, $subcache_type, $subcache_params ) = @_;

    if ( my %nonoverride_params =
        slice_exists( $subcache_params, @subcache_nonoverride_param_keys ) )
    {
        my @nonoverride_keys = sort keys(%nonoverride_params);
        warn sprintf( "cannot override these keys in a subcache: %s",
            join( ", ", @nonoverride_keys ) );
        delete( @$subcache_params{@nonoverride_keys} );
    }

    my $chi_root_class = $self->chi_root_class;
    my %inherited_params =
      slice_exists( $params, @subcache_inherited_param_keys );
    my $default_label = $self->label . ":$subcache_type";

    my $subcache = $chi_root_class->new(
        label => $default_label,
        %inherited_params, %$subcache_params,
        is_subcache   => 1,
        parent_cache  => $self,
        subcache_type => $subcache_type,
    );
    $self->{$subcache_type} = $subcache;
    push( @{ $self->{subcaches} }, $subcache );
}

# Call these methods first on the main cache, then on any subcaches.
#
foreach my $method (qw(clear expire expire_if purge remove)) {
    after $method => sub {
        my $self      = shift;
        my $subcaches = $self->subcaches;
        foreach my $subcache (@$subcaches) {
            $subcache->$method(@_);
        }
    };
}

after 'set_object' => sub {
    my ( $self, $key, $obj ) = @_;

    my $subcaches = $self->subcaches;
    foreach my $subcache (@$subcaches) {
        $subcache->set_object( $key, $obj );
        $subcache->_log_set_result( $log, $obj )
          if $log->is_debug;
    }
};

around 'get' => sub {
    my $orig     = shift;
    my $self     = shift;
    my $l1_cache = $self->l1_cache;

    if ( !defined($l1_cache) ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first
        #
        if ( defined( my $value = $l1_cache->get(@_) ) ) {
            return $value;
        }
        else {
            my ( $key, %params ) = @_;
            $params{obj_ref} ||= \my $obj_store;
            my $value = $self->$orig( $key, %params );
            if ( defined($value) ) {

                # If found in primary cache, write back to l1 cache. Use same $obj,
                # meaning same metadata and serialization.
                #
                my $key = $_[0];
                my $obj = ${ $params{obj_ref} };
                $l1_cache->set_object( $key, $obj );
            }
            return $value;
        }
    }
};

around 'get_multi_hashref' => sub {
    my $orig   = shift;
    my $self   = shift;
    my ($keys) = @_;

    my $l1_cache = $self->l1_cache;
    if ( !defined($l1_cache) ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first, then call on primary cache with remainder of keys,
        # and combine the hashes.
        #
        my $l1_result      = $l1_cache->get_multi_hashref($keys);
        my @primary_keys   = grep { !defined( $l1_result->{$_} ) } @$keys;
        my $primary_result = $self->$orig( \@primary_keys );
        my $result         = { %$l1_result, %$primary_result };
        return $result;
    }
};

1;
