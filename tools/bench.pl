use strict;
use warnings;

# BEGIN { $ENV{ALGORITHM_QUADTREE_BACKEND} = 'Algorithm::QuadTree::PP'; }
# BEGIN { $ENV{ALGORITHM_QUADTREE_BACKEND} = 'Algorithm::QuadTree::XS::NoBackRefs'; }
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

for (1 .. 100) {
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
		$qt->clear;
		$qt->add('test', 0, 0, 1000, 1000);
	},
	insert_rectangles => sub {
		$qt->clear;
		for (1 .. 100) {
			$qt->add("test$_", $start, $start, $start + $side, $start + $side);
		}
	},
	insert_circles => sub {
		$qt->clear;
		for (1 .. 100) {
			$qt->add("test$_", $center, $center, $radius);
		}
	},
	find_rectangle => sub {
		$qt_pre->getEnclosedObjects($start, $start, $start + $side, $start + $side);
	},
	find_circle => sub {
		$qt_pre->getEnclosedObjects($center, $center, $radius);
	},
};

