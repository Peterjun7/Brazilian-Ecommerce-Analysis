-- 판매자 지연일 구하기
SELECT DISTINCT 
    OO.order_id,
    OO.order_delivered_carrier_date,
    OOI.shipping_limit_date, 
    DATEDIFF(OO.order_delivered_carrier_date, OOI.shipping_limit_date) AS sellerdelay
FROM olist_orders_dataset OO
INNER JOIN olist_order_items_dataset OOI 
    ON OO.order_id = OOI.order_id
WHERE YEAR(OO.order_delivered_carrier_date) > 0 
  AND YEAR(OOI.shipping_limit_date) > 0;

-- 조인해서 order_id 하나에 중복발생 확인
WITH DISTINCT_TEST AS (
    -- 기존 DISTINCT 쿼리
    SELECT DISTINCT 
        OO.order_id,
        OO.order_delivered_carrier_date,
        OOI.shipping_limit_date, 
        DATEDIFF(OO.order_delivered_carrier_date, OOI.shipping_limit_date) AS sellerdelay
    FROM olist_orders_dataset OO
    INNER JOIN olist_order_items_dataset OOI 
        ON OO.order_id = OOI.order_id
    WHERE YEAR(OO.order_delivered_carrier_date) > 0 
      AND YEAR(OOI.shipping_limit_date) > 0
)
SELECT 
    order_id, 
    COUNT(*) AS row_count
FROM DISTINCT_TEST
GROUP BY order_id
HAVING COUNT(*) > 1  
ORDER BY row_count DESC;


-- 위 결과에서 나온 중복 order_id 중 하나입력, 여러 시간 발생
SELECT 
    OO.order_id,
    OO.order_delivered_carrier_date,
    OOI.shipping_limit_date 
FROM olist_orders_dataset OO
INNER JOIN olist_order_items_dataset OOI 
    ON OO.order_id = OOI.order_id
WHERE OO.order_id = '0a77b770428bccbea7f9dbf8aec5d6ae';


-- 여러개의 시간 한개로 통일 및 데이터 마트 생성
CREATE TABLE cleaned_seller_delay AS
SELECT 
    OO.order_id,
    OOI.seller_id, -- 나중에 도시 정보랑 연결하려면 seller_id가 꼭 필요
    MAX(OO.order_delivered_carrier_date) AS order_delivered_carrier_date,
    MAX(OOI.shipping_limit_date) AS shipping_limit_date, 
    DATEDIFF(MAX(OO.order_delivered_carrier_date), MAX(OOI.shipping_limit_date)) AS sellerdelay
FROM olist_orders_dataset OO
INNER JOIN olist_order_items_dataset OOI 
    ON OO.order_id = OOI.order_id
WHERE YEAR(OO.order_delivered_carrier_date) > 0 
  AND YEAR(OOI.shipping_limit_date) > 0
GROUP BY 
    OO.order_id, 
    OOI.seller_id;
    
-- 배송지연과 평점간의 연관성->평점이 높을수록 delay시간이 짧다
SELECT review_score, AVG(sellerdelay)
FROM cleaned_seller_delay csd
INNER JOIN olist_order_reviews_dataset oor 
    ON csd.order_id = oor.order_id
WHERE csd.sellerdelay > 0 
  AND csd.sellerdelay <= 20
GROUP BY review_score
ORDER BY review_score DESC;

-- sellerdelay가 177일인 이상치 발생
SELECT 
    sellerdelay, 
    COUNT(*) AS order_count
FROM cleaned_seller_delay
GROUP BY sellerdelay
ORDER BY sellerdelay DESC;