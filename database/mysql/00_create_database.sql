-- Local development database. Run before migrations; never drops an existing schema.
-- Requires MySQL >= 8.0.16 (CHECK constraints must be enforced).
CREATE DATABASE IF NOT EXISTS aiworkforce_ecommerce
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE aiworkforce_ecommerce;
SET NAMES utf8mb4;
SET SESSION time_zone = '+00:00';
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
