CREATE DATABASE ecommerce;
USE ecommerce;
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

-- //////////////////// Bài 1 ////////////////////
-- Tạo Trigger kiểm tra số lượng tồn kho trước khi thêm sản phẩm vào order_items. Nếu không đủ, báo lỗi SQLSTATE '45000'.
DELIMITER $$
CREATE TRIGGER check_Stock_Quantity_Before_Add_Product
BEFORE INSERT ON order_items FOR EACH ROW
BEGIN
	IF (SELECT stock_quantity FROM inventory WHERE product_id = NEW.product_id) <= NEW.quantity THEN
		signal sqlstate '45000' SET message_text = 'Lượng tồn kho không đủ';
	END IF;
END $$
DELIMITER ;

-- Tạo Trigger cập nhật total_amount trong bảng orders sau khi thêm một sản phẩm mới vào order_items.
DELIMITER $$
CREATE TRIGGER update_total_amount_after_add_product
AFTER INSERT ON order_items FOR EACH ROW
BEGIN
	UPDATE orders o 
    SET o.total_amount = (
		SELECT SUM(oi.quantity * oi.price)
        FROM order_items oi
        WHERE oi.order_id = NEW.order_id
    )
    WHERE o.order_id = NEW.order_id;
END $$
DELIMITER ;

-- Tạo Trigger kiểm tra số lượng tồn kho trước khi cập nhật số lượng sản phẩm trong order_items. Nếu không đủ, báo lỗi SQLSTATE '45000'.
DELIMITER $$
CREATE TRIGGER check_Stock_Quantity_Before_Update_Product
BEFORE UPDATE ON order_items FOR EACH ROW
BEGIN
	IF (SELECT stock_quantity FROM inventory WHERE product_id = NEW.product_id) <= NEW.quantity THEN
		signal sqlstate '45000' SET message_text = 'Lượng tồn kho không đủ';
	END IF;
END $$
DELIMITER ;

-- Tạo Trigger cập nhật lại total_amount trong bảng orders khi số lượng hoặc giá của một sản phẩm trong order_items thay đổi.
DELIMITER $$
CREATE TRIGGER update_total_amount_after_order_item_update
AFTER UPDATE ON order_items FOR EACH ROW
BEGIN
	UPDATE orders o 
    SET o.total_amount = (
		SELECT SUM(oi.quantity * oi.price)
        FROM order_items oi
        WHERE oi.order_id = NEW.order_id
    )
    WHERE o.order_id = NEW.order_id;
END $$
DELIMITER ;

-- Tạo Trigger ngăn chặn việc xóa một đơn hàng có trạng thái Completed trong bảng orders. Nếu cố gắng xóa, báo lỗi SQLSTATE '45000'.
DELIMITER $$
CREATE TRIGGER prevent_delete_completed_order
BEFORE DELETE ON orders FOR EACH ROW
BEGIN
	IF OLD.status = 'Completed' THEN
    signal sqlstate '45000' set message_text = 'Không thể xóa';
    END IF;
END $$
DELIMITER ;

-- Tạo Trigger hoàn trả số lượng sản phẩm vào kho (inventory) sau khi một sản phẩm trong order_items bị xóa.
DELIMITER $$
CREATE TRIGGER update_quantity_after_delete_product_in_order_items
AFTER DELETE ON order_items FOR EACH ROW
BEGIN
	UPDATE inventory 
    SET stock_quantity = stock_quantity  + OLD.quantity
    WHERE product_id = OLD.product_id;
END $$
DELIMITER ;

-- Sử dụng lệnh DROP TRIGGER để xóa tất cả các Trigger đã tạo.
DROP TRIGGER check_Stock_Quantity_Before_Add_Product;
DROP TRIGGER update_total_amount_after_add_product;
DROP TRIGGER check_Stock_Quantity_Before_Update_Product;
DROP TRIGGER update_quantity_after_delete_product_in_order_items;
DROP TRIGGER prevent_delete_completed_order;