--------------------------------------------------------------------------------
--
--   FileName:         i2c_master.vhd
--   Dependencies:     none
--   Design Software:  Quartus II 64-bit Version 13.1 Build 162 SJ Full Version
--
--   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
--   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
--   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
--   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
--   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
--   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
--   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
--
--   Version History
--   Version 1.0 11/01/2012 Scott Larson
--     Initial Public Release
--   Version 2.0 06/20/2014 Scott Larson
--     Added ability to interface with different slaves in the same transaction
--     Corrected ack_error bug where ack_error went 'Z' instead of '1' on error
--     Corrected timing of when ack_error signal clears
--   Version 2.1 10/21/2014 Scott Larson
--     Replaced gated clock with clock enable
--     Adjusted timing of SCL during start and stop conditions
--   Version 2.2 02/05/2015 Scott Larson
--     Corrected small SDA glitch introduced in version 2.1
-- 
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

--================================================================================
-- 实体定义: i2c_master
-- 功能: 实现一个I2C总线主控制器。
--================================================================================
ENTITY i2c_master IS
  PORT(
    clk       : IN     STD_LOGIC;                    -- 系统时钟
    reset_n   : IN     STD_LOGIC;                    -- 低电平有效异步复位
    ena       : IN     STD_LOGIC;                    -- 使能信号，高电平有效，用于锁存命令和启动/维持一次I2C传输
    addr      : IN     STD_LOGIC_VECTOR(6 DOWNTO 0); -- 目标从设备的7位地址
    rw        : IN     STD_LOGIC;                    -- 传输方向: '0' 表示写, '1' 表示读
    data_wr   : IN     STD_LOGIC_VECTOR(7 DOWNTO 0); -- 要写入从设备的数据
    busy      : OUT    STD_LOGIC;                    -- 忙标志，'1'表示I2C传输正在进行中
    data_rd   : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0); -- 从从设备读取的数据
    ack_error : BUFFER STD_LOGIC;                    -- 应答错误标志，'1'表示从设备未发送有效的应答信号(ACK)
    sda       : INOUT  STD_LOGIC;                    -- I2C串行数据线 (双向)
    scl       : INOUT  STD_LOGIC);                   -- I2C串行时钟线 (双向)
END i2c_master;

ARCHITECTURE logic OF i2c_master IS
  -- I2C总线时钟频率是通过分频系统时钟得到的。这里的注释提供了一个计算分频比的例子。
  -- CONSTANT divider  :  INTEGER := (input_clk/bus_clk)/4; -- SCL时钟1/4周期内的系统时钟周期数
  
  -- 定义状态机的状态
  TYPE machine IS(ready, start, command, slv_ack1, wr, rd, slv_ack2, mstr_ack, stop); 
  SIGNAL state         : machine;                        -- 状态机当前状态
  
  -- 内部时钟和信号
  SIGNAL data_clk      : STD_LOGIC;                      -- 数据时钟，用于同步SDA数据的变化
  SIGNAL data_clk_prev : STD_LOGIC;                      -- 上一个系统时钟周期的数据时钟值
  SIGNAL scl_clk       : STD_LOGIC;                      -- 内部生成的原始SCL时钟信号
  SIGNAL scl_ena       : STD_LOGIC := '0';               -- SCL输出使能信号，'1'时允许scl_clk驱动scl线
  SIGNAL sda_int       : STD_LOGIC := '1';               -- 内部SDA数据信号，用于主设备驱动SDA
  SIGNAL sda_ena_n     : STD_LOGIC;                      -- SDA输出使能信号（低电平有效），控制SDA线的驱动
  
  -- 数据锁存和计数器
  SIGNAL addr_rw       : STD_LOGIC_VECTOR(7 DOWNTO 0);   -- 锁存的从设备地址和读写位 (addr & rw)
  SIGNAL data_tx       : STD_LOGIC_VECTOR(7 DOWNTO 0);   -- 锁存的要发送的数据
  SIGNAL data_rx       : STD_LOGIC_VECTOR(7 DOWNTO 0);   -- 从SDA线上接收的数据
  SIGNAL bit_cnt       : INTEGER RANGE 0 TO 7 := 7;      -- 位计数器，用于追踪8位数据的传输进度
  SIGNAL stretch       : STD_LOGIC := '0';               -- 时钟延长标志, '1'表示检测到从设备正在延长SCL时钟

BEGIN

  --================================================================================
  -- 进程: 时钟生成器
  -- 功能: 
  -- 1. 基于系统时钟clk生成内部的SCL时钟(scl_clk)和数据时钟(data_clk)。
  -- 2. SCL时钟被分成四个相位，以满足I2C时序要求。
  -- 3. 实现I2C时钟延长(clock stretching)检测。当从设备将SCL拉低时，
  --    计数器暂停，直到SCL被释放，从而实现时钟延长。
  --================================================================================
  PROCESS(clk, reset_n)
    -- 注意: 这里的计数器最大值250是基于特定的系统时钟和I2C总线时钟计算得出的。
    -- 例如: 系统时钟50MHz, I2C时钟100kHz, divider = (50M/100k)/4 = 125. 计数器范围是0到499.
    -- 这里固定为250，意味着一个SCL周期包含1000个系统时钟周期。50MHz/1000 = 50kHz SCL.
    VARIABLE count  :  INTEGER RANGE 0 TO 250; -- 分频计数器
  BEGIN
    IF(reset_n = '0') THEN                -- 复位信号有效
      stretch <= '0';                     -- 清除时钟延长标志
      count := 0;                         -- 复位计数器
    ELSIF(clk'EVENT AND clk = '1') THEN
      data_clk_prev <= data_clk;          -- 保存上一个数据时钟的值
      
      IF(count = 249) THEN -- divider*4-1    -- 一个完整的SCL时钟周期结束
        count := 0;                       -- 重置计数器
      ELSIF(stretch = '0') THEN           -- 如果没有检测到时钟延长
        count := count + 1;               -- 计数器加1
      END IF;
      
      -- 根据计数器的值生成scl_clk和data_clk的波形
      CASE count IS
        WHEN 0 TO 62 => -- divider-1        -- 第1个1/4周期
          scl_clk <= '0';
          data_clk <= '0';
        WHEN 63 TO 124 => -- divider*2-1    -- 第2个1/4周期
          scl_clk <= '0';
          data_clk <= '1'; -- data_clk在SCL低电平中间产生上升沿
        WHEN 125 TO 186 => -- divider*3-1  -- 第3个1/4周期
          scl_clk <= '1';                 -- 释放SCL（拉高）
          IF(scl = '0') THEN              -- 检测SCL线是否被从设备拉低
            stretch <= '1';               -- 如果是，则设置时钟延长标志
          ELSE
            stretch <= '0';               -- 否则，清除标志
          END IF;
          data_clk <= '1';
        WHEN OTHERS =>                    -- 第4个1/4周期
          scl_clk <= '1';
          data_clk <= '0'; -- data_clk在SCL高电平中间产生下降沿
      END CASE;
    END IF;
  END PROCESS;

  --================================================================================
  -- 进程: I2C主状态机
  -- 功能: 
  -- 1. 控制I2C传输的整个流程，包括起始、命令、读/写、应答和停止。
  -- 2. 在data_clk的上升沿改变SDA上的数据 (sda_int)。
  -- 3. 在data_clk的下降沿读取SDA上的数据。
  --================================================================================
  PROCESS(clk, reset_n)
  BEGIN
    IF(reset_n = '0') THEN                 -- 复位信号有效
      state <= ready;                      -- 回到就绪状态
      busy <= '1';                         -- 置忙标志（复位期间不可用）
      scl_ena <= '0';                      -- SCL输出高阻态
      sda_int <= '1';                      -- SDA内部信号高电平（准备释放总线）
      ack_error <= '0';                    -- 清除应答错误标志
      bit_cnt <= 7;                        -- 复位位计数器
      data_rd <= "00000000";               -- 清除读取数据寄存器
    ELSIF(clk'EVENT AND clk = '1') THEN
      -- --------------------------------------------------------------------------
      -- 数据发送逻辑 (data_clk 上升沿)
      -- --------------------------------------------------------------------------
      IF(data_clk = '1' AND data_clk_prev = '0') THEN  
        CASE state IS
          WHEN ready =>                      -- 空闲状态
            IF(ena = '1') THEN               -- 如果收到使能信号，开始一次新的传输
              busy <= '1';                   -- 设置忙标志
              addr_rw <= addr & rw;          -- 锁存地址和读写位
              data_tx <= data_wr;            -- 锁存要写入的数据
              state <= start;                -- 进入起始状态
            ELSE                             -- 否则保持空闲
              busy <= '0';                   -- 清除忙标志
              state <= ready;                -- 保持就绪状态
            END IF;
            
          WHEN start =>                      -- 产生起始条件后，发送地址/命令字节的第一个bit
            busy <= '1';                     -- 在连续传输模式下，保持忙状态
            sda_int <= addr_rw(bit_cnt);     -- 发送地址的最高位 (MSB)
            state <= command;                -- 进入命令发送状态
            
          WHEN command =>                    -- 发送地址和读写命令字节
            IF(bit_cnt = 0) THEN             -- 8位地址和命令已发送完毕
              sda_int <= '1';                -- 释放SDA，准备接收从设备的ACK
              bit_cnt <= 7;                  -- 重置位计数器，为下一个字节做准备
              state <= slv_ack1;             -- 进入等待从设备ACK的状态
            ELSE                             -- 继续发送下一个bit
              bit_cnt <= bit_cnt - 1;        -- 位计数器减1
              sda_int <= addr_rw(bit_cnt-1); -- 发送下一个bit
              state <= command;              -- 保持在命令发送状态
            END IF;
            
          WHEN slv_ack1 =>                   -- 等待从设备对地址/命令的应答
            IF(addr_rw(0) = '0') THEN        -- 如果是写命令 ('0')
              sda_int <= data_tx(bit_cnt);   -- 发送写数据的第一个bit
              state <= wr;                   -- 进入写数据状态
            ELSE                             -- 如果是读命令 ('1')
              sda_int <= '1';                -- 释放SDA，准备接收数据
              state <= rd;                   -- 进入读数据状态
            END IF;
            
          WHEN wr =>                         -- 写数据字节状态
            busy <= '1';                     -- 在连续传输模式下，保持忙状态
            IF(bit_cnt = 0) THEN             -- 8位数据已发送完毕
              sda_int <= '1';                -- 释放SDA，准备接收从设备的ACK
              bit_cnt <= 7;                  -- 重置位计数器
              state <= slv_ack2;             -- 进入等待从设备ACK的状态
            ELSE                             -- 继续发送下一个bit
              bit_cnt <= bit_cnt - 1;        -- 位计数器减1
              sda_int <= data_tx(bit_cnt-1); -- 发送下一个bit
              state <= wr;                   -- 保持在写数据状态
            END IF;
            
          WHEN rd =>                         -- 读数据字节状态
            busy <= '1';                     -- 在连续传输模式下，保持忙状态
            IF(bit_cnt = 0) THEN             -- 8位数据已接收完毕
              IF(ena = '1' AND addr_rw = addr & rw) THEN  -- 如果要连续读同一地址
                sda_int <= '0';              -- 主设备发送ACK (拉低SDA)
              ELSE                           -- 如果要停止或切换到写操作
                sda_int <= '1';              -- 主设备发送NACK (不拉低SDA)
              END IF;
              bit_cnt <= 7;                  -- 重置位计数器
              data_rd <= data_rx;            -- 输出接收到的数据
              state <= mstr_ack;             -- 进入主设备应答状态
            ELSE                             -- 继续接收下一个bit
              bit_cnt <= bit_cnt - 1;        -- 位计数器减1
              state <= rd;                   -- 保持在读数据状态
            END IF;
            
          WHEN slv_ack2 =>                   -- 等待从设备对写数据的应答
            IF(ena = '1') THEN               -- 如果要继续传输
              busy <= '0';                   -- 短暂解除忙状态，表示可以接收新命令
              addr_rw <= addr & rw;          -- 锁存新的地址和命令
              data_tx <= data_wr;            -- 锁存新的写数据
              IF(addr_rw = addr & rw) THEN   -- 如果是连续写
                sda_int <= data_wr(bit_cnt); -- 发送新数据的第一个bit
                state <= wr;                 -- 回到写数据状态
              ELSE                           -- 如果是切换到读操作或新的从设备
                state <= start;              -- 产生重复起始条件
              END IF;
            ELSE                             -- 否则，结束传输
              state <= stop;                 -- 进入停止状态
            END IF;
            
          WHEN mstr_ack =>                   -- 主设备发送应答后
            IF(ena = '1') THEN               -- 如果要继续传输
              busy <= '0';                   -- 短暂解除忙状态，表示接收到的数据已可用
              addr_rw <= addr & rw;          -- 锁存新的地址和命令
              data_tx <= data_wr;            -- 锁存新的写数据
              IF(addr_rw = addr & rw) THEN   -- 如果是连续读
                sda_int <= '1';              -- 释放SDA，准备接收数据
                state <= rd;                 -- 回到读数据状态
              ELSE                           -- 如果是切换到写操作或新的从设备
                state <= start;              -- 产生重复起始条件
              END IF;    
            ELSE                             -- 否则，结束传输
              state <= stop;                 -- 进入停止状态
            END IF;
            
          WHEN stop =>                       -- 停止状态
            busy <= '0';                     -- 解除忙状态
            state <= ready;                  -- 回到就绪状态
        END CASE;    
        
      -- --------------------------------------------------------------------------
      -- 数据接收逻辑 (data_clk 下降沿)
      -- --------------------------------------------------------------------------
      ELSIF(data_clk = '0' AND data_clk_prev = '1') THEN  
        CASE state IS
          WHEN start =>                  
            IF(scl_ena = '0') THEN                  -- 如果是新的传输（非重复起始）
              scl_ena <= '1';                       -- 使能SCL输出
              ack_error <= '0';                     -- 清除应答错误标志
            END IF;
            
          WHEN slv_ack1 =>                          -- 接收从设备对地址的应答
            IF(sda /= '0' OR ack_error = '1') THEN  -- 如果SDA不是低电平(NACK)，或之前已有错误
              ack_error <= '1';                     -- 设置错误标志
            END IF;
            
          WHEN rd =>                                -- 接收从设备数据
            data_rx(bit_cnt) <= sda;                -- 在SCL高电平期间读取SDA上的数据位
            
          WHEN slv_ack2 =>                          -- 接收从设备对写数据的应答
            IF(sda /= '0' OR ack_error = '1') THEN  -- 如果SDA不是低电平(NACK)，或之前已有错误
              ack_error <= '1';                     -- 设置错误标志
            END IF;
            
          WHEN stop =>
            scl_ena <= '0';                         -- 禁用SCL输出，使其变为高阻态
            
          WHEN OTHERS =>
            NULL;
        END CASE;
      END IF;
    END IF;
  END PROCESS;  

  --================================================================================
  -- SDA 输出逻辑
  -- 功能: 根据当前状态控制SDA线的行为
  -- 1. 在start状态，SDA在SCL高电平时由高变低，产生起始条件。
  -- 2. 在stop状态，SDA在SCL高电平时由低变高，产生停止条件。
  -- 3. 在其他状态，SDA由内部信号sda_int驱动。
  --================================================================================
  WITH state SELECT
    sda_ena_n <= data_clk_prev WHEN start,     -- 起始: scl_clk为高(data_clk_prev=1)时, sda_ena_n=1->0 (SDA拉低)
                 NOT data_clk_prev WHEN stop,  -- 停止: scl_clk为高(data_clk_prev=1)时, sda_ena_n=0->1 (SDA释放)
                 sda_int WHEN OTHERS;          -- 其他: 由内部逻辑决定SDA
      
  --================================================================================
  -- SCL 和 SDA 三态门输出
  -- 功能: 将内部SCL和SDA信号连接到物理引脚
  -- 'Z' 表示高阻态，'0' 表示驱动为低电平
  --================================================================================
  scl <= '0' WHEN (scl_ena = '1' AND scl_clk = '0') ELSE 'Z'; -- 当scl_ena有效且内部时钟为低时，将SCL拉低；否则高阻
  sda <= '0' WHEN sda_ena_n = '0' ELSE 'Z'; -- 当sda_ena_n为低时，将SDA拉低；否则高阻
  
END logic;
