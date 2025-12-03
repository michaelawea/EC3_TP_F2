library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

--================================================================================
-- 实体定义: binary_bcd
-- 功能: 
-- 将一个N位的二进制数转换为5个BCD码（总共20位）。
-- 采用 "Double Dabble" 或 "Shift-and-Add-3" (移位加3) 算法。
-- 泛型参数 N: 输入二进制数的位数，默认为16。
--================================================================================
entity binary_bcd is
    generic(N: positive := 16); -- 输入二进制数的位数
    port(
        clk, reset: in std_logic; -- 时钟和高电平有效同步复位
        binary_in: in std_logic_vector(N-1 downto 0); -- 输入的N位二进制数
        -- 输出的5个BCD码 (bcd4=万位, bcd3=千位, bcd2=百位, bcd1=十位, bcd0=个位)
        bcd0, bcd1, bcd2, bcd3, bcd4: out std_logic_vector(3 downto 0) 
    );
end binary_bcd;

architecture behaviour of binary_bcd is
    -- 状态机定义: start(开始), shift(移位), done(完成)
    type states is (start, shift, done);
    signal state, state_next: states := start;

    -- 信号定义
    -- binary: 内部寄存器，存储待转换的二进制数
    signal binary, binary_next: std_logic_vector(N-1 downto 0) := (others => '0');
    -- bcds: 存放BCD码的寄存器 (5个4位BCD = 20位)
    -- bcds_reg: "加3"操作之前的中间BCD值
    signal bcds, bcds_reg, bcds_next: std_logic_vector(19 downto 0) := (others => '0');
    -- bcds_out_reg: 输出寄存器, 在转换过程中保持输出稳定
    signal bcds_out_reg, bcds_out_reg_next: std_logic_vector(19 downto 0) := (others => '0');
    -- shift_counter: 移位计数器，记录移位次数
    signal shift_counter, shift_counter_next: natural range 0 to N := 0;
begin

    --================================================================================
    -- 进程: 同步进程 (时钟驱动)
    -- 功能: 在时钟下降沿更新所有寄存器的值。
    --================================================================================
    process(clk, reset)
    begin
        if reset = '1' then -- 复位
            binary <= (others => '0');
            bcds <= (others => '0');
            state <= start;
            bcds_out_reg <= (others => '0');
            shift_counter <= 0;
        elsif falling_edge(clk) then -- 时钟下降沿触发
            binary <= binary_next;
            bcds <= bcds_next;
            state <= state_next;
            bcds_out_reg <= bcds_out_reg_next;
            shift_counter <= shift_counter_next;
        end if;
    end process;

    --================================================================================
    -- 进程: 状态机和转换逻辑 (组合逻辑)
    -- 功能: 控制状态转换和数据流。
    --================================================================================
    convert:
    process(state, binary, binary_in, bcds, bcds_reg, shift_counter)
    begin
        -- 默认情况下，下一个状态和值保持不变
        state_next <= state;
        bcds_next <= bcds;
        binary_next <= binary;
        shift_counter_next <= shift_counter;

        case state is
            when start => -- 开始状态
                state_next <= shift; -- 下一状态为移位
                binary_next <= binary_in; -- 加载输入的二进制数
                bcds_next <= (others => '0'); -- 清零BCD寄存器
                shift_counter_next <= 0; -- 清零移位计数器
                
            when shift => -- 移位状态 (算法核心)
                if shift_counter = N then -- 如果已完成N次移位
                    state_next <= done; -- 转换完成
                else
                    -- 1. 左移二进制数, 'L'表示最低位补逻辑低(在std_logic_unsigned中通常是'0')
                    binary_next <= binary(N-2 downto 0) & 'L';
                    -- 2. 将BCD寄存器(bcds_reg是加3后的结果)左移一位,
                    --    并把原始二进制数的最高位(binary(N-1))移入BCD寄存器的最低位。
                    bcds_next <= bcds_reg(18 downto 0) & binary(N-1);
                    -- 3. 移位计数器加1
                    shift_counter_next <= shift_counter + 1;
                end if;
                
            when done => -- 完成状态
                state_next <= start; -- 回到开始状态，准备下一次转换
        end case;
    end process;

    --================================================================================
    -- "移位加3" 算法的 "加3" 部分 (并行组合逻辑)
    -- 功能: 
    -- 在每次移位之前，检查每个4位的BCD码。如果其值大于4 (即 5, 6, 7, 8, 9),
    -- 则给这个BCD码加上3。
    -- bcds_reg 保存了加3后的结果，用于下一次移位。
    --================================================================================
    bcds_reg(19 downto 16) <= bcds(19 downto 16) + 3 when bcds(19 downto 16) > 4 else
                              bcds(19 downto 16);
    bcds_reg(15 downto 12) <= bcds(15 downto 12) + 3 when bcds(15 downto 12) > 4 else
                              bcds(15 downto 12);
    bcds_reg(11 downto 8) <= bcds(11 downto 8) + 3 when bcds(11 downto 8) > 4 else
                             bcds(11 downto 8);
    bcds_reg(7 downto 4) <= bcds(7 downto 4) + 3 when bcds(7 downto 4) > 4 else
                            bcds(7 downto 4);
    bcds_reg(3 downto 0) <= bcds(3 downto 0) + 3 when bcds(3 downto 0) > 4 else
                            bcds(3 downto 0);

    --================================================================================
    -- 输出寄存器逻辑
    -- 功能: 当转换完成时 (state = done)，将最终的BCD结果锁存到输出寄存器bcds_out_reg。
    -- 在转换过程中，bcds_out_reg的值保持不变，从而提供稳定的输出。
    --================================================================================
    bcds_out_reg_next <= bcds when state = done else
                         bcds_out_reg;

    --================================================================================
    -- 输出端口分配
    -- 功能: 将输出寄存器中的值分配给对应的BCD输出端口。
    --================================================================================
    bcd4 <= bcds_out_reg(19 downto 16); -- 万位
    bcd3 <= bcds_out_reg(15 downto 12); -- 千位
    bcd2 <= bcds_out_reg(11 downto 8);  -- 百位
    bcd1 <= bcds_out_reg(7 downto 4);   -- 十位
    bcd0 <= bcds_out_reg(3 downto 0);   -- 个位

end behaviour;