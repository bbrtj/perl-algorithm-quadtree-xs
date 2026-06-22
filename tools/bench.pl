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
my $side = 40;
my $radius = ($side ** 2 / pi) ** 0.5;

# NOTE: don't start at 500, since then rectangles will border with more areas
my $start = 501;
my $center = 501 + $side / 2;

timethese 200.01, {
	clear => sub {
		$qt->add('test', 0, 0, 1000, 1000);
		$qt->clear;
	},
	insert_100 => sub {
		$qt->clear;

		for my $x (0 .. 4) {
			for my $y (0 .. 9) {
				$qt->add("test$x$y", $x * 100, $y * 100, $x * 100 + $side, $y * 100 + $side);
			}
		}

		for my $x (5 .. 9) {
			for my $y (0 .. 9) {
				$qt->add("test$x$y", $x * 100, $y * 100, $radius);
			}
		}
	},
	find_100 => sub {
		$qt_pre->getEnclosedObjects($start, $start, $start + $side, $start + $side)
			for 0 .. 4;
		$qt_pre->getEnclosedObjects($center, $center, $radius)
			for 5 .. 9;
	},
};

