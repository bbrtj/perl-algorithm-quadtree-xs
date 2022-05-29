#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define CHILDREN_PER_NODE 4
typedef struct QuadTreeNode QuadTreeNode;
typedef struct QuadTreeRootNode QuadTreeRootNode;

struct QuadTreeNode {
	QuadTreeNode *children;
	AV *values;
	double xmin, ymin, xmax, ymax;
};

struct QuadTreeRootNode {
	QuadTreeNode *node;
	HV *backref;
};

QuadTreeNode* create_nodes(int count)
{
	QuadTreeNode *node = malloc(count * sizeof(QuadTreeNode));

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
		av_undef(node->values);
		SvREFCNT_dec((SV*) node->values);
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
	QuadTreeRootNode *root = malloc(sizeof(QuadTreeRootNode));
	root->node = create_nodes(1);
	root->backref = newHV();

	return root;
}

void store_backref(QuadTreeRootNode *root, QuadTreeNode* node, SV *value)
{
	AV *list;
	if (!hv_exists_ent(root->backref, value, 0)) {
		list = newAV();
		SvREFCNT_inc((SV*) list);
		if (hv_store_ent(root->backref, value, (SV*) list, 0) == NULL) {
			SvREFCNT_dec((SV*) list);
		}
	}
	else {
		list = (AV*) HeVAL(hv_fetch_ent(root->backref, value, 0, 0));
	}

	SvREFCNT_inc((SV*) node->values);
	av_push(list, (SV*) node->values);
}

void node_add_level(QuadTreeNode* node, double xmin, double ymin, double xmax, double ymax, int depth)
{
	bool last = --depth == 0;

	node->xmin = xmin;
	node->ymin = ymin;
	node->xmax = xmax;
	node->ymax = ymax;

	if (last) {
		node->values = newAV();
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
		for (i = 0; i < av_count(node->values); ++i) {
			SV **fetched = av_fetch(node->values, i, 0);
			if (fetched != NULL) {
				av_push(ret, *fetched);
				SvREFCNT_inc(*fetched);
			}
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
		av_push(node->values, value);
		SvREFCNT_inc(value);
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
		for (i = 0; i < av_count(node->values); ++i) {
			SV **fetched = av_fetch(node->values, i, 0);
			if (fetched != NULL) {
				av_push(ret, *fetched);
				SvREFCNT_inc(*fetched);
			}
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
		av_push(node->values, value);
		SvREFCNT_inc(value);
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
			AV *list = (AV*) HeVAL(hv_fetch_ent(root->backref, object, 0, 0));

			int i, j;
			for (i = 0; i < av_count(list); ++i) {
				AV *current_list = (AV*) *av_fetch(list, i, 0);
				AV *new_list = newAV();

				for(j = 0; j < av_count(current_list); ++j) {
					SV *fetched = *av_fetch(current_list, j, 0);
					if (!sv_eq(fetched, object)) {
						SvREFCNT_inc(fetched);
						av_push(new_list, fetched);
					}
				}

				if (av_count(current_list) != av_count(new_list)) {
					av_clear(current_list);
					for (j = 0; j < av_count(new_list); ++j) {
						av_push(current_list, av_pop(new_list));
					}
				}

				av_undef(new_list);
				SvREFCNT_dec((SV*) new_list);
			}

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
			AV *list = (AV*) value;
			for (i = 0; i < av_count(list); ++i) {
				av_clear((AV*) *av_fetch(list, i, 0));
			}

			SvREFCNT_dec(value);
		}

		hv_clear(root->backref);

