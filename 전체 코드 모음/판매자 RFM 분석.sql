-- 재구매율과 배송지연간의 관계-rfm분석 사용
-- seller rfm 테이블 생성
CREATE TABLE RFM_SELLER_LISTS AS (
    SELECT 
        os.seller_id,
        DATEDIFF('2018-10-17', MAX(order_delivered_carrier_date)) AS recency,
        COUNT(DISTINCT csd.order_id) AS frequency,
        SUM(IFNULL(ooi.price, 0)) + SUM(IFNULL(ooi.freight_value, 0)) AS monetary
    FROM olist_sellers_dataset os
    INNER JOIN cleaned_seller_delay csd 
        ON os.seller_id = csd.seller_id
    INNER JOIN olist_order_items_dataset ooi 
        ON ooi.seller_id = os.seller_id
        AND csd.order_id = ooi.order_id -- 주의!!!
    WHERE ooi.order_id IS NOT NULL 
    GROUP BY 1
);

-- 연도별,등급별 지연 매출 비중 
WITH Seller_Monetary_Tier AS (
    -- 판매자별 매출 5등급으로 분류
    SELECT 
        seller_id,
        SUM(IFNULL(price, 0) + IFNULL(freight_value, 0)) AS total_monetary,
        NTILE(5) OVER (ORDER BY SUM(IFNULL(price, 0) + IFNULL(freight_value, 0)) DESC) AS seller_tier
    FROM olist_order_items_dataset
    GROUP BY seller_id
),
Order_Delay_Base AS (
    -- 연도, 매출, 지연 여부(1/0) 생성
    SELECT 
        ooi.seller_id,
        YEAR(oo.order_purchase_timestamp) AS sales_year,
        (IFNULL(ooi.price, 0) + IFNULL(ooi.freight_value, 0)) AS item_monetary,
        CASE 
            WHEN DATEDIFF(oo.order_delivered_customer_date, oo.order_estimated_delivery_date) > 0 THEN 1 
            ELSE 0 
        END AS is_delayed
    FROM olist_order_items_dataset ooi
    INNER JOIN olist_orders_dataset oo 
        ON ooi.order_id = oo.order_id
    WHERE oo.order_status = 'delivered' 
      AND oo.order_delivered_customer_date IS NOT NULL
),
Yearly_Tier_Summary AS (
    -- 연도별,등급별 집계
    SELECT 
        o.sales_year,
        st.seller_tier,
        SUM(o.item_monetary) AS tier_total_sales,
        SUM(CASE WHEN o.is_delayed = 1 THEN o.item_monetary ELSE 0 END) AS tier_delayed_sales
    FROM Order_Delay_Base o
    INNER JOIN Seller_Monetary_Tier st 
        ON o.seller_id = st.seller_id
    GROUP BY o.sales_year, st.seller_tier
),
Yearly_Total AS (
    -- 연도별 전체 지연배송의 매출
    SELECT 
        sales_year,
        SUM(tier_total_sales) AS year_total_sales,
        SUM(tier_delayed_sales) AS year_total_delayed_sales
    FROM Yearly_Tier_Summary
    GROUP BY sales_year
)
-- 5. 태블로용 코드
SELECT 
    yts.sales_year,
    yts.seller_tier,
    yts.tier_total_sales,
    yts.tier_delayed_sales,
    yt.year_total_delayed_sales,
    (yts.tier_delayed_sales / NULLIF(yts.tier_total_sales, 0)) AS tier_delay_rate,
    (yts.tier_delayed_sales / NULLIF(yt.year_total_delayed_sales, 0)) AS share_of_total_delay
FROM Yearly_Tier_Summary yts
INNER JOIN Yearly_Total yt 
    ON yts.sales_year = yt.sales_year
ORDER BY yts.sales_year ASC, yts.seller_tier ASC;

-- 전체 판매자 수 확인
SELECT COUNT(DISTINCT seller_id) AS total_seller_cnt
FROM RFM_SELLER_LISTS;

-- NTILE_recency 
WITH NTILE_recency AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY recency) AS recency_segment
    FROM RFM_SELLER_LISTS
)
SELECT recency_segment,
       MIN(recency) AS MIN_recency,
       MAX(recency) AS MAX_recency,
       COUNT(DISTINCT seller_id) AS seller_cnt        
FROM NTILE_recency
GROUP BY 1
ORDER BY 1;

-- NTILE_frequency
WITH NTILE_frequency AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY frequency) AS frequency_segment
    FROM RFM_SELLER_LISTS
)
SELECT frequency_segment,
       MIN(frequency) AS MIN_frequency,
       MAX(frequency) AS MAX_frequency,
       COUNT(DISTINCT seller_id) AS seller_cnt        
FROM NTILE_frequency
GROUP BY 1
ORDER BY 1;
    
-- Frequency별 실제 판매자 분포
SELECT frequency,
       COUNT(DISTINCT seller_id) AS seller_cnt
FROM RFM_SELLER_LISTS
GROUP BY 1
ORDER BY 1;    

-- NTILE_monetary
WITH NTILE_monetary AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY monetary) AS monetary_segment
    FROM RFM_SELLER_LISTS
)
SELECT monetary_segment,
       MIN(monetary) AS MIN_monetary, 
       MAX(monetary) AS MAX_monetary,
       COUNT(DISTINCT seller_id) AS seller_cnt
FROM NTILE_monetary
GROUP BY 1
ORDER BY 1;
    
-- R분석
WITH Seller_Recency_Tier AS (
    SELECT 
        seller_id, 
        recency,
        NTILE(10) OVER (ORDER BY recency ASC) AS rec_segment 
    FROM RFM_SELLER_LISTS
),
Delay_Summary AS (
    SELECT 
        seller_id,
        AVG(sellerdelay) AS avg_delay
    FROM cleaned_seller_delay
    GROUP BY seller_id
)
SELECT 
    r.rec_segment AS '등급(1=최근 활동)',
    COUNT(DISTINCT r.seller_id) AS '판매자 수',
    ROUND(AVG(r.recency), 1) AS '평균 미판매(일)',
    ROUND(AVG(d.avg_delay), 1) AS '과거 평균 배송 지연(일)'
FROM Seller_Recency_Tier r
INNER JOIN Delay_Summary d 
    ON r.seller_id = d.seller_id
GROUP BY r.rec_segment
ORDER BY r.rec_segment ASC;    
    
-- F분석    
WITH Seller_Freq_Tier AS (
    SELECT 
        seller_id, 
        frequency,
        NTILE(10) OVER (ORDER BY frequency DESC) AS freq_segment 
    FROM RFM_SELLER_LISTS
),
Delay_Summary AS (
    SELECT 
        seller_id,
        AVG(sellerdelay) AS avg_delay
    FROM cleaned_seller_delay
    GROUP BY seller_id
)
SELECT 
    f.freq_segment AS '판매 건수 등급 (1=최다)',
    COUNT(DISTINCT f.seller_id) AS '판매자 수',
    ROUND(AVG(f.frequency), 1) AS '평균 판매 건수',
    ROUND(AVG(d.avg_delay), 1) AS '평균 배송 지연(일)'
FROM Seller_Freq_Tier f
INNER JOIN Delay_Summary d 
    ON f.seller_id = d.seller_id
GROUP BY f.freq_segment
ORDER BY f.freq_segment ASC;
    
-- m 분석
-- 판매자별 매출 등급
WITH Seller_Monetary_Tier AS (
    SELECT 
        seller_id,
        monetary,
        NTILE(10) OVER (ORDER BY monetary DESC) AS monetary_segment 
    FROM RFM_SELLER_LISTS
),
-- 판매자별 평균 지연,지연 건수
Seller_Delay_Summary AS (
    SELECT 
        seller_id,
        COUNT(order_id) AS total_orders,
        AVG(sellerdelay) AS avg_delay,
        -- 5일 이상 지연된 건을 심각으로
        SUM(CASE WHEN sellerdelay >= 5 THEN 1 ELSE 0 END) AS severe_delay_orders
    FROM cleaned_seller_delay
    GROUP BY seller_id
)
-- 매출 등급,지연 데이터
SELECT 
    sm.monetary_segment AS '매출 등급 (1이 최상위)',
    COUNT(DISTINCT sm.seller_id) AS '판매자 수',
    ROUND(AVG(sm.monetary), 1) AS '등급별 평균 매출',
    ROUND(AVG(sd.avg_delay), 1) AS '평균 지연 일수',
    ROUND(SUM(sd.severe_delay_orders) * 100.0 / SUM(sd.total_orders), 1) AS '심각한 지연 발생률(%)'
FROM Seller_Monetary_Tier sm
INNER JOIN Seller_Delay_Summary sd 
    ON sm.seller_id = sd.seller_id
GROUP BY sm.monetary_segment
ORDER BY sm.monetary_segment ASC;    

-- 매출비중 높고 delay심한 seller탐지하기
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

-- rfm분석과 코호트
WITH Seller_Cohort AS (
    -- 판매자별 입점 시작월 구하기
    SELECT 
        seller_id,
        DATE_FORMAT(MIN(order_delivered_carrier_date), '%Y-%m-01') AS cohort_month
    FROM cleaned_seller_delay
    GROUP BY seller_id
),
Seller_Stats AS (
    -- RFM 테이블에 입점월 정보 합치기
    SELECT 
        r.seller_id,
        r.frequency,
        c.cohort_month
    FROM RFM_SELLER_LISTS r
    INNER JOIN Seller_Cohort c 
        ON r.seller_id = c.seller_id
),
Relative_F_Tier AS (
    -- 같은 입점월 안에서 판매 건수 5등분(NTILE)
    SELECT 
        seller_id,
        cohort_month,
        frequency,
        NTILE(5) OVER (PARTITION BY cohort_month ORDER BY frequency DESC) AS cohort_f_tier
    FROM Seller_Stats
),
Seller_Delay AS (
    -- 판매자별 전체 평균 지연 일수
    SELECT 
        seller_id,
        AVG(sellerdelay) AS avg_delay
    FROM cleaned_seller_delay
    GROUP BY seller_id
)
-- F 등급별 평균 배송 지연 일수
SELECT 
    r.cohort_f_tier AS '동기 내 판매 빈도 등급 (1=동기 중 최상위)',
    COUNT(r.seller_id) AS '해당 등급 판매자 수',
    ROUND(AVG(r.frequency), 1) AS '등급별 평균 누적 판매(건)',
    ROUND(AVG(d.avg_delay), 2) AS '평균 배송 지연(일)'
FROM Relative_F_Tier r
INNER JOIN Seller_Delay d 
    ON r.seller_id = d.seller_id
GROUP BY r.cohort_f_tier
ORDER BY r.cohort_f_tier ASC;    

-- 최종 rfm 분석
WITH Seller_Cohort AS (
    -- 판매자들의 데뷔월 구하기
    SELECT 
        seller_id,
        DATE_FORMAT(MIN(order_delivered_carrier_date), '%Y-%m-01') AS cohort_month
    FROM cleaned_seller_delay
    GROUP BY seller_id
),
Seller_RFM_Base AS (
    -- 기존 RFM 테이블에 데뷔 월 정보
    SELECT 
        r.seller_id,
        r.recency,
        r.frequency,
        r.monetary,
        c.cohort_month
    FROM RFM_SELLER_LISTS r
    INNER JOIN Seller_Cohort c 
        ON r.seller_id = c.seller_id
),
Relative_Tiers AS (
    SELECT 
        seller_id,
        NTILE(5) OVER (PARTITION BY cohort_month ORDER BY recency ASC) AS r_tier,      -- R은 작을수록 1등급
        NTILE(5) OVER (PARTITION BY cohort_month ORDER BY frequency DESC) AS f_tier,   -- F는 클수록 1등급
        NTILE(5) OVER (PARTITION BY cohort_month ORDER BY monetary DESC) AS m_tier      -- M은 클수록 1등급
    FROM Seller_RFM_Base
),
Seller_Delay AS (
    -- 판매자별 평균 배송 지연 일수 계산
    SELECT 
        seller_id,
        AVG(sellerdelay) AS avg_delay
    FROM cleaned_seller_delay
    GROUP BY seller_id
),
Tier_Base AS (
    SELECT 
        t.seller_id, t.r_tier, t.f_tier, t.m_tier, d.avg_delay
    FROM Relative_Tiers t
    LEFT JOIN Seller_Delay d 
        ON t.seller_id = d.seller_id
)
SELECT 
    n.tier AS 'seller RFM등급 (1=최우수)',
    (SELECT ROUND(AVG(avg_delay), 2) FROM Tier_Base WHERE r_tier = n.tier) AS '최근성(R) 기준 평균지연(일)',
    (SELECT ROUND(AVG(avg_delay), 2) FROM Tier_Base WHERE f_tier = n.tier) AS '빈도(F) 기준 평균지연(일)',
    (SELECT ROUND(AVG(avg_delay), 2) FROM Tier_Base WHERE m_tier = n.tier) AS '매출(M) 기준 평균지연(일)'
FROM (
    SELECT 1 AS tier UNION ALL 
    SELECT 2 UNION ALL 
    SELECT 3 UNION ALL 
    SELECT 4 UNION ALL 
    SELECT 5
) n
ORDER BY n.tier ASC;

-- 전체 배송지연에서 배송지연 높은 판매자들이 매출에 미치는 영향
WITH RFM_SELLER_DELAY_LISTS AS (
    SELECT 
        csd.seller_id, 
        AVG(sellerdelay) AS sellerdelay, 
        AVG(monetary) AS monetary
    FROM (
        SELECT DISTINCT seller_id, sellerdelay
        FROM cleaned_seller_delay
        WHERE sellerdelay > 0 
          AND sellerdelay <= 20
    ) csd
    INNER JOIN RFM_SELLER_LISTS rsl 
        ON rsl.seller_id = csd.seller_id 
    GROUP BY 1
),
NTILE_sellerdelay AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY sellerdelay) AS sellerdelay_segment
    FROM RFM_SELLER_DELAY_LISTS
)
SELECT sellerdelay_segment,
       MIN(sellerdelay) AS min_sellerdelay,
       MAX(sellerdelay) AS max_sellerdelay,
       COUNT(DISTINCT seller_id) AS seller_cnt,
       SUM(monetary) AS SUM_monetary,
       CONCAT(ROUND((SUM(monetary) * 100.0) / SUM(SUM(monetary)) OVER (), 1), '%') AS monetary_pct
FROM NTILE_sellerdelay
GROUP BY 1;