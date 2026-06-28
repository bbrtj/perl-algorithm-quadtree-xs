#include "qtbase.h"
#include <math.h>

#define CHILDREN_PER_NODE 4
#define MAX_SIZE_INITIAL 4
#define MAX_SIZE_GROWTH 2
#define MAX_SIZE_CLEAR 32
#define PI 3.14159

Shape* create_shape()
{
	Shape *s = malloc(sizeof *s);
	return s;
}

void prepare_rectangle(Shape *s, double x, double y, double x2, double y2)
{
	s->type = shape_rectangle;
	s->x = x;
	s->y = y;
	s->x2 = x2;
	s->y2 = y2;
	s->area = (y2 - y) * (x2 - x);
}

void prepare_circle(Shape *s, double x0, double y0, double radius)
{
	s->type = shape_circle;
	s->x = x0;
	s->y = y0;
	s->radius = radius;
	s->radius_sq = radius * radius;
	s->area = s->radius_sq * PI;
}

void destroy_shape(Shape *s)
{
	free(s);
}

DynArr* create_array()
{
	DynArr *arr = malloc(sizeof *arr);
	arr->count = 0;
	arr->max_size = 0;

	return arr;
}

void destroy_array(DynArr* arr)
{
	if (arr->max_size > 0) {
		free(arr->ptr);
	}

	free(arr);
}

void clear_array(DynArr *arr)
{
	arr->count = 0;

	if (arr->max_size >= MAX_SIZE_CLEAR) {
		arr->max_size = 0;
		free(arr->ptr);
	}
}

void push_array(DynArr *arr, LeafObject obj)
{
	if (arr->count == arr->max_size) {
		if (arr->max_size == 0) {
			arr->max_size = MAX_SIZE_INITIAL;
			arr->ptr = malloc(arr->max_size * sizeof *arr->ptr);
		}
		else {
			arr->max_size *= MAX_SIZE_GROWTH;

			void *enlarged = realloc(arr->ptr, arr->max_size * sizeof *arr->ptr);
			assert(enlarged != NULL);

			arr->ptr = enlarged;
		}
	}

	arr->ptr[arr->count] = obj;
	arr->count += 1;
}

void adopt_object (QuadTreeRootNode *root, SV *value, Shape *s)
{
	SvREFCNT_inc(value);
	av_push(root->objects, value);
	hv_store_ent(root->backref, value, newSViv((uintptr_t) s), 0);
}

void disown_object (QuadTreeRootNode *root, SV *value)
{
	int i;
	AV* new_list = newAV();
	for(i = 0; i < av_count(root->objects); ++i) {
		SV **fetched = av_fetch(root->objects, i, 0);
		if (fetched != NULL && !sv_eq(*fetched, value)) {
			av_push(new_list, *fetched);
			SvREFCNT_inc(*fetched);
		}
	}

	SvREFCNT_dec((SV*) root->objects);
	root->objects = new_list;

	/* NOTE: no shape destruction here, since "adopt_object" does not create it */
	hv_delete_ent(root->backref, value, 0, 0);
}

QuadTreeNode* create_nodes(int count)
{
	QuadTreeNode *node = malloc(count * sizeof *node);

	int i;
	for (i = 0; i < count; ++i) {
		node[i].values = NULL;
		node[i].children = NULL;
	}

	return node;
}

/* NOTE: does not actually free the node, but frees its children nodes */
void destroy_node(QuadTreeNode *node)
{
	if (node->values != NULL)
		destroy_array(node->values);

	if (node->children != NULL) {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			destroy_node(&node->children[i]);
		}

		free(node->children);
	}
}

QuadTreeRootNode* create_root()
{
	QuadTreeRootNode *root = malloc(sizeof *root);
	root->node = create_nodes(1);
	root->backref = newHV();
	root->objects = newAV();

	return root;
}

void node_init(QuadTreeNode* node, double xmin, double ymin, double xmax, double ymax, int depth)
{
	prepare_rectangle(&node->dimensions, xmin, ymin, xmax, ymax);
	node->values = create_array();
	node->depth = depth;
}

void node_add_level(QuadTreeNode* node)
{
	int depth = node->depth - 1;
	if (depth < 1) return;

	double xmin = node->dimensions.x;
	double ymin = node->dimensions.y;
	double xmax = node->dimensions.x2;
	double ymax = node->dimensions.y2;

	double xmid = xmin + (xmax - xmin) / 2;
	double ymid = ymin + (ymax - ymin) / 2;

	node->children = create_nodes(CHILDREN_PER_NODE);

	node_init(&node->children[0], xmin, ymin, xmid, ymid, depth);
	node_init(&node->children[1], xmin, ymid, xmid, ymax, depth);
	node_init(&node->children[2], xmid, ymin, xmax, ymid, depth);
	node_init(&node->children[3], xmid, ymid, xmax, ymax, depth);

	DynArr *objects = node->values;
	node->values = NULL;

	int i;
	for (i = 0; i < objects->count; ++i) {
		fill_nodes(node, objects->ptr[i].var, objects->ptr[i].shape);
	}

	destroy_array(objects);
}

bool shapes_overlap (Shape *s1, Shape *s2)
{
	if (s1->type == s2->type) {
		switch (s1->type) {
			case shape_circle: {
				/* circle vs circle */
				double distance_x = s1->x - s2->x;
				double distance_y = s1->y - s2->y;
				double radius = s1->radius + s2->radius;

				return distance_x * distance_x + distance_y * distance_y
					<= radius * radius;
			}
			case shape_rectangle: {
				/* rectangle vs rectangle */
				if (s1->type == shape_rectangle) {
					return (s1->x <= s2->x2 && s1->x2 >= s2->x)
						&& (s1->y <= s2->y2 && s1->y2 >= s2->y);
				}
			}
		}
	}

	/* circle vs rectangle - circle first */
	/* circles first, if available */
	if (s2->type == shape_circle) {
		Shape *stemp;
		stemp = s1;
		s1 = s2;
		s2 = stemp;
	}

	double check_x = s1->x < s2->x
		? s2->x - s1->x
		: s1->x > s2->x2
			? s2->x2 - s1->x
			: 0
	;

	double check_y = s1->y < s2->y
		? s2->y - s1->y
		: s1->y > s2->y2
			? s2->y2 - s1->y
			: 0
	;

	return check_x * check_x + check_y * check_y <= s1->radius_sq;
}

void find_nodes(QuadTreeNode *node, HV *ret, Shape *param, bool check)
{
	if (!shapes_overlap(param, &node->dimensions)) return;

	int i;

	if (node->values != NULL) {
		for (i = 0; i < node->values->count; ++i) {
			LeafObject fetched = node->values->ptr[i];
			if (check && !shapes_overlap(param, fetched.shape))
				continue;

			SvREFCNT_inc(fetched.var);
			hv_store_ent(ret, fetched.var, fetched.var, 0);
		}
	}
	else {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			find_nodes(&node->children[i], ret, param, check);
		}
	}
}

bool fill_nodes (QuadTreeNode *node, SV *value, Shape *param)
{
	if (!shapes_overlap(param, &node->dimensions)) return false;

	int i;

	if (node->values != NULL) {
		LeafObject obj;
		obj.var = value;
		obj.shape = param;
		push_array(node->values, obj);

		if (node->values->count >= CHILDREN_PER_NODE) {
			int smaller_children = 0;
			for (i = 0; i < node->values->count; ++i) {
				smaller_children += node->values->ptr[i].shape->area < node->dimensions.area;

				/* NOTE: only split if enough objects are smaller than this area */
				if (smaller_children >= CHILDREN_PER_NODE) {
					node_add_level(node);
					break;
				}
			}
		}
	}
	else {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			fill_nodes(&node->children[i], value, param);
		}
	}

	return true;
}

void delete_nodes(QuadTreeNode *node, SV *value, Shape *param)
{
	if (!shapes_overlap(param, &node->dimensions)) return;

	int i;

	if (node->values != NULL) {
		DynArr* new_list = create_array();

		for (i = 0; i < node->values->count; ++i) {
			LeafObject fetched = node->values->ptr[i];
			if (!sv_eq(fetched.var, value)) {
				push_array(new_list, fetched);
			}
		}

		destroy_array(node->values);
		node->values = new_list;
	}
	else {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			delete_nodes(&node->children[i], value, param);
		}
	}
}

void clear_tree(QuadTreeRootNode *root)
{
	int i;
	char *key;
	I32 retlen;
	SV *value;

	if (root->node->children != NULL) {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			destroy_node(&root->node->children[i]);
		}

		free(root->node->children);
		root->node->children = NULL;
		root->node->values = create_array();
	}

	hv_iterinit(root->backref);
	while ((value = hv_iternextsv(root->backref, &key, &retlen)) != NULL) {
		destroy_shape((Shape*) SvIV(value));
	}

	hv_clear(root->backref);
	av_clear(root->objects);
}

/* XS helpers */

SV* get_hash_key (HV* hash, const char* key, int len)
{
	SV **value = hv_fetch(hash, key, len, 0);

	if (value == NULL) return NULL;
	return *value;
}

QuadTreeRootNode* get_root_from_perl(SV *self)
{
	SV *value = get_hash_key((HV*) SvRV(self), "ROOT", 4);
	if (value == NULL)
		croak("quad tree root node is undefined");

	return (QuadTreeRootNode*) SvIV(value);
}

AV* get_hash_values (HV* hash)
{
	AV *ret = newAV();
	HE *he;

	hv_iterinit(hash);
	while ((he = hv_iternext(hash)) != NULL) {
		SV *fetched = HeVAL(he);
		SvREFCNT_inc(fetched);
		av_push(ret, fetched);
	}

	return ret;
}

