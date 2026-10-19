library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- BIT90 CPU, ROM and I/O core. The active configuration has the original
-- 2 KiB CPU RAM; together with the VDP's 16 KiB this is the 18 KiB machine.
entity bit90_system is
  generic (SIM_FAST_BOOT : boolean := false);
  port (
    clk                 : in  std_logic;
    reset               : in  std_logic;
    cpu_ce              : in  std_logic;
    keyboard_rows       : in  std_logic_vector(63 downto 0) := (others => '1');
    joystick_1          : in  std_logic_vector(7 downto 0) := x"7F";
    joystick_2_tape     : in  std_logic_vector(7 downto 0) := x"7F";
    controller_irq_n    : in  std_logic := '1';
    vdp_data_i          : in  std_logic_vector(7 downto 0);
    vdp_irq_n           : in  std_logic;
    vdp_rd_n            : out std_logic;
    vdp_wr_n            : out std_logic;
    vdp_mode            : out std_logic;
    vdp_data_o          : out std_logic_vector(7 downto 0);
    psg_wr_o            : out std_logic;
    psg_data_o          : out std_logic_vector(7 downto 0);
    tape_dac_o          : out std_logic_vector(1 downto 0);
    keyboard_row_o      : out std_logic_vector(2 downto 0);
    basic_rom_active_o  : out std_logic;
    expansion_enabled_o : out std_logic;
    xbas_initialized_o : out std_logic;
    cpu_pc_o            : out std_logic_vector(15 downto 0);
    debug_cpu_a_o       : out std_logic_vector(15 downto 0);
    debug_cpu_do_o      : out std_logic_vector(7 downto 0);
    debug_iorq_n_o      : out std_logic;
    debug_wr_n_o        : out std_logic;
    tape_read_strobe_o  : out std_logic;
    ram_config          : in std_logic_vector(1 downto 0) := "00";
    xbas_enable         : in std_logic := '0';
    cold_start          : in std_logic := '0';
    cart_load_wr        : in std_logic := '0';
    cart_load_addr      : in std_logic_vector(14 downto 0) := (others=>'0');
    cart_load_data      : in std_logic_vector(7 downto 0) := (others=>'0');
    cart_present        : in std_logic := '0';
    cart_size           : in std_logic_vector(15 downto 0) := x"0000";
    bas_load_wr         : in std_logic := '0';
    bas_load_addr       : in std_logic_vector(15 downto 0) := (others=>'0');
    bas_load_data       : in std_logic_vector(7 downto 0) := (others=>'0');
    save_read_addr      : in std_logic_vector(15 downto 0) := (others=>'0');
    save_read_data      : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of bit90_system is
  type ram2k_t is array (0 to 2047) of std_logic_vector(7 downto 0);
  signal ram : ram2k_t := (others => (others => '0'));
  type ram32k_t is array (0 to 32767) of std_logic_vector(7 downto 0);
  signal ext_ram : ram32k_t := (others => (others => '0'));
  type cart32k_t is array (0 to 32767) of std_logic_vector(7 downto 0);
  signal cart_ram : cart32k_t := (others => x"FF");
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
  attribute ram_style of ext_ram : signal is "block";
  attribute ram_style of cart_ram : signal is "block";

  signal cpu_a, cpu_pc : std_logic_vector(15 downto 0);
  signal cpu_di, cpu_do, rom_q, xbas_q, ram_q, ext_ram_q, cart_q : std_logic_vector(7 downto 0);
  signal save_ram_q, save_ext_q : std_logic_vector(7 downto 0) := x"00";
  signal m1_n, mreq_n, iorq_n, rd_n, wr_n : std_logic;
  signal cpu_ts : std_logic_vector(2 downto 0);
  signal cpu_wait_n, m1_wait_done : std_logic := '1';
  signal bank_basic, expansion_enabled : std_logic := '0';
  signal u32_latch : std_logic_vector(7 downto 0) := (others => '0');
  signal io_read_q, io_write_q : std_logic := '0';
  signal io_read, io_write, vdp_sel : std_logic;
  signal keyboard_data : std_logic_vector(7 downto 0);
  signal controller_keypad_mode : std_logic := '1';
  signal controller_1_data, controller_2_data : std_logic_vector(7 downto 0);
  signal psg_wr_q : std_logic := '0';
  signal tape_read_pulse_q : std_logic := '0';
  signal cold_start_pending : std_logic := '0';
  signal ram_we, ext_we : std_logic;
  signal ram_waddr : unsigned(10 downto 0);
  signal ext_waddr : unsigned(14 downto 0);
  signal ram_wdata, ext_wdata : std_logic_vector(7 downto 0);
  signal xbas_init_busy, xbas_init_done : std_logic := '0';
  signal xbas_init_index : natural range 0 to 11 := 0;
  signal cpu_run_ce : std_logic;
  function xbas_init_address(index : natural) return unsigned is
  begin
    case index is
      when 0 => return to_unsigned(16#7005#, 16);
      when 1 => return to_unsigned(16#7006#, 16);
      when 2 => return to_unsigned(16#71E8#, 16);
      when 3 => return to_unsigned(16#71E9#, 16);
      when 4 => return to_unsigned(16#71EA#, 16);
      when 5 => return to_unsigned(16#71EB#, 16);
      when 6 => return to_unsigned(16#7606#, 16);
      when 7 => return to_unsigned(16#760C#, 16);
      when 8 => return to_unsigned(16#760D#, 16);
      when 9 => return to_unsigned(16#760E#, 16);
      when 10 => return to_unsigned(16#7611#, 16);
      when others => return to_unsigned(16#7612#, 16);
    end case;
  end function;

  function xbas_init_data(index : natural) return std_logic_vector is
  begin
    case index is
      when 0 => return x"80"; -- extended token table at FD80h
      when 1 => return x"FD";
      when 2 | 4 => return x"FF"; -- HIMEM and MEMT = EFFFh
      when 3 | 5 => return x"EF";
      when 8 => return x"4E"; -- 8 data bits, no parity, one stop bit
      when 9 => return x"1C"; -- original 20-second communications timeout
      when others => return x"00";
    end case;
  end function;
begin
  controller_mux : entity work.bit90_controller
    port map(
      cartridge_active=>cart_present,
      keypad_mode=>controller_keypad_mode,
      keyboard_rows=>keyboard_rows,
      joystick_1=>joystick_1,
      joystick_2_tape=>joystick_2_tape,
      controller_1=>controller_1_data,
      controller_2_tape=>controller_2_data);

  ram_we <= '1' when xbas_init_busy='1' or (bas_load_wr='1' and unsigned(bas_load_addr)>=16#6000# and
                       unsigned(bas_load_addr)<16#8000#) or
                      (mreq_n='0' and wr_n='0' and cpu_a(15 downto 13)="011") else '0';
  ram_waddr <= xbas_init_address(xbas_init_index)(10 downto 0) when xbas_init_busy='1' else
               unsigned(bas_load_addr(10 downto 0)) when bas_load_wr='1' else unsigned(cpu_a(10 downto 0));
  ram_wdata <= xbas_init_data(xbas_init_index) when xbas_init_busy='1' else
               bas_load_data when bas_load_wr='1' else cpu_do;
  ext_we <= '1' when (bas_load_wr='1' and bas_load_addr(15)='1') or
                      (mreq_n='0' and wr_n='0' and expansion_enabled='1' and cpu_a(15)='1' and
                       (ram_config="10" or (ram_config="01" and cpu_a(14)='0'))) else '0';
  ext_waddr <= unsigned(bas_load_addr(14 downto 0)) when bas_load_wr='1' else unsigned(cpu_a(14 downto 0));
  ext_wdata <= bas_load_data when bas_load_wr='1' else cpu_do;

  cpu: entity work.T80s
    generic map(Mode => 0, T2Write => 0, IOWait => 1)
    port map(
      RESET_n => not reset, CLK_n => clk, CEN => cpu_run_ce,
      WAIT_n => cpu_wait_n, INT_n => controller_irq_n, NMI_n => vdp_irq_n,
      BUSRQ_n => '1', M1_n => m1_n, MREQ_n => mreq_n,
      IORQ_n => iorq_n, RD_n => rd_n, WR_n => wr_n,
      RFSH_n => open, HALT_n => open, BUSAK_n => open,
      A => cpu_a, DInst => cpu_di, DI => cpu_di, DO => cpu_do,
      DBG_EN => '0', DBG_REG_ADDR => (others => '0'),
      DBG_PC_LOAD => '0', DBG_PC_DATA => (others => '0'), DBG_COMMIT => '0',
      DBG_REG_DATA => open, DBG_AF => open, DBG_AF_ALT => open,
      DBG_PC => cpu_pc, DBG_SP => open, DBG_I => open, DBG_R => open,
      DBG_IR => open, DBG_IM => open, DBG_IFF => open,
      DBG_MC => open, DBG_TS => cpu_ts);

  -- The BIT90 inserts one WAIT state into every M1 opcode fetch.
  cpu_wait_n <= '0' when m1_n='0' and cpu_ts="010" and m1_wait_done='0' else '1';
  process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' or m1_n='1' then
        m1_wait_done <= '0';
      elsif cpu_ce='1' and cpu_ts="010" and m1_wait_done='0' then
        m1_wait_done <= '1';
      end if;
    end if;
  end process;

  rom: entity work.bit90_rom_v31
    generic map(SIM_FAST_BOOT => SIM_FAST_BOOT)
    port map(clk => clk, address => cpu_a, basic_bank => bank_basic, data => rom_q);
  xbas_rom: entity work.bit90_xbas_rom
    port map(clk=>clk, address=>cpu_a(11 downto 0), data=>xbas_q);
  cpu_run_ce <= cpu_ce and not xbas_init_busy;

  process(clk)
  begin
    if rising_edge(clk) then
      if ram_we='1' then
        ram(to_integer(ram_waddr)) <= ram_wdata;
      end if;
      ram_q <= ram(to_integer(unsigned(cpu_a(10 downto 0))));
      ext_ram_q <= ext_ram(to_integer(unsigned(cpu_a(14 downto 0))));
      save_ram_q <= ram(to_integer(unsigned(save_read_addr(10 downto 0))));
      save_ext_q <= ext_ram(to_integer(unsigned(save_read_addr(14 downto 0))));
      if cart_size = x"2000" then
        cart_q <= cart_ram(to_integer(unsigned(cpu_a(12 downto 0))));
      elsif cart_size = x"4000" then
        cart_q <= cart_ram(to_integer(unsigned(cpu_a(13 downto 0))));
      else
        cart_q <= cart_ram(to_integer(unsigned(cpu_a(14 downto 0))));
      end if;
      if cart_load_wr='1' then
        cart_ram(to_integer(unsigned(cart_load_addr))) <= cart_load_data;
      end if;
      if ext_we='1' then
        ext_ram(to_integer(ext_waddr)) <= ext_wdata;
      end if;
    end if;
  end process;

  -- Once the original BASIC cold start reaches its main loop, pause the CPU
  -- briefly and perform the writes made by XBASINIT at F000h. The XBAS code
  -- itself remains read-only and is mapped over the final 4 KiB of expansion RAM.
  process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' then
        xbas_init_busy <= '0';
        xbas_init_done <= '0';
        xbas_init_index <= 0;
      elsif xbas_enable='1' and ram_config="10" and bank_basic='1' and xbas_init_done='0' and
            xbas_init_busy='0' and cpu_pc=x"023A" then
        xbas_init_busy <= '1';
        xbas_init_index <= 0;
      elsif xbas_init_busy='1' then
        if xbas_init_index=11 then
          xbas_init_busy <= '0';
          xbas_init_done <= '1';
        else
          xbas_init_index <= xbas_init_index + 1;
        end if;
      end if;
    end if;
  end process;
  -- Changing the configured RAM size must force BASIC through its cold-start
  -- memory setup. Keep the mirrored "BIT90" marker invalid until the ROM has
  -- taken the cold path and writes the new marker. This avoids relying on the
  -- exact length and alignment of the first BRAM read cycle.
  process(clk)
  begin
    if rising_edge(clk) then
      if cold_start = '1' then
        cold_start_pending <= '1';
      elsif cold_start_pending = '1' and mreq_n = '0' and wr_n = '0' and
            cpu_a(15 downto 13) = "011" and cpu_a(10 downto 0) = "00000000000" then
        cold_start_pending <= '0';
      end if;
    end if;
  end process;

  io_read  <= '1' when iorq_n = '0' and rd_n = '0' else '0';
  io_write <= '1' when iorq_n = '0' and wr_n = '0' else '0';
  vdp_sel  <= '1' when cpu_a(7 downto 5) = "101" else '0';

  -- Side effects are captured once per complete Z80 I/O strobe.
  process(clk)
  begin
    if rising_edge(clk) then
      psg_wr_q <= '0';
      tape_read_pulse_q <= '0';
      if reset = '1' then
        bank_basic <= '0';             -- U4 GAME ROM after hardware reset
        expansion_enabled <= '0';
        u32_latch <= (others => '0');
        controller_keypad_mode <= '1';
        io_read_q <= '0';
        io_write_q <= '0';
      else
        if io_read = '1' and io_read_q = '0' and cpu_a(7 downto 0) = x"FF" then
          tape_read_pulse_q <= '1';
        end if;
        if io_read = '1' and io_read_q = '0' and cpu_a(7 downto 5) = "100" then
          bank_basic <= cpu_a(3);      -- 80-87/90-97 U4, 88-8F/98-9F U3
        end if;
        if io_write = '1' and io_write_q = '0' then
          if cpu_a(7 downto 5) = "100" then
            controller_keypad_mode <= '1'; -- 80h-9Fh: keypad and ARM
          elsif cpu_a(7 downto 5) = "110" then
            controller_keypad_mode <= '0'; -- C0h-DFh: stick and FIRE
          end if;
          if cpu_a(7 downto 5) = "111" and cpu_a(2) = '0' then
            u32_latch <= cpu_do;       -- keyboard row, tape DAC and Y1
          elsif cpu_a(7 downto 5) = "111" and cpu_a(2) = '1' then
            psg_wr_q <= '1';
          elsif cpu_a(7 downto 0) = x"4F" then
            expansion_enabled <= '1';
          elsif cpu_a(7 downto 0) = x"4E" then
            expansion_enabled <= '0';
          end if;
        end if;
        io_read_q <= io_read;
        io_write_q <= io_write;
      end if;
    end if;
  end process;

  process(all)
    variable row : natural range 0 to 7;
  begin
    row := to_integer(unsigned(u32_latch(6 downto 4)));
    keyboard_data <= keyboard_rows(row*8+7 downto row*8);
  end process;

  process(all)
  begin
    cpu_di <= x"FF";
    if mreq_n = '0' and rd_n = '0' then
      case cpu_a(15 downto 13) is
        when "000" | "001" => cpu_di <= rom_q;
when "011"         =>
          if xbas_enable = '1' and cpu_a = x"7005" then
            cpu_di <= x"80";
          elsif xbas_enable = '1' and cpu_a = x"7006" then
            cpu_di <= x"FD";
          elsif cold_start_pending = '1' and cpu_a(10 downto 0) = "00000000000" then
            cpu_di <= x"00";
          else
            cpu_di <= ram_q;
          end if;
        when "100" | "101" =>
          if expansion_enabled = '1' and ram_config /= "00" then
            cpu_di <= ext_ram_q;
          elsif cart_present = '1' then
            cpu_di <= cart_q;
          end if;
        when "110" | "111" =>
          if xbas_enable = '1' and cpu_a(15 downto 12) = x"F" then
            cpu_di <= xbas_q;
          elsif expansion_enabled = '1' and ram_config = "10" then
            cpu_di <= ext_ram_q;
          elsif expansion_enabled = '0' and cart_present = '1' then
            cpu_di <= cart_q;
          end if;
        when others => cpu_di <= x"FF";
      end case;
    elsif io_read = '1' then
      if vdp_sel = '1' then
        cpu_di <= vdp_data_i;
      elsif cpu_a(7 downto 5) = "110" then
        cpu_di <= keyboard_data;
      elsif cpu_a(7 downto 5) = "111" then
        if cpu_a(1) = '0' then cpu_di <= controller_1_data;
        else cpu_di <= controller_2_data;
        end if;
      end if;
    end if;
  end process;


  process(all)
  begin
    save_read_data <= x"FF";
    if unsigned(save_read_addr) >= 16#6000# and unsigned(save_read_addr) < 16#8000# then
      save_read_data <= save_ram_q;
    elsif save_read_addr(15) = '1' and
          (ram_config = "10" or (ram_config = "01" and save_read_addr(14) = '0')) then
      save_read_data <= save_ext_q;
    end if;
  end process;
  vdp_rd_n <= rd_n when iorq_n = '0' and vdp_sel = '1' else '1';
  vdp_wr_n <= wr_n when iorq_n = '0' and vdp_sel = '1' else '1';
  vdp_mode <= cpu_a(0);
  vdp_data_o <= cpu_do;
  psg_wr_o <= psg_wr_q;
  psg_data_o <= cpu_do;
  tape_dac_o <= u32_latch(1 downto 0);
  keyboard_row_o <= u32_latch(6 downto 4);
  basic_rom_active_o <= bank_basic;
  expansion_enabled_o <= expansion_enabled;
  xbas_initialized_o <= xbas_init_done;
  cpu_pc_o <= cpu_pc;
  debug_cpu_a_o <= cpu_a;
  debug_cpu_do_o <= cpu_do;
  debug_iorq_n_o <= iorq_n;
  debug_wr_n_o <= wr_n;
  tape_read_strobe_o <= tape_read_pulse_q;
end architecture;
