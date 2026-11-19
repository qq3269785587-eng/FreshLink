#!/usr/bin/env python3
"""Exercise FreshLink D3 outbound and delivery behavior through the HTTP API."""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
import pathlib
import sys
import urllib.parse
import uuid
from concurrent.futures import ThreadPoolExecutor


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "fresh_d2_probe", PROJECT_ROOT / "scripts" / "Invoke-FreshD2ApiProbe.py"
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load the shared D2 HTTP probe helpers.")
D2 = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = D2
SPEC.loader.exec_module(D2)


class Probe(D2.Probe):
    def __init__(self):
        super().__init__()
        self.created_inventory_ids = []
        self.confirmed_order_ids = []

    def request(self, case, method, path, body=None, token=None, expect_success=True):
        api = self.api if token is None or token == self.token else D2.Api(self.api_root, token, self.evidence)
        status, payload = api.request(method, path, body=body)
        if api is not self.api:
            self.api.calls.extend(api.calls)
        success = payload.get("success") is True if isinstance(payload, dict) else False
        valid = status < 500 and (success if expect_success else not success)
        message = payload.get("message", "") if isinstance(payload, dict) else ""
        self.record(case, f"{method} {path} {'succeeds' if expect_success else 'is rejected'}",
                    valid, f"HTTP {status}, success={success}, message={message}")
        return status, payload if isinstance(payload, dict) else {"result": payload}

    def call(self, case, method, path, body=None, form=None, expect_success=True):
        if form is not None:
            status, payload = self.api.request(method, path, form=form)
            success = payload.get("success") is True if isinstance(payload, dict) else False
            self.record(case, f"{method} {path} {'succeeds' if expect_success else 'is rejected'}",
                        status < 500 and (success if expect_success else not success),
                        f"HTTP {status}, success={success}, message={payload.get('message', '') if isinstance(payload, dict) else ''}")
            return payload if isinstance(payload, dict) else {"result": payload}
        return self.request(case, method, path, body=body, expect_success=expect_success)[1]

    def detail(self, case, method, path, body=None, expect_success=True, token=None):
        _, payload = self.request(case, method, path, body=body, token=token, expect_success=expect_success)
        result = payload.get("result")
        return result if isinstance(result, dict) else {}

    def inventory(self, case):
        return self.get_list(case, "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")

    def store_id(self, store_code):
        rows = self.get_list("D3-setup", "/fresh/stores/list?pageNo=1&pageSize=100")
        store = next((row for row in rows if row.get("storeCode") == store_code), None)
        if not store or not store.get("id"):
            raise D2.ProbeError(f"Seeded store {store_code} is missing.")
        return store["id"]

    @staticmethod
    def detail_result(payload):
        result = payload.get("result") if isinstance(payload, dict) else None
        return result if isinstance(result, dict) else {}

    def create_outbound(self, store_id, lines, case):
        payload = self.call(case, "POST", "/fresh/outbounds", {"storeId": store_id, "lines": lines})
        result = self.detail_result(payload)
        order = result.get("order")
        outbound_id = order.get("id") if isinstance(order, dict) else None
        if not outbound_id:
            raise D2.ProbeError("Outbound API did not return result.order.id.")
        return outbound_id, result

    def assert_balance(self, case, expected_stock, expected_available):
        rows = self.inventory(case)
        selected = [row for row in rows if row.get("id") in self.created_inventory_ids]
        stock = sum(int(row.get("stockQuantity") or 0) for row in selected)
        available = sum(int(row.get("availableQuantity") or 0) for row in selected)
        self.record(case, "D3 inventory row and unallocated balances match expected totals",
                    stock == expected_stock and available == expected_available,
                    f"rows={len(selected)}, stock={stock}, available={available}, expected={expected_stock}")
        return selected

    def run(self):
        before_rows = self.inventory("D3-setup")
        if not any(row.get("batchNumber") == "D2-DB-EXPIRED-BOUNDARY" for row in before_rows):
            raise D2.ProbeError("Isolated D2 boundary fixture is missing. No D3 writes were sent.")

        suppliers = self.get_list("D3-setup", "/fresh/suppliers/list?pageNo=1&pageSize=100")
        supplier_id = next((row.get("id") for row in suppliers if row.get("supplierCode") == "S1"), None)
        if not supplier_id:
            raise D2.ProbeError("D3 probe requires seeded supplier S1.")

        # Create two eligible, traceable C1 lots through the ordinary D2 inbound endpoints.
        batch_a, batch_b = f"D3A-{self.suffix}", f"D3B-{self.suffix}"
        order_id = self.add_order(supplier_id, [
            self.item(batch_a, 10, self.today + dt.timedelta(days=8)),
            self.item(batch_b, 20, self.today + dt.timedelta(days=10)),
        ], case="D3-fixture")
        self.submit_and_approve(order_id, "D3-fixture")
        self.receive_and_putaway_two_lots(order_id, [
            {"batch": batch_a, "quantity": 10}, {"batch": batch_b, "quantity": 20}
        ], case="D3-fixture")

        inventory = self.inventory("D3-fixture")
        batches = {}
        for batch in (batch_a, batch_b):
            row = next((entry for entry in inventory if entry.get("batchNumber") == batch
                        and entry.get("locationCode") == "C1"), None)
            if not row or not row.get("id") or not row.get("stockBatchKey"):
                raise D2.ProbeError(f"Could not resolve eligible C1 inventory for {batch}.")
            batches[batch] = row
            self.created_inventory_ids.append(row["id"])
        self.assert_balance("D3-fixture", 30, 30)

        store_a = self.store_id("A")
        temporary_batch = f"D3TEMP-{self.suffix}"
        temporary_order = self.add_order(supplier_id, [
            self.item(temporary_batch, 1, self.today + dt.timedelta(days=12))
        ], case="D3-03")
        self.submit_and_approve(temporary_order, "D3-03")
        _, temporary_tasks = self.create_receive_task(temporary_order, "D3-03")
        temporary_task = next((row for row in temporary_tasks if row.get("batchNumber") == temporary_batch), None)
        if temporary_task is None:
            raise D2.ProbeError("Could not find the receiving task for the temporary-location fixture.")
        self.call("D3-03", "POST", "/inorder/receiveTasks/addRecords", {
            "id": temporary_task["id"], "execQuantity": 1,
            "targetLocationCode": "R1", "requestKey": str(uuid.uuid4()),
        })
        temporary_rows = self.inventory("D3-03")
        temporary_stock = next((row for row in temporary_rows if row.get("batchNumber") == temporary_batch
                                and row.get("locationCode") == "R1"), None)
        if not temporary_stock:
            raise D2.ProbeError("Could not resolve received stock at the temporary R1 location.")
        self.created_inventory_ids.append(temporary_stock["id"])
        self.record("D3-03", "receiving stock remains in a temporary location", int(temporary_stock.get("stockQuantity") or 0) == 1,
                    f"location={temporary_stock.get('locationCode')}, stock={temporary_stock.get('stockQuantity')}")
        self.reject_at_create_or_confirm("D3-03", store_a, [{
            "inventoryId": temporary_stock["id"], "stockBatchKey": temporary_stock.get("stockBatchKey"), "quantity": 1,
        }], "temporary receiving location")
        self.created_inventory_ids.remove(temporary_stock["id"])

        first_lines = [{"inventoryId": batches[batch_a]["id"], "stockBatchKey": batches[batch_a]["stockBatchKey"], "quantity": 6}]
        outbound_id, created = self.create_outbound(store_a, first_lines, "D3-01")
        self.record("D3-01", "draft has not reserved inventory or created delivery",
                    created.get("deliveryId") in (None, "") and
                    isinstance(created.get("order"), dict) and
                    created["order"].get("status") in {"DRAFT", "CREATED"},
                    f"status={created.get('order', {}).get('status')}, deliveryIdPresent={bool(created.get('deliveryId'))}")
        draft_id, draft = self.create_outbound(store_a, first_lines, "D3-draft")
        self.call("D3-draft", "PUT", f"/fresh/outbounds/{draft_id}", {"storeId": store_a, "lines": first_lines})
        self.call("D3-draft", "DELETE", f"/fresh/outbounds/{draft_id}")
        self.assert_balance("D3-01", 30, 30)

        path = f"/fresh/outbounds/{outbound_id}/confirm"
        with ThreadPoolExecutor(max_workers=2) as pool:
            replies = list(pool.map(lambda _: self.api.request("POST", path), range(2)))
        results = [payload.get("result") if isinstance(payload, dict) else None for _, payload in replies]
        success = all(status < 500 and isinstance(payload, dict) and payload.get("success") is True
                      for status, payload in replies)
        same_delivery = len({result.get("deliveryId") for result in results if isinstance(result, dict)}) == 1
        self.record("D3-04", "simultaneous confirmation of one order returns one delivery", success and same_delivery,
                    f"HTTP statuses={[status for status, _ in replies]}, deliveryIds={[result.get('deliveryId') if isinstance(result, dict) else None for result in results]}")
        confirmed_result = next((result for result in results if isinstance(result, dict)), {})
        delivery_id = confirmed_result.get("deliveryId")
        self.confirmed_order_ids.append(outbound_id)
        self.record("D3-01", "confirmation returns outbound lines and a pending delivery ID",
                    bool(delivery_id) and confirmed_result.get("order", {}).get("status") == "CONFIRMED"
                    and any(line.get("batchNumber") == batch_a and line.get("quantity") == 6
                            for line in confirmed_result.get("lines", [])),
                    f"deliveryIdPresent={bool(delivery_id)}, lines={len(confirmed_result.get('lines') or [])}")
        self.assert_balance("D3-01", 24, 24)

        duplicate = self.detail("D3-04", "POST", path)
        self.record("D3-04", "repeated confirmation returns the existing delivery",
                    duplicate.get("deliveryId") == delivery_id,
                    f"sameDelivery={duplicate.get('deliveryId') == delivery_id}")
        self.assert_balance("D3-04", 24, 24)

        # Group the same stock row before checking quantity so rows cannot individually pass and overdraw.
        first, second = sorted((batches[batch_a], batches[batch_b]), key=lambda row: row["id"])
        for label, lines in (
            ("same-row aggregate exceeds balance", [
                {"inventoryId": batches[batch_a]["id"], "stockBatchKey": batches[batch_a]["stockBatchKey"], "quantity": 3},
                {"inventoryId": batches[batch_a]["id"], "stockBatchKey": batches[batch_a]["stockBatchKey"], "quantity": 2},
            ]),
            ("multi-row total exceeds balance", [
                {"inventoryId": first["id"], "stockBatchKey": first["stockBatchKey"], "quantity": 3},
                {"inventoryId": second["id"], "stockBatchKey": second["stockBatchKey"], "quantity": 22},
            ]),
        ):
            case = "D3-02"
            invalid_id, _ = self.create_outbound(store_a, lines, case)
            self.call(case, "POST", f"/fresh/outbounds/{invalid_id}/confirm", expect_success=False)
            details = self.detail(case, "GET", f"/fresh/outbounds/{invalid_id}")
            self.record(case, label + " leaves order unconfirmed and without delivery",
                        details.get("deliveryId") in (None, "") and
                        isinstance(details.get("order"), dict)
                        and details["order"].get("status") in {"DRAFT", "CREATED"},
                        f"status={details.get('order', {}).get('status')}, deliveryIdPresent={bool(details.get('deliveryId'))}")
            self.assert_balance(case, 24, 24)

        for label, line in (
            ("wrong stock key", {"inventoryId": batches[batch_b]["id"], "stockBatchKey": "wrong-key", "quantity": 1}),
            ("expired batch", next(({"inventoryId": row.get("id"), "stockBatchKey": row.get("stockBatchKey"), "quantity": 1}
                                     for row in before_rows if row.get("batchNumber") == "D2-DB-EXPIRED-BOUNDARY"), {})),
            ("source-less history", next(({"inventoryId": row.get("id"), "stockBatchKey": row.get("stockBatchKey"), "quantity": 1}
                                           for row in before_rows if row.get("batchNumber") == "D2-DB-HISTORY-NO-SOURCE"), {})),
        ):
            self.reject_at_create_or_confirm("D3-03", store_a, [line], label)
        for invalid_quantity in (None, 0, -1, 1.5, "1", 2147483648):
            self.reject_at_create_or_confirm("D3-03", store_a, [{
                "inventoryId": batches[batch_b]["id"],
                "stockBatchKey": batches[batch_b]["stockBatchKey"],
                "quantity": invalid_quantity,
            }], f"invalid quantity {invalid_quantity}")
        self.assert_balance("D3-02", 24, 24)

        pending = self.detail("D3-06", "GET", f"/fresh/deliveries/{delivery_id}")
        self.record("D3-06", "delivery detail includes the address snapshot and batch items",
                    bool(pending.get("storeAddress")) and bool(pending.get("items")),
                    f"status={pending.get('status')}, items={len(pending.get('items') or [])}")
        self.call("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/start", expect_success=False)
        self.call("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/deliver", expect_success=False)
        self.assert_balance("D3-06", 24, 24)

        info = {"driverName": "D3 Probe Driver", "driverPhone": "13800000000", "remark": "isolated HTTP probe"}
        self.call("D3-06", "PUT", f"/fresh/deliveries/{delivery_id}/dispatch-info", info)
        in_transit = self.detail("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/start")
        self.record("D3-06", "dispatch advances pending delivery to in transit with actor and time",
                    in_transit.get("status") == "IN_TRANSIT" and bool(in_transit.get("dispatchBy"))
                    and bool(in_transit.get("dispatchAt")),
                    f"status={in_transit.get('status')}, actorPresent={bool(in_transit.get('dispatchBy'))}, timePresent={bool(in_transit.get('dispatchAt'))}")
        self.call("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/start")
        delivered = self.detail("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/deliver")
        self.record("D3-06", "delivery completes and records actor and time",
                    delivered.get("status") == "DELIVERED" and bool(delivered.get("deliveredBy"))
                    and bool(delivered.get("deliveredAt")),
                    f"status={delivered.get('status')}, actorPresent={bool(delivered.get('deliveredBy'))}, timePresent={bool(delivered.get('deliveredAt'))}")
        self.call("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/deliver")
        self.call("D3-06", "POST", f"/fresh/deliveries/{delivery_id}/start", expect_success=False)
        self.assert_balance("D3-06", 24, 24)

        self.call("D3-07", "PUT", f"/fresh/outbounds/{outbound_id}",
                  {"storeId": store_a, "lines": first_lines}, expect_success=False)
        self.call("D3-07", "DELETE", f"/fresh/outbounds/{outbound_id}", expect_success=False)
        self.call("D3-07", "PUT", "/outorder/wmsOutOrders/edit",
                  {"id": outbound_id, "status": "CREATED"}, expect_success=False)
        self.call("D3-07", "GET", "/shipment/waybill/send?" + urllib.parse.urlencode({"waveId": outbound_id}),
                  expect_success=False)
        self.assert_balance("D3-07", 24, 24)
        self.verify_store_scope(delivery_id)
        self.write_evidence()
        return self.failures == 0

    def reject_at_create_or_confirm(self, case, store_id, lines, label):
        status, payload = self.api.request("POST", "/fresh/outbounds", body={"storeId": store_id, "lines": lines})
        result = payload.get("result") if isinstance(payload, dict) else None
        order = result.get("order") if isinstance(result, dict) else None
        outbound_id = order.get("id") if isinstance(order, dict) else None
        if not payload.get("success"):
            self.record(case, f"{label} is rejected before a draft is created", status < 500,
                        f"HTTP {status}, success={payload.get('success')}, message={payload.get('message', '')}")
            return
        _, rejected = self.request(case, "POST", f"/fresh/outbounds/{outbound_id}/confirm", expect_success=False)
        self.record(case, f"{label} confirmation rejection is a business response", rejected.get("success") is False,
                    f"success={rejected.get('success')}, message={rejected.get('message', '')}")

    def verify_store_scope(self, delivery_id):
        token_a = os.environ.get("D3_STORE_A_TOKEN", "").strip()
        token_b = os.environ.get("D3_STORE_B_TOKEN", "").strip()
        if not token_a or not token_b:
            self.record("D3-07", "store-specific delivery authorization skipped",
                        True, "Set D3_STORE_A_TOKEN and D3_STORE_B_TOKEN to run own-store and other-store reads.")
            return
        own = self.detail("D3-07", "GET", f"/fresh/deliveries/{delivery_id}", token=token_a)
        self.record("D3-07", "bound store can read its delivery", bool(own), f"found={bool(own)}")
        other_status, other = self.request("D3-07", "GET", f"/fresh/deliveries/{delivery_id}", token=token_b, expect_success=False)
        self.record("D3-07", "different store cannot read this delivery",
                    other_status in (403, 404) or other.get("success") is False,
                    f"HTTP {other_status}, success={other.get('success')}")
        self.request("D3-07", "POST", f"/fresh/deliveries/{delivery_id}/deliver", token=token_a, expect_success=False)

    def write_evidence(self):
        super().write_evidence()
        (self.evidence / "d3-ids.json").write_text(json.dumps({
            "outboundIds": self.confirmed_order_ids,
            "inventoryIds": self.created_inventory_ids,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        path = self.evidence / "summary.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        report["probe"] = "D3 outbound and delivery HTTP assertions"
        report["note"] = "D3 outbound IDs are retained for isolated database fault-injection checks. Credentials are not stored."
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    probe = None
    try:
        probe = Probe()
        passed = probe.run()
        print(f"D3 HTTP probe: {len(probe.assertions) - probe.failures}/{len(probe.assertions)} assertions passed")
        return 0 if passed else 1
    except Exception as exc:
        if probe is not None:
            try:
                probe.write_evidence()
            except Exception:
                pass
        print(f"D3 HTTP probe stopped: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
