--------------------------------------------------------------------------------
--
--   FileName:         temp_reader.vhd
--   Description:      Temperature reader state machine for ADT7420 sensor
--                     Reading temperature registers via I2C
--
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

--================================================================================
-- 实体定义: temp_reader
-- 功能: 通过I2C总线读取ADT7420温度传感器的温度值
--       传感器地址: 0x4B (1001011)
--       寄存器0: 温度MSB
--       寄存器1: 温度LSB
--================================================================================
ENTITY temp_reader IS
  PORT(
    clk             : IN     STD_LOGIC;                      -- 系统时钟
    rst             : IN     STD_LOGIC;                      -- 复位信号
    trig            : IN     STD_LOGIC;                      -- 触发信号，启动温度读取
    busy            : OUT    STD_LOGIC;                      -- 忙标志，'1'表示正在读取温度

    -- I2C Master接口信号
    i2c_ena         : OUT    STD_LOGIC;                      -- I2C使能信号
    i2c_addr        : OUT    STD_LOGIC_VECTOR(6 DOWNTO 0);   -- I2C从设备地址
    i2c_rw          : OUT    STD_LOGIC;                      -- I2C读写控制: '0'=写, '1'=读
    i2c_data_wr     : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0);   -- I2C写数据
    i2c_busy        : IN     STD_LOGIC;                      -- I2C忙标志
    i2c_data_rd     : IN     STD_LOGIC_VECTOR(7 DOWNTO 0);   -- I2C读数据
    i2c_ack_error   : IN     STD_LOGIC;                      -- I2C应答错误

    -- 温度输出
    temp_data       : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0)   -- 16位温度数据 (13位有效)
  );
END temp_reader;

ARCHITECTURE behavior OF temp_reader IS

  -- 常量定义
  CONSTANT SENSOR_ADDR    : STD_LOGIC_VECTOR(6 DOWNTO 0) := "1001011";  -- ADT7420地址 0x4B
  CONSTANT TEMP_REG_ADDR  : STD_LOGIC_VECTOR(7 DOWNTO 0) := "00000000";  -- 温度寄存器地址 0x00

  -- 状态机类型定义 (按照PDF第2页标准命名)
  TYPE state_type IS (
    ready,                    -- 准备状态，等待触发信号
    start,                    -- 开始状态
    write_register_address,   -- 写寄存器地址状态
    read_busy_1,              -- 等待第一次读取完成
    read_temp_MSB,            -- 读取温度MSB（寄存器0）
    read_busy_2,              -- 等待第二次读取完成
    read_temp_LSB,            -- 读取温度LSB（寄存器1）
    wait_state                -- 等待状态，完成读取
  );

  SIGNAL state              : state_type;                    -- 当前状态
  SIGNAL temp_msb           : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- 温度高字节
  SIGNAL temp_lsb           : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- 温度低字节
  SIGNAL busy_prev          : STD_LOGIC;                     -- 上一个时钟周期的i2c_busy

BEGIN

  --================================================================================
  -- 进程: 温度读取状态机
  -- 功能: 控制I2C传输，实现温度寄存器的读取
  --       1. 写入寄存器地址0
  --       2. 读取寄存器0 (MSB)
  --       3. 读取寄存器1 (LSB)
  --================================================================================
  PROCESS(clk, rst)
  BEGIN
    IF rst = '1' THEN
      -- 复位所有信号
      state <= ready;
      busy <= '0';
      i2c_ena <= '0';
      i2c_addr <= (OTHERS => '0');
      i2c_rw <= '0';
      i2c_data_wr <= (OTHERS => '0');
      temp_msb <= (OTHERS => '0');
      temp_lsb <= (OTHERS => '0');
      temp_data <= (OTHERS => '0');
      busy_prev <= '0';

    ELSIF rising_edge(clk) THEN
      -- 保存上一个i2c_busy状态，用于检测下降沿
      busy_prev <= i2c_busy;

      CASE state IS

        -- ====================================================================
        -- ready状态: 等待触发信号
        -- ====================================================================
        WHEN ready =>
          busy <= '0';
          i2c_ena <= '0';
          IF trig = '1' THEN
            state <= start;
            busy <= '1';
          END IF;

        -- ====================================================================
        -- start状态: 准备开始I2C传输
        -- ====================================================================
        WHEN start =>
          busy <= '1';
          i2c_addr <= SENSOR_ADDR;
          state <= write_register_address;

        -- ====================================================================
        -- write_register_address状态: 写入温度寄存器地址
        -- ====================================================================
        WHEN write_register_address =>
          i2c_ena <= '1';
          i2c_rw <= '0';                      -- 写操作
          i2c_data_wr <= TEMP_REG_ADDR;       -- 寄存器地址0x00
          state <= read_busy_1;

        -- ====================================================================
        -- read_busy_1状态: 等待写寄存器地址完成
        -- ====================================================================
        WHEN read_busy_1 =>
          IF i2c_busy = '0' AND busy_prev = '1' THEN   -- 检测i2c_busy下降沿
            state <= read_temp_MSB;
          END IF;

        -- ====================================================================
        -- read_temp_MSB状态: 读取温度MSB
        -- ====================================================================
        WHEN read_temp_MSB =>
          i2c_ena <= '1';
          i2c_rw <= '1';                      -- 读操作
          i2c_addr <= SENSOR_ADDR;
          state <= read_busy_2;

        -- ====================================================================
        -- read_busy_2状态: 等待MSB读取完成，并保存数据
        -- ====================================================================
        WHEN read_busy_2 =>
          IF i2c_busy = '0' AND busy_prev = '1' THEN   -- 检测i2c_busy下降沿
            temp_msb <= i2c_data_rd;          -- 保存MSB
            state <= read_temp_LSB;
          END IF;

        -- ====================================================================
        -- read_temp_LSB状态: 读取温度LSB
        -- ====================================================================
        WHEN read_temp_LSB =>
          i2c_ena <= '1';
          i2c_rw <= '1';                      -- 读操作
          i2c_addr <= SENSOR_ADDR;
          state <= wait_state;

        -- ====================================================================
        -- wait_state状态: 等待LSB读取完成，保存数据，返回ready
        -- ====================================================================
        WHEN wait_state =>
          IF i2c_busy = '0' AND busy_prev = '1' THEN   -- 检测i2c_busy下降沿
            temp_lsb <= i2c_data_rd;          -- 保存LSB
            temp_data <= temp_msb & i2c_data_rd;  -- 组合成16位数据
            i2c_ena <= '0';                   -- 停止I2C传输
            state <= ready;
          END IF;

        WHEN OTHERS =>
          state <= ready;

      END CASE;
    END IF;
  END PROCESS;

END behavior;
