package org.jeecg.modules.iot.base.config;

import com.influxdb.client.InfluxDBClient;
import com.influxdb.client.InfluxDBClientFactory;
import lombok.Data;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * @author muht
 * @create 2025/5/7 14:12
 */
@Configuration
@Data
public class InfluxdbConfig {
    @Value("${influx.url:http://127.0.0.1:8086}")
    private String url;
    @Value("${influx.token:}")
    private String token;
    @Value("${influx.bucket:}")
    private String bucket;
    @Value("${influx.org:}")
    private String org;

    @Bean
    @org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(prefix = "iot", name = "timeseries-enabled", havingValue = "true")
    public InfluxDBClient influxDBClient() {
        InfluxDBClient client = InfluxDBClientFactory.create(url, token.toCharArray(), org, bucket);

        return client;
    }
}
