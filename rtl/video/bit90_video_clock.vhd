library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.vcomponents.all;

entity bit90_video_clock is
  port(clk100, reset : in std_logic; pixel_clk, serial_clk, locked : out std_logic);
end;
architecture rtl of bit90_video_clock is
  signal fb, fbb, p, s : std_logic;
begin
  -- VCO = 100*27/4 = 675 MHz. 675/25 = 27; 675/5 = 135.
  mmcm: MMCME2_BASE
    generic map(CLKIN1_PERIOD=>10.0, DIVCLK_DIVIDE=>4,
      CLKFBOUT_MULT_F=>27.0, CLKOUT0_DIVIDE_F=>25.0, CLKOUT1_DIVIDE=>5)
    port map(CLKIN1=>clk100, CLKFBIN=>fbb, RST=>reset, PWRDWN=>'0',
      CLKFBOUT=>fb, CLKFBOUTB=>open, CLKOUT0=>p, CLKOUT0B=>open,
      CLKOUT1=>s, CLKOUT1B=>open, CLKOUT2=>open, CLKOUT2B=>open,
      CLKOUT3=>open, CLKOUT3B=>open, CLKOUT4=>open, CLKOUT5=>open,
      CLKOUT6=>open, LOCKED=>locked);
  bfb: BUFG port map(I=>fb,O=>fbb);
  bp: BUFG port map(I=>p,O=>pixel_clk);
  bs: BUFG port map(I=>s,O=>serial_clk);
end;
