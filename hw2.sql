CREATE DATABASE ecommerce02;
USE ecommerce02;
-- 1. Bảng customers (Khách hàng)
CREATE TABLE customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Bảng orders (Đơn hàng)
CREATE TABLE orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) DEFAULT 0,
    status ENUM('Pending', 'Completed', 'Cancelled') DEFAULT 'Pending',
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- 3. Bảng products (Sản phẩm)
CREATE TABLE products (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Bảng order_items (Chi tiết đơn hàng)
CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- 5. Bảng inventory (Kho hàng)
CREATE TABLE inventory (
    product_id INT PRIMARY KEY,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
);

-- 6. Bảng payments (Thanh toán)
CREATE TABLE payments (
    payment_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10,2) NOT NULL,
    payment_method ENUM('Credit Card', 'PayPal', 'Bank Transfer', 'Cash') NOT NULL,
    status ENUM('Pending', 'Completed', 'Failed') DEFAULT 'Pending',
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);

-- Stored Procedure sp_create_order:
DELIMITER $$
CREATE PROCEDURE sp_create_order(inCustomer_id INT, inProduct_id INT, inQuantity INT, inPrice DEC(10,2))
BEGIN
	DECLARE new_order_id INT;
    
	declare exit handler for sqlexception
    BEGIN
        ROLLBACK;
        SELECT 'Giao dịch lỗi, đã rollback' AS message;
    END;
    
    -- Kiểm tra số lượng tồn kho. Nếu không đủ, ROLLBACK và thông báo lỗi.
    START TRANSACTION;
    IF (SELECT stock_quantity FROM inventory WHERE product_id = inProduct_id) < inQuantity THEN
    signal sqlstate '45000' SET message_text = 'Không đủ số lượng tồn kho';
    END IF;
    
    -- Thêm một đơn hàng mới vào bảng orders.
    INSERT INTO orders(customer_id, order_date, total_amount, status) 
    VALUES(inCustomer_id, NOW(), inQuantity * inPrice, 'Pending');
    
    -- Lấy order_id vừa tạo bằng LAST_INSERT_ID().
	SET new_order_id = LAST_INSERT_ID();
    
    -- Thêm sản phẩm vào bảng order_items.
    INSERT INTO order_items(order_id, product_id, quantity, price)
    VALUES(new_order_id, inProduct_id, inQuantity, inPrice);
    
    -- Cập nhật (giảm) số lượng tồn kho trong bảng inventory.
    UPDATE inventory 
    SET stock_quantity = stock_quantity - inQuantity 
    WHERE product_id = inProduct_id;
    
    COMMIT;
END $$
DELIMITER ;

-- Stored Procedure sp_pay_order:
DELIMITER $$
CREATE PROCEDURE sp_pay_order(inOrder_Id INT, inPayment_Method ENUM('Credit Card','PayPal','Bank Transfer','Cash'))
BEGIN
	DECLARE checkStatus VARCHAR(20);
    DECLARE totalAmount DECIMAL(10,2);
    
	declare exit handler for sqlexception
    BEGIN
		ROLLBACK;
        SELECT 'Thanh toán thất bại! Đã ROLLBACK' AS message;
	END ;
    
    SELECT status, total_amount  
    INTO  checkStatus, totalAmount
    FROM orders 
    WHERE order_id = inOrder_Id;
    
    START TRANSACTION;
    -- Kiểm tra trạng thái đơn hàng. Nếu không phải 'Pending', ROLLBACK và thông báo lỗi.
    IF checkStatus <> 'Pending' THEN
    signal sqlstate '45000' SET message_text = 'Đơn hàng đã xử lý';
    END IF;
    
    -- Thêm bản ghi thanh toán vào bảng payments.
    INSERT INTO payments(order_id, amount, payment_method)
    VALUES (inOrder_Id, totalAmount, inPayment_Method);
    
    -- Cập nhật trạng thái đơn hàng trong bảng orders thành 'Completed'.
    UPDATE orders SET status = 'Completed' WHERE order_id = inOrder_Id;
    COMMIT;
END $$	
DELIMITER ;

-- Stored Procedure sp_cancel_order:
DELIMITER $$
CREATE PROCEDURE sp_cancel_order (inOrder_Id INT)
BEGIN
	declare checkQuantity INT;
    declare checkProduct_id INT;
    
	declare exit handler for sqlexception
    BEGIN
		ROLLBACK;
        SELECT 'Giao dịch đã bị hủy' AS message;
	END;
    
    -- cập nhật biến checkQuantity
    SELECT SUM(quantity), product_id 
    INTO checkQuantity, checkProduct_id
    FROM order_items 
    WHERE order_id = inOrder_Id;
    
    START TRANSACTION;
    IF (SELECT status FROM orders WHERE order_id = inOrder_Id) <> 'Pending' THEN
    signal sqlstate '45000' SET message_text = 'Đơn hàng đã xử lý';
    END IF;
    
    -- Hoàn trả số lượng hàng vào kho bằng cách cập nhật bảng inventory.
    UPDATE inventory SET stock_quantity = stock_quantity + checkQuantity WHERE product_id = checkProduct_id;
    
    -- Xóa các sản phẩm liên quan khỏi bảng order_items.
    DELETE FROM order_items WHERE order_id = inOrder_Id;
    
    -- Cập nhật trạng thái đơn hàng trong bảng orders thành 'Cancelled'.
    UPDATE orders SET status = 'Cancelled' WHERE order_id = inOrder_Id;
    COMMIT;
END $$
DELIMITER ;

-- Sử dụng lệnh DROP PROCEDURE để xóa tất cả các Stored Procedure đã tạo.
DROP PROCEDURE sp_cancel_order;
DROP PROCEDURE sp_create_order;
DROP PROCEDURE sp_pay_order;