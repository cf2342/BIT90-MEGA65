library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bit90_sd_file_pkg.all;
use work.vfat_name_pkg.all;

entity bit90_config is
  port (
    clk, reset : in std_logic;
    help_n, escape_n, up_n, down_n, left_n, right_n, return_n : in std_logic;
    keyboard_state : in std_logic_vector(63 downto 0) := (others => '1');
    overlay_enable : out std_logic;
    overlay_page : out std_logic_vector(1 downto 0);
    menu_selection : out std_logic_vector(2 downto 0);
    browser_page_base : out integer range 0 to SD_BROWSER_LAST_INDEX;
    browser_selected_row : out integer range 0 to SD_BROWSER_PAGE_LAST;
    browser_total_file_count : in integer range 0 to 255 := 0;
    selected_config : out std_logic_vector(1 downto 0);
    active_config : out std_logic_vector(1 downto 0);
    selected_xbas : out std_logic;
    active_xbas : out std_logic;
    reset_req : out std_logic;
    storage_reset_req : out std_logic;
    browser_select_req : out std_logic;
    save_basic_req : out std_logic;
    save_name : out vfat_save_name_t;
    save_name_cursor : out integer range 0 to VFAT_SAVE_BASE_CHARS-1;
    browser_load_busy : in std_logic := '0';
    browser_load_done : in std_logic := '0';
    save_basic_busy : in std_logic := '0';
    save_basic_done : in std_logic := '0';
    loaded_valid : in std_logic := '0';
    loaded_config : in std_logic_vector(1 downto 0) := "00";
    loaded_xbas : in std_logic := '0'
  );
end entity;

architecture rtl of bit90_config is
  signal overlay_q, keyboard_help_q : std_logic := '0';
  signal page_q : unsigned(1 downto 0) := "00";
  signal menu_q : unsigned(2 downto 0) := "000";
  signal selected_q, active_q : unsigned(1 downto 0) := "00";
  signal selected_xbas_q, active_xbas_q : std_logic := '0';
  signal page_base_q : integer range 0 to SD_BROWSER_LAST_INDEX := 0;
  signal browser_row_q : integer range 0 to SD_BROWSER_PAGE_LAST := 0;
  signal previous : std_logic_vector(6 downto 0) := (others => '1');
  signal reset_count : natural range 0 to 1023 := 0;
  signal storage_reset_count : natural range 0 to 1023 := 0;
  signal browser_select_q, save_basic_q : std_logic := '0';
  signal escape_close_pending : std_logic := '0';
  signal save_name_q : vfat_save_name_t := (others => '0');
  signal save_name_cursor_q : integer range 0 to VFAT_SAVE_BASE_CHARS-1 := 0;
  signal name_keys_previous : std_logic_vector(63 downto 0) := (others => '1');

  function default_save_name(value : unsigned(1 downto 0)) return vfat_save_name_t is
    variable result : vfat_save_name_t := (others => '0');
    variable tens, ones : character;
    constant prefix : string := "SAVE";
  begin
    for i in 0 to VFAT_SAVE_BASE_CHARS-1 loop
      result(result'high-i*8 downto result'high-i*8-7) := x"20";
    end loop;
    if value=0 then tens:='1'; ones:='8';
    elsif value=1 then tens:='3'; ones:='2';
    else tens:='6'; ones:='4'; end if;
    for i in prefix'range loop
      result(result'high-(i-prefix'low)*8 downto result'high-(i-prefix'low)*8-7) :=
        std_logic_vector(to_unsigned(character'pos(prefix(i)),8));
    end loop;
    result(result'high-4*8 downto result'high-4*8-7) :=
      std_logic_vector(to_unsigned(character'pos(tens),8));
    result(result'high-5*8 downto result'high-5*8-7) :=
      std_logic_vector(to_unsigned(character'pos(ones),8));
    result(result'high-6*8 downto result'high-6*8-7) := x"4B";
    return result;
  end function;
  function name_key_code(index : integer) return integer is
  begin
    case index is
      when 5=>return 49; when 13=>return 50; when 2=>return 51; when 10=>return 52;
      when 6=>return 53; when 14=>return 54; when 1=>return 55; when 9=>return 56;
      when 7=>return 57; when 15=>return 48;
      when 45=>return 65; when 55=>return 66; when 54=>return 67; when 42=>return 68;
      when 26=>return 69; when 38=>return 70; when 46=>return 71; when 33=>return 72;
      when 23=>return 73; when 41=>return 74; when 39=>return 75; when 47=>return 76;
      when 51=>return 77; when 48=>return 78; when 31=>return 79; when 16=>return 80;
      when 29=>return 81; when 22=>return 82; when 34=>return 83; when 30=>return 84;
      when 25=>return 85; when 49=>return 86; when 18=>return 87; when 50=>return 88;
      when 17=>return 89; when 53=>return 90; when 0=>return 45; when 62=>return 32;
      when others=>return -1;
    end case;
  end function;
  function name_has_character(value : vfat_save_name_t) return boolean is
  begin
    for i in 0 to VFAT_SAVE_BASE_CHARS-1 loop
      if value(value'high-i*8 downto value'high-i*8-7)/=x"20" then return true; end if;
    end loop;
    return false;
  end function;
  function next_config(value : unsigned(1 downto 0)) return unsigned is
  begin
    if value = 2 then return to_unsigned(0, 2); end if;
    return value + 1;
  end function;

  function previous_config(value : unsigned(1 downto 0)) return unsigned is
  begin
    if value = 0 then return to_unsigned(2, 2); end if;
    return value - 1;
  end function;
begin
  overlay_enable <= overlay_q;
  overlay_page <= std_logic_vector(page_q);
  menu_selection <= "111" when keyboard_help_q = '1' else std_logic_vector(menu_q);
  browser_page_base <= page_base_q;
  browser_selected_row <= browser_row_q;
  selected_config <= std_logic_vector(selected_q);
  active_config <= std_logic_vector(active_q);
  selected_xbas <= selected_xbas_q;
  active_xbas <= active_xbas_q;
  reset_req <= '1' when reset_count /= 0 else '0';
  storage_reset_req <= '1' when storage_reset_count /= 0 else '0';
  browser_select_req <= browser_select_q;
  save_basic_req <= save_basic_q;
  save_name <= save_name_q;
  save_name_cursor <= save_name_cursor_q;

  process(clk)
    variable current : std_logic_vector(6 downto 0);
    variable name_code, name_byte_hi : integer;
  begin
    if rising_edge(clk) then
      browser_select_q <= '0';
      save_basic_q <= '0';
      current := help_n & escape_n & up_n & down_n & left_n & right_n & return_n;
      name_code := -1;
      for i in 0 to 63 loop
        if name_keys_previous(i)='1' and keyboard_state(i)='0' and name_key_code(i)>=0 then name_code:=name_key_code(i); end if;
      end loop;
      if reset = '1' then
        overlay_q <= '0';
        keyboard_help_q <= '0';
        page_q <= "00";
        menu_q <= "000";
        selected_q <= "00";
        active_q <= "00";
        selected_xbas_q <= '0';
        active_xbas_q <= '0';
        page_base_q <= 0;
        browser_row_q <= 0;
        previous <= (others => '1');
        reset_count <= 0;
        storage_reset_count <= 0;
        browser_select_q <= '0';
        save_basic_q <= '0';
        escape_close_pending <= '0';
        save_name_q <= default_save_name(to_unsigned(0,2));
        save_name_cursor_q <= 0;
        name_keys_previous <= (others=>'1');
      elsif loaded_valid = '1' then
        if loaded_xbas = '1' then
          selected_q <= "10";
          active_q <= "10";
          selected_xbas_q <= '1';
          active_xbas_q <= '1';
        elsif unsigned(loaded_config) <= 2 then
          selected_q <= unsigned(loaded_config);
          active_q <= unsigned(loaded_config);
          selected_xbas_q <= '0';
          active_xbas_q <= '0';
        else
          selected_q <= "00";
          active_q <= "00";
          selected_xbas_q <= '0';
          active_xbas_q <= '0';
        end if;
        overlay_q <= '0';
        keyboard_help_q <= '0';
        page_q <= "00";
        menu_q <= "000";
        page_base_q <= 0;
        browser_row_q <= 0;
        previous <= current;
        reset_count <= 1023;
        storage_reset_count <= 0;
        escape_close_pending <= '0';
        if loaded_xbas='1' then
          save_name_q <= default_save_name(to_unsigned(2,2));
        else
          save_name_q <= default_save_name(unsigned(loaded_config));
        end if;
        save_name_cursor_q <= 0;
        name_keys_previous <= keyboard_state;
      else
        if reset_count /= 0 then reset_count <= reset_count - 1; end if;
        if storage_reset_count /= 0 then storage_reset_count <= storage_reset_count - 1; end if;

        if browser_load_done = '1' then
          overlay_q <= '0';
          keyboard_help_q <= '0';
          escape_close_pending <= '0';
          page_q <= "00";
          menu_q <= "000";
        elsif save_basic_done = '1' then
          -- Keep the result visible until HELP or ESC.
        elsif escape_close_pending = '1' and
              previous(5) = '0' and current(5) = '1' then
          overlay_q <= '0';
          keyboard_help_q <= '0';
          escape_close_pending <= '0';
        elsif overlay_q = '1' and keyboard_help_q = '0' and
              previous(5) = '1' and current(5) = '0' then
          if page_q /= "00" then
            -- ESC/RUN STOP returns from an idle file browser to Configuration.
            -- Keep the overlay active so the held key cannot reach BASIC.
            if browser_load_busy = '0' then
              page_q <= "00";
              page_base_q <= 0;
              browser_row_q <= 0;
            end if;
          elsif save_basic_busy = '0' then
            -- On Configuration, close only after release so the held ESC does
            -- not leak into a running BASIC program.
            escape_close_pending <= '1';
          end if;
        elsif previous(6) = '1' and current(6) = '0' then
          if overlay_q = '1' then
            if keyboard_help_q = '1' then
              overlay_q <= '0';
              keyboard_help_q <= '0';
            elsif page_q /= "00" then
              -- HELP closes an idle file browser directly to the BIT90.
              if browser_load_busy = '0' then
                overlay_q <= '0';
                page_q <= "00";
                page_base_q <= 0;
                browser_row_q <= 0;
              end if;
            elsif save_basic_busy = '0' then
              keyboard_help_q <= '1';
            end if;
          else
            selected_q <= active_q;
            selected_xbas_q <= active_xbas_q;
            menu_q <= "000";
            page_q <= "00";
            keyboard_help_q <= '0';
            overlay_q <= '1';
            save_name_q <= default_save_name(active_q);
            save_name_cursor_q <= 0;
          end if;
        elsif overlay_q = '1' and keyboard_help_q = '0' then
          if page_q = "00" then
            if previous(4) = '1' and current(4) = '0' then
              if menu_q = 0 then menu_q <= to_unsigned(5, 3);
              else menu_q <= menu_q - 1; end if;
            elsif previous(3) = '1' and current(3) = '0' then
              if menu_q = 5 then menu_q <= to_unsigned(0, 3);
              else menu_q <= menu_q + 1; end if;
            elsif previous(2) = '1' and current(2) = '0' then
              if menu_q = 0 then
                selected_q <= previous_config(selected_q);
                if previous_config(selected_q) /= 2 then selected_xbas_q <= '0'; end if;
                save_name_q <= default_save_name(previous_config(selected_q));
                save_name_cursor_q <= 0;
              elsif menu_q = 1 then
                selected_xbas_q <= not selected_xbas_q;
                if selected_xbas_q = '0' then selected_q <= "10"; end if;
              elsif menu_q=5 and save_basic_busy='0' then
                if save_name_cursor_q>0 then save_name_cursor_q<=save_name_cursor_q-1; end if;
              end if;
            elsif previous(1) = '1' and current(1) = '0' then
              if menu_q = 0 then
                selected_q <= next_config(selected_q);
                if next_config(selected_q) /= 2 then selected_xbas_q <= '0'; end if;
                save_name_q <= default_save_name(next_config(selected_q));
                save_name_cursor_q <= 0;
              elsif menu_q = 1 then
                selected_xbas_q <= not selected_xbas_q;
                if selected_xbas_q = '0' then selected_q <= "10"; end if;
              elsif menu_q=5 and save_basic_busy='0' then
                if save_name_cursor_q<VFAT_SAVE_BASE_CHARS-1 then save_name_cursor_q<=save_name_cursor_q+1; end if;
              end if;
            elsif previous(0) = '1' and current(0) = '0' then
              if menu_q = 0 then
                active_q <= selected_q;
                active_xbas_q <= selected_xbas_q;
                overlay_q <= '0';
                reset_count <= 1023;
              elsif menu_q = 1 then
                active_q <= selected_q;
                active_xbas_q <= selected_xbas_q;
                overlay_q <= '0';
                reset_count <= 1023;
              elsif menu_q = 2 then
                page_q <= "01";
                page_base_q <= 0;
                browser_row_q <= 0;
                storage_reset_count <= 1023;
              elsif menu_q = 3 then
                page_q <= "10";
                page_base_q <= 0;
                browser_row_q <= 0;
                storage_reset_count <= 1023;
              elsif menu_q = 4 then
                page_q <= "11";
                page_base_q <= 0;
                browser_row_q <= 0;
                storage_reset_count <= 1023;
              else
                if save_basic_busy='0' and name_has_character(save_name_q) then save_basic_q<='1'; end if;
              end if;
            elsif menu_q=5 and save_basic_busy='0' and name_code>=0 then
              name_byte_hi:=save_name_q'high-save_name_cursor_q*8;
              save_name_q(name_byte_hi downto name_byte_hi-7)<=std_logic_vector(to_unsigned(name_code,8));
              if save_name_cursor_q<VFAT_SAVE_BASE_CHARS-1 then save_name_cursor_q<=save_name_cursor_q+1; end if;
            elsif menu_q=5 and save_basic_busy='0' and
              ((name_keys_previous(11)='1' and keyboard_state(11)='0') or (name_keys_previous(4)='1' and keyboard_state(4)='0') or (name_keys_previous(12)='1' and keyboard_state(12)='0')) then
              if name_keys_previous(11)='1' and keyboard_state(11)='0' and save_name_cursor_q>0 then
                save_name_cursor_q<=save_name_cursor_q-1; name_byte_hi:=save_name_q'high-(save_name_cursor_q-1)*8;
              else name_byte_hi:=save_name_q'high-save_name_cursor_q*8; end if;
              save_name_q(name_byte_hi downto name_byte_hi-7)<=x"20";
            end if;
          else
            if previous(4) = '1' and current(4) = '0' then
              if browser_row_q > 0 then
                browser_row_q <= browser_row_q - 1;
              elsif page_base_q >= SD_BROWSER_PAGE_SIZE then
                page_base_q <= page_base_q - SD_BROWSER_PAGE_SIZE;
                browser_row_q <= SD_BROWSER_PAGE_LAST;
              end if;
            elsif previous(3) = '1' and current(3) = '0' then
              if page_base_q + browser_row_q + 1 < browser_total_file_count then
                if browser_row_q < SD_BROWSER_PAGE_LAST then
                  browser_row_q <= browser_row_q + 1;
                elsif page_base_q <= SD_BROWSER_LAST_INDEX - SD_BROWSER_PAGE_SIZE then
                  page_base_q <= page_base_q + SD_BROWSER_PAGE_SIZE;
                  browser_row_q <= 0;
                end if;
              end if;
            elsif previous(2) = '1' and current(2) = '0' then
              if page_base_q >= SD_BROWSER_PAGE_SIZE then
                page_base_q <= page_base_q - SD_BROWSER_PAGE_SIZE;
                browser_row_q <= 0;
              end if;
            elsif previous(1) = '1' and current(1) = '0' then
              if page_base_q + SD_BROWSER_PAGE_SIZE < browser_total_file_count and
                 page_base_q <= SD_BROWSER_LAST_INDEX - SD_BROWSER_PAGE_SIZE then
                page_base_q <= page_base_q + SD_BROWSER_PAGE_SIZE;
                browser_row_q <= 0;
              end if;
            elsif previous(0) = '1' and current(0) = '0' then
              browser_select_q <= '1';
            end if;
          end if;
        end if;
        previous <= current;
        name_keys_previous <= keyboard_state;
      end if;
    end if;
  end process;
end architecture;
