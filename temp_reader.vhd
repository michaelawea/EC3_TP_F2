----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 01.12.2025 15:00:42
-- Design Name:
-- Module Name: temp_reader - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description: Temperature reader for ADT7420 sensor via I2C
--
-- Dependencies: i2c_master
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity temp_reader is
    Port (
        clk         : in  STD_LOGIC;
        rst         : in  STD_LOGIC;
        trig        : in  STD_LOGIC;
        data_rd     : in  STD_LOGIC_VECTOR (7 downto 0);
        i2c_busy    : in  STD_LOGIC;
        i2c_ack     : in  STD_LOGIC;
        busy        : out STD_LOGIC;
        data        : out STD_LOGIC_VECTOR (15 downto 0);
        i2c_ena     : out STD_LOGIC;
        i2c_rw      : out STD_LOGIC;
        i2c_data_wr : out STD_LOGIC_VECTOR (7 downto 0);
        i2c_addr    : out STD_LOGIC_VECTOR (6 downto 0)
    );
end temp_reader;

architecture Behavioral of temp_reader is

    -- 状态机类型定义
    type state_type is (
        idle,               -- 空闲状态，等待触发
        wr_reg_address,     -- 写寄存器地址
        st_busy_1,          -- 等待busy变为'1'
        st_busy_0_1,        -- 等待busy变为'0' (第一次)
        read_temp_MSB,      -- 读取温度MSB
        st_busy_2,          -- 等待busy变为'1' (读MSB)
        st_busy_0_2,        -- 等待busy变为'0' (第二次)
        read_temp_LSB,      -- 读取温度LSB
        st_busy_3,          -- 等待busy变为'1' (读LSB)
        st_busy_0_3         -- 等待busy变为'0' (第三次)
    );

    signal state, next_state : state_type;

    -- 常量定义
    constant SENSOR_ADDR    : STD_LOGIC_VECTOR(6 downto 0) := "1001011";  -- ADT7420地址 0x4B
    constant TEMP_REG_ADDR  : STD_LOGIC_VECTOR(7 downto 0) := "00000000";  -- 温度寄存器地址

    -- 内部寄存器
    signal temp_msb : STD_LOGIC_VECTOR(7 downto 0);
    signal temp_lsb : STD_LOGIC_VECTOR(7 downto 0);

begin

    -- ========================================================================
    -- 进程1: 同步状态寄存器
    -- ========================================================================
    SYNC_PROC: process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= idle;
            else
                state <= next_state;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- 进程2: Moore状态机输出逻辑 (基于当前状态)
    -- ========================================================================
    OUTPUT_DECODE: process (state)
    begin
        -- 默认值
        busy <= '1';
        i2c_ena <= '0';
        i2c_rw <= '0';
        i2c_data_wr <= (others => '0');
        i2c_addr <= SENSOR_ADDR;

        case state is
            when idle =>
                busy <= '0';
                i2c_ena <= '0';

            when wr_reg_address =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '0';
                i2c_data_wr <= TEMP_REG_ADDR;
                i2c_addr <= SENSOR_ADDR;

            when st_busy_1 =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '0';
                i2c_data_wr <= TEMP_REG_ADDR;

            when st_busy_0_1 =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '1';

            when read_temp_MSB =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '1';
                i2c_addr <= SENSOR_ADDR;

            when st_busy_2 =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '1';

            when st_busy_0_2 =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '1';

            when read_temp_LSB =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '1';
                i2c_addr <= SENSOR_ADDR;

            when st_busy_3 =>
                busy <= '1';
                i2c_ena <= '1';
                i2c_rw <= '1';

            when st_busy_0_3 =>
                busy <= '1';
                i2c_ena <= '0';

            when others =>
                busy <= '0';
                i2c_ena <= '0';

        end case;
    end process;

    -- ========================================================================
    -- 进程3: 下一状态逻辑
    -- ========================================================================
    NEXT_STATE_DECODE: process (state, trig, i2c_busy)
    begin
        -- 默认保持当前状态
        next_state <= state;

        case state is
            when idle =>
                if trig = '1' then
                    next_state <= wr_reg_address;
                end if;

            when wr_reg_address =>
                if i2c_busy = '1' then
                    next_state <= st_busy_1;
                end if;

            when st_busy_1 =>
                if i2c_busy = '0' then
                    next_state <= st_busy_0_1;
                end if;

            when st_busy_0_1 =>
                next_state <= read_temp_MSB;

            when read_temp_MSB =>
                if i2c_busy = '1' then
                    next_state <= st_busy_2;
                end if;

            when st_busy_2 =>
                if i2c_busy = '0' then
                    next_state <= st_busy_0_2;
                end if;

            when st_busy_0_2 =>
                next_state <= read_temp_LSB;

            when read_temp_LSB =>
                if i2c_busy = '1' then
                    next_state <= st_busy_3;
                end if;

            when st_busy_3 =>
                if i2c_busy = '0' then
                    next_state <= st_busy_0_3;
                end if;

            when st_busy_0_3 =>
                next_state <= idle;

            when others =>
                next_state <= idle;

        end case;
    end process;

    -- ========================================================================
    -- 进程4: 数据寄存器
    -- ========================================================================
    DATA_REG: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                temp_msb <= (others => '0');
                temp_lsb <= (others => '0');
                data <= (others => '0');
            else
                case state is
                    when st_busy_0_2 =>
                        temp_msb <= data_rd;  -- 保存MSB

                    when st_busy_0_3 =>
                        temp_lsb <= data_rd;  -- 保存LSB
                        data <= data_rd & temp_msb;  -- 组合输出（交换字节序）

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
