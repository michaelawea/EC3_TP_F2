-- ============================================================================
-- 主文件 (Main)
-- 功能：顶层实体，连接时钟分频器、采样控制器、温度读取器和I2C主控制器
-- 实现ADT7420温度传感器的定期读取功能
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity main is
    Port (
        clk     : in    STD_LOGIC;                      -- 主时钟，100 MHz (来自板卡晶振)
        rst     : in    STD_LOGIC;                      -- 复位信号（高电平有效）
        LED     : out   STD_LOGIC_VECTOR(15 downto 0); -- LED输出，显示16位温度原始数据
        JA      : out   STD_LOGIC_VECTOR(1 downto 0);  -- JA端口，用于调试I2C信号
        sda     : inout STD_LOGIC;                      -- I2C数据线（双向）
        scl     : inout STD_LOGIC                       -- I2C时钟线（双向）
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

    -- ========================================================================
    -- 内部信号定义
    -- ========================================================================

    -- clk_div 输出信号
    signal clk_sampling_s   : STD_LOGIC;    -- 采样时钟，约3 Hz
    signal clk_display_s    : STD_LOGIC;    -- 显示时钟，约6 kHz (暂不使用)

    -- sampling_controller 信号
    signal trig_s           : STD_LOGIC;    -- 触发信号，启动温度读取

    -- temp_reader 信号
    signal temp_busy_s      : STD_LOGIC;    -- 温度读取忙标志
    signal temp_data_s      : STD_LOGIC_VECTOR(15 downto 0); -- 16位温度数据

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

end Behavioral;
