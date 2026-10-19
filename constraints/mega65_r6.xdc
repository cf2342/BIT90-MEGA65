# R6 pins from the user's working Nascom2 R6 project.
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports CLK_IN]
create_clock -period 10.000 -name CLK_IN [get_ports CLK_IN]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports reset_button]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports led]
# MEGA65 keyboard serial matrix and RGB LED chain.
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports kb_io0]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports kb_io1]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports kb_io2]
set_property -dict {PACKAGE_PIN W1 IOSTANDARD TMDS_33} [get_ports TMDS_clk_p]
set_property -dict {PACKAGE_PIN Y1 IOSTANDARD TMDS_33} [get_ports TMDS_clk_n]
set_property -dict {PACKAGE_PIN AA1 IOSTANDARD TMDS_33} [get_ports {TMDS_data_p[0]}]
set_property -dict {PACKAGE_PIN AB1 IOSTANDARD TMDS_33} [get_ports {TMDS_data_n[0]}]
set_property -dict {PACKAGE_PIN AB3 IOSTANDARD TMDS_33} [get_ports {TMDS_data_p[1]}]
set_property -dict {PACKAGE_PIN AB2 IOSTANDARD TMDS_33} [get_ports {TMDS_data_n[1]}]
set_property -dict {PACKAGE_PIN AA5 IOSTANDARD TMDS_33} [get_ports {TMDS_data_p[2]}]
set_property -dict {PACKAGE_PIN AB5 IOSTANDARD TMDS_33} [get_ports {TMDS_data_n[2]}]
set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS33} [get_ports hdmi_enable_n]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports hdmi_hiz]
# MEGA65 R6 AK4432VT audio DAC for the 3.5 mm jack.
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports audio_mclk_o]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports audio_bick_o]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports audio_sdti_o]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports audio_lrclk_o]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports audio_pdn_n_o]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports audio_i2cfil_o]
set_property -dict {PACKAGE_PIN L6 IOSTANDARD LVCMOS33} [get_ports audio_scl_io]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports audio_sda_io]

# MEGA65 R6 external SD slot in SPI mode; sd2reset is DAT3/CS.
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports sd2Clock]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports sd2reset]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports sd2MISO]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports sd2MOSI]
set_property -dict {PACKAGE_PIN H3 IOSTANDARD LVCMOS33} [get_ports {sd2_dat[1]}]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD LVCMOS33} [get_ports {sd2_dat[2]}]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports sd2CD]
set_property PULLUP true [get_ports sd2MISO]
set_property PULLUP true [get_ports sd2CD]

# MEGA65 R6 internal SD slot below the bottom cover, in SPI mode.
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports sdClock]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports sdreset]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports sdMISO]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports sdMOSI]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports sdCD]
set_property PULLUP true [get_ports sdMISO]
set_property PULLUP true [get_ports sdCD]

# R6 direct joystick inputs (active low) and shared cartridge/joystick interface.
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports cart_and_joy_en]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fa_down_n_i]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fa_fire_n_i]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fa_left_n_i]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fa_right_n_i]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fa_up_n_i]
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fb_down_n_i]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fb_fire_n_i]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fb_left_n_i]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fb_right_n_i]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports fb_up_n_i]
set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33} [get_ports fa_down_drain_n]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports fa_fire_drain_n]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports fa_left_drain_n]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports fa_right_drain_n]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports fa_up_drain_n]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports fb_down_drain_n]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVCMOS33} [get_ports fb_fire_drain_n]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports fb_left_drain_n]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports fb_right_drain_n]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports fb_up_drain_n]
# Asynchronous assertion, synchronous reset release per domain.
set_false_path -from [get_ports reset_button]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *rst_pipe_reg*/PRE}]
# Asynchronous control paths enter two-stage synchronizers. The audio mailbox
# buses are held stable by their associated request toggle before the receiving
# domain captures them, so only their first destination registers are exempted.
set_false_path -to [get_pins -hierarchical -filter {
    NAME =~ *req_meta_reg/D ||
    NAME =~ *request_meta_reg/D ||
    NAME =~ *ack_meta_reg/D ||
    NAME =~ *toggle_meta_reg/D ||
    NAME =~ *data_l_meta_reg*/D ||
    NAME =~ *data_r_meta_reg*/D ||
    NAME =~ *pcm_l_sync_reg*/D ||
    NAME =~ *pcm_r_sync_reg*/D ||
    NAME =~ *overlay_meta_reg/D ||
    NAME =~ *config_meta_reg*/D ||
    NAME =~ *page_meta_reg*/D ||
    NAME =~ *menu_meta_reg*/D ||
    NAME =~ *xbas_meta_reg/D ||
    NAME =~ *browser_row_meta_reg*/D ||
    NAME =~ *sd_status_meta_reg*/D ||
    NAME =~ *cart_status_meta_reg*/D ||
    NAME =~ *names_valid_meta_reg*/D ||
    NAME =~ *names_meta_reg*/D ||
    NAME =~ *keyboard_meta_reg*/D ||
    NAME =~ *caps_meta_reg/D ||
    NAME =~ *save_debug_meta_reg*/D ||
    NAME =~ *save_name_meta_reg*/D ||
    NAME =~ *save_cursor_meta_reg*/D ||
    NAME =~ *file_count_meta_reg*/D ||
    NAME =~ *page_base_meta_reg*/D ||
    NAME =~ *joy_a_meta_reg*/D ||
    NAME =~ *joy_b_meta_reg*/D
}]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# MEGA65 analogue VGA connector; 8-bit RGB plus negative sync from the
# framebuffer's 720x576p50 raster.
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {vga_red[0]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {vga_red[1]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {vga_red[2]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {vga_red[3]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {vga_red[4]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS33} [get_ports {vga_red[5]}]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS33} [get_ports {vga_red[6]}]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS33} [get_ports {vga_red[7]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {vga_green[0]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {vga_green[1]}]
set_property -dict {PACKAGE_PIN AA15 IOSTANDARD LVCMOS33} [get_ports {vga_green[2]}]
set_property -dict {PACKAGE_PIN AB15 IOSTANDARD LVCMOS33} [get_ports {vga_green[3]}]
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS33} [get_ports {vga_green[4]}]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS33} [get_ports {vga_green[5]}]
set_property -dict {PACKAGE_PIN AA13 IOSTANDARD LVCMOS33} [get_ports {vga_green[6]}]
set_property -dict {PACKAGE_PIN AB13 IOSTANDARD LVCMOS33} [get_ports {vga_green[7]}]
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports {vga_blue[0]}]
set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports {vga_blue[1]}]
set_property -dict {PACKAGE_PIN AB12 IOSTANDARD LVCMOS33} [get_ports {vga_blue[2]}]
set_property -dict {PACKAGE_PIN AA11 IOSTANDARD LVCMOS33} [get_ports {vga_blue[3]}]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS33} [get_ports {vga_blue[4]}]
set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports {vga_blue[5]}]
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS33} [get_ports {vga_blue[6]}]
set_property -dict {PACKAGE_PIN AA10 IOSTANDARD LVCMOS33} [get_ports {vga_blue[7]}]
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports vga_hsync]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports vga_vsync]
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS33} [get_ports vdac_clk]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports vdac_sync_n]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports vdac_blank_n]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports vdac_psave_n]


