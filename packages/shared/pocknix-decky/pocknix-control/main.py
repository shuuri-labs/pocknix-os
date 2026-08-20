import asyncio

from pocknix_control.config import build_config
from pocknix_control.configio import apply_config, config_dir, export_config, read_config
from pocknix_control.led import restore_led, set_led, set_led_enabled, set_led_linked, set_led_sides
from pocknix_control.modes import set_fan_mode, set_lavd_mode
from pocknix_control.sdcard import detect_sdcard, format_sdcard
from pocknix_control.snapshots import reboot_system, snapshot_status, start_rollback
from pocknix_control.tweaks import save_tweaks
from pocknix_control.updates import check_updates, start_update, update_status


class Plugin:
    # Offload blocking work to a thread so a slow call can't stall Decky's asyncio loop.
    async def get_config(self):
        return await asyncio.to_thread(build_config)

    async def _main(self):
        await asyncio.to_thread(restore_led)

    async def detect_sdcard(self):
        return await asyncio.to_thread(detect_sdcard)

    async def format_sdcard(self, label):
        return await asyncio.to_thread(format_sdcard, label)

    async def set_fan_mode(self, mode):
        await asyncio.to_thread(set_fan_mode, mode)
        return await self.get_config()

    async def set_lavd_mode(self, mode):
        await asyncio.to_thread(set_lavd_mode, mode)
        return await self.get_config()

    async def save_tweaks(self, data):
        await asyncio.to_thread(save_tweaks, data)
        return await self.get_config()

    async def export_config(self, appid, name, basename, allow_overwrite):
        return await asyncio.to_thread(export_config, appid, name, basename, allow_overwrite)

    async def config_dir(self):
        return await asyncio.to_thread(config_dir)

    async def read_config(self, path):
        return await asyncio.to_thread(read_config, path)

    async def apply_config(self, path, source_appid, target_appid, target_name):
        return await asyncio.to_thread(apply_config, path, source_appid, target_appid, target_name)

    # Not get_config(): that re-parses the whole Steam library, and a colour slider
    # commits repeatedly while it is being dialled in.
    async def set_led(self, side, r, g, b, brightness):
        return await asyncio.to_thread(set_led, side, r, g, b, brightness)

    async def set_led_linked(self, linked):
        return await asyncio.to_thread(set_led_linked, linked)

    async def set_led_enabled(self, enabled):
        return await asyncio.to_thread(set_led_enabled, enabled)

    async def set_led_sides(self, sides):
        return await asyncio.to_thread(set_led_sides, sides)

    async def check_updates(self):
        return await asyncio.to_thread(check_updates)

    async def start_update(self):
        return await asyncio.to_thread(start_update)

    async def update_status(self):
        return await asyncio.to_thread(update_status)

    async def snapshot_status(self):
        return await asyncio.to_thread(snapshot_status)

    async def start_rollback(self, snapshot_id):
        return await asyncio.to_thread(start_rollback, snapshot_id)

    async def reboot_system(self):
        return await asyncio.to_thread(reboot_system)
