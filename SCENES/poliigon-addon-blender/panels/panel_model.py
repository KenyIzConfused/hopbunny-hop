# #### BEGIN GPL LICENSE BLOCK #####
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software Foundation,
#  Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# ##### END GPL LICENSE BLOCK #####

import os
import bpy
from typing import List, Optional, Tuple

from .. import reporting
from ..modules.poliigon_core.assets import TextureMap
from ..modules.poliigon_core.multilingual import _t
from ..operators.utils_operator import MULTIPLE_VALUES_ID, MULTIPLE_VALUES_LABEL, get_assets_unique_sizes
from ..toolbox import get_context
from .panel_material import get_tex_maps_and_asset_name, replace_node_image


def set_model_resolution(self, context: bpy.types.Context, old_size: str, new_size: str):
    """ Setting a new size for one or more models inside the size_enum dropdown """
    if self.updating or new_size == MULTIPLE_VALUES_ID:
        return
    self.updating = True

    # See if we have to update other models along the way
    selected_objects, _ = get_selected_poliigon_models(context, self.asset_id)
    tex_maps, asset_name = get_tex_maps_and_asset_name(self.asset_id, new_size)

    if len(tex_maps) == 0:
        self.report({"WARNING"}, _t("No Textures found."))
        self.updating = False
        reporting.capture_message("apply_mat_tex_not_found", asset_name)
        return

    # If parents are part of selected objects, include their children
    objects_to_change = selected_objects[:]
    for _obj in selected_objects:
        if _obj.poliigon_props.is_parent:
            for _child in _obj.children:
                if not hasattr(_child, "poliigon_props"):
                    continue
                if _child.poliigon_props.asset_id != self.asset_id:
                    continue
                if _child not in selected_objects:
                    objects_to_change.append(_child)

    _change_multiple_models_tex(context, objects_to_change, tex_maps, self.asset_id, old_size, new_size)

    self.size = new_size

    # After the change, check if parent might need an update
    _update_parent_size(self, context)

    self.updating = False


def _change_multiple_models_tex(
        context: bpy.types.Context,
        models: List[bpy.types.Object],
        tex_maps: List[TextureMap],
        asset_id: str,
        old_size: str,
        new_size: str) -> None:
    """ Change the resolution of every Image node in the material of a list of models,
        considering that different models can share the same material """
    already_changed_mats = []
    for _obj in models:
        if not hasattr(_obj, "poliigon_props"):
            continue
        _props = _obj.poliigon_props
        if _props.asset_id == asset_id:
            mat = _obj.active_material
            if mat is None or mat in already_changed_mats:
                continue

            _props.updating = True  # Important, to stop infinite loop of updating
            _change_model_tex(_obj, tex_maps, old_size, new_size)
            already_changed_mats.append(mat)  # So this material won't be changed anymore
            _props.size = new_size
            _props.updating = False

    # As this is done, any model that shares the same materials should have its size attribute updated
    _change_affected_models_size(context, already_changed_mats, new_size)


def _change_affected_models_size(
        context: bpy.types.Context,
        affected_mats: List[bpy.types.Material],
        new_size: str) -> None:
    """ After changing a material resolution,
    change the size attribute of every model that has this material """
    for _obj in context.scene.objects:
        if not hasattr(_obj, "poliigon_props"):
            continue
        if _obj.active_material in affected_mats:
            _props = _obj.poliigon_props
            _props.updating = True
            _props.size = new_size
            _props.updating = False


def _change_model_tex(
        obj: bpy.types.Object,
        tex_maps: List[TextureMap],
        old_size: str,
        new_size: str) -> None:
    """ Given a model, replace every image inside the material to the new size """
    mat = obj.active_material
    new_mat_name = mat.name.replace(old_size, new_size)

    _change_nodes_size(mat.node_tree.nodes, tex_maps, old_size, new_size, True)

    mat.name = new_mat_name


def _change_nodes_size(
        nodes_coll: bpy.types.Collection,
        tex_maps: List[TextureMap],
        old_size: str,
        new_size: str,
        check_nested_nodes: bool) -> None:
    """ Go through every node (and possibly nested node) to change the image size """
    for node in nodes_coll:
        # Image node
        if node.type == "TEX_IMAGE" and node.image:
            img_filename: str = os.path.basename(node.image.filepath)
            filename_to_find = img_filename.replace(old_size, new_size)
            tex = _get_texmap_by_filename(tex_maps, filename_to_find)
            if not tex:
                continue
                # Backup previous image settings
            replace_node_image(node, tex, new_size)

        # Checking nested nodes
        if check_nested_nodes and hasattr(node, "node_tree"):
            _change_nodes_size(node.node_tree.nodes, tex_maps, old_size, new_size, False)


def _get_texmap_by_filename(tex_maps: List[TextureMap], name: str) -> Optional[TextureMap]:
    """ Find the TextureMap inside the list that has the correct filename """
    for tex in tex_maps:
        if tex.filename == name:
            return tex
    return None


def _update_parent_size(self, context: bpy.types.Context):
    """ Update the size of a parent
    For example, if all children switch to a specific size, the parent must reflect it """
    if self.is_parent:
        return

    obj = context.active_object
    parent = obj.parent

    if not parent:
        return
    if not hasattr(parent, "poliigon_props"):
        return
    parent_props = parent.poliigon_props
    if parent_props.asset_id != self.asset_id:
        return

    # Get sizes of children
    unique_sizes = get_assets_unique_sizes(parent.children, self.asset_id, only_selected=False)
    if len(unique_sizes) != 1:
        new_size = MULTIPLE_VALUES_LABEL
        parent_props.updating = True
        parent_props.size = new_size
        parent_props.updating = False
        return

    # Update size of parent in this specific case
    new_size = unique_sizes[0]
    parent_props.updating = True
    parent_props.size = new_size
    parent_props.updating = False


class POLIIGON_PT_models(bpy.types.Panel):
    bl_label = "Poliigon"
    bl_idname = "POLIIGON_PT_models"

    # Located in Object tab
    bl_space_type = 'PROPERTIES'
    bl_region_type = 'WINDOW'
    bl_context = "object"

    @staticmethod
    def init_context(addon_version: str) -> None:
        """Called from register_panels.py to init global addon context."""
        global cTB
        cTB = get_context(addon_version)

    @classmethod
    def poll(cls, context):
        obj = context.object
        if not obj:
            return False
        return obj.poliigon_props.asset_id != -1

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False

        obj: bpy.types.Object = context.object
        props = obj.poliigon_props

        selected_poliigon_objects, all_same_asset = get_selected_poliigon_models(context, props.asset_id)

        if not all_same_asset:
            layout.label(text="Selected Poliigons models must be part of the same asset")
            return

        # Only one object (selection can be 0 as active object is not necesarily selected)
        if len(selected_poliigon_objects) <= 1:
            # Poliigon model
            if not props.is_parent:
                layout.label(text=f"Model settings ({obj.name})")
                layout.prop(props, "size_enum", text="Resolution")
            # Poliigon model PARENT
            else:
                if not is_correct_parent(obj, props):
                    layout.label(text="No child objects found for this Poliigon model")
                    return
                layout.label(text=f"Parent model settings ({obj.name})")
                layout.prop(props, "size_enum", text="Set resolution")

        # Multiple objects selected (aka the fun part)
        else:
            layout.label(text=f"Model settings ({len(selected_poliigon_objects)} selected Poliigon objects)")
            layout.prop(props, "size_enum", text="Set resolutions")


def is_correct_parent(obj: bpy.types.Object, props):
    """ We consider a parent correct if it has at least one child of the same ID """
    id = props.asset_id
    for child in obj.children:
        if child.poliigon_props.asset_id == id:
            return True
    return False


def get_selected_poliigon_models(
        context: bpy.types.Context, active_id: int) -> Tuple[List[bpy.types.Object], bool]:
    """ Get the list of selected objects that are part of Poliigon,
    and whether they are part of same asset """
    selected_objects = []
    all_same_asset = True
    for obj in context.selected_objects:
        if not hasattr(obj, "poliigon_props"):
            continue
        if obj.poliigon_props.asset_id == -1:
            continue
        # If we reach this part, this is a Poliigon model...
        selected_objects.append(obj)
        # ...but not necesarily part of the same asset!
        if obj.poliigon_props.asset_id != active_id:
            all_same_asset = False

    return selected_objects, all_same_asset
