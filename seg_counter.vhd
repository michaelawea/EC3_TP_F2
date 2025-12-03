-- ============================================================================
-- 7段数码管选择计数器 (Segment Counter)
-- 功能：基于显示时钟生成3位计数器，用于选择当前显示的数码管
-- 
-- Nexys A7 板有8个7段数码管，使用3位计数器循环选择 (0-7)
-- 计数器输出用作 seg_mux 的选择信号
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity seg_counter is
    Port (
        clk_display : in  STD_LOGIC;                    -- 显示时钟，约6kHz
        rst         : in  STD_LOGIC;                    -- 复位信号（高电平有效）
        sel         : out STD_LOGIC_VECTOR(2 downto 0)  -- 3位选择信号 (0-7)
    );
end seg_counter;

architecture Behavioral of seg_counter is
    signal count : unsigned(2 downto 0) := (others => '0');
begin

    -- ========================================================================
    -- 计数进程
    -- 每个显示时钟上升沿递增计数器，循环 0->1->2->...->7->0
    -- ========================================================================
    process(clk_display, rst)
    begin
        if rst = '1' then
            count <= (others => '0');
        elsif rising_edge(clk_display) then
            count <= count + 1;  -- 3位计数器自动回绕
        end if;
    end process;

    sel <= std_logic_vector(count);

end Behavioral;
