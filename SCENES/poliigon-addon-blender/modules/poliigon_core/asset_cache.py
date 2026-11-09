import json
import os
import shutil
import tempfile

from datetime import datetime
from logging import Logger
from typing import Any, Dict, List, Optional, Union, Set

from .thread_manager import ThreadManager, PoolKeys, run_threaded


def _write_json(
    data: Union[Dict[str, Any], List[int]],
    target_path: str,
    logger: Logger,
) -> bool:
    """
    Atomically writes a JSON file and replaces the target on success.

    Args:
        data: JSON-serializable dictionary.
        target_path: Destination JSON file path.
        logger: Logger instance.
    Returns:
        True if write succeeded, False otherwise.
    """
    temp_path = None
    target_dir = os.path.dirname(target_path) or "."

    try:
        fd, temp_path = tempfile.mkstemp(
            dir=target_dir,
            prefix=os.path.basename(target_path) + "_",
            suffix=".tmp",
        )
        os.close(fd)

        try:
            with open(temp_path, "w", encoding="utf-8") as tmp_file:
                # Write JSON data using a compact format and preserving Unicode characters.
                # separators=(",", ":") removes the default spaces after commas and colons.
                json.dump(
                    data,
                    tmp_file,
                    separators=(",", ":"),
                    ensure_ascii=False,
                )
        except (TypeError, ValueError) as e:
            logger.error(f"Invalid JSON data for '{target_path}': {e}")
            return False
        except OSError as e:
            logger.error(f"Error writing temp JSON file '{temp_path}': {e}")
            return False

        try:
            shutil.move(temp_path, target_path)
            temp_path = None
        except OSError as e:
            logger.error(f"Error atomically replacing JSON file '{target_path}': {e}")
            return False
        logger.debug(f"JSON file updated at: {target_path}")
        return True

    except OSError as e:
        logger.error(f"Filesystem error during JSON write: {e}")
        return False

    except Exception as e:
        logger.exception(
            f"Unexpected error while writing JSON file '{target_path}': {e}"
        )
        return False

    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError as e:
                logger.warning(f"Failed to clean up temp JSON file '{temp_path}': {e}")


def _read_json(
    path: str,
    logger: Logger,
    default: Optional[Any] = None,
) -> Any:
    """
    Reads a JSON file.

    - Returns `default` if the file does not exist or is invalid.
    - Logs errors if a logger is provided.
    - Deletes the file if it is corrupt.

    Args:
        path : Path to the JSON file.
        logger : Logger instance for logging.
        default : Value to return if read fails.
    """
    try:
        logger.debug(f"Reading JSON file: {path}")
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        logger.debug(f"JSON file not found: {path}")
        return default
    except (json.JSONDecodeError, OSError) as e:
        logger.error(f"Error reading JSON file '{path}': {e}")
        try:
            os.remove(path)
            if logger:
                logger.debug(f"Corrupt JSON file removed: {path}")
        except Exception as remove_error:
            if logger:
                logger.error(
                    f"Failed to remove corrupt JSON file '{path}': {remove_error}"
                )
        return default


def _validate_cache_file(path: str, ttl: int, logger: Logger) -> bool:
    """
    Validates a cache file based on its age.
    Returns True if the file exists and is within the TTL.

    Args:
        path : Path to the cache file.
        ttl : Time-to-live in seconds.
        logger : Logger instance for logging.
    """
    if not os.path.exists(path):
        logger.debug("All assets cache file does not exist.")
        return False
    file_mod_time = os.path.getmtime(path)
    age_seconds = datetime.now().timestamp() - file_mod_time
    if age_seconds > ttl:
        logger.warning(f"Cache file is older than {ttl} seconds, ignoring.")
        return False
    return True


class AssetCacheSystem:

    _last_cache_refresh: Optional[datetime]

    # In Memory caches
    _assets_cache: Dict[str, Any]
    _negative_cache: Set[int]

    # Cache file paths
    _cache_dir: str
    _max_cache_age: int
    _assets_cache_path: str
    _negative_cache_path: str

    def __init__(
        self,
        cache_dir: str,
        max_cache_age: int,
        logger: Logger,
        tm: Optional[ThreadManager] = None,
    ) -> None:
        """
        Initialize the AssetCacheSystem with a directory
        and time-to-live for cache entries.
        Args:
            cache_dir : The directory where cache files are stored.
            max_cache_age : Maximum age of cache files in seconds.
            tm : Optional ThreadManager used by @run_threaded for async disk writes.
        """
        self._cache_dir = cache_dir
        if not os.path.exists(self._cache_dir):
            os.makedirs(self._cache_dir, exist_ok=True)

        self._max_cache_age = max_cache_age
        self._logger = logger
        self._tm = tm

        self._assets_cache_path = os.path.join(self._cache_dir, "assets_cache.json")
        self._negative_cache_path = os.path.join(self._cache_dir, "negative_cache.json")

        self._last_cache_refresh = None
        self._assets_cache = {}
        self._negative_cache = []

        self._load_negative_cache()

    def write_all_assets_cache(self, data: Dict[str, Any]) -> None:
        """Updates in-memory cache immediately and writes to disk asynchronously."""
        self._logger.debug("Writing all assets cache to disk.")
        self._assets_cache = data
        self._last_cache_refresh = datetime.now()
        serialized = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
        self._write_cache_to_disk(serialized)

        # Check if any IDs in negative cache are now valid
        if self._negative_cache:
            cached_ids = {a["AssetID"] for a in data.get("data", [])}
            self._negative_cache = {
                aid for aid in self._negative_cache if aid not in cached_ids
            }
            self._logger.debug(
                f"Negative cache pruned to {len(self._negative_cache)} entries."
            )
            self._save_negative_cache()

    @run_threaded(PoolKeys.INTERACTIVE)
    def _write_cache_to_disk(self, serialized: str) -> None:
        """Writes a pre-serialized JSON string to the assets cache file atomically."""
        temp_path = None
        target_dir = os.path.dirname(self._assets_cache_path) or "."
        try:
            fd, temp_path = tempfile.mkstemp(
                dir=target_dir,
                prefix=os.path.basename(self._assets_cache_path) + "_",
                suffix=".tmp",
            )
            os.close(fd)
            with open(temp_path, "w", encoding="utf-8") as f:
                f.write(serialized)
            shutil.move(temp_path, self._assets_cache_path)
            temp_path = None
            self._logger.debug(f"JSON file updated at: {self._assets_cache_path}")
        except Exception as e:
            self._logger.error(f"Async cache write failed: {e}")
        finally:
            if temp_path and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except OSError:
                    pass

    def read_all_assets_cache(self) -> Optional[Dict[str, Any]]:
        """
        Reads and returns data from the all-assets cache file.
        Uses in-memory cache when available, and validates file age.
        Returns None if cache is missing, expired, unreadable, or corrupt.
        """
        # Return already-cached memory version
        if self._assets_cache:
            return self._assets_cache

        if not _validate_cache_file(
            self._assets_cache_path,
            self._max_cache_age,
            self._logger,
        ):
            return None

        self._logger.debug("Reading all assets cache from disk.")
        data = _read_json(
            self._assets_cache_path,
            self._logger,
            default=None,
        )
        if data is None:
            return None
        self._assets_cache = data
        return data

    def validate_all_assets_cache(self, asset_ids: List[int]) -> bool:
        """
        Validates the all-assets cache against a given list of asset IDs.

        If one or more asset IDs are missing, the cache is considered invalid
        and should be refreshed. However, if the cache was refreshed recently,
        it is still considered valid even when some IDs are missing.

        NOTE: When this method is called before the all-assets cache has been
        fetched for the first time, all provided IDs are treated as invalid
        and added to the negative cache. Once the all-assets cache is fetched
        and written, the negative cache is automatically pruned, removing any
        IDs that are now present in the cache.
        """
        cache_data = self.read_all_assets_cache()
        if cache_data is None:
            self._logger.debug("Validating all assets cache with no cache data")
            cache_data = {}

        # Ignore IDs already marked as invalid
        asset_ids = [aid for aid in asset_ids if aid not in self._negative_cache]
        cached_ids = {a["AssetID"] for a in cache_data.get("data", [])}
        invalid_ids = [aid for aid in asset_ids if aid not in cached_ids]

        # Update cache with newly found invalid IDs
        if invalid_ids:
            self._negative_cache.update(invalid_ids)
            self._save_negative_cache()
            self._logger.debug(f"Added {len(invalid_ids)} IDs to negative cache")
            # if cache was recently refreshed, consider it valid anyway
            # otherwise, it's invalid
            return self._last_cache_refresh is not None
        return True

    def _load_negative_cache(self) -> None:
        """Loads the negative cache from disk into memory."""
        self._logger.debug("Loading negative cache from disk.")
        data = _read_json(
            self._negative_cache_path,
            self._logger,
            default=None,
        )
        self._negative_cache = set(data) if isinstance(data, list) else set()

    def _save_negative_cache(self) -> None:
        """Saves the negative cache from memory to disk."""
        self._logger.debug("Saving negative cache to disk.")
        _write_json(
            list(self._negative_cache),
            self._negative_cache_path,
            self._logger,
        )
