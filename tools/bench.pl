use strict;
use warnings;

# BEGIN { $ENV{ALGORITHM_QUADTREE_BACKEND} = 'Algorithm::QuadTree::PP'; }
use Algorithm::QuadTree;
use Benchmark::Dumb qw(timethese);
use Math::Trig qw(pi);

my $depth = shift;
$depth ||= 6;

my $qt = Algorithm::QuadTree->new(
	-xmin => 0,
	-xmax => 1000,
	-ymin => 0,
	-ymax => 1000,
	-depth => $depth
);

my $qt_pre = Algorithm::QuadTree->new(
	-xmin => 0,
	-xmax => 1000,
	-ymin => 0,
	-ymax => 1000,
	-depth => $depth
);

for (1 .. 10) {
	$qt_pre->add("test$_", 400, 400, 600, 600);
}

# NOTE: same area
my $side_small = 40;
my $radius_small = ($side_small ** 2 / pi) ** 0.5;
my $side_big = 200;
my $radius_big = ($side_big ** 2 / pi) ** 0.5;

# NOTE: don't start at 500, since then rectangles will border with more areas
my $start = 501;
my $center = 501 + $side_big / 2;

timethese 200.01, {
	insert_100_small => sub {
		$qt->clear;

		for my $x (0 .. 4) {
			for my $y (0 .. 9) {
				$qt->add("test$x$y", $x * 100, $y * 100, $x * 100 + $side_small, $y * 100 + $side_small);
			}
		}

		for my $x (5 .. 9) {
			for my $y (0 .. 9) {
				$qt->add("test$x$y", $x * 100, $y * 100, $radius_small);
			}
		}
	},
	insert_100_big => sub {
		$qt->clear;

		for my $x (0 .. 4) {
			for my $y (0 .. 9) {
				$qt->add("test$x$y", $x * 100, $y * 100, $x * 100 + $side_big, $y * 100 + $side_big);
			}
		}

		for my $x (5 .. 9) {
			for my $y (0 .. 9) {
				$qt->add("test$x$y", $x * 100, $y * 100, $radius_big);
			}
		}
	},
	find_100 => sub {
		$qt_pre->getApprox($start, $start, $start + $side_big, $start + $side_big)
			for 0 .. 4;
		$qt_pre->getApprox($center, $center, $radius_big)
			for 5 .. 9;
	},
	find_100_check => sub {
		$qt_pre->get($start, $start, $start + $side_big, $start + $side_big)
			for 0 .. 4;
		$qt_pre->get($center, $center, $radius_big)
			for 5 .. 9;
	},
};

