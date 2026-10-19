library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vdp18_col_pack.all;
use work.bit90_font_pkg.all;
use work.bit90_sd_file_pkg.all;
use work.vfat_name_pkg.all;

-- Two 256x192 indexed images. A completed bank is transferred by a toggle
-- mailbox; the reader changes banks only at the output frame boundary.
-- If the reader has not acknowledged, a whole source frame is skipped.
entity bit90_framebuffer is
  port(
    src_clk, src_reset, enabled, pixel_ce : in std_logic;
    pixel_x : in integer range 0 to 255;
    pixel_y : in integer range 0 to 191;
    color : in std_logic_vector(3 downto 0);
    pix_clk, pix_reset : in std_logic;
    red, green, blue : out std_logic_vector(7 downto 0);
    hs_n, vs_n, de : out std_logic;
    overlay_enable : in std_logic := '0';
    overlay_page : in std_logic_vector(1 downto 0) := "00";
    menu_selection : in std_logic_vector(2 downto 0) := "000";
    ram_config : in std_logic_vector(1 downto 0) := "00";
    xbas_enable : in std_logic := '0';
    browser_selected_row : in integer range 0 to SD_BROWSER_PAGE_LAST := 0;
    browser_file_count : in integer range 0 to SD_BROWSER_MAX_FILES := 0;
    browser_page_base : in integer range 0 to SD_BROWSER_LAST_INDEX := 0;
    sd_card_detect_n, sd_init_busy, sd_init_done, sd_init_error : in std_logic := '0';
    sd_read_busy, sd_read_done, sd_read_error, media_dir_found : in std_logic := '0';
    cart_load_busy, cart_load_error : in std_logic := '0';
    cart_load_status : in std_logic_vector(3 downto 0) := x"0";
    save_debug : in std_logic_vector(15 downto 0) := (others => '0');
    save_name : in vfat_save_name_t := (others => '0');
    save_name_cursor : in integer range 0 to VFAT_SAVE_BASE_CHARS-1 := 0;
    media_page_valid : in sd_page_valid_array_t := (others => '0');
    media_page_display_name : in sd_page_display_name_array_t := (others => (others => '0'));
    keyboard_state : in std_logic_vector(63 downto 0) := (others => '1');
    caps_state_n : in std_logic := '1';
    raster_x : out unsigned(10 downto 0);
    raster_y : out unsigned(9 downto 0)
  );
end;
architecture rtl of bit90_framebuffer is
  type ram_t is array(0 to 131071) of std_logic_vector(3 downto 0);
  signal ram : ram_t;
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
  signal wr_bank : std_logic := '0';
  signal rd_bank : std_logic := '1';
  signal request, acknowledge : std_logic := '0';
  signal req_meta, req_sync, ack_meta, ack_sync : std_logic := '0';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of req_meta, req_sync, ack_meta, ack_sync : signal is "TRUE";
  signal capturing, valid : std_logic := '0';
  signal x : natural range 0 to 863 := 0;
  signal y : natural range 0 to 624 := 0;
  signal sample, visible, hs_q, vs_q, de_q : std_logic := '0';
  signal q : std_logic_vector(3 downto 0);
  signal address : natural range 0 to 131071 := 0;
  signal overlay_meta, overlay_pix : std_logic := '0';
  signal config_meta, config_pix : std_logic_vector(1 downto 0) := "00";
  signal page_meta, page_pix : std_logic_vector(1 downto 0) := "00";
  signal menu_meta, menu_pix : std_logic_vector(2 downto 0) := "000";
  signal xbas_meta, xbas_pix : std_logic := '0';
  signal browser_row_meta, browser_row_pix : integer range 0 to SD_BROWSER_PAGE_LAST := 0;
  signal file_count_meta, file_count_pix : integer range 0 to SD_BROWSER_MAX_FILES := 0;
  signal page_base_meta, page_base_pix : integer range 0 to SD_BROWSER_LAST_INDEX := 0;
  signal sd_status_meta, sd_status_pix : std_logic_vector(7 downto 0) := (others => '0');
  signal cart_status_meta, cart_status_pix : std_logic_vector(5 downto 0) := (others => '0');
  signal save_debug_meta, save_debug_pix : std_logic_vector(15 downto 0) := (others => '0');
  signal save_name_meta, save_name_pix : vfat_save_name_t := (others => '0');
  signal save_cursor_meta, save_cursor_pix : integer range 0 to VFAT_SAVE_BASE_CHARS-1 := 0;
  signal names_valid_meta, names_valid_pix : sd_page_valid_array_t := (others => '0');
  signal names_meta, names_pix : sd_page_display_name_array_t := (others => (others => '0'));
  signal keyboard_meta, keyboard_pix : std_logic_vector(63 downto 0) := (others => '1');
  signal caps_meta, caps_pix : std_logic := '1';
  signal bit_mode_pix, bit_key_last : std_logic := '0';
  attribute ASYNC_REG of keyboard_meta, keyboard_pix, caps_meta, caps_pix : signal is "TRUE";
  attribute ASYNC_REG of save_debug_meta, save_debug_pix : signal is "TRUE";
  attribute ASYNC_REG of save_name_meta, save_name_pix, save_cursor_meta, save_cursor_pix : signal is "TRUE";
  attribute ASYNC_REG of file_count_meta, file_count_pix, page_base_meta, page_base_pix : signal is "TRUE";
  constant key_labels0 : string := "1234567890-\^";
  constant key_labels1 : string := "QWERTYUIOP[]";
  constant key_labels2 : string := "ASDFGHJKL;:@";
  constant key_labels3 : string := "ZXCVBNM,./";

  -- User-supplied BIT90 logo, reduced to 64x14 logical overlay pixels. The
  -- green overlay background shows through every zero bit.
  type overlay_logo_rows_t is array(0 to 13) of std_logic_vector(63 downto 0);
  constant overlay_logo : overlay_logo_rows_t := (
    "1111101110000111111001111111111111100001101110000000001110110000",
    "1111101111000111111001110111111011100011101111100000111110111100",
    "1111101111100111111001110111111011100111101111110001111110111110",
    "1111101111100111111001100111111001101111101111110001111110111110",
    "1111101111000111111001100111111001101111101111111011111110111111",
    "1111101110000111111001000111111000101111101111111011111110111111",
    "1111101100000111111000000111111000000111101111111011111110111111",
    "1111101110000111111000000111111000000011101111111011111110111111",
    "1111101111000111111000000111111000000001101111111011111110111111",
    "1111101111100111111000000111111000000011001111111011111110111111",
    "1111101111100111111000000111111000000111101111110001111110111110",
    "1111101111100111111000000111111000000111101111100001111110111110",
    "1111101111000111111000000111111000000111101111000000111110111100",
    "1111101110000111111000000111111000000011011110000000001110110000"
  );
  function placed(text : string; first_col, col : natural) return character is
  begin
    if col = first_col then
      return text(text'low);
    elsif col > first_col and col < first_col + text'length then
      return text(text'low + (col - first_col));
    end if;
    return ' ';
  end function;

  function hex_char(value : std_logic_vector(3 downto 0)) return character is
    variable n : natural := to_integer(unsigned(value));
  begin
    if n < 10 then return character'val(character'pos('0') + n); end if;
    return character'val(character'pos('A') + n - 10);
  end function;
  function short_name_char(name : std_logic_vector(87 downto 0);
                           position : natural) return character is
    variable value : natural := 32;
    variable source_position : natural;
  begin
    if position < 8 then
      value := to_integer(unsigned(name(87-position*8 downto 80-position*8)));
    elsif position = 8 then
      return '.';
    elsif position < 12 then
      source_position := position - 1;
      value := to_integer(unsigned(name(87-source_position*8 downto 80-source_position*8)));
    end if;
    if value >= 32 and value <= 126 then return character'val(value); end if;
    return '?';
  end function;

  function display_name_char(name : vfat_display_name_t;
                             position : natural) return character is
    variable value : natural := 32;
  begin
    if position < VFAT_DISPLAY_CHARS then
      value := to_integer(unsigned(name(name'high-position*8 downto name'high-position*8-7)));
    end if;
    if value >= 32 and value <= 126 then return character'val(value); end if;
    return '?';
  end function;

  function save_name_char(name : vfat_save_name_t;
                          position : natural) return character is
    variable value : natural := 32;
  begin
    if position < VFAT_SAVE_BASE_CHARS then
      value := to_integer(unsigned(name(name'high-position*8 downto name'high-position*8-7)));
    elsif position = VFAT_SAVE_BASE_CHARS then return '.';
    elsif position = VFAT_SAVE_BASE_CHARS+1 then return 'B';
    elsif position = VFAT_SAVE_BASE_CHARS+2 then return 'I';
    elsif position = VFAT_SAVE_BASE_CHARS+3 then return 'T';
    end if;
    if value >= 32 and value <= 126 then return character'val(value); end if;
    return '?';
  end function;
  function key_base_code(index : integer) return integer is
  begin
    case index is
      when 0=>return 16#2D#; when 1=>return 16#37#; when 2=>return 16#33#;
      when 3=>return 16#5C#; when 4=>return 16#F5#; when 5=>return 16#31#;
      when 6=>return 16#35#; when 7=>return 16#39#; when 8=>return 16#5E#;
      when 9=>return 16#38#; when 10=>return 16#34#; when 11=>return 16#08#;
      when 12=>return 16#F4#; when 13=>return 16#32#; when 14=>return 16#36#;
      when 15=>return 16#30#; when 16=>return 16#50#; when 17=>return 16#59#;
      when 18=>return 16#57#; when 19=>return 16#5D#; when 20=>return 16#F0#;
      when 21=>return 16#1B#; when 22=>return 16#52#; when 23=>return 16#49#;
      when 24=>return 16#5B#; when 25=>return 16#55#; when 26=>return 16#45#;
      when 27=>return 16#7F#; when 28=>return 16#F3#; when 29=>return 16#51#;
      when 30=>return 16#54#; when 31=>return 16#4F#; when 32=>return 16#3B#;
      when 33=>return 16#48#; when 34=>return 16#53#; when 35=>return 16#40#;
      when 36=>return 16#2F#; when 38=>return 16#46#; when 39=>return 16#4B#;
      when 40=>return 16#3A#; when 41=>return 16#4A#; when 42=>return 16#44#;
      when 43=>return 16#0D#; when 44=>return 16#2E#; when 45=>return 16#41#;
      when 46=>return 16#47#; when 47=>return 16#4C#; when 48=>return 16#4E#;
      when 49=>return 16#56#; when 50=>return 16#58#; when 51=>return 16#4D#;
      when 52=>return 16#2C#; when 53=>return 16#5A#; when 54=>return 16#43#;
      when 55=>return 16#42#; when 59=>return 16#F2#; when 60=>return 16#F1#;
      when 62=>return 16#20#;
      when others=>return -1;
    end case;
  end function;

  function preview_key_index(keys : std_logic_vector(63 downto 0)) return integer is
  begin
    for i in 0 to 63 loop
      if keys(i)='0' and key_base_code(i)>=0 then return i; end if;
    end loop;
    return -1;
  end function;

  function shifted_key_code(base : integer; shift_pressed : boolean) return integer is
  begin
    if base>=character'pos('A') and base<=character'pos('Z') then
      if shift_pressed then return base+32; else return base; end if;
    elsif shift_pressed and base>=32 and base<127 then
      if base=16#40# then return 16#5F#;
      elsif base>=16#40# then return base+32;
      elsif (base mod 32)>=16 then return base-16;
      else return base+16;
      end if;
    end if;
    return base;
  end function;

  function basic_token_code(base : integer) return integer is
  begin
    if base>=16#2C# and base<16#30# then return base+16+16#50#;
    elsif base>=16#30# and base<16#60# then return base+16#50#;
    end if;
    return -1;
  end function;

  function graphic_key_code(code : integer) return integer is
  begin
    if code>=16#2C# and code<16#30# then return code+16+16#50#;
    elsif code>=16#30# and code<16#3C# then return code+16#50#;
    elsif code>=16#40# and code<16#7B# then return code+16#50#;
    end if;
    return code;
  end function;

  function basic_token_char(token, position : integer) return character is
  begin
    case token is
      when 16#80#=>return placed("NEW",0,position);
      when 16#81#=>return placed("SAVE",0,position);
      when 16#82#=>return placed("LOAD",0,position);
      when 16#83#=>return placed("EDIT",0,position);
      when 16#84#=>return placed("DELETE",0,position);
      when 16#85#=>return placed("RUN",0,position);
      when 16#86#=>return placed("STOP",0,position);
      when 16#87#=>return placed("CONT",0,position);
      when 16#88#=>return placed("MUSIC",0,position);
      when 16#89#=>return placed("TEMPO",0,position);
      when 16#8A#=>return placed("POKE",0,position);
      when 16#8B#=>return placed("PEEK(",0,position);
      when 16#8C#=>return placed("DEF",0,position);
      when 16#8D#=>return placed("OPEN",0,position);
      when 16#8E#=>return placed("DIM",0,position);
      when 16#8F#=>return placed("RND(",0,position);
      when 16#90#=>return placed("TAB(",0,position);
      when 16#91#=>return placed("AUTO",0,position);
      when 16#92#=>return placed("GOSUB",0,position);
      when 16#93#=>return placed("CALL",0,position);
      when 16#94#=>return placed("DATA",0,position);
      when 16#95#=>return placed("ELSE",0,position);
      when 16#96#=>return placed("FOR",0,position);
      when 16#97#=>return placed("GOTO",0,position);
      when 16#98#=>return placed("HOME",0,position);
      when 16#99#=>return placed("INPUT",0,position);
      when 16#9A#=>return placed("RANDOMIZE",0,position);
      when 16#9B#=>return placed("CLEAR",0,position);
      when 16#9C#=>return placed("LIST",0,position);
      when 16#9D#=>return placed("REM",0,position);
      when 16#9E#=>return placed("NEXT",0,position);
      when 16#9F#=>return placed("ON",0,position);
      when 16#A0#=>return placed("PRINT",0,position);
      when 16#A1#=>return placed("RESTORE",0,position);
      when 16#A2#=>return placed("READ",0,position);
      when 16#A3#=>return placed("STEP",0,position);
      when 16#A4#=>return placed("THEN",0,position);
      when 16#A5#=>return placed("PLOT",0,position);
      when 16#A6#=>return placed("RETURN",0,position);
      when 16#A7#=>return placed("TO",0,position);
      when 16#A8#=>return placed("UNTRACE",0,position);
      when 16#A9#=>return placed("IF",0,position);
      when 16#AA#=>return placed("TRACE",0,position);
      when 16#AB#=>return placed("COPY",0,position);
      when 16#AC#=>return placed("RENUM",0,position);
      when 16#AD#=>return placed("PLAY",0,position);
      when 16#AE#=>return placed("CLOSE",0,position);
      when 16#AF#=>return placed("FRE",0,position);
      when others=>return ' ';
    end case;
  end function;

  function preview_char(keys : std_logic_vector(63 downto 0);
                        bit_mode : std_logic;
                        position : natural) return character is
    variable index, base, code, token : integer;
  begin
    index := preview_key_index(keys);
    if index<0 then
      if keys(61)='0' then return placed("CTRL",0,position); end if;
      return ' ';
    end if;
    base := key_base_code(index);

    if keys(58)='0' then
      token := basic_token_code(base);
      if token>=0 then return basic_token_char(token,integer(position)); end if;
    elsif keys(63)='0' and base>=character'pos('0') and base<=character'pos('9') then
      case base is
        when 16#30#=>return placed("CODE 224",0,position);
        when 16#31#=>return placed("CODE 225",0,position);
        when 16#32#=>return placed("CODE 226",0,position);
        when 16#33#=>return placed("CODE 227",0,position);
        when 16#34#=>return placed("CODE 228",0,position);
        when 16#35#=>return placed("CODE 229",0,position);
        when 16#36#=>return placed("CODE 230",0,position);
        when 16#37#=>return placed("CODE 231",0,position);
        when 16#38#=>return placed("CODE 232",0,position);
        when others=>return placed("CODE 233",0,position);
      end case;
    elsif keys(61)='0' and base>=character'pos('A') and base<=character'pos('Z') then
      if position<5 then return placed("CTRL-",0,position);
      elsif position=5 then return character'val(base);
      else return ' ';
      end if;
    end if;

    code := shifted_key_code(base,keys(56)='0');
    if bit_mode='1' then code := graphic_key_code(code); end if;
    case code is
      when 16#08#=>return placed("BS",0,position);
      when 16#0D#=>return placed("RETURN",0,position);
      when 16#1B#=>return placed("ESC",0,position);
      when 16#7F#=>return placed("RUBOUT",0,position);
      when 16#F0#=>return placed("UP",0,position);
      when 16#F1#=>return placed("DOWN",0,position);
      when 16#F2#=>return placed("LEFT",0,position);
      when 16#F3#=>return placed("RIGHT",0,position);
      when 16#F4#=>return placed("DEL",0,position);
      when 16#F5#=>return placed("INS",0,position);
      when others =>
        if code>=32 and code<=202 and position=0 then return character'val(code); end if;
        return ' ';
    end case;
  end function;

  function basic_preview_active(keys : std_logic_vector(63 downto 0)) return boolean is
    variable index : integer;
  begin
    index := preview_key_index(keys);
    return keys(58)='0' and index>=0 and
           basic_token_code(key_base_code(index))>=0;
  end function;

  function overlay_char(row, col : natural;
                        cfg, page : std_logic_vector(1 downto 0);
                        menu : std_logic_vector(2 downto 0);
                        xbas : std_logic;
                        browser_row : natural;
                        status : std_logic_vector(7 downto 0);
                        cart_status : std_logic_vector(5 downto 0);
                        debug : std_logic_vector(15 downto 0);
                        valid_names : sd_page_valid_array_t;
                        names : sd_page_display_name_array_t;
                        keys : std_logic_vector(63 downto 0);
                        bit_mode : std_logic;
                        current_save_name : vfat_save_name_t;
                        current_save_cursor : natural;
                        file_count : natural;
                        page_base : natural) return character is
    variable ch : character := ' ';
    variable item : natural range 0 to SD_BROWSER_PAGE_LAST;
    variable current_page, total_pages : natural range 0 to 26;
  begin
    if menu = "111" then
      case row is
        when 2  => ch := placed("Keyboard Help", 9, col);
        when 3  => ch := placed("-------------", 9, col);
        when 8 =>
          if col >= 4 and col <= 26 and (col mod 2) = 0 then
            ch := key_labels1((col-4)/2+1);
          end if;
        when 15 =>
          ch := placed("ESC", 1, col);
          if col >= 5 then ch := placed("BS", 5, col); end if;
          if col >= 9 then ch := placed("INS", 9, col); end if;
          if col >= 13 then ch := placed("DEL", 13, col); end if;
          if col >= 17 then ch := placed("RUBOUT", 17, col); end if;
          if col >= 24 then ch := placed("RETURN", 24, col); end if;
        when 17 =>
          ch := placed("CAPS LOWER", 1, col);
          if col >= 13 then ch := placed("SHIFT", 13, col); end if;
          if col >= 20 then ch := placed("CTRL", 20, col); end if;
          if col >= 26 then ch := placed("BASIC", 26, col); end if;
        when 19 =>
          ch := placed("BIT", 1, col);
          if col >= 6 then ch := placed("FCTN", 6, col); end if;
          if col >= 12 then ch := placed("SPACE", 12, col); end if;
          if col >= 24 then ch := placed("PRESSED:", 24, col); end if;
        when 21 =>
          ch := placed("UP", 1, col);
          if col >= 5 then ch := placed("DOWN", 5, col); end if;
          if col >= 11 then ch := placed("LEFT", 11, col); end if;
          if col >= 17 then ch := placed("RIGHT", 17, col); end if;
          if basic_preview_active(keys) then
            if col >= 23 then ch := preview_char(keys,bit_mode,col-23); end if;
          elsif col >= 26 then
            ch := preview_char(keys,bit_mode,col-26);
          end if;
        when others => null;
      end case;
    elsif page = "00" then
      case row is
        when 1  => ch := placed("Configuration", 11, col);
        when 2  => ch := placed("-------------", 11, col);
        when 5  =>
          if col = 4 and menu = "000" then ch := '>';
          else ch := placed("RAM", 6, col); end if;
          if col >= 23 and col < 29 then
            if cfg = "00" then ch := placed("18 KB", 23, col);
            elsif cfg = "01" then ch := placed("32 KB", 23, col);
            else ch := placed("64 KB", 23, col); end if;
          end if;
        when 7 =>
          if col = 4 and menu = "001" then ch := '>';
          else ch := placed("XBasic", 6, col); end if;
          if col >= 23 and col < 26 then
            if xbas = '1' then ch := placed("ON", 23, col);
            else ch := placed("OFF", 23, col); end if;
          end if;
        when 9 =>
          if col = 4 and menu = "010" then ch := '>';
          else ch := placed("Tape Mount", 6, col); end if;
        when 11 =>
          if col = 4 and menu = "011" then ch := '>';
          else ch := placed("Cartridge", 6, col); end if;
        when 13 =>
          if col = 4 and menu = "100" then ch := '>';
          else ch := placed("BASic & RAM Dump (BIT)", 6, col); end if;
        when 15 =>
          if col = 4 and menu = "101" then ch := '>';
          else ch := placed("Save memory", 6, col); end if;
        when 16 =>
          if menu = "101" and col >= 3 and col < 29 then
            ch := save_name_char(current_save_name, col-3);
          end if;
        when 17 =>
          if menu="101" and cart_status(5)='0' and
             col=3+current_save_cursor then ch := '^';
          end if;
        when 19 =>
          if menu="101" and cart_status(5)='1' and cart_status(3 downto 0)=x"1" then
            ch := placed("Preparing SD file...", 6, col);
          elsif menu="101" and cart_status(5)='1' then
            ch := placed("Writing...", 11, col);
          elsif menu="101" and cart_status(4)='1' and cart_status(3 downto 0)=x"2" then
            ch := placed("Existing file size differs", 3, col);
          elsif menu="101" and cart_status(4)='1' and cart_status(3 downto 0)=x"3" then
            ch := placed("BIT90/BASIC directory missing", 2, col);
          elsif menu="101" and cart_status(4)='1' and cart_status(3 downto 0)=x"7" then
            ch := placed("No contiguous SD space", 5, col);
          elsif menu="101" and cart_status(4)='1' and cart_status(3 downto 0)=x"8" then
            ch := placed("BASIC directory full", 6, col);
          elsif menu="101" and cart_status(4)='1' then
            ch := placed("Save failed", 10, col);
          elsif menu="101" and cart_status(3 downto 0)=x"5" then
            ch := placed("Saved", 13, col);
          elsif status(7) = '1' then ch := placed("SD: no card", 3, col);
          elsif status(6) = '1' then ch := placed("SD: initializing", 3, col);
          elsif status(4) = '1' or status(1) = '1' then ch := placed("SD: error", 3, col);
          elsif status(5) = '1' then ch := placed("SD: ready", 3, col);
          else ch := placed("SD: waiting", 3, col); end if;
        when 21 =>
          if menu="101" then ch := placed("TYPE name  LEFT/RIGHT cursor", 2, col);
          else ch := placed("UP/DOWN item LEFT/RIGHT value", 2, col); end if;
        when 23 =>
          if menu="101" then ch := placed("RETURN save HELP help ESC close", 1, col);
          else ch := placed("RETURN select HELP keyboard", 3, col); end if;
        when others => null;
      end case;
    else
      if row = 2 then
        if page = "01" then ch := placed("Tape files", 11, col);
        elsif page = "10" then ch := placed("Cartridge files", 11, col);
        else ch := placed("BAS/BIT programs", 11, col); end if;
      elsif row = 3 then
        if page = "01" then ch := placed("----------", 11, col);
        elsif page = "10" then ch := placed("---------------", 11, col);
        else ch := placed("----------------", 11, col); end if;
      elsif row >= 5 and row <= 14 then
        item := row - 5;
        if col = 2 and item = browser_row then ch := '>'; end if;
        if valid_names(item) = '1' and col >= 4 and col < 32 then
          ch := display_name_char(names(item), col - 4);
        end if;
      elsif row = 17 then
        if cart_status(5) = '1' then
          if page="01" then ch := placed("Mounting tape...", 4, col);
          elsif page="11" then ch := placed("Loading BASIC...", 4, col);
          else ch := placed("Loading cartridge...", 4, col); end if;
        elsif cart_status(4) = '1' and cart_status(3 downto 0) = x"1" then ch := placed("No file selected", 4, col);
        elsif cart_status(4) = '1' and cart_status(3 downto 0) = x"2" then
          if page="01" then ch := placed("WAV file invalid", 4, col);
          elsif page="11" then ch := placed("BAS file too large", 4, col);
          else ch := placed("Cartridge size invalid", 4, col); end if;
        elsif cart_status(4) = '1' and cart_status(3 downto 0) = x"3" then
          if page="11" then ch := placed("Not enough BASIC RAM", 4, col);
          elsif page="01" then ch := placed("Tape read error", 4, col);
          else ch := placed("Cartridge read error", 4, col); end if;
        elsif cart_status(4) = '1' and cart_status(3 downto 0) = x"4" then
          if page="01" then ch := placed("RIFF/WAVE signature invalid", 4, col);
          elsif page="11" then ch := placed("BAS file read error", 4, col);
          else ch := placed("Cartridge signature invalid", 4, col); end if;
        elsif cart_status(4) = '1' and cart_status(3 downto 0) = x"5" then
          if page="01" then ch := placed("WAV data chunk missing", 4, col);
          else ch := placed("BASIC syntax error", 4, col); end if;
        elsif cart_status(4) = '1' and cart_status(3 downto 0) = x"6" then
          if page="01" then ch := placed("PCM format unsupported", 4, col);
          else ch := placed("BASIC program too large", 4, col); end if;
        elsif status(7) = '1' then ch := placed("No SD card", 4, col);
        elsif status(6) = '1' then ch := placed("Initializing SD...", 4, col);
        elsif status(4) = '1' then ch := placed("SD initialization error", 4, col);
        elsif status(3) = '1' then ch := placed("Reading FAT32...", 4, col);
        elsif status(1) = '1' then ch := placed("FAT32 read error", 4, col);
        elsif status(0) = '0' and status(2) = '1' then ch := placed("Directory missing", 4, col);
        elsif status(0) = '1' and valid_names(0) = '0' then ch := placed("No matching files", 4, col);
        end if;
      elsif row = 18 then
        total_pages := (file_count + SD_BROWSER_PAGE_SIZE - 1) / SD_BROWSER_PAGE_SIZE;
        if total_pages = 0 then total_pages := 1; end if;
        current_page := (page_base / SD_BROWSER_PAGE_SIZE) + 1;
        ch := placed("FILES", 2, col);
        if col=8 and file_count>=100 then ch:=character'val(character'pos('0')+(file_count/100) mod 10); end if;
        if col=9 and file_count>=10 then ch:=character'val(character'pos('0')+(file_count/10) mod 10); end if;
        if col=10 then ch:=character'val(character'pos('0')+file_count mod 10); end if;
        if col>=14 then ch:=placed("PAGE",14,col); end if;
        if col=20 and current_page>=10 then ch:=character'val(character'pos('0')+(current_page/10) mod 10); end if;
        if col=21 then ch:=character'val(character'pos('0')+current_page mod 10); end if;
        if col=22 then ch:='/'; end if;
        if col=23 and total_pages>=10 then ch:=character'val(character'pos('0')+(total_pages/10) mod 10); end if;
        if col=24 then ch:=character'val(character'pos('0')+total_pages mod 10); end if;
      elsif row = 20 then ch := placed("CURSOR browse   LEFT/RIGHT page", 2, col);
      elsif row = 22 then ch := placed("RETURN load HELP close ESC menu", 1, col);
      end if;
    end if;
    return ch;
  end function;

  -- The keyboard help uses the logical 32x24 character (256x192 pixel) area.
  -- The four printable rows follow QWERTY order; all special keys have their
  -- complete names in separately sized boxes below them.
  -- Returned numbers are indices in the active-low BIT90 keyboard matrix.
  function keyboard_matrix_index(row, column : natural) return integer is
  begin
    case row is
      when 0 =>
        case column is
          when 0=>return 5;  when 1=>return 13; when 2=>return 2;
          when 3=>return 10; when 4=>return 6;  when 5=>return 14;
          when 6=>return 1;  when 7=>return 9;  when 8=>return 7;
          when 9=>return 15; when 10=>return 0; when 11=>return 3;
          when 12=>return 8; when others=>return -1;
        end case;
      when 1 =>
        case column is
          when 0=>return 29; when 1=>return 18; when 2=>return 26;
          when 3=>return 22; when 4=>return 30; when 5=>return 17;
          when 6=>return 25; when 7=>return 23; when 8=>return 31;
          when 9=>return 16; when 10=>return 24; when 11=>return 19;
          when others=>return -1;
        end case;
      when 2 =>
        case column is
          when 0=>return 45; when 1=>return 34; when 2=>return 42;
          when 3=>return 38; when 4=>return 46; when 5=>return 33;
          when 6=>return 41; when 7=>return 39; when 8=>return 47;
          when 9=>return 32; when 10=>return 40; when 11=>return 35;
          when others=>return -1;
        end case;
      when 3 =>
        case column is
          when 0=>return 53; when 1=>return 50; when 2=>return 54;
          when 3=>return 49; when 4=>return 55; when 5=>return 48;
          when 6=>return 51; when 7=>return 52; when 8=>return 44;
          when 9=>return 36; when others=>return -1;
        end case;
      when others => return -1;
    end case;
  end function;

  function bank_base(b : std_logic) return natural is
  begin if b = '1' then return 65536; else return 0; end if; end;
begin
  -- Video, sync and DE leave this block two pixel clocks behind the internal
  -- counter. Export the coordinate belonging to those registered outputs so
  -- HDMI preambles and guard bands remain contiguous at the line boundary.
  raster_x <= to_unsigned(x - 2, raster_x'length) when x >= 2 else
              to_unsigned(x + 862, raster_x'length);
  raster_y <= to_unsigned(y, raster_y'length) when x >= 2 else
              to_unsigned(y - 1, raster_y'length) when y > 0 else
              to_unsigned(624, raster_y'length);

  process(src_clk)
    variable capture_now : boolean;
  begin
    if rising_edge(src_clk) then
      ack_meta <= acknowledge; ack_sync <= ack_meta;
      if src_reset = '1' then
        wr_bank <= '0'; request <= '0';
        capturing <= '0'; ack_meta <= '0'; ack_sync <= '0';
      elsif enabled = '0' then
        capturing <= '0';
      elsif pixel_ce = '1' then
        capture_now := capturing = '1';
        if pixel_x = 0 and pixel_y = 0 then
          capture_now := request = ack_sync and enabled = '1';
          if capture_now then capturing <= '1'; else capturing <= '0'; end if;
        end if;
        if capture_now then
          if pixel_x = 255 and pixel_y = 191 then
            request <= not request;
            wr_bank <= not wr_bank;
            capturing <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;
  -- Keep RAM free of resets, including its read output register.
  process(src_clk)
  begin
    if rising_edge(src_clk) then
      if src_reset = '0' and enabled = '1' and pixel_ce = '1' then
        if capturing = '1' or
          (pixel_x = 0 and pixel_y = 0 and request = ack_sync and enabled = '1') then
          ram(bank_base(wr_bank) + pixel_y*256 + pixel_x) <= color;
        end if;
      end if;
    end if;
  end process;
  -- 720x576 active, 864x625 total at 27 MHz: exactly 50 Hz.
  -- Integer 2x scaling, centred with a black border; no aspect-ratio correction.
  sample <= '1' when x >= 104 and x < 616 and y >= 96 and y < 480 else '0';
  address <= bank_base(rd_bank) + ((y-96)/2)*256 + (x-104)/2 when sample='1' else 0;
  process(pix_clk)
  begin
    if rising_edge(pix_clk) then q <= ram(address); end if;
  end process;
  process(pix_clk)
  begin
    if rising_edge(pix_clk) then
      overlay_meta <= overlay_enable; overlay_pix <= overlay_meta;
      config_meta <= ram_config; config_pix <= config_meta;
      page_meta <= overlay_page; page_pix <= page_meta;
      menu_meta <= menu_selection; menu_pix <= menu_meta;
      xbas_meta <= xbas_enable; xbas_pix <= xbas_meta;
      browser_row_meta <= browser_selected_row; browser_row_pix <= browser_row_meta;
      file_count_meta <= browser_file_count; file_count_pix <= file_count_meta;
      page_base_meta <= browser_page_base; page_base_pix <= page_base_meta;
      sd_status_meta <= sd_card_detect_n & sd_init_busy & sd_init_done &
                        sd_read_busy & sd_init_error & sd_read_done &
                        sd_read_error & media_dir_found;
      sd_status_pix <= sd_status_meta;
      cart_status_meta <= cart_load_busy & cart_load_error & cart_load_status;
      cart_status_pix <= cart_status_meta;
      save_debug_meta <= save_debug; save_debug_pix <= save_debug_meta;
      save_name_meta <= save_name; save_name_pix <= save_name_meta;
      save_cursor_meta <= save_name_cursor; save_cursor_pix <= save_cursor_meta;
      names_valid_meta <= media_page_valid; names_valid_pix <= names_valid_meta;
      names_meta <= media_page_display_name; names_pix <= names_meta;
      keyboard_meta <= keyboard_state; keyboard_pix <= keyboard_meta;
      caps_meta <= caps_state_n; caps_pix <= caps_meta;
    end if;
  end process;
  -- BIT toggles graphics mode in the original line editor. The help page
  -- mirrors that behaviour locally without changing the running BASIC state.
  process(pix_clk)
  begin
    if rising_edge(pix_clk) then
      if pix_reset='1' or menu_pix/="111" then
        bit_mode_pix <= '0';
        bit_key_last <= '1';
      else
        if bit_key_last='1' and keyboard_pix(57)='0' then
          bit_mode_pix <= not bit_mode_pix;
        end if;
        bit_key_last <= keyboard_pix(57);
      end if;
    end if;
  end process;

  process(pix_clk)
    variable c : natural range 0 to 15;
    variable lx, ly, col_i, row_i, gx, gy : natural;
    variable ch : character;
    variable bits : std_logic_vector(7 downto 0);
    variable key_row, key_col, key_x, key_y, key_index : integer;
    variable key_pressed, key_border, key_label : boolean;
  begin
    if rising_edge(pix_clk) then
      req_meta <= request; req_sync <= req_meta;
      if pix_reset = '1' then
        x <= 0; y <= 0; rd_bank <= '1'; valid <= '0';
        req_meta <= '0'; req_sync <= '0'; acknowledge <= '0';
        visible <= '0'; hs_q <= '1'; vs_q <= '1'; de_q <= '0';
        red <= x"00"; green <= x"00"; blue <= x"00";
        hs_n <= '1'; vs_n <= '1'; de <= '0';
      else
        if x = 863 then
          x <= 0;
          if y = 624 then
            y <= 0;
            if req_sync /= acknowledge then
              -- Bank identity is encoded by the request toggle itself:
              -- first publication 1 => bank 0, next publication 0 => bank 1.
              rd_bank <= not req_sync;
              acknowledge <= req_sync;
              valid <= '1';
            end if;
          else y <= y+1; end if;
        else x <= x+1; end if;
        visible <= sample and valid;
        hs_q <= '1'; if x >= 732 and x < 796 then hs_q <= '0'; end if;
        vs_q <= '1'; if y >= 581 and y < 586 then vs_q <= '0'; end if;
        de_q <= '0'; if x < 720 and y < 576 then de_q <= '1'; end if;
        hs_n <= hs_q; vs_n <= vs_q; de <= de_q;
        red <= x"00"; green <= x"00"; blue <= x"00";
        if visible = '1' then
          c := to_integer(unsigned(q));
          red <= std_logic_vector(to_unsigned(full_rgb_table_c(c)(0),8));
          green <= std_logic_vector(to_unsigned(full_rgb_table_c(c)(1),8));
          blue <= std_logic_vector(to_unsigned(full_rgb_table_c(c)(2),8));
        end if;
        if overlay_pix = '1' and x < 720 and y < 576 then
          red <= x"21"; green <= x"C8"; blue <= x"42";
          if x >= 104 and x < 616 and y >= 96 and y < 480 then
            lx := (x - 104) / 2; ly := (y - 96) / 2;
            col_i := lx / 8; row_i := ly / 8;
            gx := lx mod 8; gy := ly mod 8;
            ch := overlay_char(row_i, col_i, config_pix, page_pix, menu_pix, xbas_pix,
                               browser_row_pix, sd_status_pix, cart_status_pix, save_debug_pix,
                               names_valid_pix, names_pix,
                               keyboard_pix, bit_mode_pix, save_name_pix, save_cursor_pix,
                               file_count_pix, page_base_pix);
            bits := bit90_font_row(ch, gy);

            -- Pixel-precise centring inside the printable key boxes. These
            -- three rows cannot be aligned correctly on whole 8-pixel text
            -- rows: number row -3 px, home row -5 px, bottom row -2 px.
            if menu_pix = "111" then
              if ly >= 45 and ly < 53 then
                ch := ' ';
                if col_i >= 3 and col_i <= 27 and (col_i mod 2)=1 then
                  ch := key_labels0((col_i-3)/2+1);
                end if;
                bits := bit90_font_row(ch, ly-45);
              elsif ly >= 83 and ly < 91 then
                ch := ' ';
                if col_i >= 5 and col_i <= 27 and (col_i mod 2)=1 then
                  ch := key_labels2((col_i-5)/2+1);
                end if;
                bits := bit90_font_row(ch, ly-83);
              elsif ly >= 102 and ly < 110 then
                ch := ' ';
                if col_i >= 6 and col_i <= 24 and (col_i mod 2)=0 then
                  ch := key_labels3((col_i-6)/2+1);
                end if;
                bits := bit90_font_row(ch, ly-102);
              end if;
            end if;

            if bits(7-gx) = '1' then
              red <= x"00"; green <= x"00"; blue <= x"00";
            end if;

            -- The logo occupies logical x=2..65 and y=3..16. Configuration
            -- starts at x=72 on the same rows; all other titles start below it.
            if lx >= 2 and lx < 66 and ly >= 3 and ly < 17 and
               overlay_logo(ly-3)(63-(lx-2)) = '1' then
              red <= x"00"; green <= x"00"; blue <= x"00";
            end if;

            -- Interactive BIT90 keyboard diagram. The geometry follows the
            -- 32x24 character grid, keeping the pixel path shallow enough for
            -- the 27-MHz video clock.
            if menu_pix = "111" then
              key_row := -1; key_col := -1; key_index := -1;
              key_x := 0; key_y := 0;
              key_pressed := false; key_border := false;
              key_label := bits(7-gx) = '1';

              if ly >= 40 and ly < 56 and lx >= 16 and lx < 224 then
                key_row := 0; key_col := integer((lx-16)/16);
                key_x := integer((lx-16) mod 16); key_y := integer(ly-40);
              elsif ly >= 59 and ly < 75 and lx >= 24 and lx < 216 then
                key_row := 1; key_col := integer((lx-24)/16);
                key_x := integer((lx-24) mod 16); key_y := integer(ly-59);
              elsif ly >= 78 and ly < 94 and lx >= 32 and lx < 224 then
                key_row := 2; key_col := integer((lx-32)/16);
                key_x := integer((lx-32) mod 16); key_y := integer(ly-78);
              elsif ly >= 97 and ly < 113 and lx >= 40 and lx < 200 then
                key_row := 3; key_col := integer((lx-40)/16);
                key_x := integer((lx-40) mod 16); key_y := integer(ly-97);
              end if;
              if key_row >= 0 then
                key_index := keyboard_matrix_index(natural(key_row), natural(key_col));
                key_border := key_x=0 or key_x=15 or key_y=0 or key_y=15;
              end if;

              -- Full-name special keys. Every right edge is at or before
              -- logical x=255; row 23 remains free as a safety margin.
              if ly >= 116 and ly < 132 then
                key_y := integer(ly-116);
                if lx < 32 then key_index:=21; key_x:=integer(lx);
                elsif lx < 64 then key_index:=11; key_x:=integer(lx-32);
                elsif lx < 96 then key_index:=4; key_x:=integer(lx-64);
                elsif lx < 128 then key_index:=12; key_x:=integer(lx-96);
                elsif lx < 184 then key_index:=27; key_x:=integer(lx-128);
                elsif lx < 248 then key_index:=43; key_x:=integer(lx-184);
                end if;
              elsif ly >= 132 and ly < 148 then
                key_y := integer(ly-132);
                if lx < 96 then key_index:=37; key_x:=integer(lx);
                elsif lx < 152 then key_index:=56; key_x:=integer(lx-96);
                elsif lx < 200 then key_index:=61; key_x:=integer(lx-152);
                else key_index:=58; key_x:=integer(lx-200);
                end if;
              elsif ly >= 148 and ly < 164 and lx < 152 then
                key_y := integer(ly-148);
                if lx < 40 then key_index:=57; key_x:=integer(lx);
                elsif lx < 88 then key_index:=63; key_x:=integer(lx-40);
                else key_index:=62; key_x:=integer(lx-88);
                end if;
              elsif ly >= 164 and ly < 180 and lx < 184 then
                key_y := integer(ly-164);
                if lx < 32 then key_index:=20; key_x:=integer(lx);
                elsif lx < 80 then key_index:=60; key_x:=integer(lx-32);
                elsif lx < 128 then key_index:=59; key_x:=integer(lx-80);
                else key_index:=28; key_x:=integer(lx-128);
                end if;
              end if;

              if key_index >= 0 and key_row < 0 then
                key_border := key_y=0 or key_y=15;
                case key_index is
                  when 21|11|4|12 => key_border := key_border or key_x=0 or key_x=31;
                  when 27|56 => key_border := key_border or key_x=0 or key_x=55;
                  when 43 => key_border := key_border or key_x=0 or key_x=63;
                  when 37 => key_border := key_border or key_x=0 or key_x=95;
                  when 61|63|60|59 => key_border := key_border or key_x=0 or key_x=47;
                  when 58 => key_border := key_border or key_x=0 or key_x=55;
                  when 57|20 => key_border := key_border or key_x=0 or key_x=39;
                  when 62 => key_border := key_border or key_x=0 or key_x=63;
                  when 28 => key_border := key_border or key_x=0 or key_x=55;
                  when others => null;
                end case;
              end if;

              if key_index >= 0 then
                if key_index = 37 then key_pressed := caps_pix = '0';
                else key_pressed := keyboard_pix(key_index) = '0'; end if;
                if key_pressed or key_border then
                  red <= x"00"; green <= x"00"; blue <= x"00";
                end if;
                if key_pressed and key_label then
                  red <= x"21"; green <= x"C8"; blue <= x"42";
                end if;
              end if;

              -- One-key BASIC results are highlighted like their key legends.
              -- The field disappears immediately when the data key is released.
              if lx>=184 and ly>=164 and ly<180 and
                 basic_preview_active(keyboard_pix) then
                red <= x"00"; green <= x"00"; blue <= x"00";
                if bits(7-gx)='1' then
                  red <= x"21"; green <= x"C8"; blue <= x"42";
                end if;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end;
