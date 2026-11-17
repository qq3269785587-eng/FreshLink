package org.jeecg.modules.wms.goods.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.service.IService;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.common.util.RedisUtil;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.jeecg.modules.wms.goods.entity.*;
import org.jeecg.modules.wms.goods.excel.WmsProductsImport;
import org.jeecg.modules.wms.goods.mapper.WmsProductsMapper;
import org.jeecg.modules.wms.goods.service.*;
import org.springframework.beans.BeanUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * @Description: 商品信息表
 * @Author: jeecg-boot
 * @Date:   2025-04-14
 * @Version: V1.0
 */
@Service
public class WmsProductsServiceImpl extends ServiceImpl<WmsProductsMapper, WmsProducts> implements IWmsProductsService {

    @Autowired
    private RedisUtil redisUtil;

    @Autowired
    private IWmsCargoOwnersService wmsCargoOwnersService;

    @Autowired
    private IWmsProductCategoriesService wmsProductCategoriesService;

    @Autowired
    private IWmsProductImagesService wmsProductImagesService;
    @Autowired
    private IWmsProductBrandService wmsProductBrandService;
    @Transactional(rollbackFor = Exception.class)
    @Override
    public void add(WmsProducts wmsProducts) {
        normalizeFreshProduct(wmsProducts, true, null);
        //校验货主加商品编码在商品表的唯一性
        if(checkProductCode(wmsProducts)){
            throw new RuntimeException("货主加商品编码在商品表中已存在");
        }
        //生成商品条码
        wmsProducts.setProductBarcode(generateProductBarcode(wmsProducts));
        //保存商品
        save(wmsProducts);
//        String productImgs= wmsProducts.getProductImgs();
//        if(productImgs!=null){
//            //图片
//            String[] productImgArr = productImgs.split(",");
//            for (String productImg : productImgArr) {
//                WmsProductImages wmsProductImages = new WmsProductImages();
//                wmsProductImages.setProductId(wmsProducts.getId());
//                wmsProductImages.setOriginal(productImg);
//                wmsProductImagesService.save(wmsProductImages);
//            }
//        }
    }

    /**
     * 校验货主加商品编码在商品表的唯一性
     * @param wmsProducts
     * @return 不存在返回false，存在返回true
     */
    public boolean checkProductCode(WmsProducts wmsProducts) {
        String ownerId = wmsProducts.getOwnerId();
        String productCode = wmsProducts.getProductCode();
        //根据货主和商品编码查询
        List<WmsProducts> wmsProductsList = baseMapper.selectList(lambdaQuery().getWrapper()
                .eq(WmsProducts::getOwnerId,ownerId)
                .eq(WmsProducts::getProductCode,productCode));
        return wmsProductsList.size()>0;

    }

    /** Uniqueness check that excludes the record being edited. */
    public boolean checkProductCodeExcludingId(WmsProducts wmsProducts) {
        return baseMapper.selectCount(lambdaQuery().getWrapper()
                .eq(WmsProducts::getOwnerId, wmsProducts.getOwnerId())
                .eq(WmsProducts::getProductCode, wmsProducts.getProductCode())
                .ne(WmsProducts::getId, wmsProducts.getId())) > 0;
    }

    private boolean equalsNullable(String left, String right) {
        return left == null ? right == null : left.equals(right);
    }

    /**
     * Fresh master-data rules. Creation requires the full fresh contract; editing a legacy row
     * keeps its missing fields but cannot silently clear fields that are already maintained.
     */
    private void normalizeFreshProduct(WmsProducts product, boolean create, WmsProducts existing) {
        if (product == null) {
            throw new JeecgBootException("食材信息不能为空");
        }
        product.setProductName(FreshValidation.text(product.getProductName(), "食材名称", 100));
        product.setProductCode(FreshValidation.code(product.getProductCode(), "食材编码"));
        if (product.getOwnerId() == null || product.getOwnerId().trim().isEmpty()) {
            throw new JeecgBootException("货主不能为空");
        }
        if (wmsCargoOwnersService.getById(product.getOwnerId()) == null) {
            throw new JeecgBootException("货主不存在");
        }
        if (product.getCategoryId() == null || product.getCategoryId().trim().isEmpty()) {
            product.setCategoryId("0");
        }
        product.setStatus(FreshValidation.status(product.getStatus()));
        product.setProductSpec(FreshValidation.text(product.getProductSpec(), "规格描述", 64));
        product.setUnit(FreshValidation.text(product.getUnit(), "计数单位", 32));
        if (product.getIsExpiryControlled() == null) {
            product.setIsExpiryControlled(1);
        }
        if (create) {
            product.setProductSpec(FreshValidation.text(product.getProductSpec(), "规格描述", 64));
            product.setUnit(FreshValidation.text(product.getUnit(), "计数单位", 32));
            product.setStorageType(FreshValidation.storageType(product.getStorageType(), true));
            product.setNearExpiryDays(FreshValidation.nearExpiryDays(product.getNearExpiryDays()));
            if (product.getShelfLife() != null) {
                product.setShelfLife(FreshValidation.positiveDays(product.getShelfLife(), "保质期天数"));
            }
            return;
        }
        boolean touchingFreshFields = product.getStorageType() != null || product.getNearExpiryDays() != null;
        if (existing != null && existing.getStorageType() != null
                && (product.getStorageType() == null || product.getStorageType().trim().isEmpty())) {
            throw new JeecgBootException("温区不能为空");
        }
        if (existing != null && existing.getNearExpiryDays() != null && product.getNearExpiryDays() == null) {
            throw new JeecgBootException("临期阈值天数不能为空");
        }
        if (touchingFreshFields) {
            if (product.getStorageType() != null && !product.getStorageType().trim().isEmpty()) {
                product.setStorageType(FreshValidation.storageType(product.getStorageType(), true));
            }
            if (product.getNearExpiryDays() != null) {
                product.setNearExpiryDays(FreshValidation.nearExpiryDays(product.getNearExpiryDays()));
            }
        }
        if (product.getShelfLife() != null) {
            product.setShelfLife(FreshValidation.positiveDays(product.getShelfLife(), "保质期天数"));
        }
    }

    @Transactional(rollbackFor = Exception.class)
    @Override
    public void edit(WmsProducts wmsProducts) {
        String id = wmsProducts.getId();
        WmsProducts wmsProductsOld = getById(id);
        if (wmsProductsOld == null) {
            throw new RuntimeException("商品不存在或已被删除");
        }
        normalizeFreshProduct(wmsProducts, false, wmsProductsOld);
        //如果编码或货主有变化，才校验新的组合唯一性（排除自身）
        boolean codeChanged = !equalsNullable(wmsProductsOld.getProductCode(), wmsProducts.getProductCode());
        boolean ownerChanged = !equalsNullable(wmsProductsOld.getOwnerId(), wmsProducts.getOwnerId());
        if (codeChanged || ownerChanged) {
            if (checkProductCodeExcludingId(wmsProducts)) {
                throw new RuntimeException("货主加商品编码在商品表中已存在");
            }
        }
        //如果商品条码为空则生成商品条码
        if (wmsProducts.getProductBarcode() == null || wmsProducts.getProductBarcode().isEmpty()) {
            wmsProducts.setProductBarcode(generateProductBarcode(wmsProducts));
        }
        updateById(wmsProducts);
        //如果商品图片有变化
//        String productImgsOld = wmsProductsOld.getProductImgs()==null?"":wmsProductsOld.getProductImgs();
//        String productImgsNew = wmsProducts.getProductImgs()==null?"":wmsProducts.getProductImgs();
//        if(!productImgsOld.equals(productImgsNew)){
//            LambdaQueryWrapper<WmsProductImages> queryWrapper = new LambdaQueryWrapper<WmsProductImages>().eq(WmsProductImages::getProductId, id);
//            wmsProductImagesService.remove(queryWrapper);
//            if(productImgsNew!=null){
//                //图片
//                String[] productImgArr = productImgsNew.split(",");
//                for (String productImg : productImgArr) {
//                    WmsProductImages wmsProductImages = new WmsProductImages();
//                    wmsProductImages.setProductId(wmsProducts.getId());
//                    wmsProductImages.setOriginal(productImg);
//                    wmsProductImagesService.save(wmsProductImages);
//                }
//            }
//        }
    }


    /**
     * 生成商品条码全局唯一
     * @return
     */
    public String generateProductBarcode(WmsProducts wmsProducts) {
        //编码规则：6位货主编码+4位商品类别+6位序号
        //货主编码
        String ownerCode = wmsCargoOwnersService.getById(wmsProducts.getOwnerId()).getOwnerCode();
        //商品类型编码
        String categoryCode = wmsProductCategoriesService.getById(wmsProducts.getCategoryId()).getCategoryCode();

        String code = null;
        try {
            code = String.format("%06d", redisUtil.incr("WMS_PRO_BARCODE", 1));
        } catch (Exception e) {
            e.printStackTrace();
        }
        code = ownerCode + categoryCode + code;
        return code;
    }
    /**
     * 导入商品
     * @param wmsProductsImportList
     */
    @Override
    public void importProduct(List<WmsProductsImport> wmsProductsImportList) {
        for (WmsProductsImport wmsProductsImport : wmsProductsImportList){
            WmsProducts products = convertWmsProducts(wmsProductsImport);
            add(products);
        }
    }
    /**
     * 将WmsProductsImport转换为WmsProducts
     * @param wmsProductsImport
     * @return WmsProducts
     */
    private WmsProducts convertWmsProducts(WmsProductsImport wmsProductsImport) {
        WmsProducts wmsProducts = new WmsProducts();
        BeanUtils.copyProperties(wmsProductsImport,wmsProducts);
        //处理名称
        //货主名称
        String ownerName = wmsProductsImport.getOwnerName();
        //根据货主名称查询货主
        LambdaQueryWrapper<WmsCargoOwners> eq = new LambdaQueryWrapper<WmsCargoOwners>()
                .eq(WmsCargoOwners::getOwnerName, ownerName);
        WmsCargoOwners wmsCargoOwners = wmsCargoOwnersService.getOne(eq);
        wmsProducts.setOwnerId(wmsCargoOwners.getId());

        //根据商品分类名称查询分类
        String categoryName = wmsProductsImport.getCategoryName();
        LambdaQueryWrapper<WmsProductCategories> queryWrapper = new LambdaQueryWrapper<WmsProductCategories>()
                .eq(WmsProductCategories::getCategoryName, categoryName);
        WmsProductCategories wmsProductCategories = wmsProductCategoriesService.getOne(queryWrapper);
        wmsProducts.setCategoryId(wmsProductCategories.getId());
        //根据品牌名称查询 品牌
        String brandName = wmsProductsImport.getProductBrandName();
        LambdaQueryWrapper<WmsProductBrand> queryWrapper2 = new LambdaQueryWrapper<WmsProductBrand>()
                .eq(WmsProductBrand::getName, brandName);
        WmsProductBrand wmsProductBrand = wmsProductBrandService.getOne(queryWrapper2);
        wmsProducts.setProductBrand(wmsProductBrand.getId());

        return wmsProducts;
    }

}
