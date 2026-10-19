library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vfat_name_pkg.all;

-- Decodes the VFAT long-name entries which precede a normal FAT 8.3 entry.
-- The module is deliberately independent of the SD controller and machine UI.
entity vfat_lfn_decoder is
  port (
    clk              : in  std_logic;
    reset            : in  std_logic;
    clear            : in  std_logic := '0';
    byte_valid       : in  std_logic;
    entry_byte_index : in  integer range 0 to 31;
    entry_byte       : in  std_logic_vector(7 downto 0);
    display_name     : out vfat_display_name_t;
    long_name_valid  : out std_logic;
    name_truncated   : out std_logic
  );
end entity;

architecture rtl of vfat_lfn_decoder is
  type entry_bytes_t is array (0 to 31) of std_logic_vector(7 downto 0);
  type display_chars_t is array (0 to VFAT_DISPLAY_CHARS-1)
    of std_logic_vector(7 downto 0);

  signal entry_bytes : entry_bytes_t := (others => (others => '0'));
  signal working_chars : display_chars_t := (others => x"20");
  signal working_length : integer range 0 to 255 := 0;
  signal chain_active : std_logic := '0';
  signal chain_checksum : std_logic_vector(7 downto 0) := (others => '0');
  signal expected_ordinal : integer range 0 to 20 := 0;
  signal short_checksum : std_logic_vector(7 downto 0) := (others => '0');
  signal entry_pending : std_logic := '0';
  signal pending_slot : integer range 0 to 12 := 0;
  signal pending_ordinal : integer range 1 to 20 := 1;
  signal display_name_q : vfat_display_name_t := (others => '0');
  signal long_name_valid_q, name_truncated_q : std_logic := '0';
  signal working_dot_position : integer range -1 to VFAT_DISPLAY_CHARS-1 := -1;
  signal finalize_pending, finalize_use_lfn : std_logic := '0';
  signal finalize_index : integer range 0 to VFAT_DISPLAY_CHARS-1 := 0;
  signal finalize_length : integer range 0 to VFAT_DISPLAY_CHARS := 0;

  function checksum_step(
    sum_i : std_logic_vector(7 downto 0);
    byte_i : std_logic_vector(7 downto 0))
    return std_logic_vector is
    variable value : unsigned(7 downto 0);
  begin
    value := rotate_right(unsigned(sum_i), 1) + unsigned(byte_i);
    return std_logic_vector(value);
  end function;

  function display_byte(low_byte, high_byte : std_logic_vector(7 downto 0))
    return std_logic_vector is
    variable result : std_logic_vector(7 downto 0) := x"3F";
  begin
    if high_byte=x"00" and unsigned(low_byte)>=32 and unsigned(low_byte)<=126 then
      result := low_byte;
    end if;
    return result;
  end function;


begin
  display_name <= display_name_q;
  long_name_valid <= long_name_valid_q;
  name_truncated <= name_truncated_q;

  process(clk)
    variable ordinal, next_length : integer;
    variable global_position, visible_length : integer;
    variable low_byte, high_byte, output_byte : std_logic_vector(7 downto 0);
    variable code_is_end, code_is_padding, entry_ok : boolean;
  begin
    if rising_edge(clk) then
      if reset='1' or clear='1' then
        entry_bytes <= (others => (others => '0'));
        working_chars <= (others => x"20");
        working_length <= 0;
        chain_active <= '0';
        chain_checksum <= (others => '0');
        expected_ordinal <= 0;
        short_checksum <= (others => '0');
        entry_pending <= '0';
        pending_slot <= 0;
        pending_ordinal <= 1;
        display_name_q <= (others => '0');
        long_name_valid_q <= '0';
        name_truncated_q <= '0';
        working_dot_position <= -1;
        finalize_pending <= '0';
        finalize_use_lfn <= '0';
        finalize_index <= 0;
        finalize_length <= 0;
      else
        -- Serialize the selected name into the packed output. Directory bytes
        -- arrive far slower than clk, so this removes a wide 224-bit
        -- combinational path without delaying the directory scanner.
        if finalize_pending='1' then
          output_byte := x"20";
          if finalize_use_lfn='1' then
            if finalize_index<finalize_length then
              output_byte := working_chars(finalize_index);
            end if;
          elsif finalize_index<8 and entry_bytes(finalize_index)/=x"20" then
            output_byte := entry_bytes(finalize_index);
          end if;
          display_name_q <=
            display_name_q(display_name_q'high-8 downto 0) & output_byte;
          if finalize_index=VFAT_DISPLAY_CHARS-1 then
            finalize_pending <= '0';
            long_name_valid_q <= finalize_use_lfn;
          else
            finalize_index <= finalize_index+1;
          end if;
        end if;

        -- Process one UTF-16 code unit per clock. An SD directory byte takes
        -- many clk cycles, so all 13 characters finish before the next entry.
        if entry_pending='1' then
          case pending_slot is
            when 0 => low_byte:=entry_bytes(1); high_byte:=entry_bytes(2);
            when 1 => low_byte:=entry_bytes(3); high_byte:=entry_bytes(4);
            when 2 => low_byte:=entry_bytes(5); high_byte:=entry_bytes(6);
            when 3 => low_byte:=entry_bytes(7); high_byte:=entry_bytes(8);
            when 4 => low_byte:=entry_bytes(9); high_byte:=entry_bytes(10);
            when 5 => low_byte:=entry_bytes(14); high_byte:=entry_bytes(15);
            when 6 => low_byte:=entry_bytes(16); high_byte:=entry_bytes(17);
            when 7 => low_byte:=entry_bytes(18); high_byte:=entry_bytes(19);
            when 8 => low_byte:=entry_bytes(20); high_byte:=entry_bytes(21);
            when 9 => low_byte:=entry_bytes(22); high_byte:=entry_bytes(23);
            when 10=> low_byte:=entry_bytes(24); high_byte:=entry_bytes(25);
            when 11=> low_byte:=entry_bytes(28); high_byte:=entry_bytes(29);
            when others=>low_byte:=entry_bytes(30); high_byte:=entry_bytes(31);
          end case;

          global_position := (pending_ordinal-1)*13 + pending_slot;
          code_is_end := low_byte=x"00" and high_byte=x"00";
          code_is_padding := low_byte=x"FF" and high_byte=x"FF";
          if code_is_end and global_position<working_length then
            working_length <= global_position;
          elsif not code_is_end and not code_is_padding and
                global_position<VFAT_DISPLAY_CHARS then
            working_chars(global_position) <= display_byte(low_byte, high_byte);
            if low_byte=x"2E" and high_byte=x"00" and
               global_position>working_dot_position then
              working_dot_position <= global_position;
            end if;
          end if;

          if pending_slot=12 then
            entry_pending <= '0';
          else
            pending_slot <= pending_slot+1;
          end if;
        end if;

        if byte_valid='1' then
          entry_bytes(entry_byte_index) <= entry_byte;

          -- Calculate the checksum of each ordinary 8.3 entry while its eleven
          -- alias bytes arrive. At byte 11 the accumulated value is complete.
          if entry_byte_index=0 then
            short_checksum <= checksum_step(x"00", entry_byte);
          elsif entry_byte_index>=1 and entry_byte_index<=10 then
            short_checksum <= checksum_step(short_checksum, entry_byte);
          end if;

          -- Attribute byte: resolve the name of an ordinary entry. LFN entries
          -- themselves are accepted after their final byte below.
          if entry_byte_index=11 and entry_byte/=x"0F" then
            display_name_q <= (others => '0');
            long_name_valid_q <= '0';
            name_truncated_q <= '0';
            finalize_index <= 0;
            finalize_pending <= '1';

            if chain_active='1' and expected_ordinal=0 and
               short_checksum=chain_checksum and entry_pending='0' then
              -- The browser already filters by file kind, so omit the final
              -- extension whenever its dot is inside the visible prefix.
              if working_dot_position>0 then
                visible_length := working_dot_position;
              else
                visible_length := working_length;
              end if;
              if visible_length>VFAT_DISPLAY_CHARS then
                visible_length := VFAT_DISPLAY_CHARS;
                name_truncated_q <= '1';
              end if;
              finalize_use_lfn <= '1';
              finalize_length <= visible_length;
            else
              -- No valid LFN chain: serialize the unpadded eight-character
              -- alias base. The extension is already implied by the browser.
              finalize_use_lfn <= '0';
              finalize_length <= 8;
            end if;

            chain_active <= '0';
            expected_ordinal <= 0;
          end if;

          if entry_byte_index=31 then
            ordinal := to_integer(unsigned(entry_bytes(0)(4 downto 0)));
            entry_ok := entry_bytes(11)=x"0F" and
                        entry_bytes(0)/=x"E5" and
                        ordinal>=1 and ordinal<=20 and
                        entry_bytes(12)=x"00" and
                        entry_bytes(26)=x"00" and entry_bytes(27)=x"00";

            if entry_ok and entry_bytes(0)(6)='1' then
              working_chars <= (others => x"20");
              working_dot_position <= -1;
              next_length := ordinal*13;
              if next_length>255 then next_length:=255; end if;
              working_length <= next_length;
              chain_checksum <= entry_bytes(13);
              chain_active <= '1';
              expected_ordinal <= ordinal-1;
              pending_ordinal <= ordinal;
              pending_slot <= 0;
              entry_pending <= '1';
            elsif entry_ok and chain_active='1' and
                  ordinal=expected_ordinal and entry_bytes(13)=chain_checksum then
              if expected_ordinal>0 then expected_ordinal<=expected_ordinal-1; end if;
              pending_ordinal <= ordinal;
              pending_slot <= 0;
              entry_pending <= '1';
            elsif entry_bytes(11)=x"0F" then
              chain_active <= '0';
              expected_ordinal <= 0;
              entry_pending <= '0';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
