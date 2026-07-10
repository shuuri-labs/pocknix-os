import asyncio

from pocknix_control.config import build_config
from pocknix_control.modes import set_fan_mode, set_lavd_mode
from pocknix_control.sdcard import detect_sdcard, format_sdcard
from pocknix_control.tweaks import save_tweaks


class Plugin:
    # Offload blocking work to a thread so a slow call can't stall Decky's asyncio loop.
    async def get_config(self):
        return await asyncio.to_thread(build_config)

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
