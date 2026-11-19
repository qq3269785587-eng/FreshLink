package org.jeecg.modules.wms.fresh.delivery;

import com.baomidou.mybatisplus.core.metadata.IPage;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.jeecg.common.api.vo.Result;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.entity.FreshStore;
import org.springframework.web.bind.annotation.*;

import jakarta.annotation.Resource;

@Tag(name = "生鲜配送")
@RestController
@RequestMapping("/fresh/deliveries")
public class FreshDeliveryController {
    @Resource
    private FreshDeliveryService deliveryService;

    @Resource
    private FreshAccessService accessService;

    @Operation(summary = "配送单分页列表")
    @GetMapping
    public Result<IPage<FreshDelivery>> list(@RequestParam(name = "pageNo", defaultValue = "1") Integer pageNo,
                                             @RequestParam(name = "pageSize", defaultValue = "10") Integer pageSize) {
        return Result.OK(deliveryService.page(pageNo, pageSize, storeScope()));
    }

    @Operation(summary = "配送单详情及出库批次")
    @GetMapping("/{id}")
    public Result<FreshDelivery> detail(@PathVariable String id) {
        return Result.OK(deliveryService.detail(id, storeScope()));
    }

    @Operation(summary = "填写配送员资料")
    @PutMapping("/{id}/dispatch-info")
    public Result<FreshDelivery> dispatchInfo(@PathVariable String id, @RequestBody FreshDeliveryDispatchInfo info) {
        accessService.requireStaff();
        return Result.OK(deliveryService.updateDispatchInfo(id, info));
    }

    @Operation(summary = "开始配送")
    @PostMapping("/{id}/start")
    public Result<FreshDelivery> start(@PathVariable String id) {
        accessService.requireStaff();
        return Result.OK(deliveryService.start(id));
    }

    @Operation(summary = "确认送达")
    @PostMapping("/{id}/deliver")
    public Result<FreshDelivery> deliver(@PathVariable String id) {
        accessService.requireStaff();
        return Result.OK(deliveryService.deliver(id));
    }

    private String storeScope() {
        if (accessService.isStoreUser()) {
            FreshStore bound = accessService.boundStore();
            if (bound == null) {
                throw new JeecgBootException("当前账号未绑定门店");
            }
            return bound.getId();
        }
        accessService.requireStaff();
        return null;
    }
}
