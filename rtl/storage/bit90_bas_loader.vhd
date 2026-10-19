library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Converts an ASCII .BAS file to the native tokenized BIT90 program layout.
entity bit90_bas_loader is
  port(
    clk, reset, start : in std_logic;
    ram_config : in std_logic_vector(1 downto 0);
    selected_valid : in std_logic;
    selected_cluster, selected_size : in std_logic_vector(31 downto 0);
    file_read_busy, file_read_done, file_read_error, file_read_wr : in std_logic;
    file_read_addr : in std_logic_vector(15 downto 0);
    file_read_data : in std_logic_vector(7 downto 0);
    file_start : out std_logic;
    file_cluster, file_size : out std_logic_vector(31 downto 0);
    mem_wr : out std_logic;
    mem_addr : out std_logic_vector(15 downto 0);
    mem_data : out std_logic_vector(7 downto 0);
    busy, done, error : out std_logic;
    status : out std_logic_vector(3 downto 0)
  );
end;

architecture rtl of bit90_bas_loader is
  type src_t is array(0 to 16383) of std_logic_vector(7 downto 0);
  signal src : src_t;
  attribute ram_style : string;
  attribute ram_style of src : signal is "block";
  type state_t is (IDLE, START_READ, WAIT_READ, SEEK_LINE, FIND_EOL, PARSE_NUM,
    EMIT_PTR_LO, EMIT_PTR_HI, EMIT_BCD_LO, EMIT_BCD_HI, TOKEN_PREP,
    TOKEN_SKIP, TOKEN_SCAN, TOKEN_COMPARE, EMIT_TOKEN, EMIT_CHAR,
    SKIP_AFTER_TOKEN, EMIT_EOL, PATCH_LO, PATCH_HI, FINAL_LO, FINAL_HI,
    SET_ADDR_LO, SET_ADDR_HI, SET_LINE_LO, SET_LINE_HI,
    SET_DIMED_LO, SET_DIMED_HI, SET_DIMA_LO, SET_DIMA_HI,
    SET_DTAD_LO, SET_DTAD_HI, SET_CLEAR, COMPLETE, FAILED);
  signal state : state_t := IDLE;
  signal cluster_q,size_q : std_logic_vector(31 downto 0):=(others=>'0');
  signal src_size, src_pos, scan_pos, line_end, line_next, last_nonspace : unsigned(14 downto 0):=(others=>'0');
  signal dst, line_start, terminal_addr, vars_addr : unsigned(15 downto 0):=(others=>'0');
  signal mem_limit : unsigned(16 downto 0):=(others=>'0');
  signal line_num,last_line : integer range 0 to 9999 := 0;
  signal digit_count : integer range 0 to 5 := 0;
  signal token_idx : integer range 0 to 115 := 0;
  signal match_pos : integer range 0 to 31 := 0;
  signal quoted, rem_mode : std_logic:='0';
  signal wr_q,done_q,error_q : std_logic:='0';
  signal addr_q : std_logic_vector(15 downto 0):=(others=>'0');
  signal data_q : std_logic_vector(7 downto 0):=(others=>'0');
  signal status_q : std_logic_vector(3 downto 0):=x"0";
  signal src_rd_addr, src_q_addr : unsigned(14 downto 0):=(others=>'0');
  signal src_q : std_logic_vector(7 downto 0):=x"00";
  function kw_len(i : natural) return natural is
  begin
    case i is
      when 0 => return 3;
      when 1 => return 4;
      when 2 => return 4;
      when 3 => return 4;
      when 4 => return 6;
      when 5 => return 3;
      when 6 => return 4;
      when 7 => return 4;
      when 8 => return 5;
      when 9 => return 5;
      when 10 => return 4;
      when 11 => return 5;
      when 12 => return 3;
      when 13 => return 4;
      when 14 => return 3;
      when 15 => return 4;
      when 16 => return 4;
      when 17 => return 4;
      when 18 => return 5;
      when 19 => return 4;
      when 20 => return 4;
      when 21 => return 4;
      when 22 => return 3;
      when 23 => return 4;
      when 24 => return 4;
      when 25 => return 5;
      when 26 => return 9;
      when 27 => return 5;
      when 28 => return 4;
      when 29 => return 3;
      when 30 => return 4;
      when 31 => return 2;
      when 32 => return 5;
      when 33 => return 7;
      when 34 => return 4;
      when 35 => return 4;
      when 36 => return 4;
      when 37 => return 4;
      when 38 => return 6;
      when 39 => return 2;
      when 40 => return 7;
      when 41 => return 2;
      when 42 => return 5;
      when 43 => return 4;
      when 44 => return 5;
      when 45 => return 4;
      when 46 => return 12;
      when 47 => return 3;
      when 48 => return 3;
      when 49 => return 3;
      when 50 => return 10;
      when 51 => return 3;
      when 52 => return 3;
      when 53 => return 9;
      when 54 => return 6;
      when 55 => return 4;
      when 56 => return 3;
      when 57 => return 2;
      when 58 => return 2;
      when 59 => return 2;
      when 60 => return 3;
      when 61 => return 2;
      when 62 => return 3;
      when 63 => return 5;
      when 64 => return 4;
      when 65 => return 4;
      when 66 => return 4;
      when 67 => return 4;
      when 68 => return 4;
      when 69 => return 4;
      when 70 => return 3;
      when 71 => return 4;
      when 72 => return 4;
      when 73 => return 4;
      when 74 => return 4;
      when 75 => return 5;
      when 76 => return 5;
      when 77 => return 3;
      when 78 => return 6;
      when 79 => return 4;
      when 80 => return 4;
      when 81 => return 7;
      when 82 => return 4;
      when 83 => return 4;
      when 84 => return 6;
      when 85 => return 5;
      when 86 => return 4;
      when 87 => return 6;
      when 88 => return 3;
      when 89 => return 5;
      when 90 => return 2;
      when 91 => return 5;
      when 92 => return 12;
      when 93 => return 3;
      when 94 => return 12;
      when 95 => return 12;
      when 96 => return 6;
      when 97 => return 3;
      when 98 => return 6;
      when 99 => return 6;
      when 100 => return 5;
      when 101 => return 6;
      when 102 => return 5;
      when 103 => return 6;
      when 104 => return 8;
      when 105 => return 5;
      when 106 => return 4;
      when 107 => return 5;
      when 108 => return 5;
      when 109 => return 6;
      when 110 => return 5;
      when 111 => return 4;
      when 112 => return 5;
      when 113 => return 7;
      when 114 => return 6;
      when others => return 0;
    end case;
  end;
  function kw_char(i, p : natural) return std_logic_vector is
  begin
    case i is
      when 0 =>
        case p is
          when 0 => return x"4E";
          when 1 => return x"45";
          when 2 => return x"57";
          when others => return x"00";
        end case;
      when 1 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"41";
          when 2 => return x"56";
          when 3 => return x"45";
          when others => return x"00";
        end case;
      when 2 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"4F";
          when 2 => return x"41";
          when 3 => return x"44";
          when others => return x"00";
        end case;
      when 3 =>
        case p is
          when 0 => return x"45";
          when 1 => return x"44";
          when 2 => return x"49";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 4 =>
        case p is
          when 0 => return x"44";
          when 1 => return x"45";
          when 2 => return x"4C";
          when 3 => return x"45";
          when 4 => return x"54";
          when 5 => return x"45";
          when others => return x"00";
        end case;
      when 5 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"55";
          when 2 => return x"4E";
          when others => return x"00";
        end case;
      when 6 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"54";
          when 2 => return x"4F";
          when 3 => return x"50";
          when others => return x"00";
        end case;
      when 7 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4F";
          when 2 => return x"4E";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 8 =>
        case p is
          when 0 => return x"4D";
          when 1 => return x"55";
          when 2 => return x"53";
          when 3 => return x"49";
          when 4 => return x"43";
          when others => return x"00";
        end case;
      when 9 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"45";
          when 2 => return x"4D";
          when 3 => return x"50";
          when 4 => return x"4F";
          when others => return x"00";
        end case;
      when 10 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"4F";
          when 2 => return x"4B";
          when 3 => return x"45";
          when others => return x"00";
        end case;
      when 11 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"45";
          when 2 => return x"45";
          when 3 => return x"4B";
          when 4 => return x"28";
          when others => return x"00";
        end case;
      when 12 =>
        case p is
          when 0 => return x"44";
          when 1 => return x"45";
          when 2 => return x"46";
          when others => return x"00";
        end case;
      when 13 =>
        case p is
          when 0 => return x"4F";
          when 1 => return x"50";
          when 2 => return x"45";
          when 3 => return x"4E";
          when others => return x"00";
        end case;
      when 14 =>
        case p is
          when 0 => return x"44";
          when 1 => return x"49";
          when 2 => return x"4D";
          when others => return x"00";
        end case;
      when 15 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"4E";
          when 2 => return x"44";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 16 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"41";
          when 2 => return x"42";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 17 =>
        case p is
          when 0 => return x"41";
          when 1 => return x"55";
          when 2 => return x"54";
          when 3 => return x"4F";
          when others => return x"00";
        end case;
      when 18 =>
        case p is
          when 0 => return x"47";
          when 1 => return x"4F";
          when 2 => return x"53";
          when 3 => return x"55";
          when 4 => return x"42";
          when others => return x"00";
        end case;
      when 19 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"41";
          when 2 => return x"4C";
          when 3 => return x"4C";
          when others => return x"00";
        end case;
      when 20 =>
        case p is
          when 0 => return x"44";
          when 1 => return x"41";
          when 2 => return x"54";
          when 3 => return x"41";
          when others => return x"00";
        end case;
      when 21 =>
        case p is
          when 0 => return x"45";
          when 1 => return x"4C";
          when 2 => return x"53";
          when 3 => return x"45";
          when others => return x"00";
        end case;
      when 22 =>
        case p is
          when 0 => return x"46";
          when 1 => return x"4F";
          when 2 => return x"52";
          when others => return x"00";
        end case;
      when 23 =>
        case p is
          when 0 => return x"47";
          when 1 => return x"4F";
          when 2 => return x"54";
          when 3 => return x"4F";
          when others => return x"00";
        end case;
      when 24 =>
        case p is
          when 0 => return x"48";
          when 1 => return x"4F";
          when 2 => return x"4D";
          when 3 => return x"45";
          when others => return x"00";
        end case;
      when 25 =>
        case p is
          when 0 => return x"49";
          when 1 => return x"4E";
          when 2 => return x"50";
          when 3 => return x"55";
          when 4 => return x"54";
          when others => return x"00";
        end case;
      when 26 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"41";
          when 2 => return x"4E";
          when 3 => return x"44";
          when 4 => return x"4F";
          when 5 => return x"4D";
          when 6 => return x"49";
          when 7 => return x"5A";
          when 8 => return x"45";
          when others => return x"00";
        end case;
      when 27 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4C";
          when 2 => return x"45";
          when 3 => return x"41";
          when 4 => return x"52";
          when others => return x"00";
        end case;
      when 28 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"49";
          when 2 => return x"53";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 29 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"4D";
          when others => return x"00";
        end case;
      when 30 =>
        case p is
          when 0 => return x"4E";
          when 1 => return x"45";
          when 2 => return x"58";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 31 =>
        case p is
          when 0 => return x"4F";
          when 1 => return x"4E";
          when others => return x"00";
        end case;
      when 32 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"52";
          when 2 => return x"49";
          when 3 => return x"4E";
          when 4 => return x"54";
          when others => return x"00";
        end case;
      when 33 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"53";
          when 3 => return x"54";
          when 4 => return x"4F";
          when 5 => return x"52";
          when 6 => return x"45";
          when others => return x"00";
        end case;
      when 34 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"41";
          when 3 => return x"44";
          when others => return x"00";
        end case;
      when 35 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"54";
          when 2 => return x"45";
          when 3 => return x"50";
          when others => return x"00";
        end case;
      when 36 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"48";
          when 2 => return x"45";
          when 3 => return x"4E";
          when others => return x"00";
        end case;
      when 37 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"4C";
          when 2 => return x"4F";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 38 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"54";
          when 3 => return x"55";
          when 4 => return x"52";
          when 5 => return x"4E";
          when others => return x"00";
        end case;
      when 39 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"4F";
          when others => return x"00";
        end case;
      when 40 =>
        case p is
          when 0 => return x"55";
          when 1 => return x"4E";
          when 2 => return x"54";
          when 3 => return x"52";
          when 4 => return x"41";
          when 5 => return x"43";
          when 6 => return x"45";
          when others => return x"00";
        end case;
      when 41 =>
        case p is
          when 0 => return x"49";
          when 1 => return x"46";
          when others => return x"00";
        end case;
      when 42 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"52";
          when 2 => return x"41";
          when 3 => return x"43";
          when 4 => return x"45";
          when others => return x"00";
        end case;
      when 43 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4F";
          when 2 => return x"50";
          when 3 => return x"59";
          when others => return x"00";
        end case;
      when 44 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"4E";
          when 3 => return x"55";
          when 4 => return x"4D";
          when others => return x"00";
        end case;
      when 45 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"4C";
          when 2 => return x"41";
          when 3 => return x"59";
          when others => return x"00";
        end case;
      when 46 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"53";
          when 3 => return x"45";
          when 4 => return x"52";
          when 5 => return x"56";
          when 6 => return x"45";
          when 7 => return x"44";
          when 8 => return x"2D";
          when 9 => return x"31";
          when 10 => return x"37";
          when 11 => return x"34";
          when others => return x"00";
        end case;
      when 47 =>
        case p is
          when 0 => return x"46";
          when 1 => return x"52";
          when 2 => return x"45";
          when others => return x"00";
        end case;
      when 48 =>
        case p is
          when 0 => return x"42";
          when 1 => return x"59";
          when 2 => return x"45";
          when others => return x"00";
        end case;
      when 49 =>
        case p is
          when 0 => return x"45";
          when 1 => return x"4E";
          when 2 => return x"44";
          when others => return x"00";
        end case;
      when 50 =>
        case p is
          when 0 => return x"4F";
          when 1 => return x"50";
          when 2 => return x"54";
          when 3 => return x"49";
          when 4 => return x"4F";
          when 5 => return x"4E";
          when 6 => return x"42";
          when 7 => return x"41";
          when 8 => return x"53";
          when 9 => return x"45";
          when others => return x"00";
        end case;
      when 51 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"45";
          when 2 => return x"54";
          when others => return x"00";
        end case;
      when 52 =>
        case p is
          when 0 => return x"4F";
          when 1 => return x"55";
          when 2 => return x"54";
          when others => return x"00";
        end case;
      when 53 =>
        case p is
          when 0 => return x"4F";
          when 1 => return x"4E";
          when 2 => return x"45";
          when 3 => return x"52";
          when 4 => return x"52";
          when 5 => return x"47";
          when 6 => return x"4F";
          when 7 => return x"54";
          when 8 => return x"4F";
          when others => return x"00";
        end case;
      when 54 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"53";
          when 3 => return x"55";
          when 4 => return x"4D";
          when 5 => return x"45";
          when others => return x"00";
        end case;
      when 55 =>
        case p is
          when 0 => return x"57";
          when 1 => return x"41";
          when 2 => return x"49";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 56 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"43";
          when others => return x"00";
        end case;
      when 57 =>
        case p is
          when 0 => return x"3E";
          when 1 => return x"3D";
          when others => return x"00";
        end case;
      when 58 =>
        case p is
          when 0 => return x"3C";
          when 1 => return x"3D";
          when others => return x"00";
        end case;
      when 59 =>
        case p is
          when 0 => return x"3C";
          when 1 => return x"3E";
          when others => return x"00";
        end case;
      when 60 =>
        case p is
          when 0 => return x"41";
          when 1 => return x"4E";
          when 2 => return x"44";
          when others => return x"00";
        end case;
      when 61 =>
        case p is
          when 0 => return x"4F";
          when 1 => return x"52";
          when others => return x"00";
        end case;
      when 62 =>
        case p is
          when 0 => return x"4E";
          when 1 => return x"4F";
          when 2 => return x"54";
          when others => return x"00";
        end case;
      when 63 =>
        case p is
          when 0 => return x"48";
          when 1 => return x"45";
          when 2 => return x"58";
          when 3 => return x"24";
          when 4 => return x"28";
          when others => return x"00";
        end case;
      when 64 =>
        case p is
          when 0 => return x"41";
          when 1 => return x"42";
          when 2 => return x"53";
          when 3 => return x"7B";
          when others => return x"00";
        end case;
      when 65 =>
        case p is
          when 0 => return x"41";
          when 1 => return x"54";
          when 2 => return x"4E";
          when 3 => return x"7B";
          when others => return x"00";
        end case;
      when 66 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4F";
          when 2 => return x"53";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 67 =>
        case p is
          when 0 => return x"45";
          when 1 => return x"58";
          when 2 => return x"50";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 68 =>
        case p is
          when 0 => return x"49";
          when 1 => return x"4E";
          when 2 => return x"54";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 69 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"4F";
          when 2 => return x"47";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 70 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"4E";
          when 2 => return x"28";
          when others => return x"00";
        end case;
      when 71 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"47";
          when 2 => return x"4E";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 72 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"49";
          when 2 => return x"4E";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 73 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"51";
          when 2 => return x"52";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 74 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"41";
          when 2 => return x"4E";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 75 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"54";
          when 2 => return x"52";
          when 3 => return x"24";
          when 4 => return x"28";
          when others => return x"00";
        end case;
      when 76 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"48";
          when 2 => return x"52";
          when 3 => return x"24";
          when 4 => return x"28";
          when others => return x"00";
        end case;
      when 77 =>
        case p is
          when 0 => return x"49";
          when 1 => return x"4E";
          when 2 => return x"28";
          when others => return x"00";
        end case;
      when 78 =>
        case p is
          when 0 => return x"4A";
          when 1 => return x"4F";
          when 2 => return x"59";
          when 3 => return x"53";
          when 4 => return x"54";
          when 5 => return x"28";
          when others => return x"00";
        end case;
      when 79 =>
        case p is
          when 0 => return x"45";
          when 1 => return x"4F";
          when 2 => return x"46";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 80 =>
        case p is
          when 0 => return x"53";
          when 1 => return x"50";
          when 2 => return x"43";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 81 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"49";
          when 2 => return x"47";
          when 3 => return x"48";
          when 4 => return x"54";
          when 5 => return x"24";
          when 6 => return x"28";
          when others => return x"00";
        end case;
      when 82 =>
        case p is
          when 0 => return x"41";
          when 1 => return x"53";
          when 2 => return x"43";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 83 =>
        case p is
          when 0 => return x"56";
          when 1 => return x"41";
          when 2 => return x"4C";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 84 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"45";
          when 2 => return x"46";
          when 3 => return x"54";
          when 4 => return x"24";
          when 5 => return x"28";
          when others => return x"00";
        end case;
      when 85 =>
        case p is
          when 0 => return x"4D";
          when 1 => return x"49";
          when 2 => return x"44";
          when 3 => return x"24";
          when 4 => return x"28";
          when others => return x"00";
        end case;
      when 86 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"45";
          when 2 => return x"4E";
          when 3 => return x"28";
          when others => return x"00";
        end case;
      when 87 =>
        case p is
          when 0 => return x"49";
          when 1 => return x"4E";
          when 2 => return x"4B";
          when 3 => return x"45";
          when 4 => return x"59";
          when 5 => return x"24";
          when others => return x"00";
        end case;
      when 88 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"4F";
          when 2 => return x"53";
          when others => return x"00";
        end case;
      when 89 =>
        case p is
          when 0 => return x"42";
          when 1 => return x"4C";
          when 2 => return x"4F";
          when 3 => return x"41";
          when 4 => return x"44";
          when others => return x"00";
        end case;
      when 90 =>
        case p is
          when 0 => return x"46";
          when 1 => return x"4E";
          when others => return x"00";
        end case;
      when 91 =>
        case p is
          when 0 => return x"42";
          when 1 => return x"53";
          when 2 => return x"41";
          when 3 => return x"56";
          when 4 => return x"45";
          when others => return x"00";
        end case;
      when 92 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"53";
          when 3 => return x"45";
          when 4 => return x"52";
          when 5 => return x"56";
          when 6 => return x"45";
          when 7 => return x"44";
          when 8 => return x"2D";
          when 9 => return x"32";
          when 10 => return x"32";
          when 11 => return x"30";
          when others => return x"00";
        end case;
      when 93 =>
        case p is
          when 0 => return x"44";
          when 1 => return x"45";
          when 2 => return x"4C";
          when others => return x"00";
        end case;
      when 94 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"53";
          when 3 => return x"45";
          when 4 => return x"52";
          when 5 => return x"56";
          when 6 => return x"45";
          when 7 => return x"44";
          when 8 => return x"2D";
          when 9 => return x"32";
          when 10 => return x"32";
          when 11 => return x"32";
          when others => return x"00";
        end case;
      when 95 =>
        case p is
          when 0 => return x"52";
          when 1 => return x"45";
          when 2 => return x"53";
          when 3 => return x"45";
          when 4 => return x"52";
          when 5 => return x"56";
          when 6 => return x"45";
          when 7 => return x"44";
          when 8 => return x"2D";
          when 9 => return x"32";
          when 10 => return x"32";
          when 11 => return x"33";
          when others => return x"00";
        end case;
      when 96 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"58";
          when 2 => return x"54";
          when 3 => return x"4D";
          when 4 => return x"41";
          when 5 => return x"50";
          when others => return x"00";
        end case;
      when 97 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4C";
          when 2 => return x"53";
          when others => return x"00";
        end case;
      when 98 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"49";
          when 2 => return x"4E";
          when 3 => return x"50";
          when 4 => return x"55";
          when 5 => return x"54";
          when others => return x"00";
        end case;
      when 99 =>
        case p is
          when 0 => return x"4C";
          when 1 => return x"4F";
          when 2 => return x"43";
          when 3 => return x"41";
          when 4 => return x"54";
          when 5 => return x"45";
          when others => return x"00";
        end case;
      when 100 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4C";
          when 2 => return x"4F";
          when 3 => return x"41";
          when 4 => return x"44";
          when others => return x"00";
        end case;
      when 101 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"42";
          when 2 => return x"4C";
          when 3 => return x"4F";
          when 4 => return x"41";
          when 5 => return x"44";
          when others => return x"00";
        end case;
      when 102 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"53";
          when 2 => return x"41";
          when 3 => return x"56";
          when 4 => return x"45";
          when others => return x"00";
        end case;
      when 103 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"42";
          when 2 => return x"53";
          when 3 => return x"41";
          when 4 => return x"56";
          when 5 => return x"45";
          when others => return x"00";
        end case;
      when 104 =>
        case p is
          when 0 => return x"54";
          when 1 => return x"45";
          when 2 => return x"52";
          when 3 => return x"4D";
          when 4 => return x"49";
          when 5 => return x"4E";
          when 6 => return x"41";
          when 7 => return x"4C";
          when others => return x"00";
        end case;
      when 105 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"4F";
          when 2 => return x"4C";
          when 3 => return x"4F";
          when 4 => return x"52";
          when others => return x"00";
        end case;
      when 106 =>
        case p is
          when 0 => return x"45";
          when 1 => return x"58";
          when 2 => return x"49";
          when 3 => return x"54";
          when others => return x"00";
        end case;
      when 107 =>
        case p is
          when 0 => return x"56";
          when 1 => return x"50";
          when 2 => return x"4F";
          when 3 => return x"4B";
          when 4 => return x"45";
          when others => return x"00";
        end case;
      when 108 =>
        case p is
          when 0 => return x"56";
          when 1 => return x"50";
          when 2 => return x"45";
          when 3 => return x"45";
          when 4 => return x"4B";
          when others => return x"00";
        end case;
      when 109 =>
        case p is
          when 0 => return x"43";
          when 1 => return x"49";
          when 2 => return x"52";
          when 3 => return x"43";
          when 4 => return x"4C";
          when 5 => return x"45";
          when others => return x"00";
        end case;
      when 110 =>
        case p is
          when 0 => return x"50";
          when 1 => return x"41";
          when 2 => return x"49";
          when 3 => return x"4E";
          when 4 => return x"54";
          when others => return x"00";
        end case;
      when 111 =>
        case p is
          when 0 => return x"42";
          when 1 => return x"45";
          when 2 => return x"45";
          when 3 => return x"50";
          when others => return x"00";
        end case;
      when 112 =>
        case p is
          when 0 => return x"58";
          when 1 => return x"43";
          when 2 => return x"41";
          when 3 => return x"4C";
          when 4 => return x"4C";
          when others => return x"00";
        end case;
      when 113 =>
        case p is
          when 0 => return x"49";
          when 1 => return x"4E";
          when 2 => return x"56";
          when 3 => return x"45";
          when 4 => return x"52";
          when 5 => return x"53";
          when 6 => return x"45";
          when others => return x"00";
        end case;
      when 114 =>
        case p is
          when 0 => return x"4E";
          when 1 => return x"4F";
          when 2 => return x"52";
          when 3 => return x"4D";
          when 4 => return x"41";
          when 5 => return x"4C";
          when others => return x"00";
        end case;
      when others => return x"00";
    end case;
  end;
  function upper(v : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    if unsigned(v)>=97 and unsigned(v)<=122 then return std_logic_vector(unsigned(v)-32); end if;
    return v;
  end;
  function bcd_lo(n:natural) return std_logic_vector is
  begin return std_logic_vector(to_unsigned(((n/10) mod 10)*16+(n mod 10),8)); end;
  function bcd_hi(n:natural) return std_logic_vector is
  begin return std_logic_vector(to_unsigned(((n/1000) mod 10)*16+((n/100) mod 10),8)); end;
begin
  file_start <= '1' when state=START_READ else '0';
  file_cluster<=cluster_q; file_size<=size_q;
  mem_wr<=wr_q; mem_addr<=addr_q; mem_data<=data_q;
  busy<='1' when state/=IDLE and state/=COMPLETE and state/=FAILED else '0';
  done<=done_q; error<=error_q; status<=status_q;

  process(clk)
  begin
    if rising_edge(clk) then
      if file_read_wr='1' and (state=WAIT_READ or state=START_READ) and unsigned(file_read_addr)<16384 then
        src(to_integer(unsigned(file_read_addr(13 downto 0))))<=file_read_data;
      end if;
      src_q <= src(to_integer(src_rd_addr(13 downto 0)));
      src_q_addr <= src_rd_addr;
    end if;
  end process;

  process(clk)
    procedure put(a:unsigned(15 downto 0); d:std_logic_vector(7 downto 0)) is
    begin wr_q<='1'; addr_q<=std_logic_vector(a); data_q<=d; end;
    variable ch : std_logic_vector(7 downto 0);
    variable next_dst : unsigned(16 downto 0);
  begin
    if rising_edge(clk) then
      wr_q<='0'; done_q<='0';
      if reset='1' then
        state<=IDLE; error_q<='0'; status_q<=x"0"; quoted<='0'; rem_mode<='0';
      else
        case state is
          when IDLE =>
            if start='1' then
              error_q<='0'; status_q<=x"0";
              if selected_valid='0' then error_q<='1'; status_q<=x"1";
              elsif unsigned(selected_size)=0 or unsigned(selected_size)>16384 then error_q<='1'; status_q<=x"2";
              else
                cluster_q<=selected_cluster; size_q<=selected_size;
                src_size<=resize(unsigned(selected_size),15); state<=START_READ;
              end if;
            end if;
          when START_READ => state<=WAIT_READ;
          when WAIT_READ =>
            if file_read_error='1' then error_q<='1';status_q<=x"4";state<=FAILED;
            elsif file_read_done='1' and file_read_busy='0' then
              src_pos<=(others=>'0'); last_line<=0;
              if ram_config="00" then dst<=x"7500"; mem_limit<=to_unsigned(16#7800#,17);
              elsif ram_config="01" then dst<=x"8004"; mem_limit<=to_unsigned(16#C000#,17);
              else dst<=x"8004"; mem_limit<=to_unsigned(16#10000#,17); end if;
              state<=SEEK_LINE;
            end if;
          when SEEK_LINE =>
            if src_pos>=src_size then state<=FINAL_LO;
            elsif src_q_addr/=src_pos then src_rd_addr<=src_pos;
            else
              ch:=src_q;
              if ch=x"0D" or ch=x"0A" or ch=x"20" or ch=x"09" then src_pos<=src_pos+1;
              else scan_pos<=src_pos; last_nonspace<=src_pos; state<=FIND_EOL; end if;
            end if;
          when FIND_EOL =>
            if scan_pos>=src_size then
              line_end<=last_nonspace+1; line_next<=scan_pos; line_num<=0; digit_count<=0; state<=PARSE_NUM;
            elsif src_q_addr/=scan_pos then src_rd_addr<=scan_pos;
            elsif src_q=x"0D" or src_q=x"0A" then
              line_end<=last_nonspace+1; line_next<=scan_pos; line_num<=0; digit_count<=0; state<=PARSE_NUM;
            else
              if src_q/=x"20" and src_q/=x"09" then last_nonspace<=scan_pos; end if;
              scan_pos<=scan_pos+1;
            end if;
          when PARSE_NUM =>
            if src_q_addr/=src_pos then src_rd_addr<=src_pos;
            else
            ch:=src_q;
            if ch>=x"30" and ch<=x"39" and digit_count<4 then
              line_num<=line_num*10+(to_integer(unsigned(ch))-48); digit_count<=digit_count+1; src_pos<=src_pos+1;
            elsif (ch=x"20" or ch=x"09") and digit_count>0 and line_num>last_line then
              line_start<=dst; last_line<=line_num; src_pos<=src_pos+1; quoted<='0'; rem_mode<='0'; state<=EMIT_PTR_LO;
            else error_q<='1';status_q<=x"5";state<=FAILED; end if;
            end if;
          when EMIT_PTR_LO => put(dst,x"00");dst<=dst+1;state<=EMIT_PTR_HI;
          when EMIT_PTR_HI => put(dst,x"00");dst<=dst+1;state<=EMIT_BCD_LO;
          when EMIT_BCD_LO => put(dst,bcd_lo(line_num));dst<=dst+1;state<=EMIT_BCD_HI;
          when EMIT_BCD_HI => put(dst,bcd_hi(line_num));dst<=dst+1;state<=TOKEN_PREP;
          when TOKEN_PREP =>
            if src_pos>=line_end then state<=EMIT_EOL;
            elsif quoted='1' or rem_mode='1' then state<=EMIT_CHAR;
            else scan_pos<=src_pos; state<=TOKEN_SKIP; end if;
          when TOKEN_SKIP =>
            if scan_pos>=line_end then token_idx<=0;match_pos<=0;state<=TOKEN_SCAN;
            elsif src_q_addr/=scan_pos then src_rd_addr<=scan_pos;
            elsif src_q=x"20" or src_q=x"09" then scan_pos<=scan_pos+1;
            else token_idx<=0; match_pos<=0; state<=TOKEN_SCAN; end if;
          when TOKEN_SCAN =>
            if token_idx=115 then state<=EMIT_CHAR;
            else match_pos<=0; state<=TOKEN_COMPARE; end if;
          when TOKEN_COMPARE =>
            if scan_pos+match_pos>=line_end then
              token_idx<=token_idx+1; state<=TOKEN_SCAN;
            elsif src_q_addr/=scan_pos+match_pos then src_rd_addr<=scan_pos+match_pos;
            elsif upper(src_q)/=kw_char(token_idx,match_pos) then
              token_idx<=token_idx+1; state<=TOKEN_SCAN;
            elsif match_pos+1=kw_len(token_idx) then state<=EMIT_TOKEN;
            else match_pos<=match_pos+1; end if;
          when EMIT_TOKEN =>
            next_dst:=resize(dst,17)+1;
            if next_dst>=mem_limit then error_q<='1';status_q<=x"6";state<=FAILED;
            else
              put(dst,std_logic_vector(to_unsigned(128+token_idx,8)));dst<=dst+1;
              src_pos<=scan_pos+kw_len(token_idx);
              if token_idx=29 then rem_mode<='1'; state<=TOKEN_PREP;
              else state<=SKIP_AFTER_TOKEN; end if;
            end if;
          when SKIP_AFTER_TOKEN =>
            if src_pos>=line_end then state<=TOKEN_PREP;
            elsif src_q_addr/=src_pos then src_rd_addr<=src_pos;
            elsif src_q=x"20" or src_q=x"09" then src_pos<=src_pos+1;
            else state<=TOKEN_PREP; end if;
          when EMIT_CHAR =>
            next_dst:=resize(dst,17)+1;
            if next_dst>=mem_limit then error_q<='1';status_q<=x"6";state<=FAILED;
            elsif src_q_addr/=src_pos then src_rd_addr<=src_pos;
            else
              ch:=src_q; put(dst,ch);dst<=dst+1;src_pos<=src_pos+1;
              if ch=x"22" and rem_mode='0' then quoted<=not quoted; end if;
              state<=TOKEN_PREP;
            end if;
          when EMIT_EOL =>
            next_dst:=resize(dst,17)+3;
            if next_dst>=mem_limit then error_q<='1';status_q<=x"6";state<=FAILED;
            else put(dst,x"00");dst<=dst+1;state<=PATCH_LO; end if;
          when PATCH_LO => put(line_start,std_logic_vector(dst(7 downto 0)));state<=PATCH_HI;
          when PATCH_HI =>
            put(line_start+1,std_logic_vector(dst(15 downto 8)));
            src_pos<=line_next;
            if line_next<src_size then src_pos<=line_next+1; end if;
            state<=SEEK_LINE;
          when FINAL_LO =>
            terminal_addr<=dst; put(dst,x"00");dst<=dst+1;state<=FINAL_HI;
          when FINAL_HI =>
            put(dst,x"00"); vars_addr<=terminal_addr+2; state<=SET_ADDR_LO;
          when SET_ADDR_LO => put(x"71E4",std_logic_vector(terminal_addr(7 downto 0)));state<=SET_ADDR_HI;
          when SET_ADDR_HI => put(x"71E5",std_logic_vector(terminal_addr(15 downto 8)));state<=SET_LINE_LO;
          when SET_LINE_LO => put(x"71E2",bcd_lo(last_line));state<=SET_LINE_HI;
          when SET_LINE_HI => put(x"71E3",bcd_hi(last_line));state<=SET_DIMED_LO;
          when SET_DIMED_LO => put(x"7231",std_logic_vector(vars_addr(7 downto 0)));state<=SET_DIMED_HI;
          when SET_DIMED_HI => put(x"7232",std_logic_vector(vars_addr(15 downto 8)));state<=SET_DIMA_LO;
          when SET_DIMA_LO => put(x"7233",std_logic_vector(vars_addr(7 downto 0)));state<=SET_DIMA_HI;
          when SET_DIMA_HI => put(x"7234",std_logic_vector(vars_addr(15 downto 8)));state<=SET_DTAD_LO;
          when SET_DTAD_LO => put(x"7235",std_logic_vector(vars_addr(7 downto 0)));state<=SET_DTAD_HI;
          when SET_DTAD_HI => put(x"7236",std_logic_vector(vars_addr(15 downto 8)));state<=SET_CLEAR;
          when SET_CLEAR => put(x"7230",x"00");state<=COMPLETE;
          when COMPLETE => done_q<='1';state<=IDLE;
          when FAILED => null;
        end case;
      end if;
    end if;
  end process;
end;



