library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.bit90_test_patterns.all;

-- A small bus master, not a CPU: all VRAM/register changes use the real VDP ports.
-- 16 us between operations is deliberately conservative for the bring-up.
entity bit90_vdp_demo is
  generic(bus_period : positive := 1600; dwell_cycles : positive := 400000000);
  port(clk, reset : in std_logic;
       dout : in std_logic_vector(7 downto 0);
       rd_n, wr_n, mode : out std_logic;
       din : out std_logic_vector(7 downto 0);
       mode_num : out integer range 0 to 3;
       ready, failed : out std_logic;
       status : out std_logic_vector(7 downto 0));
end;
architecture rtl of bit90_vdp_demo is
  -- 0/1: write address. 2..16385: fill VRAM.
  -- 16386/7: read address 0000, then verify 16 sequential reads.
  -- 16404..16419: eight register pairs. 16420: idle/status poll.
  type rom_t is array(0 to 16383) of std_logic_vector(7 downto 0);
  function init_image return rom_t is
    variable result : rom_t;
  begin
    for a in result'range loop result(a):=vram_byte(a); end loop;
    return result;
  end;
  signal image : rom_t := init_image;
  attribute rom_style : string;
  attribute rom_style of image : signal is "block";
  signal image_address : natural range 0 to 16383 := 0;
  signal image_data : std_logic_vector(7 downto 0);
  signal step : natural range 0 to 16420 := 0;
  signal phase : natural range 0 to bus_period-1 := 0;
  signal dwell : natural range 0 to dwell_cycles-1 := 0;
  signal m : natural range 0 to 3 := 0;
  signal error_q, ready_q : std_logic := '0';
begin
  image_address <= step-2 when step>=2 and step<16386 else 0;
  process(clk)
  begin
    if rising_edge(clk) then image_data <= image(image_address); end if;
  end process;
  mode_num <= m; ready <= ready_q; failed <= error_q;
  process(all)
    variable r : natural;
  begin
    rd_n <= '1'; wr_n <= '1'; mode <= '1'; din <= x"00";
    if step = 1 then din <= x"40";
    elsif step >= 2 and step < 16386 then mode <= '0'; din <= image_data;
    elsif step >= 16388 and step < 16404 then mode <= '0';
    elsif step >= 16404 and step < 16420 then
      r := (step-16404)/2;
      if step mod 2 = 0 then din <= register_byte(r,m);
      else din <= std_logic_vector(to_unsigned(128+r,8)); end if;
    end if;
    if reset = '0' and phase >= 16 and phase < 80 then
      if (step >= 16388 and step < 16404) or step = 16420 then rd_n <= '0';
      else wr_n <= '0'; end if;
    end if;
  end process;
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        step <= 0; phase <= 0; dwell <= 0; m <= 0;
        error_q <= '0'; ready_q <= '0'; status <= (others=>'0');
      else
        if step < 16420 then ready_q <= '0'; end if;
        if phase = 64 then
          if step >= 16388 and step < 16404 then
            if dout /= vram_byte(step-16388) then error_q <= '1'; end if;
          elsif step = 16420 then status <= dout;
          end if;
        end if;
        if phase = bus_period-1 then
          phase <= 0;
          if step < 16420 then step <= step+1; end if;
        else phase <= phase+1; end if;
        if step = 16420 then
          ready_q <= '1';
          if dwell = dwell_cycles-1 then
            dwell <= 0; m <= (m+1) mod 4; step <= 16404; phase <= 0; ready_q <= '0';
          else dwell <= dwell+1; end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
