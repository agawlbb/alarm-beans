# SPDX-License-Identifier: MPL-2.0
"""Narrow, credential-authenticated endpoints; no HA administrator token on iPhone."""
import asyncio
import io
import json
from aiohttp import web
import segno
from homeassistant.components.http import HomeAssistantView
from . import DOMAIN, registry
from .protocol import authorized


class BaseView(HomeAssistantView):
    requires_auth = False  # These endpoints validate a scoped device credential instead.

    def __init__(self, hass):
        self.hass = hass


class PairView(BaseView):
    url = "/api/alarm_beans/pair"
    name = "api:alarm_beans:pair"

    async def post(self, request):
        if request.content_length is None or request.content_length > 4096:
            raise web.HTTPRequestEntityTooLarge(max_size=4096, actual_size=request.content_length or 0)
        try:
            ticket, credential = registry(self.hass).broker.consume((await request.json())["token"])
        except (ValueError, KeyError, TypeError):
            raise web.HTTPUnauthorized() from None
        manager = self.hass.config_entries.options if ticket["options"] else self.hass.config_entries.flow
        try:
            await manager.async_configure(ticket["flow_id"], user_input={})
            state = registry(self.hass)
            await asyncio.wait_for(state.ready.setdefault(ticket["device_id"], asyncio.Event()).wait(), 10)
        except (ValueError, TimeoutError):
            raise web.HTTPServiceUnavailable() from None
        return web.json_response({"device_id": ticket["device_id"], "credential": credential},
                                 headers={"Cache-Control": "no-store"})


class QRView(BaseView):
    url = "/api/alarm_beans/pairing/{ticket_id}/qr.svg"
    name = "api:alarm_beans:qr"

    async def get(self, request, ticket_id):
        try:
            payload = registry(self.hass).broker.qr(ticket_id)
        except ValueError:
            raise web.HTTPNotFound() from None
        buffer = io.BytesIO()
        segno.make(json.dumps(payload, separators=(",", ":")), micro=False).save(buffer, kind="svg", scale=5, dark="black", light="white")
        return web.Response(body=buffer.getvalue(), content_type="image/svg+xml",
                            headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"})


class SyncView(BaseView):
    url = "/api/alarm_beans/device/{device_id}/sync"
    name = "api:alarm_beans:sync"

    async def post(self, request, device_id):
        hub = registry(self.hass).hubs.get(device_id)
        header = request.headers.get("Authorization", "")
        if not hub or not header.startswith("Bearer ") or not authorized(header[7:], hub.entry.data.get("credential_hash")):
            raise web.HTTPUnauthorized()
        if request.content_length is None or request.content_length > 65536:
            raise web.HTTPRequestEntityTooLarge(max_size=65536, actual_size=request.content_length or 0)
        try:
            commands = await hub.sync(await request.json(), header[7:])
        except PermissionError:
            raise web.HTTPUnauthorized() from None
        except (ValueError, KeyError, TypeError):
            raise web.HTTPBadRequest() from None
        return web.json_response({"requests": commands}, headers={"Cache-Control": "no-store"})


class RevokeView(BaseView):
    url = "/api/alarm_beans/device/{device_id}/revoke"
    name = "api:alarm_beans:revoke"

    async def post(self, request, device_id):
        hub = registry(self.hass).hubs.get(device_id)
        header = request.headers.get("Authorization", "")
        if not hub or not header.startswith("Bearer ") or not authorized(header[7:], hub.entry.data.get("credential_hash")):
            raise web.HTTPUnauthorized()
        async with hub.lock:
            if not authorized(header[7:], hub.entry.data.get("credential_hash")):
                raise web.HTTPUnauthorized()
            data = dict(hub.entry.data)
            data["credential_hash"] = None
            self.hass.config_entries.async_update_entry(hub.entry, data=data)
            hub.ledger.invalidate_pending()
            await hub.store.async_save(hub.ledger.data)
            hub.notify()
        return web.json_response({}, headers={"Cache-Control": "no-store"})
