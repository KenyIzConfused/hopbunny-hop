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

import bpy
from typing import List, Tuple
from ..modules.poliigon_core.multilingual import _t

MULTIPLE_VALUES_ID = "multiple_values"
MULTIPLE_VALUES_LABEL = _t("(Multiple values)")


def fill_size_dropdown(addon, asset_id: int) -> List[Tuple[str, str, str]]:
    """Returns a list of enum items with locally available sizes."""

    asset_data = addon._asset_index.get_asset(asset_id)
    asset_type_data = asset_data.get_type_data()

    local_sizes = asset_type_data.get_size_list(
        local_only=True,
        addon_convention=addon._asset_index.addon_convention,
        local_convention=asset_data.get_convention(local=True))
    # Populate dropdown items
    items_size = []
    for size in local_sizes:
        items_size.append((size, size, size))
    return items_size


def fill_model_size_dropdown(
        self, context: bpy.types.Context, addon) -> List[Tuple[str, str, str]]:
    """ Like fill_size_dropdown, but with one additional option:
    If a parent or multiple objects are selected and their sizes are different,
    don't show a value, but explain this is only to set a new value """

    normal_size_dropdown = fill_size_dropdown(addon, self.asset_id)

    objects = context.scene.objects
    only_selected = True

    if self.is_parent:
        current_obj = _get_current_object(context, self.asset_id, must_be_parent=True)
        if not current_obj:
            return normal_size_dropdown
        objects = current_obj.children
        only_selected = False

    # Get selection list (part of the asset), and list of unique sizes
    unique_sizes = get_assets_unique_sizes(objects, self.asset_id, only_selected)

    # Only one asset object selected - or all selected objects have the same size
    if len(unique_sizes) <= 1:
        return normal_size_dropdown

    # Multiple objects of the same asset selected - not all with the same size
    normal_size_dropdown.insert(0, (MULTIPLE_VALUES_ID, MULTIPLE_VALUES_LABEL, MULTIPLE_VALUES_LABEL))

    return normal_size_dropdown


def get_assets_unique_sizes(
        objects: List[bpy.types.Object],
        asset_id: int,
        only_selected: bool,
        ) -> List[str]:
    """ Get all models in list of objects whose ID match, and the amount of unique sizes """
    unique_sizes: List[str] = []

    for _obj in objects:
        if only_selected and not _obj.select_get():
            continue
        if not hasattr(_obj, "poliigon_props"):
            continue
        _props = _obj.poliigon_props
        if not _props.asset_id == asset_id:
            continue

        if _props.size not in unique_sizes:
            unique_sizes.append(_props.size)

    return unique_sizes


def _get_current_object(context: bpy.types.Context,
                        asset_id: int,
                        must_be_parent: bool) -> bpy.types.Context:
    """ This method can be called while another object is active
    So we need to find which object is the one being updated """
    obj = context.active_object
    props = obj.poliigon_props
    if must_be_parent and not props.is_parent:
        obj = obj.parent
        if obj is None or not hasattr(obj, "poliigon_props"):
            return None
        props = obj.poliigon_props

    if props.asset_id != asset_id:
        return None

    return obj
