library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Board-independent TMS9929A wrapper. VRAM has one synchronous read cycle.
-- CPU port bit 7 is the MSB; VDP18's ascending vectors map positionally.
entity bit90_vdp is
  port (
    clk : in std_logic;
    reset : in std_logic;
    ce_10m7 : in std_logic;
    rd_n, wr_n, mode : in std_logic;
    din : in std_logic_vector(7 downto 0);
    dout : out std_logic_vector(7 downto 0);
    irq_n : out std_logic;
    pixel_ce : out std_logic;
    pixel_x : out integer range 0 to 255;
    pixel_y : out integer range 0 to 191;
    color : out std_logic_vector(3 downto 0);
    hs_n, vs_n, hblank, vblank : out std_logic;
    debug_addr : in std_logic_vector(3 downto 0) := x"1";
    debug_data : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of bit90_vdp is
  type ram_t is array(0 to 16383) of std_logic_vector(7 downto 0);
  signal ram : ram_t;
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
  signal a : std_logic_vector(13 downto 0);
  signal wd, q : std_logic_vector(7 downto 0);
  signal we : std_logic;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      q <= ram(to_integer(unsigned(a)));
      if we = '1' then ram(to_integer(unsigned(a))) <= wd; end if;
    end if;
  end process;
  vdp: entity work.vdp18_core
    generic map(is_pal_g => 1, compat_rgb_g => 0)
    port map(clk_i => clk, clk_en_10m7_i => ce_10m7, reset_n_i => not reset,
      csr_n_i => rd_n, csw_n_i => wr_n, mode_i => mode,
      int_n_o => irq_n, cd_i => din, cd_o => dout,
      vram_we_o => we, vram_a_o => a, vram_d_o => wd, vram_d_i => q,
      pixel_ce_o => pixel_ce, pixel_x_o => pixel_x, pixel_y_o => pixel_y,
      border_i => '1', col_o => color, rgb_r_o => open, rgb_g_o => open,
      rgb_b_o => open, hsync_n_o => hs_n, vsync_n_o => vs_n,
      blank_n_o => open, hblank_o => hblank, vblank_o => vblank,
      comp_sync_n_o => open, ss_a_i => x"4" & debug_addr, ss_d_o => debug_data);
end architecture;



