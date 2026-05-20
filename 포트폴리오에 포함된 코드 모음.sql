-- 01-1.배송이 지연된 주문의 매출 비중이 증가하고 있는 문제
-- 01-1.지연된 주문의 매출비중, 주문수 그래프
SELECT 
    YEAR(o.order_purchase_timestamp) AS order_year,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(i.price+i.freight_value) AS total_revenue,
    SUM(CASE 
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
        THEN i.price 
        ELSE 0 
    END) AS delayed_revenue,
    ROUND(
        (SUM(CASE 
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
            THEN i.price 
            ELSE 0 
        END) / SUM(i.price+i.freight_value)) * 100, 
    2) AS delayed_revenue_ratio_pct
FROM olist_orders_dataset o
JOIN olist_order_items_dataset i 
    ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
GROUP BY YEAR(o.order_purchase_timestamp)
ORDER BY order_year;

-- 01-1. Urgent Seller관련 코드
WITH Ranked_Sellers AS (
    SELECT 
        seller_id,
        recency,
        monetary,
        frequency,
        NTILE(10) OVER (ORDER BY monetary DESC) AS m_tier -- 상위 10%가 1등급
    FROM RFM_SELLER_LISTS
),
Delay_Sellers AS (
    SELECT 
        seller_id,
        ROUND(AVG(sellerdelay), 1) AS avg_seller_delay,
        MAX(sellerdelay) AS max_seller_delay
    FROM cleaned_seller_delay
    GROUP BY seller_id
)
SELECT 
    r.seller_id AS '판매자 ID',
    r.recency AS '최근 판매 후 경과시점(일)',
    r.monetary AS '총 매출',
    r.frequency AS '총 판매 건수',
    d.avg_seller_delay AS '평균 지연(일)',
    d.max_seller_delay AS '최대 지연(일)',
    r.m_tier AS '매출 등급'
FROM Ranked_Sellers r
INNER JOIN Delay_Sellers d 
    ON r.seller_id = d.seller_id
ORDER BY d.avg_seller_delay DESC;    

-- 01-2. 도시별 배송 지연 주체(판매자/택배사) 추적 부재
-- 도시와 위도경도 연결
SELECT geolocation_city, MAX(geolocation_lat) AS max_lat, MAX(geolocation_lng) AS max_lng
FROM olist_geolocation_dataset
GROUP BY geolocation_city;

-- 택배사(Carrier) 지연 기준 쿼리
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

-- 판매자(Seller) 지연 기준 쿼리
SELECT 
    CASE 
        -- 1단계: 복합어(도시/주) 및 구체적인 도시 먼저 필터링
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'ribeirao preto%' OR TRIM(LOWER(OS.seller_city)) LIKE 'riberao%' THEN 'ribeirao preto'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'santo andre%' OR TRIM(LOWER(OS.seller_city)) = 'sando andre' THEN 'santo andre'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'carapicuiba%' THEN 'carapicuiba'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%bernardo do ca%' THEN 'sao bernardo do campo'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%rio de janeiro%' THEN 'rio de janeiro'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'santa barbara d%' THEN 'santa barbara d''oeste'
        WHEN TRIM(LOWER(OS.seller_city)) = 'garulhos' THEN 'guarulhos'
        WHEN TRIM(LOWER(OS.seller_city)) = 'portoferreira' THEN 'porto ferreira'
        WHEN TRIM(LOWER(OS.seller_city)) LIKE '%jose do rio pret%' THEN 'sao jose do rio preto'
        
        -- 2단계: 남은 것들 중 상파울루 관련 데이터 싹 다 묶기
        WHEN TRIM(LOWER(OS.seller_city)) LIKE 'sao paulo%' 
          OR TRIM(LOWER(OS.seller_city)) = 'sao paluo'  
          OR TRIM(LOWER(OS.seller_city)) IN ('sp', 'sp / sp') THEN 'sao paulo'
        
        -- 3단계: 나머지 정상 도시
        ELSE TRIM(LOWER(OS.seller_city))
    END AS cleaned_seller_city,
    AVG(CSD.sellerdelay) AS avg_delay_days,
    COUNT(CSD.order_id) AS order_count
FROM cleaned_seller_delay CSD
INNER JOIN olist_sellers_dataset OS ON CSD.seller_id = OS.seller_id
WHERE CSD.sellerdelay > 0 
  AND CSD.sellerdelay <= 59  
  AND OS.seller_city NOT LIKE '%@%' -- 이메일 차단
GROUP BY cleaned_seller_city
HAVING COUNT(CSD.order_id) >= 10  -- 통계적 유의성 확보
ORDER BY avg_delay_days DESC;


-- 01-3. 판매자의 배송 지연 시간 비중에 따른 타켓팅 솔루션 부재
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


-- 01-4. 빠른 배송 판매자 식별 및 우대 기능 부재
WITH Seller_Consistency AS (
    SELECT 
        seller_id,
        -- 물건을 판 달의 개수
        COUNT(DISTINCT DATE_FORMAT(order_delivered_carrier_date, '%Y-%m')) AS active_months_count,
        AVG(sellerdelay) AS avg_seller_delay
    FROM cleaned_seller_delay
    GROUP BY seller_id
),
Consistency_Groups AS (
    SELECT 
        seller_id,
        active_months_count,
        avg_seller_delay,
        CASE 
            WHEN active_months_count = 1 THEN '단발성 (1개월 활동)'
            WHEN active_months_count BETWEEN 2 AND 3 THEN '초기 이탈 (2~3개월 활동)'
            WHEN active_months_count BETWEEN 4 AND 6 THEN '단기 정착 (4~6개월 활동)'
            WHEN active_months_count BETWEEN 7 AND 12 THEN '중기 정착 (7~12개월 활동)'
            ELSE '장기 우수 (13개월 이상 활동)'
        END AS consistency_group
    FROM Seller_Consistency
)
-- 3. 그룹별 평균 지연 일수 집계 및 비교
SELECT 
    consistency_group AS '활동기간',
    COUNT(seller_id) AS '판매자 수',
    ROUND(AVG(active_months_count), 1) AS '평균 활동(월)',
    ROUND(AVG(avg_seller_delay), 2) AS '배송 지연(일)'
FROM Consistency_Groups
GROUP BY consistency_group
ORDER BY consistency_group ASC;


-- 01-5. 신규 입점 판매자의 배송 지연 리스크 방치 및 제재 기준 미비
WITH First_Month_Orders AS (
    -- 판매자별 최초 입점
    SELECT 
        seller_id,
        DATE_FORMAT(MIN(order_delivered_carrier_date), '%Y-%m-01') AS cohort_month
    FROM cleaned_seller_delay
    GROUP BY seller_id
),
First_Month_Delay AS (
    -- 첫달 배송들의 평균 지연일 수
    SELECT 
        f.seller_id,
        AVG(c.sellerdelay) AS first_month_avg_delay
    FROM First_Month_Orders f
    INNER JOIN cleaned_seller_delay c 
        ON f.seller_id = c.seller_id 
        AND DATE_FORMAT(c.order_delivered_carrier_date, '%Y-%m-01') = f.cohort_month
    GROUP BY f.seller_id
),
Split_Equal_Cohorts AS (
    -- 첫달 지연일 기준으로 두집단으로분리
    SELECT 
        seller_id,
        first_month_avg_delay,
        NTILE(2) OVER (ORDER BY first_month_avg_delay ASC) AS delay_group
    FROM First_Month_Delay
),
Cohort_Labels AS (
    SELECT 
        seller_id,
        CASE 
            WHEN delay_group = 1 THEN '첫 달 배송 우수 집단'
            ELSE '첫 달 배송 지연 심각 집단' 
        END AS cohort_type
    FROM Split_Equal_Cohorts
),
Seller_Activity AS (
    SELECT DISTINCT 
        seller_id,
        DATE_FORMAT(order_delivered_carrier_date, '%Y-%m-01') AS activity_month
    FROM cleaned_seller_delay
),
Cohort_Base AS (
    -- 6. 활동 내역과 그룹 정보를 매핑하여 경과 월수(Month N) 계산
    SELECT 
        l.cohort_type,
        a.activity_month,
        l.seller_id,
        PERIOD_DIFF(
            EXTRACT(YEAR_MONTH FROM a.activity_month), 
            EXTRACT(YEAR_MONTH FROM (SELECT cohort_month FROM First_Month_Orders WHERE seller_id = l.seller_id))
        ) AS month_number
    FROM Cohort_Labels l
    INNER JOIN Seller_Activity a 
        ON l.seller_id = a.seller_id
),
Cohort_Size AS (
    SELECT 
        cohort_type,
        COUNT(DISTINCT seller_id) AS total_cohort_size
    FROM Cohort_Labels
    GROUP BY cohort_type
)
-- 두 그룹 유지율 비교
SELECT 
    b.cohort_type AS '코호트 그룹',
    s.total_cohort_size AS '초기 전체 판매자 수',
    b.month_number AS '경과 월수(Month)',
    COUNT(DISTINCT b.seller_id) AS '활동 판매자 수',
    ROUND(COUNT(DISTINCT b.seller_id) * 100.0 / s.total_cohort_size, 1) AS '유지율(%)'
FROM Cohort_Base b
INNER JOIN Cohort_Size s 
    ON b.cohort_type = s.cohort_type
GROUP BY b.cohort_type, s.total_cohort_size, b.month_number
ORDER BY b.cohort_type ASC, b.month_number ASC;    


