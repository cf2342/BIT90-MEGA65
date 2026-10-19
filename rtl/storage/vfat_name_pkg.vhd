library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vfat_name_pkg is
  constant VFAT_DISPLAY_CHARS : positive := 28;
  subtype vfat_display_name_t is
    std_logic_vector(VFAT_DISPLAY_CHARS*8-1 downto 0);
  type vfat_display_name_array_t is
    array (natural range <>) of vfat_display_name_t;

  constant VFAT_SAVE_BASE_CHARS : positive := 22;
  subtype vfat_save_name_t is
    std_logic_vector(VFAT_SAVE_BASE_CHARS*8-1 downto 0);

  function vfat_save_name_length(name : vfat_save_name_t) return natural;
  function vfat_save_needs_lfn(name : vfat_save_name_t) return boolean;
  function vfat_save_lfn_count(name : vfat_save_name_t) return natural;
  function vfat_save_display_name(name : vfat_save_name_t)
    return vfat_display_name_t;
  function vfat_save_short_name(name : vfat_save_name_t;
                                extension : std_logic_vector(23 downto 0);
                                suffix : positive := 1)
    return std_logic_vector;
  function vfat_checksum_step(sum_value, name_byte : std_logic_vector(7 downto 0))
    return std_logic_vector;
  function vfat_short_name_checksum(name : std_logic_vector(87 downto 0))
    return std_logic_vector;
  function vfat_lfn_entry_byte_known_length(
                               name : vfat_save_name_t;
                               base_length : natural;
                               extension : std_logic_vector(23 downto 0);
                               ordinal : positive;
                               last_entry : boolean;
                               byte_index : natural;
                               checksum : std_logic_vector(7 downto 0))
    return std_logic_vector;
  function vfat_lfn_entry_byte(name : vfat_save_name_t;
                               extension : std_logic_vector(23 downto 0);
                               ordinal : positive;
                               last_entry : boolean;
                               byte_index : natural;
                               checksum : std_logic_vector(7 downto 0))
    return std_logic_vector;
end package;

package body vfat_name_pkg is
  function name_byte(name : vfat_save_name_t; position : natural)
    return std_logic_vector is
  begin
    return name(name'high-position*8 downto name'high-position*8-7);
  end function;

  function vfat_save_name_length(name : vfat_save_name_t) return natural is
  begin
    for i in VFAT_SAVE_BASE_CHARS-1 downto 0 loop
      if name_byte(name, i)/=x"20" and name_byte(name, i)/=x"00" then
        return i+1;
      end if;
    end loop;
    return 0;
  end function;

  function vfat_save_needs_lfn(name : vfat_save_name_t) return boolean is
    variable length : natural := vfat_save_name_length(name);
    variable ch : std_logic_vector(7 downto 0);
  begin
    if length>8 then return true; end if;
    for i in 0 to VFAT_SAVE_BASE_CHARS-1 loop
      exit when i>=length;
      ch := name_byte(name, i);
      if not ((unsigned(ch)>=character'pos('A') and unsigned(ch)<=character'pos('Z')) or
              (unsigned(ch)>=character'pos('0') and unsigned(ch)<=character'pos('9')) or
              ch=x"2D" or ch=x"5F") then
        return true;
      end if;
    end loop;
    return false;
  end function;

  function vfat_save_lfn_count(name : vfat_save_name_t) return natural is
    variable full_length : natural;
  begin
    if not vfat_save_needs_lfn(name) then return 0; end if;
    full_length := vfat_save_name_length(name)+4;
    return (full_length+12)/13;
  end function;

  function vfat_save_display_name(name : vfat_save_name_t)
    return vfat_display_name_t is
    variable result : vfat_display_name_t := (others => '0');
  begin
    for i in 0 to VFAT_DISPLAY_CHARS-1 loop
      result(result'high-i*8 downto result'high-i*8-7) := x"20";
    end loop;
    for i in 0 to VFAT_SAVE_BASE_CHARS-1 loop
      result(result'high-i*8 downto result'high-i*8-7) := name_byte(name, i);
    end loop;
    return result;
  end function;

  function vfat_save_short_name(name : vfat_save_name_t;
                                extension : std_logic_vector(23 downto 0);
                                suffix : positive := 1)
    return std_logic_vector is
    variable result : std_logic_vector(87 downto 0) := (others => '0');
    variable ch : std_logic_vector(7 downto 0);
    variable length : natural := vfat_save_name_length(name);
  begin
    for i in 0 to 7 loop
      result(result'high-i*8 downto result'high-i*8-7) := x"20";
    end loop;
    result(23 downto 0) := extension;
    if not vfat_save_needs_lfn(name) then
      for i in 0 to 7 loop
        exit when i>=length;
        result(result'high-i*8 downto result'high-i*8-7) := name_byte(name, i);
      end loop;
    else
      for i in 0 to 5 loop
        if i<length then ch:=name_byte(name, i); else ch:=x"5F"; end if;
        if ch=x"20" or ch=x"00" then ch:=x"5F"; end if;
        result(result'high-i*8 downto result'high-i*8-7) := ch;
      end loop;
      result(39 downto 32) := x"7E";
      if suffix<=9 then
        result(31 downto 24) := std_logic_vector(to_unsigned(character'pos('0')+suffix, 8));
      else
        result(31 downto 24) := x"39";
      end if;
    end if;
    return result;
  end function;

  function vfat_checksum_step(sum_value, name_byte : std_logic_vector(7 downto 0))
    return std_logic_vector is
  begin
    return std_logic_vector(rotate_right(unsigned(sum_value),1)+unsigned(name_byte));
  end function;

  function vfat_short_name_checksum(name : std_logic_vector(87 downto 0))
    return std_logic_vector is
    variable sum : std_logic_vector(7 downto 0) := (others => '0');
  begin
    for i in 0 to 10 loop
      sum:=vfat_checksum_step(sum,name(name'high-i*8 downto name'high-i*8-7));
    end loop;
    return sum;
  end function;

  function vfat_lfn_entry_byte_known_length(
                               name : vfat_save_name_t;
                               base_length : natural;
                               extension : std_logic_vector(23 downto 0);
                               ordinal : positive;
                               last_entry : boolean;
                               byte_index : natural;
                               checksum : std_logic_vector(7 downto 0))
    return std_logic_vector is
    variable slot : integer := -1;
    variable position, length : natural;
    variable ch : std_logic_vector(7 downto 0) := x"FF";
    variable result : std_logic_vector(7 downto 0) := x"FF";
  begin
    case byte_index is
      when 0 =>
        result:=std_logic_vector(to_unsigned(ordinal, 8));
        if last_entry then result(6):='1'; end if;
        return result;
      when 11 => return x"0F";
      when 12 => return x"00";
      when 13 => return checksum;
      when 26 | 27 => return x"00";
      when 1 | 2=>slot:=0; when 3 | 4=>slot:=1;
      when 5 | 6=>slot:=2; when 7 | 8=>slot:=3;
      when 9 | 10=>slot:=4; when 14 | 15=>slot:=5;
      when 16 | 17=>slot:=6; when 18 | 19=>slot:=7;
      when 20 | 21=>slot:=8; when 22 | 23=>slot:=9;
      when 24 | 25=>slot:=10; when 28 | 29=>slot:=11;
      when 30 | 31=>slot:=12;
      when others=>return x"00";
    end case;
    position := (ordinal-1)*13+natural(slot);
    length := base_length+4;
    if position<length then
      if position<base_length then
        ch:=name_byte(name, position);
      elsif position=base_length then
        ch:=x"2E";
      else
        case position-base_length is
          when 1=>ch:=extension(23 downto 16);
          when 2=>ch:=extension(15 downto 8);
          when others=>ch:=extension(7 downto 0);
        end case;
      end if;
      case byte_index is
        when 1 | 3 | 5 | 7 | 9 | 14 | 16 | 18 | 20 | 22 | 24 | 28 | 30 =>
          result:=ch;
        when others => result:=x"00";
      end case;
    elsif position=length then
      result:=x"00";
    else
      result:=x"FF";
    end if;
    return result;
  end function;

  function vfat_lfn_entry_byte(name : vfat_save_name_t;
                               extension : std_logic_vector(23 downto 0);
                               ordinal : positive;
                               last_entry : boolean;
                               byte_index : natural;
                               checksum : std_logic_vector(7 downto 0))
    return std_logic_vector is
  begin
    return vfat_lfn_entry_byte_known_length(
      name,vfat_save_name_length(name),extension,ordinal,last_entry,byte_index,checksum);
  end function;
end package body;
