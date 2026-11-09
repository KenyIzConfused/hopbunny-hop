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

from typing import List, Tuple, Dict

import bpy

from .modules.poliigon_core.user import UserDownloadPreferences
from .modules.poliigon_core.maps import MAP_DESCRIPTIONS, MapType
from .modules.poliigon_core.multilingual import _t
from .toolbox import get_context
from .utils import get_prefs
from .toolbox_settings import save_settings


def _get_required_dict() -> Dict:
    """ For optimization purposes, create a dict of Maps -> required bool
    Beats having to iterate for every map
    """
    name_to_required_dict = {}
    user_prefs: UserDownloadPreferences = cTB.user.map_preferences
    for _map_format in user_prefs.texture_maps:
        map_type_eff: MapType = _map_format.map_type.get_effective()
        name_to_required_dict[map_type_eff.value] = _map_format.required
    return name_to_required_dict


def add_map_pref_rows(cTB, col: bpy.types.UILayout, context) -> None:
    """ Draw the list of maps inside the settings """
    if cTB.user is None or cTB.user.map_preferences is None:
        col.label(text=_t("Must be logged in to change"), icon="ERROR")
        return

    name_to_required_dict = _get_required_dict()

    prefs = get_prefs()
    map_prefs_list = prefs.map_prefs

    for map_pref_props in map_prefs_list:
        _map_type: MapType = getattr(MapType, map_pref_props.name)
        if not _map_type:
            continue

        is_required = name_to_required_dict.get(_map_type.value, False)
        row_map_type = col.row()
        row_map_type.use_property_split = True
        row_map_type.use_property_decorate = False

        col_check = row_map_type.column()
        col_check.enabled = not is_required
        col_label = row_map_type.column()
        col_formats = row_map_type.column()
        col_formats.enabled = map_pref_props.enabled

        optional_label = ""
        if not is_required:
            optional_label = " (optional)"
        label = f" {MAP_DESCRIPTIONS[_map_type].display_name}{optional_label}"

        # Actual drawing
        col_check.prop(map_pref_props, "enabled")
        fake_label = col_label.operator("poliigon.poliigon_label_with_description", text=label, emboss=False)
        fake_label.dynamic_description = MAP_DESCRIPTIONS[_map_type].description
        col_formats.prop(map_pref_props, "file_format")


def _get_file_format_options(map_type: MapType) -> List[Tuple[str, str, str, str, int]]:
    user_prefs = cTB.user.map_preferences
    if user_prefs is None:
        return []

    map_format = user_prefs.get_map_preferences(map_type)
    if map_format is None:
        return [("NONE", "None", "File format: None", "NONE", 0)]

    options = []
    for _idx_ext, (_ext, _avail) in enumerate(map_format.extensions.items()):
        if not _avail:
            continue
        if _ext in ["png", "jpg"]:
            bits = 8
        else:
            bits = 16
        ext_upper = _ext.upper()
        label = f"{ext_upper} ({bits}bit)"
        options.append(
            (_ext, label, f"File format: {ext_upper}", "NONE", _idx_ext))
    return options


class MapPrefProperties(bpy.types.PropertyGroup):
    """ Individual properties of a specific map (AO, normal, etc)
    Must be instanciated inside a CollectionProperty as an array
    """

    @staticmethod
    def _map_pref_update(
        context,
        map_type: MapType,
        enabled: bool,
        file_format: str
    ) -> None:
        user_prefs = cTB.user.map_preferences
        if user_prefs is None:
            return

        map_format = user_prefs.get_map_preferences(map_type)
        if map_format is None:
            cTB.logger.error(f"No map prefs found for {map_type.name}")
            return

        map_format.enabled = enabled
        if enabled:
            map_format.selected = file_format
        else:
            map_format.selected = "NONE"
        save_settings(cTB)

    def _update_map_pref(self, context):
        """ Check/uncheck enabled & changing file format """
        map_type: MapType = getattr(MapType, self.name.upper())
        self._map_pref_update(context, map_type, self.enabled, self.file_format)

    def _get_file_format_options(self, context):
        """ Get dropdown items for file formats """
        map_type: MapType = getattr(MapType, self.name.upper())
        return _get_file_format_options(map_type)

    name: bpy.props.StringProperty(default="")  # noqa: F722 # type: ignore
    description: bpy.props.StringProperty(default="")  # noqa: F722 # type: ignore
    enabled: bpy.props.BoolProperty(
        name="",  # noqa: F722
        default=True,
        update=_update_map_pref
    )  # type: ignore
    file_format: bpy.props.EnumProperty(
        name="",  # noqa: F722
        items=_get_file_format_options,
        options={'HIDDEN'},  # noqa: F821
        update=_update_map_pref
    )  # type: ignore


class POLIIGON_OT_LabelWithDescription(bpy.types.Operator):
    """ This is meant to be a non-clickable operator only to show a label with dynamic description """
    bl_idname = "poliigon.poliigon_label_with_description"
    bl_label = "Map description"
    bl_options = {"INTERNAL", "UNDO"}

    dynamic_description: bpy.props.StringProperty()  # type: ignore

    @classmethod
    def description(cls, context, properties):
        if not context or not hasattr(properties, "dynamic_description"):
            return _t("Map description loading...")
        return properties.dynamic_description

    def execute(self, context):
        return {'FINISHED'}


cTB = None


def register(addon_version: str) -> None:
    global cTB

    cTB = get_context(addon_version)

    bpy.utils.register_class(POLIIGON_OT_LabelWithDescription)
    bpy.utils.register_class(MapPrefProperties)


def unregister() -> None:
    bpy.utils.unregister_class(MapPrefProperties)
    bpy.utils.unregister_class(POLIIGON_OT_LabelWithDescription)
