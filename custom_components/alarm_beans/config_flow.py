# SPDX-License-Identifier: MPL-2.0
"""User-initiated HTTPS pairing and credential revocation."""
from uuid import uuid4
import probatio as schema
from homeassistant import config_entries
from homeassistant.core import callback
from homeassistant.helpers.network import get_url, NoURLAvailableError
from . import DOMAIN, registry
from .protocol import validate_url


class PairFlow:
    _ticket = None

    async def async_step_pair(self, user_input=None):
        if self._ticket["credential_hash"]:
            data = {"device_id": self._ticket["device_id"], "url": self._ticket["url"],
                    "credential_hash": self._ticket["credential_hash"]}
            if isinstance(self, config_entries.OptionsFlow):
                hub = self.config_entry.runtime_data
                async with hub.lock:
                    hub.ledger.invalidate_pending()
                    await hub.store.async_save(hub.ledger.data)
                    self.hass.config_entries.async_update_entry(self.config_entry, data=data)
                    hub.notify()
                return self.async_create_entry(title="", data={})
            return self.async_create_entry(title="Alarm Beans", data=data)
        broker = registry(self.hass).broker
        try:
            broker.qr(self._ticket["ticket_id"])
        except ValueError:
            self._ticket = broker.issue(self.flow_id, self._ticket["url"], self._ticket["device_id"],
                                        isinstance(self, config_entries.OptionsFlow))
        return self.async_show_form(step_id="pair", data_schema=schema.Schema({}),
            description_placeholders={"qr_url": f"{self._ticket['url']}/api/alarm_beans/pairing/{self._ticket['ticket_id']}/qr.svg"},
            errors={"base": "not_paired"} if user_input is not None else {})


class AlarmBeansConfigFlow(PairFlow, config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input=None):
        await self.async_set_unique_id(DOMAIN)
        self._abort_if_unique_id_configured()
        errors = {}
        try:
            default_url = get_url(self.hass, prefer_external=True, require_ssl=True)
        except NoURLAvailableError:
            default_url = ""
        if user_input is not None:
            try:
                url = validate_url(user_input["url"])
                self._ticket = registry(self.hass).broker.issue(self.flow_id, url, str(uuid4()))
                return await self.async_step_pair()
            except ValueError:
                errors["base"] = "invalid_url"
        return self.async_show_form(step_id="user", data_schema=schema.Schema({schema.Required("url", default=default_url): str}), errors=errors)

    @staticmethod
    @callback
    def async_get_options_flow(config_entry):
        return AlarmBeansOptionsFlow()


class AlarmBeansOptionsFlow(PairFlow, config_entries.OptionsFlow):
    async def async_step_init(self, user_input=None):
        return self.async_show_menu(step_id="init", menu_options=["pair", "revoke"])

    async def async_step_pair(self, user_input=None):
        if self._ticket is None:
            self._ticket = registry(self.hass).broker.issue(self.flow_id, self.config_entry.data["url"],
                                                           self.config_entry.data["device_id"], True)
        return await super().async_step_pair(user_input)

    async def async_step_revoke(self, user_input=None):
        hub = self.config_entry.runtime_data
        async with hub.lock:
            hub.ledger.invalidate_pending()
            await hub.store.async_save(hub.ledger.data)
            data = dict(self.config_entry.data)
            data["credential_hash"] = None
            self.hass.config_entries.async_update_entry(self.config_entry, data=data)
            hub.notify()
        return self.async_create_entry(title="", data={})
