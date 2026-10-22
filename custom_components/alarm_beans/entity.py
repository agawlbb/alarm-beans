# SPDX-License-Identifier: MPL-2.0
from homeassistant.helpers.entity import Entity
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.exceptions import HomeAssistantError
from . import DOMAIN


class BeanEntity(Entity):
    _attr_should_poll = False
    _attr_has_entity_name = True

    def __init__(self, hub, field, name):
        self.hub, self.field = hub, field
        self._attr_name = name
        self._attr_unique_id = f"{hub.entry.data['device_id']}_{field}"
        self._attr_device_info = DeviceInfo(identifiers={(DOMAIN, hub.entry.data["device_id"])}, name="Alarm Beans", manufacturer="Alarm Beans")

    async def async_added_to_hass(self):
        await super().async_added_to_hass()
        self.hub.listeners.add(self.async_write_ha_state)
        self.async_on_remove(lambda: self.hub.listeners.discard(self.async_write_ha_state))

    @property
    def extra_state_attributes(self):
        return self.hub.ledger.attributes(self.field)

    async def request(self, value):
        try:
            await self.hub.request(self.field, value)
        except ValueError as error:
            raise HomeAssistantError(str(error)) from error
