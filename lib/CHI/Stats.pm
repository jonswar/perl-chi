package CHI::Stats;
use CHI::Util qw(json_encode json_decode);
use Log::Any qw($log);
use Moose;
use strict;
use warnings;

has 'chi_root_class' => ( is => 'ro' );
has 'data'           => ( is => 'ro', default => sub { {} } );
has 'enabled'        => ( is => 'ro', default => 0 );
has 'start_time'     => ( is => 'ro', default => sub { time } );

__PACKAGE__->meta->make_immutable();

sub enable  { $_[0]->{enabled} = 1 }
sub disable { $_[0]->{enabled} = 0 }

sub flush {
    my ($self) = @_;

    my $data = $self->data;
    foreach my $label ( sort keys %$data ) {
        my $label_stats = $data->{$label};
        foreach my $namespace ( sort keys(%$label_stats) ) {
            my $namespace_stats = $label_stats->{$namespace};
            if (%$namespace_stats) {
                $self->log_namespace_stats( $label, $namespace,
                    $namespace_stats );
            }
        }
    }
    $self->clear();
}

sub log_namespace_stats {
    my ( $self, $label, $namespace, $namespace_stats ) = @_;

    my %data = (
        label      => $label,
        end_time   => time(),
        namespace  => $namespace,
        root_class => $self->chi_root_class,
        %$namespace_stats
    );
    %data =
      map { /_ms$/ ? ( $_, int( $data{$_} ) ) : ( $_, $data{$_} ) } keys(%data);
    $log->infof( 'CHI stats: %s', json_encode( \%data ) );
}

sub format_time {
    my ($time) = @_;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime($time);
    return sprintf(
        "%04d%02d%02d:%02d:%02d:%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );
}

sub stats_for_driver {
    my ( $self, $cache ) = @_;

    my $stats =
      ( $self->data->{ $cache->label }->{ $cache->namespace } ||= {} );
    $stats->{start_time} ||= time;
    return $stats;
}

sub parse_stats_logs {
    my $self = shift;
    my ( %results_hash, @results );
    foreach my $log (@_) {
        my $logfh;
        if ( ref($log) ) {
            $logfh = $log;
        }
        else {
            open( $logfh, '<', $log ) or die "cannot open $log: $!";
        }
        while ( my $line = <$logfh> ) {
            chomp($line);
            if ( my ($json) = ( $line =~ /CHI stats: (\{.*\})$/ ) ) {
                my %hash       = %{ json_decode($json) };
                my $root_class = delete( $hash{root_class} );
                my $namespace  = delete( $hash{namespace} );
                my $label      = delete( $hash{label} );
                my $results_set =
                  ( $results_hash{$root_class}->{$label}->{$namespace} ||= {} );
                if ( !%$results_set ) {
                    $results_set->{root_class} = $root_class;
                    $results_set->{namespace}  = $namespace;
                    $results_set->{label}      = $label;
                    push( @results, $results_set );
                }
                while ( my ( $key, $value ) = each(%hash) ) {
                    next if $key =~ /_time$/;
                    $results_set->{$key} += $value;
                }
            }
        }
    }
    return \@results;
}

sub clear {
    my ($self) = @_;

    my $data = $self->data;
    foreach my $key ( keys %{$data} ) {
        %{ $data->{$key} } = ();
    }
    $self->{start_time} = time;
}

1;

__END__

=pod

=head1 NAME

CHI::Stats - Record and report per-namespace cache statistics

=head1 SYNOPSIS

    # Turn on statistics collection
    CHI->stats->enable();

    # Perform cache operations

    # Flush statistics to logs
    CHI->stats->flush();

    ...

    # Parse logged statistics
    my $results = CHI->stats->parse_stats_logs($file1, ...);

=head1 DESCRIPTION

CHI can record statistics, such as number of hits, misses and sets, on a
per-namespace basis and log the results to your L<Log::Any|Log::Any> logger.
You can then parse the logs to get a combined summary.

A single CHI::Stats object is maintained for each CHI root class, and tallies
statistics over any number of CHI::Driver objects.

Statistics are reported when you call the L</flush> method. You can choose to
do this once at process end, or on a periodic basis.

=head1 STATISTICS

The following statistics are tracked:

=over

=item *

absent_misses - Number of gets that failed due to item not being in the cache

=item *

compute_time_ms - Total time spent computing missed results in
L<compute|CHI/compute>, in ms (divide by number of computes to get average).
i.e. the amount of time spent in the code reference passed as the third
argument to compute().

=item *

computes - Number of L<compute|CHI/compute> calls

=item *

expired_misses - Number of gets that failed due to item expiring

=item *

get_errors - Number of caught runtime errors during gets

=item *

get_time_ms - Total time spent in get operation, in ms (divide by number of
gets to get average)

=item *

hits - Number of gets that succeeded

=item *

set_key_size - Number of bytes in set keys (divide by number of sets to get
average)

=item *

set_value_size - Number of bytes in set values (divide by number of sets to get
average)

=item *

set_time_ms - Total time spent in set operation, in ms (divide by number of
sets to get average)

=item *

sets - Number of sets

=item *

set_errors - Number of caught runtime errors during sets

=back

=head1 METHODS

=over

=item enable

=item disable

=item enabled

Enable, disable, and query the current enabled status.

When stats are enabled, each new cache object will collect statistics. Enabling
and disabling does not affect existing cache objects. e.g.

    my $cache1 = CHI->new(...);
    CHI->stats->enable();
    # $cache1 will not collect statistics
    my $cache2 = CHI->new(...);
    CHI->stats->disable();
    # $cache2 will continue to collect statistics

=item flush

Log all statistics to L<Log::Any|Log::Any> (at Info level in the CHI::Stats
category), then clear statistics from memory. There is one log message for each
distinct triplet of L<root class|CHI/chi_root_class>, L<cache label|CHI/label>,
and L<namespace|CHI/namespace>. Each log message contains the string "CHI
stats:" followed by a JSON encoded hash of statistics. e.g.

    CHI stats: {"absent_misses":1,"label":"File","end_time":1338410398,"get_time_ms":5,
       "namespace":"Foo","root_class":"CHI","set_key_size":6,"set_time_ms":23,
       "set_value_size":20,"sets":1,"start_time":1338409391}

=item parse_stats_logs (log1, log2, ...)

Parses logs output by C<CHI::Stats> and returns a listref of stats totals by
root class, cache label, and namespace. e.g.

    [
        {
            root_class     => 'CHI',
            label          => 'File',
            namespace      => 'Foo',
            absent_misses  => 100,
            expired_misses => 200,
            ...
        },
        {
            root_class     => 'CHI',
            label          => 'File',
            namespace      => 'Bar',
            ...
        },
    ]

Lines with the same root class, cache label, and namespace are summed together.
 Non-stats lines are ignored. The parser will only pay attention to the string
"CHI stats:" and everything after, ignoring anything preceding on the log line
(e.g. a timestamp).

Each parameter to this method may be a filename or a reference to an open
filehandle.

=back

=cut
