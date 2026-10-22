# SPDX-License-Identifier: MPL-2.0
"""Transport-independent pairing and one-shot settings protocol."""
from __future__ import annotations

from copy import deepcopy
import hashlib
import hmac
import re
import secrets
import time
from uuid import UUID, uuid4
from urllib.parse import urlsplit

FIELDS = {"wake_time", "haptic_interval", "iphone_offset"}


def validate_url(value: str) -> str:
    url = urlsplit(value)
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or url.query or url.fragment or url.path not in ("", "/")):
        raise ValueError("A trusted HTTPS Home Assistant origin is required")
    if url.port is not None and not 1 <= url.port <= 65535:
        raise ValueError("Invalid HTTPS port")
    return value.rstrip("/")


def validate_value(field: str, value):
    if field == "wake_time":
        if not isinstance(value, str) or not re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", value):
            raise ValueError("Use HH:MM")
    elif field in ("haptic_interval", "iphone_offset"):
        maximum = 60 if field == "haptic_interval" else 30
        if type(value) is not int or not 1 <= value <= maximum:
            raise ValueError("Outside supported range")
    else:
        raise ValueError("Unsupported setting")
    return value


def credential_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def authorized(secret: str, stored_hash: str | None) -> bool:
    return bool(stored_hash and len(secret) <= 128 and
                hmac.compare_digest(credential_hash(secret), stored_hash))


class PairingBroker:
    """Tokens live only in RAM, expire in five minutes, and are consumed once."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.tickets = {}

    def issue(self, flow_id: str, url: str, device_id: str, options=False):
        self.tickets = {k: v for k, v in self.tickets.items() if v["expires"] > self.clock()}
        if len(self.tickets) >= 16:
            raise ValueError("Too many pairing attempts")
        ticket_id, token = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        ticket = {"ticket_id": ticket_id, "token": token, "url": validate_url(url),
                  "flow_id": flow_id, "device_id": device_id, "options": options,
                  "expires": self.clock() + 300, "credential_hash": None}
        self.tickets[ticket_id] = ticket
        return ticket

    def qr(self, ticket_id: str):
        ticket = self.tickets.get(ticket_id)
        if not ticket or ticket["expires"] <= self.clock():
            raise ValueError("Pairing expired")
        return {"url": ticket["url"], "token": ticket["token"]}

    def consume(self, token: str):
        if not isinstance(token, str) or len(token) > 128:
            raise ValueError("Invalid pairing token")
        for key, ticket in list(self.tickets.items()):
            if hmac.compare_digest(token, ticket["token"]):
                del self.tickets[key]  # consume synchronously, before any await
                if ticket["expires"] <= self.clock():
                    raise ValueError("Pairing expired")
                credential = secrets.token_urlsafe(32)
                ticket["credential_hash"] = credential_hash(credential)
                return ticket, credential
        raise ValueError("Invalid or used pairing token")


class Ledger:
    """Only acknowledged phone values become entity state; commands are one-shot."""

    def __init__(self, data=None):
        self.data = deepcopy(data) if data else {"values": None, "enabled": None,
            "locked": None, "last_sync": None, "requests": {}}

    def request(self, field, value):
        validate_value(field, value)
        command = {"id": str(uuid4()), "field": field, "value": str(value), "status": "pending"}
        self.data["requests"][field] = command  # coalesce only requests not delivered yet
        if self.data["locked"]:
            command.update(status="rejected", reason="Alarm is locked")
            raise ValueError("Alarm is locked")

    def sync(self, report, now):
        values = report["values"]
        if set(values) != FIELDS or type(report["enabled"]) is not bool or type(report["locked"]) is not bool:
            raise ValueError("Invalid report")
        for field, value in values.items():
            validate_value(field, value)
        receipts = report.get("receipts", [])
        if not isinstance(receipts, list) or len(receipts) > 256:
            raise ValueError("Invalid receipts")
        for receipt in receipts:
            if (not isinstance(receipt, dict) or not isinstance(receipt.get("id"), str)
                    or type(receipt.get("accepted")) is not bool):
                raise ValueError("Invalid receipt")
            UUID(receipt["id"])
        self.data.update(values=dict(values), enabled=report["enabled"], locked=report["locked"], last_sync=now)
        by_id = {str(UUID(receipt["id"])): receipt for receipt in receipts}
        commands = []
        for command in self.data["requests"].values():
            if command["status"] == "claimed":
                receipt = by_id.get(command["id"])
                if receipt:
                    command.update(status="accepted" if receipt["accepted"] else "rejected")
                    if not receipt["accepted"]:
                        command["reason"] = str(receipt.get("reason", "Rejected"))[:160]
                else:
                    command.update(status="rejected", reason="Delivery not acknowledged; request again")
            elif command["status"] == "pending":
                if report["locked"]:
                    command.update(status="rejected", reason="Alarm is locked")
                elif not receipts:  # acknowledgement POST must never claim new work
                    command["status"] = "claimed"
                    commands.append({key: command[key] for key in ("id", "field", "value")})
        return commands

    def attributes(self, field=None):
        result = {"last_sync": self.data["last_sync"], "settings_locked": self.data["locked"]}
        if field and (command := self.data["requests"].get(field)):
            result["request_status"] = command["status"]
            if command["status"] in ("pending", "claimed"):
                result["pending_value"] = command["value"]
            if command.get("reason"):
                result["rejection_reason"] = command["reason"]
        return result

    def invalidate_pending(self):
        for command in self.data["requests"].values():
            if command["status"] in ("pending", "claimed"):
                command.update(status="rejected", reason="Pairing changed; request again")
