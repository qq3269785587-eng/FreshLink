package org.jeecg.modules.wms.fresh.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import jakarta.annotation.Resource;

@Configuration
public class FreshWebMvcConfiguration implements WebMvcConfigurer {

    @Resource
    private FreshStoreAccessInterceptor freshStoreAccessInterceptor;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(freshStoreAccessInterceptor)
                .addPathPatterns("/**")
                .excludePathPatterns("/error");
    }
}
