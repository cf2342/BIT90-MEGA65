library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- BIT90 adapter for the SN76489AN. CPU writes are captured at 100 MHz and
-- translated into the two enabled write cycles plus release cycle required by
-- the PSG core. BIT90 OUT instructions are far enough apart that one slot is
-- sufficient.
entity bit90_sn76489 is
  port(
    clk          : in  std_logic;
    reset        : in  std_logic;
    psg_ce       : in  std_logic;
    write_strobe : in  std_logic;
    data_in      : in  std_logic_vector(7 downto 0);
    pcm_out      : out std_logic_vector(15 downto 0);
    busy_o       : out std_logic
  );
end entity;

architecture rtl of bit90_sn76489 is
  signal data_latch : std_logic_vector(7 downto 0) := (others => '0');
  signal busy, write_active : std_logic := '0';
  signal enabled_writes : natural range 0 to 1 := 0;
  signal pcm14 : unsigned(13 downto 0);
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        busy <= '0';
        write_active <= '0';
        enabled_writes <= 0;
      elsif busy = '0' then
        if write_strobe = '1' then
          data_latch <= data_in;
          busy <= '1';
          write_active <= '1';
          enabled_writes <= 0;
        end if;
      elsif psg_ce = '1' then
        if write_active = '1' then
          if enabled_writes = 0 then
            enabled_writes <= 1;
          else
            -- The core commits the byte on this second enabled cycle.
            write_active <= '0';
          end if;
        else
          -- One enabled cycle with WR_n high returns the core to IO_IDLE.
          busy <= '0';
          enabled_writes <= 0;
        end if;
      end if;
    end if;
  end process;

  psg: entity work.sn76489_audio
    generic map(FAST_IO_G => '1', MIN_PERIOD_CNT_G => 6)
    port map(
      clk_i => clk, en_clk_psg_i => psg_ce,
      ce_n_i => not write_active, wr_n_i => not write_active, ready_o => open,
      data_i => data_latch,
      ch_a_o => open, ch_b_o => open, ch_c_o => open, noise_o => open,
      mix_audio_o => open, pcm14s_o => pcm14);

  -- Signed two's-complement 14-bit audio, left-aligned for the HDMI and DAC
  -- 16-bit PCM interfaces.
  pcm_out <= std_logic_vector(pcm14) & "00";
  busy_o <= busy;
end architecture;
