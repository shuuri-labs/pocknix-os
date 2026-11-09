import asyncio

from pocknix_control.config import build_config
from pocknix_control.gamemode import sync_game_mode
from pocknix_control.led import restore_led, set_led, set_led_enabled, set_led_linked, set_led_sides
from pocknix_control.modes import set_fan_mode, set_lavd_mode
from pocknix_control.snapshots import reboot_system, snapshot_status, start_rollback
from pocknix_control.touch import sync_touch
from pocknix_control.tweaks import patch_tweaks
from pocknix_control.updates import check_updates, start_update, update_status


class Plugin:
    # Appid of the running game, reported by the frontend's app-lifetime hook; drives the
    # touchscreen tweak. Starts None, so a (re)loaded backend turns touch back on.
    _running_appid = None

    # Offload blocking work to a thread so a slow call can't stall Decky's asyncio loop.
    async def get_config(self):
        return await asyncio.to_thread(build_config)

    async def _main(self):
        await asyncio.to_thread(restore_led)
        await asyncio.to_thread(sync_touch, self._running_appid)

    async def _unload(self):
        await asyncio.to_thread(sync_touch, None)

    async def game_lifetime(self, appid, running):
        appid = str(appid or "")
        if running:
            self._running_appid = appid or None
        elif appid == self._running_appid:
            self._running_appid = None
        await asyncio.to_thread(sync_touch, self._running_appid)

    async def set_fan_mode(self, mode):
        await asyncio.to_thread(set_fan_mode, mode)
        return await self.get_config()

    async def set_lavd_mode(self, mode):
        await asyncio.to_thread(set_lavd_mode, mode)
        return await self.get_config()

    async def patch_tweaks(self, appid, fields):
        tweaks = await asyncio.to_thread(patch_tweaks, appid, fields)
        await asyncio.to_thread(sync_touch, self._running_appid)
        await asyncio.to_thread(sync_game_mode)
        return tweaks

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
