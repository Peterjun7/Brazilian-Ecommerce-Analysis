-- 코호트 분석    
WITH Seller_First_Sale AS (
    -- 판매자별 최초 입점
    SELECT 
        seller_id,
        DATE_FORMAT(MIN(order_delivered_carrier_date), '%Y-%m-01') AS cohort_month
    FROM cleaned_seller_delay
    GROUP BY seller_id
),
Seller_Activity AS (
    -- 판매자별 월별 실제 활동 여부
    SELECT DISTINCT
        seller_id,
        DATE_FORMAT((order_delivered_carrier_date), '%Y-%m-01') AS activity_month
    FROM cleaned_seller_delay
),
Cohort_Base AS (
    -- 최초 활동월과 실제 활동월을 결합, 경과 월수 계산
    SELECT 
        f.cohort_month,
        a.activity_month,
        f.seller_id,
        -- 두 날짜 개월수 차이 계산 
        PERIOD_DIFF(EXTRACT(YEAR_MONTH FROM a.activity_month), EXTRACT(YEAR_MONTH FROM f.cohort_month)) AS month_number
    FROM Seller_First_Sale f
    INNER JOIN Seller_Activity a 
        ON f.seller_id = a.seller_id
),
Cohort_Size AS (
    -- 코호트별 초기 진입 판매자 총수
    SELECT 
        cohort_month,
        COUNT(DISTINCT seller_id) AS cohort_size
    FROM Seller_First_Sale
    GROUP BY cohort_month
)
SELECT 
    b.cohort_month AS '코호트 월(최초 활동)',
    s.cohort_size AS '초기 판매자 수',
    b.month_number AS '경과 월수(Month N)',
    COUNT(DISTINCT b.seller_id) AS '활동 판매자 수',
    ROUND(COUNT(DISTINCT b.seller_id) * 100.0 / s.cohort_size, 1) AS '유지율(%)'
FROM Cohort_Base b
INNER JOIN Cohort_Size s 
    ON b.cohort_month = s.cohort_month
GROUP BY b.cohort_month, s.cohort_size, b.month_number
ORDER BY b.cohort_month ASC, b.month_number ASC;    
    
-- 코호트분석 응용    
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

-- LIfecycle segment
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