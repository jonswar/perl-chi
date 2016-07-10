package CHI::Driver::Role::HasSubcaches;

use Moo::Role;
use CHI::Types qw(:all);
use MooX::Types::MooseLike::Base qw(:all);
use Log::Any qw($log);
use Scalar::Util qw(weaken);
use strict;
use warnings;

my @subcache_nonoverride_params =
  qw(expires_at expires_in expires_variance serializer);

sub _non_overridable {
    my $params = shift;
    if ( is_HashRef($params) ) {
        if (
            my @nonoverride =
            grep { exists $params->{$_} } @subcache_nonoverride_params
          )
        {
            warn sprintf( "cannot override these keys in a subcache: %s",
                join( ", ", @nonoverride ) );
            delete( @$params{@nonoverride} );
        }
    }
    return $params;
}

my @subcache_inherited_params = (
    qw(expires_at expires_in expires_variance namespace on_get_error on_set_error serializer)
);

my @subcache_types = qw(l1_cache mirror_cache);

for my $type (@subcache_types) {
    my $config_acc = "_${type}_config";
    has $config_acc => (
        is       => 'ro',
        init_arg => $type,
        isa      => HashRef,
        coerce   => \&_non_overridable,
    );

    my $default = sub {
        my $self = shift;
        my $config = $self->$config_acc or return undef;

        my %inherit = map { ( defined $self->$_ ) ? ( $_ => $self->$_ ) : () }
          @subcache_inherited_params;

        # Don't instantiate the subcache with another subcache that's defined
        # using the core, namespace or storage defaults.
        #
        my @no_defaults_for = @{ $self->no_defaults_for || [] };
        push @no_defaults_for, @subcache_types;

        my $build_config = {
            %inherit,
            label => $self->label . ":$type",
            %$config,
            is_subcache     => 1,
            parent_cache    => $self,
            subcache_type   => $type,
            no_defaults_for => \@no_defaults_for,
        };

        return $self->chi_root_class->new(%$build_config);
    };

    has $type => (
        is       => 'ro',
        lazy     => 1,
        init_arg => undef,
        default  => $default,
        isa      => Maybe [ InstanceOf ['CHI::Driver'] ],
    );
}

has subcaches => (
    is       => 'lazy',
    init_arg => undef,
);

sub _build_subcaches {
    [ grep { defined $_ } $_[0]->l1_cache, $_[0]->mirror_cache ];
}

sub _build_has_subcaches { 1 }

# Call these methods first on the main cache, then on any subcaches.
#
foreach my $method (qw(clear expire purge remove set)) {
    after $method => sub {
        my $self      = shift;
        my $subcaches = $self->subcaches;
        foreach my $subcache (@$subcaches) {
            $subcache->$method(@_);
        }
    };
}

around 'get' => sub {
    my $orig = shift;
    my $self = shift;
    my ( $key, %params ) = @_;
    my $l1_cache = $self->l1_cache;

    if ( !defined($l1_cache) || $params{obj} ) {
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

                # If found in primary cache, write back to l1 cache.
                #
                my $obj = ${ $params{obj_ref} };
                $l1_cache->set(
                    $key,
                    $obj->value,
                    {
                        expires_at       => $obj->expires_at,
                        early_expires_at => $obj->early_expires_at
                    }
                );
            }
            return $value;
        }
    }
};

around 'get_multi_arrayref' => sub {
    my $orig   = shift;
    my $self   = shift;
    my ($keys) = @_;

    my $l1_cache = $self->l1_cache;
    if ( !defined($l1_cache) ) {
        return $self->$orig(@_);
    }
    else {

        # Consult l1 cache first, then call on primary cache with remainder of keys,
        # and combine the arrays.
        #
        my $l1_values = $l1_cache->get_multi_arrayref($keys);
        my @indices   = ( 0 .. scalar(@$keys) - 1 );
        my @primary_keys =
          map { $keys->[$_] } grep { !defined( $l1_values->[$_] ) } @indices;
        my $primary_values = $self->$orig( \@primary_keys );
        my $values         = [
            map {
                defined( $l1_values->[$_] )
                  ? $l1_values->[$_]
                  : shift(@$primary_values)
            } @indices
        ];
        return $values;
    }
};

1;
