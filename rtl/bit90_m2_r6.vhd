library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tyto_types_pkg.all;
use work.bit90_sd_file_pkg.all;
use work.vfat_name_pkg.all;
library unisim;
use unisim.vcomponents.all;

entity bit90_m2_r6 is
  generic(G_BOARD : string := "MEGA65_R6");
  port(CLK_IN, reset_button : in std_logic;
       kb_io0, kb_io1 : out std_logic;
       kb_io2 : in std_logic;
       led : out std_logic;
       TMDS_clk_p, TMDS_clk_n : out std_logic;
       TMDS_data_p, TMDS_data_n : out std_logic_vector(0 to 2);
       hdmi_enable_n, hdmi_hiz : out std_logic;
       vga_red, vga_green, vga_blue : out std_logic_vector(7 downto 0);
       vga_hsync, vga_vsync : out std_logic;
       vdac_clk, vdac_sync_n, vdac_blank_n, vdac_psave_n : out std_logic;
       audio_mclk_o, audio_bick_o, audio_sdti_o : out std_logic;
       audio_lrclk_o, audio_pdn_n_o, audio_i2cfil_o : out std_logic;
       audio_scl_io, audio_sda_io : inout std_logic;
       sd2Clock, sd2reset, sd2MOSI : out std_logic;
       sd2MISO, sd2CD : in std_logic;
       sd2_dat : out std_logic_vector(2 downto 1);
       sdClock, sdreset, sdMOSI : out std_logic;
       sdMISO, sdCD : in std_logic;
       fa_down_n_i, fa_fire_n_i, fa_left_n_i, fa_right_n_i, fa_up_n_i : in std_logic;
       fb_down_n_i, fb_fire_n_i, fb_left_n_i, fb_right_n_i, fb_up_n_i : in std_logic;
       cart_and_joy_en : out std_logic;
       fa_down_drain_n, fa_fire_drain_n, fa_left_drain_n : out std_logic;
       fa_right_drain_n, fa_up_drain_n : out std_logic;
       fb_down_drain_n, fb_fire_drain_n, fb_left_drain_n : out std_logic;
       fb_right_drain_n, fb_up_drain_n : out std_logic);
end;

architecture rtl of bit90_m2_r6 is
  signal pclk, sclk, locked, arst, rst, prst : std_logic;
  signal srst_pipe, prst_pipe : std_logic_vector(2 downto 0) := (others=>'1');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of srst_pipe, prst_pipe : signal is "TRUE";
  signal accumulator : natural range 0 to 99999999 := 0;
  signal vdp_ce, cpu_ce : std_logic := '0';
  signal cpu_div : natural range 0 to 2 := 0;
  signal rd_n, wr_n, mode, irq_n, pixel_ce : std_logic;
  signal din, dout : std_logic_vector(7 downto 0);
  signal color : std_logic_vector(3 downto 0);
  signal px : integer range 0 to 255;
  signal py : integer range 0 to 191;
  signal red, green, blue : std_logic_vector(7 downto 0);
  signal hs, vs, de, tclk : std_logic;
  signal serial : std_logic_vector(0 to 2);
  signal encoded : slv10_vector(0 to 2);
  signal raster_x : unsigned(10 downto 0);
  signal raster_y : unsigned(9 downto 0);
  signal keyboard_rows, system_keyboard_rows : std_logic_vector(63 downto 0);
  -- MEGA65 joystick contacts are asynchronous and active low. The vector
  -- order is fire, right, left, down, up, matching the R6 wrapper signals.
  signal joy_a_meta, joy_a_sync : std_logic_vector(4 downto 0) := (others=>'1');
  signal joy_b_meta, joy_b_sync : std_logic_vector(4 downto 0) := (others=>'1');
  signal bit90_joy1, bit90_joy2 : std_logic_vector(7 downto 0) := x"FF";
  attribute ASYNC_REG of joy_a_meta, joy_a_sync, joy_b_meta, joy_b_sync : signal is "TRUE";
  signal help_n, escape_n, up_n, down_n, left_n, right_n, return_n : std_logic;
  signal caps_n : std_logic;
  signal overlay_enable, config_reset_req, core_rst : std_logic;
  signal overlay_page : std_logic_vector(1 downto 0);
  signal menu_selection : std_logic_vector(2 downto 0);
  signal selected_config, active_config : std_logic_vector(1 downto 0);
  signal selected_xbas, active_xbas : std_logic;
  signal browser_page_base : integer range 0 to SD_BROWSER_LAST_INDEX;
  signal browser_selected_row : integer range 0 to SD_BROWSER_PAGE_LAST;
  signal storage_reset_req, storage_reset : std_logic;
  signal sd_mux_reset, sd_mux_external_active : std_logic;
  signal sd_card_detect_n, sd_controller_miso : std_logic;
  signal sd_controller_sclk, sd_controller_mosi, sd_controller_cs_n : std_logic;
  signal sd_init_busy, sd_init_done, sd_init_error : std_logic;
  signal sd_read_busy, sd_read_done, sd_read_error : std_logic;
  signal sd_error_code : std_logic_vector(3 downto 0);
  signal sd_state_code : std_logic_vector(7 downto 0);
  signal sd_block_addressing, sd_media_dir_found, sd_has_files : std_logic;
  signal sd_file_count : integer range 0 to SD_BROWSER_MAX_FILES;
  signal sd_total_file_count : integer range 0 to 255;
  signal sd_page_valid : sd_page_valid_array_t;
  signal sd_page_name : sd_page_name_array_t;
  signal sd_page_display_name : sd_page_display_name_array_t;
  signal sd_selected_valid : std_logic;
  signal sd_selected_name : std_logic_vector(87 downto 0);
  signal sd_selected_cluster, sd_selected_size : std_logic_vector(31 downto 0);
  signal system_cpu_ce : std_logic;
  signal browser_select_req, save_basic_req : std_logic;
  signal raw_read_start, raw_read_raw, raw_read_wr, raw_read_ready : std_logic;
  signal raw_read_cluster, raw_read_size : std_logic_vector(31 downto 0);
  signal raw_read_addr : std_logic_vector(15 downto 0);
  signal raw_read_data : std_logic_vector(7 downto 0);
  signal cart_load_start, cart_load_busy, cart_load_done, cart_load_error : std_logic;
  signal cart_file_start : std_logic;
  signal cart_file_cluster, cart_file_size : std_logic_vector(31 downto 0);
  signal tape_load_start, tape_load_busy, tape_load_done, tape_load_error : std_logic;
  signal tape_file_start, tape_file_ready, tape_bit, tape_read_strobe, tape_reset : std_logic;
  signal tape_playing, drive_led_activity, front_drive_led : std_logic := '0';
  signal cfg_load_start_q, cfg_load_busy, cfg_load_done, cfg_load_error : std_logic := '0';
  signal cfg_loaded_valid, cfg_loaded_xbas : std_logic := '0';
  signal cfg_loaded_ram : std_logic_vector(1 downto 0) := "00";
  signal cfg_save_start_q, cfg_save_busy, cfg_save_done, cfg_save_error : std_logic := '0';
  signal cfg_load_pending, cfg_save_pending : std_logic := '0';
  signal cfg_apply_q, cfg_reset_previous, cfg_ignore_reset, cfg_valid_seen : std_logic := '0';
  signal tape_led_div : unsigned(23 downto 0) := (others=>'0');
  signal tape_file_cluster, tape_file_size : std_logic_vector(31 downto 0);
  signal tape_load_status : std_logic_vector(3 downto 0);
  signal media_kind : std_logic_vector(1 downto 0);
  signal bas_load_start, bas_load_busy, bas_load_done, bas_load_error, bas_reset : std_logic;
  signal bas_file_start, bas_wr, system_load_wr : std_logic;
  signal bas_file_cluster, bas_file_size : std_logic_vector(31 downto 0);
  signal bas_addr, system_load_addr : std_logic_vector(15 downto 0);
  signal bas_data, system_load_data : std_logic_vector(7 downto 0);
  signal bas_load_status : std_logic_vector(3 downto 0);
  signal media_load_busy, media_load_error : std_logic;
  signal media_load_status : std_logic_vector(3 downto 0);
  signal cart_load_status : std_logic_vector(3 downto 0);
  signal cart_wr, cart_present, cart_reset_req : std_logic;
  signal system_cold_start : std_logic;
  signal cart_addr : std_logic_vector(14 downto 0);
  signal cart_data : std_logic_vector(7 downto 0);
  signal cart_size : std_logic_vector(15 downto 0);
  signal psg_wr, psg_busy : std_logic;
  signal psg_data : std_logic_vector(7 downto 0);
  signal audio_pcm_16, overlay_audio_pcm, hdmi_pcm_l, hdmi_pcm_r : std_logic_vector(15 downto 0);
  signal audio_pdm_l, audio_pdm_r : std_logic;
  signal hdmi_pcm_valid : std_logic;
  type save_state_t is (SAVE_IDLE, SAVE_ARM_CHECK, SAVE_WAIT_CHECK,
                        SAVE_ARM_WRITE, SAVE_WAIT_WRITE);
  signal save_state : save_state_t := SAVE_IDLE;
  signal save_check_start_q, save_check_done, save_check_exists : std_logic := '0';
  signal save_check_can_create, save_check_can_allocate : std_logic := '0';
  signal save_write_start_q, save_write_busy, save_write_done, save_write_error : std_logic := '0';
  signal save_done_q, save_error_q, save_busy_ui : std_logic := '0';
  signal save_write_status : std_logic_vector(3 downto 0) := (others=>'0');
  signal save_sectors_left : std_logic_vector(7 downto 0) := (others=>'0');
  signal save_debug_q : std_logic_vector(15 downto 0) := (others=>'0');
  signal save_name : vfat_save_name_t := (others=>'0');
  signal save_name_cursor : integer range 0 to VFAT_SAVE_BASE_CHARS-1 := 0;
  signal save_start_addr, save_end_addr, save_mem_addr : std_logic_vector(15 downto 0) := (others=>'0');
  signal save_mem_data : std_logic_vector(7 downto 0);
  signal bit_load_start, bit_load_busy, bit_load_done, bit_load_error : std_logic := '0';
  signal bit_file_start, bit_seen_busy : std_logic := '0';
  signal bit_file_cluster, bit_file_size : std_logic_vector(31 downto 0) := (others=>'0');
  signal bit_header_bad : std_logic := '0';
  signal bit_start_addr, bit_end_addr : unsigned(15 downto 0) := (others=>'0');
  signal bit_mem_wr : std_logic := '0';
  signal bit_mem_addr : std_logic_vector(15 downto 0) := (others=>'0');
  signal bit_mem_data : std_logic_vector(7 downto 0) := (others=>'0');
  signal bit_reset_count : natural range 0 to 1023 := 0;
  signal bit_reset_req : std_logic;
begin
  clocking: entity work.bit90_video_clock
    port map(CLK_IN, '0', pclk, sclk, locked);
  arst <= reset_button or not locked;
  process(CLK_IN, arst)
  begin
    if arst='1' then srst_pipe <= (others=>'1');
    elsif rising_edge(CLK_IN) then srst_pipe <= srst_pipe(1 downto 0)&'0'; end if;
  end process;
  process(pclk, arst)
  begin
    if arst='1' then prst_pipe <= (others=>'1');
    elsif rising_edge(pclk) then prst_pipe <= prst_pipe(1 downto 0)&'0'; end if;
  end process;
  rst <= srst_pipe(2); prst <= prst_pipe(2);

  -- Register the live storage diagnostics in the source clock domain. The
  -- SD state decoder is otherwise a long combinational path into the pixel
  -- clock synchronizer and needlessly becomes a cross-clock timing path.
  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      if rst='1' then
        save_debug_q <= (others=>'0');
      else
        save_debug_q <= sd_state_code & save_sectors_left;
      end if;
    end if;
  end process;

  -- R4/R5/R6 share joystick and cartridge circuitry. Enable the interface
  -- and release every open-drain output because this core only reads sticks.
  cart_and_joy_en <= '1';
  fa_down_drain_n <= '1'; fa_fire_drain_n <= '1';
  fa_left_drain_n <= '1'; fa_right_drain_n <= '1'; fa_up_drain_n <= '1';
  fb_down_drain_n <= '1'; fb_fire_drain_n <= '1';
  fb_left_drain_n <= '1'; fb_right_drain_n <= '1'; fb_up_drain_n <= '1';

  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      if rst='1' then
        joy_a_meta <= (others=>'1'); joy_a_sync <= (others=>'1');
        joy_b_meta <= (others=>'1'); joy_b_sync <= (others=>'1');
      else
        joy_a_meta <= fa_fire_n_i & fa_right_n_i & fa_left_n_i &
                      fa_down_n_i & fa_up_n_i;
        joy_a_sync <= joy_a_meta;
        joy_b_meta <= fb_fire_n_i & fb_right_n_i & fb_left_n_i &
                      fb_down_n_i & fb_up_n_i;
        joy_b_sync <= joy_b_meta;
      end if;
    end if;
  end process;

  -- BIT90 controller bits: 0=up, 1=right, 2=down, 3=left, 6=fire.
  bit90_joy1 <= '1' & joy_a_sync(4) & "11" & joy_a_sync(2) &
                joy_a_sync(1) & joy_a_sync(3) & joy_a_sync(0);
  bit90_joy2 <= tape_bit & joy_b_sync(4) & "11" & joy_b_sync(2) &
                joy_b_sync(1) & joy_b_sync(3) & joy_b_sync(0);

  -- TMS9929A at 10.738635 MHz; the Z80 and SN76489 receive the same
  -- 3.579545 MHz enable, preserving the original fixed phase relationship.
  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      vdp_ce <= '0'; cpu_ce <= '0';
      if rst='1' then
        accumulator <= 0; cpu_div <= 0;
      else
        if accumulator >= 89261365 then
          accumulator <= accumulator-89261365;
          vdp_ce <= '1';
          if cpu_div=2 then cpu_div <= 0; cpu_ce <= '1';
          else cpu_div <= cpu_div+1;
          end if;
        else
          accumulator <= accumulator+10738635;
        end if;
      end if;
    end if;
  end process;

  front_drive_led <= drive_led_activity or cfg_save_busy or save_busy_ui;

  keyboard: entity work.bit90_keyboard
    port map(clk=>CLK_IN, reset=>rst, drive_led=>front_drive_led, kb_io0=>kb_io0, kb_io1=>kb_io1,
      kb_io2=>kb_io2, keyboard_rows=>keyboard_rows, caps_n=>caps_n,
      help_n=>help_n, escape_n=>escape_n, up_n=>up_n, down_n=>down_n, left_n=>left_n,
      right_n=>right_n, return_n=>return_n);

  config_control: entity work.bit90_config
    port map(clk=>CLK_IN, reset=>rst, help_n=>help_n, escape_n=>escape_n, up_n=>up_n,
      down_n=>down_n, left_n=>left_n, right_n=>right_n, return_n=>return_n,
      overlay_enable=>overlay_enable, overlay_page=>overlay_page,
      menu_selection=>menu_selection, browser_page_base=>browser_page_base,
      browser_selected_row=>browser_selected_row,
      browser_total_file_count=>sd_total_file_count,
      selected_config=>selected_config, active_config=>active_config,
      selected_xbas=>selected_xbas, active_xbas=>active_xbas,
      reset_req=>config_reset_req, storage_reset_req=>storage_reset_req,
      browser_select_req=>browser_select_req, save_basic_req=>save_basic_req,
      keyboard_state=>keyboard_rows, save_name=>save_name,
      save_name_cursor=>save_name_cursor, save_basic_busy=>save_busy_ui,
      browser_load_busy=>media_load_busy,
      browser_load_done=>(cart_load_done or tape_load_done or bas_load_done or bit_load_done),
      save_basic_done=>save_done_q,
      loaded_valid=>cfg_apply_q, loaded_config=>cfg_loaded_ram,
      loaded_xbas=>cfg_loaded_xbas);

  storage_reset <= rst or storage_reset_req or sd_mux_reset;
  media_kind <= "00" when overlay_page="01" else
                "01" when overlay_page="10" else "10";

  sd_slots: entity work.bit90_sd_slot_mux
    generic map(
      PREFER_EXTERNAL=>(G_BOARD/="MEGA65_R3"),
      INTERNAL_CD_RELIABLE=>(G_BOARD/="MEGA65_R3"),
      RESET_CYCLES=>16)
    port map(
      clk=>CLK_IN, reset=>rst, controller_init_error=>sd_init_error,
      internal_cd_n=>sdCD, internal_miso=>sdMISO,
      internal_sclk=>sdClock, internal_mosi=>sdMOSI, internal_cs_n=>sdreset,
      external_cd_n=>sd2CD, external_miso=>sd2MISO,
      external_sclk=>sd2Clock, external_mosi=>sd2MOSI, external_cs_n=>sd2reset,
      controller_cd_n=>sd_card_detect_n, controller_miso=>sd_controller_miso,
      controller_sclk=>sd_controller_sclk, controller_mosi=>sd_controller_mosi,
      controller_cs_n=>sd_controller_cs_n, controller_reset=>sd_mux_reset,
      external_active=>sd_mux_external_active);

  storage: entity work.bit90_sd_browser
    port map(clk=>CLK_IN, reset=>storage_reset, sd_cd=>sd_card_detect_n,
      sd_miso=>sd_controller_miso, sd_sclk=>sd_controller_sclk,
      sd_mosi=>sd_controller_mosi, sd_cs_n=>sd_controller_cs_n,
      media_kind=>media_kind,
      page_base_index=>browser_page_base,
      selected_page_row=>browser_selected_row,
      init_busy=>sd_init_busy, init_done=>sd_init_done,
      init_error=>sd_init_error, read_busy=>sd_read_busy,
      read_done=>sd_read_done, read_error=>sd_read_error,
      error_code=>sd_error_code, state_code=>sd_state_code,
      card_block_addressing=>sd_block_addressing,
      media_dir_found=>sd_media_dir_found, has_files=>sd_has_files,
      file_count=>sd_file_count, total_file_count=>sd_total_file_count,
      page_valid=>sd_page_valid, page_name=>sd_page_name,
      page_display_name=>sd_page_display_name,
      selected_valid=>sd_selected_valid, selected_name=>sd_selected_name,
      selected_cluster=>sd_selected_cluster, selected_size=>sd_selected_size,
      raw_read_start=>raw_read_start, raw_read_raw=>raw_read_raw, raw_read_ready=>raw_read_ready,
      raw_read_cluster=>raw_read_cluster,
      raw_read_size=>raw_read_size, raw_read_wr=>raw_read_wr,
      raw_read_addr=>raw_read_addr, raw_read_data=>raw_read_data,
      cfg_load_start=>cfg_load_start_q, cfg_load_busy=>cfg_load_busy,
      cfg_load_done=>cfg_load_done, cfg_load_error=>cfg_load_error,
      cfg_loaded_valid=>cfg_loaded_valid, cfg_loaded_ram=>cfg_loaded_ram,
      cfg_loaded_xbas=>cfg_loaded_xbas, cfg_save_start=>cfg_save_start_q,
      cfg_save_busy=>cfg_save_busy, cfg_save_done=>cfg_save_done,
      cfg_save_error=>cfg_save_error, cfg_save_ram=>active_config,
      cfg_save_xbas=>active_xbas,
      save_check_start=>save_check_start_q, save_name=>save_name,
      save_check_done=>save_check_done, save_check_exists=>save_check_exists,
      save_check_can_create=>save_check_can_create, save_check_can_allocate=>save_check_can_allocate,
      save_write_start=>save_write_start_q, save_write_start_addr=>save_start_addr,
      save_write_end_addr=>save_end_addr, save_write_busy=>save_write_busy,
      save_write_done=>save_write_done, save_write_error=>save_write_error,
      save_write_status=>save_write_status, save_debug_sectors_left=>save_sectors_left,
      save_mem_addr=>save_mem_addr,
      save_mem_data=>save_mem_data);
  -- Load BIT90.CFG once after card initialisation.  A RAM selection accepted
  -- with RETURN is committed after its reset pulse starts.  The reset caused
  -- by applying a loaded file is deliberately ignored by the save detector.
  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      cfg_load_start_q <= '0';
      cfg_save_start_q <= '0';
      cfg_apply_q <= '0';

      if rst = '1' then
        cfg_load_pending <= '1';
        cfg_save_pending <= '0';
        cfg_reset_previous <= '0';
        cfg_ignore_reset <= '0';
        cfg_valid_seen <= '0';
      elsif sd_card_detect_n = '1' then
        cfg_load_pending <= '1';
        cfg_save_pending <= '0';
        cfg_reset_previous <= '0';
        cfg_ignore_reset <= '0';
        cfg_valid_seen <= '0';
      else
        cfg_reset_previous <= config_reset_req;

        if cfg_load_busy = '1' or cfg_load_done = '1' or cfg_load_error = '1' then
          cfg_load_pending <= '0';
        end if;
        if cfg_save_busy = '1' or cfg_save_done = '1' or cfg_save_error = '1' then
          cfg_save_pending <= '0';
        end if;

        if cfg_loaded_valid = '1' and cfg_valid_seen = '0' then
          cfg_apply_q <= '1';
          cfg_valid_seen <= '1';
          cfg_ignore_reset <= '1';
        end if;

        if config_reset_req = '1' and cfg_reset_previous = '0' then
          if cfg_ignore_reset = '1' then
            cfg_ignore_reset <= '0';
          else
            cfg_save_pending <= '1';
          end if;
        end if;

        if cfg_load_pending = '1' and sd_init_done = '1' and
           cfg_load_busy = '0' and cfg_save_busy = '0' and sd_read_busy = '0' then
          cfg_load_start_q <= '1';
        elsif cfg_save_pending = '1' and cfg_load_busy = '0' and
              cfg_save_busy = '0' and sd_read_busy = '0' then
          cfg_save_start_q <= '1';
        end if;
      end if;
    end if;
  end process;


  -- Save a stable snapshot of all CPU-visible RAM. The existing FAT32 writer
  -- stores it as an address-bearing BIT memory image, so loading restores both
  -- BASIC's workspace/pointers and the tokenized program bytes.
  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      save_check_start_q <= '0';
      save_write_start_q <= '0';
      save_done_q <= '0';
      if rst='1' then
        save_state <= SAVE_IDLE;
        save_error_q <= '0';
      else
        case save_state is
          when SAVE_IDLE =>
            if save_basic_req='1' and sd_init_done='1' then
              save_error_q <= '0';
              if active_config="00" then
                save_start_addr <= x"6000"; save_end_addr <= x"7FFF";
              elsif active_config="01" then
                save_start_addr <= x"7000"; save_end_addr <= x"BFFF";
              else
                save_start_addr <= x"7000"; save_end_addr <= x"FFFF";
              end if;
              save_check_start_q <= '1';
              save_state <= SAVE_ARM_CHECK;
            end if;
          when SAVE_ARM_CHECK =>
            if save_check_done='0' then
              save_state <= SAVE_WAIT_CHECK;
            end if;
          when SAVE_WAIT_CHECK =>
            if save_check_done='1' then
              if save_check_exists='1' or
                 (save_check_can_create='1' and save_check_can_allocate='1') then
                save_state <= SAVE_ARM_WRITE;
              else
                save_error_q <= '1';
                save_state <= SAVE_IDLE;
              end if;
            end if;
          when SAVE_ARM_WRITE =>
            -- Keep the request asserted until the backend acknowledges it
            -- with BUSY. ST_READ_READY may still be finishing a higher-priority
            -- browser/cache action and must not be allowed to lose a pulse.
            save_write_start_q <= '1';
            if save_write_busy='1' then
              save_state <= SAVE_WAIT_WRITE;
            elsif save_write_done='1' then
              save_done_q <= '1';
              save_state <= SAVE_IDLE;
            elsif save_write_error='1' then
              save_error_q <= '1';
              save_state <= SAVE_IDLE;
            end if;
          when SAVE_WAIT_WRITE =>
            if save_write_done='1' then
              save_done_q <= '1';
              save_state <= SAVE_IDLE;
            elsif save_write_error='1' then
              save_error_q <= '1';
              save_state <= SAVE_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
  sd2_dat <= "11";

  cart_load_start <= browser_select_req when overlay_page="10" else '0';
  cartridge_loader: entity work.bit90_cart_loader
    port map(clk=>CLK_IN, reset=>rst, start=>cart_load_start,
      selected_valid=>sd_selected_valid, selected_cluster=>sd_selected_cluster,
      selected_size=>sd_selected_size, file_read_busy=>sd_read_busy,
      file_read_done=>sd_read_done, file_read_error=>sd_read_error,
      file_read_wr=>raw_read_wr, file_read_addr=>raw_read_addr,
      file_read_data=>raw_read_data, file_start=>cart_file_start,
      file_cluster=>cart_file_cluster, file_size=>cart_file_size,
      cart_wr=>cart_wr, cart_addr=>cart_addr, cart_data=>cart_data,
      cart_present=>cart_present, cart_size=>cart_size,
      busy=>cart_load_busy, done=>cart_load_done, error=>cart_load_error,
      status=>cart_load_status, core_reset_req=>cart_reset_req);

  -- Blink DRIVE for the complete interval in which PCM samples are actually
  -- presented to the Z80. This is independent of waveform edges, so silence,
  -- synchronisation gaps and the end of the file remain unambiguous.
  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      if rst='1' or tape_playing='0' then
        tape_led_div <= (others=>'0');
        drive_led_activity <= '0';
      elsif tape_led_div = to_unsigned(12499999, tape_led_div'length) then
        tape_led_div <= (others=>'0');
        drive_led_activity <= not drive_led_activity;
      else
        tape_led_div <= tape_led_div + 1;
      end if;
    end if;
  end process;

  tape_load_start <= browser_select_req when overlay_page="01" else '0';
  tape_reset <= rst or storage_reset_req;
  tape_player: entity work.bit90_tape_player
    port map(clk=>CLK_IN, reset=>tape_reset, start=>tape_load_start,
      selected_valid=>sd_selected_valid, selected_cluster=>sd_selected_cluster,
      selected_size=>sd_selected_size, file_read_busy=>sd_read_busy,
      file_read_done=>sd_read_done, file_read_error=>sd_read_error,
      file_read_wr=>raw_read_wr, file_read_data=>raw_read_data,
      file_start=>tape_file_start, file_cluster=>tape_file_cluster,
      file_size=>tape_file_size, file_ready=>tape_file_ready,
      tape_read_strobe=>tape_read_strobe, tape_bit=>tape_bit,
      playing_o=>tape_playing,
      busy=>tape_load_busy, done=>tape_load_done, error=>tape_load_error,
      status=>tape_load_status);

  bas_load_start <= browser_select_req when overlay_page="11" and
                    sd_selected_name(23 downto 0)=x"424153" else '0';
  bit_load_start <= browser_select_req when overlay_page="11" and
                    sd_selected_name(23 downto 0)=x"424954" else '0';
  bas_reset <= rst or (storage_reset_req and overlay_page(1) and overlay_page(0));
  basic_loader: entity work.bit90_bas_loader
    port map(clk=>CLK_IN, reset=>bas_reset, start=>bas_load_start,
      ram_config=>active_config, selected_valid=>sd_selected_valid,
      selected_cluster=>sd_selected_cluster, selected_size=>sd_selected_size,
      file_read_busy=>sd_read_busy, file_read_done=>sd_read_done,
      file_read_error=>sd_read_error, file_read_wr=>raw_read_wr,
      file_read_addr=>raw_read_addr, file_read_data=>raw_read_data,
      file_start=>bas_file_start, file_cluster=>bas_file_cluster,
      file_size=>bas_file_size, mem_wr=>bas_wr, mem_addr=>bas_addr,
      mem_data=>bas_data, busy=>bas_load_busy, done=>bas_load_done,
      error=>bas_load_error, status=>bas_load_status);


  -- Compact BIT90 memory image: 16-byte B90B header followed by one
  -- contiguous RAM range. Header validation completes before payload byte 0.
  process(CLK_IN)
    variable payload_offset_v : unsigned(15 downto 0);
    variable target_addr_v : unsigned(15 downto 0);
    variable expected_size_v : unsigned(31 downto 0);
  begin
    if rising_edge(CLK_IN) then
      bit_file_start <= '0';
      bit_load_done <= '0';
      bit_mem_wr <= '0';
      if bit_reset_count /= 0 then
        bit_reset_count <= bit_reset_count - 1;
      end if;
      if rst='1' or storage_reset_req='1' then
        bit_load_busy <= '0';
        bit_load_error <= '0';
        bit_seen_busy <= '0';
        bit_header_bad <= '0';
        bit_start_addr <= (others=>'0');
        bit_end_addr <= (others=>'0');
        bit_reset_count <= 0;
      elsif bit_load_start='1' then
        if sd_selected_valid='1' and unsigned(sd_selected_size)>=to_unsigned(16,32) then
          bit_file_cluster <= sd_selected_cluster;
          bit_file_size <= sd_selected_size;
          bit_file_start <= '1';
          bit_load_busy <= '1';
          bit_load_error <= '0';
          bit_seen_busy <= '0';
          bit_header_bad <= '0';
          bit_start_addr <= (others=>'0');
          bit_end_addr <= (others=>'0');
        else
          bit_load_error <= '1';
        end if;
      elsif bit_load_busy='1' then
        if raw_read_wr='1' then
          case to_integer(unsigned(raw_read_addr)) is
            when 0 => if raw_read_data/=x"42" then bit_header_bad<='1'; end if;
            when 1 => if raw_read_data/=x"39" then bit_header_bad<='1'; end if;
            when 2 => if raw_read_data/=x"30" then bit_header_bad<='1'; end if;
            when 3 => if raw_read_data/=x"42" then bit_header_bad<='1'; end if;
            when 4 => if raw_read_data/=x"01" then bit_header_bad<='1'; end if;
            when 5 => if raw_read_data/=x"00" then bit_header_bad<='1'; end if;
            when 6 => bit_start_addr(7 downto 0) <= unsigned(raw_read_data);
            when 7 => bit_start_addr(15 downto 8) <= unsigned(raw_read_data);
            when 8 => bit_end_addr(7 downto 0) <= unsigned(raw_read_data);
            when 9 => bit_end_addr(15 downto 8) <= unsigned(raw_read_data);
            when 10 to 15 => null;
            when others =>
              payload_offset_v := unsigned(raw_read_addr)-to_unsigned(16,16);
              target_addr_v := bit_start_addr + payload_offset_v;
              if bit_header_bad='0' and bit_end_addr>=bit_start_addr and
                 target_addr_v>=bit_start_addr and target_addr_v<=bit_end_addr then
                bit_mem_wr <= '1';
                bit_mem_addr <= std_logic_vector(target_addr_v);
                bit_mem_data <= raw_read_data;
              else
                bit_header_bad <= '1';
              end if;
          end case;
        end if;
        if sd_read_busy='1' then
          bit_seen_busy <= '1';
        elsif bit_seen_busy='1' and sd_read_done='1' then
          expected_size_v := resize(bit_end_addr-bit_start_addr,32)+to_unsigned(17,32);
          bit_load_busy <= '0';
          if bit_header_bad='0' and bit_end_addr>=bit_start_addr and
             unsigned(bit_file_size)=expected_size_v then
            bit_load_done <= '1';
            -- A BIT image replaces the BASIC workspace and Z80 stack while
            -- the CPU is paused in the live line editor. Resume through the
            -- ROM's warm-start path so registers, stack and editor state are
            -- rebuilt around the restored program. Do not request a cold
            -- start: the B90B image contains the valid BIT90 warm marker.
            bit_reset_count <= 1023;
          else
            bit_load_error <= '1';
          end if;
        elsif sd_read_error='1' then
          bit_load_busy <= '0';
          bit_load_error <= '1';
        end if;
      end if;
    end if;
  end process;  raw_read_start <= tape_file_start or cart_file_start or bas_file_start or bit_file_start;
  raw_read_cluster <= tape_file_cluster when tape_load_busy='1' else
                      bit_file_cluster when bit_load_busy='1' else
                      bas_file_cluster when bas_load_busy='1' else cart_file_cluster;
  raw_read_size <= tape_file_size when tape_load_busy='1' else
                   bit_file_size when bit_load_busy='1' else
                   bas_file_size when bas_load_busy='1' else cart_file_size;
  raw_read_ready <= tape_file_ready when tape_load_busy='1' else '1';
  raw_read_raw <= '1';
  system_load_wr <= bit_mem_wr when bit_load_busy='1' else bas_wr;
  system_load_addr <= bit_mem_addr when bit_load_busy='1' else bas_addr;
  system_load_data <= bit_mem_data when bit_load_busy='1' else bas_data;
  bit_reset_req <= '1' when bit_reset_count /= 0 else '0';

  save_busy_ui <= '1' when save_state/=SAVE_IDLE or save_write_busy='1' else '0';
  media_load_busy <= save_busy_ui when overlay_page="00" and menu_selection="101" else
                     tape_load_busy when overlay_page="01" else
                     (bas_load_busy or bit_load_busy) when overlay_page="11" else cart_load_busy;
  media_load_error <= save_error_q when overlay_page="00" and menu_selection="101" else
                      tape_load_error when overlay_page="01" else
                      (bas_load_error or bit_load_error) when overlay_page="11" else cart_load_error;
  media_load_status <= x"1" when overlay_page="00" and menu_selection="101" and
                       (save_state=SAVE_ARM_CHECK or save_state=SAVE_WAIT_CHECK) else
                       x"2" when overlay_page="00" and menu_selection="101" and save_busy_ui='1' else
                       save_write_status when overlay_page="00" and menu_selection="101" else
                       tape_load_status when overlay_page="01" else
                       bas_load_status when overlay_page="11" else cart_load_status;

  core_rst <= rst or config_reset_req or cart_reset_req or bit_reset_req;
  system_cold_start <= config_reset_req or cart_reset_req;
  system_cpu_ce <= cpu_ce and not overlay_enable;
  system_keyboard_rows <= keyboard_rows when overlay_enable='0' else (others=>'1');

  system: entity work.bit90_system
    port map(clk=>CLK_IN, reset=>core_rst, cpu_ce=>system_cpu_ce,
      keyboard_rows=>system_keyboard_rows, joystick_1=>bit90_joy1,
      joystick_2_tape=>bit90_joy2,
      controller_irq_n=>'1', vdp_data_i=>dout, vdp_irq_n=>irq_n,
      vdp_rd_n=>rd_n, vdp_wr_n=>wr_n, vdp_mode=>mode, vdp_data_o=>din,
      psg_wr_o=>psg_wr, psg_data_o=>psg_data, tape_dac_o=>open,
      keyboard_row_o=>open, basic_rom_active_o=>open,
      expansion_enabled_o=>open, xbas_initialized_o=>open, cpu_pc_o=>open, debug_cpu_a_o=>open,
      debug_cpu_do_o=>open, debug_iorq_n_o=>open, debug_wr_n_o=>open,
      tape_read_strobe_o=>tape_read_strobe,
      ram_config=>active_config, xbas_enable=>active_xbas,
      cold_start=>system_cold_start,
      cart_load_wr=>cart_wr, cart_load_addr=>cart_addr,
      cart_load_data=>cart_data, cart_present=>cart_present,
      cart_size=>cart_size, bas_load_wr=>system_load_wr, bas_load_addr=>system_load_addr,
      bas_load_data=>system_load_data, save_read_addr=>save_mem_addr,
      save_read_data=>save_mem_data);

  sound: entity work.bit90_sn76489
    port map(clk=>CLK_IN, reset=>core_rst, psg_ce=>cpu_ce,
      write_strobe=>psg_wr, data_in=>psg_data,
      pcm_out=>audio_pcm_16, busy_o=>psg_busy);

  -- The CPU is paused while an overlay is visible. Silence both physical
  -- outputs as well so a sustained PSG state cannot produce stray tones.
  overlay_audio_pcm <= (others=>'0') when overlay_enable='1' else audio_pcm_16;

  -- R6 headphone jack: AK4432VT, 48-kHz stereo with the mono PSG on both sides.
  jack_audio: entity work.ak4432_audio
    port map(clk100=>CLK_IN, reset=>arst, pcm_l=>overlay_audio_pcm, pcm_r=>overlay_audio_pcm,
      audio_mclk_o=>audio_mclk_o, audio_bick_o=>audio_bick_o,
      audio_sdti_o=>audio_sdti_o, audio_lrclk_o=>audio_lrclk_o,
      audio_pdn_n_o=>audio_pdn_n_o, audio_pdm_l_o=>audio_pdm_l, audio_pdm_r_o=>audio_pdm_r);
  audio_i2cfil_o <= audio_pdm_l when G_BOARD="MEGA65_R3" else '0';
  audio_scl_io <= audio_pdm_r when G_BOARD="MEGA65_R3" else 'Z';
  audio_sda_io <= 'Z';

  vdp: entity work.bit90_vdp
    port map(CLK_IN,core_rst,vdp_ce,rd_n,wr_n,mode,din,dout,irq_n,
      pixel_ce,px,py,color,open,open,open,open,x"1",open);
  display: entity work.bit90_framebuffer
    port map(src_clk=>CLK_IN, src_reset=>core_rst, enabled=>not core_rst,
      pixel_ce=>pixel_ce, pixel_x=>px, pixel_y=>py, color=>color,
      pix_clk=>pclk, pix_reset=>prst, red=>red, green=>green, blue=>blue,
      hs_n=>hs, vs_n=>vs, de=>de, overlay_enable=>overlay_enable,
      overlay_page=>overlay_page, menu_selection=>menu_selection,
      ram_config=>selected_config, xbas_enable=>selected_xbas,
      browser_selected_row=>browser_selected_row,
      browser_file_count=>sd_file_count, browser_page_base=>browser_page_base,
      sd_card_detect_n=>sd_card_detect_n, sd_init_busy=>sd_init_busy,
      sd_init_done=>sd_init_done, sd_init_error=>sd_init_error,
      sd_read_busy=>sd_read_busy, sd_read_done=>sd_read_done,
      sd_read_error=>sd_read_error, media_dir_found=>sd_media_dir_found,
      cart_load_busy=>media_load_busy, cart_load_error=>media_load_error,
      cart_load_status=>media_load_status, save_debug=>save_debug_q,
      save_name=>save_name, save_name_cursor=>save_name_cursor,
      media_page_valid=>sd_page_valid, media_page_display_name=>sd_page_display_name,
      keyboard_state=>keyboard_rows, caps_state_n=>caps_n,
      raster_x=>raster_x, raster_y=>raster_y);

  hdmi_audio_cdc: entity work.audio_pcm_cdc
    generic map(source_clock_hz=>100000000, sample_rate_hz=>48000)
    port map(source_clk=>CLK_IN, source_reset=>rst,
      source_pcm_l=>overlay_audio_pcm, source_pcm_r=>overlay_audio_pcm,
      destination_clk=>pclk, destination_reset=>prst,
      destination_pcm_l=>hdmi_pcm_l, destination_pcm_r=>hdmi_pcm_r,
      destination_valid=>hdmi_pcm_valid);

  hdmi: entity work.hdmi_proven_tx
    port map(PixelClk=>pclk, reset=>prst, audio_enable=>'1',
      pcm_l=>hdmi_pcm_l, pcm_r=>hdmi_pcm_r, pcm_valid=>hdmi_pcm_valid,
      red=>red, green=>green, blue=>blue, hsync=>hs, vsync=>vs, de=>de,
      x_pos=>raster_x, y_pos=>raster_y,
      tmds_ch0=>encoded(0), tmds_ch1=>encoded(1), tmds_ch2=>encoded(2));

  serializer: entity work.hdmi_tx_selectio
    port map(sclk,prst,pclk,encoded,tclk,serial);
  clk_buf: OBUFDS generic map(IOSTANDARD=>"TMDS_33")
    port map(I=>tclk,O=>TMDS_clk_p,OB=>TMDS_clk_n);
  data_buf: for i in 0 to 2 generate
    buf: OBUFDS generic map(IOSTANDARD=>"TMDS_33")
      port map(I=>serial(i),O=>TMDS_data_p(i),OB=>TMDS_data_n(i));
  end generate;
  -- The analogue VGA connector carries the same 720x576p50 raster as HDMI.
  vga_red <= red; vga_green <= green; vga_blue <= blue;
  vga_hsync <= hs; vga_vsync <= vs;
  vdac_clk <= pclk;
  vdac_sync_n <= '0'; vdac_blank_n <= '1'; vdac_psave_n <= '1';
  led <= '1';
  hdmi_enable_n <= '0'; hdmi_hiz <= '0';
end;
