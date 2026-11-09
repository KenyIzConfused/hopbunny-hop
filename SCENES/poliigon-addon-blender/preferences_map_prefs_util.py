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

from .modules.poliigon_core.maps import MapType
from .utils import get_prefs


def update_map_prefs_properties(cTB) -> None:
    user_prefs = cTB.user.map_preferences
    if user_prefs is None:
        return

    # Make dict to optimize code (we only go through the list once this way)
    _maptype_to_updates_dict = {}
    for _map_format in user_prefs.texture_maps:
        selected_format = _map_format.selected
        # Added the != "NONE" check after seen empirically with file_format_orm
        enabled = selected_format is not None and selected_format != "NONE"
        if selected_format is None:
            selected_format = list(_map_format.extensions.keys())[0]
        map_type_eff = _map_format.map_type.get_effective()
        _maptype_to_updates_dict[map_type_eff.value] = {
            "enabled": enabled,
            "selected_format": selected_format
        }

    prefs = get_prefs()
    maps_prefs_list = prefs.map_prefs
    for map_pref_props in maps_prefs_list:
        _map_type: MapType = getattr(MapType, map_pref_props.name)
        if not _map_type:
            continue

        updates = _maptype_to_updates_dict[_map_type.value]
        if not updates:
            continue

        enabled = updates.get("enabled", True)
        map_pref_props.enabled = enabled
        if enabled:
            map_pref_props.file_format = updates.get("selected_format")
