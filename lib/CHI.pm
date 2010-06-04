package CHI;
use 5.006;
use Carp;
use CHI::Stats;
use strict;
use warnings;

our $VERSION = '0.35';

my ( %final_class_seen, %stats );

sub logger {
    warn
      "CHI now uses Log::Any for logging - see Log::Any documentation for details";
}

sub stats {
    my ($class) = @_;

    # Each CHI root class gets its own stats object
    #
    $stats{$class} ||= CHI::Stats->new( chi_root_class => $class );
    return $stats{$class};
}

sub new {
    my ( $chi_root_class, %params ) = @_;

    # Get driver class from driver or driver_class parameters
    #
    my $driver_class;
    if ( my $driver = delete( $params{driver} ) ) {
        $driver_class = "CHI::Driver::$driver";
    }
    else {
        $driver_class = delete( $params{driver_class} );
    }
    croak "missing required param 'driver' or 'driver_class'"
      unless defined $driver_class;

    # Load driver class if it hasn't been loaded or defined in-line already
    #
    unless ( $driver_class->can('fetch') ) {
        Class::MOP::load_class($driver_class);
    }

    # Select roles depending on presence of certain arguments. Everyone gets
    # the Universal role.
    #
    my @roles = ('CHI::Driver::Role::Universal');
    if ( exists( $params{roles} ) ) {
        push( @roles, @{ delete( $params{roles} ) } );
    }
    if ( exists( $params{max_size} ) || exists( $params{is_size_aware} ) ) {
        push( @roles, 'CHI::Driver::Role::IsSizeAware' );
    }
    if ( exists( $params{l1_cache} ) || exists( $params{mirror_cache} ) ) {
        push( @roles, 'CHI::Driver::Role::HasSubcaches' );
    }
    if ( $params{is_subcache} ) {
        push( @roles, 'CHI::Driver::Role::IsSubcache' );
    }

    # Select a final class based on the driver class and roles, creating it
    # if necessary - adapted from MooseX::Traits
    #
    my $meta = Moose::Meta::Class->create_anon_class(
        superclasses => [$driver_class],
        roles        => \@roles,
        cache        => 1
    );
    my $final_class = $meta->name;
    $meta->add_method( 'meta' => sub { $meta } )
      if !$final_class_seen{$final_class}++;

    return $final_class->new(
        chi_root_class => $chi_root_class,
        driver_class   => $driver_class,
        %params
    );
}

1;

__END__

=pod

=head1 NAME

CHI -- Unified cache handling interface

=head1 SYNOPSIS

    use CHI;

    # Choose a standard driver
    #
    my $cache = CHI->new( driver => 'Memory', global => 1 );
    my $cache = CHI->new( driver => 'File',
        root_dir => '/path/to/root'
    );
    my $cache = CHI->new( driver => 'FastMmap',
        root_dir   => '/path/to/root',
        cache_size => '1k'
    );
    my $cache = CHI->new( driver  => 'Memcached',
        servers => [ "10.0.0.15:11211", "10.0.0.15:11212" ],
        l1_cache => { driver => 'FastMmap', root_dir => '/path/to/root' }
    );
    my $cache = CHI->new( driver => 'DBI',
        dbh => $dbh
    );
    my $cache = CHI->new( driver => 'BerkeleyDB',
        root_dir => '/path/to/root'
    );

    # Create your own driver
    # 
    my $cache = CHI->new( driver_class => 'My::Special::Driver' );

    # Basic cache operations
    #
    my $customer = $cache->get($name);
    if ( !defined $customer ) {
        $customer = get_customer_from_db($name);
        $cache->set( $name, $customer, "10 minutes" );
    }
    $cache->remove($name);

=head1 DESCRIPTION

CHI provides a unified caching API, designed to assist a developer in
persisting data for a specified period of time.

The CHI interface is implemented by driver classes that support fetching,
storing and clearing of data. Driver classes exist or will exist for the gamut
of storage backends available to Perl, such as memory, plain files, memory
mapped files, memcached, and DBI.

CHI is intended as an evolution of DeWitt Clinton's
L<Cache::Cache|Cache::Cache> package, adhering to the basic Cache API but
adding new features and addressing limitations in the Cache::Cache
implementation.

=head1 FEATURES

=over

=item *

Easy to create new drivers

=item *

Uniform support for namespaces

=item *

Automatic serialization of keys and values

=item *

Multilevel caches

=item *

Probabilistic expiration and busy locks, to reduce cache miss stampedes

=item *

Optional logging and statistics collection of cache activity

=back

=for readme stop

=head1 CONSTRUCTOR

To create a new cache handle, call CHI-E<gt>new. It takes the following common
options. All are optional, except that either I<driver> or I<driver_class> must
be passed.

=over

=item driver [STRING]

The name of a standard driver to drive the cache, for example "Memory" or
"File".  CHI will prefix the string with "CHI::Driver::".

=item driver_class [STRING]

The exact CHI::Driver subclass to drive the cache, for example
"My::Memory::Driver".

=item expires_in [DURATION]

=item expires_at [INT]

=item expires_variance [FLOAT]

Provide default values for the corresponding L</set> options.

=item key_digester [STRING|HASHREF|OBJECT]

Digest algorithm to use on keys longer than L</max_key_length> - e.g. "MD5",
"SHA-1", or "SHA-256".

Can be a L<Digest|Digest> object, or a string or hashref which will passed to
Digest->new(). You will need to ensure Digest is installed to use these
options.

Default is "MD5".

=item label [STRING]

A label for the cache as a whole, independent of namespace - e.g.
"web-file-cache". Used when referring to the cache in logs, statistics, and
error messages. By default, set to L</short_driver_name>.

=item l1_cache [HASHREF]

Add an L1 cache as a subcache. See L</SUBCACHES>.

=item max_key_length [INT]

Keys over this size will be L<digested|key_digester>. The default is
driver-specific; L<CHI::Driver::File|File>, for example, defaults this to 240
due to file system limits. For most drivers there is no maximum.

=item mirror_cache [HASHREF]

Add an mirror cache as a subcache. See L</SUBCACHES>.

=item namespace [STRING]

Identifies a namespace that all cache entries for this object will be in. This
allows easy separation of multiple, distinct caches without worrying about key
collision.

Suggestions for easy namespace selection:

=over

=item *

In a class, use the class name:

    my $cache = CHI->new(namespace => __PACKAGE__, ...);

=item *

In a script, use the script's absolute path name:

    use Cwd qw(realpath);
    my $cache = CHI->new(namespace => realpath($0), ...);

=item *

In a web template, use the template name. For example, in Mason, $m-E<gt>cache
will set the namespace to the current component path.

=back

Defaults to 'Default' if not specified.

=item serializer [STRING|HASHREF|OBJECT]

An object to use for serializing data before storing it in the cache, and
deserializing data after retrieving it from the cache.

If this is a string, a L<Data::Serializer|Data::Serializer> object will be
created, with the string passed as the 'serializer' option and raw=1. Common
options include 'Storable', 'Data::Dumper', and 'YAML'. If this is a hashref,
L<Data::Serializer|Data::Serializer-E<gt>new> will be called with the hash. You
will need to ensure Data::Serializer is installed to use these options.

Otherwise, this must be a L<Data::Serializer|Data::Serializer> object or
another object that implements I<serialize()> and I<deserialize()>.

e.g.

    # Serialize using raw Data::Dumper
    my $cache = CHI->new(serializer => 'Data::Dumper');

    # Serialize using Data::Dumper, compressed and (per Data::Serializer defaults) hex-encoded
    my $cache = CHI->new(serializer => { serializer => 'Data::Dumper', compress => 1 });

    # Serialize using custom object
    my $cache = CHI->new(serializer => My::Custom::Serializer->new())

The default is to use raw Storable.

=item key_serializer [STRING|HASHREF|OBJECT]

An object to use for serializing keys that are references. See L</serializer>
above for the different ways this can be passed in. The default is to use JSON
in canonical mode (sorted hash keys).

=item on_get_error [STRING|CODEREF]

=item on_set_error [STRING|CODEREF]

How to handle runtime errors occurring during cache gets and cache sets, which
may or may not be considered fatal in your application. Options are:

=over

=item *

log (the default) - log an error, or ignore if no logger is set - see
L</LOGGING>

=item *

ignore - do nothing

=item *

warn - call warn() with an appropriate message

=item *

die - call die() with an appropriate message

=item *

I<coderef> - call this code reference with three arguments: an appropriate
message, the key, and the original raw error message

=back

=back    

Some drivers will take additional constructor options. For example, the File
driver takes C<root_dir> and C<depth> options.

=head1 INSTANCE METHODS

The following methods can be called on any cache handle returned from
CHI-E<gt>new(). They are implemented in the L<CHI::Driver|CHI::Driver> package.

=head2 Getting and setting

=over

=item get( $key, [option =E<gt> value, ...] )

Returns the data associated with I<$key>. If I<$key> does not exist or has
expired, returns undef. Expired items are not automatically removed and may be
examined with L</get_object> or L</get_expires_at>.

I<$key> may be followed by one or more name/value parameters:

=over

=item expire_if [CODEREF]

If I<$key> exists and has not expired, call code reference with the
L<CHI::CacheObject|CHI::CacheObject> as a single parameter. If code returns a
true value, C<get> returns undef as if the item were expired. For example, to
treat the cache as expired if I<$file> has changed since the value was
computed:

    $cache->get('foo', expire_if => sub { $_[0]->created_at < (stat($file))[9] });

=item busy_lock [DURATION]

If the value has expired, set its expiration time to the current time plus the
specified L<duration|/DURATION EXPRESSIONS> before returning undef.  This is
used to prevent multiple processes from recomputing the same expensive value
simultaneously. The problem with this technique is that it doubles the number
of writes performed - see L</expires_variance> for another technique.

=back

=item set( $key, $data, [$expires_in | "now" | "never" | options] )

Associates I<$data> with I<$key> in the cache, overwriting any existing entry.
Returns I<$data>.

The third argument to C<set> is optional, and may be either a scalar or a hash
reference. If it is a scalar, it may be the string "now", the string "never",
or else a duration treated as an I<expires_in> value described below. If it is
a hash reference, it may contain one or more of the following options. Most of
these options can be provided with defaults in the cache constructor.

=over

=item expires_in [DURATION]

Amount of time (in seconds) until this data expires.

=item expires_at [INT]

The epoch time at which the data expires.

=item expires_variance [FLOAT]

Controls the variable expiration feature, which allows items to expire a little
earlier than the stated expiration time to help prevent cache miss stampedes.

Value is between 0.0 and 1.0, with 0.0 meaning that items expire exactly when
specified (feature is disabled), and 1.0 meaning that items might expire
anytime from now til the stated expiration time. The default is 0.0. A setting
of 0.10 to 0.25 would introduce a small amount of variation without interfering
too much with intended expiration times.

The probability of expiration increases as a function of how far along we are
in the potential expiration window, with the probability being near 0 at the
beginning of the window and approaching 1 at the end.

For example, in all of the following cases, an item might be considered expired
any time between 15 and 20 minutes, with about a 20% chance at 16 minutes, a
40% chance at 17 minutes, and a 100% chance at 20 minutes.

    my $cache = CHI->new ( ..., expires_variance => 0.25, ... );
    $cache->set($key, $value, '20 min');
    $cache->set($key, $value, { expires_at => time() + 20*60 });

    my $cache = CHI->new ( ... );
    $cache->set($key, $value, { expires_in => '20 min', expires_variance => 0.25 });

CHI will make a new probabilistic choice every time it needs to know whether an
item has expired (i.e. it does not save the results of its determination), so
you can get situations like this:

    my $value = $cache->get($key);     # returns undef (indicating expired)
    my $value = $cache->get($key);     # returns valid value this time!

    if ($cache->is_valid($key))        # returns undef (indicating expired)
    if ($cache->is_valid($key))        # returns true this time!

Typical applications won't be affected by this, since the object is recomputed
as soon as it is determined to be expired. But it's something to be aware of.

=back

=item compute( $key, $code, $set_options )

Combines the C<get> and C<set> operations in a single call. Attempts to get
I<$key>; if successful, returns the value. Otherwise, calls I<$code> and uses
the return value as the new value for I<$key>, which is then returned.
I<$set_options> is a scalar or hash reference, used as the third argument to
set.

This method will eventually support the ability to recompute a value in the
background just before it actually expires, so that users are not impacted by
recompute time.

=back

=head2 Removing and expiring

=over

=item remove( $key )

Remove the data associated with the I<$key> from the cache.

=item expire( $key )

If I<$key> exists, expire it by setting its expiration time into the past. Does
not necessarily remove the data. Since this involves essentially setting the
value again, C<remove> may be more efficient for some drivers.

=back

=head2 Inspecting keys

=over

=item is_valid( $key )

Returns a boolean indicating whether I<$key> exists in the cache and has not
expired. Note: Expiration may be determined probabilistically if
L</expires_variance> was used.

=item exists_and_is_expired( $key )

Returns a boolean indicating whether I<$key> exists in the cache and has
expired.  Note: Expiration may be determined probabilistically if
L</expires_variance> was used.

=item get_expires_at( $key )

Returns the epoch time at which I<$key> definitively expires. Returns undef if
the key does not exist or it has no expiration time.

=item get_object( $key )

Returns a L<CHI::CacheObject|CHI::CacheObject> object containing data about the
entry associated with I<$key>, or undef if no such key exists. The object will
be returned even if the entry has expired, as long as it has not been removed.

=back

=head2 Namespace operations

=over

=item clear( )

Remove all entries from the namespace.

=item get_keys( )

Returns a list of keys in the namespace. This may or may not include expired
keys, depending on the driver.

The keys may not look the same as they did when passed into L</set>; they may
have been serialized, utf8 encoded, and/or digested (see L</KEY AND VALUE
TRANSFORMATION>). However, they may still be passed back into L</get>, L</set>,
etc. to access the same underlying objects. i.e. the following code is
guaranteed to produce all key/value pairs from the cache:

  map { ($_, $c->get($_)) } $c->get_keys()

=item purge( )

Remove all entries that have expired from the namespace associated with this
cache instance. Warning: May be very inefficient, depending on the number of
keys and the driver.

=item get_namespaces( )

Returns a list of namespaces associated with the cache. This may or may not
include empty namespaces, depending on the driver.

=back

=head2 Multiple key/value operations

The methods in this section process multiple keys and/or values at once. By
default these are implemented with the obvious map operations, but some cache
drivers (e.g. L<Cache::Memcached|Cache::Memcached>) can override them with more
efficient implementations.

=over

=item get_multi_arrayref( $keys )

Get the keys in list reference I<$keys>, and return a list reference of the
same length with corresponding values or undefs.

=item get_multi_hashref( $keys )

Like L</get_multi_arrayref>, but returns a hash reference with each key in
I<$keys> mapping to its corresponding value or undef. Will only work with
scalar keys.

=item set_multi( $key_values, $set_options )

Set the multiple keys and values provided in hash reference I<$key_values>.
I<$set_options> is a scalar or hash reference, used as the third argument to
set. Will only work with scalar keys.

=item remove_multi( $keys )

Removes the keys in list reference I<$keys>.

=item dump_as_hash( )

Returns a hash reference containing all the non-expired keys and values in the
cache.

=back

=head2 Property accessors

=over

=item driver_class( )

Returns the full name of the driver class. e.g.

    CHI->new(driver=>'File')->driver_class
       => CHI::Driver::File
    CHI->new(driver_class=>'CHI::Driver::File')->driver_class
       => CHI::Driver::File
    CHI->new(driver_class=>'My::Driver::File')->driver_class
       => My::Driver::File

You should use this rather than C<ref()>. Due to some subclassing tricks CHI
employs, the actual class of the object is neither guaranteed nor likely to be
the driver class.

=item short_driver_name( )

Returns the name of the driver class, minus the CHI::Driver:: prefix, if any.
e.g.

    CHI->new(driver=>'File')->short_driver_name
       => File
    CHI->new(driver_class=>'CHI::Driver::File')->short_driver_name
       => File
    CHI->new(driver_class=>'My::Driver::File')->short_driver_name
       => My::Driver::File

=item Standard read-write accessors

    expires_in
    expires_at
    expires_variance
    label
    on_get_error
    on_set_error
    
=item Standard read-only accessors

    namespace
    serializer
    
=back

=head2 Deprecated methods

The following methods are deprecated and will be removed in a later version:

    is_empty

=head1 DURATION EXPRESSIONS

Duration expressions, which appear in the L</set> command and various other
parts of the API, are parsed by L<Time::Duration::Parse|Time::Duration::Parse>.
A duration is either a plain number, which is treated like a number of seconds,
or a number and a string representing time units where the string is one of:

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

=head1 KEY AND VALUE TRANSFORMATION

CHI strives to accept arbitrary keys and values for caching regardless of the
limitations of the underlying driver.

=over

=item *

Keys that are references are serialized - see L</key_serializer>.

=item *

Keys with a utf8 flag are utf8 encoded.

=item *

For some drivers (e.g. L<CHI::Driver::File|File>), keys containing special
characters or whitespace are escaped with URL-like escaping.

=item *

Keys exceeding the maximum length for the underlying driver are digested - see
L</max_key_length> and L</key_digester>.

=item *

Values which are references are automatically serialized before storing, and
deserialized after retrieving - see L</serializer>.

=item *

Values with a utf8 flag are are utf8 encoded before storing, and utf8 decoded
after retrieving.

=back

=head1 SUBCACHES

It is possible to a cache to have one or more I<subcaches>. There are currently
two types of subcaches: I<L1> and I<mirror>.

=head2 L1 cache

An L1 (or "level one") cache sits in front of the primary cache, usually to
provide faster access for commonly accessed cache entries. For example, this
places an in-process Memory cache in front of a Memcached cache:

    my $cache = CHI->new(
        driver   => 'Memcached',
        servers  => [ "10.0.0.15:11211", "10.0.0.15:11212" ],
        l1_cache => { driver => 'Memory' }
    );

On a C<get>, the L1 cache is checked first - if a valid value exists, it is
returned. Otherwise, the primary cache is checked - if a valid value exists, it
is returned, and the value is placed in the L1 cache with the same expiration
time. In this way, items fetched most frequently from the primary cache will
tend to be in the L1 cache.

C<set> operations are distributed to both the primary and L1 cache.

You can access the L1 cache with the C<l1_cache> method. For example, this
clears the L1 cache but leaves the primary cache intact:

    $cache->l1_cache->clear();

=head2 Mirror cache

A mirror cache is a write-only cache that, over time, mirrors the content of
the primary cache. C<set> operations are distributed to both the primary and
mirror cache, but C<get> operations go only to the primary cache.

Mirror caches are useful when you want to migrate from one cache to another.
You can populate a mirror cache and switch over to it once it is sufficiently
populated. For example, here we migrate from an old to a new cache directory:

    my $cache = CHI->new(
        driver          => 'File',
        root_dir        => '/old/cache/root',
        mirror_cache => { driver => 'File', root_dir => '/new/cache/root' },
    );

We leave this running for a few hours (or as needed), then replace it with

    my $cache = CHI->new(
        driver   => 'File',
        root_dir => '/new/cache/root'
    );

You can access the mirror cache with the C<mirror_cache> method. For example,
to see how many keys have made it over to the mirror cache:

    my @keys = $cache->mirror_cache->get_keys();

=head2 Creating subcaches

As illustrated above, you create subcaches by passing the C<l1_cache> and/or
C<mirror_cache> option to the CHI constructor. These options, in turn, should
contain a hash of options to create the subcache with.

The cache containing the subcache is called the I<parent cache>.

The following options are automatically inherited by the subcache from the
parent cache, and may not be overriden:

    expires_at
    expires_in
    expires_variance
    serializer

(Reason: for efficiency, we want to create a single L<cache
object|CHI::CacheObject> and store it in both caches. The cache object contains
expiration information and is dependent on the serializer.  At some point we
could conceivably add code that will use a single object or separate objects as
necessary, and thus allow the above to be overriden.)

The following options are automatically inherited by the subcache from the
parent cache, but may be overriden:

    namespace
    on_get_error
    on_set_error

All other options are initialized in the subcache as normal, irrespective of
their values in the parent.

It is not currently possible to pass an existing cache in as a subcache.

=head2 Common subcache behaviors

These behaviors hold regardless of the type of subcache.

The following methods are distributed to both the primary cache and subcache:

    clear
    expire
    purge
    remove

The following methods return information solely from the primary cache.
However, you are free to call them explicitly on the subcache. (Trying to merge
in subcache information automatically would require too much guessing about the
caller's intent.)

    get_keys
    get_namespaces
    get_object
    get_expires_at
    exists_and_is_expired
    is_valid
    dump_as_hash

=head2 Multiple subcaches

It is valid for a cache to have one of each kind of subcache, e.g. an L1 cache
and a mirror cache.

A cache cannot have more than one of each kind of subcache, but a subcache can
have its own subcaches, and so on. e.g.

    my $cache = CHI->new(
        driver   => 'Memcached',
        servers  => [ "10.0.0.15:11211", "10.0.0.15:11212" ],
        l1_cache => {
            driver     => 'File',
            root_dir   => '/path/to/root',
            l1_cache   => { driver => 'Memory' }
        }
    );

=head2 Methods for parent caches

=over

=item has_subcaches( )

Returns a boolean indicating whether this cache has subcaches.

=item l1_cache( )

Returns the L1 cache for this cache, if any. Can only be called if
I<has_subcaches> is true.

=item mirror_cache( )

Returns the mirror cache for this cache, if any. Can only be called if
I<has_subcaches> is true.

=item subcaches( )

Returns the subcaches for this cache, in arbitrary order. Can only be called if
I<has_subcaches> is true.

=back

=head2 Methods for subcaches

=over

=item is_subcache( )

Returns a boolean indicating whether this is a subcache.

=item subcache_type( )

Returns the type of subcache as a string, e.g. 'l1_cache' or 'mirror_cache'.
Can only be called if I<is_subcache> is true.

=item parent_cache( )

Returns the parent cache (weakened to prevent circular reference).  Can only be
called if I<is_subcache> is true.

=back

=head2 Developing new kinds of subcaches

At this time, subcache behavior is hardcoded into CHI::Driver, so there is no
easy way to modify the behavior of existing subcache types or create new ones.
We'd like to make this more flexible eventually.

=head1 SIZE AWARENESS

If L</is_size_aware> or L</max_size> are passed to the constructor, the cache
will be I<size aware> - that is, it will keep track of its own size (in bytes)
as items are added and removed. You can get a cache's size with L</get_size>.

Size aware caches generally keep track of their size in a separate meta-key,
and have to do an extra store whenever the size changes (e.g. on each set and
remove).

=head2 Maximum size and discard policies

If a cache's size rises above its L</max_size>, items are discarded until the
cache size is sufficiently below the max size. (See
L</max_size_reduction_factor> for how to fine-tune this.)

The order in which items are discarded is controlled with L</discard_policy>.
The default discard policy is 'arbitrary', which discards items in an arbitrary
order.  The available policies and default policy can differ with each driver,
e.g. the L<CHI::Driver::Memory|Memory> driver provides and defaults to an 'LRU'
policy.

=head2 Appropriate drivers

Size awareness was chiefly designed for, and works well with, the
L<CHI::Driver::Memory|Memory> driver: one often needs to enforce a maximum size
on a memory cache, and the overhead of tracking size in memory is negligible.
However, the capability may be useful with other drivers.

Some drivers - for example, L<CHI::Driver::FastMmap|FastMmap> and
L<CHI::Driver::Memcached|Memcached> - inherently keep track of their size and
enforce a maximum size, and it makes no sense to turn on CHI's size awareness
for these.

Also, for drivers that cannot atomically read and update a value - for example,
L<CHI::Driver::File|File> - there is a race condition in the updating of size
that can cause the size to grow inaccurate over time.

=for readme continue

=head1 AVAILABILITY OF DRIVERS

The following drivers are currently available as part of this distribution:

=over

=item *

L<CHI::Driver::Memory|CHI::Driver::Memory> - In-process memory based cache

=item *

L<CHI::Driver::File|CHI::Driver::File> - File-based cache using one file per
entry in a multi-level directory structure

=item *

L<CHI::Driver::FastMmap|CHI::Driver::FastMmap> - Shared memory interprocess
cache via mmap'ed files

=item *

L<CHI::Driver::Null|CHI::Driver::Null> - Dummy cache in which nothing is stored

=item *

L<CHI::Driver::CacheCache|CHI::Driver::CacheCache> - CHI wrapper for
Cache::Cache

=back

The following drivers are currently available as separate CPAN distributions:

=over

=item *

L<CHI::Driver::Memcached|CHI::Driver::Memcached> - Distributed memory-based
cache (works with L<Cache::Memcached|Cache::Memcached>,
L<Cache::Memcached::Fast|Cache::Memcached::Fast>, and
L<Cache::Memcached::libmemcached|Cache::Memcached::libmemcached>)

=item *

L<CHI::Driver::DBI|CHI::Driver::DBI> - Cache in any DBI-supported database

=item *

L<CHI::Driver::BerkeleyDB|CHI::Driver::BerkeleyDB> - Cache in BerkeleyDB files

=back

This list is likely incomplete. A complete set of drivers can be found on CPAN
by searching for "CHI::Driver".

=for readme stop

=head1 DEVELOPING NEW DRIVERS

See L<CHI::Driver::Development|CHI::Driver::Development> for information on
developing new drivers.

=head1 LOGGING

C<CHI> uses L<Log::Any|Log::Any> for logging events. For example, a debug log
message is sent for every cache get and set.

See L<Log::Any|Log::Any> documentation for how to control where logs get sent,
if anywhere.

=head1 STATS

CHI can record statistics, such as number of hits, misses and sets, on a
per-namespace basis and log the results to your L<Log::Any|Log::Any> logger.
You can then use utilities included with this distribution to read stats back
from the logs and report a summary. See L<CHI::Stats|CHI::Stats> for details.

=for readme continue

=head1 RELATION TO OTHER MODULES

=head2 Cache::Cache

CHI is intended as an evolution of DeWitt Clinton's
L<Cache::Cache|Cache::Cache> package. It starts with the same basic API (which
has proven durable over time) but addresses some implementation shortcomings
that cannot be fixed in Cache::Cache due to backward compatibility concerns. 
In particular:

=over

=item Performance

Some of Cache::Cache's subclasses (e.g. L<Cache::FileCache|Cache::FileCache>)
have been justifiably criticized as inefficient. CHI has been designed from the
ground up with performance in mind, both in terms of general overhead and in
the built-in driver classes. Method calls are kept to a minimum, data is only
serialized when necessary, and metadata such as expiration time is stored in
packed binary format alongside the data.

As an example, using Rob Mueller's cacheperl benchmarks, CHI's file driver runs
3 to 4 times faster than Cache::FileCache.

=item Ease of subclassing

New Cache::Cache subclasses can be tedious to create, due to a lack of code
refactoring, the use of non-OO package subroutines, and the separation of
"cache" and "backend" classes. With CHI, the goal is to make the creation of
new drivers as easy as possible, roughly the same as writing a TIE interface to
your data store.  Concerns like serialization and expiration options are
handled by the driver base class so that individual drivers don't have to worry
about them.

=item Increased compatibility with cache implementations

Probably because of the reasons above, Cache::Cache subclasses were never
created for some of the most popular caches available on CPAN, e.g.
L<Cache::FastMmap|Cache::FastMmap> and L<Cache::Memcached|Cache::Memcached>.
CHI's goal is to be able to support these and other caches with a minimum
performance overhead and minimum of glue code required.

=back

=head2 Cache

The L<Cache|Cache> distribution is another redesign and implementation of
Cache, created by Chris Leishman in 2003. Like CHI, it improves performance and
reduces the barrier to implementing new cache drivers. It breaks with the
Cache::Cache interface in a few ways that I considered non-negotiable - for
example, get/set do not serialize data, and namespaces are an optional feature
that drivers may decide not to implement.

=head2 Cache::Memcached, Cache::FastMmap, etc.

CPAN sports a variety of full-featured standalone cache modules representing
particular backends. CHI does not reinvent these but simply wraps them with an
appropriate driver. For example, CHI::Driver::Memcached and
CHI::Driver::FastMmap are thin layers around Cache::Memcached and
Cache::FastMmap.

Of course, because these modules already work on their own, there will be some
overlap. Cache::FastMmap, for example, already has code to serialize data and
handle expiration times. Here's how CHI resolves these overlaps.

=over

=item Serialization

CHI handles its own serialization, passing a flat binary string to the
underlying cache backend.

=item Expiration

CHI packs expiration times (as well as other metadata) inside the binary string
passed to the underlying cache backend. The backend is unaware of these values;
from its point of view the item has no expiration time. Among other things,
this means that you can use CHI to examine expired items (e.g. with
$cache-E<gt>get_object) even if this is not supported natively by the backend.

At some point CHI will provide the option of explicitly notifying the backend
of the expiration time as well. This might allow the backend to do better
storage management, etc., but would prevent CHI from examining expired items.

=back

Naturally, using CHI's FastMmap or Memcached driver will never be as time or
storage efficient as simply using Cache::FastMmap or Cache::Memcached.  In
terms of performance, we've attempted to make the overhead as small as
possible, on the order of 5% per get or set (benchmarks coming soon). In terms
of storage size, CHI adds about 16 bytes of metadata overhead to each item. How
much this matters obviously depends on the typical size of items in your cache.

=head1 SUPPORT AND DOCUMENTATION

Questions and feedback are welcome, and should be directed to the perl-cache
mailing list:

    http://groups.google.com/group/perl-cache-discuss

Bugs and feature requests will be tracked at RT:

    http://rt.cpan.org/NoAuth/Bugs.html?Dist=CHI

The latest source code can be browsed and fetched at:

    http://github.com/jonswar/perl-chi/tree/master
    git clone git://github.com/jonswar/perl-chi.git

=head1 TODO

=over

=item *

Perform cache benchmarks comparing both CHI and non-CHI cache implementations

=item *

Release BerkeleyDB drivers as separate CPAN distributions

=item *

Add docs comparing various strategies for reducing miss stampedes and cost of
recomputes

=item *

Add expires_next syntax (e.g. expires_next => 'hour')

=item *

Support automatic serialization and escaping of keys

=item *

Create XS versions of main functions in Driver.pm (e.g. get, set)

=back

=head1 ACKNOWLEDGMENTS

Thanks to Dewitt Clinton for the original Cache::Cache, to Rob Mueller for the
Perl cache benchmarks, and to Perrin Harkins for the discussions that got this
going.

CHI was originally designed and developed for the Digital Media group of the
Hearst Corporation, a diversified media company based in New York City.  Many
thanks to Hearst management for agreeing to this open source release.

=head1 AUTHOR

Jonathan Swartz

=head1 SEE ALSO

L<Cache::Cache|Cache::Cache>, L<Cache::Memcached|Cache::Memcached>,
L<Cache::FastMmap|Cache::FastMmap>

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

CHI is provided "as is" and without any express or implied warranties,
including, without limitation, the implied warranties of merchantibility and
fitness for a particular purpose.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
