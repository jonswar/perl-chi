package CHI::Test::Class;
use CHI::Util qw(require_dynamic);
use Getopt::Long;
use Module::Load::Conditional qw(can_load);
use strict;
use warnings;
use base qw(Test::Class);

sub runtests {
    my ($class) = @_;

    # Handle -m flag in case test script is being run directly.
    #
    GetOptions( 'm|method=s' => sub { $ENV{TEST_METHOD} = ".*" . $_[1] . ".*" },
    );

    if ( $ENV{TEST_STACK_TRACE} ) {

        # Show entire stack trace on fatal errors or warnings
        $SIG{'__DIE__'}  = sub { Carp::confess(@_) };
        $SIG{'__WARN__'} = sub { Carp::confess(@_) };
    }

    # Check for internal_only
    #
    if ( $class->internal_only && !$class->is_internal ) {
        $class->SKIP_ALL('internal test only');
    }

    # Check for required modules
    #
    if ( my $required_modules = $class->required_modules ) {
        while ( my ( $key, $value ) = each(%$required_modules) ) {
            unless ( can_load( modules => { $key, $value } ) ) {
                $class->SKIP_ALL("one of required modules not installed: $key");
            }
        }
    }

    # Only run tests directly in $class.
    #
    my $test_obj = $class->new();
    Test::Class::runtests($test_obj);
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
