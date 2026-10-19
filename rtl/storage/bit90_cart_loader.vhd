library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bit90_cart_loader is
  port(
    clk, reset : in std_logic;
    start : in std_logic;
    selected_valid : in std_logic;
    selected_cluster, selected_size : in std_logic_vector(31 downto 0);
    file_read_busy, file_read_done, file_read_error : in std_logic;
    file_read_wr : in std_logic;
    file_read_addr : in std_logic_vector(15 downto 0);
    file_read_data : in std_logic_vector(7 downto 0);
    file_start : out std_logic;
    file_cluster, file_size : out std_logic_vector(31 downto 0);
    cart_wr : out std_logic;
    cart_addr : out std_logic_vector(14 downto 0);
    cart_data : out std_logic_vector(7 downto 0);
    cart_present : out std_logic;
    cart_size : out std_logic_vector(15 downto 0);
    busy, done, error : out std_logic;
    status : out std_logic_vector(3 downto 0);
    core_reset_req : out std_logic
  );
end entity;

architecture rtl of bit90_cart_loader is
  type state_t is (IDLE, CLEAR_RAM, START_READ, WAIT_ACTIVE, WAIT_DONE);
  signal state : state_t := IDLE;
  signal clear_addr : unsigned(14 downto 0) := (others=>'0');
  signal cluster_q, size_q : std_logic_vector(31 downto 0) := (others=>'0');
  signal signature_lo, signature_hi : std_logic_vector(7 downto 0) := x"00";
  signal present_q, done_q, error_q : std_logic := '0';
  signal status_q : std_logic_vector(3 downto 0) := x"0";
  signal size16_q : std_logic_vector(15 downto 0) := x"0000";
  signal reset_count : natural range 0 to 1023 := 0;
begin
  file_cluster <= cluster_q;
  file_size <= size_q;
  cart_present <= present_q;
  cart_size <= size16_q;
  busy <= '1' when state /= IDLE else '0';
  done <= done_q;
  error <= error_q;
  status <= status_q;
  core_reset_req <= '1' when reset_count /= 0 else '0';
  file_start <= '1' when state = START_READ else '0';

  cart_wr <= '1' when state = CLEAR_RAM or
                      ((state = WAIT_ACTIVE or state = WAIT_DONE) and file_read_wr='1')
             else '0';
  cart_addr <= std_logic_vector(clear_addr) when state = CLEAR_RAM
               else file_read_addr(14 downto 0);
  cart_data <= x"FF" when state = CLEAR_RAM else file_read_data;

  process(clk)
    variable file_bytes : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      done_q <= '0';
      if reset_count /= 0 then reset_count <= reset_count - 1; end if;
      if reset='1' then
        state <= IDLE;
        clear_addr <= (others=>'0');
        cluster_q <= (others=>'0');
        size_q <= (others=>'0');
        signature_lo <= x"00";
        signature_hi <= x"00";
        present_q <= '0';
        size16_q <= x"0000";
        error_q <= '0';
        status_q <= x"0";
        reset_count <= 0;
      else
        if file_read_wr='1' and (state=WAIT_ACTIVE or state=WAIT_DONE) then
          if unsigned(file_read_addr)=0 then signature_lo <= file_read_data; end if;
          if unsigned(file_read_addr)=1 then signature_hi <= file_read_data; end if;
        end if;
        case state is
          when IDLE =>
            if start='1' then
              error_q <= '0';
              status_q <= x"0";
              present_q <= '0';
              signature_lo <= x"00";
              signature_hi <= x"00";
              file_bytes := unsigned(selected_size);
              if selected_valid='0' then
                error_q <= '1';
                status_q <= x"1";
              elsif file_bytes < 2 or file_bytes > 32768 then
                error_q <= '1';
                status_q <= x"2";
              else
                cluster_q <= selected_cluster;
                size_q <= selected_size;
                size16_q <= selected_size(15 downto 0);
                clear_addr <= (others=>'0');
                state <= CLEAR_RAM;
              end if;
            end if;

          when CLEAR_RAM =>
            if clear_addr = to_unsigned(32767, clear_addr'length) then
              state <= START_READ;
            else
              clear_addr <= clear_addr + 1;
            end if;

          when START_READ =>
            state <= WAIT_ACTIVE;

          when WAIT_ACTIVE =>
            if file_read_error='1' then
              error_q <= '1'; status_q <= x"3"; state <= IDLE;
            elsif file_read_done='0' or file_read_busy='1' then
              state <= WAIT_DONE;
            end if;

          when WAIT_DONE =>
            if file_read_error='1' then
              error_q <= '1'; status_q <= x"3"; state <= IDLE;
            elsif file_read_done='1' and file_read_busy='0' then
              if (signature_lo=x"55" and signature_hi=x"AA") or
                 (signature_lo=x"AA" and signature_hi=x"55") then
                present_q <= '1';
                done_q <= '1';
                reset_count <= 1023;
                state <= IDLE;
              else
                error_q <= '1';
                status_q <= x"4";
                state <= IDLE;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
