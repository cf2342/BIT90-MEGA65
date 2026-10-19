library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Streams an ordinary RIFF/WAVE file from FAT32 and turns its PCM samples
-- into the one-bit cassette input seen at BIT90 I/O port FFh.
entity bit90_tape_player is
  generic (
    CLK_HZ : positive := 100000000;
    PULSE_FIFO_DEPTH : positive := 65536;
    PULSE_HIGH_WATER : positive := 49152
  );
  port(
    clk, reset : in std_logic;
    start : in std_logic;
    selected_valid : in std_logic;
    selected_cluster, selected_size : in std_logic_vector(31 downto 0);
    file_read_busy, file_read_done, file_read_error : in std_logic;
    file_read_wr : in std_logic;
    file_read_data : in std_logic_vector(7 downto 0);
    file_start : out std_logic;
    file_cluster, file_size : out std_logic_vector(31 downto 0);
    file_ready : out std_logic;
    tape_read_strobe : in std_logic;
    tape_bit : out std_logic;
    playing_o : out std_logic;
    busy, done, error : out std_logic;
    status : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of bit90_tape_player is
  type state_t is (IDLE, START_READ, HEADER, STREAM, FAILED);
  type fifo_t is array(0 to 4095) of std_logic_vector(15 downto 0);
  signal fifo : fifo_t;
  attribute ram_style : string;
  attribute ram_style of fifo : signal is "block";
  signal state : state_t := IDLE;
  signal cluster_q, size_q : std_logic_vector(31 downto 0) := (others=>'0');
  signal stream_pos : unsigned(31 downto 0) := (others=>'0');
  signal riff_ok, wave_ok, fmt_ok : std_logic := '0';
  signal chunk_id : std_logic_vector(31 downto 0) := (others=>'0');
  signal chunk_size, chunk_left : unsigned(31 downto 0) := (others=>'0');
  signal header_phase : integer range 0 to 7 := 0;
  signal in_chunk : std_logic := '0';
  signal chunk_is_fmt : std_logic := '0';
  signal fmt_pos : integer range 0 to 65535 := 0;
  signal audio_format, channels, bits_per_sample : unsigned(15 downto 0) := (others=>'0');
  signal sample_rate : unsigned(31 downto 0) := to_unsigned(44100,32);
  signal low_byte : std_logic_vector(7 downto 0) := x"00";
  signal have_low : std_logic := '0';
  signal wptr, rptr : unsigned(11 downto 0) := (others=>'0');
  signal fifo_rd_data : std_logic_vector(15 downto 0) := (others=>'0');
  signal fifo_rd_valid : std_logic := '0';
  signal fifo_count : integer range 0 to 4096 := 0;
  signal playing, output_started, mounted, stream_eof : std_logic := '0';
  signal eof_run_flushed : std_logic := '0';
  signal phase_acc : unsigned(31 downto 0) := (others=>'0');
  signal tape_q : std_logic := '1';
  -- Analyse PCM as fast as the SD stream supplies it, then replay clean
  -- nominal 6/9-sample FSK half waves at the recorded sample rate. A deep
  -- descriptor FIFO decouples both rates; without it the replay side catches
  -- the detector and stretches arbitrary half waves whenever the queue empties.
  constant PULSE_PREFILL : natural := 8;
  -- Keep the circular BRAM FIFO away from the ambiguous completely-full
  -- state. The remaining quarter still provides more than a second of FSK
  -- reserve while SD input is paused at FAT/cluster boundaries.
  -- Keep length and level in one 9-bit word.  The registered read below is
  -- deliberate: an asynchronous array read makes Vivado build this deep FIFO
  -- out of thousands of LUT RAMs and misses the 100 MHz timing constraint.
  type pulse_fifo_t is array(0 to PULSE_FIFO_DEPTH-1) of std_logic_vector(8 downto 0);
  signal pulse_fifo : pulse_fifo_t;
  signal pulse_rd_data : std_logic_vector(8 downto 0) := '1' & x"01";
  attribute ram_style of pulse_fifo : signal is "block";
  signal pulse_wptr, pulse_rptr : unsigned(15 downto 0) := (others=>'0');
  signal pulse_count : integer range 0 to PULSE_FIFO_DEPTH := 0;
  signal pulse_remaining : integer range 0 to 255 := 0;
  signal detector_q, shaper_started : std_logic := '0';
  -- Q16 running average, matching the adaptive comparator threshold in the original.
  signal dc_average : signed(32 downto 0) := (others=>'0');
  signal run_samples : integer range 0 to 65535 := 0;
  signal done_q, error_q : std_logic := '0';
  signal status_q : std_logic_vector(3 downto 0) := x"0";
begin
  file_start <= '1' when state=START_READ else '0';
  file_cluster <= cluster_q;
  file_size <= size_q;
-- Never pause the SD SPI transfer in the middle of a 512-byte sector.
  -- At a sector boundary, reserve enough PCM FIFO space for the complete next
  -- sector (256 samples for 16-bit mono, with an additional safety margin).
  file_ready <= '1' when state=HEADER or
                 (state=STREAM and (stream_pos(8 downto 0)/=to_unsigned(0,9) or
                                    fifo_count < 3584)) else '0';
  tape_bit <= tape_q;
  playing_o <= playing;
  busy <= '1' when state/=IDLE and state/=FAILED else '0';
  done <= done_q;
  error <= error_q;
  status <= status_q;

  process(clk)
    variable id_v : std_logic_vector(31 downto 0);
    variable size_v : unsigned(31 downto 0);
    variable sample_v : signed(15 downto 0);
    variable sample_target_v : signed(32 downto 0);
    variable ac_sample_v : signed(16 downto 0);
    variable detector_next_v : std_logic;
    variable push_v, pop_v, pulse_push_v, pulse_pop_v : boolean;
    variable pulse_len_v : integer range 1 to 255;
    variable pulse_level_v : std_logic;
    variable push_data_v : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      done_q <= '0';
      push_v := false;
      pop_v := false;
      pulse_push_v := false;
      pulse_pop_v := false;
      if reset='1' then
        state <= IDLE; cluster_q <= (others=>'0'); size_q <= (others=>'0');
        stream_pos <= (others=>'0'); riff_ok<='0'; wave_ok<='0'; fmt_ok<='0';
        chunk_id <= (others=>'0'); chunk_size <= (others=>'0'); chunk_left <= (others=>'0');
        header_phase<=0; in_chunk<='0'; chunk_is_fmt<='0'; fmt_pos<=0;
        audio_format<=(others=>'0'); channels<=(others=>'0'); bits_per_sample<=(others=>'0');
        sample_rate<=to_unsigned(44100,32); have_low<='0'; wptr<=(others=>'0'); rptr<=(others=>'0');
        fifo_count<=0; fifo_rd_valid<='0'; playing<='0'; output_started<='0'; mounted<='0'; stream_eof<='0'; eof_run_flushed<='0'; phase_acc<=(others=>'0');
        tape_q<='1'; detector_q<='0'; shaper_started<='0'; dc_average<=(others=>'0'); run_samples<=0;
        pulse_wptr<=(others=>'0'); pulse_rptr<=(others=>'0'); pulse_count<=0;
        pulse_remaining<=0; error_q<='0'; status_q<=x"0";
      else
        -- Synchronous read port for block-RAM inference.  pulse_rptr remains
        -- stable for an entire shaped half wave, so the requested word is
        -- available long before the next sample-rate dequeue event.
        pulse_rd_data <= pulse_fifo(to_integer(pulse_rptr));

        if tape_read_strobe='1' and mounted='1' then playing <= '1'; end if;
        if playing='1' and output_started='0' and
           (pulse_count>=PULSE_PREFILL or stream_eof='1') then
          output_started <= '1';
        end if;

        -- PCM analysis is intentionally independent of playback time. The SD
        -- stream is much faster than 44.1 kHz, so the replay FIFO gains a lead
        -- before the ROM starts reading the tape input. Reserve one descriptor
        -- before consuming a sample to make overflow loss impossible.
        if mounted='1' and fifo_count>0 and pulse_count<PULSE_HIGH_WATER-1 then
          fifo_rd_data <= fifo(to_integer(rptr));
          fifo_rd_valid <= '1';
          rptr <= rptr + 1;
          pop_v := true;
        else
          fifo_rd_valid <= '0';
        end if;

        -- Pipeline the sample RAM read before threshold detection and descriptor
        -- generation. This cuts the former rptr-to-pulse-BRAM enable path.
        if fifo_rd_valid='1' then
          sample_v := signed(fifo_rd_data);
          sample_target_v := shift_left(resize(sample_v, sample_target_v'length), 16);
          dc_average <= dc_average + shift_right(sample_target_v - dc_average, 10);
          ac_sample_v := resize(sample_v, ac_sample_v'length) -
                         resize(shift_right(dc_average,16), ac_sample_v'length);
          detector_next_v := detector_q;
          if ac_sample_v > to_signed(2048,ac_sample_v'length) then detector_next_v := '1';
          elsif ac_sample_v < to_signed(-2048,ac_sample_v'length) then detector_next_v := '0';
          end if;
          if detector_next_v/=detector_q then
            if shaper_started='0' and run_samples>=30 then
              shaper_started <= '1';
            elsif shaper_started='1' then
              if run_samples<6 then pulse_len_v:=run_samples;
              elsif run_samples<8 then pulse_len_v:=6;
              elsif run_samples<30 then pulse_len_v:=9;
              else pulse_len_v:=24;
              end if;
              if pulse_len_v<1 then pulse_len_v:=1; end if;
              pulse_level_v:=detector_q;
              pulse_push_v:=true;
              if to_integer(pulse_wptr)=PULSE_FIFO_DEPTH-1 then pulse_wptr<=(others=>'0');
              else pulse_wptr<=pulse_wptr+1; end if;
            end if;
            detector_q<=detector_next_v;
            run_samples<=1;
          elsif run_samples<65535 then
            run_samples<=run_samples+1;
          end if;
        end if;

        -- A WAV commonly ends in a long constant/silent level. Normal pulse
        -- creation happens only at a comparator transition, so explicitly
        -- flush the final level before declaring playback complete.
        if stream_eof='1' and fifo_count=0 and fifo_rd_valid='0' and
           eof_run_flushed='0' and pulse_count<PULSE_HIGH_WATER-1 then
          eof_run_flushed <= '1';
          if shaper_started='1' and run_samples>0 then
            if run_samples<6 then pulse_len_v:=run_samples;
            elsif run_samples<8 then pulse_len_v:=6;
            elsif run_samples<30 then pulse_len_v:=9;
            else pulse_len_v:=24;
            end if;
            if pulse_len_v<1 then pulse_len_v:=1; end if;
            pulse_level_v:=detector_q;
            pulse_push_v:=true;
            if to_integer(pulse_wptr)=PULSE_FIFO_DEPTH-1 then pulse_wptr<=(others=>'0');
            else pulse_wptr<=pulse_wptr+1; end if;
          end if;
          run_samples<=0;
        end if;

        if playing='1' and output_started='1' then
          if phase_acc >= to_unsigned(CLK_HZ,32) - sample_rate then
            phase_acc <= phase_acc + sample_rate - to_unsigned(CLK_HZ,32);
            if pulse_remaining>0 then
              pulse_remaining <= pulse_remaining-1;
            elsif pulse_count>0 then
              tape_q <= pulse_rd_data(8);
              pulse_remaining <= to_integer(unsigned(pulse_rd_data(7 downto 0)))-1;
              if to_integer(pulse_rptr)=PULSE_FIFO_DEPTH-1 then pulse_rptr<=(others=>'0');
              else pulse_rptr<=pulse_rptr+1; end if;
              pulse_pop_v := true;
            elsif stream_eof='0' then
              output_started <= '0';
            end if;
          else
            phase_acc <= phase_acc + sample_rate;
          end if;
        end if;

        case state is
          when IDLE =>
            playing <= '0'; output_started <= '0'; mounted <= '0'; tape_q <= '1';
            if start='1' then
              error_q<='0'; status_q<=x"0";
              if selected_valid='0' then error_q<='1'; status_q<=x"1";
              elsif unsigned(selected_size)<44 then error_q<='1'; status_q<=x"2";
              else
                cluster_q<=selected_cluster; size_q<=selected_size;
                stream_pos<=(others=>'0'); riff_ok<='0'; wave_ok<='0'; fmt_ok<='0';
                header_phase<=0; in_chunk<='0'; have_low<='0';
                wptr<=(others=>'0'); rptr<=(others=>'0'); fifo_count<=0; fifo_rd_valid<='0'; stream_eof<='0'; eof_run_flushed<='0';
                detector_q<='0'; shaper_started<='0'; dc_average<=(others=>'0'); run_samples<=0;
                pulse_wptr<=(others=>'0'); pulse_rptr<=(others=>'0'); pulse_count<=0;
                pulse_remaining<=0; output_started<='0';
                state<=START_READ;
              end if;
            end if;

          when START_READ => state<=HEADER;

          when HEADER | STREAM =>
            if file_read_error='1' then error_q<='1'; status_q<=x"3"; state<=FAILED;
            elsif file_read_wr='1' then
              stream_pos <= stream_pos + 1;
              if stream_pos=0 and file_read_data=x"52" then riff_ok<='1';
              elsif stream_pos=1 and file_read_data/=x"49" then riff_ok<='0';
              elsif stream_pos=2 and file_read_data/=x"46" then riff_ok<='0';
              elsif stream_pos=3 and file_read_data/=x"46" then riff_ok<='0';
              elsif stream_pos=8 and file_read_data=x"57" then wave_ok<='1';
              elsif stream_pos=9 and file_read_data/=x"41" then wave_ok<='0';
              elsif stream_pos=10 and file_read_data/=x"56" then wave_ok<='0';
              elsif stream_pos=11 then
                if file_read_data/=x"45" or riff_ok='0' or wave_ok='0' then
                  error_q<='1'; status_q<=x"4"; state<=FAILED;
                else
                  header_phase<=0;
                end if;
              elsif stream_pos>11 then
                if state=STREAM then
                  if bits_per_sample=to_unsigned(16,16) then
                    if have_low='0' then low_byte<=file_read_data; have_low<='1';
                    else
                      push_data_v := file_read_data & low_byte;
                      wptr<=wptr+1; push_v:=true; have_low<='0';
                    end if;
                  else
                    sample_v := signed(resize(unsigned(file_read_data),16));
                    push_data_v := std_logic_vector(shift_left(sample_v,7) - to_signed(16384,16));
                    wptr<=wptr+1; push_v:=true;
                  end if;
                  if chunk_left/=0 then chunk_left<=chunk_left-1; end if;
                elsif in_chunk='0' then
                  if header_phase<4 then
                    id_v:=chunk_id;
                    id_v((3-header_phase)*8+7 downto (3-header_phase)*8):=file_read_data;
                    chunk_id<=id_v; header_phase<=header_phase+1;
                  else
                    size_v:=chunk_size;
                    size_v((header_phase-4)*8+7 downto (header_phase-4)*8):=unsigned(file_read_data);
                    chunk_size<=size_v;
                    if header_phase=7 then
                      header_phase<=0; in_chunk<='1'; chunk_left<=size_v; fmt_pos<=0;
                      if chunk_id=x"666D7420" then chunk_is_fmt<='1';
                      elsif chunk_id=x"64617461" then
                        if fmt_ok='1' then
                          mounted<='1'; done_q<='1'; state<=STREAM; chunk_left<=size_v;
                        else error_q<='1'; status_q<=x"5"; state<=FAILED; end if;
                      else chunk_is_fmt<='0'; end if;
                    else header_phase<=header_phase+1; end if;
                  end if;
                else
                    if chunk_is_fmt='1' then
                      case fmt_pos is
                        when 0 => audio_format(7 downto 0)<=unsigned(file_read_data);
                        when 1 => audio_format(15 downto 8)<=unsigned(file_read_data);
                        when 2 => channels(7 downto 0)<=unsigned(file_read_data);
                        when 3 => channels(15 downto 8)<=unsigned(file_read_data);
                        when 4 => sample_rate(7 downto 0)<=unsigned(file_read_data);
                        when 5 => sample_rate(15 downto 8)<=unsigned(file_read_data);
                        when 6 => sample_rate(23 downto 16)<=unsigned(file_read_data);
                        when 7 => sample_rate(31 downto 24)<=unsigned(file_read_data);
                        when 14 => bits_per_sample(7 downto 0)<=unsigned(file_read_data);
                        when 15 => bits_per_sample(15 downto 8)<=unsigned(file_read_data);
                        when others => null;
                      end case;
                    end if;
                    fmt_pos<=fmt_pos+1;
                    if chunk_left=1 then
                      in_chunk<='0'; header_phase<=0;
                      if chunk_is_fmt='1' then
                        if audio_format=1 and channels=1 and
                           (bits_per_sample=8 or bits_per_sample=16) and
                           sample_rate>=8000 and sample_rate<=96000 then fmt_ok<='1';
                        else error_q<='1'; status_q<=x"6"; state<=FAILED; end if;
                      end if;
                    end if;
                    if chunk_left/=0 then chunk_left<=chunk_left-1; end if;
                  end if;
                end if;
              end if;
            if file_read_done='1' and file_read_busy='0' then
              if mounted='0' then error_q<='1'; status_q<=x"5"; state<=FAILED;
              elsif eof_run_flushed='1' and fifo_count=0 and fifo_rd_valid='0' and pulse_count=0 and pulse_remaining=0 then state<=IDLE;
              else stream_eof<='1'; end if;
            elsif state=STREAM and stream_eof='1' and fifo_count=0 and
                  fifo_rd_valid='0' and eof_run_flushed='1' and
                  pulse_count=0 and pulse_remaining=0 then
              state<=IDLE;
            end if;

          when FAILED => null;
        end case;

        if push_v then
          fifo(to_integer(wptr)) <= push_data_v;
        end if;

        if push_v and not pop_v then
          if fifo_count<4096 then fifo_count<=fifo_count+1; end if;
        elsif pop_v and not push_v then
          if fifo_count>0 then fifo_count<=fifo_count-1; end if;
        end if;

        if pulse_push_v then
          pulse_fifo(to_integer(pulse_wptr)) <=
            pulse_level_v & std_logic_vector(to_unsigned(pulse_len_v,8));
        end if;
        if pulse_push_v and not pulse_pop_v then
          if pulse_count<PULSE_FIFO_DEPTH then pulse_count<=pulse_count+1; end if;
        elsif pulse_pop_v and not pulse_push_v then
          if pulse_count>0 then pulse_count<=pulse_count-1; end if;
        end if;
      end if;
    end if;
  end process;
end architecture;

