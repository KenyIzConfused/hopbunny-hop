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

import io
import locale
import os
import re

try:
    import ConfigParser
except Exception:
    import configparser as ConfigParser


class PoliigonSettings():
    """Settings used for the addon."""

    addon_name: str  # e.g. poliigon-addon-3dsmax
    base: str  # Path to base directory of addon or package
    software_source: str  # e.g. blender
    settings_filename: str

    config: ConfigParser.ConfigParser = None

    def __init__(self,
                 addon_name: str,
                 software_source: str,
                 base: str = os.path.join(os.path.expanduser("~"), "Poliigon"),
                 settings_filename: str = "settings.ini"):
        self.addon_name = addon_name
        self.base = os.path.join(base, software_source)
        self.settings_filename = settings_filename
        self.get_settings()

    def _ensure_sections_exist(self):
        sections = [
            "download",
            "library",
            "update",
            "logging",
            "purchase",
            "import",
            "onboarding",
            "ui",
            "user",
            "upgrade"
        ]

        for sec in sections:
            if not self.config.has_section(sec):
                self.config.add_section(sec)

    def _populate_default_settings(self):
        self._ensure_sections_exist()

        defaults = {
            "download": {
                "brush": "2K",
                "download_lods": "true",
                "hdri_bg": "8K",
                "hdri_light": "1K",
                "lod": "NONE",
                "model_res": "NONE",
                "tex_res": "2K"
            },
            "map_preferences": {},
            "library": {
                "primary": ""
            },
            "directories": {},
            "logging": {
                "reporting_opt_in": "true",
                "verbose_logs": "true"
            },
            "purchase": {
                "auto_download": "true"
            },
            "user": {
                "token": "",
                "first_local_asset": ""
            }
        }

        for section_name, section_defaults in defaults.items():
            if len(section_defaults.items()) == 0:
                self.config.add_section(section_name)
                continue
            for option, value in section_defaults.items():
                self.config.set(section_name, option, value)

    def get_settings(self):
        # https://docs.python.org/3/library/configparser.html#configparser.ConfigParser.optionxform
        self.config = ConfigParser.ConfigParser()
        self.config.optionxform = str

        self._populate_default_settings()

        settings_file = os.path.join(self.base, self.settings_filename)
        valid_ini = self.is_ini_valid(settings_file)

        if valid_ini is True:
            try:
                self.config.read(settings_file, encoding="utf-8")
            except UnicodeDecodeError:
                # Fall back to system, in case last saved format wasn't utf-8.
                # Using preferred_encoding for mocking in automated testing.
                preferred_encoding = locale.getpreferredencoding(False)
                with io.open(settings_file, "r", encoding=preferred_encoding) as decoded:
                    self.config.read_file(decoded)
            except ValueError as e:
                print(f"Could not load settings for {self.addon_name}!")
                print(e)
        else:
            self.save_settings()

    def save_settings(self):
        if self.config is None:
            print(f"No settings found for {self.addon_name}! Initializing...")
            self.get_settings()

        if not os.path.exists(self.base):
            try:
                os.makedirs(self.base)
            except Exception as e:
                print("Failed to create directory: ", e)
                raise

        settings_file = os.path.join(self.base, self.settings_filename)
        with io.open(settings_file, "w+", encoding="utf-8") as f:
            self.config.write(f)

    def is_ini_valid(self, filepath: str) -> bool:
        """Check if INI file is not corrupted"""
        if not os.path.exists(filepath):
            return False

        try:  # Do broad exception to be conservative
            # Follow same pattern as above in get_settings
            preferred_encoding = locale.getpreferredencoding(False)
            try:
                with io.open(filepath, "r", encoding="utf-8") as f:
                    return self._validate_ini_lines(f)
            except UnicodeDecodeError:
                with io.open(filepath, "r", encoding=preferred_encoding) as f:
                    return self._validate_ini_lines(f)
        except Exception as e:
            print("Exception while validating settings file, generating new one: ", e)
            return False

    @staticmethod
    def _validate_ini_lines(file_obj: io.TextIOWrapper) -> bool:
        # Regex for a valid section header [between brackets]
        section_header_pattern = re.compile(r'^\s*\[.+\]\s*$')

        # Regex for comments (lines starting with # or ;)
        comment_pattern = re.compile(r'^\s*[#;]')

        # Regex for a valid option (key = value or key : value)
        option_pattern = re.compile(r'.+[=:].*')
        sections_started = False

        for line_num, line in enumerate(file_obj, 1):
            # Empty line
            stripped = line.strip()
            if not stripped:
                continue

            # Comment
            if comment_pattern.match(line):
                continue

            # Section header
            if section_header_pattern.match(line):
                sections_started = True
                continue

            # Content written before a Section starts
            if not sections_started:
                print(f"Error at line {line_num}: Content found before first [Section] header.")
                return False

            # Checking for a valid Key = Value
            # > If a line is indented, it might be a multiline value continuation.
            # >> so we only validate lines that are not indented.
            is_indented = line[0].isspace()
            if not is_indented:
                # If it's not indented, it must contain a delimiter (= or :)
                if not option_pattern.match(stripped):
                    print(f"Error at line {line_num}: Line is not a section, comment, or valid key=value pair.")
                    return False
        return True
