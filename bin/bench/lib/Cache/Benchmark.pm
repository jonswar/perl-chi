package Cache::Benchmark;

use warnings;
use strict;

use Time::HiRes();
use Carp();

my $KEY             = 0;
my $PROB            = 1;
my $STANDARD_VALUES = {
    keys                => 1_000,
    min_key_length      => 30,
    access_counter      => 100_000,
    value               => ( 'x' x 500 ),
    test_type           => 'weighted',
    sleep_time          => 0,
    weighted_key_config => {
        1.5 => 15,
        10  => 10,
        35  => 7,
        50  => 5,
        65  => 3,
        85  => 2,
        99  => 1,
    },
};

=head1 NAME

Cache::Benchmark - Tests the quality and speed of a cache module to compare
cachemodules and algorithms.

=head1 VERSION

Version 0.011

=cut

our $VERSION = '0.011';

=head1 SYNOPSIS

 use Cache::Benchmark();
 use Cache::MemoryCache();
 use Cache::SizeAwareMemoryCache();
 
 my $cache_1 = new Cache::MemoryCache({
 	namespace => 'my',
 	default_expires_in => 1,
 });
 my $cache_2 = new Cache::SizeAwareMemoryCache({
 	namespace => 'my',
 	default_expires_in => 1,
 	max_size => 400,
 });
 
 my $test = new Cache::Benchmark();
 $test->init( access_counter => 10_000 );
 
 $test->run($cache_1);
 print $test->get_printable_result();
 
 $test->run($cache_2);
 print $test->get_printable_result();

=head1 EXPORT

-

=head1 CONSTRUCTOR

=head2 new()

=over 4

No parameter. You have to L</init()> the object

B<return:> __PACKAGE__

B<parameter:> -

=back

=cut

sub new {
    my $package = $_[0];

    my $self = bless( {}, ref($package) || $package );
    $self->{'_keylist_length'}      = 0;
    $self->{'_access_counter'}      = 0;
    $self->{'_cache_value'}         = '';
    $self->{'_result'}              = {};
    $self->{'_is_init'}             = 0;
    $self->{'_test_type'}           = '';
    $self->{'_key_length'}          = 0;
    $self->{'_supported_types'}     = [qw(plain random weighted)];
    $self->{'_weighted_key_config'} = {};
    $self->{'_accesslist'}          = [];
    $self->{'_sleep_time'}          = 0;
    return $self;
}

=head1 METHODS

=head2 init( [ L</keys> => INT, L</min_key_length> => INT, L</access_counter> => INT, L</value> => SCALAR, L</test_type> => ENUM, L</weighted_key_config> => HASHREF, L</sleep_time> => FLOAT, L</access_list> => ARRAYREF ] )

=over 4

Initialises and configures the benchmark-test. Without that, no other method
will work. All parameters are optional.

B<return:> BOOLEAN

B<parameter:>

=over 4

=item B<keys>: INT [default: 1_000]

how many cache keys are used

=item B<min_key_length>: INT [default: 30]

the minimal length of any key in the cache. The standard-keys are integers
(from 0 till defined "keys"), if you define some min-length, the keys will be
filled with initial zeros until reaching the given length.

=item B<access_counter>: INT [default: 100_000]

how many times will a cache key be get() or set() to the cache-module

=item B<value>: SCALAR [default: STRING, 500 bytes long]

what the cache-value should be (can be anything except UNDEF, only to stress
the memory usage)

=item B<test_type>: ENUM [default: weighted]

types of test. These can be:

=over 4

=item C<plain>:

not a real test. This will only call all keys one after another. No random, no
peaks.

=item C<random>:

only for access-speed tests. The key is randomly generated. No peaks.

=item C<weighted>:

keys are randomly generated and weighted. Some keys have a high chance of being
used, others have less chances

=back

=item B<sleep_time>: FLOAT [default: 0] 

the waiting time between each access in seconds. For example use 0.001 to wait
a millisecond between each access.

=item B<weighted_key_config>: [default: this example-config]

an own config for the test_type "weighted". It's a simple hashref with the
following structure:

=over 4

 $config = {
  1.5 => 15, 
  10  => 10, 
  35  => 7, 
  50  => 5,
  65  => 3,
  85  => 2,
  99  => 1,
 };

=back

I<Example:>

=over 4

=item 1.5 => 15

means: the first 1.5% of all keys have a 15 times higher chance to hit

=item 10  => 10

means: from 1.5% till 10% the keys will have a 10 times higher chance...

=item 35  => 7

means: from 10% till 35% ... 7 times higher ...  ...etc

=back

the key (percent) can be a FLOAT, value (weight) has to be an INT

=item B<accesslist>: ARRAYREF [default: undef]

sets the list of keys the benchmark-test will use in run(). (an ARRAYREF of
INT) Usable to repeat exactly the same test which was stored via
L</get_generated_keylist()> or to define your own list. If you give an access
list, all other parameters, except L</sleep_time>, are senseless.

Attention: the arrayref is not dereferenced!

=back

=back

=cut

sub init {
    my $self   = shift(@_);
    my %config = @_;

    $self->{'_is_init'} = 0;

    my $keylist_length =
      exists( $config{'keys'} )
      ? int( delete( $config{'keys'} ) )
      : $STANDARD_VALUES->{'keys'};
    my $key_length =
      exists( $config{'min_key_length'} )
      ? int( delete( $config{'min_key_length'} ) )
      : $STANDARD_VALUES->{'min_key_length'};
    my $access_counter =
      exists( $config{'access_counter'} )
      ? int( delete( $config{'access_counter'} ) )
      : $STANDARD_VALUES->{'access_counter'};
    my $cache_value =
      exists( $config{'value'} )
      ? delete( $config{'value'} )
      : $STANDARD_VALUES->{'value'};
    my $test_type =
      exists( $config{'test_type'} )
      ? delete( $config{'test_type'} )
      : $STANDARD_VALUES->{'test_type'};
    my $weighted_key_config =
      exists( $config{'weighted_key_config'} )
      ? delete( $config{'weighted_key_config'} )
      : $STANDARD_VALUES->{'weighted_key_config'};
    my $sleep_time =
      exists( $config{'sleep_time'} )
      ? delete( $config{'sleep_time'} )
      : $STANDARD_VALUES->{'sleep_time'};
    my $accesslist =
      exists( $config{'accesslist'} ) ? delete( $config{'accesslist'} ) : undef;

    foreach ( keys %config ) {
        Carp::carp("init-parameter '$_' is unknown!");
        return 0;
    }
    if ( $keylist_length < 10 ) {
        Carp::carp("keylist length has to be bigger than 9");
        return 0;
    }
    if ( $access_counter < 1 ) {
        Carp::carp("access_counter has to be bigger than 0");
        return 0;
    }
    if ( $access_counter <= $keylist_length ) {
        Carp::carp(
            "for usable results the access_counter ($access_counter) has to be MUCH bigger than the keylist length ($keylist_length)"
        );
    }
    if ( !defined($cache_value) ) {
        Carp::carp("undefined cache-value is not allowed");
        return 0;
    }
    my $type_ok = 0;
    foreach my $type ( @{ $self->{'_supported_types'} } ) {
        $type_ok = 1 if ( $test_type eq $type );
    }
    if ( !$type_ok ) {
        Carp::carp("test-type '$test_type' is not supported");
        return 0;
    }
    if ( ref($weighted_key_config) ne 'HASH' ) {
        Carp::carp(
            "weighted_key_config ($weighted_key_config) must be an hahsref");
    }
    if ( defined($accesslist) && ref($accesslist) ne 'ARRAY' ) {
        Carp::carp("parameter 'accesslist' has to be an arrayref of INT");
        return 0;
    }
    if ( defined($accesslist) && $#$accesslist == -1 ) {
        Carp::carp("the 'accesslist' has no content");
        return 0;
    }
    $self->{'_keylist_length'} = int($keylist_length);
    $self->{'_access_counter'} = int($access_counter);
    $self->{'_cache_value'}    = $cache_value;
    $self->{'_test_type'}      = $test_type;
    $self->{'_key_length'}     = ( $key_length > 0 ) ? int($key_length) : 0;
    $self->{'_weighted_key_config'} = $weighted_key_config;
    if ( defined($accesslist) ) {
        $self->{'_accesslist'} = $accesslist;
    }
    else {
        $self->{'_accesslist'} = $self->_create_accesslist(
            $self->{'_test_type'},  $self->{'_keylist_length'},
            $self->{'_key_length'}, $self->{'_access_counter'},
            $self->{'_weighted_key_config'}
        );
    }
    $self->{'_sleep_time'} = $sleep_time;

    $self->{'_is_init'} = 1;
    return 1;
}

=head2 run( L</cacheObject>, [ L</auto_purge> ] )

=over 4

Runs the benchmark-test with the given cache-object.

B<return:> BOOLEAN

B<parameter:>

=over 4

=item B<cacheObject>: OBJECT

every cache-object with an interface like the L</Cache> Module. Only the
following part of the interface is needed:

=over 4

=item set(key, value)

sets a cache

=item get(key)

reads a cache

=item purge()

cleans up all overhanging caches (on sized cache modules)

=back
				
=item B<auto_purge>: BOOLEAN [default: 0]

should purge() called after any B<set()> or B<get()>? Useful for some
SizeAware... Cache modules.

=back

=back				

=cut

sub run {
    my $self       = $_[0];
    my $cache      = $_[1];
    my $auto_purge = $_[2];

    if ( !$self->{'_is_init'} ) {
        Carp::carp('try to use uninitialised cache-test');
        return 0;
    }
    return 0 if ( !$self->_check_cache_class($cache) );
    $self->{'_result'} = $self->_run_benchmark(
        $cache,                 $self->{'_accesslist'},
        $self->{'_sleep_time'}, \$self->{'_cache_value'},
        ( $auto_purge ? 1 : 0 ), $self->{'_keylist_length'}
    );
    return 1;
}

=head2 get_accesslist( )

=over 4

get the list of all accessed keys, which the benchmark-test will set() / get().
Usable to store this list and repeat the test with exactly the same
environment.

Attention: the arrayref is not dereferenced!

B<return:> ARRAYREF of INT

B<parameter:> -

=back

=cut

sub get_accesslist {
    my $self = $_[0];

    return [] if ( !$self->{'_is_init'} );
    return $self->{'_accesslist'};
}

=head2 get_raw_result( )

=over 4

returns all benchmark-data in a plain hash for further usage. Have a look at
some L</get_printable_result()> to understand the data.

B<return:> HASHREF

B<parameter:> -

=back

=cut

sub get_raw_result {
    my $self = $_[0];
    if ( !$self->{'_is_init'} ) {
        Carp::carp('try to use uninitialised object');
        return {};
    }
    return $self->{'_result'};
}

=head2 get_printable_result( )

=over 4

returns all benchmark-data as a readable string. Quality (cached access divided
by uncached access) and runtime (for all get() / set() / purge() operations)
are the most important results to compare caches.

B<return:> STRING

B<parameter:> -

=back

=cut

sub get_printable_result {
    my $self = $_[0];

    if ( !$self->{'_is_init'} ) {
        Carp::carp('try to use uninitialised object');
        return '';
    }
    return <<HERE;
CONCLUSION FOR $self->{'_result'}->{'class'}:
--------------------------------------------------------------
Quality: $self->{'_result'}->{'quality'} (bigger is better)
Hint:    $self->{'_result'}->{'quality_extra'}
Runtime: $self->{'_result'}->{'runtime'} s

CONFIG:
-------
Accesses:       $self->{'_result'}->{'access_counter'}
Keylist length: $self->{'_result'}->{'keylist_length'}
Sleep time:	$self->{'_result'}->{'sleep_time'}s

SINGLE VALUES:
--------------
Cache-keys read:    $self->{'_result'}->{'reads'}
Cache-keys rewrite: $self->{'_result'}->{'rewrites'}
Cache-keys write:   $self->{'_result'}->{'writes'}
Cache purged:       $self->{'_result'}->{'purged'}

Get-time:   $self->{'_result'}->{'get_time'}
Set-time:   $self->{'_result'}->{'set_time'}
Purge-time: $self->{'_result'}->{'purge_time'}
Runtime:    $self->{'_result'}->{'runtime'}

HERE
}

# Protected: generates a random number from 0 to the given value
# int
sub _generate_random_number {
    my $self    = $_[0];
    my $max_val = $_[1];

    return sprintf( "%.0f", rand(1) * $max_val );
}

# Protected: fill a given key with 'x' till the min-length is reached
# string
sub _fill_key {
    my $self       = $_[0];
    my $key        = $_[1];
    my $min_length = $_[2];

    my $fill_length = $min_length - length($key);
    return $key if ( $fill_length <= 0 );
    return ( '0' x $fill_length ) . $key;
}

# Protected: generate all cache-keys for the bell-curve
# array( array( int, int ))
sub _create_accesslist {
    my $self            = $_[0];
    my $test_type       = $_[1];
    my $keylist_length  = $_[2];
    my $key_length      = $_[3];
    my $access_counter  = $_[4];
    my $weighted_config = $_[5];

    my $list = [];
    if ( $test_type eq 'plain' ) {
        my $plain_list = [ 0 .. ( $keylist_length - 1 ) ];
        my $i = 0;
        foreach ( 1 .. $access_counter ) {
            $i = 0 if ( $i > $#$plain_list );
            push( @$list,
                $self->_fill_key( $plain_list->[ $i++ ], $key_length ) );
        }
    }
    elsif ( $test_type eq 'random' ) {
        foreach ( 1 .. $access_counter ) {
            push(
                @$list,
                $self->_fill_key(
                    $self->_generate_random_number( $keylist_length - 1 ),
                    $key_length
                )
            );
        }
    }
    elsif ( $test_type eq 'weighted' ) {
        my @sorted_percents = sort( { $a <=> $b } keys(%$weighted_config) );
        my $actual_step     = shift(@sorted_percents);
        my $plain_keylist   = [];
        foreach my $key ( 0 .. ( $keylist_length - 1 ) ) {
            my $weight = 1;
            if ( defined($actual_step) ) {
                my $percent = ( ( $key + 1 ) / $keylist_length ) * 100;
                $actual_step = shift(@sorted_percents)
                  if ( $actual_step < $percent );
                $weight = int( $weighted_config->{$actual_step} )
                  if ( defined($actual_step) );
            }
            foreach ( 1 .. $weight ) {
                push( @$plain_keylist, $self->_fill_key( $key, $key_length ) );
            }
        }
        my $length = $#$plain_keylist;
        foreach ( 1 .. $access_counter ) {
            push( @$list,
                $plain_keylist->[ $self->_generate_random_number($length) ] );
        }
    }
    return $list;
}

# Protected: check the object-interface of the given cache-object
# boolean
sub _check_cache_class {
    my $self  = $_[0];
    my $cache = $_[1];

    foreach my $method (qw/set get/) {
        if ( !UNIVERSAL::can( $cache, $method ) ) {
            Carp::carp( "You need to implement method $method in Class '"
                  . ref($cache)
                  . "'" );
            return 0;
        }
    }
    return 1;
}

# Protected: run the benchmark test
# hashref
sub _run_benchmark {
    my $self           = $_[0];
    my $cache          = $_[1];
    my $access_list    = $_[2];
    my $sleep_time     = $_[3];
    my $cache_value    = $_[4];
    my $auto_purge     = $_[5];
    my $keylist_length = $_[6];

    my $cached_keys = {};
    my ( $cached, $not_cached, $cache_deleted, $cache_purged ) = ( 0, 0, 0, 0 );
    my ( $set_time, $get_time, $purge_time ) = ( 0, 0, 0 );
    foreach my $key (@$access_list) {
        if ( $sleep_time > 0 ) {
            Time::HiRes::nanosleep($sleep_time);
        }
        if ( $cached_keys->{$key} ) {
            my $start_time = Time::HiRes::time();
            my $val        = $cache->get($key);
            $get_time += Time::HiRes::time() - $start_time;
            if ( defined($val) ) {
                ++$cached;
            }
            else {
                ++$cache_deleted;
                my $start_time = Time::HiRes::time();
                $cache->set( $key, $$cache_value );
                $set_time += Time::HiRes::time() - $start_time;
            }
        }
        else {
            ++$not_cached;
            my $start_time = Time::HiRes::time();
            $cache->set( $key, $$cache_value );
            $set_time += Time::HiRes::time() - $start_time;
        }
        $cached_keys->{$key} = 1;
        my $start_time = Time::HiRes::time();
        if ($auto_purge) {
            ++$cache_purged if ( $cache->purge() );
            $purge_time += Time::HiRes::time() - $start_time;
        }
    }
    my $cache_written = $not_cached + $cache_deleted;
    my $quality =
      $cache_deleted
      ? sprintf( "%0.4f", $cached / $cache_deleted )
      : 9_999_999_999_999;
    return {
        class      => ref($cache),
        runtime    => sprintf( "%0.6f", $set_time + $get_time + $purge_time ),
        set_time   => sprintf( "%0.6f", $set_time ),
        get_time   => sprintf( "%0.6f", $get_time ),
        purge_time => sprintf( "%0.6f", $purge_time ),
        keylist_length => $keylist_length,
        quality        => $quality,
        quality_extra  => ( $cache_deleted ? '-' : 'no cachedata was cleared' ),
        access_counter => scalar(@$access_list),
        reads          => $cached,
        rewrites       => $cache_deleted,
        writes         => $not_cached,
        purged         => $cache_purged,
        sleep_time     => $sleep_time,

    };
}

=head1 AUTHOR

Tobias Tacke, C<< <cpan at tobias-tacke.de> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-cache-benchmark at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Cache-Benchmark>. I will be
notified, and then you'll automatically be notified of any progress on your bug
as I make changes.

=head1 SUPPORT

You can find the documentation of this module with the perldoc command.

    perldoc Cache::Benchmark

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Cache-Benchmark>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Cache-Benchmark>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Cache-Benchmark>

=item * Search CPAN

L<http://search.cpan.org/dist/Cache-Benchmark>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2007 Tobias Tacke, all rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;    # End of Cache::Benchmark
