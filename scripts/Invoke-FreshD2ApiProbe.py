#!/usr/bin/env python3
"""Exercise FreshLink D2 inbound behavior through the running HTTP API.

Credentials and database provisioning stay outside this reusable probe. Supply an
access token issued by the local test login flow and point the probe at an
isolated test instance. Evidence contains sanitized HTTP exchanges only.
"""

from __future__ import annotations

import csv
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import json
import os
import pathlib
import sys
import urllib.parse
import urllib.error
import urllib.request
import uuid


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]


class ProbeError(RuntimeError):
    pass


class Api:
    def __init__(self, root: str, token: str, evidence: pathlib.Path):
        self.root = root.rstrip("/")
        parsed_root = urllib.parse.urlparse(self.root)
        if (parsed_root.scheme != "http" or parsed_root.hostname not in {"127.0.0.1", "localhost", "::1"}
                or parsed_root.username or parsed_root.password or parsed_root.query or parsed_root.fragment):
            raise ProbeError("API root must be plain HTTP on a loopback host.")
        self.token = token
        self.evidence = evidence
        self.calls = []

    def request(self, method: str, path: str, body=None, form=None):
        url = self.root + path
        headers = {"X-Access-Token": self.token, "Authorization": self.token, "Version": "v3"}
        data = None
        if body is not None:
            data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        elif form is not None:
            data = urllib.parse.urlencode(form).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        status = 0
        raw = ""
        try:
            with urllib.request.urlopen(req, timeout=45) as response:
                status = response.status
                raw = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            status = exc.code
            raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {"raw": raw[:2000]}
        exchange = {
            "method": method,
            "path": path,
            "http": status,
            "request": body if body is not None else form,
            "response": parsed,
        }
        self.calls.append(exchange)
        return status, parsed


class Probe:
    def __init__(self):
        self.api_root = os.environ.get("FRESHLINK_API_ROOT", "http://127.0.0.1:18082/jeecg-boot")
        self.token = os.environ.get("FRESHLINK_ACCESS_TOKEN", "").strip()
        self.operator_id = os.environ.get("FRESHLINK_OPERATOR_ID", "").strip()
        evidence_arg = os.environ.get("FRESHLINK_EVIDENCE_DIR", "")
        if not self.token:
            raise ProbeError("Set FRESHLINK_ACCESS_TOKEN to a local test-account access token.")
        if not self.operator_id:
            raise ProbeError("Set FRESHLINK_OPERATOR_ID to the test warehouse user's ID.")
        if not evidence_arg:
            raise ProbeError("Set FRESHLINK_EVIDENCE_DIR to a fresh directory under project work/.")
        evidence_path = pathlib.Path(evidence_arg)
        evidence = (evidence_path if evidence_path.is_absolute() else PROJECT_ROOT / evidence_path).resolve()
        work = (PROJECT_ROOT / "work").resolve()
        if work not in evidence.parents:
            raise ProbeError("Evidence must be written under this checkout's work/ directory.")
        if evidence.exists() and any(evidence.iterdir()):
            raise ProbeError("Evidence directory is not empty. Use a new attempt directory.")
        evidence.mkdir(parents=True, exist_ok=True)
        self.evidence = evidence
        self.api = Api(self.api_root, self.token, evidence)
        self.assertions = []
        self.failures = 0
        self.today = dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).date()
        self.suffix = uuid.uuid4().hex[:8].upper()

    def record(self, case, assertion, passed, detail):
        result = {"case": case, "assertion": assertion, "passed": bool(passed), "detail": str(detail)}
        self.assertions.append(result)
        print(("PASS" if passed else "FAIL") + f" {case} {assertion}: {detail}")
        self.failures += int(not passed)

    def call(self, case, method, path, body=None, form=None, expect_success=True):
        status, payload = self.api.request(method, path, body=body, form=form)
        success = payload.get("success") is True if isinstance(payload, dict) else False
        valid = status < 500 and (success if expect_success else not success)
        self.record(case, f"{method} {path} {'succeeds' if expect_success else 'is rejected'}", valid,
                    f"HTTP {status}, success={success}, message={payload.get('message', '') if isinstance(payload, dict) else ''}")
        return payload if isinstance(payload, dict) else {"result": payload}

    def get_list(self, case, path):
        payload = self.call(case, "GET", path)
        return (payload.get("result") or {}).get("records", [])

    def add_order(self, supplier_id, items, case="D2-01"):
        body = {
            "orderType": "PURCHASE_IN",
            "sourceNumber": f"D2-{self.suffix}-{uuid.uuid4().hex[:6].upper()}",
            "ownerId": "fresh_p1_owner",
            "expectedArrivalTime": dt.datetime.combine(self.today, dt.time(12)).strftime("%Y-%m-%d %H:%M:%S"),
            "warehouseId": "fresh_p1_wh_w1",
            "supplierId": supplier_id,
            "remarks": "HTTP D2 probe fixture",
            "wmsStockInOrderItemsList": items,
        }
        result = self.call(case, "POST", "/inorder/wmsStockInOrders/add", body)
        result_data = result.get("result")
        order_id = result_data.get("id") if isinstance(result_data, dict) else None
        if not order_id:
            # Some Jeecg add endpoints return only a message. Read back by the unique source number.
            rows = self.get_list(case, "/inorder/wmsStockInOrders/list?" + urllib.parse.urlencode({"pageNo": 1, "pageSize": 100, "sourceNumber": body["sourceNumber"]}))
            order_id = next((row.get("id") for row in rows if row.get("sourceNumber") == body["sourceNumber"]), None)
        if not order_id:
            raise ProbeError("Inbound add response did not identify the created order. Inspect sanitized exchange evidence.")
        return order_id

    def submit_and_approve(self, order_id, case):
        self.call(case, "POST", "/inorder/wmsStockInOrders/submitAudit", {"id": order_id})
        self.call(case, "POST", "/inorder/wmsStockInOrders/audit", {"id": order_id, "status": "APPROVED"})

    def create_receive_task(self, order_id, case):
        self.call(case, "POST", "/inorder/receiveTasks/add", form={"orderIds": order_id, "operator": self.operator_id})
        order = self.call(case, "GET", "/inorder/wmsStockInOrders/queryById?" + urllib.parse.urlencode({"id": order_id}))
        order_number = (order.get("result") or {}).get("orderNumber")
        rows = self.get_list(case, "/inorder/receiveTasks/list?" + urllib.parse.urlencode({"pageNo": 1, "pageSize": 100, "stockInOrderNumber": order_number}))
        tasks = [row for row in rows if row.get("stockInOrderId") == order_id]
        if not tasks:
            raise ProbeError("Could not find the receive task created for the HTTP fixture order.")
        return order_number, tasks

    def receive_and_putaway(self, order_id, quantity, case="D2-01"):
        order_number, receive_tasks = self.create_receive_task(order_id, case)
        receive_task = next((row for row in receive_tasks if int(row.get("quantity") or 0) == quantity), receive_tasks[0])
        task_id = receive_task["id"]
        correct = {"id": task_id, "execQuantity": quantity, "targetLocationCode": "R1", "requestKey": str(uuid.uuid4())}
        self.call(case, "POST", "/inorder/receiveTasks/addRecords", correct)
        retry = self.api.request("POST", "/inorder/receiveTasks/addRecords", body=correct)
        self.record(case, "same receive request key is idempotent", retry[0] < 500 and retry[1].get("success") is True,
                    f"HTTP {retry[0]}, success={retry[1].get('success')}")
        conflicting_retry = dict(correct, execQuantity=quantity + 1)
        self.call("D2-02", "POST", "/inorder/receiveTasks/addRecords", conflicting_retry, expect_success=False)
        over_receive = dict(correct, execQuantity=1, requestKey=str(uuid.uuid4()))
        self.call("D2-02", "POST", "/inorder/receiveTasks/addRecords", over_receive, expect_success=False)
        # The receive task creates one putaway task for the received lot.
        putaway_rows = self.get_list(case, "/inorder/putawayTasks/list?" + urllib.parse.urlencode({"pageNo": 1, "pageSize": 100, "stockInOrderNumber": order_number}))
        task = next((row for row in putaway_rows if row.get("stockInOrderItemId") == receive_task.get("stockInOrderItemId")), None)
        if not task:
            raise ProbeError("Could not find the putaway task created after receiving.")
        action = {"id": task["id"], "execQuantity": quantity, "targetLocationCode": "C1", "requestKey": str(uuid.uuid4())}
        self.call(case, "POST", "/inorder/putawayTasks/addRecords", action)
        self.call(case, "POST", "/inorder/putawayTasks/addRecords", action)
        over_putaway = dict(action, execQuantity=1, requestKey=str(uuid.uuid4()))
        self.call("D2-02", "POST", "/inorder/putawayTasks/addRecords", over_putaway, expect_success=False)
        return task_id

    def receive_and_putaway_two_lots(self, order_id, expected_lots, case="D2-01"):
        order_number, receive_tasks = self.create_receive_task(order_id, case)
        for index, lot in enumerate(expected_lots):
            receive_task = next((row for row in receive_tasks if row.get("batchNumber") == lot["batch"]), None)
            if receive_task is None:
                raise ProbeError(f"Receive task missing for {lot['batch']}.")
            action = {"id": receive_task["id"], "execQuantity": lot["quantity"], "targetLocationCode": "R1", "requestKey": str(uuid.uuid4())}
            if index == 0:
                for invalid_quantity in (None, 2147483648):
                    invalid = dict(action, execQuantity=invalid_quantity, requestKey=str(uuid.uuid4()))
                    self.call("D2-03", "POST", "/inorder/receiveTasks/addRecords", invalid, expect_success=False)
            if index == 0:
                with ThreadPoolExecutor(max_workers=2) as pool:
                    replies = list(pool.map(
                        lambda _: self.api.request("POST", "/inorder/receiveTasks/addRecords", body=action),
                        range(2),
                    ))
                passed = all(status < 500 and body.get("success") is True for status, body in replies)
                self.record("D2-02", "two simultaneous receipts with one key both return success",
                            passed, f"HTTP statuses={[status for status, _ in replies]}")
            else:
                self.call(case, "POST", "/inorder/receiveTasks/addRecords", action)
            replay = self.api.request("POST", "/inorder/receiveTasks/addRecords", body=action)
            self.record(case, f"{lot['batch']} same-key receive replay succeeds", replay[0] < 500 and replay[1].get("success") is True,
                        f"HTTP {replay[0]}, success={replay[1].get('success')}")
            if index == 0:
                conflict = dict(action, execQuantity=lot["quantity"] + 1)
                self.call("D2-02", "POST", "/inorder/receiveTasks/addRecords", conflict, expect_success=False)
                extra = dict(action, execQuantity=1, requestKey=str(uuid.uuid4()))
                self.call("D2-02", "POST", "/inorder/receiveTasks/addRecords", extra, expect_success=False)

        received = self.get_list(case, "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")
        received_lots = [row for row in received if row.get("batchNumber") in {lot["batch"] for lot in expected_lots}
                         and row.get("locationCode") == "R1"]
        received_by_lot = {row.get("batchNumber"): int(row.get("stockQuantity") or 0) for row in received_lots}
        self.record(case, "both lots are at R1 with total 30 before putaway",
                    sum(received_by_lot.values()) == 30 and all(received_by_lot.get(lot["batch"]) == lot["quantity"] for lot in expected_lots),
                    f"R1 quantities={received_by_lot}, total={sum(received_by_lot.values())}")

        putaway_rows = self.get_list(case, "/inorder/putawayTasks/list?" + urllib.parse.urlencode({"pageNo": 1, "pageSize": 100, "stockInOrderNumber": order_number}))
        for index, lot in enumerate(expected_lots):
            receive_task = next(row for row in receive_tasks if row.get("batchNumber") == lot["batch"])
            task = next((row for row in putaway_rows if row.get("stockInOrderItemId") == receive_task.get("stockInOrderItemId")), None)
            if task is None:
                raise ProbeError(f"Putaway task missing for {lot['batch']}.")
            action = {"id": task["id"], "execQuantity": lot["quantity"], "targetLocationCode": "C1", "requestKey": str(uuid.uuid4())}
            if index == 0:
                self.call("D2-02", "POST", "/inorder/putawayTasks/addRecords",
                          dict(action, targetLocationCode="N1"), expect_success=False)
                for invalid_quantity in (None, 2147483648):
                    invalid = dict(action, execQuantity=invalid_quantity, requestKey=str(uuid.uuid4()))
                    self.call("D2-03", "POST", "/inorder/putawayTasks/addRecords", invalid, expect_success=False)
            self.call(case, "POST", "/inorder/putawayTasks/addRecords", action)
            replay = self.api.request("POST", "/inorder/putawayTasks/addRecords", body=action)
            self.record(case, f"{lot['batch']} same-key putaway replay succeeds", replay[0] < 500 and replay[1].get("success") is True,
                        f"HTTP {replay[0]}, success={replay[1].get('success')}")
            conflict = dict(action, execQuantity=lot["quantity"] + 1)
            self.call("D2-02", "POST", "/inorder/putawayTasks/addRecords", conflict, expect_success=False)
            if index == 0:
                extra = dict(action, execQuantity=1, requestKey=str(uuid.uuid4()))
                self.call("D2-02", "POST", "/inorder/putawayTasks/addRecords", extra, expect_success=False)

        after = self.get_list(case, "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")
        target_lots = [row for row in after if row.get("batchNumber") in {lot["batch"] for lot in expected_lots}
                       and row.get("locationCode") == "C1"]
        target_quantities = {row.get("batchNumber"): int(row.get("stockQuantity") or 0) for row in target_lots}
        self.record(case, "both lots moved to C1 with total 30 and R1 was emptied",
                    sum(target_quantities.values()) == 30 and all(target_quantities.get(lot["batch"]) == lot["quantity"] for lot in expected_lots)
                    and not any(row.get("batchNumber") in {lot["batch"] for lot in expected_lots} and row.get("locationCode") == "R1" and int(row.get("stockQuantity") or 0) for row in after),
                    f"C1 quantities={target_quantities}, total={sum(target_quantities.values())}")

    def item(self, batch, quantity, expiry, production=None):
        return {
            "productId": "fresh_p1_product_x",
            "expectedQuantity": quantity,
            "batchNumber": batch,
            "productionDate": (production or self.today - dt.timedelta(days=2)).isoformat(),
            "expiryDate": expiry.isoformat(),
        }

    def run(self):
        preflight = self.get_list("setup", "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")
        if not {"D2-DB-EXPIRED-BOUNDARY", "D2-DB-HISTORY-NO-SOURCE"}.issubset(
                {row.get("batchNumber") for row in preflight}):
            raise ProbeError("Isolated D2 fixture markers are missing. No write requests were sent.")

        suppliers = self.get_list("D2-05", "/fresh/suppliers/list?pageNo=1&pageSize=100")
        supplier_by_code = {row.get("supplierCode"): row.get("id") for row in suppliers}
        s1 = supplier_by_code.get("S1")
        s2 = supplier_by_code.get("S2")
        if not s1 or not s2:
            raise ProbeError("D2 probe requires active seeded suppliers S1 and S2.")

        # Real API-created lots establish the positive receipt/putaway path and supplier-scoped same-name batches.
        lot_a = f"D2A-{self.suffix}"
        lot_b = f"D2B-{self.suffix}"
        same_lot = f"D2SAME-{self.suffix}"
        dates = [(self.today + dt.timedelta(days=n)) for n in (2, 8, 2)]
        orders = [
            self.add_order(s1, [self.item(lot_a, 10, dates[0]), self.item(lot_b, 20, dates[1])]),
            self.add_order(s2, [self.item(same_lot, 5, dates[2])], case="D2-05"),
            self.add_order(s1, [self.item(same_lot, 7, dates[2])], case="D2-05"),
        ]
        self.submit_and_approve(orders[0], "D2-01")
        self.receive_and_putaway_two_lots(orders[0], [{"batch": lot_a, "quantity": 10}, {"batch": lot_b, "quantity": 20}])
        for order_id, quantity in zip(orders[1:], (5, 7)):
            self.submit_and_approve(order_id, "D2-05")
            self.receive_and_putaway(order_id, quantity, case="D2-05")

        inventory = self.get_list("D2-01", "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")
        batches = [row for row in inventory if str(row.get("batchNumber", "")).startswith("D2")]
        self.record("D2-01", "inventory shows the received total of 30 for B1/B2", sum(int(row.get("stockQuantity") or 0) for row in batches if row.get("batchNumber") in (lot_a, lot_b)) == 30,
                    f"matching rows={len(batches)}, B1/B2 stock={sum(int(row.get('stockQuantity') or 0) for row in batches if row.get('batchNumber') in (lot_a, lot_b))}")
        same_rows = [row for row in batches if row.get("batchNumber") == same_lot]
        same_sources = {row.get("supplierId") for row in same_rows}
        self.record("D2-05", "same batch number remains separate by supplier", {s1, s2}.issubset(same_sources), f"distinct source suppliers={len(same_sources)}")
        self.record("D2-05", "supplier-scoped inventory rows use distinct internal lot keys",
                    len({row.get("stockBatchKey") for row in same_rows if row.get("stockBatchKey")}) >= 2,
                    f"internal lot keys={len({row.get('stockBatchKey') for row in same_rows if row.get('stockBatchKey')})}")

        self.verify_product_edit_keeps_lot_dates(lot_a, dates[0], lot_b, dates[1])

        # Invalid plans must fail before producing new stock-in data.
        valid_item = {
            "productId": "fresh_p1_product_x", "expectedQuantity": 1,
            "batchNumber": f"D2BAD-{self.suffix}",
            "productionDate": (self.today - dt.timedelta(days=1)).isoformat(),
            "expiryDate": (self.today + dt.timedelta(days=3)).isoformat(),
        }
        for invalid_quantity in (0, -1, 1.5):
            item = dict(valid_item, expectedQuantity=invalid_quantity)
            body = {"orderType": "PURCHASE_IN", "ownerId": "fresh_p1_owner", "warehouseId": "fresh_p1_wh_w1",
                    "supplierId": s1, "wmsStockInOrderItemsList": [item]}
            self.call("D2-03", "POST", "/inorder/wmsStockInOrders/add", body, expect_success=False)
        for changes in ({"supplierId": None}, {"batchNumber": ""}, {"productionDate": None}, {"expiryDate": None}):
            item = dict(valid_item, batchNumber=f"D2MISS-{self.suffix}")
            body = {"orderType": "PURCHASE_IN", "ownerId": "fresh_p1_owner", "warehouseId": "fresh_p1_wh_w1",
                    "supplierId": s1, "wmsStockInOrderItemsList": [item]}
            if "supplierId" in changes:
                body.update(changes)
            else:
                item.update(changes)
            self.call("D2-03", "POST", "/inorder/wmsStockInOrders/add", body, expect_success=False)
        for production, expiry in (
            (self.today + dt.timedelta(days=1), self.today + dt.timedelta(days=3)),
            (self.today - dt.timedelta(days=1), self.today),
            (self.today, self.today - dt.timedelta(days=1)),
        ):
            batch = f"D2DATE-{self.suffix}-{production.day}-{expiry.day}"
            if not expiry > production:
                body = {"orderType": "PURCHASE_IN", "ownerId": "fresh_p1_owner", "warehouseId": "fresh_p1_wh_w1",
                        "supplierId": s1, "wmsStockInOrderItemsList": [dict(valid_item, batchNumber=batch,
                            productionDate=production.isoformat(), expiryDate=expiry.isoformat())]}
                self.call("D2-03", "POST", "/inorder/wmsStockInOrders/add", body, expect_success=False)
                continue
            # Date eligibility is checked on receipt, so a plan can persist, but it must not receive stock.
            order_id = self.add_order(s1, [self.item(batch, 1, expiry, production)], case="D2-03")
            self.submit_and_approve(order_id, "D2-03")
            _, tasks = self.create_receive_task(order_id, "D2-03")
            invalid_action = {"id": tasks[0]["id"], "execQuantity": 1, "targetLocationCode": "R1", "requestKey": str(uuid.uuid4())}
            self.call("D2-03", "POST", "/inorder/receiveTasks/addRecords", invalid_action, expect_success=False)

        # Date boundaries 1/3/4 are produced by valid real receipts. Expiry today and legacy source-less stock
        # require the isolated test DB fixture because the receive API correctly rejects expiry <= business day.
        for days in (1, 3, 4):
            expiry = self.today + dt.timedelta(days=days)
            order_id = self.add_order(s1, [self.item(f"D2EDGE{days}-{self.suffix}", 1, expiry)], case="D2-04")
            self.submit_and_approve(order_id, "D2-04")
            self.receive_and_putaway(order_id, 1, case="D2-04")
        edge_rows = self.get_list("D2-04", "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")
        for days, status in ((1, "NEAR_EXPIRY"), (3, "NEAR_EXPIRY"), (4, "NORMAL")):
            lot = f"D2EDGE{days}-{self.suffix}"
            row = next((item for item in edge_rows if item.get("batchNumber") == lot), {})
            self.record("D2-04", f"remaining days {days} classifies as {status}", row.get("expiryStatus") == status,
                        f"batch found={bool(row)}, status={row.get('expiryStatus')}")

        expired_fixture = next((row for row in edge_rows if str(row.get("batchNumber", "")).startswith("D2-DB-EXPIRED-")), {})
        pending_fixture = next((row for row in edge_rows if str(row.get("batchNumber", "")).startswith("D2-DB-HISTORY-")), {})
        self.record("D2-04", "database boundary fixture with expiry today is EXPIRED",
                    expired_fixture.get("expiryStatus") == "EXPIRED" and int(expired_fixture.get("eligibleQuantity") or 0) == 0,
                    f"status={expired_fixture.get('expiryStatus')}, eligible={expired_fixture.get('eligibleQuantity')}")
        self.record("D2-04", "legacy source-less fixture is pending verification and not eligible",
                    pending_fixture.get("expiryStatus") == "PENDING_VERIFICATION" and int(pending_fixture.get("eligibleQuantity") or 0) == 0,
                    f"status={pending_fixture.get('expiryStatus')}, eligible={pending_fixture.get('eligibleQuantity')}")

        self.verify_supplier_reference_guard(s1)

        self.write_evidence()
        return self.failures == 0

    def verify_product_edit_keeps_lot_dates(self, lot_a, expiry_a, lot_b, expiry_b):
        original = self.call("D2-04", "GET", "/goods/wmsProducts/queryById?id=fresh_p1_product_x").get("result")
        if not isinstance(original, dict):
            raise ProbeError("Could not read the seeded product before checking batch date immutability.")
        changed = dict(original)
        changed["shelfLife"] = int(original.get("shelfLife") or 7) + 1
        try:
            self.call("D2-04", "POST", "/goods/wmsProducts/edit", changed)
            rows = self.get_list("D2-04", "/inventory/wmsInventory/list?pageNo=1&pageSize=200&productCode=FRESH-X")
            expected = {lot_a: expiry_a.isoformat(), lot_b: expiry_b.isoformat()}
            observed = {}
            for row in rows:
                batch = row.get("batchNumber")
                if batch in expected:
                    observed[batch] = str(row.get("expiryDate") or "")[:10]
            self.record("D2-04", "editing product shelf life leaves persisted lot expiry dates unchanged",
                        observed == expected, f"dates={observed}")
        finally:
            self.call("D2-04", "POST", "/goods/wmsProducts/edit", original)

    def verify_supplier_reference_guard(self, base_supplier_id):
        supplier_code = f"D2REF-{self.suffix}"
        created = self.call("D2-05", "POST", "/fresh/suppliers/add", {
            "supplierCode": supplier_code,
            "supplierName": "D2引用保护探针供应商",
            "contactName": "probe",
            "contactPhone": "13800000000",
            "status": "ACTIVE",
            "remark": "D2 HTTP probe reference check",
        })
        supplier = created.get("result")
        if not isinstance(supplier, dict) or not supplier.get("id"):
            raise ProbeError("Supplier API did not return the created supplier ID.")
        order_id = self.add_order(base_supplier_id, [self.item(f"D2REF-{self.suffix}", 1, self.today + dt.timedelta(days=5))], case="D2-05")
        # The referenced supplier is a temporary, isolated-test fixture. Point the order at it through edit.
        order = self.call("D2-05", "GET", "/inorder/wmsStockInOrders/queryById?" + urllib.parse.urlencode({"id": order_id})).get("result")
        order["supplierId"] = supplier["id"]
        details = self.call("D2-05", "GET", "/inorder/wmsStockInOrders/queryWmsStockInOrderItemsByMainId?" + urllib.parse.urlencode({"id": order_id})).get("result")
        order["wmsStockInOrderItemsList"] = details
        self.call("D2-05", "POST", "/inorder/wmsStockInOrders/edit", order)
        status, payload = self.api.request("DELETE", "/fresh/suppliers/delete?" + urllib.parse.urlencode({"id": supplier["id"]}))
        success = payload.get("success") is True if isinstance(payload, dict) else False
        message = payload.get("message", "") if isinstance(payload, dict) else ""
        self.record("D2-05", "supplier referenced by an inbound order cannot be deleted",
                    status < 500 and not success and "引用" in message,
                    f"HTTP {status}, success={success}, message={message}")

    def write_evidence(self):
        # Never persist access tokens or passwords, even if an endpoint echoes a submitted value.
        scrubbed = []
        secrets = (self.token,)

        def redact(value):
            if isinstance(value, dict):
                return {key: ("[redacted]" if key.lower() in {"token", "password", "access_token"} else redact(child))
                        for key, child in value.items()}
            if isinstance(value, list):
                return [redact(child) for child in value]
            if isinstance(value, str):
                for secret in secrets:
                    if secret:
                        value = value.replace(secret, "[redacted]")
            return value

        for call in self.api.calls:
            scrubbed.append(redact(call))
        (self.evidence / "http-exchanges.json").write_text(json.dumps(scrubbed, ensure_ascii=False, indent=2), encoding="utf-8")
        (self.evidence / "assertions.json").write_text(json.dumps(self.assertions, ensure_ascii=False, indent=2), encoding="utf-8")
        with (self.evidence / "assertions.tsv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=("case", "assertion", "passed", "detail"), delimiter="\t")
            writer.writeheader()
            writer.writerows(self.assertions)
        report = {
            "status": "passed" if self.failures == 0 else "failed",
            "apiRoot": self.api_root,
            "checks": len(self.assertions),
            "passed": len(self.assertions) - self.failures,
            "failed": self.failures,
            "businessDate": self.today.isoformat(),
            "runSuffix": self.suffix,
            "note": "HTTP-only fixture creation. Expiry-today and historical source-less stock require staged isolated-DB fixtures.",
        }
        (self.evidence / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    probe = None
    try:
        probe = Probe()
        passed = probe.run()
        print(f"D2 HTTP probe: {len(probe.assertions) - probe.failures}/{len(probe.assertions)} assertions passed")
        return 0 if passed else 1
    except Exception as exc:
        if probe is not None:
            try:
                probe.write_evidence()
            except Exception:
                pass
        print(f"D2 HTTP probe stopped: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
