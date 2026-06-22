#include "qtbase.h"

#define CHILDREN_PER_NODE 4
#define MAX_SIZE_INITIAL 4
#define MAX_SIZE_GROWTH 2
#define MAX_SIZE_CLEAR 32
#define MAX_ID_DECIMALS 4

int id_to_str (int value, char *out)
{
	/* NOTE: we don't treat 0 as a real id - empty string is returned */
	/* NOTE: actual number is reversed in the string, but that's okay */

	int len = 0;
	while (value > 0) {
		out[len] = value & 0xff;
		len += 1;
		value = value >> 4;
	}

	return len;
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

void push_array(DynArr *arr, int id)
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

	arr->ptr[arr->count] = id;
	arr->count += 1;
}

QuadTreeNode* create_nodes(int count, QuadTreeNode *parent)
{
	QuadTreeNode *node = malloc(count * sizeof *node);

	int i;
	for (i = 0; i < count; ++i) {
		node[i].values = NULL;
		node[i].children = NULL;
		node[i].parent = parent;
		node[i].has_objects = false;
	}

	return node;
}

/* NOTE: does not actually free the node, but frees its children nodes */
void destroy_node(QuadTreeNode *node)
{
	if (node->values != NULL) {
		destroy_array(node->values);
	}
	else {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			destroy_node(&node->children[i]);
		}

		free(node->children);
	}
}

void clear_has_objects (QuadTreeNode *node)
{
	if (node->values == NULL) {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			if (node->children[i].has_objects) return;
		}
	}

	node->has_objects = false;
	if (node->parent != NULL) {
		clear_has_objects(node->parent);
	}
}

QuadTreeRootNode* create_root_nobackref()
{
	QuadTreeRootNode *root = malloc(sizeof *root);
	root->node = create_nodes(1, NULL);
	root->backref = NULL;
	root->objects = newHV();
	root->max_id = 0;

	return root;
}

QuadTreeRootNode* create_root()
{
	QuadTreeRootNode *root = create_root_nobackref();
	root->backref = newHV();
	root->objects_reverse = newHV();

	return root;
}

void store_backref(QuadTreeRootNode *root, QuadTreeNode* node, int id)
{
	AV *list;
	char key[MAX_ID_DECIMALS];
	int len = id_to_str(id, key);

	if (!hv_exists(root->backref, key, len)) {
		list = newAV();
		hv_store(root->backref, key, len, (SV*) list, 0);
	}
	else {
		list = (AV*) *(hv_fetch(root->backref, key, len, 0));
	}

	av_push(list, newSViv((uintptr_t) node));
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
		node->children = create_nodes(CHILDREN_PER_NODE, node);
		double xmid = xmin + (xmax - xmin) / 2;
		double ymid = ymin + (ymax - ymin) / 2;

		node_add_level(&node->children[0], xmin, ymin, xmid, ymid, depth);
		node_add_level(&node->children[1], xmin, ymid, xmid, ymax, depth);
		node_add_level(&node->children[2], xmid, ymin, xmax, ymid, depth);
		node_add_level(&node->children[3], xmid, ymid, xmax, ymax, depth);
	}
}

bool is_within_node_rect(QuadTreeNode *node, double xmin, double ymin, double xmax, double ymax)
{
	return (xmin <= node->xmax && xmax >= node->xmin)
		&& (ymin <= node->ymax && ymax >= node->ymin);
}

bool is_within_node_circ(QuadTreeNode *node, double x, double y, double radius_sq)
{
	double check_x = x < node->xmin
		? node->xmin - x
		: x > node->xmax
			? node->xmax - x
			: 0
	;

	double check_y = y < node->ymin
		? node->ymin - y
		: y > node->ymax
			? node->ymax - y
			: 0
	;

	return check_x * check_x + check_y * check_y <= radius_sq;
}

bool is_within_node(QuadTreeNode *node, Shape *param)
{
	switch (param->type) {
		case shape_rectangle:
			return is_within_node_rect(node, param->dimensions[0], param->dimensions[1], param->dimensions[2], param->dimensions[3]);
		case shape_circle:
			return is_within_node_circ(node, param->dimensions[0], param->dimensions[1], param->dimensions[2]);
	}
}

void find_nodes(QuadTreeRootNode *root, QuadTreeNode *node, HV *ret, Shape *param)
{
	if (!node->has_objects || !is_within_node(node, param)) return;

	int i;
	char key[MAX_ID_DECIMALS];

	if (node->values != NULL) {
		for (i = 0; i < node->values->count; ++i) {
			int id = node->values->ptr[i];
			int len = id_to_str(id, key);

			if (hv_exists(ret, key, len)) continue;

			SV **fetched = hv_fetch(root->objects, key, len, 0);
			SV *value = fetched == NULL ? NULL : *fetched;
			hv_store(ret, key, len, value, 0);
			SvREFCNT_inc(value);
		}
	}
	else {
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			find_nodes(root, &node->children[i], ret, param);
		}
	}
}

bool fill_nodes_nobackref(QuadTreeNode *node, int id, Shape *param)
{
	if (!is_within_node(node, param)) return false;

	node->has_objects = true;
	if (node->values != NULL) {
		push_array(node->values, id);
	}
	else {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			fill_nodes_nobackref(&node->children[i], id, param);
		}
	}

	/* only first level matters - if it is added to the first level, it will
	 * surely be added somewhere further */
	return true;
}

bool fill_nodes(QuadTreeRootNode *root, QuadTreeNode *node, int id, Shape *param)
{
	if (!is_within_node(node, param)) return false;

	node->has_objects = true;
	if (node->values != NULL) {
		push_array(node->values, id);
		store_backref(root, node, id);
	}
	else {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			fill_nodes(root, &node->children[i], id, param);
		}
	}

	/* only first level matters - if it is added to the first level, it will
	 * surely be added somewhere further */
	return true;
}

void clear_node(QuadTreeNode *node)
{
	if (!node->has_objects) return;
	node->has_objects = false;

	if (node->values != NULL) {
		clear_array(node->values);
	}
	else {
		int i;
		for (i = 0; i < CHILDREN_PER_NODE; ++i) {
			clear_node(&node->children[i]);
		}
	}
}

void clear_tree(QuadTreeRootNode *root)
{
	clear_node(root->node);

	char *key;
	I32 retlen;
	SV *value;

	if (root->backref != NULL) {
		/* hv_iterinit(root->backref); */
		/* while ((value = hv_iternextsv(root->backref, &key, &retlen)) != NULL) { */
		/* 	SvREFCNT_dec(value); */
		/* } */

		hv_clear(root->backref);
	}

	hv_clear(root->objects);
	root->max_id = 0;
}

/* XS helpers */

SV* get_hash_key (HV* hash, const char* key)
{
	SV **value = hv_fetch(hash, key, strlen(key), 0);

	assert(value != NULL);
	return *value;
}

QuadTreeRootNode* get_root_from_perl(SV *self)
{
	HV *params = (HV*) SvRV(self);

	return (QuadTreeRootNode*) SvIV(get_hash_key(params, "ROOT"));
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

AV* get_backref (QuadTreeRootNode *root, int id)
{
	char key[MAX_ID_DECIMALS];
	int len = id_to_str(id, key);

	SV **value = hv_fetch(root->backref, key, len, 0);
	if (value == NULL) return NULL;
	return (AV*) *value;
}

SV* get_object (QuadTreeRootNode *root, int id)
{
	char key[MAX_ID_DECIMALS];
	int len = id_to_str(id, key);

	SV **value = hv_fetch(root->objects, key, len, 0);
	if (value == NULL) return NULL;
	return *value;
}

int get_object_id (QuadTreeRootNode *root, SV* object)
{
	return SvIV(HeVAL(hv_fetch_ent(root->objects_reverse, object, 0, 0)));
}

int set_object (QuadTreeRootNode *root, SV *object)
{
	int id = ++root->max_id;

	char key[MAX_ID_DECIMALS];
	int len = id_to_str(id, key);
	hv_store(root->objects, key, len, object, 0);
	SvREFCNT_inc(object);

	return id;
}

void set_reverse_object (QuadTreeRootNode *root, SV *object, int id)
{
	hv_store_ent(root->objects_reverse, object, newSViv(id), 0);
}

void unset_object (QuadTreeRootNode *root, int id)
{
	char key[MAX_ID_DECIMALS];
	int len = id_to_str(id, key);
	hv_delete(root->objects, key, len, 0);

	/* NOTE: max_id does not need to be altered */
}

/* drops all stuff, including backrefs */
void drop_object (QuadTreeRootNode *root, SV *object, int id)
{
	char key[MAX_ID_DECIMALS];
	int len = id_to_str(id, key);
	hv_delete(root->objects, key, len, 0);
	hv_delete(root->backref, key, len, 0);
	hv_delete_ent(root->objects_reverse, object, 0, 0);
}

