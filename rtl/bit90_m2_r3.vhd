library ieee;
use ieee.std_logic_1164.all;

-- MEGA65 R3/R3A board wrapper. The BIT90 implementation remains shared with
-- the R6 build; only reset, HDMI level control and analogue audio differ.
entity bit90_m2_r3 is
  port(
    CLK_IN : in std_logic;
    max10_tx : in std_logic;
    max10_rx, reset_from_max10 : out std_logic;
    kb_io0, kb_io1 : out std_logic;
    kb_io2 : in std_logic;
    led : out std_logic;
    TMDS_clk_p, TMDS_clk_n : out std_logic;
    TMDS_data_p, TMDS_data_n : out std_logic_vector(0 to 2);
    hdmi_ls_oe, hdmi_ct_hpd : out std_logic;
    hdmi_hpd : in std_logic;
    pwm_l, pwm_r : out std_logic;
    vga_red, vga_green, vga_blue : out std_logic_vector(7 downto 0);
    vga_hsync, vga_vsync : out std_logic;
    vdac_clk, vdac_sync_n, vdac_blank_n : out std_logic;
    sd2Clock, sd2reset, sd2MOSI : out std_logic;
    sd2MISO, sd2CD : in std_logic;
    sdClock, sdreset, sdMOSI : out std_logic;
    sdMISO, sdCD : in std_logic;
    fa_down_n_i, fa_fire_n_i, fa_left_n_i, fa_right_n_i, fa_up_n_i : in std_logic;
    fb_down_n_i, fb_fire_n_i, fb_left_n_i, fb_right_n_i, fb_up_n_i : in std_logic
  );
end entity;

architecture rtl of bit90_m2_r3 is
  signal r3_reset_n : std_logic := '1';
  signal r3_reset_active_high : std_logic;
begin
  -- R3/R3A HDMI level shifter controls, identical to the proven Nascom2 R3
  -- wrapper. HPD is supplied by the display and needs no core-side action.
  hdmi_ls_oe <= '1';
  hdmi_ct_hpd <= '1';
  r3_reset_active_high <= not r3_reset_n;

  max10 : entity work.mega65_r3_max10
    port map(
      protocol_clock=>CLK_IN, system_clock=>CLK_IN,
      max10_rx=>max10_rx, max10_tx=>max10_tx,
      max10_clkandsync=>reset_from_max10, reset_n=>r3_reset_n);

  u_board_common : entity work.bit90_m2_r6
    generic map(G_BOARD=>"MEGA65_R3")
    port map(
      CLK_IN=>CLK_IN, reset_button=>r3_reset_active_high,
      kb_io0=>kb_io0, kb_io1=>kb_io1, kb_io2=>kb_io2, led=>led,
      TMDS_clk_p=>TMDS_clk_p, TMDS_clk_n=>TMDS_clk_n,
      TMDS_data_p=>TMDS_data_p, TMDS_data_n=>TMDS_data_n,
      hdmi_enable_n=>open, hdmi_hiz=>open,
      vga_red=>vga_red, vga_green=>vga_green, vga_blue=>vga_blue,
      vga_hsync=>vga_hsync, vga_vsync=>vga_vsync,
      vdac_clk=>vdac_clk, vdac_sync_n=>vdac_sync_n,
      vdac_blank_n=>vdac_blank_n, vdac_psave_n=>open,
      audio_mclk_o=>open, audio_bick_o=>open, audio_sdti_o=>open,
      audio_lrclk_o=>open, audio_pdn_n_o=>open,
      audio_i2cfil_o=>pwm_l, audio_scl_io=>pwm_r, audio_sda_io=>open,
      sd2Clock=>sd2Clock, sd2reset=>sd2reset, sd2MOSI=>sd2MOSI,
      sd2MISO=>sd2MISO, sd2CD=>sd2CD, sd2_dat=>open,
      sdClock=>sdClock, sdreset=>sdreset, sdMOSI=>sdMOSI,
      sdMISO=>sdMISO, sdCD=>sdCD,
      fa_down_n_i=>fa_down_n_i, fa_fire_n_i=>fa_fire_n_i,
      fa_left_n_i=>fa_left_n_i, fa_right_n_i=>fa_right_n_i,
      fa_up_n_i=>fa_up_n_i,
      fb_down_n_i=>fb_down_n_i, fb_fire_n_i=>fb_fire_n_i,
      fb_left_n_i=>fb_left_n_i, fb_right_n_i=>fb_right_n_i,
      fb_up_n_i=>fb_up_n_i,
      cart_and_joy_en=>open,
      fa_down_drain_n=>open, fa_fire_drain_n=>open,
      fa_left_drain_n=>open, fa_right_drain_n=>open, fa_up_drain_n=>open,
      fb_down_drain_n=>open, fb_fire_drain_n=>open,
      fb_left_drain_n=>open, fb_right_drain_n=>open, fb_up_drain_n=>open);
end architecture;
