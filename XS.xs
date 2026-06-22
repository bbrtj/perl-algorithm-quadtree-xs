#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"
#include "qtbase.h"

MODULE = Algorithm::QuadTree::XS		PACKAGE = Algorithm::QuadTree::XS

PROTOTYPES: DISABLE

void
_AQT_init(obj)
		SV *obj
	CODE:
		QuadTreeRootNode *root = create_root();

		HV *params = (HV*) SvRV(obj);

		node_add_level(root->node,
			SvNV(get_hash_key(params, "XMIN")),
			SvNV(get_hash_key(params, "YMIN")),
			SvNV(get_hash_key(params, "XMAX")),
			SvNV(get_hash_key(params, "YMAX")),
			SvIV(get_hash_key(params, "DEPTH"))
		);

		SV *root_sv = newSViv((uintptr_t) root);
		SvREADONLY_on(root_sv);
		hv_stores(params, "ROOT", root_sv);

void
_AQT_deinit(self)
		SV *self
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		clear_tree(root);
		destroy_node(root->node);
		free(root->node);
		SvREFCNT_dec((SV*) root->backref);
		SvREFCNT_dec((SV*) root->objects);
		SvREFCNT_dec((SV*) root->objects_reverse);


		free(root);


void
_AQT_addObject(self, object, x, y, x2_or_radius, ...)
		SV *self
		SV *object
		double x
		double y
		double x2_or_radius
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		Shape param;
		param.dimensions[0] = x;
		param.dimensions[1] = y;
		if (items > 5) {
			param.type = shape_rectangle;
			param.dimensions[2] = x2_or_radius;
			param.dimensions[3] = SvNV(ST(5));
		}
		else {
			param.type = shape_circle;
			param.dimensions[2] = x2_or_radius * x2_or_radius;
		}

		int id = set_object(root, object);
		if (!fill_nodes(root, root->node, id, &param)) {
			unset_object(root, id);
		}
		else {
			set_reverse_object(root, object, id);
		}

SV*
_AQT_findObjects(self, x, y, x2_or_radius, ...)
		SV *self
		double x
		double y
		double x2_or_radius
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		HV *ret_hash = newHV();

		Shape param;
		param.dimensions[0] = x;
		param.dimensions[1] = y;
		if (items > 4) {
			param.type = shape_rectangle;
			param.dimensions[2] = x2_or_radius;
			param.dimensions[3] = SvNV(ST(4));
		}
		else {
			param.type = shape_circle;
			param.dimensions[2] = x2_or_radius * x2_or_radius;
		}

		find_nodes(root, root->node, ret_hash, &param);
		AV *ret = get_hash_values(ret_hash);

		SvREFCNT_dec((SV*) ret_hash);
		RETVAL = newRV_noinc((SV*) ret);
	OUTPUT:
		RETVAL

void
_AQT_delete(self, object)
		SV *self
		SV *object
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		int id = get_object_id(root, object);
		AV *list = get_backref(root, id);
		int i, j;

		if (list != NULL) {
			for (i = 0; i < av_count(list); ++i) {
				SV **fetched = av_fetch(list, i, 0);
				assert(fetched != NULL);

				QuadTreeNode *node = (QuadTreeNode*) SvIV(*fetched);
				DynArr* new_list = create_array();

				for (j = 0; j < node->values->count; ++j) {
					if (node->values->ptr[j] != id) {
						push_array(new_list, id);
					}
				}

				destroy_array(node->values);
				node->values = new_list;
				if (new_list->count == 0) clear_has_objects(node);
			}

			drop_object(root, object, id);
		}

void
_AQT_clear(self)
		SV* self
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);
		clear_tree(root);

MODULE = Algorithm::QuadTree::XS		PACKAGE = Algorithm::QuadTree::XS::NoBackRefs		PREFIX = nbr

PROTOTYPES: DISABLE

void
nbr_AQT_init(obj)
		SV *obj
	CODE:
		QuadTreeRootNode *root = create_root_nobackref();

		HV *params = (HV*) SvRV(obj);

		node_add_level(root->node,
			SvNV(get_hash_key(params, "XMIN")),
			SvNV(get_hash_key(params, "YMIN")),
			SvNV(get_hash_key(params, "XMAX")),
			SvNV(get_hash_key(params, "YMAX")),
			SvIV(get_hash_key(params, "DEPTH"))
		);

		SV *root_sv = newSViv((uintptr_t) root);
		SvREADONLY_on(root_sv);
		hv_stores(params, "ROOT", root_sv);

void
nbr_AQT_deinit(self)
		SV *self
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		clear_tree(root);
		destroy_node(root->node);
		free(root->node);
		SvREFCNT_dec((SV*) root->objects);

		free(root);

void
nbr_AQT_addObject(self, object, x, y, x2_or_radius, ...)
		SV *self
		SV *object
		double x
		double y
		double x2_or_radius
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		Shape param;
		param.dimensions[0] = x;
		param.dimensions[1] = y;
		if (items > 5) {
			param.type = shape_rectangle;
			param.dimensions[2] = x2_or_radius;
			param.dimensions[3] = SvNV(ST(5));
		}
		else {
			param.type = shape_circle;
			param.dimensions[2] = x2_or_radius * x2_or_radius;
		}

		int id = set_object(root, object);
		if (!fill_nodes_nobackref(root->node, id, &param)) {
			unset_object(root, id);
		}

SV*
nbr_AQT_findObjects(self, x, y, x2_or_radius, ...)
		SV *self
		double x
		double y
		double x2_or_radius
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);

		HV *ret_hash = newHV();

		Shape param;
		param.dimensions[0] = x;
		param.dimensions[1] = y;
		if (items > 4) {
			param.type = shape_rectangle;
			param.dimensions[2] = x2_or_radius;
			param.dimensions[3] = SvNV(ST(4));
		}
		else {
			param.type = shape_circle;
			param.dimensions[2] = x2_or_radius * x2_or_radius;
		}

		find_nodes(root, root->node, ret_hash, &param);
		AV *ret = get_hash_values(ret_hash);

		SvREFCNT_dec((SV*) ret_hash);
		RETVAL = newRV_noinc((SV*) ret);
	OUTPUT:
		RETVAL

void
nbr_AQT_clear(self)
		SV* self
	CODE:
		QuadTreeRootNode *root = get_root_from_perl(self);
		clear_tree(root);

