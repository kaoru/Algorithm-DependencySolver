use strict;
use warnings;

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::TempDir;

use File::Type;
use File::Spec::Functions;
use File::Which;

use Algorithm::DependencySolver::Operation;
use Algorithm::DependencySolver::Solver;
use Algorithm::DependencySolver::Traversal;

# This test checks that the traversal logic works as expected.
# ie. the correct nodes are traversed in the correct order based on the
# depends, affects, and prerequesites.

# (We use the dryrun() method, which is a wrapper around run() which puts the
# nodes into an array and returns a reference to that array.)

my @tests = (

    #
    # base case - no operations
    #
    {
        'message' => 'no operations',
        'input'   => [ ],
        'output'  => [ ],
    },

    #
    # extremely simple cases - one operation
    #
    {
        'message' => 'one operation, no depends, no affects',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            }
        ],
        'output'  => [ 'a' ],
    },
    {
        'message' => 'one operation, one depend (x), no affect',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'x' ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            }
        ],
        'output'  => [ 'a' ],
    },
    {
        'message' => 'one operation, no depends, one affect (x)',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ ],
                'affects'       => [ 'x' ],
                'prerequisites' => [ ],
            }
        ],
        'output'  => [ 'a' ],
    },
    {
        'message' => 'one operation, one depend (x), one affect (x)',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'x' ],
                'affects'       => [ 'x' ],
                'prerequisites' => [ ],
            }
        ],
        'output'  => [ 'a' ],
    },
    {
        'message' => 'one operation, one depend (x), one affect (y)',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'x' ],
                'affects'       => [ 'y' ],
                'prerequisites' => [ ],
            }
        ],
        'output'  => [ 'a' ],
    },

    #
    # depends & affects, two operations
    #
    {
        'message' => 'two operations, no depends, no affects',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
            {
                'id'            => 'b',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
        ],
        'output' => {
            'one_of' => [
                [ 'a', 'b' ],
                [ 'b', 'a' ],
            ],
        },
    },
    {
        'message' => 'two operations, a affects x, b depends x',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ ],
                'affects'       => [ 'x' ],
                'prerequisites' => [ ],
            },
            {
                'id'            => 'b',
                'depends'       => [ 'x' ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
        ],
        'output'  => [ 'a', 'b' ],
    },
    {
        'message' => 'two operations, a depends x, b affects x',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'x' ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
            {
                'id'            => 'b',
                'depends'       => [ ],
                'affects'       => [ 'x' ],
                'prerequisites' => [ ],
            },
        ],
        'output'  => [ 'b', 'a' ],
    },
    {
        'message' => 'two operations, a depends x, b affects y',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'x' ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
            {
                'id'            => 'b',
                'depends'       => [ ],
                'affects'       => [ 'y' ],
                'prerequisites' => [ ],
            },
        ],
        'output'  => {
            'one_of' => [
                [ 'a', 'b' ],
                [ 'b', 'a' ],
            ],
        },
    },

    #
    # prerequisites
    #
    {
        'message' => 'two operations, b has a as prerequisite',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
            {
                'id'            => 'b',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ 'a' ],
            },
        ],
        'output'  => [ 'a', 'b' ],
    },
    {
        'message' => 'two operations, a has b as prerequisite',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ 'b' ],
            },
            {
                'id'            => 'b',
                'depends'       => [ ],
                'affects'       => [ ],
                'prerequisites' => [ ],
            },
        ],
        'output'  => [ 'b', 'a' ],
    },

    #
    # complex example from the SYNOPSIS of Solver
    #
    # 1 affects x
    # 2 affects y
    # 3 affects z
    #
    # 1 depends on z, so must come after 3
    # 2 depends on x, so must come after 1
    # 3 depends on y, so must come after 2
    #
    # what?!
    #
    # luckily here we also know that 1 is an explicit prerequisite of 3, so the
    # only possible order is:
    #
    # +---+     +---+     +---+
    # | c | --> | a | --> | b |
    # +---+     +---+     +---+
    #
    # hooray!!
    #
    {
        'message' => 'complex case from the SYNOPSIS of Solver',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'z' ],
                'affects'       => [ 'x' ],
                'prerequisites' => [ 'c' ],
            },
            {
                'id'            => 'b',
                'depends'       => [ 'x' ],
                'affects'       => [ 'y' ],
                'prerequisites' => [     ],
            },
            {
                'id'            => 'c',
                'depends'       => [ 'y' ],
                'affects'       => [ 'z' ],
                'prerequisites' => [     ],
            },
        ],
        'output' => [ 'c', 'a', 'b' ],
    },

    #
    # example of an invalid graph
    #
    {
        'message' => 'invalid graph - cycle',
        'input'   => [
            {
                'id'            => 'a',
                'depends'       => [ 'x' ],
                'affects'       => [ 'y' ],
                'prerequisites' => [ ],
            },
            {
                'id'            => 'b',
                'depends'       => [ 'y' ],
                'affects'       => [ 'x' ],
                'prerequisites' => [     ],
            },
        ],
        'output' => 'EXCEPTION',
    }
);

###########################################################

plan tests => scalar @tests;

TEST:
for my $test (@tests) {

    my @operations;
    for my $opp (@{ $test->{'input'} }) {
        push @operations, Algorithm::DependencySolver::Operation->new(
            %$opp
        );
    }

    my $solver = Algorithm::DependencySolver::Solver->new(
        'nodes' => \@operations
    );

    my $traversal = Algorithm::DependencySolver::Traversal->new(
        'Solver' => $solver,
    );

    my $expected = $test->{'output'};
    if ($expected eq 'EXCEPTION') {
        throws_ok {
            $traversal->dryrun();
        } qr/Not a valid graph!/, $test->{'message'};
        note($solver->to_s);
        next TEST;
    }
    elsif (ref($expected) eq ref({})) {
        $expected = any(@{ $expected->{'one_of'} });
    }

    my $got = [ map { $_->[0]{'id'} } @{ $traversal->dryrun() } ];

    my $msg = $test->{'message'};

    my $ok = cmp_deeply($got, $expected, $msg);
    if (!$ok) {
        diag("Got:\n", $solver->to_s);
    }
    else {
        note($solver->to_s);
    }
}
