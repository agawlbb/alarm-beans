# SPDX-License-Identifier: MPL-2.0
"""Pure protocol tests run locally without a live Home Assistant instance."""
import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).parents[2] / "custom_components/alarm_beans/protocol.py"
spec = importlib.util.spec_from_file_location("bean_protocol", path)
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)


def report(locked=False, receipts=None):
    return {"values": {"wake_time": "07:00", "haptic_interval": 5, "iphone_offset": 5},
            "enabled": locked, "locked": locked, "receipts": receipts or []}


class ProtocolTests(unittest.TestCase):
    def test_pairing_is_single_use_and_device_credential_is_revocable(self):
        broker = protocol.PairingBroker(clock=lambda: 0)
        ticket = broker.issue("flow", "https://ha.example", "device")
        payload = broker.qr(ticket["ticket_id"])
        consumed, credential = broker.consume(payload["token"])
        self.assertNotEqual(credential, payload["token"])
        self.assertEqual(consumed["credential_hash"], protocol.credential_hash(credential))
        self.assertTrue(protocol.authorized(credential, consumed["credential_hash"]))
        self.assertFalse(protocol.authorized(credential, None))
        self.assertFalse(protocol.authorized("wrong", consumed["credential_hash"]))
        with self.assertRaises(ValueError): broker.consume(payload["token"])
        with self.assertRaises(ValueError): broker.qr(ticket["ticket_id"])

    def test_qr_and_token_expire_and_restart_invalidates_tokens(self):
        now = [0]
        broker = protocol.PairingBroker(clock=lambda: now[0])
        ticket = broker.issue("flow", "https://ha.example", "device")
        now[0] = 300
        with self.assertRaises(ValueError): broker.qr(ticket["ticket_id"])
        with self.assertRaises(ValueError): broker.consume(ticket["token"])
        with self.assertRaises(ValueError): protocol.PairingBroker().consume(ticket["token"])

    def test_pairing_accepts_only_trusted_https_origin_shape(self):
        for url in ["http://ha.local", "https://u:p@ha.local", "https://ha.local/path", "https://ha.local?x=1", "https://ha.local#part"]:
            with self.subTest(url=url), self.assertRaises(ValueError): protocol.validate_url(url)
        self.assertEqual(protocol.validate_url("https://ha.example:8123/"), "https://ha.example:8123")

    def test_pending_preserves_accepted_state_then_acknowledges(self):
        ledger = protocol.Ledger()
        ledger.sync(report(), "first")
        ledger.request("wake_time", "09:14")
        self.assertEqual(ledger.data["values"]["wake_time"], "07:00")
        self.assertEqual(ledger.attributes("wake_time")["pending_value"], "09:14")
        commands = ledger.sync(report(), "second")
        self.assertEqual(commands[0]["value"], "09:14")
        accepted = report(receipts=[{"id": commands[0]["id"].upper(), "accepted": True}])
        accepted["values"]["wake_time"] = "09:14"
        self.assertEqual(ledger.sync(accepted, "third"), [])
        self.assertEqual(ledger.data["values"]["wake_time"], "09:14")
        self.assertEqual(ledger.attributes("wake_time")["request_status"], "accepted")
        self.assertNotIn("pending_value", ledger.attributes("wake_time"))

    def test_active_report_rejects_and_discards_requests(self):
        ledger = protocol.Ledger()
        for field, value in [("wake_time", "08:00"), ("haptic_interval", 14), ("iphone_offset", 9)]: ledger.request(field, value)
        self.assertEqual(ledger.sync(report(locked=True), "active"), [])
        self.assertTrue(all(r["status"] == "rejected" for r in ledger.data["requests"].values()))
        self.assertEqual(ledger.sync(report(), "dismissed"), [])
        self.assertEqual(ledger.data["values"], report()["values"])

    def test_setter_rejects_known_locked_alarm_without_queueing(self):
        ledger = protocol.Ledger()
        ledger.sync(report(True), "active")
        with self.assertRaises(ValueError): ledger.request("wake_time", "10:00")
        self.assertEqual(ledger.attributes("wake_time")["request_status"], "rejected")
        self.assertEqual(ledger.sync(report(), "dismissed"), [])

    def test_rejected_or_unacknowledged_claim_never_replays_after_restart(self):
        for acknowledge in [False, True]:
            ledger = protocol.Ledger()
            ledger.request("wake_time", "11:00")
            commands = ledger.sync(report(), "claim")
            ledger = protocol.Ledger(json.loads(json.dumps(ledger.data)))
            receipts = [{"id": commands[0]["id"], "accepted": False, "reason": "Alarm locked"}] if acknowledge else []
            self.assertEqual(ledger.sync(report(receipts=receipts), "resume"), [])
            self.assertEqual(ledger.attributes("wake_time")["request_status"], "rejected")
            self.assertEqual(ledger.sync(report(), "after-dismiss"), [])

    def test_acknowledgement_does_not_claim_new_pending_request(self):
        ledger = protocol.Ledger()
        ledger.request("wake_time", "12:00")
        commands = ledger.sync(report(), "claim")
        ledger.request("haptic_interval", 23)
        receipts = [{"id": commands[0]["id"], "accepted": True}]
        self.assertEqual(ledger.sync(report(receipts=receipts), "ack"), [])
        self.assertEqual(ledger.attributes("haptic_interval")["request_status"], "pending")
        self.assertEqual(len(ledger.sync(report(), "next-open")), 1)

    def test_new_pairing_discards_old_pending_and_claimed_requests(self):
        ledger = protocol.Ledger()
        ledger.request("wake_time", "12:00")
        ledger.sync(report(), "claim")
        ledger.request("iphone_offset", 13)
        ledger.invalidate_pending()
        self.assertEqual(ledger.sync(report(), "new-pair"), [])

    def test_bounds_and_exactly_three_writable_fields(self):
        for field, value in [("wake_time", "24:00"), ("wake_time", "1:01"), ("wake_time", "12:00:01"),
                             ("haptic_interval", True), ("haptic_interval", 0), ("haptic_interval", 61),
                             ("iphone_offset", 31), ("iphone_offset", 1.5), ("enabled", True), ("pattern", "retry")]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError): protocol.validate_value(field, value)
        for field, value in [("wake_time", "00:00"), ("wake_time", "23:59"), ("haptic_interval", 60), ("iphone_offset", 30)]:
            self.assertEqual(protocol.validate_value(field, value), value)


if __name__ == "__main__": unittest.main()
