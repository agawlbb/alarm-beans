# SPDX-License-Identifier: MPL-2.0
from homeassistant.components.binary_sensor import BinarySensorEntity
from .entity import BeanEntity


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([AlarmEnabled(entry.runtime_data, "enabled", "Alarm enabled")])


class AlarmEnabled(BeanEntity, BinarySensorEntity):
    @property
    def is_on(self):
        return self.hub.ledger.data["enabled"]
