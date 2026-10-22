# SPDX-License-Identifier: MPL-2.0
"""Alarm Beans: four entities bridged by the paired iPhone on app opening."""
import asyncio
from copy import deepcopy
from homeassistant.const import Platform
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util
from .protocol import Ledger, PairingBroker, authorized

DOMAIN = "alarm_beans"
PLATFORMS = [Platform.TIME, Platform.NUMBER, Platform.BINARY_SENSOR]


class Hub:
    def __init__(self, hass, entry):
        self.hass, self.entry = hass, entry
        self.store = Store(hass, 1, f"{DOMAIN}.{entry.data['device_id']}")
        self.ledger = Ledger()
        self.lock = asyncio.Lock()
        self.listeners = set()

    async def load(self):
        self.ledger = Ledger(await self.store.async_load())

    async def request(self, field, value):
        async with self.lock:
            try:
                self.ledger.request(field, value)
            finally:
                await self.store.async_save(self.ledger.data)
                self.notify()

    async def sync(self, report, credential):
        async with self.lock:
            if not authorized(credential, self.entry.data.get("credential_hash")):
                raise PermissionError("Device credential revoked")
            previous = deepcopy(self.ledger.data)
            try:
                commands = self.ledger.sync(report, dt_util.utcnow().isoformat())
                # Persist claims before returning any command to the phone.
                await self.store.async_save(self.ledger.data)
            except Exception:
                self.ledger = Ledger(previous)
                raise
            self.notify()
            return commands

    def notify(self):
        for listener in tuple(self.listeners):
            listener()


class Registry:
    def __init__(self):
        self.broker = PairingBroker()
        self.hubs = {}
        self.ready = {}


def registry(hass):
    if DOMAIN not in hass.data:
        hass.data[DOMAIN] = Registry()
        from .http import PairView, QRView, SyncView, RevokeView
        for view in (PairView, QRView, SyncView, RevokeView):
            hass.http.register_view(view(hass))
    return hass.data[DOMAIN]


async def async_setup(hass, config):
    registry(hass)
    return True


async def async_setup_entry(hass, entry):
    state = registry(hass)
    hub = Hub(hass, entry)
    await hub.load()
    entry.runtime_data = hub
    state.hubs[entry.data["device_id"]] = hub
    state.ready.setdefault(entry.data["device_id"], asyncio.Event()).set()
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass, entry):
    if await hass.config_entries.async_unload_platforms(entry, PLATFORMS):
        state = registry(hass)
        state.hubs.pop(entry.data["device_id"], None)
        state.ready.pop(entry.data["device_id"], None)
        return True
    return False
