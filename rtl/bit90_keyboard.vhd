library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package bit90_keyboard_pkg is
  function map_to_bit90(
    k : std_logic_vector(73 downto 0);
    caps, restore : std_logic) return std_logic_vector;
end package;

package body bit90_keyboard_pkg is
  function map_to_bit90(
    k : std_logic_vector(73 downto 0);
    caps, restore : std_logic) return std_logic_vector is
    variable r : std_logic_vector(63 downto 0) := (others => '1');
    variable shift_n : std_logic;
    variable alpha_n : std_logic;
  begin
    shift_n := k(15) and k(52);
    -- Active low: zero when at least one alphabetic MEGA65 key is held.
    alpha_n := k(10) and k(28) and k(20) and k(18) and k(14) and
               k(21) and k(26) and k(29) and k(33) and k(34) and
               k(37) and k(42) and k(36) and k(39) and k(38) and
               k(41) and k(62) and k(17) and k(13) and k(22) and
               k(30) and k(31) and k(9) and k(23) and k(25) and k(12);
    -- Number row.
    r(5):=k(56); r(13):=k(59); r(2):=k(8);  r(10):=k(11); r(6):=k(16);
    r(14):=k(19); r(1):=k(24); r(9):=k(27); r(7):=k(32); r(15):=k(35);

    -- Alphabetic keys.
    r(45):=k(10); r(55):=k(28); r(54):=k(20); r(42):=k(18); r(26):=k(14);
    r(38):=k(21); r(46):=k(26); r(33):=k(29); r(23):=k(33); r(41):=k(34);
    r(39):=k(37); r(47):=k(42); r(51):=k(36); r(48):=k(39); r(31):=k(38);
    r(16):=k(41); r(29):=k(62); r(22):=k(17); r(34):=k(13); r(30):=k(22);
    r(25):=k(30); r(49):=k(31); r(18):=k(9);  r(50):=k(23); r(17):=k(25);
    r(53):=k(12);

    -- Editing, punctuation and cursor keys. INST/DEL is INS without SHIFT
    -- and DEL with SHIFT. RUN/STOP and ESC both operate the BIT90 ESC key.
    r(4):=k(0) or not shift_n;
    r(12):=k(0) or shift_n;
    r(11):=k(51); r(43):=k(1);  r(27):=restore;
    r(21):=k(63) and k(71);
    r(20):=k(72); r(28):=k(2);  r(59):=k(73); r(60):=k(7);
    r(0):=k(43);  r(3):=k(57);  r(8):=k(54);  r(19):=k(48);
    r(24):=k(49); r(32):=k(50); r(40):=k(45); r(35):=k(46);
    r(36):=k(55); r(44):=k(44); r(52):=k(47);

    -- BIT90 modifiers: MEGA/C= is BIT, TAB is BASIC, CTRL (scan key 58)
    -- and ALT (scan key 66) both operate CTRL, and '=' is FCTN.
    -- CAPS LOWER reverses SHIFT only for alphabetic keys. It is kept out of
    -- the BIT90 matrix so the latched MEGA65 CAPS state cannot mask letters.
    r(37):='1';
    if caps = '0' and alpha_n = '0' then
      r(56):=not shift_n;
    else
      r(56):=shift_n;
    end if;
    r(57):=k(61);
    r(58):=k(65);
    r(61):=k(58) and k(66);
    r(62):=k(60);
    r(63):=k(53);
    return r;
  end function;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bit90_keyboard_pkg.all;

-- MEGA65 R6 keyboard scanner and direct BIT90 8x8 matrix translator.
-- Both matrices use active-low key states. The keyboard LED stream keeps only
-- the duplicated Power LED channels lit, in green.
entity bit90_keyboard is
  port (
    clk           : in  std_logic;
    reset         : in  std_logic;
    drive_led     : in  std_logic;
    kb_io0        : out std_logic;
    kb_io1        : out std_logic;
    kb_io2        : in  std_logic;
    keyboard_rows : out std_logic_vector(63 downto 0);
    caps_n : out std_logic;
    help_n, escape_n, up_n, down_n, left_n, right_n, return_n : out std_logic
  );
end entity;

architecture rtl of bit90_keyboard is
  constant KBD_DIV_MAX : natural := 64;
  signal divider       : natural range 0 to KBD_DIV_MAX := 0;
  signal kbd_clock     : std_logic := '0';
  signal sync_pulse    : std_logic := '0';
  signal phase         : natural range 0 to 140 := 0;
  signal led_vector    : std_logic_vector(127 downto 0) := (others => '0');
  signal scan_keys     : std_logic_vector(73 downto 0) := (others => '1');
  signal keys          : std_logic_vector(73 downto 0) := (others => '1');
  signal delete_key    : std_logic := '1';
  signal return_key    : std_logic := '1';
  signal caps_key      : std_logic := '1';
  signal sampled_caps  : std_logic := '1';
  signal help_key, sampled_help : std_logic := '1';

begin
  keyboard_rows <= map_to_bit90(keys, sampled_caps, sampled_help);
  caps_n <= sampled_caps;
  -- HELP controls the overlay; the controller's dedicated RESTORE phase is
  -- independently translated to the BIT90 RUBOUT key.
  help_n <= keys(67);
  escape_n <= keys(63) and keys(71);
  up_n <= keys(72); down_n <= keys(7);
  left_n <= keys(73); right_n <= keys(2);
  return_n <= keys(1);

  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        divider <= 0;
        kbd_clock <= '0';
        sync_pulse <= '0';
        phase <= 0;
        led_vector <= (others => '0');
        scan_keys <= (others => '1');
        keys <= (others => '1');
        delete_key <= '1';
        return_key <= '1';
        caps_key <= '1';
        sampled_caps <= '1';
        help_key <= '1'; sampled_help <= '1';
        kb_io0 <= '1';
        kb_io1 <= '0';
      elsif divider < KBD_DIV_MAX then
        divider <= divider + 1;
      else
        divider <= 0;
        kbd_clock <= not kbd_clock;
        kb_io0 <= kbd_clock or sync_pulse;

        if kbd_clock = '1' and phase < 128 then
          if phase = 72 then caps_key <= kb_io2; end if;
          if phase = 73 then scan_keys(72) <= kb_io2; end if;
          if phase = 74 then scan_keys(73) <= kb_io2; end if;
          if phase = 75 then help_key <= kb_io2; end if;
          if phase = 76 then delete_key <= kb_io2; end if;
          if phase = 77 then return_key <= kb_io2; end if;

          if phase = 0 then
            scan_keys(0) <= delete_key;
          elsif phase = 1 then
            scan_keys(1) <= return_key;
          elsif phase < 72 then
            scan_keys(phase) <= kb_io2;
          end if;
        end if;

        if kbd_clock = '0' then
          if phase < 140 then phase <= phase + 1; else phase <= 0; end if;

          if phase = 127 then
            sync_pulse <= '1';
            keys <= scan_keys;
            sampled_caps <= caps_key;
            sampled_help <= help_key;
            led_vector <= (others => '0');
            if drive_led = '1' then
              -- Two identical RGB fields feed the duplicated red DRIVE LEDs.
              led_vector(23 downto 0) <= x"0000FF";
              led_vector(47 downto 24) <= x"0000FF";
            end if;
            led_vector(71 downto 48) <= x"00FF00";
            led_vector(95 downto 72) <= x"00FF00";
          elsif phase = 140 then
            sync_pulse <= '0';
          elsif phase < 127 then
            kb_io1 <= led_vector(127);
            led_vector(127 downto 1) <= led_vector(126 downto 0);
            led_vector(0) <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
