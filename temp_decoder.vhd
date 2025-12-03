-- ============================================================================
-- 温度解码器模块 (Temperature Decoder)
-- 功能：将16位二进制温度值转换为BCD格式用于7段数码管显示
-- 
-- ADT7420温度传感器数据格式（13位分辨率，0.0625°C/LSB）：
--   寄存器0 (高字节): D12 D11 D10 D9 D8 D7 D6 D5
--   寄存器1 (低字节): D4  D3  D2  D1 D0 X  X  X
--   
-- 组合后的16位数据：temp_data(15 downto 3) = 13位温度值
--   - D12 (bit 15): 符号位，0=正温度
--   - D11-D4 (bits 14-7): 整数部分高8位 
--   - D3-D0 (bits 6-3): 小数部分（0.0625°C步进）
--   - bits 2-0: 未使用
--
-- 输出：
--   - bcd_tens: 十位度 (0-9)
--   - bcd_units: 个位度 (0-9)
--   - bcd_tenth: 十分之一度 (0-9)
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity temp_decoder is
    Port (
        clk         : in  STD_LOGIC;                        -- 系统时钟
        rst         : in  STD_LOGIC;                        -- 复位信号（高电平有效）
        temp_data   : in  STD_LOGIC_VECTOR(15 downto 0);    -- 16位原始温度数据
        bcd_tens    : out STD_LOGIC_VECTOR(3 downto 0);     -- 十位度 BCD
        bcd_units   : out STD_LOGIC_VECTOR(3 downto 0);     -- 个位度 BCD
        bcd_tenth   : out STD_LOGIC_VECTOR(3 downto 0)      -- 十分之一度 BCD
    );
end temp_decoder;

architecture Behavioral of temp_decoder is

    -- ========================================================================
    -- 组件声明：binary_bcd 转换器
    -- ========================================================================
    component binary_bcd is
        generic(N: positive := 16);
        port(
            clk, reset  : in std_logic;
            binary_in   : in std_logic_vector(N-1 downto 0);
            bcd0, bcd1, bcd2, bcd3, bcd4: out std_logic_vector(3 downto 0)
        );
    end component;

    -- ========================================================================
    -- 内部信号
    -- ========================================================================
    
    -- 温度整数部分（9位：D12-D4，范围0-127°C正温度）
    -- 从16位数据中提取：bits 15-7 对应 D12-D4
    signal temp_integer : STD_LOGIC_VECTOR(8 downto 0);
    
    -- 温度小数部分（4位：D3-D0，用于计算十分之一度）
    -- 从16位数据中提取：bits 6-3 对应 D3-D0
    signal temp_fraction : STD_LOGIC_VECTOR(3 downto 0);
    
    -- binary_bcd 的输入（扩展到16位）
    signal binary_in_s : STD_LOGIC_VECTOR(15 downto 0);
    
    -- binary_bcd 的输出
    signal bcd_out_0 : STD_LOGIC_VECTOR(3 downto 0);  -- 个位
    signal bcd_out_1 : STD_LOGIC_VECTOR(3 downto 0);  -- 十位
    signal bcd_out_2 : STD_LOGIC_VECTOR(3 downto 0);  -- 百位（温度通常不会超过99°C）
    signal bcd_out_3 : STD_LOGIC_VECTOR(3 downto 0);  -- 千位（不使用）
    signal bcd_out_4 : STD_LOGIC_VECTOR(3 downto 0);  -- 万位（不使用）
    
    -- 十分之一度 BCD 信号
    signal bcd_tenth_s : STD_LOGIC_VECTOR(3 downto 0);

begin

    -- ========================================================================
    -- 提取温度数据各部分
    -- ========================================================================
    -- 整数部分：D12-D4 = temp_data(15 downto 7)
    -- 注意：这里我们取绝对值用于显示，对于正温度直接使用
    temp_integer <= temp_data(15 downto 7);
    
    -- 小数部分：D3-D0 = temp_data(6 downto 3)
    temp_fraction <= temp_data(6 downto 3);
    
    -- 准备 binary_bcd 的输入（16位，高位补0）
    binary_in_s <= "0000000" & temp_integer;

    -- ========================================================================
    -- 实例化 binary_bcd 转换器（转换整数部分）
    -- ========================================================================
    binary_bcd_inst: binary_bcd
        generic map (N => 16)
        port map (
            clk       => clk,
            reset     => rst,
            binary_in => binary_in_s,
            bcd0      => bcd_out_0,   -- 个位度
            bcd1      => bcd_out_1,   -- 十位度
            bcd2      => bcd_out_2,   -- 百位（通常不用）
            bcd3      => bcd_out_3,   -- 不使用
            bcd4      => bcd_out_4    -- 不使用
        );

    -- ========================================================================
    -- 输出整数部分 BCD
    -- ========================================================================
    bcd_units <= bcd_out_0;  -- 个位度
    bcd_tens  <= bcd_out_1;  -- 十位度

    -- ========================================================================
    -- 小数部分转换（4位二进制 -> 十分之一度 BCD）
    -- 
    -- 每个LSB = 0.0625°C，4位小数范围 0-15，对应 0-0.9375°C
    -- 转换表：将 4位二进制小数 近似为 十分之一度
    -- 
    -- 二进制值 | 实际温度   | 近似十分之一度
    -- ---------|-----------|---------------
    --   0000   | 0.0000    | 0
    --   0001   | 0.0625    | 1
    --   0010   | 0.1250    | 1
    --   0011   | 0.1875    | 2
    --   0100   | 0.2500    | 2 (或3)
    --   0101   | 0.3125    | 3
    --   0110   | 0.3750    | 4
    --   0111   | 0.4375    | 4
    --   1000   | 0.5000    | 5
    --   1001   | 0.5625    | 6
    --   1010   | 0.6250    | 6
    --   1011   | 0.6875    | 7
    --   1100   | 0.7500    | 7 (或8)
    --   1101   | 0.8125    | 8
    --   1110   | 0.8750    | 9
    --   1111   | 0.9375    | 9
    -- ========================================================================
    with temp_fraction select
        bcd_tenth_s <=
            "0000" when "0000",  -- 0.0000 -> 0
            "0001" when "0001",  -- 0.0625 -> 1
            "0001" when "0010",  -- 0.1250 -> 1
            "0010" when "0011",  -- 0.1875 -> 2
            "0011" when "0100",  -- 0.2500 -> 3
            "0011" when "0101",  -- 0.3125 -> 3
            "0100" when "0110",  -- 0.3750 -> 4
            "0100" when "0111",  -- 0.4375 -> 4
            "0101" when "1000",  -- 0.5000 -> 5
            "0110" when "1001",  -- 0.5625 -> 6
            "0110" when "1010",  -- 0.6250 -> 6
            "0111" when "1011",  -- 0.6875 -> 7
            "1000" when "1100",  -- 0.7500 -> 8
            "1000" when "1101",  -- 0.8125 -> 8
            "1001" when "1110",  -- 0.8750 -> 9
            "1001" when "1111",  -- 0.9375 -> 9
            "0000" when others;  -- 默认值

    bcd_tenth <= bcd_tenth_s;

end Behavioral;
