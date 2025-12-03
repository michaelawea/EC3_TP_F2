-- ============================================================================
-- 7段数码管多路复用器 (Segment Multiplexer)
-- 功能：8:1多路复用器，顺序显示8个7段数码管的内容
-- 
-- Nexys A7 板上数码管排列（从左到右）：
--   AN7  AN6  AN5  AN4  AN3  AN2  AN1  AN0
--   
-- 本项目使用右侧4个数码管 (AN3-AN0) 显示温度：
--   AN3: 十位度
--   AN2: 个位度（带小数点）
--   AN1: 十分之一度
--   AN0: 度数符号 "°"
--   
-- AN7-AN4: 不使用（关闭）
--
-- 阳极信号 (an): 低电平有效，选中对应数码管
-- 段信号 (seg): 低电平点亮对应段
-- 小数点 (dp): 低电平点亮
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity seg_mux is
    Port (
        sel         : in  STD_LOGIC_VECTOR(2 downto 0);     -- 3位选择信号
        -- 8个数码管的7段输入
        seg_in0     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN0 的段数据（度数符号）
        seg_in1     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN1 的段数据（十分之一度）
        seg_in2     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN2 的段数据（个位度）
        seg_in3     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN3 的段数据（十位度）
        seg_in4     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN4（不使用）
        seg_in5     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN5（不使用）
        seg_in6     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN6（不使用）
        seg_in7     : in  STD_LOGIC_VECTOR(6 downto 0);     -- AN7（不使用）
        -- 8个数码管的小数点输入
        dp_in       : in  STD_LOGIC_VECTOR(7 downto 0);     -- 小数点输入 (dp7..dp0)
        -- 输出
        seg_out     : out STD_LOGIC_VECTOR(6 downto 0);     -- 当前段输出
        dp_out      : out STD_LOGIC;                         -- 当前小数点输出
        an          : out STD_LOGIC_VECTOR(7 downto 0)      -- 阳极选择输出（低电平有效）
    );
end seg_mux;

architecture Behavioral of seg_mux is
begin

    -- ========================================================================
    -- 多路复用逻辑
    -- 根据 sel 选择对应的数码管和段数据
    -- ========================================================================
    process(sel, seg_in0, seg_in1, seg_in2, seg_in3, seg_in4, seg_in5, seg_in6, seg_in7, dp_in)
    begin
        case sel is
            when "000" =>  -- 选择 AN0（度数符号）
                an <= "11111110";
                seg_out <= seg_in0;
                dp_out <= dp_in(0);
                
            when "001" =>  -- 选择 AN1（十分之一度）
                an <= "11111101";
                seg_out <= seg_in1;
                dp_out <= dp_in(1);
                
            when "010" =>  -- 选择 AN2（个位度，带小数点）
                an <= "11111011";
                seg_out <= seg_in2;
                dp_out <= dp_in(2);
                
            when "011" =>  -- 选择 AN3（十位度）
                an <= "11110111";
                seg_out <= seg_in3;
                dp_out <= dp_in(3);
                
            when "100" =>  -- 选择 AN4（不使用，关闭）
                an <= "11101111";
                seg_out <= seg_in4;
                dp_out <= dp_in(4);
                
            when "101" =>  -- 选择 AN5（不使用，关闭）
                an <= "11011111";
                seg_out <= seg_in5;
                dp_out <= dp_in(5);
                
            when "110" =>  -- 选择 AN6（不使用，关闭）
                an <= "10111111";
                seg_out <= seg_in6;
                dp_out <= dp_in(6);
                
            when "111" =>  -- 选择 AN7（不使用，关闭）
                an <= "01111111";
                seg_out <= seg_in7;
                dp_out <= dp_in(7);
                
            when others =>
                an <= "11111111";  -- 全部关闭
                seg_out <= "1111111";
                dp_out <= '1';
        end case;
    end process;

end Behavioral;
