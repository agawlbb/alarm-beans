# SPDX-License-Identifier: MPL-2.0
from homeassistant.components.number import NumberEntity, NumberMode
from .entity import BeanEntity


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([SettingNumber(entry.runtime_data, "haptic_interval", "Haptic interval", 60, "s"),
                        SettingNumber(entry.runtime_data, "iphone_offset", "iPhone offset", 30, "min")])


class SettingNumber(BeanEntity, NumberEntity):
    def __init__(self, hub, field, name, maximum, unit):
        super().__init__(hub, field, name)
        self._attr_native_min_value = 1
        self._attr_native_max_value = maximum
        self._attr_native_step = 1
        self._attr_native_unit_of_measurement = unit
        self._attr_mode = NumberMode.BOX

    @property
    def native_value(self):
        values = self.hub.ledger.data["values"]
        return values[self.field] if values else None

    async def async_set_native_value(self, value):
        if not isinstance(value, (int, float)) or isinstance(value, bool) or not float(value).is_integer():
            raise ValueError("Use a whole number")
        await self.request(int(value))
