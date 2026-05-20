-- 도시별 평균 seller지연시간(도시이름 데이터 전처리 전)
SELECT 
    OS.seller_city,
    AVG(CSD.sellerdelay) AS avg_delay_days
FROM cleaned_seller_delay CSD
INNER JOIN olist_sellers_dataset OS 
    ON CSD.seller_id = OS.seller_id
WHERE CSD.sellerdelay > 0 
  AND CSD.sellerdelay <= 20
GROUP BY OS.seller_city
ORDER BY avg_delay_days DESC;


-- 핵심분석
SELECT 
    CASE 
        -- 도시이름 전처리
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'ribeirao preto%' OR TRIM(LOWER(OS.seller_city)) LIKE 'riberao%' THEN 'ribeirao preto'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'santo andre%' OR TRIM(LOWER(OS.seller_city)) = 'sando andre' THEN 'santo andre'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'carapicuiba%' THEN 'carapicuiba'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%bernardo do ca%' THEN 'sao bernardo do campo'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%rio de janeiro%' THEN 'rio de janeiro'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'santa barbara d%' THEN 'santa barbara d''oeste'
        WHEN TRIM(LOWER(OS.seller_city)) = 'garulhos' THEN 'guarulhos'
        WHEN TRIM(LOWER(OS.seller_city)) = 'portoferreira' THEN 'porto ferreira'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%jose do rio pret%' THEN 'sao jose do rio preto'
        
        -- 상파울루 관련 이름 묶기
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'sao paulo%' 
          OR TRIM(LOWER(OS.seller_city)) = 'sao paluo'  
          OR TRIM(LOWER(OS.seller_city)) IN ('sp', 'sp / sp') THEN 'sao paulo'
        
        -- 나머지 일반 도시
        ELSE TRIM(LOWER(OS.seller_city))
    END AS cleaned_seller_city,
    
    AVG(CSD.sellerdelay) AS avg_delay_days,
    COUNT(CSD.order_id) AS order_count

FROM cleaned_seller_delay CSD
INNER JOIN olist_sellers_dataset OS 
    ON CSD.seller_id = OS.seller_id
WHERE CSD.sellerdelay > 0 
  AND CSD.sellerdelay <= 59  
  AND OS.seller_city NOT LIKE '%@%' -- 이메일 차단
GROUP BY cleaned_seller_city
HAVING COUNT(CSD.order_id) >= 10  -- 통계적 유의성 확보
ORDER BY avg_delay_days DESC;

--  물류센터의 지연시간 분석
CREATE TABLE cleaned_carrier_delay AS
SELECT 
    OO.order_id,
    OOI.seller_id,
    DATEDIFF(MAX(order_delivered_customer_date), MAX(order_delivered_carrier_date)) - DATEDIFF(MAX(order_estimated_delivery_date), MAX(shipping_limit_date)) AS carrierdelay
FROM olist_orders_dataset OO
INNER JOIN olist_order_items_dataset OOI 
    ON OO.order_id = OOI.order_id
WHERE YEAR(OO.order_delivered_carrier_date) > 0 
  AND YEAR(OOI.shipping_limit_date) > 0
  AND YEAR(order_delivered_customer_date) > 0
  AND YEAR(order_estimated_delivery_date) > 0
GROUP BY 
    OO.order_id, 
    OOI.seller_id;

-- 택배사 지연시간 922 이상값 발생
SELECT carrierdelay,
       COUNT(*) AS order_count
FROM cleaned_carrier_delay
GROUP BY carrierdelay
ORDER BY carrierdelay DESC;

-- 도시별 carrier지연시간
SELECT 
    OS.seller_city,
    AVG(CCD.carrierdelay) AS avg_delay_days
FROM cleaned_carrier_delay CCD
INNER JOIN olist_sellers_dataset OS 
    ON CCD.seller_id = OS.seller_id
WHERE CCD.carrierdelay > 0 
  AND CCD.carrierdelay <= 20  
GROUP BY OS.seller_city
ORDER BY avg_delay_days DESC;


-- 핵심분석
SELECT 
    CASE 
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'ribeirao preto%' OR TRIM(LOWER(OS.seller_city)) LIKE 'riberao%' THEN 'ribeirao preto'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'santo andre%' OR TRIM(LOWER(OS.seller_city)) = 'sando andre' THEN 'santo andre'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'carapicuiba%' THEN 'carapicuiba'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%bernardo do ca%' THEN 'sao bernardo do campo'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%rio de janeiro%' THEN 'rio de janeiro'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'santa barbara d%' THEN 'santa barbara d''oeste'
        WHEN TRIM(LOWER(OS.seller_city)) = 'garulhos' THEN 'guarulhos'
        WHEN TRIM(LOWER(OS.seller_city)) = 'portoferreira' THEN 'porto ferreira'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%jose do rio pret%' THEN 'sao jose do rio preto'
        
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'sao paulo%' 
          OR TRIM(LOWER(OS.seller_city)) = 'sao paluo'  
          OR TRIM(LOWER(OS.seller_city)) IN ('sp', 'sp / sp') THEN 'sao paulo'
        
        ELSE TRIM(LOWER(OS.seller_city))
    END AS cleaned_seller_city,
    AVG(CCD.carrierdelay) AS avg_delay_days,
    COUNT(CCD.order_id) AS order_count

FROM cleaned_carrier_delay CCD
INNER JOIN olist_sellers_dataset OS 
    ON CCD.seller_id = OS.seller_id
WHERE CCD.carrierdelay > 0 
  AND CCD.carrierdelay <= 191
  AND OS.seller_city NOT LIKE '%@%' 
GROUP BY cleaned_seller_city
HAVING COUNT(CCD.order_id) >= 10 
ORDER BY avg_delay_days DESC;

-- 고객분포파악, 같은 zip_code에 다른 위도 경도가 있어서 행수가 급격하게 늘어남
SELECT 
    oc.customer_unique_id, 
    geo.avg_lat AS geolocation_lat, 
    geo.avg_lng AS geolocation_lng
FROM Brazilian.olist_customers_dataset oc
INNER JOIN (
    -- 우편번호별 위도/경도 평균을 먼저 구함
    SELECT 
        geolocation_zip_code_prefix,
        AVG(geolocation_lat) AS avg_lat,
        AVG(geolocation_lng) AS avg_lng
    FROM Brazilian.olist_geolocation_dataset
    GROUP BY geolocation_zip_code_prefix
) geo ON oc.customer_zip_code_prefix = geo.geolocation_zip_code_prefix;

-- seller 분포파악, 같은 zip_code에 다른 위도 경도가 있어서 행수가 급격하게 늘어남
SELECT 
    os.seller_id, 
    os.seller_city, 
    os.seller_state,
    geo.avg_lat AS geolocation_lat, 
    geo.avg_lng AS geolocation_lng
FROM Brazilian.olist_sellers_dataset os
INNER JOIN (
    -- zipcode별 위도/경도 중복을 제거
    SELECT 
        geolocation_zip_code_prefix,
        AVG(geolocation_lat) AS avg_lat,
        AVG(geolocation_lng) AS avg_lng
    FROM Brazilian.olist_geolocation_dataset
    GROUP BY geolocation_zip_code_prefix
) geo ON os.seller_zip_code_prefix = geo.geolocation_zip_code_prefix;

-- 도시와 위도경도 연결
SELECT geolocation_city, MAX(geolocation_lat) AS max_lat, MAX(geolocation_lng) AS max_lng
FROM olist_geolocation_dataset
GROUP BY geolocation_city;