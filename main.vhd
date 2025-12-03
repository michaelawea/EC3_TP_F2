-- ============================================================================
-- 主文件 (Main)
-- 功能：顶层实体，连接时钟分频器、采样控制器、温度读取器、I2C主控制器
--       以及温度解码器和7段数码管显示模块
-- 实现ADT7420温度传感器的定期读取和十进制显示功能
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity main is
    Port (
        clk     : in    STD_LOGIC;                      -- 主时钟，100 MHz (来自板卡晶振)
        rst     : in    STD_LOGIC;                      -- 复位信号（高电平有效）
        LED     : out   STD_LOGIC_VECTOR(15 downto 0);  -- LED输出，显示16位温度原始数据
        JA      : out   STD_LOGIC_VECTOR(1 downto 0);   -- JA端口，用于调试I2C信号
        sda     : inout STD_LOGIC;                      -- I2C数据线（双向）
        scl     : inout STD_LOGIC;                      -- I2C时钟线（双向）
        -- 7段数码管输出
        seg     : out   STD_LOGIC_VECTOR(6 downto 0);   -- 7段数码管段选信号
        dp      : out   STD_LOGIC;                      -- 小数点
        an      : out   STD_LOGIC_VECTOR(7 downto 0)    -- 数码管阳极选择（低电平有效）
    );
end main;

architecture Behavioral of main is

    -- ========================================================================
    -- 组件声明
    -- ========================================================================

    -- 时钟分频器组件
    component clk_div is
        Port (
            clk_in      : in  STD_LOGIC;
            clk_sampling: out STD_LOGIC;
            clk_display : out STD_LOGIC
        );
    end component;

    -- 采样控制器组件
    component sampling_controller is
        Port (
            clk             : in  STD_LOGIC;
            rst             : in  STD_LOGIC;
            clk_sampling    : in  STD_LOGIC;
            busy            : in  STD_LOGIC;
            trig            : out STD_LOGIC
        );
    end component;

    -- 温度读取器组件
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

    -- I2C主控制器组件
    component i2c_master is
        Port (
            clk       : in     STD_LOGIC;
            reset_n   : in     STD_LOGIC;
            ena       : in     STD_LOGIC;
            addr      : in     STD_LOGIC_VECTOR(6 downto 0);
            rw        : in     STD_LOGIC;
            data_wr   : in     STD_LOGIC_VECTOR(7 downto 0);
            busy      : out    STD_LOGIC;
            data_rd   : out    STD_LOGIC_VECTOR(7 downto 0);
            ack_error : BUFFER STD_LOGIC;
            sda       : inout  STD_LOGIC;
            scl       : inout  STD_LOGIC
        );
    end component;

    -- 温度解码器组件
    component temp_decoder is
        Port (
            clk         : in  STD_LOGIC;
            rst         : in  STD_LOGIC;
            temp_data   : in  STD_LOGIC_VECTOR(15 downto 0);
            bcd_tens    : out STD_LOGIC_VECTOR(3 downto 0);
            bcd_units   : out STD_LOGIC_VECTOR(3 downto 0);
            bcd_tenth   : out STD_LOGIC_VECTOR(3 downto 0)
        );
    end component;

    -- BCD到7段解码器组件
    component bcd2seg is
        Port (
            bcd     : in  STD_LOGIC_VECTOR(3 downto 0);
            seg     : out STD_LOGIC_VECTOR(6 downto 0)
        );
    end component;

    -- 度数符号组件
    component degree_symbol is
        Port (
            seg     : out STD_LOGIC_VECTOR(6 downto 0)
        );
    end component;

    -- 数码管选择计数器组件
    component seg_counter is
        Port (
            clk_display : in  STD_LOGIC;
            rst         : in  STD_LOGIC;
            sel         : out STD_LOGIC_VECTOR(2 downto 0)
        );
    end component;

    -- 数码管多路复用器组件
    component seg_mux is
        Port (
            sel         : in  STD_LOGIC_VECTOR(2 downto 0);
            seg_in0     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in1     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in2     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in3     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in4     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in5     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in6     : in  STD_LOGIC_VECTOR(6 downto 0);
            seg_in7     : in  STD_LOGIC_VECTOR(6 downto 0);
            dp_in       : in  STD_LOGIC_VECTOR(7 downto 0);
            seg_out     : out STD_LOGIC_VECTOR(6 downto 0);
            dp_out      : out STD_LOGIC;
            an          : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    -- ========================================================================
    -- 内部信号定义
    -- ========================================================================

    -- clk_div 输出信号
    signal clk_sampling_s   : STD_LOGIC;    -- 采样时钟，约3 Hz
    signal clk_display_s    : STD_LOGIC;    -- 显示时钟，约6 kHz

    -- sampling_controller 信号
    signal trig_s           : STD_LOGIC;    -- 触发信号，启动温度读取

    -- temp_reader 信号
    signal temp_busy_s      : STD_LOGIC;    -- 温度读取忙标志
    signal temp_data_s      : STD_LOGIC_VECTOR(15 downto 0) := (others => '0'); -- 16位温度数据

    -- temp_reader 到 i2c_master 的信号
    signal i2c_ena_s        : STD_LOGIC;    -- I2C使能信号
    signal i2c_rw_s         : STD_LOGIC;    -- I2C读写控制
    signal i2c_data_wr_s    : STD_LOGIC_VECTOR(7 downto 0);  -- I2C写数据
    signal i2c_addr_s       : STD_LOGIC_VECTOR(6 downto 0);  -- I2C从设备地址

    -- i2c_master 输出信号
    signal i2c_busy_s       : STD_LOGIC;    -- I2C总线忙标志
    signal i2c_data_rd_s    : STD_LOGIC_VECTOR(7 downto 0);  -- I2C读取数据
    signal i2c_ack_error_s  : STD_LOGIC;    -- I2C应答错误标志

    -- 复位信号转换 (i2c_master使用低电平有效复位)
    signal reset_n_s        : STD_LOGIC;

    -- temp_decoder 输出信号
    signal bcd_tens_s       : STD_LOGIC_VECTOR(3 downto 0);  -- 十位度 BCD
    signal bcd_units_s      : STD_LOGIC_VECTOR(3 downto 0);  -- 个位度 BCD
    signal bcd_tenth_s      : STD_LOGIC_VECTOR(3 downto 0);  -- 十分之一度 BCD

    -- bcd2seg 输出信号（7段数据）
    signal seg_tens_s       : STD_LOGIC_VECTOR(6 downto 0);  -- 十位度 7段
    signal seg_units_s      : STD_LOGIC_VECTOR(6 downto 0);  -- 个位度 7段
    signal seg_tenth_s      : STD_LOGIC_VECTOR(6 downto 0);  -- 十分之一度 7段
    signal seg_degree_s     : STD_LOGIC_VECTOR(6 downto 0);  -- 度数符号 7段

    -- seg_counter 输出信号
    signal seg_sel_s        : STD_LOGIC_VECTOR(2 downto 0);  -- 数码管选择

    -- 小数点配置：只有个位度（AN2）显示小数点
    signal dp_config_s      : STD_LOGIC_VECTOR(7 downto 0) := "11111011";

    -- 不使用的数码管（全灭）
    signal seg_off_s        : STD_LOGIC_VECTOR(6 downto 0) := "1111111";

begin

    -- ========================================================================
    -- 信号转换
    -- ========================================================================
    reset_n_s <= not rst;  -- 将高电平有效复位转换为低电平有效

    -- ========================================================================
    -- 输出连接
    -- ========================================================================
    LED <= temp_data_s;     -- 将温度数据输出到LED
    JA(0) <= scl;           -- JA端口用于调试：SCL信号
    JA(1) <= sda;           -- JA端口用于调试：SDA信号

    -- ========================================================================
    -- 组件实例化
    -- ========================================================================

    -- 实例1: 时钟分频器
    -- 功能：将100MHz主时钟分频为3Hz采样时钟和6kHz显示时钟
    clk_div_1: clk_div
        port map (
            clk_in       => clk,
            clk_sampling => clk_sampling_s,
            clk_display  => clk_display_s
        );

    -- 实例2: 采样控制器
    -- 功能：根据采样时钟生成触发脉冲，控制温度读取的启动时机
    sampling_controller_1: sampling_controller
        port map (
            clk          => clk,
            rst          => rst,
            clk_sampling => clk_sampling_s,
            busy         => temp_busy_s,
            trig         => trig_s
        );

    -- 实例3: 温度读取器
    -- 功能：通过I2C总线读取ADT7420温度传感器的数据
    temp_reader_1: temp_reader
        port map (
            clk         => clk,
            rst         => rst,
            trig        => trig_s,
            data_rd     => i2c_data_rd_s,
            i2c_busy    => i2c_busy_s,
            i2c_ack     => i2c_ack_error_s,
            busy        => temp_busy_s,
            data        => temp_data_s,
            i2c_ena     => i2c_ena_s,
            i2c_rw      => i2c_rw_s,
            i2c_data_wr => i2c_data_wr_s,
            i2c_addr    => i2c_addr_s
        );

    -- 实例4: I2C主控制器
    -- 功能：实现I2C总线协议，与温度传感器通信
    i2c_master_1: i2c_master
        port map (
            clk       => clk,
            reset_n   => reset_n_s,
            ena       => i2c_ena_s,
            addr      => i2c_addr_s,
            rw        => i2c_rw_s,
            data_wr   => i2c_data_wr_s,
            busy      => i2c_busy_s,
            data_rd   => i2c_data_rd_s,
            ack_error => i2c_ack_error_s,
            sda       => sda,
            scl       => scl
        );

    -- ========================================================================
    -- 第二部分：温度解码和7段数码管显示
    -- ========================================================================

    -- 实例5: 温度解码器
    -- 功能：将16位二进制温度值转换为BCD格式
    temp_decoder_1: temp_decoder
        port map (
            clk       => clk,
            rst       => rst,
            temp_data => temp_data_s,
            bcd_tens  => bcd_tens_s,
            bcd_units => bcd_units_s,
            bcd_tenth => bcd_tenth_s
        );

    -- 实例6: BCD到7段解码器（十位度）
    bcd2seg_tens: bcd2seg
        port map (
            bcd => bcd_tens_s,
            seg => seg_tens_s
        );

    -- 实例7: BCD到7段解码器（个位度）
    bcd2seg_units: bcd2seg
        port map (
            bcd => bcd_units_s,
            seg => seg_units_s
        );

    -- 实例8: BCD到7段解码器（十分之一度）
    bcd2seg_tenth: bcd2seg
        port map (
            bcd => bcd_tenth_s,
            seg => seg_tenth_s
        );

    -- 实例9: 度数符号
    degree_symbol_1: degree_symbol
        port map (
            seg => seg_degree_s
        );

    -- 实例10: 数码管选择计数器
    seg_counter_1: seg_counter
        port map (
            clk_display => clk_display_s,
            rst         => rst,
            sel         => seg_sel_s
        );

    -- 实例11: 数码管多路复用器
    -- AN0: 度数符号, AN1: 十分之一度, AN2: 个位度(带小数点), AN3: 十位度
    -- AN4-AN7: 不使用（全灭）
    seg_mux_1: seg_mux
        port map (
            sel     => seg_sel_s,
            seg_in0 => seg_degree_s,    -- AN0: 度数符号 "°"
            seg_in1 => seg_tenth_s,     -- AN1: 十分之一度
            seg_in2 => seg_units_s,     -- AN2: 个位度
            seg_in3 => seg_tens_s,      -- AN3: 十位度
            seg_in4 => seg_off_s,       -- AN4: 不使用
            seg_in5 => seg_off_s,       -- AN5: 不使用
            seg_in6 => seg_off_s,       -- AN6: 不使用
            seg_in7 => seg_off_s,       -- AN7: 不使用
            dp_in   => dp_config_s,     -- 小数点配置
            seg_out => seg,             -- 7段输出
            dp_out  => dp,              -- 小数点输出
            an      => an               -- 阳极选择输出
        );

end Behavioral;
