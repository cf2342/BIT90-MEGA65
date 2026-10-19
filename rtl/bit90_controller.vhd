library ieee;
use ieee.std_logic_1164.all;

-- ColecoVision-compatible controller response used while a cartridge is
-- active.  The original BIT90 substitutes keyboard keys for the controller
-- keypad: arrows are the stick, CTRL is FIRE and BASIC is ARM.
entity bit90_controller is
  port (
    cartridge_active  : in  std_logic;
    keypad_mode       : in  std_logic;
    keyboard_rows     : in  std_logic_vector(63 downto 0);
    joystick_1        : in  std_logic_vector(7 downto 0);
    joystick_2_tape   : in  std_logic_vector(7 downto 0);
    controller_1      : out std_logic_vector(7 downto 0);
    controller_2_tape : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of bit90_controller is
begin
  process(all)
    variable p1, p2 : std_logic_vector(7 downto 0);
    variable code   : std_logic_vector(3 downto 0);
  begin
    p1 := joystick_1;
    p2 := joystick_2_tape;

    if cartridge_active = '1' then
      if keypad_mode = '1' then
        -- Coleco keypad encoding on D3..D0.  Shift+3 is '#', and
        -- Shift+the BIT90 ':' key is '*'.  Multiple keys follow a stable
        -- priority because the original diode matrix did not support them.
        code := x"F";
        if keyboard_rows(56) = '0' and keyboard_rows(2) = '0' then
          code := x"6";                 -- #
        elsif keyboard_rows(56) = '0' and keyboard_rows(40) = '0' then
          code := x"9";                 -- *
        elsif keyboard_rows(56) = '1' then
          if    keyboard_rows(15) = '0' then code := x"A"; -- 0
          elsif keyboard_rows(5)  = '0' then code := x"D"; -- 1
          elsif keyboard_rows(13) = '0' then code := x"7"; -- 2
          elsif keyboard_rows(2)  = '0' then code := x"C"; -- 3
          elsif keyboard_rows(10) = '0' then code := x"2"; -- 4
          elsif keyboard_rows(6)  = '0' then code := x"3"; -- 5
          elsif keyboard_rows(14) = '0' then code := x"E"; -- 6
          elsif keyboard_rows(1)  = '0' then code := x"5"; -- 7
          elsif keyboard_rows(9)  = '0' then code := x"1"; -- 8
          elsif keyboard_rows(7)  = '0' then code := x"B"; -- 9
          end if;
        end if;

        -- BASIC is the original BIT90 ARM key.  Player two has no keyboard
        -- substitute, but its tape input on D7 must remain visible.
        p1 := '0' & keyboard_rows(58) & "11" & code;
        p2 := joystick_2_tape(7) & "1111111";
      else
        -- Joystick mode combines the physical first port with the keyboard.
        -- CTRL supplies the second, FIRE-side controller function.
        p1(7) := '0';
        p1(6) := joystick_1(6) and keyboard_rows(61); -- CTRL = FIRE
        p1(3) := joystick_1(3) and keyboard_rows(59); -- left
        p1(2) := joystick_1(2) and keyboard_rows(28); -- down
        p1(1) := joystick_1(1) and keyboard_rows(60); -- right
        p1(0) := joystick_1(0) and keyboard_rows(20); -- up
      end if;
    end if;

    controller_1 <= p1;
    controller_2_tape <= p2;
  end process;
end architecture;
