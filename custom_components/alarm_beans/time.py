# SPDX-License-Identifier: MPL-2.0
from datetime import time
from homeassistant.components.time import TimeEntity
from .entity import BeanEntity


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([WakeTime(entry.runtime_data, "wake_time", "Wake time")])


class WakeTime(BeanEntity, TimeEntity):
    @property
    def native_value(self):
        values = self.hub.ledger.data["values"]
        return time.fromisoformat(values["wake_time"]) if values else None

    async def async_set_value(self, value):
        if value.second or value.microsecond:
            raise ValueError("Wake time uses hours and minutes")
        await self.request(value.strftime("%H:%M"))
