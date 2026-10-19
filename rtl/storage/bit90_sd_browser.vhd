LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.bit90_sd_file_pkg.ALL;
USE work.vfat_name_pkg.ALL;

-- BIT90-facing wrapper around the proven Nascom2 SD/FAT32 engine. Media paths
-- remain read-only; the configuration ports retain the small verified sector-
-- write path used for /BIT90/BIT90.CFG.
ENTITY bit90_sd_browser IS
  PORT (
    clk, reset : IN STD_LOGIC;
    sd_cd, sd_miso : IN STD_LOGIC;
    sd_sclk, sd_mosi, sd_cs_n : OUT STD_LOGIC;
    media_kind : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    page_base_index : IN INTEGER RANGE 0 TO SD_BROWSER_LAST_INDEX;
    selected_page_row : IN INTEGER RANGE 0 TO SD_BROWSER_PAGE_LAST;
    init_busy, init_done, init_error : OUT STD_LOGIC;
    read_busy, read_done, read_error : OUT STD_LOGIC;
    error_code : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    state_code : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    card_block_addressing : OUT STD_LOGIC;
    media_dir_found, has_files : OUT STD_LOGIC;
    file_count : OUT INTEGER RANGE 0 TO SD_BROWSER_MAX_FILES;
    total_file_count : OUT INTEGER RANGE 0 TO 255;
    page_valid : OUT sd_page_valid_array_t;
    page_name : OUT sd_page_name_array_t;
    page_display_name : OUT sd_page_display_name_array_t;
    selected_valid : OUT STD_LOGIC;
    selected_name : OUT STD_LOGIC_VECTOR(87 DOWNTO 0);
    selected_cluster, selected_size : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    raw_read_start : IN STD_LOGIC := '0';
    raw_read_raw : IN STD_LOGIC := '1';
    raw_read_ready : IN STD_LOGIC := '1';
    raw_read_cluster, raw_read_size : IN STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    raw_read_wr : OUT STD_LOGIC;
    raw_read_addr : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    raw_read_data : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    cfg_load_start : IN STD_LOGIC := '0';
    cfg_load_busy, cfg_load_done, cfg_load_error, cfg_loaded_valid : OUT STD_LOGIC;
    cfg_loaded_ram : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    cfg_loaded_xbas : OUT STD_LOGIC;
    cfg_save_start : IN STD_LOGIC := '0';
    cfg_save_busy, cfg_save_done, cfg_save_error : OUT STD_LOGIC;
    cfg_save_ram : IN STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    cfg_save_xbas : IN STD_LOGIC := '0';
    save_check_start : IN STD_LOGIC := '0';
    save_name : IN vfat_save_name_t := (OTHERS => '0');
    save_check_done, save_check_exists, save_check_can_create, save_check_can_allocate : OUT STD_LOGIC;
    save_write_start : IN STD_LOGIC := '0';
    save_write_start_addr, save_write_end_addr : IN STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    save_write_busy, save_write_done, save_write_error : OUT STD_LOGIC;
    save_write_status : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    save_debug_sectors_left : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    save_mem_addr : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    save_mem_data : IN STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0')
  );
END ENTITY;

ARCHITECTURE rtl OF bit90_sd_browser IS
BEGIN
  storage : ENTITY work.bit90_sd_spi_fat32
    GENERIC MAP (CLK_HZ => 100000000, SPI_HZ => 400000, DATA_SPI_HZ => 12500000)
    PORT MAP (
      clk => clk,
      reset => reset,
      sd_cd => sd_cd,
      sd_miso => sd_miso,
      sd_sclk => sd_sclk,
      sd_mosi => sd_mosi,
      sd_cs_n => sd_cs_n,
      sd_reset_n => OPEN,
      cd_raw => OPEN,
      init_busy => init_busy,
      init_done => init_done,
      init_error => init_error,
      read_busy => read_busy,
      read_done => read_done,
      read_error => read_error,
      read_stage => OPEN,
      read_lba => OPEN,
      read_token => OPEN,
      read_count => OPEN,
      read_first_word => OPEN,
      read_signature => OPEN,
      part_type => OPEN,
      part_lba => OPEN,
      boot_bps => OPEN,
      boot_spc => OPEN,
      boot_reserved => OPEN,
      boot_num_fats => OPEN,
      boot_spf => OPEN,
      boot_root_cluster => OPEN,
      root_dir_lba => OPEN,
      root_file_count => file_count,
      root_total_file_count => total_file_count,
      browser_dir_found => media_dir_found,
      browser_include_dsk => '0',
      browser_include_pas => '0',
      browser_media_kind => media_kind,
      page_base_index => page_base_index,
      selected_page_row => selected_page_row,
      browser_has_files => has_files,
      page_valid => page_valid,
      page_name => page_name,
      page_display_name => page_display_name,
      page_kind => OPEN,
      selected_valid => selected_valid,
      selected_name => selected_name,
      selected_cluster => selected_cluster,
      selected_size => selected_size,
      manage_start => '0',
      manage_delete => '0',
      manage_old_name => (OTHERS => '0'),
      manage_new_name => (OTHERS => '0'),
      manage_busy => OPEN,
      manage_done => OPEN,
      manage_error => OPEN,
      manage_status => OPEN,
      save_check_start => save_check_start,
      save_name => save_name,
      save_is_pascal => '0',
      save_is_binary => '1',
      save_check_busy => OPEN,
      save_check_done => save_check_done,
      save_check_exists => save_check_exists,
      save_check_can_create => save_check_can_create,
      save_check_can_allocate => save_check_can_allocate,
      save_check_requires_dir_growth => OPEN,
      save_check_dir_full => OPEN,
      save_debug_free_lba => OPEN,
      save_debug_free_slot => OPEN,
      save_debug_free_marker => OPEN,
      save_debug_free_cluster => OPEN,
      save_done_clear => '0',
      save_status_clear => '0',
      save_write_start => save_write_start,
      save_write_start_addr => save_write_start_addr,
      save_write_end_addr => save_write_end_addr,
      save_write_busy => save_write_busy,
      save_write_done => save_write_done,
      save_write_error => save_write_error,
      save_write_status => save_write_status,
      save_debug_sectors_left => save_debug_sectors_left,
      save_mem_addr => save_mem_addr,
      save_mem_data => save_mem_data,
      cfg_load_start => cfg_load_start,
      cfg_load_busy => cfg_load_busy,
      cfg_load_done => cfg_load_done,
      cfg_load_error => cfg_load_error,
      cfg_loaded_valid => cfg_loaded_valid,
      cfg_loaded_speed => cfg_loaded_ram,
      cfg_loaded_phosphor_amber => cfg_loaded_xbas,
      cfg_loaded_scanlines => OPEN,
      cfg_loaded_video_zoom => OPEN,
      cfg_loaded_rs232 => OPEN,
      cfg_loaded_rs232_speed => OPEN,
      cfg_loaded_rs232_flow => OPEN,
      cfg_loaded_slot_rom => OPEN,
      cfg_loaded_fdd => OPEN,
      cfg_loaded_cpm => OPEN,
      cfg_loaded_avc => OPEN,
      cfg_loaded_bls => OPEN,
      cfg_loaded_network => OPEN,
      cfg_loaded_network_dhcp => OPEN,
      cfg_loaded_network_ipv4 => OPEN,
      cfg_loaded_network_netmask => OPEN,
      cfg_loaded_network_gateway => OPEN,
      cfg_loaded_network_dns => OPEN,
      cfg_save_start => cfg_save_start,
      cfg_save_busy => cfg_save_busy,
      cfg_save_done => cfg_save_done,
      cfg_save_error => cfg_save_error,
      cfg_save_speed => cfg_save_ram,
      cfg_save_phosphor_amber => cfg_save_xbas,
      cfg_save_scanlines => '0',
      cfg_save_video_zoom => (OTHERS => '0'),
      cfg_save_rs232 => (OTHERS => '0'),
      cfg_save_rs232_speed => (OTHERS => '0'),
      cfg_save_rs232_flow => '0',
      cfg_save_slot_rom => (OTHERS => '0'),
      cfg_save_fdd => '0',
      cfg_save_cpm => '0',
      cfg_save_avc => '0',
      cfg_save_bls => '0',
      cfg_save_network => '0',
      cfg_save_network_dhcp => '0',
      cfg_save_network_ipv4 => (OTHERS => '0'),
      cfg_save_network_netmask => (OTHERS => '0'),
      cfg_save_network_gateway => (OTHERS => '0'),
      cfg_save_network_dns => (OTHERS => '0'),
      fdd_read_start => '0',
      fdd_read_cluster => (OTHERS => '0'),
      fdd_read_sd_sector => (OTHERS => '0'),
      fdd_read_half => '0',
      fdd_read_busy => OPEN,
      fdd_read_done => OPEN,
      fdd_read_error => OPEN,
      fdd_buffer_addr => (OTHERS => '0'),
      fdd_buffer_data => OPEN,
      fdd_buffer_write_enable => '0',
      fdd_buffer_write_addr => (OTHERS => '0'),
      fdd_buffer_write_data => (OTHERS => '0'),
      fdd_write_start => '0',
      fdd_write_cluster => (OTHERS => '0'),
      fdd_write_sd_sector => (OTHERS => '0'),
      fdd_write_half => '0',
      fdd_write_busy => OPEN,
      fdd_write_done => OPEN,
      fdd_write_error => OPEN,
      fdd_format_start => '0',
      fdd_format_name => (OTHERS => '0'),
      fdd_format_cluster => (OTHERS => '0'),
      fdd_format_busy => OPEN,
      fdd_format_done => OPEN,
      fdd_format_error => OPEN,
      fdd_format_new_cluster => OPEN,
      file_read_start => raw_read_start,
      file_read_cluster => raw_read_cluster,
      file_read_size => raw_read_size,
      file_read_is_cas => '0',
      file_read_raw => raw_read_raw,
      file_read_ready => raw_read_ready,
      file_load_addr_valid => OPEN,
      file_load_addr => OPEN,
      file_mem_wr => raw_read_wr,
      file_mem_addr => raw_read_addr,
      file_mem_data => raw_read_data,
      debug_read_cmd17_r1 => OPEN,
      debug_read_error_code => error_code,
      debug_root_current_cluster => OPEN,
      debug_root_next_cluster => OPEN,
      debug_root_sectors_left => OPEN,
      debug_root_scan_phase => OPEN,
      debug_root_scan_job => OPEN,
      state_code => state_code,
      last_r1 => OPEN,
      card_block_addressing => card_block_addressing
    );
END ARCHITECTURE;
