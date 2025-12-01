----------------------------------------------------------------------------------
-- Testbench for temp_reader
-- 测试温度读取模块
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity temp_reader_tb is
end temp_reader_tb;

architecture Behavioral of temp_reader_tb is

    -- 被测试模块的组件声明
    component temp_reader is
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
    end component;

    -- 时钟周期
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    -- 测试信号
    signal clk         : STD_LOGIC := '0';
    signal rst         : STD_LOGIC := '0';
    signal trig        : STD_LOGIC := '0';
    signal data_rd     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal i2c_busy    : STD_LOGIC := '0';
    signal i2c_ack     : STD_LOGIC := '0';
    signal busy        : STD_LOGIC;
    signal data        : STD_LOGIC_VECTOR(15 downto 0);
    signal i2c_ena     : STD_LOGIC;
    signal i2c_rw      : STD_LOGIC;
    signal i2c_data_wr : STD_LOGIC_VECTOR(7 downto 0);
    signal i2c_addr    : STD_LOGIC_VECTOR(6 downto 0);

    -- 测试数据 (25.1°C = 0x0C88)
    constant TEMP_MSB  : STD_LOGIC_VECTOR(7 downto 0) := "00001100";  -- 0x0C
    constant TEMP_LSB  : STD_LOGIC_VECTOR(7 downto 0) := "10001000";  -- 0x88

begin

    -- 实例化被测试模块
    UUT: temp_reader
        port map (
            clk         => clk,
            rst         => rst,
            trig        => trig,
            data_rd     => data_rd,
            i2c_busy    => i2c_busy,
            i2c_ack     => i2c_ack,
            busy        => busy,
            data        => data,
            i2c_ena     => i2c_ena,
            i2c_rw      => i2c_rw,
            i2c_data_wr => i2c_data_wr,
            i2c_addr    => i2c_addr
        );

    -- 时钟生成进程
    CLK_PROCESS: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- 模拟I2C Master行为的进程
    I2C_MASTER_SIM: process
    begin
        i2c_busy <= '0';
        data_rd <= (others => '0');

        wait until i2c_ena = '1' and i2c_rw = '0';  -- 等待写寄存器地址
        wait for 50 ns;
        i2c_busy <= '1';
        wait for 100 ns;
        i2c_busy <= '0';

        wait until i2c_ena = '1' and i2c_rw = '1';  -- 等待读MSB
        wait for 50 ns;
        i2c_busy <= '1';
        wait for 100 ns;
        data_rd <= TEMP_MSB;  -- 提供MSB数据
        i2c_busy <= '0';
        wait for 10 ns;

        wait until i2c_ena = '1' and i2c_rw = '1';  -- 等待读LSB
        wait for 50 ns;
        i2c_busy <= '1';
        wait for 100 ns;
        data_rd <= TEMP_LSB;  -- 提供LSB数据
        i2c_busy <= '0';

        wait;
    end process;

    -- 测试激励进程
    STIMULUS: process
    begin
        -- 初始复位
        rst <= '1';
        trig <= '0';
        wait for 100 ns;
        rst <= '0';
        wait for 50 ns;

        -- 发送触发信号
        report "Starting temperature read...";
        trig <= '1';
        wait for CLK_PERIOD;
        trig <= '0';

        -- 等待读取完成
        wait until busy = '0';
        wait for 100 ns;

        -- 检查结果
        report "Temperature read complete!";
        report "Data = 0x" &
               integer'image(to_integer(unsigned(data(15 downto 12)))) &
               integer'image(to_integer(unsigned(data(11 downto 8)))) &
               integer'image(to_integer(unsigned(data(7 downto 4)))) &
               integer'image(to_integer(unsigned(data(3 downto 0))));

        if data = (TEMP_MSB & TEMP_LSB) then
            report "TEST PASSED: Data matches expected value 0x0C88 (25.1C)" severity note;
        else
            report "TEST FAILED: Data mismatch!" severity error;
        end if;

        wait for 200 ns;

        -- 第二次读取测试
        report "Starting second temperature read...";
        trig <= '1';
        wait for CLK_PERIOD;
        trig <= '0';

        wait until busy = '0';
        wait for 100 ns;

        report "Second read complete!";
        report "Simulation finished.";

        wait;
    end process;

end Behavioral;
