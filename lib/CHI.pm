package CHI;
use CHI::NullLogger;
use strict;
use warnings;

our $Logger = CHI::NullLogger->new();

sub logger {
    my $self = shift;
    if (@_) {
        $Logger = shift;
    }
    return $Logger;
}

sub new {
    my ( $class, %params ) = @_;

    my $driver_class;
    if ( my $driver = delete( $params{driver} ) ) {
        $driver_class = "CHI::Driver::$driver";
    }
    else {
        $driver_class = delete( $params{driver_class} );
    }
    die "missing required param 'driver' or 'driver_class'"
      unless defined $driver_class;
    eval "require $driver_class";
    die $@ if $@;

    return $driver_class->new( \%params );
}

1;

__END__

=pod

=head1 NAME

CHI -- Unified cache interface

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new( driver => 'Memory' );
    my $cache = CHI->new( driver => 'File', cache_root => '/path/to/root' );
    my $cache = CHI->new(
        driver     => 'FastMmap',
        root_dir   => '/path/to/root',
        cache_size => '1k'
    );
    my $cache = CHI->new(
        driver  => 'Memcached',
        servers => [ "10.0.0.15:11211", "10.0.0.15:11212" ]
    );
    my $cache = CHI->new(
        driver => 'Multilevel',
        subcaches => [
            { driver => 'Memory' },
            {
                driver  => 'Memcached',
                servers => [ "10.0.0.15:11211", "10.0.0.15:11212" ]
            }
        ],
    );

    my $cache = CHI->new( driver_class => 'My::Special::Driver' );

    # (These drivers coming soon...)
    #
    my $cache = CHI->new( driver => 'DBI', dbh => $dbh, table => 'app_cache' );
    my $cache = CHI->new( driver => 'BerkeleyDB', root_dir => '/path/to/root' );

    my $customer = $cache->get($name);
    if ( !defined $customer ) {
        $customer = get_customer_from_db($name);
        $cache->set( $name, $customer, "10 minutes" );
    }
    $cache->clear($name);

=head1 DESCRIPTION

CHI provides a unified caching API, designed to assist a developer in persisting data for
a specified period of time.

The CHI interface is implemented by driver classes that support fetching, storing and
clearing of data. Driver classes exist or will exist for the gamut of storage backends
available to Perl, such as memory, plain files, memory mapped files, memcached, and DBI.

=head1 RELATION TO CACHE::CACHE

CHI is intended as an evolution of DeWitt Clinton's venerable Cache::Cache package. It
starts with the same basic API (which has proven durable over time) but addresses some
implementation shortcomings that cannot be fixed in Cache::Cache due to backward
compatibility concerns.  In particular:

=over

=item Performance

Some of Cache::Cache's subclasses (e.g. Cache::FileCache) have been justifiably criticized
as inefficient. CHI has been designed from the ground up with performance in mind, both in
terms of general overhead and in the built-in driver classes.  Method calls are kept to a
minimum, data is only serialized when necessary, and metadata such as expiration time is
stored in packed binary format alongside the data.

=item Ease of subclassing

New Cache::Cache subclasses can be tedious to create, due to a lack of code refactoring,
the use of non-OO package subroutines, and the separation of "cache" and "backend"
classes. With CHI, the goal is to make the creation of new drivers as easy as possible,
roughly the same as writing a TIE interface to your data store.  Concerns like
serialization and expiration options are handled by the driver base class so that
individual drivers don't have to worry about them.

=item Increased compatibility with cache implementations

Probably because of the reasons above, Cache::Cache subclasses were never created for some
of the most popular caches available on CPAN, e.g. Cache::FastMmap and Cache::Memcached.
CHI's goal is to be able to support these and other caches with a minimum performance
overhead and minimum of glue code required.

=back

=head1 CONSTRUCTOR

To create a new cache handle, call CHI->new. It takes the following common options.

=over

=item driver [STRING]

The name of a standard driver to drive the cache, for example "Memory" or "File".  CHI
will prefix the string with "CHI::Driver::".

=item driver_class [STRING]

The exact CHI::Driver subclass to drive the cache, for example "My::Memory::Driver".

=item namespace [STRING]

Identifies a namespace that all cache entries for this object will be in. This allows
separation of multiple caches with different data but conflicting keys.

Defaults to the package from which new() was called, which means that each package will
automatically have its own cache. If you want multiple packages to share the same cache,
just decide a common namespace like 'main'.

=item expires_in [DURATION]
=item expires_at [NUM]
=item expires_variance [FLOAT]

Provide default values for the corresponding set() options - see set().

=item on_set_error

How to handle runtime errors occurring during cache writes, which may or may not
be considered fatal in your application. Options are:

=over

=item *

ignore - do nothing

=item *

warn - call warn() with an appropriate message

=item *

die - call die() with an appropriate message

=item *

I<coderef> - call this code reference with three arguments: an appropriate message, the key, and the original raw error message

=back

Each driver will take additional options specific to that driver. For example, the File
driver takes root_dir and depth options.

=back

=head1 METHODS

The following methods can be called on any cache handle returned from CHI->new(). They are implemented in the L<Cache::Driver> package.

=over

=item get( $key, [option => value, ...] )

Returns the data associated with I<$key>. If I<$key> does not exist or has expired, returns undef.
Expired items are not automatically removed and may be examined with L</get_object> or L</get_expires_at>.

I<$key> may be followed by one or more name/value parameters:

=over

=item expire_if => $code

If I<$key> exists and has not expired, call code reference I<$code> with the
L<CHI::CacheObject> as a single parameter. If I<$code> returns a true value, expire the
data. e.g.

    $cache->get('foo', expire_if => sub { $_[0]->created_at < (stat($file))[9] });

=item busy_lock => $duration

If the value has expired, set its expiration time to the current time plus I<$duration>
before returning undef.  This is used to prevent multiple processes from recomputing the
same expensive value simultaneously. I<$duration> may be any valid
L<duration expression|/DURATION EXPRESSIONS>.

=back

=item set( $key, $data, [$expires_in | options] )

Associates I<$data> with I<$key> in the cache, overwriting any existing entry.

The third argument to set() is optional, and may be either a scalar or a hash reference.
If it is a scalar, it is treated as an I<expires_in> value described below. If it is a
hash reference, it may contain one or more of the following options. Most of these options
can be provided with defaults in the cache constructor.

=over

=item expires_in [DURATION]

Amount of time until this data expires; see L</DURATION EXPRESSIONS> for the possible
forms this can take.

=item expires_at [NUM]

The epoch time at which the data expires.

=item expires_variance [FLOAT]

Controls the variable expiration feature, which allows items to expire a little earlier
than the stated expiration time to help prevent cache miss stampedes.

Value is between 0.0 and 1.0, with 0.0 meaning that items expire exactly when specified
(feature is disabled), and 1.0 meaning that items might expire anytime from now til the
stated expiration time. The default is 0.0.

The probability of expiration increases as a function of how far along we are in the
potential expiration window, with the probability being near 0 at the beginning of the
window and approaching 1 at the end.

For example, all of the following will expire sometime between 15 and 20 minutes, with
about a 20% chance at 16 minutes, a 40% chance at 17 minutes, and a 100% chance at 20
minutes.

    my $cache = CHI->new ( ..., expires_variance => 0.25, ... );
    $cache->set($key, $value, '20 min');
    $cache->set($key, $value, { expires_at => time() + 20*60 });

    my $cache = CHI->new ( ... );
    $cache->set($key, $value, { expires_in => '20 min', expires_variance => 0.25 });

By "expire", we simply mean that get() returns undef, as if the specified expiration time
had been reached. The "dice are rolled" on every get(), so you can get situations like
this with two consecutive gets:

    my $value = $cache->get($key);        # returns undef (indicating expired)
    my $value = $cache->get($key);        # returns valid value this time!

=back

=item remove( $key )

Delete the data associated with the I<$key> from the cache.

=item expire( $key )

If I<$key> exists, expire it by setting its expiration time into the past.

=item expire_if ( $key, $code )

If I<$key> exists, call code reference I<$code> with the L<CHI::CacheObject> as a single
parameter. If I<$code> returns a true value, expire the data. e.g.

    $cache->expire_if('foo', sub { $_[0]->created_at < (stat($file))[9] });

=item clear( )

Remove all entries from the namespace associated with this cache instance.

=item get_keys( )

Returns a list of keys in the cache. This may include expired keys that have not yet been purged.

=item is_empty( )

Returns a boolean indicating whether the cache is empty, based on get_keys().

=item purge( )

Remove all entries that have expired from the namespace associated
with this cache instance.

=item get_expires_at( $key )

Returns the epoch time at which I<$key> expires, or undef if it has no expiration time.

=item is_valid( $key )

Returns a boolean indicating whether I<$key> is in the cache and has not expired.

=item get_object( $key )

Returns a L<CHI::CacheObject> object containing data about the entry associated with
I<$key>, or undef if no such key exists. The object will be returned even if the entry
has expired, as long as it has not been removed.

=item compute( $key, $code, $set_options )

Combines the C<get> and C<set> operations in a single call. Attempts to get I<$key>;
if successful, returns the value. Otherwise, calls I<$code> and uses the
return value as the new value for I<$key>, which is then returned. I<$set_options>
is a scalar or hash reference, used as the third argument to set.

This method will eventually support the ability to recompute a value in the background
just before it actually expires, so that users are not impacted by recompute time.

=back

=head2 MULTIPLE KEY/VALUE OPERATIONS

The methods in this section process multiple keys and/or values at once. By default these
are implemented with the obvious map operations, but some cache drivers
(e.g. Cache::Memcached) can override them with more efficient implementations.

=over

=item get_multi_arrayref( $keys )

Get the keys in list reference I<$keys>, and return a list reference of the same length
with corresponding values or undefs.

=item get_multi_hashref( $keys )

Like L</get_multi_arrayref>, but returns a hash reference with each key in I<$keys> mapping to
its corresponding value or undef.

=item set_multi( $key_values, $set_options )

Set the multiple keys and values provided in hash reference I<$key_values>. I<$set_options>
is a scalar or hash reference, used as the third argument to set.

=item remove_multi( $keys )

Removes the keys in list reference I<$keys>.

=item dump_as_hash( )

Returns a hash reference containing all the non-expired keys and values in the cache.

=back

=head1 DURATION EXPRESSIONS

Various options like I<expire_in> take a duration expression. This will be parsed by
L<Time::Duration::Parse>. It is either a plain number, which is treated like a number of
seconds, or a number and a string representing time units where the string is one of:

    s second seconds sec secs
    m minute minutes min mins
    h hr hour hours
    d day days
    w week weeks
    M month months
    y year years

e.g. the following are all valid duration expressions:

    25
    3s
    5 seconds
    1 minute and ten seconds
    1 hour

=head1 IMPLEMENTING NEW DRIVERS

To implement a new driver, create a new subclass of CHI::Driver and implement an
appropriate subset of the methods listed below. We recommend that you call your subclass
CHI::Driver::<something> so that users can create it simply by passing I<something> to the
C<driver> option of CHI->new.

The easiest way to start is to look at or copy existing drivers, such as the
L<CHI::Driver::Memory> and L<CHI::Driver::File> included with this distribution.

All cache handles have an assigned namespace that you can access with
C<$self-E<gt>namespace>. You should use the namespace to partition your data store.

=head2 Required methods

The following methods have no default implementation, and MUST be defined by your subclass:

=over

=item store ( $self, $key, $data, $expires_at, $options )

Associate I<$data> with I<$key> in the namespace, overwriting any existing entry.  Called
by L</set>. <$data> will contain any necessary metadata, including expiration options, so
you can just store it as a single block.

The I<$expires_at> epoch value is provided in case you are working with an existing
cache implementation (like memcached) that also has an interest in storing the
expiration time for its own purposes. Normally, you can ignore this.

=item fetch ( $self, $key )

Returns the data associated with I<$key> in the namespace. Called by L</set>. The main
CHI::Driver superclass will take care of extracting out metadata like expiration options
and determining if the value has expired.

=item delete ( $self, $key )

Delete the data associated with the I<$key> in the namespace.

=back

=head2 Overridable methods

The following methods have a default implementation, but MAY be overriden by your subclass:

=over

=item new ( %options )

Override the constructor if you want to process any options specific to your driver.

=item clear ( $self )

Override this if you want to provide an efficient method of clearing a namespace.
The default implementation will iterate over all keys and call L</remove> for each.

=item _serialize ( $value )
=item _deserialize ( $value )

Override these if you want to change the serialization method used for references. The
default is Storable freeze/thaw.

=item fetch_multi_arrayref ( $keys )

Override this if you want to efficiently process multiple fetches. Return an array
reference of data or undef corresponding to I<$keys>. The default will iterate over
I<$keys> and call fetch for each.

=item store_multi ( $key_data, $options )

Override this if you want to efficiently process multiple stores. I<$key_data> is a hash
of keys and data that should be stored. The default will iterate over I<$key_data> and
call store for each pair.

=back

=head2 Optional methods

The following methods have no default implementation, and MAY be defined by your subclass,
but are not required for basic cache operations.

=over

=item get_keys ( $self )

Return all keys in the namespace. It is acceptable to return expired keys as well.

=item get_namespaces ( $self )

Return all namespaces associated with the cache.

=back

=head1 SEE ALSO

Cache::Cache, Cache::Memcached, Cache::FastMmap

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
