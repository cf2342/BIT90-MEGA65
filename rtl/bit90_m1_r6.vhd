library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tyto_types_pkg.all;
library unisim;
use unisim.vcomponents.all;

entity bit90_m1_r6 is
  port(CLK_IN, reset_button : in std_logic;
       led : out std_logic;
       TMDS_clk_p, TMDS_clk_n : out std_logic;
       TMDS_data_p, TMDS_data_n : out std_logic_vector(0 to 2);
       hdmi_enable_n, hdmi_hiz : out std_logic);
end;
architecture rtl of bit90_m1_r6 is
  signal pclk, sclk, locked, arst, rst, prst : std_logic;
  signal srst_pipe, prst_pipe : std_logic_vector(2 downto 0) := (others=>'1');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of srst_pipe, prst_pipe : signal is "TRUE";
  signal accumulator : natural range 0 to 99999999 := 0;
  signal ce : std_logic := '0';
  signal rd_n, wr_n, mode, irq_n, pixel_ce, ready, failed : std_logic;
  signal din, dout, status : std_logic_vector(7 downto 0);
  signal color : std_logic_vector(3 downto 0);
  signal px : integer range 0 to 255;
  signal py : integer range 0 to 191;
  signal mode_num : integer range 0 to 3;
  signal red, green, blue : std_logic_vector(7 downto 0);
  signal hs, vs, de, tclk : std_logic;
  signal serial : std_logic_vector(0 to 2);
  signal encoded : slv10_vector(0 to 2);
  signal heartbeat : unsigned(25 downto 0) := (others=>'0');
begin
  clocking: entity work.bit90_video_clock
    port map(CLK_IN, '0', pclk, sclk, locked);
  arst <= reset_button or not locked;
  process(CLK_IN, arst)
  begin
    if arst='1' then srst_pipe <= (others=>'1');
    elsif rising_edge(CLK_IN) then srst_pipe <= srst_pipe(1 downto 0)&'0'; end if;
  end process;
  process(pclk, arst)
  begin
    if arst='1' then prst_pipe <= (others=>'1');
    elsif rising_edge(pclk) then prst_pipe <= prst_pipe(1 downto 0)&'0'; end if;
  end process;
  rst <= srst_pipe(2); prst <= prst_pipe(2);
  process(CLK_IN)
  begin
    if rising_edge(CLK_IN) then
      ce <= '0';
      if rst='1' then accumulator <= 0; heartbeat <= (others=>'0');
      else
        heartbeat <= heartbeat+1;
        -- 10.738635 MHz average, 10 ns clock-enable quantisation.
        if accumulator >= 89261365 then
          accumulator <= accumulator-89261365; ce <= '1';
        else accumulator <= accumulator+10738635; end if;
      end if;
    end if;
  end process;
  led <= '1' when failed='1' else heartbeat(25) when ready='1' else '0';
  demo: entity work.bit90_vdp_demo
    port map(CLK_IN,rst,dout,rd_n,wr_n,mode,din,mode_num,ready,failed,status);
  vdp: entity work.bit90_vdp
    port map(CLK_IN,rst,ce,rd_n,wr_n,mode,din,dout,irq_n,
      pixel_ce,px,py,color,open,open,open,open,x"1",open);
  display: entity work.bit90_framebuffer
    port map(CLK_IN,rst,ready,pixel_ce,px,py,color,
      pclk,prst,red,green,blue,hs,vs,de,'0',"00",open,open);
  enc_b: entity work.TMDS_Encoder
    port map(pclk,sclk,prst,encoded(0),blue,hs,vs,de);
  enc_g: entity work.TMDS_Encoder
    port map(pclk,sclk,prst,encoded(1),green,'0','0',de);
  enc_r: entity work.TMDS_Encoder
    port map(pclk,sclk,prst,encoded(2),red,'0','0',de);
  serializer: entity work.hdmi_tx_selectio
    port map(sclk,prst,pclk,encoded,tclk,serial);
  clk_buf: OBUFDS generic map(IOSTANDARD=>"TMDS_33")
    port map(I=>tclk,O=>TMDS_clk_p,OB=>TMDS_clk_n);
  data_buf: for i in 0 to 2 generate
    buf: OBUFDS generic map(IOSTANDARD=>"TMDS_33")
      port map(I=>serial(i),O=>TMDS_data_p(i),OB=>TMDS_data_n(i));
  end generate;
  hdmi_enable_n <= '0'; hdmi_hiz <= '0';
end;




