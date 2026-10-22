# SPDX-License-Identifier: MPL-2.0
"""Framework contract tests run in CI with the pinned actual HA package."""
import importlib.util
import sys
from pathlib import Path
import unittest
from types import SimpleNamespace

try:
    import homeassistant
except ImportError:
    homeassistant = None


@unittest.skipIf(homeassistant is None, "HA framework contract is checked on Linux CI")
class HAContractTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        sys.path.insert(0, str(Path(__file__).parents[1]))
        from custom_components.alarm_beans.protocol import Ledger
        self.hub = SimpleNamespace(entry=SimpleNamespace(data={"device_id": "test-device"}), ledger=Ledger(), listeners=set())

    async def test_platforms_create_exactly_four_entities(self):
        from custom_components.alarm_beans import time, number, binary_sensor
        from homeassistant.components.time import TimeEntity
        from homeassistant.components.number import NumberEntity
        from homeassistant.components.binary_sensor import BinarySensorEntity
        entities = []
        entry = SimpleNamespace(runtime_data=self.hub)
        for platform in [time, number, binary_sensor]:
            await platform.async_setup_entry(None, entry, entities.extend)
        self.assertEqual(len(entities), 4)
        self.assertEqual(sum(isinstance(e, TimeEntity) for e in entities), 1)
        self.assertEqual(sum(isinstance(e, NumberEntity) for e in entities), 2)
        self.assertEqual(sum(isinstance(e, BinarySensorEntity) for e in entities), 1)
        self.assertEqual(len({e.unique_id for e in entities}), 4)
        self.assertTrue(all(not e.should_poll for e in entities))
        self.assertIsNone(entities[0].native_value)
        self.assertIsNone(entities[-1].is_on)

    async def test_config_flow_and_scoped_http_views_import(self):
        from custom_components.alarm_beans.config_flow import AlarmBeansConfigFlow, AlarmBeansOptionsFlow
        from custom_components.alarm_beans.http import PairView, QRView, SyncView, RevokeView
        self.assertEqual(AlarmBeansConfigFlow.VERSION, 1)
        self.assertTrue(callable(AlarmBeansOptionsFlow.async_step_revoke))
        self.assertEqual(len({v.url for v in [PairView, QRView, SyncView, RevokeView]}), 4)

    async def test_http_rejects_missing_wrong_and_revoked_credentials(self):
        from aiohttp import web
        from custom_components.alarm_beans import Registry, DOMAIN
        from custom_components.alarm_beans.http import SyncView
        from custom_components.alarm_beans.protocol import credential_hash
        self.hub.entry.data["credential_hash"] = credential_hash("valid-device-secret")
        state = Registry()
        state.hubs["test-device"] = self.hub
        view = SyncView(SimpleNamespace(data={DOMAIN: state}))
        for header in ["", "Bearer invalid", "Basic valid-device-secret"]:
            with self.assertRaises(web.HTTPUnauthorized):
                await view.post(SimpleNamespace(headers={"Authorization": header}), "test-device")
        self.hub.entry.data["credential_hash"] = None
        with self.assertRaises(web.HTTPUnauthorized):
            await view.post(SimpleNamespace(headers={"Authorization": "Bearer valid-device-secret"}), "test-device")

    async def test_qr_and_pair_view_consume_token_once(self):
        import asyncio,json
        from aiohttp import web
        from custom_components.alarm_beans import Registry, DOMAIN
        from custom_components.alarm_beans.http import PairView, QRView
        state = Registry()
        ticket = state.broker.issue("flow", "https://ha.example", "device")
        ready = state.ready.setdefault("device", asyncio.Event())
        async def configure(flow_id, user_input):
            self.assertEqual(flow_id, "flow")
            ready.set()
        hass = SimpleNamespace(data={DOMAIN: state}, config_entries=SimpleNamespace(flow=SimpleNamespace(async_configure=configure)))
        qr = await QRView(hass).get(None, ticket["ticket_id"])
        self.assertIn(b"<svg", qr.body)
        self.assertEqual(qr.headers["Cache-Control"], "no-store")
        async def body(): return {"token": ticket["token"]}
        request = SimpleNamespace(content_length=100, json=body)
        result = await PairView(hass).post(request)
        self.assertEqual(result.status, 200)
        self.assertIn("credential", json.loads(result.body))
        with self.assertRaises(web.HTTPUnauthorized): await PairView(hass).post(request)
        with self.assertRaises(web.HTTPNotFound): await QRView(hass).get(None, ticket["ticket_id"])

    async def test_hub_rechecks_revocation_inside_state_lock(self):
        import asyncio
        from custom_components.alarm_beans import Hub
        from custom_components.alarm_beans.protocol import credential_hash
        class MemoryStore:
            async def async_save(self, value): pass
        hub = object.__new__(Hub)
        hub.entry = self.hub.entry
        hub.entry.data["credential_hash"] = credential_hash("valid")
        hub.lock = asyncio.Lock()
        hub.ledger = self.hub.ledger
        hub.store = MemoryStore()
        hub.listeners = set()
        report = {"values": {"wake_time": "07:00", "haptic_interval": 5, "iphone_offset": 5},
                  "enabled": False, "locked": False, "receipts": []}
        await hub.lock.acquire()
        task = asyncio.create_task(hub.sync(report, "valid"))
        await asyncio.sleep(0)
        hub.entry.data["credential_hash"] = None
        hub.lock.release()
        with self.assertRaises(PermissionError): await task
        self.assertIsNone(hub.ledger.data["values"])

    async def test_hub_does_not_return_unpersisted_commands(self):
        import asyncio
        from custom_components.alarm_beans import Hub
        from custom_components.alarm_beans.protocol import credential_hash
        class FailedStore:
            async def async_save(self, value): raise OSError("disk unavailable")
        hub = object.__new__(Hub)
        hub.entry = self.hub.entry
        hub.entry.data["credential_hash"] = credential_hash("valid")
        hub.lock = asyncio.Lock()
        hub.ledger = self.hub.ledger
        hub.store = FailedStore()
        hub.listeners = set()
        hub.ledger.request("wake_time", "10:20")
        report = {"values": {"wake_time": "07:00", "haptic_interval": 5, "iphone_offset": 5},
                  "enabled": False, "locked": False, "receipts": []}
        with self.assertRaises(OSError): await hub.sync(report, "valid")
        self.assertEqual(hub.ledger.attributes("wake_time")["request_status"], "pending")
        self.assertIsNone(hub.ledger.data["values"])
        previous_id = hub.ledger.data["requests"]["wake_time"]["id"]
        with self.assertRaises(OSError): await hub.request("wake_time", "16:00")
        self.assertEqual(hub.ledger.data["requests"]["wake_time"]["id"], previous_id)


if __name__ == "__main__": unittest.main()
