library ieee;
use ieee.std_logic_1164.all;

-- Selects one of the two physical MEGA65 SD-card slots for the shared SPI
-- controller.  R6 prefers the rear micro-SD slot.  R3 starts with the internal
-- tray because its internal card-detect input is not reliable on all R3 boards.
entity bit90_sd_slot_mux is
  generic(
    PREFER_EXTERNAL     : boolean := true;
    INTERNAL_CD_RELIABLE: boolean := true;
    RESET_CYCLES        : positive := 16
  );
  port(
    clk, reset          : in  std_logic;
    controller_init_error : in std_logic;

    internal_cd_n, internal_miso : in std_logic;
    internal_sclk, internal_mosi, internal_cs_n : out std_logic;
    external_cd_n, external_miso : in std_logic;
    external_sclk, external_mosi, external_cs_n : out std_logic;

    controller_cd_n, controller_miso : out std_logic;
    controller_sclk, controller_mosi, controller_cs_n : in std_logic;
    controller_reset : out std_logic;
    external_active  : out std_logic
  );
end entity;

architecture rtl of bit90_sd_slot_mux is
  type mux_state_t is (WAIT_DETECT, RESET_CONTROLLER, ACTIVE);
  signal state : mux_state_t := WAIT_DETECT;
  signal active_external : std_logic := '0';
  signal internal_cd_meta, internal_cd_sync : std_logic := '1';
  signal external_cd_meta, external_cd_sync : std_logic := '1';
  signal wait_count : natural range 0 to 3 := 3;
  signal reset_count : natural range 0 to RESET_CYCLES-1 := RESET_CYCLES-1;
  signal fallback_used : std_logic := '0';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of internal_cd_meta, internal_cd_sync : signal is "TRUE";
  attribute ASYNC_REG of external_cd_meta, external_cd_sync : signal is "TRUE";
begin
  external_active <= active_external;
  controller_reset <= '1' when state/=ACTIVE else '0';

  -- An R3 tray card is treated as present while it is selected.  This avoids
  -- depending on the broken tray card-detect connection of original R3 PCBs;
  -- a failed SPI initialisation still allows a fallback to the rear slot.
  controller_cd_n <= '1' when state/=ACTIVE else
                     external_cd_sync when active_external='1' else
                     internal_cd_sync when INTERNAL_CD_RELIABLE else '0';
  controller_miso <= external_miso when active_external='1' else internal_miso;

  internal_sclk <= controller_sclk when state=ACTIVE and active_external='0' else '0';
  internal_mosi <= controller_mosi when state=ACTIVE and active_external='0' else '0';
  internal_cs_n <= controller_cs_n when state=ACTIVE and active_external='0' else '1';
  external_sclk <= controller_sclk when state=ACTIVE and active_external='1' else '0';
  external_mosi <= controller_mosi when state=ACTIVE and active_external='1' else '0';
  external_cs_n <= controller_cs_n when state=ACTIVE and active_external='1' else '1';

  process(clk)
    variable initial_external : std_logic;
  begin
    if rising_edge(clk) then
      internal_cd_meta <= internal_cd_n;
      internal_cd_sync <= internal_cd_meta;
      external_cd_meta <= external_cd_n;
      external_cd_sync <= external_cd_meta;

      if reset='1' then
        state <= WAIT_DETECT;
        wait_count <= 3;
        reset_count <= RESET_CYCLES-1;
        fallback_used <= '0';
        if PREFER_EXTERNAL then active_external <= '1';
        else active_external <= '0';
        end if;
      else
        case state is
          when WAIT_DETECT =>
            if wait_count=0 then
              initial_external := '0';
              if PREFER_EXTERNAL and external_cd_sync='0' then
                initial_external := '1';
              end if;
              active_external <= initial_external;
              fallback_used <= '0';
              reset_count <= RESET_CYCLES-1;
              state <= RESET_CONTROLLER;
            else
              wait_count <= wait_count-1;
            end if;

          when RESET_CONTROLLER =>
            if reset_count=0 then
              state <= ACTIVE;
            else
              reset_count <= reset_count-1;
            end if;

          when ACTIVE =>
            if PREFER_EXTERNAL then
              -- External insertion/removal immediately re-establishes the R6
              -- priority.  Failed initialisation may try the internal card
              -- once without creating an endless slot-to-slot loop.
              if active_external='0' and external_cd_sync='1' then
                -- Removing a failed external card arms it for a later retry.
                fallback_used <= '0';
              elsif active_external='0' and external_cd_sync='0' and
                    fallback_used='0' then
                active_external <= '1';
                fallback_used <= '0';
                reset_count <= RESET_CYCLES-1;
                state <= RESET_CONTROLLER;
              elsif active_external='1' and external_cd_sync='1' then
                active_external <= '0';
                fallback_used <= '0';
                reset_count <= RESET_CYCLES-1;
                state <= RESET_CONTROLLER;
              elsif controller_init_error='1' and fallback_used='0' and
                    active_external='1' and internal_cd_sync='0' then
                active_external <= '0';
                fallback_used <= '1';
                reset_count <= RESET_CYCLES-1;
                state <= RESET_CONTROLLER;
              end if;
            else
              -- R3 always attempts the internal tray first.  Only an actual
              -- initialisation failure, combined with a detected rear card,
              -- moves operation to the external slot.
              if active_external='1' and external_cd_sync='1' then
                active_external <= '0';
                fallback_used <= '0';
                reset_count <= RESET_CYCLES-1;
                state <= RESET_CONTROLLER;
              elsif controller_init_error='1' and fallback_used='0' and
                    active_external='0' and external_cd_sync='0' then
                active_external <= '1';
                fallback_used <= '1';
                reset_count <= RESET_CYCLES-1;
                state <= RESET_CONTROLLER;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
