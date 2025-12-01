-- ============================================================================
-- Testbench for main
-- 功能：测试顶层模块，包含完整的温度读取系统
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_main is
end tb_main;

architecture tb of tb_main is

    -- ========================================================================
    -- 被测试组件声明
    -- ========================================================================
    component main
        port (
            clk : in    std_logic;
            rst : in    std_logic;
            LED : out   std_logic_vector(15 downto 0);
            JA  : out   std_logic_vector(1 downto 0);
            sda : inout std_logic;
            scl : inout std_logic
        );
    end component;

    -- ========================================================================
    -- 测试信号定义
    -- ========================================================================
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal LED : std_logic_vector(15 downto 0);
    signal JA  : std_logic_vector(1 downto 0);
    signal sda : std_logic;
    signal scl : std_logic;

    -- 时钟参数
    constant TbPeriod : time := 10 ns;  -- 100 MHz时钟周期
    signal TbClock : std_logic := '0';
    signal TbSimEnded : std_logic := '0';

begin

    -- ========================================================================
    -- 被测试单元实例化
    -- ========================================================================
    dut : main
    port map (
        clk => clk,
        rst => rst,
        LED => LED,
        JA  => JA,
        sda => sda,
        scl => scl
    );

    -- ========================================================================
    -- 时钟生成
    -- ========================================================================
    TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';
    clk <= TbClock;

    -- ========================================================================
    -- I2C总线上拉模拟
    -- ========================================================================
    i2c_pullup : process
    begin
        sda <= 'H';  -- 弱上拉到高电平
        scl <= 'H';  -- 弱上拉到高电平
        wait;
    end process;

    -- ========================================================================
    -- 激励信号生成
    -- ========================================================================
    stimuli : process
    begin
        -- 初始化
        rst <= '1';
        wait for 200 ns;

        -- 释放复位
        rst <= '0';
        wait for 1 us;

        -- 观察系统运行
        wait for 2 ms;

        -- 等待第二次读取
        wait for 2 ms;

        -- 测试复位功能
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 2 ms;

        -- 结束仿真
        TbSimEnded <= '1';
        wait;
    end process;

end tb;

-- ============================================================================
-- 配置
-- ============================================================================
configuration cfg_tb_main of tb_main is
    for tb
    end for;
end cfg_tb_main;
