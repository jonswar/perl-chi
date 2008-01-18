package CHI::Test::Class;
use strict;
use warnings;
use CHI::Util qw(dump_one_line require_dynamic);
use Getopt::Long;
use Module::Find qw(findallmod);
use Module::Load::Conditional qw(can_load);
use Test::More qw();
use base qw(Test::Class);

sub load_tests {
    my ($class) = @_;

    my $test_class_pattern;
    if ( defined( $test_class_pattern = $ENV{TEST_CLASS} ) ) {
        $test_class_pattern =~ s{/}{::}g;
    }
    my @classes;
    my @candidates = findallmod('CHI::t');

    foreach my $class (@candidates) {
        next
          if defined($test_class_pattern) && $class !~ /$test_class_pattern/o;
        require_dynamic($class);
    }
    if ( $ENV{TEST_STACK_TRACE} ) {

        # Show entire stack trace when testing aborts with fatal error
        $SIG{'__DIE__'}  = sub { Carp::confess(@_) };
        $SIG{'__WARN__'} = sub { Carp::confess(@_) };
    }
    return @classes;
}

sub runtests {
    my ($class) = @_;

    # Handle -m flag in case test script is being run directly.
    #
    GetOptions( 'm|method=s' => sub { $ENV{TEST_METHOD} = ".*" . $_[1] . ".*" },
    );

    # Check for internal_only
    #
    if ( $class->internal_only && !$class->is_internal ) {
        $class->skip_all('internal test only');
    }

    # Check for required modules
    #
    if ( my $required_modules = $class->required_modules ) {
        unless ( can_load( modules => $required_modules ) ) {
            $class->skip_all(
                sprintf( 'one of required modules not installed: %s',
                    dump_one_line($required_modules) )
            );
        }
    }

    # Only run tests directly in $class.
    #
    my $test_obj = $class->new();
    Test::Class::runtests($test_obj);
}

sub skip_all {
    my ($reason) = @_;

    Test::More::plan( skip_all => $reason );
}

sub is_internal {
    return $ENV{CHI_INTERNAL_TESTS};
}

sub internal_only {
    return 0;
}

sub required_modules {
    return {};
}

1;
