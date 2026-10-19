library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package bit90_test_patterns is
  -- VRAM: fonts 0000-17FF, graphics names 1800, text names 1C00,
  -- SAT 1B00, colors 2000-37FF, sprites/MC patterns 3800, MC names 3C00.
  function vram_byte(a : natural) return std_logic_vector;
  function register_byte(r, mode_num : natural) return std_logic_vector;
end package;

package body bit90_test_patterns is
  function vram_byte(a : natural) return std_logic_vector is
  begin
    return work.bit90_demo_image.demo_image(a);
  end;
  function register_byte(r, mode_num : natural) return std_logic_vector is
    variable v : natural := 0;
  begin
    case r is
      when 0 => if mode_num = 1 then v := 2; end if;
      when 1 =>
        case mode_num is
          when 2 => v := 16#EA#; -- multicolor, IRQ, 16x16 sprites
          when 3 => v := 16#F0#; -- 40-column text, no sprites
          when others => v := 16#E2#;
        end case;
      when 2 =>
        if mode_num=3 then v:=7; elsif mode_num=2 then v:=15; else v:=6; end if;
      when 3 => if mode_num = 1 then v := 255; else v := 128; end if;
      when 4 => if mode_num = 1 then v := 3; elsif mode_num=2 then v:=7; end if;
      when 5 => v := 54;
      when 6 => v := 7;
      when 7 => v := 16#F4#;
      when others => null;
    end case;
    return std_logic_vector(to_unsigned(v, 8));
  end;
end package body;
