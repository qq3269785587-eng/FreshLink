package org.jeecg.modules.wms.fresh.outbound;

import org.jeecg.common.api.vo.Result;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/fresh/outbounds")
public class FreshOutboundController {
    private final FreshOutboundService service;

    public FreshOutboundController(FreshOutboundService service) {
        this.service = service;
    }

    @GetMapping
    public Result<FreshOutboundService.OutboundPage> list(
            @RequestParam(defaultValue = "1") int pageNo,
            @RequestParam(defaultValue = "10") int pageSize,
            @RequestParam(required = false) String storeId,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String stockBatchKey) {
        return Result.OK(service.list(pageNo, pageSize, storeId, status, stockBatchKey));
    }

    @GetMapping("/{id}")
    public Result<FreshOutboundService.OutboundDetail> detail(@PathVariable String id) {
        return Result.OK(service.detail(id));
    }

    @PostMapping
    public Result<FreshOutboundService.OutboundDetail> create(@RequestBody FreshOutboundService.DraftRequest request) {
        return Result.OK(service.createDraft(request));
    }

    @PutMapping("/{id}")
    public Result<FreshOutboundService.OutboundDetail> edit(
            @PathVariable String id, @RequestBody FreshOutboundService.DraftRequest request) {
        return Result.OK(service.editDraft(id, request));
    }

    @DeleteMapping("/{id}")
    public Result<String> delete(@PathVariable String id) {
        service.deleteDraft(id);
        return Result.OK("草稿已删除");
    }

    @PostMapping("/{id}/confirm")
    public Result<FreshOutboundService.OutboundDetail> confirm(@PathVariable String id) {
        return Result.OK(service.confirm(id));
    }
}
