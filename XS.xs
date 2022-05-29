#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define CHILDREN_PER_NODE 4
typedef struct QuadTreeNode QuadTreeNode;
typedef struct QuadTreeRootNode QuadTreeRootNode;
typedef struct DynArr DynArr;

struct QuadTreeNode {
	QuadTreeNode *children;
	DynArr *values;
	double xmin, ymin, xmax, ymax;
};

struct QuadTreeRootNode {
	QuadTreeNode *node;
	HV *backref;
};

struct DynArr {
	void **ptr;
	unsigned int count;
	unsigned int max_size;
};

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

void destroy_array_SV(DynArr* arr)
{
	int i;
	for (i = 0; i < arr->count; ++i) {
		SvREFCNT_dec((SV*) arr->ptr[i]);
	}

	destroy_array(arr);
}

void push_array(DynArr *arr, void *ptr)
{
	if (arr->max_size == 0) {
		arr->max_size = 2;
		arr->ptr = malloc(arr->max_size * sizeof *arr->ptr);
	}
	else if (arr->count == arr->max_size) {
		arr->max_size *= 2;
		arr->ptr = realloc(arr->ptr, arr->max_size * sizeof *arr->ptr);
	}

	arr->ptr[arr->count] = ptr;
	arr->count += 1;
}

void push_array_SV(DynArr *arr, SV *ptr)
{
	push_array(arr, ptr);
	SvREFCNT_inc(ptr);
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

void destroy_node(QuadTreeNode *node)
{
	if (node->values != NULL) {
		destroy_array_SV(node->values);
	}
	else {
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

	return root;
}

void store_backref(QuadTreeRootNode *root, QuadTreeNode* node, SV *value)
{
	DynArr *list;
	if (!hv_exists_ent(root->backref, value, 0)) {
		list = create_array();
		hv_store_ent(root->backref, value, newSViv((unsigned long) list), 0);
	}
	else {
		list = (DynArr*) SvIV(HeVAL(hv_fetch_ent(root->backref, value, 0, 0)));
	}

	push_array(list, node);
}

void node_add_level(QuadTreeNode* node, double xmin, double ymin, double xmax, double ymax, int depth)
{
	bool last = --depth == 0;

	node->xmin = xmin;
	node->ymin = ymin;
	node->xmax = xmax;
	node->ymax = ymax;

	if (last) {
		node->values = create_array();
	}
	else {
		node->children = create_nodes(CHILDREN_PER_NODE);
		double xmid = xmin + (xmax - xmin) / 2;
		double ymid = ymin + (ymax - ymin) / 2;

		node_add_level(&node->children[0], xmin, ymin, xmid, ymid, depth);
		node_add_level(&node->children[1], xmin, ymid, xmid, ymax, depth);
		node_add_level(&node->children[2], xmid, ymin, xmax, ymid, depth);
		node_add_level(&node->children[3], xmid, ymid, xmax, ymax, depth);
	}
}

// rectangular operations

bool is_within_node_rect(QuadTreeNode *node, double xmin, double ymin, double xmax, double ymax)
{
	return (xmin <= node->xmax && xmax >= node->xmin)
		&& (ymin <= node->ymax && ymax >= node->ymin);
}

void find_nodes_rect(QuadTreeNode *node, AV *ret, double xmin, double ymin, double xmax, double ymax)
{
	if (!is_within_node_rect(node, xmin, ymin, xmax, ymax)) return;

	int i;

	if (node->values != NULL) {
		for (i = 0; i < node->values->count; ++i) {
			SV *fetched = (SV*) node->values->ptr[i];
			SvREFCNT_inc(fetched);
			av_push(ret, fetched);
		}
	}
	else {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			find_nodes_rect(&node->children[i], ret, xmin, ymin, xmax, ymax);
		}
	}
}

void fill_nodes_rect(QuadTreeRootNode *root, QuadTreeNode *node, SV *value, double xmin, double ymin, double xmax, double ymax)
{
	if (!is_within_node_rect(node, xmin, ymin, xmax, ymax)) return;

	if (node->values != NULL) {
		push_array_SV(node->values, value);
		store_backref(root, node, value);
	}
	else {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			fill_nodes_rect(root, &node->children[i], value, xmin, ymin, xmax, ymax);
		}
	}
}

// circular operations

bool is_within_node_circ(QuadTreeNode *node, double x, double y, double radius)
{
	if (!is_within_node_rect(node, x - radius, y - radius, x + radius, y + radius)) {
		return false;
	}

	double check_x = x < node->xmin
		? node->xmin
		: x > node->xmax
			? node->xmax
			: x
	;

	double check_y = y < node->ymin
		? node->ymin
		: y > node->ymax
			? node->ymax
			: y
	;

	check_x -= x;
	check_y -= y;

	return check_x * check_x + check_y * check_y <= radius * radius;
}

void find_nodes_circ(QuadTreeNode *node, AV *ret, double x, double y, double radius)
{
	if (!is_within_node_circ(node, x, y, radius)) return;

	int i;

	if (node->values != NULL) {
		for (i = 0; i < node->values->count; ++i) {
			SV *fetched = (SV*) node->values->ptr[i];
			SvREFCNT_inc(fetched);
			av_push(ret, fetched);
		}
	}
	else {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			find_nodes_circ(&node->children[i], ret, x, y, radius);
		}
	}
}

void fill_nodes_circ(QuadTreeRootNode *root, QuadTreeNode *node, SV *value, double x, double y, double radius)
{
	if (!is_within_node_circ(node, x, y, radius)) return;

	if (node->values != NULL) {
		push_array_SV(node->values, value);
		store_backref(root, node, value);
	}
	else {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			fill_nodes_circ(root, &node->children[i], value, x, y, radius);
		}
	}
}


// proper XS Code starts here

MODULE = Algorithm::QuadTree::XS		PACKAGE = Algorithm::QuadTree::XS

void
_AQT_init(obj)
		SV *obj
	CODE:
		QuadTreeRootNode *root = create_root();

		HV *params = (HV*) SvRV(obj);

		SV *root_sv = newSViv((unsigned long) root);
		SvREADONLY_on(root_sv);

		hv_store(params, "ROOT", 4, root_sv, 0);

		node_add_level(root->node,
			SvNV(*hv_fetch(params, "XMIN", 4, 0)),
			SvNV(*hv_fetch(params, "YMIN", 4, 0)),
			SvNV(*hv_fetch(params, "XMAX", 4, 0)),
			SvNV(*hv_fetch(params, "YMAX", 4, 0)),
			SvIV(*hv_fetch(params, "DEPTH", 5, 0))
		);

void
_AQT_deinit(self)
		SV *self
	CODE:
		HV *params = (HV*) SvRV(self);
		QuadTreeRootNode *root = (QuadTreeRootNode*) SvIV(*hv_fetch(params, "ROOT", 4, 0));

		call_method("_AQT_clear", 0);
		destroy_node(root->node);
		free(root->node);
		SvREFCNT_dec((SV*) root->backref);

		free(root);


void
_AQT_addObject(self, object, x, y, x2_or_radius, ...)
		SV *self
		SV *object
		double x
		double y
		double x2_or_radius
	CODE:
		HV *params = (HV*) SvRV(self);
		QuadTreeRootNode *root = (QuadTreeRootNode*) SvIV(*hv_fetch(params, "ROOT", 4, 0));

		if (items > 5) {
			fill_nodes_rect(
				root,
				root->node,
				object,
				x,
				y,
				x2_or_radius,
				SvNV(ST(5))
			);
		}
		else {
			fill_nodes_circ(
				root,
				root->node,
				object,
				x,
				y,
				x2_or_radius
			);
		}

SV*
_AQT_findObjects(self, x, y, x2_or_radius, ...)
		SV *self
		double x
		double y
		double x2_or_radius
	CODE:
		AV *ret = newAV();
		HV *params = (HV*) SvRV(self);
		QuadTreeRootNode *root = (QuadTreeRootNode*) SvIV(*hv_fetch(params, "ROOT", 4, 0));

		if (items > 4) {
			find_nodes_rect(
				root->node,
				ret,
				x,
				y,
				x2_or_radius,
				SvNV(ST(4))
			);
		}
		else {
			find_nodes_circ(
				root->node,
				ret,
				x,
				y,
				x2_or_radius
			);
		}
		RETVAL = newRV_noinc((SV*) ret);
	OUTPUT:
		RETVAL

void
_AQT_delete(self, object)
		SV *self
		SV *object
	CODE:
		HV *params = (HV*) SvRV(self);
		QuadTreeRootNode *root = (QuadTreeRootNode*) SvIV(*hv_fetch(params, "ROOT", 4, 0));

		if (hv_exists_ent(root->backref, object, 0)) {
			DynArr* list = (DynArr*) SvIV(HeVAL(hv_fetch_ent(root->backref, object, 0, 0)));

			int i, j;
			for (i = 0; i < list->count; ++i) {
				QuadTreeNode *node = (QuadTreeNode*) list->ptr[i];
				DynArr* new_list = create_array();

				for(j = 0; j < node->values->count; ++j) {
					SV *fetched = (SV*) node->values->ptr[j];
					if (!sv_eq(fetched, object)) {
						push_array_SV(new_list, fetched);
					}
				}

				destroy_array_SV(node->values);
				node->values = new_list;
			}

			destroy_array(list);
			hv_delete_ent(root->backref, object, 0, 0);
		}

void
_AQT_clear(self)
		SV* self
	CODE:
		HV *params = (HV*) SvRV(self);
		QuadTreeRootNode *root = (QuadTreeRootNode*) SvIV(*hv_fetch(params, "ROOT", 4, 0));

		char *key;
		I32 retlen;
		SV *value;
		int i;

		hv_iterinit(root->backref);
		while ((value = hv_iternextsv(root->backref, &key, &retlen)) != NULL) {
			DynArr *list = (DynArr*) SvIV(value);
			for (i = 0; i < list->count; ++i) {
				QuadTreeNode *node = (QuadTreeNode*) list->ptr[i];
				destroy_array_SV(node->values);
				node->values = create_array();
			}

			destroy_array(list);
		}

		hv_clear(root->backref);

