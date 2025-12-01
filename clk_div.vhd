-- ============================================================================
-- 时钟分频器模块 (Clock Divider)
-- 功能：将FPGA板卡上的100MHz时钟分频为所需的两个时钟信号
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity clk_div is
    Port (
        clk_in      : in  STD_LOGIC;    -- 输入时钟，来自板卡的100 MHz晶振
        clk_sampling: out STD_LOGIC;    -- 输出采样时钟，约3 Hz，用于触发温度读取
        clk_display : out STD_LOGIC     -- 输出显示时钟，约6 kHz，用于7段数码管刷新
    );
end clk_div;

architecture Behavioral of clk_div is

    -- ========================================================================
    -- 分频系数计算
    -- ========================================================================
    -- 采样时钟：3 Hz 从 100 MHz
    --   完整周期 = 100,000,000 / 3 = 33,333,333 个时钟周期
    --   半周期 = 16,666,667 个时钟周期（用于翻转时钟信号）
    constant SAMPLING_DIV : integer := 16_666_667;

    -- 显示时钟：6 kHz 从 100 MHz
    --   完整周期 = 100,000,000 / 6,000 = 16,667 个时钟周期
    --   半周期 = 8,333 个时钟周期（用于翻转时钟信号）
    constant DISPLAY_DIV  : integer := 8_333;

    -- ========================================================================
    -- 内部信号定义
    -- ========================================================================
    -- 采样时钟计数器（0 到 16,666,667）
    signal cnt_sampling : integer range 0 to SAMPLING_DIV := 0;

    -- 显示时钟计数器（0 到 8,333）
    signal cnt_display  : integer range 0 to DISPLAY_DIV := 0;

    -- 内部时钟信号（用于在process内部赋值）
    signal clk_sampling_i : STD_LOGIC := '0';
    signal clk_display_i  : STD_LOGIC := '0';

begin

    -- ========================================================================
    -- 输出连接
    -- ========================================================================
    clk_sampling <= clk_sampling_i;
    clk_display  <= clk_display_i;

    -- ========================================================================
    -- 采样时钟生成进程 (~3 Hz)
    -- 用于控制温度传感器的读取频率
    -- ========================================================================
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            -- 每个100MHz时钟上升沿递增计数器
            if cnt_sampling = SAMPLING_DIV then
                -- 达到半周期，翻转时钟并重置计数器
                cnt_sampling <= 0;
                clk_sampling_i <= not clk_sampling_i;
            else
                -- 继续计数
                cnt_sampling <= cnt_sampling + 1;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- 显示时钟生成进程 (~6 kHz)
    -- 用于7段数码管的多路复用刷新（避免闪烁）
    -- ========================================================================
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            -- 每个100MHz时钟上升沿递增计数器
            if cnt_display = DISPLAY_DIV then
                -- 达到半周期，翻转时钟并重置计数器
                cnt_display <= 0;
                clk_display_i <= not clk_display_i;
            else
                -- 继续计数
                cnt_display <= cnt_display + 1;
            end if;
        end if;
    end process;

end Behavioral;
