-- Testbench for temp_reader
-- Modified from auto-generated template

library ieee;
use ieee.std_logic_1164.all;

entity tb_temp_reader is
end tb_temp_reader;

architecture tb of tb_temp_reader is

    component temp_reader
        port (clk         : in std_logic;
              rst         : in std_logic;
              trig        : in std_logic;
              data_rd     : in std_logic_vector (7 downto 0);
              i2c_busy    : in std_logic;
              i2c_ack     : in std_logic;
              busy        : out std_logic;
              data        : out std_logic_vector (15 downto 0);
              i2c_ena     : out std_logic;
              i2c_rw      : out std_logic;
              i2c_data_wr : out std_logic_vector (7 downto 0);
              i2c_addr    : out std_logic_vector (6 downto 0));
    end component;

    signal clk         : std_logic;
    signal rst         : std_logic;
    signal trig        : std_logic;
    signal data_rd     : std_logic_vector (7 downto 0);
    signal i2c_busy    : std_logic;
    signal i2c_ack     : std_logic;
    signal busy        : std_logic;
    signal data        : std_logic_vector (15 downto 0);
    signal i2c_ena     : std_logic;
    signal i2c_rw      : std_logic;
    signal i2c_data_wr : std_logic_vector (7 downto 0);
    signal i2c_addr    : std_logic_vector (6 downto 0);

    constant TbPeriod : time := 10 ns; -- 100MHz clock
    signal TbClock : std_logic := '0';
    signal TbSimEnded : std_logic := '0';

    -- Test data: 25.1°C = 0x0C88
    constant TEMP_MSB : std_logic_vector(7 downto 0) := "00001100"; -- 0x0C
    constant TEMP_LSB : std_logic_vector(7 downto 0) := "10001000"; -- 0x88

begin

    dut : temp_reader
    port map (clk         => clk,
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
              i2c_addr    => i2c_addr);

    -- Clock generation
    TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';
    clk <= TbClock;

    -- I2C Master behavior simulation
    i2c_master_sim : process
    begin
        i2c_busy <= '0';
        data_rd <= (others => '0');

        -- Wait for first i2c_ena (write register address)
        wait until i2c_ena = '1' and i2c_rw = '0';
        wait for 3 * TbPeriod;
        i2c_busy <= '1';
        wait for 10 * TbPeriod;
        i2c_busy <= '0';
        wait for 2 * TbPeriod;

        -- Wait for second i2c_ena (read MSB)
        wait until i2c_ena = '1' and i2c_rw = '1';
        wait for 3 * TbPeriod;
        i2c_busy <= '1';
        wait for 10 * TbPeriod;
        data_rd <= TEMP_MSB;  -- Provide MSB data
        wait for 1 * TbPeriod;
        i2c_busy <= '0';
        wait for 2 * TbPeriod;

        -- Wait for third i2c_ena (read LSB)
        wait until i2c_ena = '1' and i2c_rw = '1';
        wait for 3 * TbPeriod;
        i2c_busy <= '1';
        wait for 10 * TbPeriod;
        data_rd <= TEMP_LSB;  -- Provide LSB data
        wait for 1 * TbPeriod;
        i2c_busy <= '0';

        wait;
    end process;

    -- Stimulus process
    stimuli : process
    begin
        -- Initialization
        trig <= '0';
        i2c_ack <= '0';

        -- Reset generation
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        -- Send trigger to start temperature reading
        report "=== Starting temperature read ===" severity note;
        trig <= '1';
        wait for TbPeriod;
        trig <= '0';

        -- Wait for busy to go high
        wait until busy = '1';
        report "Temperature reader is busy" severity note;

        -- Wait for operation to complete
        wait until busy = '0';
        wait for 50 ns;

        report "=== Temperature read complete ===" severity note;
        report "Output data = " &
               integer'image(to_integer(unsigned(data(15 downto 8)))) &
               " (MSB), " &
               integer'image(to_integer(unsigned(data(7 downto 0)))) &
               " (LSB)" severity note;

        -- Verify result
        if data = (TEMP_MSB & TEMP_LSB) then
            report "*** TEST PASSED: Data = 0x0C88 (25.1C) ***" severity note;
        else
            report "*** TEST FAILED: Data mismatch! ***" severity error;
        end if;

        wait for 200 ns;

        -- Second read test
        report "=== Starting second temperature read ===" severity note;
        trig <= '1';
        wait for TbPeriod;
        trig <= '0';

        wait until busy = '1';
        wait until busy = '0';
        wait for 50 ns;

        report "=== Second read complete ===" severity note;
        report "Output data = " &
               integer'image(to_integer(unsigned(data(15 downto 8)))) &
               " (MSB), " &
               integer'image(to_integer(unsigned(data(7 downto 0)))) &
               " (LSB)" severity note;

        wait for 100 ns;

        report "=== SIMULATION FINISHED ===" severity note;

        -- Stop the clock and terminate simulation
        TbSimEnded <= '1';
        wait;
    end process;

end tb;

-- Configuration block
configuration cfg_tb_temp_reader of tb_temp_reader is
    for tb
    end for;
end cfg_tb_temp_reader;
