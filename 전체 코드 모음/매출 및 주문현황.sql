USE Brazilian;

SELECT COUNT(seller_id)
FROM olist_sellers_dataset;

SELECT COUNT(seller_id)
FROM olist_order_items_dataset;

SELECT COUNT(distinct seller_id)
FROM olist_order_items_dataset;

SELECT count(ooi.order_id)
FROM olist_order_items_dataset ooi;
-- 112650개

SELECT count(distinct ooi.order_id)
FROM olist_order_items_dataset ooi;
-- 98666개

SELECT count(oo.order_id)
FROM olist_orders_dataset oo;
-- 99441개

SELECT count(distinct oo.order_id)
FROM olist_orders_dataset oo;
-- 99441개

-- 연도별 주문건수, 매출액, 배송지연으로 인한 매출액 및 지연 매출 비중
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

-- 연도별 지연 매출액과 정상 매출액
WITH Order_Delay_Base AS (
    SELECT 
        ooi.order_id, 
        ooi.monetary, 
        DATEDIFF(oo.order_delivered_customer_date, order_estimated_delivery_date) AS delay,
        YEAR(oo.order_purchase_timestamp) AS sales_year
    FROM (
        SELECT 
            ooi.order_id,
            SUM(IFNULL(ooi.price, 0)) + SUM(IFNULL(ooi.freight_value, 0)) AS monetary
        FROM olist_order_items_dataset ooi
        GROUP BY 1
    ) ooi
    INNER JOIN olist_orders_dataset oo 
        ON ooi.order_id = oo.order_id
    WHERE oo.order_status = 'delivered'
)
SELECT 
    sales_year AS "연도",

    SUM(monetary) AS "전체_매출액",
    
    SUM(CASE WHEN delay > 0 THEN monetary ELSE 0 END) AS "지연_매출액",
    
    SUM(CASE WHEN delay <= 0 THEN monetary ELSE 0 END) AS "정상_매출액",
    
    CONCAT(
        ROUND(
            (SUM(CASE WHEN delay > 0 THEN monetary ELSE 0 END) * 100.0) / SUM(monetary), 
        1), 
    '%') AS "지연_매출_비중",
    
    CONCAT(
        ROUND(
            (SUM(CASE WHEN delay <= 0 THEN monetary ELSE 0 END) * 100.0) / SUM(monetary), 
        1), 
    '%') AS "정상_매출_비중"

FROM Order_Delay_Base
WHERE delay IS NOT NULL 
GROUP BY sales_year
ORDER BY sales_year;