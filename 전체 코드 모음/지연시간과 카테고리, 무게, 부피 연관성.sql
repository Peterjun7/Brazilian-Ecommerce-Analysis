-- 상품 카테고리 및 사이즈에 따른 지연분석
-- 배송지연이 심한 도시들은 상품의 무게,부피가 증가함에 따라 배송지연이 가파르게 상승할것이다. 
CREATE TABLE product_delay AS
SELECT 
    ooi.order_id, 
    ooi.seller_id,

    -- 모든 상품의 무게합
    SUM(op.product_weight_g) AS total_weight_g,
    
    -- 모든 상품의 부피합
    SUM(op.product_width_cm * op.product_height_cm * op.product_length_cm) AS total_volume_cm3,
    
    -- 카테고리는 1개만 가져오기
    MAX(op.product_category_name) AS representative_category,
    
    -- 주문안에있는 상품개수
    COUNT(ooi.product_id) AS total_item_count

FROM olist_order_items_dataset ooi
INNER JOIN olist_products_dataset op 
    ON ooi.product_id = op.product_id
GROUP BY ooi.order_id, ooi.seller_id;

SELECT pd.order_id, pd.seller_id, total_weight_g, total_volume_cm3, representative_category, total_item_count, sellerdelay, carrierdelay
FROM product_delay pd
INNER JOIN cleaned_seller_delay csd 
    ON csd.order_id = pd.order_id
    AND csd.seller_id = pd.seller_id
INNER JOIN cleaned_carrier_delay ccd 
    ON ccd.order_id = pd.order_id
    AND ccd.seller_id = pd.seller_id
WHERE 0 <= sellerdelay AND sellerdelay <= 20
  AND 0 <= carrierdelay AND carrierdelay <= 20;

WITH RankedData AS (
    SELECT 
        pd.order_id,
        pd.seller_id,
        pd.total_weight_g,
        pd.total_volume_cm3,
        pd.representative_category,
        pd.total_item_count,
        csd.sellerdelay,
        ccd.carrierdelay,
        csd.sellerdelay + ccd.carrierdelay AS total_delay,
        PERCENT_RANK() OVER (ORDER BY csd.sellerdelay + ccd.carrierdelay ASC) AS delay_percentile
    FROM product_delay pd
    INNER JOIN cleaned_seller_delay csd 
        ON csd.order_id = pd.order_id AND csd.seller_id = pd.seller_id
    INNER JOIN cleaned_carrier_delay ccd 
        ON ccd.order_id = pd.order_id AND ccd.seller_id = pd.seller_id
    WHERE csd.sellerdelay >= 0 AND csd.sellerdelay <= 20
      AND ccd.carrierdelay >= 0 AND ccd.carrierdelay <= 20
)
SELECT 
    order_id,
    seller_id,
    total_weight_g,
    total_volume_cm3,
    representative_category,
    total_item_count,
    sellerdelay,
    carrierdelay,
    total_delay,
    ROUND(delay_percentile * 100) AS delay_percentile
FROM RankedData
-- WHERE delay_percentile>=0.7
-- WHERE 없애서 전체도 출력
WHERE delay_percentile <= 0.3;



WITH RankedData AS (
    SELECT 
        pd.order_id,
        pd.seller_id,
        pd.total_weight_g,
        pd.total_volume_cm3,
        pd.representative_category,
        pd.total_item_count,
        csd.sellerdelay,
        ccd.carrierdelay,
        (csd.sellerdelay + ccd.carrierdelay) AS total_delay,
        PERCENT_RANK() OVER (ORDER BY csd.sellerdelay + ccd.carrierdelay ASC) AS delay_percentile
    FROM product_delay pd
    INNER JOIN cleaned_seller_delay csd 
        ON csd.order_id = pd.order_id AND csd.seller_id = pd.seller_id
    INNER JOIN cleaned_carrier_delay ccd 
        ON ccd.order_id = pd.order_id AND ccd.seller_id = pd.seller_id
    -- WHERE (csd.sellerdelay + ccd.carrierdelay) >= -32 
    --   AND (csd.sellerdelay + ccd.carrierdelay) <= 8
)
SELECT 
    order_id,
    seller_id,
    total_weight_g,
    total_volume_cm3,
    representative_category,
    total_item_count,
    sellerdelay,
    carrierdelay,
    total_delay,
    ROUND(delay_percentile * 100) AS delay_percentile
FROM RankedData;

-- delay발생한 건 중 sellerdelay의 비중이 증가함에 따라 무게 부피가 어떻게 변하는지 분석
WITH ValidDelays AS (
    SELECT 
        pd.order_id,
        pd.total_weight_g,
        pd.total_volume_cm3,
        csd.sellerdelay,
        ccd.carrierdelay,
        (csd.sellerdelay + ccd.carrierdelay) AS total_delay,
        -- 전체 지연에서 판매자가 차지하는 비중 
        (csd.sellerdelay / (csd.sellerdelay + ccd.carrierdelay)) AS seller_ratio
    FROM product_delay pd
    INNER JOIN cleaned_seller_delay csd 
        ON csd.order_id = pd.order_id AND csd.seller_id = pd.seller_id
    INNER JOIN cleaned_carrier_delay ccd 
        ON ccd.order_id = pd.order_id AND ccd.seller_id = pd.seller_id
    WHERE (csd.sellerdelay + ccd.carrierdelay) > 0 
      AND csd.sellerdelay >= -58 AND csd.sellerdelay <= 59
      AND ccd.carrierdelay >= -76 AND ccd.carrierdelay <= 173
    -- and csd.sellerdelay > 0 and ccd.carrierdelay > 0 ->해당 조건을 추가했을시 표본이 줄어들어 경향성이 잘 나타나지 않는다
),
RankedByRatio AS (
    -- 판매자 지연비중이 높은 순으로 출력
    SELECT *,
           NTILE(10) OVER (ORDER BY seller_ratio DESC) AS ratio_group
    FROM ValidDelays
)
-- 그룹별 평균 무게와 부피 변화 확인
SELECT 
    ratio_group AS '그룹',
    CONCAT(ROUND(MIN(seller_ratio) * 100, 1), '% ~ ', ROUND(MAX(seller_ratio) * 100, 1), '%') AS '판매자 지연 비중 구간',
    ROUND(AVG(seller_ratio) * 100, 1) AS '판매자 지연 비중 평균(%)',
    COUNT(order_id) AS '주문 건수',
    ROUND(AVG(total_weight_g), 1) AS '평균 무게(g)',
    ROUND(AVG(total_volume_cm3), 1) AS '평균 부피(cm3)'
FROM RankedByRatio
GROUP BY ratio_group
ORDER BY ratio_group ASC;

WITH ValidDelays AS (
    SELECT 
        pd.order_id,
        csd.sellerdelay,
        ccd.carrierdelay,
        (csd.sellerdelay + ccd.carrierdelay) AS total_delay,
        (csd.sellerdelay / (csd.sellerdelay + ccd.carrierdelay)) AS seller_ratio
    FROM product_delay pd
    INNER JOIN cleaned_seller_delay csd 
        ON csd.order_id = pd.order_id AND csd.seller_id = pd.seller_id
    INNER JOIN cleaned_carrier_delay ccd 
        ON ccd.order_id = pd.order_id AND ccd.seller_id = pd.seller_id
    WHERE (csd.sellerdelay + ccd.carrierdelay) > 0 
      AND csd.sellerdelay >= -58 AND csd.sellerdelay <= 59
      AND ccd.carrierdelay >= -76 AND ccd.carrierdelay <= 173
)

-- 극단적으로 높은 비율 상위 5건 확인, 판매자 지연 비중이 3100%의 경우 판매자 지연일이 31일, 택배사 지연일이 -30이였음
(
    SELECT 
        'Top 극단치(+)' AS '구분',
        order_id,
        sellerdelay AS '판매자 지연일',
        carrierdelay AS '택배사 지연일(조기배송)',
        total_delay AS '전체 지연일(분모)',
        ROUND(seller_ratio * 100, 1) AS '판매자 지연 비중(%)'
    FROM ValidDelays
    ORDER BY seller_ratio DESC
    LIMIT 5
)
UNION ALL
-- 극단적으로 낮은 비율 하위 5건 확인
(
    SELECT 
        'Bottom 극단치(-)' AS '구분',
        order_id,
        sellerdelay AS '판매자 지연일(조기출고)',
        carrierdelay AS '택배사 지연일',
        total_delay AS '전체 지연일(분모)',
        ROUND(seller_ratio * 100, 1) AS '판매자 지연 비중(%)'
    FROM ValidDelays
    ORDER BY seller_ratio ASC
    LIMIT 5
);

-- 그룹별 많이 팔린 카테고리 확인, 많이 팔린 카테고리로 인해 뚜렷한 경향이 나타나지 않음
WITH ValidDelays AS (
    SELECT 
        pd.order_id,
        pd.representative_category,
        csd.sellerdelay,
        ccd.carrierdelay,
        (GREATEST(csd.sellerdelay, 0) / (GREATEST(csd.sellerdelay, 0) + GREATEST(ccd.carrierdelay, 0))) AS seller_ratio
    FROM product_delay pd
    INNER JOIN cleaned_seller_delay csd 
        ON csd.order_id = pd.order_id AND csd.seller_id = pd.seller_id
    INNER JOIN cleaned_carrier_delay ccd 
        ON ccd.order_id = pd.order_id AND ccd.seller_id = pd.seller_id
    WHERE (csd.sellerdelay + ccd.carrierdelay) > 0
),
RankedByRatio AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY seller_ratio DESC) AS ratio_group
    FROM ValidDelays
),
CategoryCounts AS (
    SELECT 
        ratio_group,
        representative_category,
        COUNT(order_id) AS cnt,
        ROW_NUMBER() OVER (PARTITION BY ratio_group ORDER BY COUNT(order_id) DESC) AS rnk
    FROM RankedByRatio
    GROUP BY ratio_group, representative_category
)
SELECT 
    ratio_group AS '그룹(1=판매자 책임 최대)',
    MAX(CASE WHEN rnk = 1 THEN CONCAT(representative_category, ' (', cnt, '건)') END) AS '1위 카테고리',
    MAX(CASE WHEN rnk = 2 THEN CONCAT(representative_category, ' (', cnt, '건)') END) AS '2위 카테고리',
    MAX(CASE WHEN rnk = 3 THEN CONCAT(representative_category, ' (', cnt, '건)') END) AS '3위 카테고리'
FROM CategoryCounts
GROUP BY ratio_group
ORDER BY ratio_group ASC;

WITH ValidDelays AS (
    -- 1단계: 마이너스 지연을 0으로 보정하고 데이터 추출
    SELECT 
        pd.order_id,
        pd.representative_category,
        csd.sellerdelay AS safe_sellerdelay,
        ccd.carrierdelay AS safe_carrierdelay
    FROM product_delay pd
    INNER JOIN cleaned_seller_delay csd 
        ON csd.order_id = pd.order_id AND csd.seller_id = pd.seller_id
    INNER JOIN cleaned_carrier_delay ccd 
        ON ccd.order_id = pd.order_id AND ccd.seller_id = pd.seller_id
    -- 실제 총 지연이 발생한 건만 필터링, 이상값 처리
    WHERE (csd.sellerdelay + ccd.carrierdelay) > 0 
      AND csd.sellerdelay >= -58 AND csd.sellerdelay <= 59
      AND ccd.carrierdelay >= -76 AND ccd.carrierdelay <= 173
)
-- 카테고리별로 묶어서 비중과 평균을 계산
SELECT 
    representative_category AS '카테고리',
    COUNT(order_id) AS '지연 발생 총 건수',
    ROUND(AVG(safe_sellerdelay), 1) AS '평균 판매자 지연(일)',
    ROUND(AVG(safe_carrierdelay), 1) AS '평균 택배사 지연(일)',
    -- 카테고리별 평균 판매자 지연일 비중
    CONCAT(ROUND(AVG(safe_sellerdelay / (safe_sellerdelay + safe_carrierdelay)) * 100, 1), '%') AS '판매자 지연일 비중(%)'
FROM ValidDelays
GROUP BY representative_category
-- 통계적 의미를 위해 100건 이상 지연된 카테고리만 출력
HAVING COUNT(order_id) >= 100
ORDER BY AVG(safe_sellerdelay / (safe_sellerdelay + safe_carrierdelay)) DESC;